. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# Feature #10: a selected target with an unmerged descendant ("sub-branch") not itself selected is
# SKIPPED (not consolidated) with a clear warning — so its children's work is not silently left behind.
Test-Case 'gitmerge skips a target that has an unmerged descendant branch, and warns (#10)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        # feature/A: ahead of main
        New-SandboxBranch -Sandbox $sb -Name 'feature/A' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/A') | Out-Null
        $featA = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A work'
        # feature/A-child: descends from feature/A with extra (unmerged) work
        New-SandboxBranch -Sandbox $sb -Name 'feature/A-child' -StartPoint 'feature/A'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/A-child') | Out-Null
        $child = New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "child`n" -Message 'child work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $output = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/A' -Sandbox $sb

        # feature/A was skipped => main NOT advanced to feature/A's work; descendants untouched.
        Assert-Equal $base (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main must be unchanged (target was skipped)'
        Assert-Equal $featA (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/A') -Message 'feature/A untouched'
        Assert-Equal $child (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/A-child') -Message 'descendant untouched'
        Assert-Match "Skipping 'feature/A'" $output -Message 'must warn that the target was skipped'
        Assert-Match 'feature/A-child' $output -Message 'must name the unmerged descendant'
    }
    finally { Remove-GitSandbox $sb }
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
