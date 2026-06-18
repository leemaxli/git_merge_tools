. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v6.8.0: every command summary should show 10 recent commits (was 5). We seed 12 commits commit-01..12
# (commit-12 newest). At depth 10 the log shows commit-12..commit-03, so 'commit-03' is present and
# 'commit-02' is not -- a depth that is exactly 10 (a red bar at the old -5, which stops at commit-08).
function New-RecentLogSandbox {
    $sb = New-GitSandbox
    for ($i = 1; $i -le 12; $i++) {
        $n = '{0:00}' -f $i
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "rev-$n`n" -Message "commit-$n"
    }
    return $sb
}

function New-RecentLogOriginSandbox {
    $sb = New-RecentLogSandbox
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
    return $sb
}

Test-Case 'gitmerge summary shows 10 recent commits (commit-03 visible, commit-02 not)' {
    $sb = New-RecentLogSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Sandbox $sb
        Assert-Match 'commit-03' $out -Message 'depth 10 must reach commit-03'
        Assert-False ($out -match 'commit-02') 'depth must cap at 10 (commit-02 must NOT appear)'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitstatus summary shows 10 recent commits (commit-03 visible, commit-02 not)' {
    $sb = New-RecentLogSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Sandbox $sb
        Assert-Match 'commit-03' $out -Message 'depth 10 must reach commit-03'
        Assert-False ($out -match 'commit-02') 'depth must cap at 10 (commit-02 must NOT appear)'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitsync summary shows a recent-commits block with 10 commits' {
    $sb = New-RecentLogOriginSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Sandbox $sb
        Assert-Match 'Recent commits on' $out -Message 'gitsync summary must include a recent-commits block'
        Assert-Match 'commit-03' $out -Message 'depth 10 must reach commit-03'
        Assert-False ($out -match 'commit-02') 'depth must cap at 10 (commit-02 must NOT appear)'
    } finally { Remove-GitSandbox $sb }
}
