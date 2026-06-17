Test-Case 'sandbox repo lives under the OS temp dir' {
    $sb = New-GitSandbox
    try {
        $tempC = Get-CanonicalPath ([System.IO.Path]::GetTempPath())
        $repoC = Get-CanonicalPath $sb.Repo
        Assert-True ($repoC.StartsWith($tempC, [System.StringComparison]::OrdinalIgnoreCase)) "repo '$repoC' not under temp '$tempC'"
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'containment guard REFUSES a path outside the sandbox' {
    $sb = New-GitSandbox
    try {
        $threw = $false
        try { Assert-PathInSandbox $sb (Join-Path ([System.IO.Path]::GetTempPath()) 'definitely-not-mine') } catch { $threw = $true }
        Assert-True $threw 'guard should refuse a path outside the sandbox root'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'containment guard ACCEPTS a path inside the sandbox' {
    $sb = New-GitSandbox
    try { Assert-PathInSandbox $sb (Join-Path $sb.Repo 'sub/file.txt') } finally { Remove-GitSandbox $sb }
}

Test-Case 'git in the sandbox resolves to a repo under temp (no GIT_DIR leak)' {
    $sb = New-GitSandbox
    try {
        $dir = Invoke-SandboxGit $sb.Repo @('rev-parse', '--absolute-git-dir')
        Assert-Equal 0 $dir.ExitCode
        $tempC = Get-CanonicalPath ([System.IO.Path]::GetTempPath())
        Assert-True ((Get-CanonicalPath $dir.Output[0]).StartsWith($tempC, [System.StringComparison]::OrdinalIgnoreCase)) 'git-dir escaped temp'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'global git config resolves only to the sandbox' {
    $sb = New-GitSandbox
    try {
        $origin = Invoke-SandboxGit $sb.Repo @('config', '--show-origin', '--get', 'user.email')
        Assert-Equal 0 $origin.ExitCode
        Assert-Match 'gmt-tests-' ($origin.Output -join ' ')
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'a non-ASCII branch name round-trips byte-exact through git capture' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -Content 'a' -Message 'init')
        $name = 'feature/caf' + [char]0x00E9 + '-' + [char]0x6D4B  # café-测
        New-SandboxBranch -Sandbox $sb -Name $name
        $listed = Invoke-SandboxGit $sb.Repo @('for-each-ref', '--format=%(refname:short)', 'refs/heads/')
        Assert-True (@($listed.Output) -contains $name) "branch '$name' did not round-trip; got: $($listed.Output -join ', ')"
    } finally { Remove-GitSandbox $sb }
}
