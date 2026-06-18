. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# skip-and-proceed (user decision 2026-06-18): with all/cross-all, a TARGET branch whose worktree can't
# safely participate (dirty / mid-operation) is SKIPPED with a warning -- the rest still consolidate --
# consistent with the #10 sub-branch skip. MAIN unsafe still ABORTS (everything routes through main).

Test-Case 'gitmerge all skips a dirty non-main target and still consolidates the clean one' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'feature/clean' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/clean') | Out-Null
        $cClean = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "clean work`n" -Message 'clean work'  # ahead of main
        New-SandboxBranch -Sandbox $sb -Name 'feature/dirty' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/dirty') | Out-Null                # current = feature/dirty
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty edit`n" -Encoding utf8  # dirty worktree
        # main is NOT checked out (current is feature/dirty); feature/clean is NOT checked out.

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-True $ok 'gitmerge all should skip the dirty branch and consolidate the clean one'
        $anc = Invoke-SandboxGit $sb.Repo @('merge-base', '--is-ancestor', $cClean, 'refs/heads/main')
        Assert-Equal 0 $anc.ExitCode -Message "the clean branch's work must be consolidated into main"
        Assert-Equal $c1 (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/dirty') -Message 'the dirty branch must be untouched (skipped)'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge all still ABORTS when MAIN itself is the dirty worktree (main is the integration point)' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "ahead`n" -Message 'ahead'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null                          # current = main
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty edit`n" -Encoding utf8  # MAIN worktree dirty
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-False $ok 'gitmerge must still abort when MAIN''s own worktree is dirty'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main must be unchanged when its worktree is dirty'
    } finally { Remove-GitSandbox $sb }
}
