. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# Defect #7: gitmerge called `git merge --abort` unconditionally on a merge failure. When the merge
# fails BEFORE a merge state is created (e.g. "refusing to merge unrelated histories" -- no MERGE_HEAD),
# the abort itself errors ("no merge to abort") and emits a misleading warning that masks the real cause.
Test-Case 'pre-merge failure (unrelated histories): main unchanged, no spurious merge --abort warning (#7)' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        # orphan branch with unrelated history (no common ancestor with main)
        Invoke-SandboxGit $sb.Repo @('checkout', '--orphan', 'feature/x') | Out-Null
        Invoke-SandboxGit $sb.Repo @('rm', '-rf', '.') | Out-Null
        Set-Content -LiteralPath (Join-Path $sb.Repo 'u.txt') -Value "unrelated`n" -Encoding utf8
        Invoke-SandboxGit $sb.Repo @('add', 'u.txt') | Out-Null
        Invoke-SandboxGit $sb.Repo @('commit', '-m', 'unrelated root') | Out-Null
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'

        $output = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/x' -Sandbox $sb

        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main must be unchanged on a failed merge'
        Assert-False ($output -match 'Cannot abort the temporary merge') -Message 'no spurious merge --abort warning when no merge was in progress'
        # temp worktree/branch must still be cleaned up
        $wts = Invoke-SandboxGit $sb.Repo @('worktree', 'list', '--porcelain')
        Assert-False ((@($wts.Output) -join "`n") -match 'gitmerge-tmp-') -Message 'temp worktree must be cleaned'
    }
    finally { Remove-GitSandbox $sb }
}
