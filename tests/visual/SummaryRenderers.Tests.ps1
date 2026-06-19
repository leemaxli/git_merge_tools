. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.4-B: Standard and Rich WriteRunSummary content tests.
# Constructs renderers DIRECTLY (bypasses capability gating) to assert that the unified
# header (version + DRY-RUN/LIVE tag), Parameter line, Workflow chain, and Notices section
# are all present in Standard and Rich tier summary output.
#
# Mirrors the direct-construction pattern in tests/visual/BannerAbout.Tests.ps1.

$summaryTestRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function New-TestRunState {
    return [pscustomobject]@{
        Parameter          = 'all'
        Stages             = [System.Collections.Generic.List[string]](@('PREFLIGHT', 'MERGE', 'PUBLISH'))
        Messages           = [System.Collections.Generic.List[object]](@([pscustomobject]@{ Level = 'WARNING'; Text = 'Skipped X: conflict' }))
        Result             = 'SUCCESS'
        MainBranch         = 'main'
        DryRun             = $false
        Mode               = 'all'
        Repository         = '/repo'
        WorktreeCount      = 1
        LocalBranchCount   = 2
        IntegratedBranches = [System.Collections.Generic.List[string]]::new()
        SynchronizedBranches = [System.Collections.Generic.List[string]]::new()
        SkippedBranches    = [System.Collections.Generic.List[string]]::new()
        FailedBranches     = [System.Collections.Generic.List[string]]::new()
        TargetBranches     = [System.Collections.Generic.List[string]]::new()
        ConflictBranch     = ''
        CleanupStatus      = 'CLEAN'
        Elapsed            = [timespan]::Zero
        FailureReason      = ''
        MainPublished      = ''
        SummaryEnabled     = $true
    }
}

# ---------------------------------------------------------------------------
# Standard tier: WriteRunSummary content
# ---------------------------------------------------------------------------

Test-Case 'Standard WriteRunSummary contains version v7.4.0' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Standard.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualStandard -CommandName 'gitmerge' -RequestedVisualMode 'standard' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match 'v7\.4\.' $out -Message 'Standard summary must contain version v7.4.0'
}

Test-Case 'Standard WriteRunSummary contains [LIVE] tag' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Standard.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualStandard -CommandName 'gitmerge' -RequestedVisualMode 'standard' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match '\[LIVE\]' $out -Message 'Standard summary must contain [LIVE] tag'
}

Test-Case 'Standard WriteRunSummary contains Parameter line with value' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Standard.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualStandard -CommandName 'gitmerge' -RequestedVisualMode 'standard' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match 'Parameter' $out -Message 'Standard summary must contain Parameter line'
    Assert-Match '\ball\b' $out -Message 'Standard summary Parameter line must show the value "all"'
}

Test-Case 'Standard WriteRunSummary contains Workflow chain with -> and stage names' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Standard.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualStandard -CommandName 'gitmerge' -RequestedVisualMode 'standard' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match 'Workflow' $out -Message 'Standard summary must contain a Workflow line'
    Assert-Match '->' $out -Message 'Standard summary Workflow line must contain ->'
    Assert-Match 'PREFLIGHT' $out -Message 'Standard summary Workflow must name PREFLIGHT stage'
    Assert-Match 'MERGE' $out -Message 'Standard summary Workflow must name MERGE stage'
}

Test-Case 'Standard WriteRunSummary contains Notices section with warning text' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Standard.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualStandard -CommandName 'gitmerge' -RequestedVisualMode 'standard' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match 'Notices.*warnings' $out -Message 'Standard summary must contain Notices & warnings section'
    Assert-Match 'Skipped X: conflict' $out -Message 'Standard summary Notices section must contain the warning text'
}

Test-Case 'Standard WriteRunSummary [DRY-RUN] tag when DryRun is true' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Standard.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualStandard -CommandName 'gitmerge' -RequestedVisualMode 'standard' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $state.DryRun = $true
    $state.Result = 'SIMULATED'
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match '\[DRY-RUN\]' $out -Message 'Standard summary must contain [DRY-RUN] tag when DryRun=true'
}

# ---------------------------------------------------------------------------
# Rich tier: WriteRunSummary content
# ---------------------------------------------------------------------------

Test-Case 'Rich WriteRunSummary contains version v7.4.0' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Rich.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualRich -CommandName 'gitmerge' -RequestedVisualMode 'rich' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match 'v7\.4\.' $out -Message 'Rich summary must contain version v7.4.0'
}

Test-Case 'Rich WriteRunSummary contains [LIVE] tag' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Rich.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualRich -CommandName 'gitmerge' -RequestedVisualMode 'rich' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match '\[LIVE\]' $out -Message 'Rich summary must contain [LIVE] tag'
}

Test-Case 'Rich WriteRunSummary contains Parameter line with value' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Rich.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualRich -CommandName 'gitmerge' -RequestedVisualMode 'rich' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match 'Parameter' $out -Message 'Rich summary must contain Parameter line'
    Assert-Match '\ball\b' $out -Message 'Rich summary Parameter line must show the value "all"'
}

Test-Case 'Rich WriteRunSummary contains Workflow chain with -> and stage names' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Rich.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualRich -CommandName 'gitmerge' -RequestedVisualMode 'rich' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match 'Workflow' $out -Message 'Rich summary must contain a Workflow line'
    Assert-Match '->' $out -Message 'Rich summary Workflow line must contain ->'
    Assert-Match 'PREFLIGHT' $out -Message 'Rich summary Workflow must name PREFLIGHT stage'
    Assert-Match 'MERGE' $out -Message 'Rich summary Workflow must name MERGE stage'
}

Test-Case 'Rich WriteRunSummary contains Notices section with warning text' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Rich.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualRich -CommandName 'gitmerge' -RequestedVisualMode 'rich' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match 'Notices.*warnings' $out -Message 'Rich summary must contain Notices & warnings section'
    Assert-Match 'Skipped X: conflict' $out -Message 'Rich summary Notices section must contain the warning text'
}

Test-Case 'Rich WriteRunSummary [DRY-RUN] tag when DryRun is true' {
    Import-Module (Join-Path $summaryTestRepoRoot 'Modules/GitMergeTools.Visual.Rich.psm1') -Force -ErrorAction Stop
    $v = New-GitMergeToolsVisualRich -CommandName 'gitmerge' -RequestedVisualMode 'rich' -RichUnavailableReasons @() -VisualWarningSuppressed $true
    $state = New-TestRunState
    $state.DryRun = $true
    $state.Result = 'SIMULATED'
    $out = (& $v.WriteRunSummary -State $state -RecentLines @() -Name 'gitmerge') *>&1 | Out-String
    Assert-Match '\[DRY-RUN\]' $out -Message 'Rich summary must contain [DRY-RUN] tag when DryRun=true'
}