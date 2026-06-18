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
