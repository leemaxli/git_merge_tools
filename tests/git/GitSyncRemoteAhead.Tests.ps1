. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v6.0 (Stage 1): when origin is ahead of local, gitsync must STOP with an actionable ACTION NEEDED prompt
# and change nothing (no local ref, no remote ref) -- replacing the old hard error exit. Auto-pull is later.
function New-OriginAheadSandbox {
    # Returns a sandbox whose local main is one commit BEHIND origin/main (a clean fast-forward), plus the
    # local tip (c1) and origin tip (c2) so the test can assert nothing moved.
    $sb = New-GitSandbox
    $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null            # origin/main = c1
    $c2 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "ahead`n" -Message 'c2'
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null            # origin/main = c2 (tracking ref too)
    Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null             # local main = c1 (behind origin)
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin; LocalTip = $c1; OriginTip = $c2 }
}

Test-Case 'gitsync stops with ACTION NEEDED when origin/main is ahead (v6.0); local + origin unchanged' {
    $ctx = New-OriginAheadSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-Match 'ACTION NEEDED' $out -Message 'origin-ahead must surface ACTION NEEDED, not a hard error'
        Assert-Match 'pull' $out -Message 'the prompt must be actionable (mention pull)'
        Assert-Equal $ctx.LocalTip (Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/main') -Message 'local main must be unchanged'
        $ls = Invoke-SandboxGit $ctx.Sandbox.Repo @('ls-remote', $ctx.Origin, 'refs/heads/main')
        Assert-Match ([regex]::Escape($ctx.OriginTip)) ((@($ls.Output) -join ' ')) -Message 'origin/main must be unchanged'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitsync returns $false on ACTION NEEDED (origin ahead) so command chains stop' {
    $ctx = New-OriginAheadSandbox
    try {
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-False $ok 'gitsync must return $false when a pull is required'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}
