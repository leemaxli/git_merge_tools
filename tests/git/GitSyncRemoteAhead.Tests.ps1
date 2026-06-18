. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# gitsync stops with ACTION NEEDED (changing NOTHING) when origin has updates that cannot be safely
# auto-pulled. Conflicting divergence (origin and local both changed the same file) is the case that
# always prompts -- it is never auto-resolved (no rebase, no conflicting merge) through any v6.x stage,
# so it is the stable regression scenario for the prompt path.
function New-DivergedSandbox {
    $sb = New-GitSandbox
    $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
    $cOrigin = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "origin change`n" -Message 'origin work'
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null              # origin/main = cOrigin
    Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null
    $cLocal = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "local change`n" -Message 'local work'  # diverges (conflicting)
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin; LocalTip = $cLocal; OriginTip = $cOrigin }
}

Test-Case 'gitsync stops with ACTION NEEDED when origin has diverged from local; local + origin unchanged' {
    $ctx = New-DivergedSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-Match 'ACTION NEEDED' $out -Message 'divergence must surface ACTION NEEDED, not a hard error'
        Assert-Match 'diverged' $out -Message 'the prompt must name the divergence'
        Assert-Equal $ctx.LocalTip (Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/main') -Message 'local main must be unchanged'
        $ls = Invoke-SandboxGit $ctx.Sandbox.Repo @('ls-remote', $ctx.Origin, 'refs/heads/main')
        Assert-Match ([regex]::Escape($ctx.OriginTip)) ((@($ls.Output) -join ' ')) -Message 'origin/main must be unchanged'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitsync returns $false on ACTION NEEDED (divergence) so command chains stop' {
    $ctx = New-DivergedSandbox
    try {
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-False $ok 'gitsync must return $false when manual reconciliation is required'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}
