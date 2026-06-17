[CmdletBinding()] param([string]$Filter = '*')
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$runner = Join-Path $here 'Invoke-GitMergeToolsTests.ps1'
$hosts = @()
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
$wps  = Get-Command powershell.exe -ErrorAction SilentlyContinue
if ($pwsh) { $hosts += [pscustomobject]@{ Name = 'pwsh (7+)'; Exe = $pwsh.Source } }
if ($wps)  { $hosts += [pscustomobject]@{ Name = 'Windows PowerShell 5.1'; Exe = $wps.Source } }

$fail = 0
foreach ($h in $hosts) {
    Write-Host ''
    Write-Host ("########## $($h.Name) ##########") -ForegroundColor Magenta
    & $h.Exe -NoProfile -File $runner -Filter $Filter
    if ($LASTEXITCODE -ne 0) { $fail++ ; Write-Host ("FAILED under $($h.Name)") -ForegroundColor Red }
}
Write-Host ''
Write-Host ("Cross-runtime: {0}/{1} runtimes green" -f ($hosts.Count - $fail), $hosts.Count) -ForegroundColor Cyan
exit ([int]($fail -gt 0))
