. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

Test-Case 'merge conflict leaves main UNCHANGED, target branch intact, and no temp worktree' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        # Diverge main and feature on the same line to force a conflict.
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "main-change`n" -Message 'main edit')
        New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "feature-change`n" -Message 'feature edit')
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $featBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/x'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/x' -Sandbox $sb
        Assert-False $ok 'gitmerge must report failure on conflict'

        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main moved despite conflict'
        Assert-Equal $featBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/x') -Message 'feature branch moved despite conflict'

        $wts = Invoke-SandboxGit $sb.Repo @('worktree', 'list', '--porcelain')
        Assert-False ((@($wts.Output) -join "`n") -match 'gitmerge-tmp-') 'a temp worktree was left behind'
        $branches = Invoke-SandboxGit $sb.Repo @('for-each-ref', '--format=%(refname:short)', 'refs/heads/')
        Assert-False ((@($branches.Output) -join "`n") -match 'gitmerge-tmp-') 'a temp branch was left behind'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'a dirty checked-out worktree makes gitmerge refuse without changing refs' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base')
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "ahead`n" -Message 'ahead')
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty`n" -Encoding utf8  # uncommitted change on main worktree

        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/x' -Sandbox $sb
        Assert-False $ok 'gitmerge must refuse when an affected worktree is dirty'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main moved despite dirty worktree'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge never deletes or force-moves the user branch (clean fast-forward case)' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base')
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        $featTip = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "work`n" -Message 'feature work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/x' -Sandbox $sb
        Assert-True $ok 'a clean fast-forwardable merge should succeed'
        # main advanced to include the feature work; feature still exists (not deleted).
        Assert-Equal $featTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main should fast-forward to the integrated tip'
        Assert-True ($null -ne (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/x')) 'feature branch must still exist'
    } finally { Remove-GitSandbox $sb }
}
