$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Test-Case 'Import-GitMergeToolsRuntimeModule is idempotent (module-scoped cache guard present)' {
    $text = Get-Content -LiteralPath (Join-Path $repoRoot 'GitMergeTools.Common.psm1') -Raw
    Assert-Match 'GitMergeToolsRuntimeModuleLoaded' $text -Message 'expected a module-scoped cache guard for the runtime import'
}

Test-Case 'runtime state still resolves correctly after the caching change' {
    # Get-GitMergeToolsRuntimeState is module-internal (not exported); invoke it in module scope.
    $mod = Import-Module (Join-Path $repoRoot 'GitMergeTools.Common.psm1') -Force -PassThru
    $state = & $mod { Get-GitMergeToolsRuntimeState }
    Assert-True ($state.PowerShellVersion.Length -gt 0) 'runtime state must still resolve'
}
