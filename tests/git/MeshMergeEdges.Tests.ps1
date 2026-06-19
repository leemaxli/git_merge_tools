. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7 follow-up: lock two cross-all (mesh) edge cases the v7.2 review verified manually but left untested.
function Test-IsAncestorSb { param($sb, $anc, $desc); return (Invoke-SandboxGit $sb.Repo @('merge-base', '--is-ancestor', $anc, $desc)).ExitCode -eq 0 }

# Edge 1: the CURRENT branch itself is dirty. Mesh has no essential branch, so current is skipped
# (unsafe state, skip-and-proceed) and the remaining safe branches still converge; current is untouched.
Test-Case 'gitmerge cross-all: a dirty CURRENT branch is skipped; the other branches still converge' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $tWork = New-SandboxCommit -Sandbox $sb -FileName 't.txt' -Content "T`n" -Message 'main work'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null
        $aWork = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A work'
        New-SandboxBranch -Sandbox $sb -Name 'branch-c' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-c') | Out-Null
        $cWork = New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "C`n" -Message 'C work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty`n" -Encoding utf8   # dirty the CURRENT (main) worktree

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-True $ok 'cross-all should succeed by skipping the dirty current branch'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'the dirty current branch must be untouched'
        Assert-Equal (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a') (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-c') -Message 'the safe branches converge to one union'
        Assert-True (Test-IsAncestorSb $sb $aWork 'refs/heads/branch-a') 'union has branch-a work'
        Assert-True (Test-IsAncestorSb $sb $cWork 'refs/heads/branch-a') 'union has branch-c work'
        Assert-False (Test-IsAncestorSb $sb $tWork 'refs/heads/branch-a') 'union must NOT contain the skipped current branch work'
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
