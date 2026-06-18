. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.0: `gitmerge` (empty) and `gitmerge {branch}` merge the CURRENT branch and target X so BOTH converge
# to their union, de-main-centered. main is touched only when it IS current or X.

# current != main != X: on branch-a, `gitmerge branch-b` converges a<->b; main untouched; caller stays on a.
Test-Case 'gitmerge {branch} converges current and X (both diverged-clean); main untouched; caller stays' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'branch-b' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null
        $aTip = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "a`n" -Message 'a work'
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-b') | Out-Null
        $bTip = New-SandboxCommit -Sandbox $sb -FileName 'b.txt' -Content "b`n" -Message 'b work'
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'branch-b' -Sandbox $sb
        Assert-True $ok 'a clean current<->X merge should succeed'

        $aAfter = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a'
        $bAfter = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-b'
        Assert-Equal $aAfter $bAfter -Message 'branch-a and branch-b must converge to the same union commit'
        Assert-Equal 0 (Invoke-SandboxGit $sb.Repo @('merge-base', '--is-ancestor', $aTip, 'refs/heads/branch-a')).ExitCode -Message 'union must descend branch-a old tip'
        Assert-Equal 0 (Invoke-SandboxGit $sb.Repo @('merge-base', '--is-ancestor', $bTip, 'refs/heads/branch-a')).ExitCode -Message 'union must descend branch-b old tip'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main must be UNTOUCHED (de-main-centered)'
        $head = @((Invoke-SandboxGit $sb.Repo @('symbolic-ref', '--short', 'HEAD')).Output)[0]
        Assert-Equal 'branch-a' $head -Message 'caller must stay on branch-a'
        $wts = Invoke-SandboxGit $sb.Repo @('worktree', 'list', '--porcelain')
        Assert-False ((@($wts.Output) -join "`n") -match 'gitmerge-tmp-') 'no temp worktree may leak'
    } finally { Remove-GitSandbox $sb }
}

# X == current -> reminder, nothing changed.
Test-Case 'gitmerge naming the current branch is a no-op reminder' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null
        $aTip = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "a`n" -Message 'a work'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'branch-a' -Sandbox $sb
        Assert-True $ok 'naming the current branch should succeed as a no-op'
        Assert-Equal $aTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a') -Message 'current branch must be unchanged'
    } finally { Remove-GitSandbox $sb }
}

# `gitmerge main` from a feature now merges feature<->main (was "nothing to consolidate").
Test-Case 'gitmerge main from a feature converges feature and main' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $mainTip = New-SandboxCommit -Sandbox $sb -FileName 'm.txt' -Content "m`n" -Message 'main work'
        New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        $featTip = New-SandboxCommit -Sandbox $sb -FileName 'feat.txt' -Content "feat`n" -Message 'feat work'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'main' -Sandbox $sb
        Assert-True $ok 'gitmerge main from a feature should converge feature<->main'
        $featAfter = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/x'
        $mainAfter = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        Assert-Equal $featAfter $mainAfter -Message 'feature/x and main must converge to the same union'
        Assert-Equal 0 (Invoke-SandboxGit $sb.Repo @('merge-base', '--is-ancestor', $mainTip, 'refs/heads/feature/x')).ExitCode -Message 'union descends old main'
        Assert-Equal 0 (Invoke-SandboxGit $sb.Repo @('merge-base', '--is-ancestor', $featTip, 'refs/heads/main')).ExitCode -Message 'union descends old feature tip'
    } finally { Remove-GitSandbox $sb }
}

# Conflict: nothing changes, no temp leak (returns false). current != main != X.
Test-Case 'gitmerge {branch} conflict leaves both branches unchanged and no temp worktree' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'branch-b' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null
        $aTip = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "a-change`n" -Message 'a edit'
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-b') | Out-Null
        $bTip = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "b-change`n" -Message 'b edit'
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'branch-b' -Sandbox $sb
        Assert-False $ok 'gitmerge must report failure on conflict'
        Assert-Equal $aTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a') -Message 'branch-a unchanged on conflict'
        Assert-Equal $bTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-b') -Message 'branch-b unchanged on conflict'
        $wts = Invoke-SandboxGit $sb.Repo @('worktree', 'list', '--porcelain')
        Assert-False ((@($wts.Output) -join "`n") -match 'gitmerge-tmp-') 'no temp worktree may leak'
    } finally { Remove-GitSandbox $sb }
}

# X is ahead of current (current is ancestor): current fast-forwards up to X; X unchanged. (X not checked out.)
Test-Case 'gitmerge {branch} fast-forwards current up to an ahead X (X not checked out)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'branch-b' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-b') | Out-Null
        $bTip = New-SandboxCommit -Sandbox $sb -FileName 'b.txt' -Content "b`n" -Message 'b work'
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null  # branch-a == base, behind branch-b

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'branch-b' -Sandbox $sb
        Assert-True $ok 'a fast-forward convergence should succeed'
        Assert-Equal $bTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a') -Message 'branch-a fast-forwards up to branch-b tip'
        Assert-Equal $bTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-b') -Message 'branch-b is unchanged (already the union)'
    } finally { Remove-GitSandbox $sb }
}

# F1 all-or-nothing: X checked out in a dirty extra worktree -> preflight re-check fires -> both unchanged.
Test-Case 'gitmerge {branch} refuses when X is checked out in another worktree and dirty; both unchanged' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'branch-b' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-b') | Out-Null
        $bTip = New-SandboxCommit -Sandbox $sb -FileName 'b.txt' -Content "b`n" -Message 'b work'
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null
        $aTip = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "a`n" -Message 'a work'
        # check out branch-b in a SEPARATE worktree and dirty it
        $wtB = Join-Path $sb.Root 'wt-b'
        Invoke-SandboxGit $sb.Repo @('worktree', 'add', $wtB, 'branch-b') | Out-Null
        Set-Content -LiteralPath (Join-Path $wtB 'b.txt') -Value "dirty`n" -Encoding utf8

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'branch-b' -Sandbox $sb
        Assert-False $ok 'gitmerge must refuse when X (branch-b) is checked out dirty elsewhere'
        Assert-Equal $aTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a') -Message 'branch-a unchanged'
        Assert-Equal $bTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-b') -Message 'branch-b unchanged'
    } finally {
        $wtB = Join-Path $sb.Root 'wt-b'
        if (Test-Path -LiteralPath $wtB) {
            Invoke-SandboxGit $sb.Repo @('worktree', 'remove', '--force', $wtB) | Out-Null
        }
        Remove-GitSandbox $sb
    }
}
