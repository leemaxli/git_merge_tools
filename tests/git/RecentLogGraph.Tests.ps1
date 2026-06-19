. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.4 item 10: richer recent-log -- commit-chain graph + tier-aware color/emoji.
# Tests: Get-RecentCommitLines -Graph returns graph glyphs (*), gitmerge basic-tier output
# contains graph glyphs, Rich WriteRunSummary header has the 🌳 emoji, and basic-tier
# output does NOT contain 🌳 (portability / basic must stay ASCII-clean).

$graphTestRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# ---------------------------------------------------------------------------
# Helper: sandbox with a merge commit so --graph output contains *
# ---------------------------------------------------------------------------
function New-GraphSandbox {
    # Creates: main: A--B
    #          feature branched from A, gets commit C, then merged into main -> M
    # The resulting main log (--graph) shows a merge node (*)  and branch lines (| \).
    $sb = New-GitSandbox
    $null = New-SandboxCommit -Sandbox $sb -FileName 'base.txt' -Content "base`n" -Message "commit-A"
    $null = Invoke-SandboxGit $sb.Repo @('checkout', '-b', 'feature')
    $null = New-SandboxCommit -Sandbox $sb -FileName 'feat.txt' -Content "feat`n" -Message "commit-C"
    $null = Invoke-SandboxGit $sb.Repo @('checkout', 'main')
    $null = New-SandboxCommit -Sandbox $sb -FileName 'main2.txt' -Content "main2`n" -Message "commit-B"
    $null = Invoke-SandboxGit $sb.Repo @('merge', '--no-edit', 'feature')
    return $sb
}

# ---------------------------------------------------------------------------
# Data layer: Get-RecentCommitLines -Graph returns graph glyphs
# ---------------------------------------------------------------------------
Test-Case 'Get-RecentCommitLines -Graph returns lines containing graph glyph asterisk' {
    $sb = New-GraphSandbox
    try {
        Import-Module (Join-Path $graphTestRepoRoot 'Modules/GitMergeTools.Core.psm1') -Force -ErrorAction Stop
        $lines = Get-RecentCommitLines -Repository $sb.Repo -Branch 'main' -Graph
        $hasAsterisk = ($lines | Where-Object { $_ -match '\*' }).Count -gt 0
        Assert-True $hasAsterisk 'Get-RecentCommitLines -Graph must return at least one line containing * (commit node glyph)'
    } finally { Remove-GitSandbox $sb }
}

# ---------------------------------------------------------------------------
# Summaries via basic tier: graph glyph (*) appears; no 🌳 emoji (portability)
# ---------------------------------------------------------------------------
Test-Case 'gitmerge basic-tier summary recent-log contains graph glyph asterisk' {
    $sb = New-GraphSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Sandbox $sb
        Assert-Match '\*' $out -Message 'gitmerge basic summary recent-log must contain * graph glyph'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge basic-tier summary recent-log does NOT contain tree emoji' {
    $sb = New-GraphSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Sandbox $sb
        Assert-False ($out -match [regex]::Escape([System.String]::new([char[]](0xD83C, 0xDF33)))) 'basic-tier recent-log must NOT contain the 🌳 tree emoji (portability)'
    } finally { Remove-GitSandbox $sb }
}

# ---------------------------------------------------------------------------
# Rich tier: 🌳 header emoji present; Basic tier: no emoji (portability)
# ---------------------------------------------------------------------------
Test-Case 'Rich WriteRunSummary recent-log header contains tree emoji' {
    Import-Module (Join-Path $graphTestRepoRoot 'Modules/GitMergeTools.Visual.Rich.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualRich -CommandName 'gitmerge' -RequestedVisualMode 'rich' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = [pscustomobject]@{
        Parameter = 'all'; Stages = [System.Collections.Generic.List[string]]::new()
        Messages = [System.Collections.Generic.List[object]]::new()
        Result = 'SUCCESS'; MainBranch = 'main'; DryRun = $false; Mode = 'all'
        Repository = '/repo'; WorktreeCount = 1; LocalBranchCount = 2
        IntegratedBranches = [System.Collections.Generic.List[string]]::new()
        SynchronizedBranches = [System.Collections.Generic.List[string]]::new()
        SkippedBranches = [System.Collections.Generic.List[string]]::new()
        FailedBranches = [System.Collections.Generic.List[string]]::new()
        TargetBranches = [System.Collections.Generic.List[string]]::new()
        ConflictBranch = ''; CleanupStatus = 'CLEAN'
        Elapsed = [timespan]::Zero; FailureReason = ''; MainPublished = ''; SummaryEnabled = $true
    }
    # Provide a fake recent-lines array with a graph line to trigger the rendering block
    $fakeRecent = @('* abc1234 commit-M', '|\  ', '| * def5678 commit-C', '* 890abcd commit-B')
    $out = (& $v.WriteRunSummary -State $state -RecentLines $fakeRecent -Name 'gitmerge') *>&1 | Out-String
    $treeEmoji = [System.String]::new([char[]](0xD83C, 0xDF33))
    Assert-True ($out.Contains($treeEmoji)) 'Rich WriteRunSummary recent-log header must contain the 🌳 tree emoji'
}