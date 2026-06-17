. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

Test-Case 'gitsync consolidates a feature branch and pushes it to origin, reporting success' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $origin = Join-Path $sb.Root 'origin.git'
        Assert-Equal 0 (Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin)).ExitCode -Message 'init bare origin'
        Assert-Equal 0 (Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin)).ExitCode -Message 'add origin'
        Assert-Equal 0 (Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main')).ExitCode -Message 'seed origin main'
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        $featTip = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "feature`n" -Message 'feature work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'feature/x' -Sandbox $sb
        Assert-True $ok -Message 'gitsync should return true on a clean consolidate+push'
        $lsMain = Invoke-SandboxGit $sb.Repo @('ls-remote', $origin, 'refs/heads/main')
        Assert-Match $featTip ((@($lsMain.Output) -join ' ')) -Message 'origin/main must hold the integrated feature tip'
    }
    finally { Remove-GitSandbox $sb }
}

Test-Case 'gitsync does not prune a local-only tag even with fetch.pruneTags=true configured (#2 non-destructive)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $origin = Join-Path $sb.Root 'origin.git'
        Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
        # adversarial repo config: prune tags on fetch (the destructive behavior #2 must neutralize)
        Invoke-SandboxGit $sb.Repo @('config', 'fetch.prune', 'true') | Out-Null
        Invoke-SandboxGit $sb.Repo @('config', 'fetch.pruneTags', 'true') | Out-Null
        Invoke-SandboxGit $sb.Repo @('tag', 'local-only-tag', $base) | Out-Null

        # current branch is main => gitsync pushes main only (its fetches must still not prune the tag)
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Sandbox $sb
        Assert-True $ok -Message 'gitsync should succeed'
        $tag = Invoke-SandboxGit $sb.Repo @('tag', '-l', 'local-only-tag')
        Assert-Match 'local-only-tag' ((@($tag.Output) -join ' ')) -Message 'local-only tag must survive (gitsync pins fetch.prune/pruneTags=false)'
    }
    finally { Remove-GitSandbox $sb }
}
