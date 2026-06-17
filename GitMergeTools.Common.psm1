[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSProvideCommentHelp',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'This module contains private helper functions for interactive profile scripts.'
)]
param()
function Test-GitMergeToolsTruthyEnv {
    param([string]$Value)
    return ($Value -in @('1', 'true', 'TRUE', 'yes', 'YES', 'on', 'ON'))
}

function Test-GitMergeToolsSuppressWarning {
    return (
        (Test-GitMergeToolsTruthyEnv $env:GITMERGE_TOOLS_SUPPRESS_WARNING) -or
        (Test-GitMergeToolsTruthyEnv $env:GITMERGE_VISUAL_SUPPRESS_WARNING)
    )
}

function Import-GitMergeToolsRuntimeModule {
    [CmdletBinding()]
    param()

    $runtimeModuleName = if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -ge 7) {
        'GitMergeTools.Common.PowerShell7.psm1'
    }
    else {
        'GitMergeTools.Common.PowerShell51.psm1'
    }
    $runtimeModulePath = Join-Path $PSScriptRoot $runtimeModuleName
    if (Test-Path -LiteralPath $runtimeModulePath) {
        Import-Module $runtimeModulePath -Force -ErrorAction Stop
        return $runtimeModuleName
    }
    return $null
}

function ConvertTo-GitMergeToolsVisualMode {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return 'auto' }
    switch ($Value.Trim().ToLowerInvariant()) {
        'a' { 'rich'; break }
        'rich' { 'rich'; break }
        'full' { 'rich'; break }
        'emoji' { 'rich'; break }
        'b' { 'standard'; break }
        'standard' { 'standard'; break }
        'current' { 'standard'; break }
        'enhanced' { 'standard'; break }
        'c' { 'basic'; break }
        'basic' { 'basic'; break }
        'fallback' { 'basic'; break }
        'plain' { 'basic'; break }
        default { 'auto' }
    }
}

function Get-GitMergeToolsBaseDirectory {
    param(
        [string]$ScriptRoot,
        [Alias('PSCommandPath')]
        [string]$ToolPSCommandPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ScriptRoot)) {
        return $ScriptRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($ToolPSCommandPath)) {
        return Split-Path -Parent $ToolPSCommandPath
    }
    return (Get-Location).Path
}

function Get-GitMergeToolsSearchDirectory {
    [CmdletBinding()]
    param(
        [string]$ScriptRoot,
        [Alias('PSCommandPath')]
        [string]$ToolPSCommandPath
    )

    $profileDirectory = $null
    if (-not [string]::IsNullOrWhiteSpace($PROFILE)) {
        $profileDirectory = Split-Path -Parent $PROFILE
    }
    $baseDirectory = Get-GitMergeToolsBaseDirectory -ScriptRoot $ScriptRoot -PSCommandPath $ToolPSCommandPath

    $runtimeModule = Import-GitMergeToolsRuntimeModule
    if ($runtimeModule -eq 'GitMergeTools.Common.PowerShell7.psm1') {
        return Get-GitMergeToolsPowerShell7SearchDirectory -ToolsHome $env:GITMERGE_TOOLS_HOME -BaseDirectory $baseDirectory -ModuleDirectory $PSScriptRoot -ProfileDirectory $profileDirectory
    }
    if ($runtimeModule -eq 'GitMergeTools.Common.PowerShell51.psm1') {
        return Get-GitMergeToolsPowerShell51SearchDirectory -ToolsHome $env:GITMERGE_TOOLS_HOME -BaseDirectory $baseDirectory -ModuleDirectory $PSScriptRoot -ProfileDirectory $profileDirectory
    }

    $isWindowsRuntime = ($PSVersionTable.PSEdition -eq 'Desktop' -or $PSVersionTable.Platform -eq 'Win32NT' -or $IsWindows)
    $xdgPowerShell = if (-not [string]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME)) { Join-Path $env:XDG_CONFIG_HOME 'powershell' } else { $null }
    $homeConfigPowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path $HOME '.config') 'powershell' } else { $null }
    $homeDocumentsPowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path $HOME 'Documents') 'PowerShell' } else { $null }
    $windowsDocumentsPowerShell = if ($isWindowsRuntime) { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell' } else { $null }
    $windowsOneDrivePowerShell = if ($isWindowsRuntime -and -not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path (Join-Path $HOME 'OneDrive') 'Documents') 'PowerShell' } else { $null }
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $directories = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @(
            $env:GITMERGE_TOOLS_HOME,
            $baseDirectory,
            $PSScriptRoot,
            $profileDirectory,
            $xdgPowerShell,
            $homeConfigPowerShell,
            $homeDocumentsPowerShell,
            $windowsDocumentsPowerShell,
            $windowsOneDrivePowerShell
        )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
            if ($set.Add($resolved)) {
                $directories.Add($resolved)
            }
        }
    }

    return $directories.ToArray()
}

function Resolve-GitMergeToolsModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [string]$ExplicitPath,

        [string]$ScriptRoot,

        [Alias('PSCommandPath')]
        [string]$ToolPSCommandPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath) -and (Test-Path -LiteralPath $ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    foreach ($directory in Get-GitMergeToolsSearchDirectory -ScriptRoot $ScriptRoot -PSCommandPath $ToolPSCommandPath) {
        $candidate = Join-Path $directory $ModuleName
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Resolve-GitMergeToolsScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName,

        [string]$ExplicitPath,

        [string]$ScriptRoot,

        [Alias('PSCommandPath')]
        [string]$ToolPSCommandPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath) -and (Test-Path -LiteralPath $ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    foreach ($directory in Get-GitMergeToolsSearchDirectory -ScriptRoot $ScriptRoot -PSCommandPath $ToolPSCommandPath) {
        $candidate = Join-Path $directory $ScriptName
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Get-GitMergeToolsRuntimeState {
    [CmdletBinding()]
    param()

    $runtimeModule = Import-GitMergeToolsRuntimeModule
    if ($runtimeModule -eq 'GitMergeTools.Common.PowerShell7.psm1') {
        return Get-GitMergeToolsPowerShell7RuntimeState
    }
    if ($runtimeModule -eq 'GitMergeTools.Common.PowerShell51.psm1') {
        return Get-GitMergeToolsPowerShell51RuntimeState
    }

    $isPwsh7 = ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -ge 7)
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    $runtimeLevel = if ($isPwsh7) { 'powershell7' } elseif ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell51' } else { 'unknown' }

    [pscustomobject]@{
        RuntimeLevel          = $runtimeLevel
        IsPowerShell7         = $isPwsh7
        PowerShellVersion     = $PSVersionTable.PSVersion.ToString()
        PowerShellEdition     = $PSVersionTable.PSEdition
        PowerShell7Available  = [bool]$pwsh
        PowerShell51Available = [bool]$windowsPowerShell
    }
}

function Test-GitMergeToolsRichVisualEnvironment {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RuntimeState)

    $runtimeModule = Import-GitMergeToolsRuntimeModule
    if ($runtimeModule -eq 'GitMergeTools.Common.PowerShell7.psm1') {
        return Test-GitMergeToolsPowerShell7RichVisualEnvironment
    }
    if ($runtimeModule -eq 'GitMergeTools.Common.PowerShell51.psm1') {
        return Test-GitMergeToolsPowerShell51RichVisualEnvironment
    }

    $reasons = [System.Collections.Generic.List[string]]::new()
    if (-not $RuntimeState.IsPowerShell7) {
        $reasons.Add('PowerShell 7+ runtime is required for the preferred rich visual path.')
    }
    if ($null -eq [Console]::OutputEncoding -or [Console]::OutputEncoding.WebName -notmatch 'utf') {
        $reasons.Add('Console OutputEncoding is not UTF-8.')
    }
    if ($null -eq [Console]::InputEncoding -or [Console]::InputEncoding.WebName -notmatch 'utf') {
        $reasons.Add('Console InputEncoding is not UTF-8.')
    }
    $hasCapableTerminal = (
        -not [string]::IsNullOrWhiteSpace($env:WT_SESSION) -or
        -not [string]::IsNullOrWhiteSpace($env:TERM_PROGRAM) -or
        (-not [string]::IsNullOrWhiteSpace($env:TERM) -and $env:TERM -ne 'dumb')
    )
    if (-not $hasCapableTerminal) {
        $reasons.Add('Terminal capability detection did not find Windows Terminal or a capable TERM.')
    }

    [pscustomobject]@{
        IsAvailable = ($reasons.Count -eq 0)
        Reasons     = [string[]]$reasons.ToArray()
    }
}

function Get-GitMergeToolsVisualCandidates {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns',
        '',
        Justification = 'The function returns an ordered candidate list.'
    )]
    param([string]$RequestedMode)

    switch ($RequestedMode) {
        'basic' { return @('basic') }
        'standard' { return @('standard', 'basic') }
        'rich' { return @('rich', 'standard', 'basic') }
        default { return @('rich', 'standard', 'basic') }
    }
}

function Write-GitMergeToolsRecommendationSummary {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'These scripts intentionally render interactive summary notices.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        $RuntimeState,

        [string]$VisualLevel,

        [string[]]$Reasons = @()
    )

    if (Test-GitMergeToolsSuppressWarning) { return }

    $needsSummary = (-not $RuntimeState.IsPowerShell7 -or $VisualLevel -ne 'rich' -or @($Reasons).Count -gt 0)
    if (-not $needsSummary) { return }

    Write-Warning "GitMergeTools recommendation summary for $CommandName"
    Write-Host ("  Runtime                  : {0} {1}" -f $RuntimeState.PowerShellEdition, $RuntimeState.PowerShellVersion) -ForegroundColor Yellow
    Write-Host ("  Visual level             : {0}" -f $VisualLevel) -ForegroundColor Yellow
    foreach ($reason in @($Reasons)) {
        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            Write-Host "  Reason                   : $reason" -ForegroundColor Yellow
        }
    }
    if (-not $RuntimeState.IsPowerShell7) {
        if ($RuntimeState.PowerShell7Available) {
            Write-Host "  Recommendation           : run $CommandName from pwsh / PowerShell 7 for the preferred runtime." -ForegroundColor Yellow
        }
        else {
            Write-Host '  Recommendation           : install PowerShell 7+ so the preferred runtime is available.' -ForegroundColor Yellow
        }
    }
    if ($RuntimeState.IsPowerShell7 -and -not $RuntimeState.PowerShell51Available) {
        Write-Host '  Fallback note            : Windows PowerShell 5.1 was not found; PowerShell 7 is active.' -ForegroundColor Yellow
    }
    if ($VisualLevel -ne 'rich') {
        Write-Host '  Recommendation           : use PowerShell 7+, UTF-8 input/output, and a Unicode-capable terminal for rich visuals.' -ForegroundColor Yellow
        Write-Host "  Visual preference         : unset `$env:GITMERGE_VISUAL_MODE for auto, or set it to rich, standard, or basic." -ForegroundColor Yellow
    }
    Write-Host "  Suppress notice           : `$env:GITMERGE_TOOLS_SUPPRESS_WARNING='1'" -ForegroundColor DarkGray
}

function New-GitMergeToolsVisual {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This function constructs a renderer object and does not change Git or filesystem state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [string]$ScriptRoot,

        [Alias('PSCommandPath')]
        [string]$ToolPSCommandPath
    )

    $runtime = Get-GitMergeToolsRuntimeState
    $requestedMode = ConvertTo-GitMergeToolsVisualMode $env:GITMERGE_VISUAL_MODE
    $richState = Test-GitMergeToolsRichVisualEnvironment -RuntimeState $runtime
    $fallbackReasons = [System.Collections.Generic.List[string]]::new()
    $selectedMode = $null
    $selectedModule = $null

    foreach ($candidate in Get-GitMergeToolsVisualCandidates -RequestedMode $requestedMode) {
        $moduleName = "GitMergeTools.Visual.$($candidate.Substring(0, 1).ToUpperInvariant())$($candidate.Substring(1)).psm1"
        $explicit = $null
        if ($candidate -eq 'rich') { $explicit = $env:GITMERGE_TOOLS_VISUAL_RICH_MODULE }
        elseif ($candidate -eq 'standard') { $explicit = $env:GITMERGE_TOOLS_VISUAL_STANDARD_MODULE }
        elseif ($candidate -eq 'basic') { $explicit = $env:GITMERGE_TOOLS_VISUAL_BASIC_MODULE }

        $modulePath = Resolve-GitMergeToolsModule -ModuleName $moduleName -ExplicitPath $explicit -ScriptRoot $ScriptRoot -PSCommandPath $ToolPSCommandPath
        if ([string]::IsNullOrWhiteSpace($modulePath)) {
            $fallbackReasons.Add("$moduleName was not found.")
            continue
        }
        if ($candidate -eq 'rich' -and -not $richState.IsAvailable) {
            foreach ($reason in @($richState.Reasons)) { $fallbackReasons.Add($reason) }
            continue
        }
        if ($candidate -eq 'standard') {
            $utf8Ok = ($null -ne [Console]::OutputEncoding -and [Console]::OutputEncoding.WebName -match 'utf')
            if (-not $utf8Ok) {
                $fallbackReasons.Add('Console OutputEncoding is not UTF-8; standard box-drawing is unavailable.')
                continue
            }
        }

        $selectedMode = $candidate
        $selectedModule = $modulePath
        break
    }

    if ([string]::IsNullOrWhiteSpace($selectedModule)) {
        Write-GitMergeToolsRecommendationSummary -CommandName $CommandName -RuntimeState $runtime -VisualLevel 'none' -Reasons ([string[]]$fallbackReasons.ToArray())
        return $null
    }

    try {
        Import-Module $selectedModule -Force -ErrorAction Stop
        $factory = "New-GitMergeToolsVisual$($selectedMode.Substring(0, 1).ToUpperInvariant())$($selectedMode.Substring(1))"
        $renderer = & $factory `
            -CommandName $CommandName `
            -RequestedVisualMode $requestedMode `
            -RichUnavailableReasons ([string[]]$fallbackReasons.ToArray()) `
            -VisualWarningSuppressed:(Test-GitMergeToolsSuppressWarning)

        Write-GitMergeToolsRecommendationSummary -CommandName $CommandName -RuntimeState $runtime -VisualLevel $selectedMode -Reasons ([string[]]$fallbackReasons.ToArray())
        return $renderer
    }
    catch {
        $fallbackReasons.Add("$selectedModule could not be loaded. $($_.Exception.Message)")
        Write-GitMergeToolsRecommendationSummary -CommandName $CommandName -RuntimeState $runtime -VisualLevel 'none' -Reasons ([string[]]$fallbackReasons.ToArray())
        return $null
    }
}

Export-ModuleMember -Function @(
    'New-GitMergeToolsVisual',
    'Resolve-GitMergeToolsScript',
    'Resolve-GitMergeToolsModule',
    'Write-GitMergeToolsRecommendationSummary'
)
