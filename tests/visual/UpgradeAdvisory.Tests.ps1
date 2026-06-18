$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repoRoot 'GitMergeTools.Common.psm1') -Force

function New-AdvCap {
    param($cl = 1, $vt = $false, $u = $true, $rd = $false, $ci = $false, $nc = $false)
    [pscustomobject]@{ ColorLevel = $cl; HasVT = $vt; UnicodeOk = $u; IsRedirected = $rd; IsCI = $ci; NoColor = $nc }
}

Test-Case 'advisory: suppressed => no lines' {
    $lines = Get-GitMergeToolsUpgradeAdvisoryLines -AchievedTier 'basic' -RequestedMode 'rich' -Capability (New-AdvCap) -Suppressed $true
    Assert-Equal 0 @($lines).Count -Message 'suppressed must produce no advisory'
}

Test-Case 'advisory: auto requested => no nag even when only basic achieved' {
    $lines = Get-GitMergeToolsUpgradeAdvisoryLines -AchievedTier 'basic' -RequestedMode 'auto' -Capability (New-AdvCap) -Suppressed $false
    Assert-Equal 0 @($lines).Count -Message 'auto must never nag'
}

Test-Case 'advisory: achieved tier meets requested => no lines' {
    $lines = Get-GitMergeToolsUpgradeAdvisoryLines -AchievedTier 'rich' -RequestedMode 'rich' -Capability (New-AdvCap) -Suppressed $false
    Assert-Equal 0 @($lines).Count -Message 'met request => no advisory'
}

Test-Case 'advisory: pinned rich but basic achieved (no UTF-8) => advises UTF-8' {
    $lines = Get-GitMergeToolsUpgradeAdvisoryLines -AchievedTier 'basic' -RequestedMode 'rich' -Capability (New-AdvCap -u $false) -Suppressed $false
    Assert-True (@($lines).Count -gt 0) -Message 'rich below-pin must advise'
    Assert-Match 'UTF-8' ((@($lines) -join ' ')) -Message 'explains the missing UTF-8 for rich'
}
