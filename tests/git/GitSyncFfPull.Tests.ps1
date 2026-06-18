. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v6.x Stage 2: gitsync auto fast-forward-pulls a branch that origin is ahead of WHEN that branch is not
# checked out in any worktree (a CAS update-ref FF -- no working tree to disturb, the safest pull). The
# REMOTE PULL phase is all-or-nothing: it classifies every branch read-only first; if ANY branch can't be
# safely synced at this stage, it changes nothing and prompts (ACTION NEEDED).

function New-NotCheckedOutFfSandbox {
    # main checked out and in sync with origin; feature/x NOT checked out and one commit BEHIND origin.
    $sb = New-GitSandbox
    $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null              # origin/main = c1
    New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $c1
    Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
    $cF = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "feat`n" -Message 'feature work'
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'feature/x') | Out-Null         # origin/feature/x = cF
    Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null                # local feature/x = c1
    Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null                      # feature/x not checked out
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin; FeatTip = $cF; Base = $c1 }
}

function New-MixedFfSandbox {
    # feature/x: origin ahead, NOT checked out (auto-pullable). main: origin ahead, CHECKED OUT (needs manual).
    $sb = New-GitSandbox
    $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null              # origin/main = c1
    New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $c1
    Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
    $null = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "feat`n" -Message 'feature work'
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'feature/x') | Out-Null         # origin/feature/x ahead
    Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null                # local feature/x = c1
    Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
    $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "mainwork`n" -Message 'main work'
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null              # origin/main ahead
    Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null                # local main = c1 (checked out, behind)
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin; Base = $c1 }
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

Test-Case 'gitsync Stage 2 is all-or-nothing: nothing is pulled when another branch needs manual handling' {
    $ctx = New-MixedFfSandbox
    try {
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-False $ok 'a checked-out FF branch (needs manual) must make the whole run ACTION NEEDED'
        Assert-Equal $ctx.Base (Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/feature/x') -Message 'feature/x must be unchanged (all-or-nothing: no partial pull)'
        Assert-Equal $ctx.Base (Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/main') -Message 'main must be unchanged'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}
