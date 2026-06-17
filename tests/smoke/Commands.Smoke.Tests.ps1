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

# DOCUMENTED BUG #1 (spec §2): the rich renderer crashes at the first stage because the captured
# $stageIcon helper collides with the $StageIcon parameter (PS variables are case-insensitive).
# Invoking the full command under rich does NOT reliably select rich in a captured/non-interactive
# test (the rich capability gate fails), so we exercise the Rich renderer directly here for a
# deterministic reproduction. This is XFAIL until P1 fixes it.
Test-Case 'rich renderer WriteStage crashes on a stage icon (defect #1)' -KnownFail {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'GitMergeTools.Visual.Rich.psm1') -Force
    $r = New-GitMergeToolsVisualRich -CommandName 'gitmerge' -RequestedVisualMode 'rich' -RichUnavailableReasons @() -VisualWarningSuppressed:$true
    # Defect #1: captured $stageIcon collides with the $StageIcon parameter (PS vars are case-insensitive),
    # so this becomes `& 'SCAN' 'SCAN'` -> CommandNotFound. Once fixed it will NOT throw -> XPASS -> flip this test.
    & $r.WriteStage -Title 'PREFLIGHT' -Subtitle 'x' -StageIcon 'SCAN' -Color ([ConsoleColor]::Cyan)
}
