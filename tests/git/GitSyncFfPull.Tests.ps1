. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v6.x remote-pull auto fast-forward. The REMOTE PULL phase is all-or-nothing: classify every branch
# read-only first; if ANY branch can't be safely synced at this stage, change nothing and prompt; only
# when the whole set is safe do we pull, then consolidate + push.
#   Stage 2 (v6.1.0): FastForwardable + NOT checked out          -> CAS update-ref
#   Stage 3 (v6.2.0): FastForwardable + checked out + CLEAN tree  -> merge --ff-only in the worktree
#                     FastForwardable + checked out + DIRTY tree  -> still prompts (never touch a dirty tree)

function New-NotCheckedOutFfSandbox {
    # main checked out and in sync with origin; feature/x NOT checked out and one commit BEHIND origin.
    $sb = New-GitSandbox
    $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
    New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $c1
    Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
    $cF = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "feat`n" -Message 'feature work'
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'feature/x') | Out-Null
    Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null
    Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin; FeatTip = $cF; Base = $c1 }
}

function New-AutoPullablePlusDivergedSandbox {
    # feature/x: origin ahead, NOT checked out (auto-pullable). main: origin DIVERGED, checked out (needs manual).
    $sb = New-GitSandbox
    $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
    New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $c1
    Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
    $null = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "feat`n" -Message 'feature work'
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'feature/x') | Out-Null
    Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null
    Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
    $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "origin change`n" -Message 'origin work'
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null              # origin/main diverges
    Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null
    $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "local change`n" -Message 'local work'  # conflicting
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin; Base = $c1 }
}

function New-CheckedOutCleanFfSandbox {
    # main checked out, CLEAN, and one commit BEHIND origin (a fast-forward).
    $sb = New-GitSandbox
    $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
    $c2 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "ahead`n" -Message 'c2'
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null              # origin/main = c2
    Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null                # local main = c1 (clean, behind)
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin; OriginTip = $c2; Base = $c1 }
}

function New-DirtyCheckedOutFfSandbox {
    # main checked out and BEHIND origin (FF), but the worktree is DIRTY (uncommitted tracked change).
    $ctx = New-CheckedOutCleanFfSandbox
    Set-Content -LiteralPath (Join-Path $ctx.Sandbox.Repo 'f.txt') -Value "dirty edit`n" -Encoding utf8   # uncommitted
    return $ctx
}

Test-Case 'gitsync Stage 2: auto FF-pulls a not-checked-out branch origin is ahead of, then syncs' {
    $ctx = New-NotCheckedOutFfSandbox
    try {
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-True $ok 'gitsync should auto-pull the safe FF branch and complete (not ACTION NEEDED)'
        $isAnc = Invoke-SandboxGit $ctx.Sandbox.Repo @('merge-base', '--is-ancestor', $ctx.FeatTip, 'refs/heads/feature/x')
        Assert-Equal 0 $isAnc.ExitCode -Message 'origin commit must be reachable from local feature/x after the auto FF-pull'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitsync is all-or-nothing: nothing is pulled when another branch needs manual handling (diverged)' {
    $ctx = New-AutoPullablePlusDivergedSandbox
    try {
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-False $ok 'a diverged branch (needs manual) must make the whole run ACTION NEEDED'
        Assert-Equal $ctx.Base (Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/feature/x') -Message 'feature/x must be unchanged (all-or-nothing: no partial pull)'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitsync Stage 3: auto FF-pulls a checked-out CLEAN branch via merge --ff-only, then syncs' {
    $ctx = New-CheckedOutCleanFfSandbox
    try {
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-True $ok 'gitsync should auto-pull a checked-out clean FF branch and complete'
        $isAnc = Invoke-SandboxGit $ctx.Sandbox.Repo @('merge-base', '--is-ancestor', $ctx.OriginTip, 'refs/heads/main')
        Assert-Equal 0 $isAnc.ExitCode -Message 'origin commit must be reachable from local main after the auto FF-pull'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitsync Stage 3: a DIRTY checked-out FF branch still prompts (ACTION NEEDED); nothing changed' {
    $ctx = New-DirtyCheckedOutFfSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-Match 'ACTION NEEDED' $out -Message 'a dirty worktree must never be auto-fast-forwarded'
        Assert-Equal $ctx.Base (Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/main') -Message 'local main must be unchanged when its worktree is dirty'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}
