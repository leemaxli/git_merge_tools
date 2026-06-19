. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.4-B: unified summary header (version + DRY-RUN/LIVE tag), Parameter line,
# Workflow chain, and collected Notices & warnings section across all three commands.

function New-BasicSandbox {
    $sb = New-GitSandbox
    $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $null = New-SandboxBranch -Sandbox $sb -Name 'feature/x'
    $null = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "feat`n" -Message 'feat'
    Invoke-SandboxGit $sb.Repo @('checkout', 'main') | Out-Null
    return $sb
}

function New-OriginSandboxForSync {
    $sb = New-GitSandbox
    $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $null = New-SandboxBranch -Sandbox $sb -Name 'feature/x'
    $null = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "feat`n" -Message 'feat'
    Invoke-SandboxGit $sb.Repo @('checkout', 'main') | Out-Null
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main', 'feature/x') | Out-Null
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin }
}

# ---------------------------------------------------------------------------
# GROUP 1: Parameter shown
# ---------------------------------------------------------------------------

Test-Case 'gitmerge all summary shows Parameter line containing "all"' {
    $sb = New-BasicSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-Match 'Parameter' $out -Message 'summary must include a Parameter line'
        Assert-Match '\ball\b' $out -Message 'Parameter line must show "all"'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge with no arg shows default Parameter label in summary' {
    $sb = New-BasicSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Sandbox $sb
        Assert-Match 'Parameter' $out -Message 'summary must include a Parameter line'
        Assert-Match 'default: current branch' $out -Message 'empty arg must show default label'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge <branch> summary shows the branch name in the Parameter line' {
    $sb = New-BasicSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature/x' -Sandbox $sb
        Assert-Match 'Parameter' $out -Message 'summary must include a Parameter line'
        Assert-Match 'feature/x' $out -Message 'Parameter line must show the branch name'
    } finally { Remove-GitSandbox $sb }
}

# ---------------------------------------------------------------------------
# GROUP 2: Version + unified header + DRY-RUN tag (item 4 bug fix)
# All THREE commands must show [DRY-RUN] in debug mode and [LIVE] in normal mode.
# ---------------------------------------------------------------------------

Test-Case 'gitmerge debug summary contains [DRY-RUN] and version v7.4.0' {
    $sb = New-BasicSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'debug' -Sandbox $sb
        Assert-Match '\[DRY-RUN\]' $out -Message 'gitmerge debug must show [DRY-RUN] in summary'
        Assert-Match 'v7\.4\.0' $out -Message 'gitmerge debug must show version in summary'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge live run summary contains [LIVE] and version v7.4.0' {
    $sb = New-BasicSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Sandbox $sb
        Assert-Match '\[LIVE\]' $out -Message 'gitmerge live run must show [LIVE] in summary'
        Assert-Match 'v7\.4\.0' $out -Message 'gitmerge live run must show version in summary'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitsync debug summary contains [DRY-RUN] and version v7.4.0' {
    $ctx = New-OriginSandboxForSync
    try {
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'debug' -Sandbox $ctx.Sandbox
        Assert-Match '\[DRY-RUN\]' $out -Message 'gitsync debug must show [DRY-RUN] in summary'
        Assert-Match 'v7\.4\.0' $out -Message 'gitsync debug must show version in summary'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitsync live run summary contains [LIVE] and version v7.4.0' {
    $ctx = New-OriginSandboxForSync
    try {
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Sandbox $ctx.Sandbox
        Assert-Match '\[LIVE\]' $out -Message 'gitsync live run must show [LIVE] in summary'
        Assert-Match 'v7\.4\.0' $out -Message 'gitsync live run must show version in summary'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitstatus debug summary contains [DRY-RUN] and version v7.4.0' {
    $sb = New-BasicSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Arg 'debug' -Sandbox $sb
        Assert-Match '\[DRY-RUN\]' $out -Message 'gitstatus debug must show [DRY-RUN] in summary'
        Assert-Match 'v7\.4\.0' $out -Message 'gitstatus debug must show version in summary'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitstatus live run summary contains [LIVE] and version v7.4.0' {
    $sb = New-BasicSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Sandbox $sb
        Assert-Match '\[LIVE\]' $out -Message 'gitstatus live run must show [LIVE] in summary'
        Assert-Match 'v7\.4\.0' $out -Message 'gitstatus live run must show version in summary'
    } finally { Remove-GitSandbox $sb }
}

# ---------------------------------------------------------------------------
# GROUP 3: Collected messages section (item 6)
# ---------------------------------------------------------------------------

Test-Case 'gitmerge all with skipped spoke shows Notices & warnings section' {
    # Build a sandbox with main and a spoke that conflicts with main.
    $sb = New-GitSandbox
    try {
        # Base commit on main.
        $null = New-SandboxCommit -Sandbox $sb -FileName 'shared.txt' -Content "base`n" -Message 'base on main'
        # Create and checkout the conflicting branch, then make a diverging change.
        $null = New-SandboxBranch -Sandbox $sb -Name 'conflicting'
        Invoke-SandboxGit $sb.Repo @('checkout', 'conflicting') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'shared.txt' -Content "conflicting side`n" -Message 'conflicting change'
        # Back to main, make an incompatible change to the same file.
        Invoke-SandboxGit $sb.Repo @('checkout', 'main') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'shared.txt' -Content "main side`n" -Message 'main update'
        # Now gitmerge all: the conflicting spoke should be skipped and a message collected.
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        # The run should include a Notices & warnings section with something about the conflicting branch.
        Assert-Match 'Notices.*warnings' $out -Message 'summary must contain a Notices & warnings section when a branch is skipped'
        Assert-Match 'conflicting' $out -Message 'the skipped branch name must appear in the messages section'
    } finally { Remove-GitSandbox $sb }
}

# ---------------------------------------------------------------------------
# GROUP 4: Workflow chain (item 9)
# ---------------------------------------------------------------------------

Test-Case 'gitmerge all summary contains a Workflow line with -> and multiple stages' {
    $sb = New-BasicSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-Match 'Workflow' $out -Message 'summary must include a Workflow line'
        Assert-Match '->' $out -Message 'Workflow line must use -> between stage names'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitsync live run summary contains a Workflow line' {
    $ctx = New-OriginSandboxForSync
    try {
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Sandbox $ctx.Sandbox
        Assert-Match 'Workflow' $out -Message 'gitsync summary must include a Workflow line'
        Assert-Match '->' $out -Message 'gitsync Workflow line must contain ->'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitstatus live run summary contains a Workflow line' {
    $sb = New-BasicSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Sandbox $sb
        Assert-Match 'Workflow' $out -Message 'gitstatus summary must include a Workflow line'
    } finally { Remove-GitSandbox $sb }
}
