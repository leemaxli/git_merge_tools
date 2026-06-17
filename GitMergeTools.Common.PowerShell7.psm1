[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSProvideCommentHelp',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'This module contains PowerShell 7 runtime helpers for git tools.'
)]
param()

function Test-GitMergeToolsPowerShell7IsWindows {
    [CmdletBinding()]
    param()
    return ($PSVersionTable.Platform -eq 'Win32NT' -or $IsWindows)
}

function Get-GitMergeToolsPowerShell7RuntimeState {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        RuntimeLevel          = 'powershell7'
        IsPowerShell7         = $true
        PowerShellVersion     = $PSVersionTable.PSVersion.ToString()
        PowerShellEdition     = $PSVersionTable.PSEdition
        PowerShell7Available  = [bool](Get-Command pwsh -ErrorAction SilentlyContinue)
        PowerShell51Available = if (Test-GitMergeToolsPowerShell7IsWindows) { [bool](Get-Command powershell.exe -ErrorAction SilentlyContinue) } else { $false }
    }
}

function Get-GitMergeToolsPowerShell7SearchDirectory {
    [CmdletBinding()]
    param(
        [string]$ToolsHome,
        [string]$BaseDirectory,
        [string]$ModuleDirectory,
        [string]$ProfileDirectory
    )

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $directories = [System.Collections.Generic.List[string]]::new()
    $xdgPowerShell = if (-not [string]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME)) { Join-Path $env:XDG_CONFIG_HOME 'powershell' } else { $null }
    $homeConfigPowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path $HOME '.config') 'powershell' } else { $null }
    $homeDocumentsPowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path $HOME 'Documents') 'PowerShell' } else { $null }
    $windowsOneDrivePowerShell = if ((Test-GitMergeToolsPowerShell7IsWindows) -and -not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path (Join-Path $HOME 'OneDrive') 'Documents') 'PowerShell' } else { $null }

    foreach ($candidate in @($ToolsHome, $BaseDirectory, $ModuleDirectory, $ProfileDirectory, $xdgPowerShell, $homeConfigPowerShell, $homeDocumentsPowerShell, $windowsOneDrivePowerShell)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
            if ($set.Add($resolved)) { $directories.Add($resolved) }
        }
    }
    return $directories.ToArray()
}

function Test-GitMergeToolsPowerShell7RichVisualEnvironment {
    [CmdletBinding()]
    param()

    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
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

Export-ModuleMember -Function @(
    'Get-GitMergeToolsPowerShell7RuntimeState',
    'Get-GitMergeToolsPowerShell7SearchDirectory',
    'Test-GitMergeToolsPowerShell7RichVisualEnvironment'
)
