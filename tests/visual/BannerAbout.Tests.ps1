. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# Repo root: tests/visual -> tests -> repo root (same pattern as the smoke helper).
$bannerTestRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

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

# Helper: assert only the full-span box border lines (╔...╗, ║...║, ╚...╝) are aligned.
# Uses Get-GitMergeToolsDisplayWidth (from Visual.Common) so wide glyphs (emoji) count as 2 columns.
# Logo-art lines (╗ embedded in short ASCII art) are excluded by requiring the line to start with
# one of the three border characters.
function Assert-FullBoxLinesAligned {
    param([string]$Output, [string]$Label)
    Import-Module (Join-Path $bannerTestRepoRoot 'Modules/GitMergeTools.Visual.Common.psm1') -Force -ErrorAction Stop
    $lines    = ($Output -split "`n") | ForEach-Object { $_.TrimEnd() }
    # Full-span box border lines start with ╔, ║, or ╚ (logo-art lines start with spaces).
    $boxLines = @($lines | Where-Object { $_ -match '^[╔║╚]' })
    Assert-True ($boxLines.Count -ge 3) ($Label + ': expected at least 3 full box-border lines, got ' + $boxLines.Count)
    $widths = $boxLines | ForEach-Object { Get-GitMergeToolsDisplayWidth $_ }
    $first  = $widths[0]
    $i = 0
    foreach ($w in $widths) {
        Assert-Equal $first $w -Message ($Label + ' box line ' + $i + ' display-width mismatch: expected ' + $first + ', got ' + $w)
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

# --- Banner alignment: every box border line in the run banner has equal display width ---
# Pre-fix: Standard used Width=58 giving lines of 62 vs 64-char borders (off by 2).
# Pre-fix: gitsync/gitstatus fallback boxes had hand-padded middle lines shorter than the borders.
# These tests catch either regression.
#
# The tests bypass capability gating (which downgrades to basic under redirected output) by
# constructing the Standard and Rich renderer objects DIRECTLY and capturing Write-Host via *>&1.
# This makes alignment assertions deterministic on both pwsh and Windows PowerShell 5.1.

Test-Case 'gitmerge banner box lines all have equal display width (standard tier)' {
    Import-Module (Join-Path $bannerTestRepoRoot 'Modules/GitMergeTools.Visual.Standard.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualStandard -CommandName 'gitmerge' -RequestedVisualMode 'standard' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $banner = $v.WriteRunBanner
    $out = (& $banner -DryRun:$true -Name 'gitmerge') *>&1 | Out-String
    Assert-BoxLinesAligned -Output $out -Label 'gitmerge-standard'
}

Test-Case 'gitsync banner box lines all have equal display width (standard tier)' {
    Import-Module (Join-Path $bannerTestRepoRoot 'Modules/GitMergeTools.Visual.Standard.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualStandard -CommandName 'gitsync' -RequestedVisualMode 'standard' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $banner = $v.WriteRunBanner
    $out = (& $banner -DryRun:$true -Name 'gitsync') *>&1 | Out-String
    Assert-BoxLinesAligned -Output $out -Label 'gitsync-standard'
}

Test-Case 'gitstatus banner box lines all have equal display width (standard tier)' {
    Import-Module (Join-Path $bannerTestRepoRoot 'Modules/GitMergeTools.Visual.Standard.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualStandard -CommandName 'gitstatus' -RequestedVisualMode 'standard' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $banner = $v.WriteRunBanner
    $out = (& $banner -DryRun:$true -Name 'gitstatus') *>&1 | Out-String
    Assert-BoxLinesAligned -Output $out -Label 'gitstatus-standard'
}

Test-Case 'gitmerge banner box lines all have equal display width (rich tier)' {
    Import-Module (Join-Path $bannerTestRepoRoot 'Modules/GitMergeTools.Visual.Rich.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualRich -CommandName 'gitmerge' -RequestedVisualMode 'rich' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $banner = $v.WriteRunBanner
    $out = (& $banner -DryRun:$true -Name 'gitmerge') *>&1 | Out-String
    Assert-FullBoxLinesAligned -Output $out -Label 'gitmerge-rich'
}
