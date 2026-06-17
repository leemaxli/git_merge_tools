$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Test-Case 'each entry script uses a truthy suppress-check (true/yes/on), not the literal -eq 1' {
    foreach ($script in 'gitmerge.ps1', 'gitsync.ps1', 'gitstatus.ps1') {
        $text = Get-Content -LiteralPath (Join-Path $repoRoot $script) -Raw
        Assert-False ($text -match "GITMERGE_TOOLS_SUPPRESS_WARNING\s*-eq\s*'1'") -Message "$script still uses the literal -eq '1' suppress check"
        Assert-Match 'function Test-GitMergeToolsSuppressWarningLocal' $text -Message "$script should define a local truthy suppress helper"
    }
}
