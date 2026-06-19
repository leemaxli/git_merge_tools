. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

function Test-IsAncestorSb { param($sb,$anc,$desc); return (Invoke-SandboxGit $sb.Repo @('merge-base','--is-ancestor',$anc,$desc)).ExitCode -eq 0 }

# v7.2: cross-all = full mesh. Everyone converges to ONE union commit (union of all). main not special.
Test-Case 'gitmerge cross-all: every branch converges to the same union commit' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $tWork = New-SandboxCommit -Sandbox $sb -FileName 't.txt' -Content "T`n" -Message 'main work'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-a') | Out-Null
        $aWork = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A work'
        New-SandboxBranch -Sandbox $sb -Name 'branch-c' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-c') | Out-Null
        $cWork = New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "C`n" -Message 'C work'
        Invoke-SandboxGit $sb.Repo @('switch','main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-True $ok 'cross-all (clean) should succeed'
        $m = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $a = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a'
        $c = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-c'
        Assert-Equal $m $a -Message 'main and branch-a converge to the same commit'
        Assert-Equal $m $c -Message 'main and branch-c converge to the same commit'
        # the union contains everyone's work
        Assert-True (Test-IsAncestorSb $sb $tWork 'refs/heads/main') 'union has main work'
        Assert-True (Test-IsAncestorSb $sb $aWork 'refs/heads/main') 'union has A work'
        Assert-True (Test-IsAncestorSb $sb $cWork 'refs/heads/main') 'union has C work'
        Assert-Equal 'main' (@((Invoke-SandboxGit $sb.Repo @('symbolic-ref','--short','HEAD')).Output)[0]) -Message 'caller stays on current'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge cross-all: a conflict aborts the whole run (fail-fast); nothing changes; no leak' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $tWork = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "T-line`n" -Message 'main edits f'
        New-SandboxBranch -Sandbox $sb -Name 'branch-x' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-x') | Out-Null
        $xWork = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "X-line`n" -Message 'x edits f (conflicts)'
        Invoke-SandboxGit $sb.Repo @('switch','main') | Out-Null
        $mBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $xBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-x'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-False $ok 'a conflict must fail the whole cross-all run'
        Assert-Equal $mBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main unchanged (fail-fast)'
        Assert-Equal $xBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-x') -Message 'branch-x unchanged (fail-fast)'
        $wts = Invoke-SandboxGit $sb.Repo @('worktree','list','--porcelain')
        Assert-False ((@($wts.Output) -join "`n") -match 'gitmerge-tmp-') 'no temp worktree may leak'
    } finally { Remove-GitSandbox $sb }
}

# v7.5.0: NON-overlapping dirty change -> branch converges fine (dirty edit preserved).
Test-Case 'gitmerge cross-all: a non-overlapping dirty branch converges; dirty edit preserved' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $tWork = New-SandboxCommit -Sandbox $sb -FileName 't.txt' -Content "T`n" -Message 'main work'
        New-SandboxBranch -Sandbox $sb -Name 'branch-clean' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-clean') | Out-Null
        $cleanWork = New-SandboxCommit -Sandbox $sb -FileName 'clean.txt' -Content "clean`n" -Message 'clean'
        New-SandboxBranch -Sandbox $sb -Name 'branch-dirty' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-dirty') | Out-Null
        $dirtyWork = New-SandboxCommit -Sandbox $sb -FileName 'd.txt' -Content "d`n" -Message 'd'
        Invoke-SandboxGit $sb.Repo @('switch','main') | Out-Null
        $wtD = Join-Path $sb.Root 'wt-dirty'
        Invoke-SandboxGit $sb.Repo @('worktree','add', $wtD, 'branch-dirty') | Out-Null
        # dirty on d.txt (NON-overlapping: the FF of branch-dirty to union adds t.txt and clean.txt, not d.txt)
        Set-Content -LiteralPath (Join-Path $wtD 'd.txt') -Value "uncommitted`n" -Encoding utf8
        $dirtyBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-dirty'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-True $ok 'cross-all succeeds (non-overlapping dirty branch is not skipped)'
        # All branches converge to the same union
        Assert-Equal (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-clean') -Message 'main and branch-clean converge'
        Assert-Equal (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-dirty') -Message 'branch-dirty also converges (non-overlapping dirty)'
        Assert-True (Test-IsAncestorSb $sb $dirtyWork 'refs/heads/main') 'union contains the dirty branch work (it was not skipped)'
        # dirty edit preserved in the worktree
        $content = Get-Content -LiteralPath (Join-Path $wtD 'd.txt') -Raw
        Assert-True ($content -match 'uncommitted') 'uncommitted dirty edit must be preserved after non-overlapping FF'
        Invoke-SandboxGit $sb.Repo @('worktree','remove','--force', $wtD) | Out-Null
    } finally { Remove-GitSandbox $sb }
}

# v7.5.0: OVERLAPPING dirty change -> git refuses FF at apply -> branch SKIPPED (skip-and-proceed).
# Setup: branch-dirty at base; union adds shared.txt (from branch-clean). wt-dirty has untracked shared.txt.
Test-Case 'gitmerge cross-all: an overlapping dirty branch is skipped at apply; the rest converge' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        # branch-clean at base, adds shared.txt
        New-SandboxBranch -Sandbox $sb -Name 'branch-clean' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-clean') | Out-Null
        $cleanWork = New-SandboxCommit -Sandbox $sb -FileName 'shared.txt' -Content "shared`n" -Message 'adds shared'
        # branch-dirty at base (no unique commits)
        New-SandboxBranch -Sandbox $sb -Name 'branch-dirty' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','main') | Out-Null
        $wtD = Join-Path $sb.Root 'wt-dirty'
        Invoke-SandboxGit $sb.Repo @('worktree','add', $wtD, 'branch-dirty') | Out-Null
        # untracked shared.txt in wt-dirty -> FF would introduce tracked shared.txt -> git refuses
        Set-Content -LiteralPath (Join-Path $wtD 'shared.txt') -Value "wip`n" -Encoding utf8
        $dirtyBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-dirty'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-True $ok 'cross-all must succeed (skip-and-proceed past overlapping dirty branch)'
        # branch-dirty skipped; ref unchanged; wip preserved
        Assert-Equal $dirtyBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-dirty') -Message 'skipped branch-dirty ref unchanged'
        $wip = Get-Content -LiteralPath (Join-Path $wtD 'shared.txt') -Raw
        Assert-True ($wip -match 'wip') 'overlapping wip must be preserved (not overwritten)'
        # main and branch-clean converged (union includes shared.txt)
        Assert-True (Test-IsAncestorSb $sb $cleanWork 'refs/heads/main') 'union has the clean branch work'
        Assert-Equal (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-clean') -Message 'main and branch-clean converge'
        Invoke-SandboxGit $sb.Repo @('worktree','remove','--force', $wtD) | Out-Null
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge debug: dry-run of the mesh changes nothing' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-a') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A')
        Invoke-SandboxGit $sb.Repo @('switch','main') | Out-Null
        $mBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $aBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'debug' -Sandbox $sb
        Assert-True $ok 'debug dry-run should succeed'
        Assert-Equal $mBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'debug changes no ref'
        Assert-Equal $aBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a') -Message 'debug changes no ref'
        $wts = Invoke-SandboxGit $sb.Repo @('worktree','list','--porcelain')
        Assert-False ((@($wts.Output) -join "`n") -match 'gitmerge-tmp-') 'debug leaves no temp worktree'
    } finally { Remove-GitSandbox $sb }
}
