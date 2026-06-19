[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'These visual modules intentionally render interactive console output.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseShouldProcessForStateChangingFunctions',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'These visual helpers construct renderer objects and do not change system state.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseOutputTypeCorrectly',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'These helpers return small internal renderer/context objects.'
)][Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSProvideCommentHelp',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'This module contains the basic visual renderer for interactive git tools.'
)]
param()

function New-GitMergeToolsVisualBasic {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This function constructs a renderer object and does not change system state.'
    )]
    [CmdletBinding()]
    param(
        [string]$CommandName = 'gitmerge',
        [string]$RequestedVisualMode = 'auto',
        [string[]]$RichUnavailableReasons = @(),
        [bool]$VisualWarningSuppressed
    )

    $commonPath = Join-Path $PSScriptRoot 'GitMergeTools.Visual.Common.psm1'
    Import-Module $commonPath -Force -ErrorAction Stop
    $context = New-GitMergeToolsVisualContext -CommandName $CommandName -VisualLevel 'basic' -RequestedVisualMode $RequestedVisualMode -RichUnavailableReasons $RichUnavailableReasons -VisualWarningSuppressed:$VisualWarningSuppressed
    $theme = $context.Theme
    $getCommandDescription = (Get-Command Get-GitMergeToolsCommandDescription -ErrorAction Stop).ScriptBlock
    $writeFallbackNotice = (Get-Command Write-GitMergeToolsRichFallbackNotice -ErrorAction Stop).ScriptBlock

    $writeRunBanner = {
        param([bool]$DryRun, [string]$Name)
        & $writeFallbackNotice -Context $context
        $description = & $getCommandDescription $Name
        $title = if ($DryRun) { "$($Name.ToUpperInvariant()) DEBUG / DRY-RUN" } else { "$($Name.ToUpperInvariant()) $description" }
        Write-Host ''
        Write-Host "== $title ==" -ForegroundColor $(if ($DryRun) { $theme.BannerDry } else { $theme.Banner })
        Write-Host ''
    }

    $writeStage = {
        param([string]$Title, [string]$Subtitle, [string]$StageIcon, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
        $null = $StageIcon
        Write-Host ''
        Write-Host "-- $Title --" -ForegroundColor $Color
        if (-not [string]::IsNullOrWhiteSpace($Subtitle)) { Write-Host "   $Subtitle" -ForegroundColor $theme.Info }
    }

    $writeStatusLine = {
        param([string]$Marker, [string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
        Write-Host ("  {0,-5} {1}" -f $Marker, $Message) -ForegroundColor $Color
    }

    $writeMiniProgress = {
        param([int]$Current, [int]$Total, [string]$Label, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
        if ($Total -le 0) { return }
        $barWidth = 20
        $filled = [math]::Floor(($Current / $Total) * $barWidth)
        $bar = ('#' * $filled) + ('-' * ($barWidth - $filled))
        $pct = '{0,3:P0}' -f ($Current / $Total)
        Write-Host ("  {0,-16} [{1}] {2}/{3} {4}" -f $Label, $bar, $Current, $Total, $pct) -ForegroundColor $Color
    }

    $writeBranchTree = {
        param([string]$MainBranch, [string[]]$TargetBranches)
        Write-Host ''
        Write-Host "Main branch: $MainBranch" -ForegroundColor $theme.MainBranch
        foreach ($branch in @($TargetBranches)) { Write-Host "Target     : $branch" -ForegroundColor $theme.TargetBranch }
        Write-Host ''
    }

    $writeSuccessBanner = {
        param([int]$ConvergedCount, [string]$Name)
        $commandLabel = if ([string]::IsNullOrWhiteSpace($Name)) { 'COMMAND' } else { $Name.ToUpperInvariant() }
        if ($ConvergedCount -eq 0) {
            Write-Host "SUCCESS: $commandLabel current; nothing to merge" -ForegroundColor $theme.Success
        } else {
            Write-Host ("SUCCESS: {0}: {1} branch(es) converged" -f $commandLabel, $ConvergedCount) -ForegroundColor $theme.Success
        }
    }

    $writeSuccessBannerForSummary = $writeSuccessBanner.GetNewClosure()

    $writeRunSummary = {
        param([Parameter(Mandatory)]$State, [string[]]$RecentLines, [string]$Name)
        $modeTag = if ($State.DryRun) { '[DRY-RUN]' } else { '[LIVE]' }
        $version = Get-GitMergeToolsVersion
        $borderColor = if ($State.Result -eq 'SUCCESS') { $theme.Success } elseif ($State.Result -eq 'SIMULATED') { [ConsoleColor]::Magenta } else { $theme.Error }
        $convergedList = [System.Collections.Generic.List[string]]::new()
        foreach ($b in @($State.IntegratedBranches)) { if (-not $convergedList.Contains($b)) { $convergedList.Add($b) } }
        foreach ($b in @($State.SynchronizedBranches)) { if (-not $convergedList.Contains($b)) { $convergedList.Add($b) } }
        $convergedCount = $convergedList.Count
        $skippedCount = @($State.SkippedBranches).Count; $failedCount = @($State.FailedBranches).Count
        if ($State.Result -eq 'SUCCESS') { & $writeSuccessBannerForSummary -ConvergedCount $convergedCount -Name $Name }
        $paramLabel = $null
        $paramMembers = $State | Get-Member -Name 'Parameter' -MemberType NoteProperty, Property -ErrorAction SilentlyContinue
        if ($paramMembers) { $paramLabel = $State.Parameter }
        Write-Host ''
        Write-Host "GIT MERGE SUMMARY  v$version  $modeTag" -ForegroundColor $borderColor
        if (-not [string]::IsNullOrWhiteSpace($paramLabel)) { Write-Host ("  Parameter                 : {0}" -f $paramLabel) }
        Write-Host ("  Result                    : {0}" -f $State.Result) -ForegroundColor $borderColor
        Write-Host ("  Mode                      : {0}" -f $State.Mode)
        Write-Host ("  Repository                : {0}" -f $State.Repository)
        Write-Host ("  Current branch            : {0}" -f $State.MainBranch)
        Write-Host ("  Worktrees                 : {0}" -f $State.WorktreeCount)
        Write-Host ("  Local branches            : {0}" -f $State.LocalBranchCount)
        Write-Host ("  Converged branches        : {0}" -f $convergedCount)
        if ($convergedCount -gt 0) { Write-Host ("    Converged               : {0}" -f ($convergedList -join ', ')) }
        Write-Host ("  Skipped branches          : {0}" -f $skippedCount)
        if ($skippedCount -gt 0) { Write-Host ("    Skipped                 : {0}" -f (@($State.SkippedBranches) -join ', ')) }
        Write-Host ("  Failed branches           : {0}" -f $failedCount)
        if ($failedCount -gt 0) { Write-Host ("    Failed                  : {0}" -f (@($State.FailedBranches) -join ', ')) -ForegroundColor $theme.Error }
        if (-not [string]::IsNullOrWhiteSpace($State.ConflictBranch)) { Write-Host ("  Conflict branch           : {0}" -f $State.ConflictBranch) -ForegroundColor $theme.Error }
        Write-Host ("  Temporary cleanup         : {0}" -f $State.CleanupStatus)
        Write-Host ("  Elapsed                   : {0:n2}s" -f $State.Elapsed.TotalSeconds)
        if (-not [string]::IsNullOrWhiteSpace($State.FailureReason)) { Write-Host ("  Failure reason            : {0}" -f $State.FailureReason) -ForegroundColor $theme.Error }
        # Workflow chain.
        $stagesMembers = $State | Get-Member -Name 'Stages' -MemberType NoteProperty, Property -ErrorAction SilentlyContinue
        if ($stagesMembers -and $null -ne $State.Stages -and $State.Stages.Count -gt 0) {
            Write-Host ("  Workflow                  : {0}" -f ($State.Stages -join ' -> '))
        }
        if (-not $State.DryRun -and -not [string]::IsNullOrWhiteSpace($State.MainBranch) -and @($RecentLines).Count -gt 0) {
            Write-Host ''
            Write-Host "Recent commits on $($State.MainBranch):"
            foreach ($line in @($RecentLines)) { Write-Host "   $line" }
        }
        # Collected messages section.
        $messagesMembers = $State | Get-Member -Name 'Messages' -MemberType NoteProperty, Property -ErrorAction SilentlyContinue
        if ($messagesMembers -and $null -ne $State.Messages -and $State.Messages.Count -gt 0) {
            $errorMsgs  = @($State.Messages | Where-Object { $_.Level -eq 'ERROR' })
            $warnMsgs   = @($State.Messages | Where-Object { $_.Level -eq 'WARNING' })
            $noticeMsgs = @($State.Messages | Where-Object { $_.Level -eq 'NOTICE' })
            Write-Host ''
            Write-Host "  Notices & warnings ($($State.Messages.Count)):" -ForegroundColor Yellow
            foreach ($m in $errorMsgs)  { Write-Host ("    [ERROR]   {0}" -f $m.Text) -ForegroundColor $theme.Error }
            foreach ($m in $warnMsgs)   { Write-Host ("    [WARNING] {0}" -f $m.Text) -ForegroundColor Yellow }
            foreach ($m in $noticeMsgs) { Write-Host ("    [NOTICE]  {0}" -f $m.Text) -ForegroundColor $theme.Info }
        }
        Write-Host ''
        if ($State.Result -eq 'SUCCESS') { Write-Host "$Name finished." -ForegroundColor $theme.Success } elseif ($State.Result -eq 'SIMULATED') { Write-Host "$Name dry-run finished; no changes were made." -ForegroundColor ([ConsoleColor]::Magenta) } else { Write-Host "$Name stopped before full completion." -ForegroundColor $theme.Error }
    }

    New-GitMergeToolsVisualObject -Context $context -WriteRunBanner ($writeRunBanner.GetNewClosure()) -WriteStage ($writeStage.GetNewClosure()) -WriteStatusLine ($writeStatusLine.GetNewClosure()) -WriteMiniProgress ($writeMiniProgress.GetNewClosure()) -WriteBranchTree ($writeBranchTree.GetNewClosure()) -WriteSuccessBanner ($writeSuccessBanner.GetNewClosure()) -WriteRunSummary ($writeRunSummary.GetNewClosure())
}

Export-ModuleMember -Function New-GitMergeToolsVisualBasic
