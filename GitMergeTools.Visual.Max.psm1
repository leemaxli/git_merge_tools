[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseShouldProcessForStateChangingFunctions',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'This function constructs a renderer object and does not change system state.'
)][Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSProvideCommentHelp',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'This module contains the max visual renderer for interactive git tools.'
)]
param()

# Max is the top visual tier (gated on truecolor + VT + UTF-8, non-redirected/CI, no NO_COLOR).
# For now it delegates to the Rich renderer and re-tags the visual level as 'max'; the distinctive
# truecolor/OSC effects are layered onto this tier in P1c. Keeping it a thin delegator avoids
# duplicating the Rich renderer while the 4-tier selection framework lands.
function New-GitMergeToolsVisualMax {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Constructs a renderer object; changes no system state.'
    )]
    [CmdletBinding()]
    param(
        [string]$CommandName = 'gitmerge',
        [string]$RequestedVisualMode = 'auto',
        [string[]]$RichUnavailableReasons = @(),
        [bool]$VisualWarningSuppressed
    )

    Import-Module (Join-Path $PSScriptRoot 'GitMergeTools.Visual.Rich.psm1') -Force -ErrorAction Stop
    $renderer = New-GitMergeToolsVisualRich `
        -CommandName $CommandName `
        -RequestedVisualMode $RequestedVisualMode `
        -RichUnavailableReasons $RichUnavailableReasons `
        -VisualWarningSuppressed:$VisualWarningSuppressed
    $renderer.VisualLevel = 'max'
    return $renderer
}

Export-ModuleMember -Function New-GitMergeToolsVisualMax
