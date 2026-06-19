. (Join-Path $PSScriptRoot '..' 'smoke' 'Commands.Smoke.Tests.ps1.helper.ps1')

# Helper: display width for box-drawing lines (box chars and ASCII are all 1 display column, so .Length works).
function Get-Width { param([string]$s) $s.Length }

# Helper: extract box-drawing lines from output and assert they all have equal display width.
function Assert-BoxLinesAligned {
    param([string]$Output, [string]$Label)
    $lines    = ($Output -split "`n") | ForEach-Object { $_.TrimEnd() }
    $boxLines = @($lines | Where-Object { $_ -match '[╔╗╚╝║]' })
    Assert-True ($boxLines.Count -ge 3) ($Label + ': expected at least 3 box-drawing lines, got ' + $boxLines.Count)
    $widths = $boxLines | ForEach-Object { Get-Width $_ }
    $first  = $widths[0]
    $i = 0
    foreach ($w in $widths) {
        Assert-Equal $first $w -Message ($Label + ' box line ' + $i + ' width mismatch: expected ' + $first + ', got ' + $w)
        $i++
    }
}

# --- About-line assertions: version, repo, author appear in each command's output ---

Test-Case 'gitmerge output contains version v7.4.0, repo URL, and author' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -Content 'a' -Message 'init')
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'debug' -Sandbox $sb
        Assert-True ($out -match 'v7\.4\.0') 'gitmerge output should contain v7.4.0'
        Assert-True ($out -match 'github\.com/leemaxli/git_merge_tools') 'gitmerge output should contain repo URL'
        Assert-True ($out -match 'Leemax Li') 'gitmerge output should contain author'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitsync output contains version v7.4.0, repo URL, and author' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -Content 'a' -Message 'init')
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'debug' -Sandbox $sb
        Assert-True ($out -match 'v7\.4\.0') 'gitsync output should contain v7.4.0'
        Assert-True ($out -match 'github\.com/leemaxli/git_merge_tools') 'gitsync output should contain repo URL'
        Assert-True ($out -match 'Leemax Li') 'gitsync output should contain author'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitstatus output contains version v7.4.0, repo URL, and author' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -Content 'a' -Message 'init')
        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Sandbox $sb
        Assert-True ($out -match 'v7\.4\.0') 'gitstatus output should contain v7.4.0'
        Assert-True ($out -match 'github\.com/leemaxli/git_merge_tools') 'gitstatus output should contain repo URL'
        Assert-True ($out -match 'Leemax Li') 'gitstatus output should contain author'
    } finally { Remove-GitSandbox $sb }
}

# --- Banner alignment: every box-drawing line in the run banner has equal display width ---
# Standard visual (used in tests via basic->standard discovery) renders a box banner.
# Pre-fix: Standard used Width=58 giving lines of 62 vs 64-char borders (off by 2).
# Pre-fix: gitsync/gitstatus fallback boxes had hand-padded middle lines shorter than the borders.
# These tests catch either regression.

Test-Case 'gitmerge banner box lines all have equal display width (standard tier)' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -Content 'a' -Message 'init')
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'debug' -Sandbox $sb -VisualMode 'standard'
        Assert-BoxLinesAligned -Output $out -Label 'gitmerge'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitsync banner box lines all have equal display width (standard tier)' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -Content 'a' -Message 'init')
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'debug' -Sandbox $sb -VisualMode 'standard'
        Assert-BoxLinesAligned -Output $out -Label 'gitsync'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitstatus banner box lines all have equal display width (standard tier)' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -Content 'a' -Message 'init')
        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Sandbox $sb -VisualMode 'standard'
        Assert-BoxLinesAligned -Output $out -Label 'gitstatus'
    } finally { Remove-GitSandbox $sb }
}
