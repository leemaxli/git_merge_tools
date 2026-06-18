. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# #1: git output must be decoded as UTF-8 regardless of the console code page. On a redirected stdout
# (agent pipe / non-tty) the console falls back to the system ANSI code page (cp936/GBK here), so a
# non-ASCII branch name read back from git mojibakes -- and `merge refs/heads/<mojibake>` then targets
# the wrong (or no) ref. `gitmerge all` must still integrate a branch whose name is non-ASCII.
Test-Case 'gitmerge all integrates a non-ASCII (CJK) branch name (#1 UTF-8 capture)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $cjk = [string][char]0x529F + [string][char]0x80FD   # two Han chars: a CJK branch name
        New-SandboxBranch -Sandbox $sb -Name $cjk -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', $cjk) | Out-Null
        $tip = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "work`n" -Message 'cjk work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-True $ok -Message 'gitmerge all should succeed'
        Assert-Equal $tip (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'main must integrate the CJK branch tip (its name must survive the UTF-8 round-trip)'
    }
    finally { Remove-GitSandbox $sb }
}

Test-Case 'gitsync all pushes a non-ASCII (CJK) branch name to origin (#1 UTF-8 capture)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $origin = Join-Path $sb.Root 'origin.git'
        Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
        $cjk = [string][char]0x529F + [string][char]0x80FD   # two Han chars
        New-SandboxBranch -Sandbox $sb -Name $cjk -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', $cjk) | Out-Null
        $tip = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "work`n" -Message 'cjk work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $sb
        Assert-True $ok -Message 'gitsync all should succeed'
        $ls = Invoke-SandboxGit $sb.Repo @('ls-remote', $origin, "refs/heads/$cjk")
        Assert-Match ([regex]::Escape($tip)) ((@($ls.Output) -join ' ')) -Message 'origin must receive the CJK branch (its name survived the UTF-8 round-trip)'
    }
    finally { Remove-GitSandbox $sb }
}
