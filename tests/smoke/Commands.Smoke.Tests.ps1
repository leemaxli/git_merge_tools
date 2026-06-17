. (Join-Path $PSScriptRoot 'Commands.Smoke.Tests.ps1.helper.ps1')

Test-Case 'gitstatus (current branch) returns true on a one-commit repo (basic visuals)' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -Content 'a' -Message 'init')
        $ok = Invoke-ProductCommand -Script 'gitstatus.ps1' -Func 'gitstatus' -Sandbox $sb
        Assert-True $ok 'gitstatus should return $true'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge debug returns true (dry-run, basic visuals)' {
    $sb = New-GitSandbox
    try {
        [void](New-SandboxCommit -Sandbox $sb -Content 'a' -Message 'init')
        New-SandboxBranch -Sandbox $sb -Name 'feature/x'
        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'debug' -Sandbox $sb
        Assert-True $ok 'gitmerge debug should return $true'
    } finally { Remove-GitSandbox $sb }
}

# DEFECT #1 (spec §2) — FIXED: the rich renderer used to crash at the first stage because the captured
# $stageIcon helper collided with the $StageIcon parameter (PS variables are case-insensitive), turning
# the call into `& 'SCAN' 'SCAN'` -> CommandNotFound. The helper was renamed to $resolveStageIcon.
# Invoking the full command under rich does NOT reliably select rich in a captured/non-interactive
# test (the rich capability gate fails), so we exercise the Rich renderer directly here for a
# deterministic reproduction.
Test-Case 'rich renderer WriteStage renders a stage icon without crashing (defect #1 fixed)' {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'GitMergeTools.Visual.Rich.psm1') -Force
    $r = New-GitMergeToolsVisualRich -CommandName 'gitmerge' -RequestedVisualMode 'rich' -RichUnavailableReasons @() -VisualWarningSuppressed:$true
    # Capture host output; must NOT throw (defect #1 was a $stageIcon/$StageIcon collision -> & 'SCAN' 'SCAN').
    & $r.WriteStage -Title 'PREFLIGHT' -Subtitle 'x' -StageIcon 'SCAN' -Color ([ConsoleColor]::Cyan) *> $null
    Assert-True $true 'WriteStage completed without throwing'
}
