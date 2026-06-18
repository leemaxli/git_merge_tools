. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# Summary improvement: the gitsync / gitstatus run summary should show the REMOTE location (origin URL),
# not only the local repository path -- both commands interact with origin (push / compare), so the user
# should see where they are syncing against.
function New-OriginSandbox {
    $sb = New-GitSandbox
    $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin }
}

Test-Case 'gitsync summary shows the origin remote location (URL), not just the local path' {
    $ctx = New-OriginSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Sandbox $ctx.Sandbox
        Assert-Match 'Remote \(origin\)' $out -Message 'the summary must show the origin remote'
        Assert-Match ([regex]::Escape($ctx.Origin)) $out -Message 'the summary must show the origin URL/location'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitstatus summary shows the origin remote location (URL)' {
    $ctx = New-OriginSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Sandbox $ctx.Sandbox
        Assert-Match 'Remote \(origin\)' $out -Message 'the summary must show the origin remote'
        Assert-Match ([regex]::Escape($ctx.Origin)) $out -Message 'the summary must show the origin URL/location'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitstatus summary notes when there is no origin remote' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Sandbox $sb
        Assert-Match 'Remote \(origin\)' $out -Message 'the summary must show the origin remote line even with no origin'
        Assert-Match 'no origin remote' $out -Message 'with no origin, the summary should say so'
    } finally { Remove-GitSandbox $sb }
}
