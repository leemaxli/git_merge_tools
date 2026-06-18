. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# Regression: gitsync cross-all must use skip-and-proceed for unsafe non-main targets (v7.1 review).
# Before the fix, Get-Mode 'cross-all' returned 'cross-all' (was 'all'), so the
# $mode -ne 'all' guard wrongly triggered the whole-run ACTION NEEDED abort path.

Test-Case 'gitsync cross-all SKIPS a conflicting non-main branch and still syncs a safe sibling (skip-and-proceed)' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $origin = Join-Path $sb.Root 'origin.git'
        Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null

        # feature/safe: origin is ahead (different file) -> fast-forward, should auto-pull.
        New-SandboxBranch -Sandbox $sb -Name 'feature/safe' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/safe') | Out-Null
        $safeTip = New-SandboxCommit -Sandbox $sb -FileName 'safe.txt' -Content "safe`n" -Message 'safe work'
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'feature/safe') | Out-Null
        Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null

        # feature/conflict: diverged with a content conflict, not checked out -> must be SKIPPED (not abort).
        New-SandboxBranch -Sandbox $sb -Name 'feature/conflict' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/conflict') | Out-Null
        $conflictOrigin = New-SandboxCommit -Sandbox $sb -FileName 'shared.txt' -Content "origin side`n" -Message 'conflict origin'
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'feature/conflict') | Out-Null
        Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null
        $conflictLocal = New-SandboxCommit -Sandbox $sb -FileName 'shared.txt' -Content "local side`n" -Message 'conflict local'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        # cross-all must skip-and-proceed: safe sibling syncs, conflicting branch left untouched.
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'cross-all' -Sandbox $sb
        Assert-True $ok 'gitsync cross-all must skip the conflicting branch and still complete (not abort)'
        $anc = Invoke-SandboxGit $sb.Repo @('merge-base', '--is-ancestor', $safeTip, 'refs/heads/feature/safe')
        Assert-Equal 0 $anc.ExitCode -Message 'safe sibling must be pulled and synced'
        Assert-Equal $conflictLocal (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/conflict') -Message 'conflicting branch must be left untouched (skipped)'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitsync cross-all does NOT produce ACTION NEEDED output when only non-main branch conflicts' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $origin = Join-Path $sb.Root 'origin.git'
        Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null

        # feature/bad: diverged with conflict, not checked out.
        New-SandboxBranch -Sandbox $sb -Name 'feature/bad' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/bad') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'shared.txt' -Content "origin side`n" -Message 'bad origin'
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'feature/bad') | Out-Null
        Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null
        $badLocal = New-SandboxCommit -Sandbox $sb -FileName 'shared.txt' -Content "local side`n" -Message 'bad local'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'cross-all' -Sandbox $sb
        Assert-False ([bool]($out -match 'ACTION NEEDED')) 'cross-all must skip-and-proceed, not show ACTION NEEDED for non-main conflict'
        Assert-Match 'Skipping' $out -Message 'cross-all must report the skip'
        Assert-Equal $badLocal (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/bad') -Message 'conflicting branch must be untouched'
    } finally { Remove-GitSandbox $sb }
}
