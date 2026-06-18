. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.1: `gitmerge all` = current-branch STAR. Hub T (=current) absorbs every other branch (T = union of
# all). Each other branch B reverse-merges T's ORIGINAL commit -> B = originalT u B (B never gets another
# B's work). Skip-and-proceed; hub's own dirty worktree aborts.

# helper: is $anc an ancestor of $desc (commit reachable)?
function Test-IsAncestorSb { param($sb,$anc,$desc); return (Invoke-SandboxGit $sb.Repo @('merge-base','--is-ancestor',$anc,$desc)).ExitCode -eq 0 }

Test-Case 'gitmerge all: hub absorbs all; each spoke gets originalT but not each other' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        # hub = main (current). give main its own work on a distinct file.
        $tWork = New-SandboxCommit -Sandbox $sb -FileName 't.txt' -Content "T`n" -Message 'T work'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-a') | Out-Null
        $aWork = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A work'
        New-SandboxBranch -Sandbox $sb -Name 'branch-c' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-c') | Out-Null
        $cWork = New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "C`n" -Message 'C work'
        Invoke-SandboxGit $sb.Repo @('switch','main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-True $ok 'gitmerge all (clean) should succeed'

        # hub (main) = union of all: descends T, A, C work.
        Assert-True (Test-IsAncestorSb $sb $tWork 'refs/heads/main') 'hub has T work'
        Assert-True (Test-IsAncestorSb $sb $aWork 'refs/heads/main') 'hub has A work'
        Assert-True (Test-IsAncestorSb $sb $cWork 'refs/heads/main') 'hub has C work'
        # branch-a = originalT u A: has T work and A work, but NOT C work.
        Assert-True (Test-IsAncestorSb $sb $tWork 'refs/heads/branch-a') 'branch-a got originalT work'
        Assert-True (Test-IsAncestorSb $sb $aWork 'refs/heads/branch-a') 'branch-a kept its own work'
        Assert-False (Test-IsAncestorSb $sb $cWork 'refs/heads/branch-a') 'branch-a must NOT get branch-c work (no B<->B)'
        # branch-c = originalT u C: has T and C, but NOT A.
        Assert-True (Test-IsAncestorSb $sb $tWork 'refs/heads/branch-c') 'branch-c got originalT work'
        Assert-True (Test-IsAncestorSb $sb $cWork 'refs/heads/branch-c') 'branch-c kept its own work'
        Assert-False (Test-IsAncestorSb $sb $aWork 'refs/heads/branch-c') 'branch-c must NOT get branch-a work'
        # caller stays on main.
        Assert-Equal 'main' (@((Invoke-SandboxGit $sb.Repo @('symbolic-ref','--short','HEAD')).Output)[0]) -Message 'caller stays on hub'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge all: a conflicting spoke is skipped; the clean ones still merge' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $tWork = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "T-line`n" -Message 'T edits f'
        New-SandboxBranch -Sandbox $sb -Name 'branch-good' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-good') | Out-Null
        $goodWork = New-SandboxCommit -Sandbox $sb -FileName 'good.txt' -Content "good`n" -Message 'good'
        New-SandboxBranch -Sandbox $sb -Name 'branch-bad' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-bad') | Out-Null
        $badWork = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "bad-line`n" -Message 'bad edits f (conflicts with T)'
        Invoke-SandboxGit $sb.Repo @('switch','main') | Out-Null

        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        # good merged into hub; bad skipped (its work not in hub, branch-bad untouched).
        Assert-True (Test-IsAncestorSb $sb $goodWork 'refs/heads/main') 'hub absorbed the clean branch'
        Assert-False (Test-IsAncestorSb $sb $badWork 'refs/heads/main') 'hub must NOT contain the conflicting branch'
        Assert-Equal $badWork (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-bad') -Message 'conflicting branch left untouched'
        Assert-Match 'branch-bad' $out -Message 'summary should name the skipped branch'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge all: a dirty HUB worktree aborts; nothing changed' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-a') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A')
        Invoke-SandboxGit $sb.Repo @('switch','main') | Out-Null
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $aBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a'
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty`n" -Encoding utf8

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-False $ok 'a dirty hub worktree must abort gitmerge all'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'hub unchanged'
        Assert-Equal $aBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a') -Message 'spoke unchanged'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge all: a dirty non-hub spoke is skipped; a clean spoke still merges; run succeeds' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'branch-clean' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-clean') | Out-Null
        $cleanWork = New-SandboxCommit -Sandbox $sb -FileName 'clean.txt' -Content "clean`n" -Message 'clean work'
        New-SandboxBranch -Sandbox $sb -Name 'branch-dirty' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-dirty') | Out-Null
        $dirtyWork = New-SandboxCommit -Sandbox $sb -FileName 'd.txt' -Content "d`n" -Message 'dirty branch work'
        Invoke-SandboxGit $sb.Repo @('switch','main') | Out-Null
        # check out branch-dirty in a separate worktree and dirty it
        $wtD = Join-Path $sb.Root 'wt-dirty'
        Invoke-SandboxGit $sb.Repo @('worktree','add', $wtD, 'branch-dirty') | Out-Null
        Set-Content -LiteralPath (Join-Path $wtD 'd.txt') -Value "uncommitted`n" -Encoding utf8
        $dirtyBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-dirty'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-True $ok 'star run should succeed (skip-and-proceed past the dirty spoke)'
        Assert-True ((Invoke-SandboxGit $sb.Repo @('merge-base','--is-ancestor',$cleanWork,'refs/heads/main')).ExitCode -eq 0) 'hub absorbed the clean spoke'
        Assert-False ((Invoke-SandboxGit $sb.Repo @('merge-base','--is-ancestor',$dirtyWork,'refs/heads/main')).ExitCode -eq 0) 'hub must NOT absorb the dirty (skipped) spoke'
        Assert-Equal $dirtyBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-dirty') -Message 'skipped dirty spoke left untouched'
        Invoke-SandboxGit $sb.Repo @('worktree','remove','--force', $wtD) | Out-Null
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge all: no temp worktree leaks' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch','branch-a') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A')
        Invoke-SandboxGit $sb.Repo @('switch','main') | Out-Null
        $null = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        $wts = Invoke-SandboxGit $sb.Repo @('worktree','list','--porcelain')
        Assert-False ((@($wts.Output) -join "`n") -match 'gitmerge-tmp-') 'no temp worktree may leak'
    } finally { Remove-GitSandbox $sb }
}
