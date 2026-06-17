. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

Test-Case 'gitmerge does not prune a local-only tag even with fetch.pruneTags=true configured (#2 twin non-destructive)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $origin = Join-Path $sb.Root 'origin.git'
        Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
        # adversarial repo config: prune tags on fetch (the destructive behavior #2's twin must neutralize)
        Invoke-SandboxGit $sb.Repo @('config', 'fetch.prune', 'true') | Out-Null
        Invoke-SandboxGit $sb.Repo @('config', 'fetch.pruneTags', 'true') | Out-Null
        Invoke-SandboxGit $sb.Repo @('tag', 'local-only-tag', $base) | Out-Null

        # a feature branch to consolidate, so gitmerge runs Sync-MainFromOrigin (fetch origin) before merging
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "feature`n" -Message 'feature work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/x' -Sandbox $sb
        Assert-True $ok -Message 'gitmerge should succeed'
        $tag = Invoke-SandboxGit $sb.Repo @('tag', '-l', 'local-only-tag')
        Assert-Match 'local-only-tag' ((@($tag.Output) -join ' ')) -Message 'local-only tag must survive (gitmerge pins fetch.prune/pruneTags=false)'
    }
    finally { Remove-GitSandbox $sb }
}
