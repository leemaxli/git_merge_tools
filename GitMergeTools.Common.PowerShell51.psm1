[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSProvideCommentHelp',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'This module contains Windows PowerShell 5.1 fallback helpers for git tools.'
)]
param()

function Get-GitMergeToolsPowerShell51RuntimeState {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        IsPowerShell7         = $false
        PowerShellVersion     = $PSVersionTable.PSVersion.ToString()
        PowerShellEdition     = $PSVersionTable.PSEdition
        PowerShell7Available  = [bool](Get-Command pwsh -ErrorAction SilentlyContinue)
        PowerShell51Available = [bool](Get-Command powershell.exe -ErrorAction SilentlyContinue)
    }
}

function Get-GitMergeToolsPowerShell51SearchDirectory {
    [CmdletBinding()]
    param(
        [string]$ToolsHome,
        [string]$BaseDirectory,
        [string]$ModuleDirectory,
        [string]$ProfileDirectory
    )

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $directories = New-Object 'System.Collections.Generic.List[string]'
    $myDocumentsPowerShell = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell'
    $homeDocumentsPowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path $HOME 'Documents') 'PowerShell' } else { $null }
    $oneDrivePowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path (Join-Path $HOME 'OneDrive') 'Documents') 'PowerShell' } else { $null }

    foreach ($candidate in @($ToolsHome, $BaseDirectory, $ModuleDirectory, $ProfileDirectory, $myDocumentsPowerShell, $homeDocumentsPowerShell, $oneDrivePowerShell)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
            if ($set.Add($resolved)) { $directories.Add($resolved) }
        }
    }
    return $directories.ToArray()
}

function Test-GitMergeToolsPowerShell51RichVisualEnvironment {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        IsAvailable = $false
        Reasons     = [string[]]@('PowerShell 7+ runtime is required for the preferred rich visual path.')
    }
}

Export-ModuleMember -Function @(
    'Get-GitMergeToolsPowerShell51RuntimeState',
    'Get-GitMergeToolsPowerShell51SearchDirectory',
    'Test-GitMergeToolsPowerShell51RichVisualEnvironment'
)
