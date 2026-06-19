. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# Feature #10: a selected target with an unmerged descendant ("sub-branch") not itself selected is
# SKIPPED (not consolidated) with a clear warning -- so its children's work is not silently left behind.
# SCOPE: the #10 sub-branch-skip concept is retired across the v7 topology engines. Test 1 below
# verifies the 2-branch engine (Invoke-TwoBranchMerge) integrates a target that has a descendant,
# because a pure fast-forward leaves all descendant commits intact. Test 2 verifies the star engine
# (Invoke-StarMerge / `all` mode) integrates a descendant when it is itself a selected target --
# i.e. no skip occurs when the whole tree is in scope. Invoke-GitMergeConsolidation is removed.
Test-Case 'gitmerge {branch} converges even when the target has an unmerged descendant (v7.0: #10 skip retired for 2-branch)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'feature/A' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/A') | Out-Null
        $featA = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A work'
        New-SandboxBranch -Sandbox $sb -Name 'feature/A-child' -StartPoint 'feature/A'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/A-child') | Out-Null
        $child = New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "child`n" -Message 'child work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/A' -Sandbox $sb
        Assert-True $ok 'gitmerge feature/A should converge (no longer skips on an unmerged descendant)'
        Assert-Equal $featA (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main converges up to feature/A (it was behind)'
        Assert-Equal $featA (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/A') -Message 'feature/A unchanged (already the union)'
        Assert-Equal $child (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/A-child') -Message 'descendant untouched, all its work intact'
    } finally { Remove-GitSandbox $sb }
}

# In 'all' mode the descendant is itself a target, so the rule must NOT skip (everything is consolidated).
Test-Case 'gitmerge all does NOT skip when the descendant is also selected (#10)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'feature/A' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/A') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A work'
        New-SandboxBranch -Sandbox $sb -Name 'feature/A-child' -StartPoint 'feature/A'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/A-child') | Out-Null
        $child = New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "child`n" -Message 'child work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-True $ok -Message 'all-mode consolidation should succeed'
        # everything integrated => main reaches the deepest descendant tip
        Assert-Equal $child (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'all mode integrates the descendant too (no skip)'
    }
    finally { Remove-GitSandbox $sb }
}
