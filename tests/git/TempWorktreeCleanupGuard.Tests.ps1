$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulesRoot = Join-Path $repoRoot 'Modules'
Import-Module (Join-Path $modulesRoot 'GitMergeTools.Core.psm1') -Force
Import-Module (Join-Path $modulesRoot 'GitMergeTools.Merge.psm1') -Force

# Test-TemporaryWorktreeForCleanup is the SOLE gate before the tool's only destructive operation,
# `git worktree remove --force` (Invoke-TemporaryCleanup). It must return $true ONLY for a path that is
# exactly <temp>/<branch>, whose branch matches ^gitmerge-tmp-[0-9a-f]{32}$, that maps to a real, UNLOCKED
# worktree record. The happy path (returning $true during a real run's cleanup) is exercised by every
# engine/smoke test; these tests pin the REFUSAL arms so a regression can't loosen the gate into
# force-removing a user-owned worktree.

Test-Case 'Test-TemporaryWorktreeForCleanup refuses anything that is not exactly our temp worktree' {
    $sb = New-GitSandbox
    try {
        $valid = 'gitmerge-tmp-' + ('a' * 32)
        $validPath = Join-Path ([System.IO.Path]::GetTempPath()) $valid
        # empty inputs
        Assert-False (Test-TemporaryWorktreeForCleanup -Repository $sb.Repo -WorktreePath '' -TemporaryBranch $valid) -Message 'an empty path must be refused'
        Assert-False (Test-TemporaryWorktreeForCleanup -Repository $sb.Repo -WorktreePath $validPath -TemporaryBranch '') -Message 'an empty branch must be refused'
        # branch not matching the gitmerge-tmp-<32 hex> pattern
        Assert-False (Test-TemporaryWorktreeForCleanup -Repository $sb.Repo -WorktreePath $validPath -TemporaryBranch 'feature/x') -Message 'a non-tmp branch name must be refused'
        $shortPath = Join-Path ([System.IO.Path]::GetTempPath()) 'gitmerge-tmp-short'
        Assert-False (Test-TemporaryWorktreeForCleanup -Repository $sb.Repo -WorktreePath $shortPath -TemporaryBranch 'gitmerge-tmp-short') -Message 'a malformed (non-32-hex) tmp suffix must be refused'
        # valid pattern, but the path is NOT <temp>/<branch> (here: inside the repo, a user-owned path)
        Assert-False (Test-TemporaryWorktreeForCleanup -Repository $sb.Repo -WorktreePath (Join-Path $sb.Repo $valid) -TemporaryBranch $valid) -Message 'a path outside <temp>/<branch> must be refused'
        # valid pattern + path, but no such worktree record exists
        Assert-False (Test-TemporaryWorktreeForCleanup -Repository $sb.Repo -WorktreePath $validPath -TemporaryBranch $valid) -Message 'a non-existent worktree must be refused'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'Test-TemporaryWorktreeForCleanup accepts a real gitmerge-tmp worktree but refuses it when LOCKED' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $tmpBranch = 'gitmerge-tmp-' + [guid]::NewGuid().ToString('N')
        $tmpPath = Join-Path ([System.IO.Path]::GetTempPath()) $tmpBranch
        $add = Invoke-SandboxGit $sb.Repo @('worktree', 'add', '-b', $tmpBranch, $tmpPath, 'HEAD')
        Assert-Equal 0 $add.ExitCode -Message 'setup: create the temp worktree'
        try {
            # positive: a real, unlocked gitmerge-tmp worktree at the expected path is accepted (proves the
            # refusals above are real, not vacuous).
            Assert-True (Test-TemporaryWorktreeForCleanup -Repository $sb.Repo -WorktreePath $tmpPath -TemporaryBranch $tmpBranch) -Message 'a real, unlocked gitmerge-tmp worktree must be accepted'
            # locked: never force-remove a locked worktree.
            [void](Invoke-SandboxGit $sb.Repo @('worktree', 'lock', $tmpPath))
            Assert-False (Test-TemporaryWorktreeForCleanup -Repository $sb.Repo -WorktreePath $tmpPath -TemporaryBranch $tmpBranch) -Message 'a LOCKED worktree must be refused'
            [void](Invoke-SandboxGit $sb.Repo @('worktree', 'unlock', $tmpPath))
        } finally {
            [void](Invoke-SandboxGit $sb.Repo @('worktree', 'remove', '--force', $tmpPath))
        }
    } finally { Remove-GitSandbox $sb }
}
