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

# v7.5.0: Uncommitted changes on the checked-out worktree are NOT a pre-block.
# git merge --ff-only is the data-safety arbiter:
#   (i) NON-OVERLAPPING dirty change -> FF succeeds; the dirty edit is preserved.
#   (ii) OVERLAPPING dirty change    -> FF refuses (exit non-zero); nothing is changed.

Test-Case 'gitmerge succeeds when main has NON-OVERLAPPING dirty change; dirty edit preserved' {
    # main is dirty on f.txt; feature/x adds g.txt (no overlap). FF succeeds; f.txt edit preserved.
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base')
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "ahead`n" -Message 'ahead')
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        # Dirty main on f.txt -- feature/x never touches f.txt, so the FF is non-overlapping
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty-nonoverlap`n" -Encoding utf8

        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/x' -Sandbox $sb
        Assert-True $ok 'gitmerge must SUCCEED when dirty change is non-overlapping with the FF'
        # main must have moved (FF succeeded)
        Assert-True ((Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -ne $mainBefore) 'main must advance (FF succeeded)'
        # uncommitted edit on f.txt must be preserved
        $content = Get-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Raw
        Assert-True ($content -match 'dirty-nonoverlap') 'uncommitted edit on f.txt must be preserved after non-overlapping FF'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge refuses when main has OVERLAPPING dirty change; nothing changed (data protected)' {
    # main is dirty on f.txt; feature/x also changes f.txt -> FF would overwrite the uncommitted edit.
    # git refuses; main ref unchanged; dirty edit preserved.
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base')
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "feature-change`n" -Message 'feature edits f')
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        # Dirty main on the SAME f.txt that feature/x changed (overlapping)
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty-overlap`n" -Encoding utf8

        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $featBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/x'
        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/x' -Sandbox $sb
        Assert-False $ok 'gitmerge must refuse when dirty change is overlapping with the FF (data protection)'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main must be unchanged when FF is refused'
        Assert-Equal $featBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/x') -Message 'feature/x must be unchanged'
        # uncommitted dirty edit must still be there
        $content = Get-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Raw
        Assert-True ($content -match 'dirty-overlap') 'uncommitted dirty edit must be preserved (not overwritten)'
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
