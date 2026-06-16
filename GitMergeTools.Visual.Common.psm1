[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'These visual modules intentionally render interactive console output.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseShouldProcessForStateChangingFunctions',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'These visual helpers construct renderer objects and do not change system state.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseOutputTypeCorrectly',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'These helpers return small internal renderer/context objects.'
)][Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSProvideCommentHelp',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'This module contains shared helpers for visual renderer modules.'
)]
param()

function New-GitMergeToolsVisualTheme {
    [CmdletBinding()]
    param()

    return @{
        Banner       = [ConsoleColor]::Cyan
        BannerDry    = [ConsoleColor]::Magenta
        Divider      = [ConsoleColor]::DarkGray
        Info         = [ConsoleColor]::DarkGray
        Success      = [ConsoleColor]::Green
        Warning      = [ConsoleColor]::Yellow
        Error        = [ConsoleColor]::Red
        Highlight    = [ConsoleColor]::White
        MainBranch   = [ConsoleColor]::Green
        TargetBranch = [ConsoleColor]::Yellow
        Progress     = [ConsoleColor]::Cyan
    }
}

function Get-GitMergeToolsCommandDescription {
    [CmdletBinding()]
    param([string]$Name)

    switch ($Name.ToLowerInvariant()) {
        'gitstatus' { 'Enhanced status, log, and comparisons'; break }
        'gitsync' { 'Merge, synchronize, and push safely'; break }
        default { 'Merge, synchronize, and safety checks' }
    }
}

function Get-GitMergeToolsMarkerColor {
    [CmdletBinding()]
    param(
        [string]$Marker,
        [ConsoleColor]$DefaultColor = [ConsoleColor]::Gray,
        [Parameter(Mandatory)]
        [hashtable]$Theme
    )

    switch ($Marker) {
        '✓' { $Theme.Success; break }
        '✔' { $Theme.Success; break }
        'OK' { $Theme.Success; break }
        '→' { [ConsoleColor]::Cyan; break }
        '◇' { [ConsoleColor]::Magenta; break }
        '✗' { $Theme.Error; break }
        '✘' { $Theme.Error; break }
        'FAIL' { $Theme.Error; break }
        '↺' { $Theme.Info; break }
        default { $DefaultColor }
    }
}

function New-GitMergeToolsVisualContext {
    [CmdletBinding()]
    param(
        [string]$CommandName = 'gitmerge',
        [Parameter(Mandatory)]
        [ValidateSet('rich', 'standard', 'basic')]
        [string]$VisualLevel,
        [string]$RequestedVisualMode = 'auto',
        [string[]]$RichUnavailableReasons = @(),
        [bool]$VisualWarningSuppressed
    )

    $reasonList = [System.Collections.Generic.List[string]]::new()
    foreach ($reason in @($RichUnavailableReasons)) {
        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            $reasonList.Add($reason)
        }
    }

    return [pscustomobject]@{
        Name = $CommandName
        VisualLevel = $VisualLevel
        RequestedVisualMode = $RequestedVisualMode
        RichUnavailableReasons = [string[]]$reasonList.ToArray()
        VisualWarningSuppressed = $VisualWarningSuppressed
        Theme = New-GitMergeToolsVisualTheme
        NoticeShown = $false
    }
}

function Write-GitMergeToolsRichFallbackNotice {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'These scripts intentionally render interactive visual fallback notices.'
    )]
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    if ($Context.NoticeShown -or $Context.VisualWarningSuppressed) { return }
    if ($Context.VisualLevel -eq 'rich') { return }
    if ($Context.RequestedVisualMode -notin @('auto', 'rich')) { return }

    $Context.NoticeShown = $true
    $reasonText = if (@($Context.RichUnavailableReasons).Count -gt 0) {
        @($Context.RichUnavailableReasons) -join ' '
    }
    else {
        "Visual mode is set to '$($Context.VisualLevel)'."
    }
    Write-Warning "Rich git visual mode is not active. $reasonText"
    Write-Host '  Use PowerShell 7+, UTF-8 input/output, and a Unicode-capable terminal to enable rich visuals.' -ForegroundColor Yellow
    Write-Host "  Preferred mode: unset `$env:GITMERGE_VISUAL_MODE for auto, or set it to 'rich', 'standard', or 'basic'." -ForegroundColor Yellow
    Write-Host "  To hide this notice: `$env:GITMERGE_TOOLS_SUPPRESS_WARNING='1'" -ForegroundColor DarkGray
}

function New-GitMergeToolsVisualObject {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This function constructs a renderer object and does not change system state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][hashtable]$Icons,
        [Parameter(Mandatory)][scriptblock]$WriteRunBanner,
        [Parameter(Mandatory)][scriptblock]$WriteStage,
        [Parameter(Mandatory)][scriptblock]$WriteStatusLine,
        [Parameter(Mandatory)][scriptblock]$WriteMiniProgress,
        [Parameter(Mandatory)][scriptblock]$WriteBranchTree,
        [Parameter(Mandatory)][scriptblock]$WriteSuccessBanner,
        [Parameter(Mandatory)][scriptblock]$WriteRunSummary
    )

    return [pscustomobject]@{
        Name = $Context.Name
        VisualLevel = $Context.VisualLevel
        RequestedVisualMode = $Context.RequestedVisualMode
        RichUnavailableReasons = [string[]]@($Context.RichUnavailableReasons)
        VisualWarningSuppressed = $Context.VisualWarningSuppressed
        Theme = $Context.Theme
        Icons = $Icons
        WriteRunBanner = $WriteRunBanner
        WriteStage = $WriteStage
        WriteStatusLine = $WriteStatusLine
        WriteMiniProgress = $WriteMiniProgress
        WriteBranchTree = $WriteBranchTree
        WriteSuccessBanner = $WriteSuccessBanner
        WriteRunSummary = $WriteRunSummary
    }
}

Export-ModuleMember -Function @(
    'New-GitMergeToolsVisualContext',
    'New-GitMergeToolsVisualObject',
    'Get-GitMergeToolsCommandDescription',
    'Get-GitMergeToolsMarkerColor',
    'Write-GitMergeToolsRichFallbackNotice'
)
