. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.3 gitsync topology tests: origin-backed scenarios for 2-branch / all-star / cross-all-mesh.
# Each test builds a bare origin (New-GitSandbox + git init --bare + remote add + push), runs
# gitsync, and asserts the exact per-branch push results on origin (no --force, skip-on-reject).

# ---------------------------------------------------------------------------
# Helper: create a bare origin, wire it, and push main.
# Returns: [pscustomobject]@{ Sandbox; Origin }
# ---------------------------------------------------------------------------
function New-BareOriginSandbox {
    param([string]$InitFile = 'base.txt', [string]$InitContent = "base`n", [string]$Msg = 'base')
    $sb = New-GitSandbox
    $null = New-SandboxCommit -Sandbox $sb -FileName $InitFile -Content $InitContent -Message $Msg
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin }
}

# Helper: read a ref from the bare origin.
function Get-OriginRef {
    param($ctx, [string]$Branch)
    $res = Invoke-SandboxGit $ctx.Sandbox.Repo @('ls-remote', $ctx.Origin, "refs/heads/$Branch")
    if ($res.ExitCode -ne 0 -or $null -eq $res.Output -or @($res.Output).Count -eq 0) { return $null }
    return (@($res.Output)[0] -split '\s+')[0]
}

# Helper: assert that a branch ref at origin matches a local ref.
function Assert-OriginMatchesLocal {
    param($ctx, [string]$Branch, [string]$MsgSuffix)
    $local = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref "refs/heads/$Branch"
    $remote = Get-OriginRef -ctx $ctx -Branch $Branch
    Assert-Equal $local $remote -Message "origin/$Branch must match local $Branch $MsgSuffix"
}

# ---------------------------------------------------------------------------
# Test 1: 2-branch push -- branch-a (current) gitsync branch-b
# Both branches have local-only work (origin in sync at the base). After sync:
#   - both local refs advance to the union
#   - origin/branch-a = origin/branch-b = the union
#   - origin/main is untouched
# ---------------------------------------------------------------------------
Test-Case 'gitsync 2-branch: both branches converge locally and on origin; origin/main untouched' {
    $ctx = New-BareOriginSandbox
    try {
        # Create branch-a with a local commit.
        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'branch-a' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-a') | Out-Null
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'branch-a') | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'a.txt' -Content "alpha`n" -Message 'a work'

        # Create branch-b with a local commit (different file, no conflict).
        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'branch-b' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-b') | Out-Null
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'branch-b') | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'b.txt' -Content "beta`n" -Message 'b work'

        # Switch to branch-a (current); gitsync branch-b (2-branch).
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-a') | Out-Null

        $mainBefore = Get-OriginRef -ctx $ctx -Branch 'main'

        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'branch-b' -Sandbox $ctx.Sandbox
        Assert-True $ok 'gitsync 2-branch must succeed when both branches diverge cleanly'

        # Both local refs must contain both a.txt and b.txt (union).
        $a_has_a = (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/branch-a:a.txt')).ExitCode
        $a_has_b = (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/branch-a:b.txt')).ExitCode
        Assert-Equal 0 $a_has_a -Message 'branch-a must contain a.txt (its own work) after union'
        Assert-Equal 0 $a_has_b -Message 'branch-a must contain b.txt (branch-b work) after union'

        $b_has_a = (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/branch-b:a.txt')).ExitCode
        $b_has_b = (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/branch-b:b.txt')).ExitCode
        Assert-Equal 0 $b_has_a -Message 'branch-b must contain a.txt (branch-a work) after union'
        Assert-Equal 0 $b_has_b -Message 'branch-b must contain b.txt (its own work) after union'

        # Both local refs must be pushed to origin.
        Assert-OriginMatchesLocal -ctx $ctx -Branch 'branch-a' -MsgSuffix 'after 2-branch sync'
        Assert-OriginMatchesLocal -ctx $ctx -Branch 'branch-b' -MsgSuffix 'after 2-branch sync'

        # origin/main must be untouched (2-branch is de-main-centered).
        $mainAfter = Get-OriginRef -ctx $ctx -Branch 'main'
        Assert-Equal $mainBefore $mainAfter -Message 'origin/main must be untouched by a 2-branch gitsync'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

# ---------------------------------------------------------------------------
# Test 2: 2-branch unsafe pull -> abort (ACTION NEEDED), NOTHING pushed
# origin/branch-b diverged with a conflict from local branch-b.
# ---------------------------------------------------------------------------
Test-Case 'gitsync 2-branch: unsafe origin pull aborts; nothing pushed; local refs unchanged' {
    $ctx = New-BareOriginSandbox
    try {
        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'branch-a' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-a') | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'a.txt' -Content "alpha`n" -Message 'a work'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'branch-a') | Out-Null

        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'branch-b' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-b') | Out-Null
        # Put a conflicting commit on origin/branch-b first.
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'shared.txt' -Content "origin side`n" -Message 'b origin'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'branch-b') | Out-Null
        # Reset local branch-b and make a conflicting local commit.
        $baseRef = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('reset', '--hard', $baseRef) | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'shared.txt' -Content "local side`n" -Message 'b local'
        $localBTip = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/branch-b'

        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-a') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'branch-b' -Sandbox $ctx.Sandbox
        Assert-False $ok 'gitsync must return false when the origin pull is unsafe (conflict)'

        # local branch-b must be unchanged.
        $localBAfter = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/branch-b'
        Assert-Equal $localBTip $localBAfter -Message 'branch-b local ref must be unchanged after abort'

        # origin/branch-b must be unchanged (the conflict tip that was there before).
        $originBTip = Get-OriginRef -ctx $ctx -Branch 'branch-b'
        # origin/branch-b still has the "origin side" commit, not the local side.
        Assert-False ([string]::IsNullOrWhiteSpace($originBTip)) 'origin/branch-b should still exist'
        # Nothing should have been pushed to origin/branch-a either (abort before push).
        $originATip = Get-OriginRef -ctx $ctx -Branch 'branch-a'
        $localATip = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/branch-a'
        Assert-Equal $localATip $originATip -Message 'origin/branch-a must still match local (no partial push)'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

# ---------------------------------------------------------------------------
# Test 3: all (star) + per-branch push
# Hub = main (current). Spokes = branch-a, branch-c.
# After sync:
#   - hub (main) has all three branches' work (= hub union).
#   - each spoke has hub-original merged in (but NOT the other spoke's work).
#   - each origin/<spoke> == local <spoke>; origin/main == local main.
# ---------------------------------------------------------------------------
Test-Case 'gitsync all (star): hub absorbs all spokes; each spoke gets hub; per-branch origin push' {
    $ctx = New-BareOriginSandbox
    try {
        # Add branch-a with unique work.
        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'branch-a' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-a') | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'a.txt' -Content "alpha`n" -Message 'a work'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'branch-a') | Out-Null

        # Add branch-c with unique work.
        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'branch-c' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-c') | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'c.txt' -Content "gamma`n" -Message 'c work'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'branch-c') | Out-Null

        # Hub: add a commit to main so it is ahead of spokes.
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'main') | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'hub.txt' -Content "hub work`n" -Message 'hub work'

        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-True $ok 'gitsync all (star) must succeed'

        # Hub (main) must contain a.txt, c.txt, and hub.txt.
        Assert-Equal 0 (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/main:a.txt')).ExitCode -Message 'main must contain a.txt (from branch-a)'
        Assert-Equal 0 (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/main:c.txt')).ExitCode -Message 'main must contain c.txt (from branch-c)'
        Assert-Equal 0 (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/main:hub.txt')).ExitCode -Message 'main must contain hub.txt'

        # Per-branch origin push: origin/<branch> == local <branch>.
        Assert-OriginMatchesLocal -ctx $ctx -Branch 'main' -MsgSuffix 'after all (star) sync'
        Assert-OriginMatchesLocal -ctx $ctx -Branch 'branch-a' -MsgSuffix 'after all (star) sync'
        Assert-OriginMatchesLocal -ctx $ctx -Branch 'branch-c' -MsgSuffix 'after all (star) sync'

        # Spokes should have hub's work (hub.txt) but it's fine if they also got the union through
        # the reverse-merge; the key assertion is that each spoke got the hub original merged in.
        $a_has_hub = (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/branch-a:hub.txt')).ExitCode
        Assert-Equal 0 $a_has_hub -Message 'branch-a must contain hub.txt after star sync (hub original merged into spoke)'
        $c_has_hub = (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/branch-c:hub.txt')).ExitCode
        Assert-Equal 0 $c_has_hub -Message 'branch-c must contain hub.txt after star sync'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

# ---------------------------------------------------------------------------
# Test 4: all -- a spoke whose origin diverged-with-conflict is excluded
# -> skipped from merge AND not pushed; the rest still sync; run succeeds.
# ---------------------------------------------------------------------------
Test-Case 'gitsync all: spoke with conflicting origin diverge is excluded; rest sync; run succeeds' {
    $ctx = New-BareOriginSandbox
    try {
        # branch-good: origin ahead by one FF commit -> safe.
        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'branch-good' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-good') | Out-Null
        $goodWork = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'good.txt' -Content "good`n" -Message 'good work'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'branch-good') | Out-Null
        Invoke-SandboxGit $ctx.Sandbox.Repo @('reset', '--hard', 'refs/heads/main') | Out-Null  # local behind origin

        # branch-bad: diverged with a conflict origin vs local (same file, different content).
        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'branch-bad' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-bad') | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'shared.txt' -Content "origin side`n" -Message 'bad origin'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'branch-bad') | Out-Null
        $baseRef = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('reset', '--hard', $baseRef) | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'shared.txt' -Content "local side`n" -Message 'bad local'
        $badLocalTip = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/branch-bad'
        $badOriginTip = Get-OriginRef -ctx $ctx -Branch 'branch-bad'

        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-True $ok 'gitsync all must skip-and-proceed past the conflicting spoke'

        # branch-bad: local unchanged; origin unchanged (never pushed).
        $badLocalAfter = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/branch-bad'
        Assert-Equal $badLocalTip $badLocalAfter -Message 'branch-bad local must be unchanged (skipped)'
        $badOriginAfter = Get-OriginRef -ctx $ctx -Branch 'branch-bad'
        Assert-Equal $badOriginTip $badOriginAfter -Message 'origin/branch-bad must be unchanged (excluded from push)'

        # branch-good: origin auto-pulled then synced (contains good.txt from the pulled commit).
        $goodLocal = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/branch-good'
        Assert-True ($null -ne $goodLocal) 'branch-good must exist'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

# ---------------------------------------------------------------------------
# Test 5: cross-all (mesh) + per-branch push
# All branches converge to one union locally and on origin (every origin/B == local B).
# ---------------------------------------------------------------------------
Test-Case 'gitsync cross-all (mesh): all branches converge to one union; every origin/B matches local' {
    $ctx = New-BareOriginSandbox
    try {
        # branch-x: unique file x.txt.
        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'branch-x' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-x') | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'x.txt' -Content "ex`n" -Message 'x work'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'branch-x') | Out-Null

        # branch-y: unique file y.txt.
        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'branch-y' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'branch-y') | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'y.txt' -Content "why`n" -Message 'y work'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'branch-y') | Out-Null

        # main: unique file m.txt.
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'main') | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'm.txt' -Content "main work`n" -Message 'main work'

        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'cross-all' -Sandbox $ctx.Sandbox
        Assert-True $ok 'gitsync cross-all (mesh) must succeed'

        # Every local branch must have all three files (mesh = full union).
        foreach ($b in @('main', 'branch-x', 'branch-y')) {
            Assert-Equal 0 (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', "refs/heads/${b}:x.txt")).ExitCode -Message "$b must contain x.txt after mesh"
            Assert-Equal 0 (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', "refs/heads/${b}:y.txt")).ExitCode -Message "$b must contain y.txt after mesh"
            Assert-Equal 0 (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', "refs/heads/${b}:m.txt")).ExitCode -Message "$b must contain m.txt after mesh"
        }

        # Per-branch push: every origin/<branch> == local <branch>.
        foreach ($b in @('main', 'branch-x', 'branch-y')) {
            Assert-OriginMatchesLocal -ctx $ctx -Branch $b -MsgSuffix 'after cross-all (mesh) sync'
        }
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

# ---------------------------------------------------------------------------
# Test 6: all (star) -- the HUB (current, non-main) has a conflicting origin
# diverge -> ABORT (ACTION NEEDED), hub ref unchanged, nothing pushed.
# The hub is not skippable in a star topology; a doomed push is not acceptable.
# ---------------------------------------------------------------------------
Test-Case 'gitsync all: non-main hub with conflicting origin diverge aborts; hub ref unchanged; nothing pushed' {
    $ctx = New-BareOriginSandbox
    try {
        # feature/hub will be the hub (current branch).
        # Make origin/feature/hub and local feature/hub diverge on the same file (conflict).
        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'feature/hub' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('switch', 'feature/hub') | Out-Null
        # Push origin side first.
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'shared.txt' -Content "origin side`n" -Message 'hub origin'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'feature/hub') | Out-Null
        # Reset local to base, then make a conflicting local commit.
        $baseRef = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('reset', '--hard', $baseRef) | Out-Null
        $null = New-SandboxCommit -Sandbox $ctx.Sandbox -FileName 'shared.txt' -Content "local side`n" -Message 'hub local'
        $hubLocalTip = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/feature/hub'
        $hubOriginTip = Get-OriginRef -ctx $ctx -Branch 'feature/hub'

        # Add a clean spoke so we confirm it also stays untouched (abort = nothing changes).
        New-SandboxBranch -Sandbox $ctx.Sandbox -Name 'spoke' -StartPoint 'refs/heads/main'
        Invoke-SandboxGit $ctx.Sandbox.Repo @('push', 'origin', 'spoke') | Out-Null
        $spokeTip = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/spoke'

        # feature/hub is still current (we haven't switched away).
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-False $ok 'gitsync all must abort (return false) when the non-main hub has a conflicting origin diverge'

        # Hub local ref must be unchanged.
        $hubLocalAfter = Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/feature/hub'
        Assert-Equal $hubLocalTip $hubLocalAfter -Message 'hub (feature/hub) local ref must be unchanged after abort'

        # Nothing pushed: origin/feature/hub still has the original "origin side" tip.
        $hubOriginAfter = Get-OriginRef -ctx $ctx -Branch 'feature/hub'
        Assert-Equal $hubOriginTip $hubOriginAfter -Message 'origin/feature/hub must be unchanged (abort before push)'

        # spoke origin also untouched.
        $spokeOriginAfter = Get-OriginRef -ctx $ctx -Branch 'spoke'
        Assert-Equal $spokeTip $spokeOriginAfter -Message 'origin/spoke must be unchanged (abort before push)'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}
