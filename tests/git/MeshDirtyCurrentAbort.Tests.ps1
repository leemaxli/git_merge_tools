. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# Regression for the "hollow success" bug: running `gitmerge cross-all` from a branch whose worktree is
# DIRTY skipped the current branch (the only one carrying unique work), collapsing the union to the other
# branches' shared tip -> they were "already at union" -> reported SUCCESS / "converged" while NOTHING
# actually merged. The current branch is essential to a cross-all; a dirty current must ABORT (like the
# star's hub and the 2-branch current), NOT be silently skipped. Non-current dirty branches still skip.

Test-Case 'gitmerge cross-all ABORTS when the current branch worktree is dirty (no hollow success)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'   # main @ base
        New-SandboxBranch -Sandbox $sb -Name 'codex' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'deepseek' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'claude' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'claude') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "claude work`n" -Message 'claude work')  # claude ahead (the only unique work)
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "uncommitted`n" -Encoding utf8              # dirty the CURRENT (claude) worktree
        $codexBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/codex'
        $deepBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/deepseek'
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-False $ok 'cross-all must ABORT (not hollow-succeed) when the current branch worktree is dirty'
        # Nothing must have changed (the run aborted before any ref moved).
        Assert-Equal $codexBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/codex') -Message 'codex must be unchanged on abort'
        Assert-Equal $deepBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/deepseek') -Message 'deepseek must be unchanged on abort'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main must be unchanged on abort'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge cross-all dirty-current abort gives an actionable message naming the current branch' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'codex' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'claude' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'claude') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "work`n" -Message 'claude work')
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "uncommitted`n" -Encoding utf8

        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-Match "claude" $out -Message 'the abort message must name the current branch'
        Assert-Match 'commit or stash' $out -Message 'the abort message must tell the user to commit or stash'
        Assert-False ($out -match 'Result\s*:\s*SUCCESS') 'a dirty-current cross-all must NOT report SUCCESS'
    } finally { Remove-GitSandbox $sb }
}
