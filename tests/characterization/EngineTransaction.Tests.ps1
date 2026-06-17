. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# Characterization tests that LOCK the transactional merge engine's safety invariants before the P3
# engine extraction. They capture current (correct) behavior; any P3 change that alters it turns these
# red. Together with Safety.Tests (conflict->no-change/no-leak, dirty->refuse, clean-FF->branch-kept)
# they cover: all-or-nothing, non-FF merge integration, caller-HEAD invariance, post-success cleanup.

Test-Case 'gitmerge all is all-or-nothing: one conflicting target leaves main and ALL branches unchanged' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "main-change`n" -Message 'main edit')
        New-SandboxBranch -Sandbox $sb -Name 'feature/good' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/good') | Out-Null
        $goodTip = New-SandboxCommit -Sandbox $sb -FileName 'good.txt' -Content "good`n" -Message 'good work'
        New-SandboxBranch -Sandbox $sb -Name 'feature/bad' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/bad') | Out-Null
        $badTip = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "feature-change`n" -Message 'bad edit'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-False $ok 'gitmerge all must fail if any target conflicts'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main must be unchanged (all-or-nothing): the good branch must not partially land'
        Assert-Equal $goodTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/good') -Message 'the good branch ref must be untouched'
        Assert-Equal $badTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/bad') -Message 'the bad branch ref must be untouched'
        $wts = Invoke-SandboxGit $sb.Repo @('worktree', 'list', '--porcelain')
        Assert-False ((@($wts.Output) -join "`n") -match 'gitmerge-tmp-') 'no temp worktree may leak'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge integrates a diverged (non-fast-forward) branch via a merge commit; user branch untouched' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $mainTip = New-SandboxCommit -Sandbox $sb -FileName 'main.txt' -Content "main`n" -Message 'main work'
        New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        $featTip = New-SandboxCommit -Sandbox $sb -FileName 'feat.txt' -Content "feat`n" -Message 'feat work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/x' -Sandbox $sb
        Assert-True $ok 'a clean (non-conflicting) diverged merge should succeed'
        $newMain = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        Assert-False ($newMain -eq $mainTip) 'main should advance to a new merge commit (not stay at the old tip)'
        Assert-Equal 0 (Invoke-SandboxGit $sb.Repo @('merge-base', '--is-ancestor', $mainTip, 'refs/heads/main')).ExitCode -Message 'new main must descend from old main'
        Assert-Equal 0 (Invoke-SandboxGit $sb.Repo @('merge-base', '--is-ancestor', $featTip, 'refs/heads/main')).ExitCode -Message 'new main must descend from the feature tip (work integrated)'
        # Consolidation: the target branch is fast-forwarded UP to the integrated main (ancestor-guarded,
        # never force-moved/rewound — the old tip remains an ancestor, no work is lost).
        Assert-Equal $newMain (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/x') -Message 'feature/x is fast-forwarded to the integrated main'
        Assert-Equal 0 (Invoke-SandboxGit $sb.Repo @('merge-base', '--is-ancestor', $featTip, 'refs/heads/feature/x')).ExitCode -Message 'feature/x only advanced (old tip is an ancestor); it was never force-moved'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge leaves the caller current branch / HEAD unchanged and cleans up after success' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base')
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "work`n" -Message 'work')
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        $headBefore = @((Invoke-SandboxGit $sb.Repo @('symbolic-ref', '--short', 'HEAD')).Output)[0]

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/x' -Sandbox $sb
        Assert-True $ok 'merge should succeed'
        $headAfter = @((Invoke-SandboxGit $sb.Repo @('symbolic-ref', '--short', 'HEAD')).Output)[0]
        Assert-Equal $headBefore $headAfter -Message 'the caller current branch (HEAD) must be unchanged'
        $wts = Invoke-SandboxGit $sb.Repo @('worktree', 'list', '--porcelain')
        Assert-False ((@($wts.Output) -join "`n") -match 'gitmerge-tmp-') 'no temp worktree may leak after a successful run'
    } finally { Remove-GitSandbox $sb }
}
