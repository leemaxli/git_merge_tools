. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7 follow-up + dirty-current bug fix: two cross-all (mesh) edge cases.

# Edge 1: the CURRENT branch is dirty. The current branch is essential to a cross-all (it's the user's
# active context, usually the one carrying the work to converge); a dirty current ABORTS the run --
# consistent with the star hub and the 2-branch current branch. It must NOT be silently skipped while the
# other branches "converge" into a hollow success. The abort takes precedence even when other branches
# have legitimate divergent work to converge (the user must clean the current branch, then re-run).
Test-Case 'gitmerge cross-all: a dirty CURRENT branch ABORTS the run; nothing changes' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A work')
        New-SandboxBranch -Sandbox $sb -Name 'branch-c' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-c') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "C`n" -Message 'C work')
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty`n" -Encoding utf8   # dirty the CURRENT (main) worktree
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $aBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a'
        $cBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-c'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-False $ok 'a dirty current branch must ABORT cross-all (not hollow-succeed by skipping it)'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'current (main) unchanged on abort'
        Assert-Equal $aBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a') -Message 'branch-a unchanged on abort'
        Assert-Equal $cBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-c') -Message 'branch-c unchanged on abort'
    } finally { Remove-GitSandbox $sb }
}

# Edge 2: fewer than 2 safe branches remain (everyone else skipped) -> nothing to converge, success, no change.
Test-Case 'gitmerge cross-all: fewer than two safe branches is a no-op success, nothing changed' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'   # main = current, clean
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A work')
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        $wtA = Join-Path $sb.Root 'wt-a'
        Invoke-SandboxGit $sb.Repo @('worktree', 'add', $wtA, 'branch-a') | Out-Null
        Set-Content -LiteralPath (Join-Path $wtA 'a.txt') -Value "uncommitted`n" -Encoding utf8       # branch-a dirty -> skipped
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $aBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-True $ok 'with only one safe branch, cross-all is a no-op success'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main unchanged'
        Assert-Equal $aBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a') -Message 'the skipped dirty branch unchanged'
        Invoke-SandboxGit $sb.Repo @('worktree', 'remove', '--force', $wtA) | Out-Null
    } finally { Remove-GitSandbox $sb }
}
