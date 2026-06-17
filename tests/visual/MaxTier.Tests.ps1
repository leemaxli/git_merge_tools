$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repoRoot 'GitMergeTools.Common.psm1') -Force

Test-Case 'max availability requires all six conditions (truecolor+VT+utf8, not redirected/CI, no NO_COLOR)' {
    function New-Cap($cl, $vt, $u, $rd, $ci, $nc) {
        [pscustomobject]@{ ColorLevel = $cl; HasVT = $vt; UnicodeOk = $u; IsRedirected = $rd; IsCI = $ci; NoColor = $nc }
    }
    Assert-True  (Test-GitMergeToolsMaxAvailable -Capability (New-Cap 3 $true $true $false $false $false)) -Message 'all conditions met => available'
    Assert-False (Test-GitMergeToolsMaxAvailable -Capability (New-Cap 2 $true $true $false $false $false)) -Message 'colorlevel < 3'
    Assert-False (Test-GitMergeToolsMaxAvailable -Capability (New-Cap 3 $false $true $false $false $false)) -Message 'no VT'
    Assert-False (Test-GitMergeToolsMaxAvailable -Capability (New-Cap 3 $true $false $false $false $false)) -Message 'no unicode'
    Assert-False (Test-GitMergeToolsMaxAvailable -Capability (New-Cap 3 $true $true $true $false $false)) -Message 'redirected'
    Assert-False (Test-GitMergeToolsMaxAvailable -Capability (New-Cap 3 $true $true $false $true $false)) -Message 'CI'
    Assert-False (Test-GitMergeToolsMaxAvailable -Capability (New-Cap 3 $true $true $false $false $true)) -Message 'NO_COLOR'
}

Test-Case 'visual candidates: auto and max start with max and list all four tiers' {
    $mod = Get-Module GitMergeTools.Common
    $auto = & $mod { Get-GitMergeToolsVisualCandidates -RequestedMode 'auto' }
    Assert-Equal 'max' $auto[0] -Message 'auto should try max first'
    Assert-Equal 4 $auto.Count -Message 'auto should have 4 tiers'
    $max = & $mod { Get-GitMergeToolsVisualCandidates -RequestedMode 'max' }
    Assert-Equal 4 $max.Count -Message 'max should have 4 tiers'
    $rich = & $mod { Get-GitMergeToolsVisualCandidates -RequestedMode 'rich' }
    Assert-Equal 3 $rich.Count -Message 'rich pin should NOT include max'
}

Test-Case 'GITMERGE_VISUAL_MODE=max resolves to the max mode' {
    $mod = Get-Module GitMergeTools.Common
    $resolved = & $mod { ConvertTo-GitMergeToolsVisualMode 'max' }
    Assert-Equal 'max' $resolved -Message 'max input maps to max mode'
}

Test-Case 'max renderer delegates to rich and is tagged max, renders a stage without crashing' {
    Import-Module (Join-Path $repoRoot 'GitMergeTools.Visual.Max.psm1') -Force
    $r = New-GitMergeToolsVisualMax -CommandName 'gitmerge' -RequestedVisualMode 'max' -RichUnavailableReasons @() -VisualWarningSuppressed:$true
    Assert-Equal 'max' $r.VisualLevel -Message 'renderer tagged max'
    Assert-True ($null -ne $r.WriteStage) -Message 'renderer has WriteStage'
    & $r.WriteStage -Title 'PREFLIGHT' -Subtitle 'y' -StageIcon 'SCAN' -Color ([ConsoleColor]::Cyan) *> $null
    Assert-True $true -Message 'WriteStage ran without throwing'
}
