. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# #3: gitsync builds its push set independently of the engine, so it would push (and report as
# "synced") a branch that gitmerge's #10 guard deliberately skipped — misreporting work that never
# entered main. gitsync must honor the same unmerged-descendant skip.
Test-Case 'gitsync does not push a branch the engine skips for an unmerged descendant (#3 / #10 consistency)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $origin = Join-Path $sb.Root 'origin.git'
        Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
        # feature/A ahead of main; feature/A-child descends from it with extra unmerged work (NOT selected).
        New-SandboxBranch -Sandbox $sb -Name 'feature/A' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/A') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A work'
        New-SandboxBranch -Sandbox $sb -Name 'feature/A-child' -StartPoint 'feature/A'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/A-child') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "child`n" -Message 'child work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        # gitsync feature/A: the engine skips feature/A (#10); gitsync must NOT push it to origin.
        $null = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'feature/A' -Sandbox $sb
        $ls = Invoke-SandboxGit $sb.Repo @('ls-remote', $origin, 'refs/heads/feature/A')
        Assert-Equal '' ((@($ls.Output) -join ' ').Trim()) -Message 'a skipped branch must not be pushed to origin (gitsync must honor the #10 skip)'
    }
    finally { Remove-GitSandbox $sb }
}
