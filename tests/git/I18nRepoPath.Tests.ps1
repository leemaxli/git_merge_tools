. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# P4 encoding/i18n: the tools must operate on repositories whose PATH contains spaces or non-ASCII
# (CJK) characters -- both are routine on the cp936/GBK Windows dev environment (e.g. localized user
# folders, "My Documents"). This exercises `git -C "<awkward path>"`, worktree creation, ref reads, and
# the path-containment guard end-to-end. The temporary integration worktree still lives under the system
# temp dir; what is stressed here is every -C and ref operation against the awkward repo path.

function New-NestedRepo {
    # Creates a second hermetic repo under the sandbox root at a caller-chosen (awkward) leaf name, and
    # returns a sandbox-shaped proxy so the existing helpers (New-SandboxCommit, Invoke-ProductCommand,
    # Get-SandboxRef) operate on it. Containment still keys on the real sandbox root.
    param([Parameter(Mandatory)]$Sandbox, [Parameter(Mandatory)][string]$LeafName)
    $repoPath = Join-Path $Sandbox.Root $LeafName
    New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
    $init = Invoke-SandboxGit $repoPath @('init', '-b', 'main')
    if ($init.ExitCode -ne 0) { throw "nested git init failed: $($init.Output -join '; ')" }
    return [pscustomobject]@{ Root = $Sandbox.Root; Repo = $repoPath; Home = $Sandbox.Home; DefaultBranch = 'main' }
}

function Test-ConsolidatesUnderPath {
    param([Parameter(Mandatory)]$Repo)
    $base = New-SandboxCommit -Sandbox $Repo -FileName 'f.txt' -Content "base`n" -Message 'base'
    New-SandboxBranch -Sandbox $Repo -Name 'feature/x' -StartPoint $base
    Invoke-SandboxGit $Repo.Repo @('switch', 'feature/x') | Out-Null
    $tip = New-SandboxCommit -Sandbox $Repo -FileName 'g.txt' -Content "work`n" -Message 'feature work'
    Invoke-SandboxGit $Repo.Repo @('switch', 'main') | Out-Null

    $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $Repo
    Assert-True $ok -Message 'gitmerge all must succeed regardless of the repo path'
    Assert-Equal $tip (Get-SandboxRef -Sandbox $Repo -Ref 'refs/heads/main') -Message 'main must integrate feature/x'
}

Test-Case 'gitmerge consolidates when the repository path contains spaces' {
    $sb = New-GitSandbox
    try {
        $repo = New-NestedRepo -Sandbox $sb -LeafName 'my repo with spaces'
        Test-ConsolidatesUnderPath -Repo $repo
    }
    finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge consolidates when the repository path contains non-ASCII (CJK) characters' {
    $sb = New-GitSandbox
    try {
        $cjk = 'repo-' + [string][char]0x4ED3 + [string][char]0x5E93   # 'repo-' + two Han chars
        $repo = New-NestedRepo -Sandbox $sb -LeafName $cjk
        Test-ConsolidatesUnderPath -Repo $repo
    }
    finally { Remove-GitSandbox $sb }
}

Test-Case 'gitstatus reads a repository whose path contains spaces (read-only)' {
    $sb = New-GitSandbox
    try {
        $repo = New-NestedRepo -Sandbox $sb -LeafName 'status path with spaces'
        $null = New-SandboxCommit -Sandbox $repo -FileName 'f.txt' -Content "base`n" -Message 'base'
        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Sandbox $repo
        Assert-Match 'Git root:' $out -Message 'gitstatus must resolve a spaced repo path'
        Assert-False ([bool]($out -match 'not inside a Git repository')) 'a spaced path must not derail repo resolution'
    }
    finally { Remove-GitSandbox $sb }
}
