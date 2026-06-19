. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.5.0: Dirty-current handling in cross-all (mesh).
# Principle: uncommitted changes are NOT a pre-block. The union is built from COMMITTED tips in a throwaway.
# A dirty current that is ALREADY AT THE UNION (i.e. it is the most-advanced branch) does not need to move
# -- the ref is left untouched, uncommitted changes preserved. A dirty current that MUST MOVE is advanced
# by git merge --ff-only, which preserves non-overlapping changes and refuses overlapping ones (skip +
# WARNING in mesh = skip-and-proceed). An IN-PROGRESS current (mid-merge/rebase/cherry-pick/revert) still
# aborts because the worktree is genuinely untouchable.

# (a) Headline case: current (claude) is AHEAD of others + has NON-OVERLAPPING uncommitted changes.
# Others should be converged up to claude's tip; claude's ref is untouched; its dirty change preserved.
Test-Case 'gitmerge cross-all converges others up to dirty CURRENT when current is ahead; changes preserved' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'   # main @ base
        New-SandboxBranch -Sandbox $sb -Name 'codex' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'deepseek' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'claude' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'claude') | Out-Null
        $claudeTip = New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "claude work`n" -Message 'claude work'
        # Non-overlapping dirty change on a DIFFERENT file (does not touch any of the others' files)
        Set-Content -LiteralPath (Join-Path $sb.Repo 'claude-wip.txt') -Value "wip`n" -Encoding utf8
        $claudeRef = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/claude'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-True $ok 'cross-all must succeed when current is ahead with non-overlapping dirty changes'

        # claude ref is unchanged (already at union)
        Assert-Equal $claudeRef (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/claude') -Message 'claude ref must be untouched (it was already the union)'
        # others converge up to claude's tip
        Assert-Equal $claudeTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/codex') -Message 'codex must converge to claude tip'
        Assert-Equal $claudeTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/deepseek') -Message 'deepseek must converge to claude tip'
        Assert-Equal $claudeTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main must converge to claude tip'
        # uncommitted change file still present (preserved)
        Assert-True (Test-Path -LiteralPath (Join-Path $sb.Repo 'claude-wip.txt')) 'uncommitted wip file must still exist'
    } finally { Remove-GitSandbox $sb }
}

# (b) A non-current branch checked out in a SEPARATE WORKTREE with OVERLAPPING uncommitted change ->
# that branch is SKIPPED with a commit/stash warning, the rest converge, no data lost.
# Setup: branch-b is at base (no unique commits). Union will add shared.txt (from branch-a).
# branch-b's worktree has untracked shared.txt -> FF from base to union would overwrite it -> git refuses.
Test-Case 'gitmerge cross-all skips branch with OVERLAPPING dirty changes; others still converge' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        # branch-a: adds shared.txt = "A content" (diverges from base)
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null
        $aTip = New-SandboxCommit -Sandbox $sb -FileName 'shared.txt' -Content "A content`n" -Message 'A adds shared'
        # branch-b: stays at base (no unique commits) -- will be behind the union
        New-SandboxBranch -Sandbox $sb -Name 'branch-b' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        # check out branch-b in a worktree; write an UNTRACKED shared.txt
        # FF of branch-b from base to union would introduce shared.txt (tracked), but worktree has untracked shared.txt -> git refuses
        $wtB = Join-Path $sb.Root 'wt-b'
        Invoke-SandboxGit $sb.Repo @('worktree', 'add', $wtB, 'branch-b') | Out-Null
        Set-Content -LiteralPath (Join-Path $wtB 'shared.txt') -Value "my-wip`n" -Encoding utf8   # overlapping untracked

        $branchBBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-b'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-True $ok 'cross-all must succeed (skip-and-proceed past the branch with overlapping dirty change)'
        # branch-b was skipped; its ref is unchanged, wip file preserved
        Assert-Equal $branchBBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-b') -Message 'branch-b ref must be unchanged (skipped)'
        # shared.txt wip must still be there (not overwritten)
        $wip = Get-Content -LiteralPath (Join-Path $wtB 'shared.txt') -Raw
        Assert-True ($wip -match 'my-wip') 'overlapping wip in branch-b worktree must be preserved (not overwritten)'
        # main (current) should have been moved to the union (= branch-a's tip)
        Assert-Equal $aTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main must converge to branch-a tip (the union)'
        Invoke-SandboxGit $sb.Repo @('worktree', 'remove', '--force', $wtB) | Out-Null
    } finally { Remove-GitSandbox $sb }
}

# (c) An IN-PROGRESS CURRENT worktree (mid-merge) still aborts -- it is genuinely untouchable.
Test-Case 'gitmerge cross-all ABORTS when the current branch worktree is mid-merge (in-progress op)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'codex' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'claude' -StartPoint $base
        # Put claude's worktree mid-merge: make a conflicting commit on a side branch, then fail a merge
        Invoke-SandboxGit $sb.Repo @('switch', 'claude') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "claude side`n" -Message 'claude edit f')
        New-SandboxBranch -Sandbox $sb -Name 'conflict-feeder' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'conflict-feeder') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "conflict side`n" -Message 'conflict edit f')
        Invoke-SandboxGit $sb.Repo @('switch', 'claude') | Out-Null
        Invoke-SandboxGit $sb.Repo @('merge', 'conflict-feeder') | Out-Null   # leaves MERGE_HEAD (conflict)

        $claudeRef = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/claude'
        $codexRef = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/codex'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-False $ok 'cross-all must ABORT when the current branch worktree has an in-progress merge'
        # Nothing must have changed
        Assert-Equal $claudeRef (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/claude') -Message 'claude ref unchanged on abort'
        Assert-Equal $codexRef (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/codex') -Message 'codex ref unchanged on abort'
    } finally { Remove-GitSandbox $sb }
}

# (d) Actionable message for the in-progress abort case.
Test-Case 'gitmerge cross-all in-progress-current abort gives actionable message naming the operation' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'codex' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'claude' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'claude') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "claude side`n" -Message 'claude edit f')
        New-SandboxBranch -Sandbox $sb -Name 'conflict-feeder' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'conflict-feeder') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "conflict side`n" -Message 'conflict edit f')
        Invoke-SandboxGit $sb.Repo @('switch', 'claude') | Out-Null
        Invoke-SandboxGit $sb.Repo @('merge', 'conflict-feeder') | Out-Null   # leaves MERGE_HEAD

        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-Match 'in progress' $out -Message 'the abort message must mention the in-progress operation'
        Assert-False ($out -match 'Result\s*:\s*SUCCESS') 'an in-progress-current cross-all must NOT report SUCCESS'
    } finally { Remove-GitSandbox $sb }
}
