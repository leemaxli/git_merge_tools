$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repoRoot 'GitMergeTools.Common.psm1') -Force

# The 'max' tier was folded into 'rich' and deleted (its truecolor/OSC effects were cut as eye-candy).
# GITMERGE_VISUAL_MODE=max stays a compatibility alias that resolves to rich; max no longer appears as a
# candidate, and the max gate function + renderer module are gone.
Test-Case 'GITMERGE_VISUAL_MODE=max is a compatibility alias that resolves to rich' {
    $mod = Get-Module GitMergeTools.Common
    Assert-Equal 'rich' (& $mod { ConvertTo-GitMergeToolsVisualMode 'max' }) -Message 'max resolves to rich'
}

Test-Case 'the visual candidate list no longer contains max (auto starts at rich)' {
    $mod = Get-Module GitMergeTools.Common
    $auto = & $mod { Get-GitMergeToolsVisualCandidates -RequestedMode 'auto' }
    Assert-Equal 'rich' $auto[0] -Message 'auto now starts at rich'
    Assert-False ([bool](@($auto) -contains 'max')) 'no max tier in the candidate list'
    Assert-Equal 3 @($auto).Count -Message 'three tiers remain: rich, standard, basic'
}

Test-Case 'the Max renderer module and the max gate function are gone' {
    Assert-False (Test-Path -LiteralPath (Join-Path $repoRoot 'GitMergeTools.Visual.Max.psm1')) -Message 'Visual.Max.psm1 deleted'
    Assert-False ([bool](Get-Command Test-GitMergeToolsMaxAvailable -ErrorAction SilentlyContinue)) 'Test-GitMergeToolsMaxAvailable removed'
}
