$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repoRoot 'GitMergeTools.Common.psm1') -Force

function New-RtState {
    param([bool]$Ps7, [bool]$Ps7Available = $true, [bool]$Ps51Available = $true)
    [pscustomobject]@{
        IsPowerShell7        = $Ps7
        PowerShell7Available = $Ps7Available
        PowerShell51Available = $Ps51Available
        PowerShellEdition    = $(if ($Ps7) { 'Core' } else { 'Desktop' })
        PowerShellVersion    = $(if ($Ps7) { '7.6.2' } else { '5.1.26100.1' })
    }
}

function Invoke-RecSummary {
    param($RuntimeState, [string]$VisualLevel, [string[]]$Reasons = @())
    $prevA = $env:GITMERGE_TOOLS_SUPPRESS_WARNING; $prevB = $env:GITMERGE_VISUAL_SUPPRESS_WARNING
    Remove-Item -LiteralPath Env:GITMERGE_TOOLS_SUPPRESS_WARNING -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath Env:GITMERGE_VISUAL_SUPPRESS_WARNING -ErrorAction SilentlyContinue
    try {
        return ((Write-GitMergeToolsRecommendationSummary -CommandName 'gitmerge' -RuntimeState $RuntimeState -VisualLevel $VisualLevel -Reasons $Reasons) *>&1 | Out-String)
    }
    finally {
        if ($null -ne $prevA) { $env:GITMERGE_TOOLS_SUPPRESS_WARNING = $prevA }
        if ($null -ne $prevB) { $env:GITMERGE_VISUAL_SUPPRESS_WARNING = $prevB }
    }
}

# The reported bug: at the optimal max tier on PowerShell 7, there must be NO upgrade/recommendation noise.
Test-Case 'recommendation summary is SILENT at the optimal max tier on PowerShell 7' {
    $out = Invoke-RecSummary -RuntimeState (New-RtState -Ps7 $true) -VisualLevel 'max'
    Assert-Equal '' ($out.Trim()) -Message 'optimal (max + PS7) must produce no recommendation/upgrade output at all'
}

# Auto-selection always picks the best renderable tier, so ANY successful tier on PS7 is silent (no nag).
Test-Case 'recommendation summary is SILENT for a successfully selected rich tier on PowerShell 7' {
    $out = Invoke-RecSummary -RuntimeState (New-RtState -Ps7 $true) -VisualLevel 'rich'
    Assert-Equal '' ($out.Trim()) -Message 'a successfully selected tier on PS7 must not be nagged about'
}

# Off PowerShell 7, the (specific, actionable) runtime recommendation still surfaces.
Test-Case 'recommendation summary surfaces the PowerShell 7 runtime recommendation off PS7' {
    $out = Invoke-RecSummary -RuntimeState (New-RtState -Ps7 $false) -VisualLevel 'rich'
    Assert-Match 'PowerShell 7' $out -Message 'a non-PS7 runtime should still get the runtime recommendation'
    Assert-False ([bool]($out -match 'for rich visuals')) 'the generic "for rich visuals" nag must be gone'
}

# A hard failure (no renderer could load) must still report the concrete reasons.
Test-Case 'recommendation summary reports reasons when no renderer could load' {
    $out = Invoke-RecSummary -RuntimeState (New-RtState -Ps7 $true) -VisualLevel 'none' -Reasons @('GitMergeTools.Visual.Rich.psm1 was not found.')
    Assert-Match 'was not found' $out -Message 'a renderer load failure must surface its reason'
}
