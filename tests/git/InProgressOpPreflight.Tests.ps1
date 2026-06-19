$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulesRoot = Join-Path $repoRoot 'Modules'
Import-Module (Join-Path $modulesRoot 'GitMergeTools.Core.psm1') -Force
Import-Module (Join-Path $modulesRoot 'GitMergeTools.Merge.psm1') -Force
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# Git-safety hardening: if an affected worktree is mid-merge / mid-rebase / mid-cherry-pick / mid-revert,
# consolidating through it would compound a half-finished operation. The engine must REFUSE up front and
# name the operation. Markers are resolved per-worktree via `git rev-parse --git-path`, which is correct
# for linked worktrees too (their state lives under .git/worktrees/<name>/).

function New-ConflictingMergeSandbox {
    # Returns a sandbox whose main worktree is left mid-merge (MERGE_HEAD present) with a conflict, plus
    # the pre-merge main tip so the test can assert main was not advanced.
    $sb = New-GitSandbox
    $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $base
    Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
    $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "feature side`n" -Message 'feature change'
    Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
    $mainTip = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "mainline side`n" -Message 'main change'
    Invoke-SandboxGit $sb.Repo @('merge', 'feature/x') | Out-Null   # conflicts; leaves MERGE_HEAD in place
    return [pscustomobject]@{ Sandbox = $sb; MainTip = $mainTip }
}

Test-Case 'Get-WorktreeInProgressOperation detects an in-progress merge (MERGE_HEAD present)' {
    $ctx = New-ConflictingMergeSandbox
    try {
        $op = Get-WorktreeInProgressOperation -Worktree ([pscustomobject]@{ Path = $ctx.Sandbox.Repo })
        Assert-Equal 'a merge' $op -Message 'MERGE_HEAD must be reported as an in-progress merge'
    }
    finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'Get-WorktreeInProgressOperation returns null for a clean worktree' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $op = Get-WorktreeInProgressOperation -Worktree ([pscustomobject]@{ Path = $sb.Repo })
        Assert-True ($null -eq $op) -Message 'a clean worktree has no in-progress operation'
    }
    finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge refuses when an affected worktree is mid-merge, naming the operation; main unchanged' {
    $ctx = New-ConflictingMergeSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-Match 'in progress' $out -Message 'the refusal must name the in-progress operation, not just call it dirty'
        Assert-Equal $ctx.MainTip (Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/main') -Message 'main must be unchanged'
    }
    finally { Remove-GitSandbox $ctx.Sandbox }
}

# v7.5.1 BUGFIX: a leftover REBASE_HEAD ref is NOT an in-progress rebase. git writes REBASE_HEAD to point at
# the commit being replayed and LEAVES IT BEHIND after the rebase finishes/aborts (like ORIG_HEAD). git's own
# "rebase in progress" test (wt-status.c) keys on the rebase-merge / rebase-apply DIRECTORY, never on
# REBASE_HEAD. Before this fix, a stale REBASE_HEAD made Get-WorktreeInProgressOperation report 'a rebase',
# which made Test-WorktreeUsable refuse and aborted gitmerge/gitsync cross-all on a perfectly clean branch.

Test-Case 'Get-WorktreeInProgressOperation ignores a stale REBASE_HEAD ref (no rebase-merge/apply dir)' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $tip = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'
        Set-Content -LiteralPath (Join-Path $sb.Repo '.git/REBASE_HEAD') -Value $tip -NoNewline -Encoding ascii
        $op = Get-WorktreeInProgressOperation -Worktree ([pscustomobject]@{ Path = $sb.Repo })
        Assert-True ($null -eq $op) -Message 'a stale REBASE_HEAD (no rebase dir) must NOT be treated as an in-progress rebase'
    }
    finally { Remove-GitSandbox $sb }
}

Test-Case 'Get-WorktreeInProgressOperation still detects a real in-progress rebase (rebase-merge dir present)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'topic' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'topic') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "topic side`n" -Message 'topic change'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "main side`n" -Message 'main change'
        Invoke-SandboxGit $sb.Repo @('switch', 'topic') | Out-Null
        Invoke-SandboxGit $sb.Repo @('rebase', 'main') | Out-Null   # conflicts -> real rebase-merge dir
        $op = Get-WorktreeInProgressOperation -Worktree ([pscustomobject]@{ Path = $sb.Repo })
        Assert-Equal 'a rebase' $op -Message 'a real in-progress rebase (rebase-merge dir) must still be detected'
    }
    finally {
        Invoke-SandboxGit $sb.Repo @('rebase', '--abort') | Out-Null
        Remove-GitSandbox $sb
    }
}

Test-Case 'gitmerge cross-all does NOT abort the current branch for a stale REBASE_HEAD' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'   # main @ base
        New-SandboxBranch -Sandbox $sb -Name 'codex' -StartPoint $base
        New-SandboxBranch -Sandbox $sb -Name 'deepseek' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        $mainTip = New-SandboxCommit -Sandbox $sb -FileName 'm.txt' -Content "main work`n" -Message 'main ahead'
        # stale REBASE_HEAD on the CURRENT (main) worktree -- no real rebase in progress
        Set-Content -LiteralPath (Join-Path $sb.Repo '.git/REBASE_HEAD') -Value $base -NoNewline -Encoding ascii
        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-True $ok 'cross-all must not abort when the current branch has only a stale REBASE_HEAD'
        Assert-Equal $mainTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/codex') -Message 'codex must converge to the main tip'
        Assert-Equal $mainTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/deepseek') -Message 'deepseek must converge to the main tip'
    }
    finally { Remove-GitSandbox $sb }
}
