. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.5.0: two cross-all (mesh) edge cases updated for correct dirty-handling semantics.

# Edge 1: the CURRENT branch is dirty but is ALREADY THE UNION (does not need to move).
# v7.5.0: uncommitted changes on a branch that does NOT move are irrelevant -- the ref is left untouched,
# the changes preserved. The other branches converge up to current's tip. This is the correct outcome;
# aborting (v7.4.1 behaviour) was over-blocking.
# Setup: main is already the union (it has merged all other branches). Others are ancestors. main is dirty.
Test-Case 'gitmerge cross-all: a dirty CURRENT that is ahead does NOT abort; others converge up to it' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'branch-a' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A work')
        New-SandboxBranch -Sandbox $sb -Name 'branch-c' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-c') | Out-Null
        [void](New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "C`n" -Message 'C work')
        # Make main the union by merging both branches into it
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        Invoke-SandboxGit $sb.Repo @('merge', '--no-edit', 'branch-a', 'branch-c') | Out-Null   # main is now the union
        $mainRef = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        # Dirty current (main) on f.txt (non-overlapping: the union already includes all files)
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty`n" -Encoding utf8

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-True $ok 'a dirty current that is already the union must not abort cross-all (it does not need to move)'
        # main ref untouched (it was already the union)
        Assert-Equal $mainRef (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'current (main) ref unchanged (was already the union)'
        # branch-a and branch-c should have been moved up (they were ancestors of the union)
        Assert-Equal $mainRef (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a') -Message 'branch-a converged to main tip'
        Assert-Equal $mainRef (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-c') -Message 'branch-c converged to main tip'
        # dirty file still present and unchanged
        $content = Get-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Raw
        Assert-True ($content -match 'dirty') 'dirty edit must be preserved after cross-all'
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
        # Simulate an in-progress op on branch-a in a separate worktree (untouchable state -> skip)
        # We use a locked worktree to trigger the skip without needing a real in-progress op.
        # Actually: just make it the only other branch and give main no work -> it's a no-op (already at union)
        # Simpler: main == base, branch-a is ahead; put branch-a in a worktree with an in-progress merge.
        # Instead, just have only main with no other safe branch and verify no-op:
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        $aBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a'

        # Trigger the "fewer than 2 safe" path by making branch-a's worktree untouchable (lock it).
        $wtA = Join-Path $sb.Root 'wt-a'
        Invoke-SandboxGit $sb.Repo @('worktree', 'add', $wtA, 'branch-a') | Out-Null
        Invoke-SandboxGit $sb.Repo @('worktree', 'lock', $wtA) | Out-Null   # makes it locked -> untouchable

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-True $ok 'with only one safe branch (others untouchable), cross-all is a no-op success'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main unchanged'
        Assert-Equal $aBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/branch-a') -Message 'the locked branch unchanged'
        Invoke-SandboxGit $sb.Repo @('worktree', 'unlock', $wtA) | Out-Null
        Invoke-SandboxGit $sb.Repo @('worktree', 'remove', '--force', $wtA) | Out-Null
    } finally { Remove-GitSandbox $sb }
}
