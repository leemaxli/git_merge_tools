#requires -Version 5.1
[CmdletBinding()]
param([string]$Filter = '*')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }

Import-Module (Join-Path $here 'lib/TestHarness.psm1') -Force
Import-Module (Join-Path $here 'lib/GitSandbox.psm1') -Force
Reset-TestState

Write-Host ("Runtime: {0} {1}" -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion) -ForegroundColor Cyan

$testFiles = Get-ChildItem -LiteralPath $here -Recurse -Filter '*.Tests.ps1' |
    Where-Object { $_.Name -like $Filter } | Sort-Object FullName

foreach ($f in $testFiles) {
    Write-Host ''
    Write-Host ("== {0} ==" -f $f.FullName.Substring($here.Length).TrimStart('\','/')) -ForegroundColor White
    try { . $f.FullName }
    catch { Write-Host ("  [FAIL ] loading $($f.Name): $($_.Exception.Message)") -ForegroundColor Red }
}

try { Clear-AllSandboxes } catch { }
$code = Write-TestSummary
exit $code
