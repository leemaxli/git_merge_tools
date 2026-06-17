. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# Defect #6: gitmerge passed bareword branch names to git. git resolves a bareword to
# refs/tags/<name> BEFORE refs/heads/<name>, so a tag with the same name as the target branch
# would be integrated instead of the branch -> wrong content published to main (hard-constraint risk).
Test-Case 'gitmerge integrates the target BRANCH, not a same-named shadowing tag (#6)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        $featTip = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "feature-work`n" -Message 'feature work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        # a tag named exactly like the target branch, pointing at the OLD base (shadows the branch)
        Assert-Equal 0 (Invoke-SandboxGit $sb.Repo @('tag', 'feature/x', $base)).ExitCode -Message 'create shadowing tag'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/x' -Sandbox $sb
        Assert-True $ok -Message 'gitmerge should succeed'
        # main must contain the feature BRANCH work (clean FF => main tip == feature tip),
        # NOT stay stuck at base (which is what integrating the shadowing tag would produce).
        Assert-Equal $featTip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main must integrate the branch, not the tag'
    }
    finally { Remove-GitSandbox $sb }
}
