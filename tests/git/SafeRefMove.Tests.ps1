$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulesRoot = Join-Path $repoRoot 'Modules'
Import-Module (Join-Path $modulesRoot 'GitMergeTools.Core.psm1') -Force
Import-Module (Join-Path $modulesRoot 'GitMergeTools.Merge.psm1') -Force

# Safety primitive for the gitsync worktree-free pull paths ('ref' and 'merge-ref'): advance a local
# branch to NewHash ONLY IF the ref is still exactly the hash the decision was based on (ExpectedOldHash)
# AND NewHash is a true fast-forward of it (descends it). This closes the between-pass race the adversarial
# review found: re-reading the tip fresh and CAS-ing against THAT would force-move a concurrently-advanced
# branch sideways (orphaning the new commit) -- here a concurrent move makes the CAS old-value mismatch and
# we refuse, changing nothing.
function Set-SandboxBranchRef {
    param($Sandbox, [string]$Branch, [string]$Hash)
    Invoke-SandboxGit $Sandbox.Repo @('update-ref', "refs/heads/$Branch", $Hash) | Out-Null
}

Test-Case 'Move-BranchRefSafely: fast-forwards the branch when expected-old matches and it is a true FF' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "a`n" -Message 'c1'
        $c2 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "b`n" -Message 'c2'   # c2 descends c1
        New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $c1
        $ok = Move-BranchRefSafely -Repository $sb.Repo -Branch 'feature/x' -ExpectedOldHash $c1 -NewHash $c2
        Assert-True $ok 'a true FF with matching expected-old must succeed'
        Assert-Equal $c2 (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/x') -Message 'feature/x must advance to c2'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'Move-BranchRefSafely: REFUSES and changes nothing when the ref moved since expected-old (stale CAS)' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "a`n" -Message 'c1'
        $c2 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "b`n" -Message 'c2'
        $c3 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "c`n" -Message 'c3'   # c3 descends c1
        New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $c1
        Set-SandboxBranchRef $sb 'feature/x' $c2     # a "concurrent" move: feature/x is now c2, not c1
        $ok = Move-BranchRefSafely -Repository $sb.Repo -Branch 'feature/x' -ExpectedOldHash $c1 -NewHash $c3
        Assert-False $ok 'a stale expected-old must refuse (the branch moved concurrently)'
        Assert-Equal $c2 (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/x') -Message 'feature/x must be UNCHANGED (the concurrent commit is not orphaned)'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'Move-BranchRefSafely: REFUSES a non-fast-forward target (never orphans a commit)' {
    $sb = New-GitSandbox
    try {
        $c0 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'c0'
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "a`n" -Message 'c1'   # main = c1 (descends c0)
        New-SandboxBranch -Sandbox $sb -Name 'sib' -StartPoint $c0
        Invoke-SandboxGit $sb.Repo @('switch', 'sib') | Out-Null
        $cs = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "sib`n" -Message 'sib'  # cs descends c0, sibling to c1
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $c1
        $ok = Move-BranchRefSafely -Repository $sb.Repo -Branch 'feature/x' -ExpectedOldHash $c1 -NewHash $cs
        Assert-False $ok 'a non-FF target must refuse'
        Assert-Equal $c1 (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/x') -Message 'feature/x must be unchanged on a refused non-FF'
    } finally { Remove-GitSandbox $sb }
}
