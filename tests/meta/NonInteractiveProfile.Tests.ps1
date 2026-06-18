$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # tests/meta -> repo root

# Companion to the behavioral NonInteractiveProfile tests. GIT_TERMINAL_PROMPT has no clean per-process
# readback (it only changes behavior when git would otherwise prompt for credentials, which needs a real
# remote), so this meta-test pins the wiring in source: the shared Invoke-GitCommand must set it to '0'
# and must save/restore it so there is no global leak. The `-c` flags and GIT_EDITOR are covered
# behaviorally in tests/git/NonInteractiveProfile.Tests.ps1.
Test-Case 'Invoke-GitCommand wires GIT_TERMINAL_PROMPT=0 and save/restores it (non-interactive credential safety)' {
    $core = Join-Path (Join-Path $repoRoot 'Modules') 'GitMergeTools.Core.psm1'
    Assert-True (Test-Path -LiteralPath $core) -Message "Core module must exist: $core"
    $text = Get-Content -LiteralPath $core -Raw
    Assert-Match "GIT_TERMINAL_PROMPT'?\s*,?\s*'0'|GIT_TERMINAL_PROMPT[^\r\n]*=\s*'0'" $text -Message 'Invoke-GitCommand must set GIT_TERMINAL_PROMPT to 0'
    Assert-Match 'GIT_EDITOR' $text -Message 'Invoke-GitCommand must set a non-interactive GIT_EDITOR'
}
