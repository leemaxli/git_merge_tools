. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.5.0: skip-and-proceed semantics for the v7.1 star engine.
# Uncommitted changes alone do NOT cause skip/abort. Only UNTOUCHABLE states do:
#   - locked / prunable / unavailable worktree
#   - in-progress op (merge/rebase/cherry-pick/revert)
# A hub with uncommitted changes that does NOT move is fine; one that must move but is refused by git
# -> abort with commit/stash message. Spokes that must move but git refuses -> skip + WARNING, continue.

Test-Case 'gitmerge all (v7.1 star): in-progress HUB (current branch) aborts; spokes untouched' {
    # Hub worktree mid-merge (MERGE_HEAD present) => abort because it is UNTOUCHABLE, not merely dirty.
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'feature/clean' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/clean') | Out-Null
        $cClean = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "clean work`n" -Message 'clean work'
        # Create a hub branch with an in-progress merge (conflict -> MERGE_HEAD present)
        New-SandboxBranch -Sandbox $sb -Name 'feature/hub' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/hub') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "hub side`n" -Message 'hub edits f')
        New-SandboxBranch -Sandbox $sb -Name 'conflict-src' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'conflict-src') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "conflict side`n" -Message 'conflict edits f')
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/hub') | Out-Null
        Invoke-SandboxGit $sb.Repo @('merge', 'conflict-src') | Out-Null   # leaves MERGE_HEAD (hub is mid-merge)
        $hubBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/hub'
        $cleanBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/clean'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-False $ok 'gitmerge all must abort when the HUB (current) worktree has an in-progress merge'
        Assert-Equal $hubBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/hub') -Message 'in-progress hub branch must be untouched'
        Assert-Equal $cleanBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/clean') -Message 'clean spoke must also be untouched (aborted)'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge all: dirty (merely uncommitted) HUB that MUST move aborts with commit/stash message' {
    # Hub has a NEW committed commit (spokes are ancestors) but also OVERLAPPING uncommitted changes.
    # git merge --ff-only refuses; hub is essential -> abort (not skip).
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'spoke' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'spoke') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'spoke.txt' -Content "spoke`n" -Message 'spoke work')
        # Hub = main (current): has spoke work + a committed new file
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'spoke.txt' -Content "spoke`n" -Message 'absorb spoke')
        [void](New-SandboxCommit -Sandbox $sb -FileName 'hub.txt' -Content "hub`n" -Message 'hub work')
        # The union will include hub.txt; dirty the hub with an OVERLAPPING change on spoke.txt
        # Actually the hub's union must NOT move (hub is already the union) to get the abort path.
        # To test the "hub must move but FF refused" path: spoke has unique work, hub is at base.
        # Reset:
        Remove-GitSandbox $sb
        $sb = New-GitSandbox
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'spoke' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'spoke') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'spoke.txt' -Content "spoke content`n" -Message 'spoke work')
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null   # main = base (behind spoke)
        # Dirty main on spoke.txt (overlapping with spoke's committed change)
        Set-Content -LiteralPath (Join-Path $sb.Repo 'spoke.txt') -Value "hub wip`n" -Encoding utf8
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $spokeBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/spoke'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-False $ok 'gitmerge all must abort when the hub has overlapping uncommitted changes that block the FF'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'hub unchanged when FF refused'
        Assert-Equal $spokeBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/spoke') -Message 'spoke unchanged on hub abort'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge all still ABORTS when MAIN is in-progress (mid-merge) as HUB' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "ahead`n" -Message 'ahead'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null                          # current = main
        # Cause a mid-merge on main
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "main side`n" -Message 'main edits f')
        New-SandboxBranch -Sandbox $sb -Name 'conflict-src' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'conflict-src') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "conflict side`n" -Message 'conflict edits f')
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        Invoke-SandboxGit $sb.Repo @('merge', 'conflict-src') | Out-Null   # leaves MERGE_HEAD on main
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-False $ok 'gitmerge must abort when the current (hub) branch has an in-progress operation'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'hub must be unchanged'
    } finally { Remove-GitSandbox $sb }
}
