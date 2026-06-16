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
    Justification = 'This module contains the rich visual renderer for interactive git tools.'
)]
param()

function New-GitMergeToolsVisualRich {
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
    $context = New-GitMergeToolsVisualContext -CommandName $CommandName -VisualLevel 'rich' -RequestedVisualMode $RequestedVisualMode -RichUnavailableReasons $RichUnavailableReasons -VisualWarningSuppressed:$VisualWarningSuppressed
    $theme = $context.Theme
    $getCommandDescription = (Get-Command Get-GitMergeToolsCommandDescription -ErrorAction Stop).ScriptBlock
    $getMarkerColor = (Get-Command Get-GitMergeToolsMarkerColor -ErrorAction Stop).ScriptBlock
    $icons = @{
        Git = '🔀'; Branch = '🌿'; Merge = '🔀'; Check = '✅'; Cross = '❌'; Sync = '🔄'; Rocket = '🚀'; Trash = '🧹'; Search = '🔍'; Cloud = '☁️'; Beaker = '🧪'; Status = '📊'
    }

    $stageIcon = {
        param([string]$Icon)
        switch ($Icon) {
            'SCAN' { '🔍'; break }
            'REMOTE' { '☁️'; break }
            'MERGE' { '🧪'; break }
            'PUSH' { '🚀'; break }
            'SYNC' { '🔄'; break }
            'CLEAN' { '🧹'; break }
            'STATUS' { '📊'; break }
            default { if ([string]::IsNullOrWhiteSpace($Icon)) { '•' } else { $Icon } }
        }
    }

    $writeRunBanner = {
        param([bool]$DryRun, [string]$Name)
        $frameColor = if ($DryRun) { $theme.BannerDry } else { $theme.Banner }
        $description = & $getCommandDescription $Name
        $title = if ($DryRun) { "$($Name.ToUpperInvariant())  DEBUG / DRY-RUN  Preview only; refs unchanged" } else { "$($Name.ToUpperInvariant())  $description" }
        if ($title.Length -gt 54) { $title = $title.Substring(0, 54) }
        $prefix = if ($DryRun) { '🔬' } elseif ($Name -eq 'gitstatus') { '📊' } elseif ($Name -eq 'gitsync') { '🔄' } else { '🔀' }
        Write-Host ''
        Write-Host '         ██████╗ ██╗████████╗' -ForegroundColor $frameColor
        Write-Host '        ██╔════╝ ██║╚══██╔══╝' -ForegroundColor $frameColor
        Write-Host '        ██║  ███╗██║   ██║   ' -ForegroundColor $frameColor
        Write-Host '        ██║   ██║██║   ██║   ' -ForegroundColor $frameColor
        Write-Host '        ╚██████╔╝██║   ██║   ' -ForegroundColor $frameColor
        Write-Host '         ╚═════╝ ╚═╝   ╚═╝   ' -ForegroundColor $frameColor
        Write-Host ''
        Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor $frameColor
        Write-Host ("║  {0,-56}  ║" -f "$prefix $title") -ForegroundColor $frameColor
        Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor $frameColor
        Write-Host ''
    }

    $writeStage = {
        param([string]$Title, [string]$Subtitle, [string]$StageIcon, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
        Write-Host ''
        Write-Host ("  ━━━━━━━━  {0}  {1}  ━━━━━━━━" -f (& $stageIcon $StageIcon), $Title) -ForegroundColor $Color
        if (-not [string]::IsNullOrWhiteSpace($Subtitle)) { Write-Host "    $Subtitle" -ForegroundColor $theme.Info }
        Write-Host ('  ' + ('─' * 62)) -ForegroundColor $theme.Divider
    }

    $writeStatusLine = {
        param([string]$Marker, [string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
        $markerColor = & $getMarkerColor -Marker $Marker -DefaultColor $Color -Theme $theme
        $richMarker = switch ($Marker) {
            '✓' { '✅'; break } '✔' { '✅'; break } '→' { '➜'; break } '✗' { '❌'; break } '✘' { '❌'; break } '↔' { '↔️'; break } '↕' { '↕️'; break } default { $Marker }
        }
        Write-Host '  ' -NoNewline
        Write-Host $richMarker -ForegroundColor $markerColor -NoNewline
        Write-Host "  $Message" -ForegroundColor $Color
    }

    $writeMiniProgress = {
        param([int]$Current, [int]$Total, [string]$Label, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
        if ($Total -le 0) { return }
        $barWidth = 20
        $filled = [math]::Floor(($Current / $Total) * $barWidth)
        $bar = ('█' * $filled) + ('░' * ($barWidth - $filled))
        $pct = '{0,3:P0}' -f ($Current / $Total)
        Write-Host '  ⏳ ' -NoNewline -ForegroundColor $theme.Info
        Write-Host $Label.PadRight(16) -NoNewline -ForegroundColor $theme.Info
        Write-Host " [$bar]" -NoNewline -ForegroundColor $Color
        Write-Host " $Current/$Total $pct" -ForegroundColor $theme.Info
    }

    $writeBranchTree = {
        param([string]$MainBranch, [string[]]$TargetBranches)
        Write-Host ''
        Write-Host '  📂 Branch topology' -ForegroundColor $theme.Highlight
        Write-Host '  ┌─ ' -NoNewline -ForegroundColor $theme.Divider
        Write-Host "🏠 $MainBranch (main)" -ForegroundColor $theme.MainBranch
        for ($i = 0; $i -lt $TargetBranches.Count; $i++) {
            $prefix = if ($i -eq $TargetBranches.Count - 1) { '  └─ ' } else { '  ├─ ' }
            Write-Host $prefix -NoNewline -ForegroundColor $theme.Divider
            Write-Host "🌿 $($TargetBranches[$i])" -ForegroundColor $theme.TargetBranch
        }
        Write-Host ''
    }

    $writeSuccessBanner = {
        param([string]$MainBranch, [int]$TargetCount, [string]$MainPublished, [string]$Name)
        $commandLabel = if ([string]::IsNullOrWhiteSpace($Name)) { 'COMMAND' } else { $Name.ToUpperInvariant() }
        Write-Host ''
        Write-Host '  ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨' -ForegroundColor $theme.Warning
        Write-Host '  ╔════════════════════════════════════════════════════════╗' -ForegroundColor $theme.Success
        if ($TargetCount -eq 0 -or $MainPublished -eq 'NOT REQUIRED') {
            Write-Host ("  ║  SUCCESS  {0,-43}║" -f "✅ $commandLabel current; nothing to merge") -ForegroundColor $theme.Success
        } else {
            $line = ("  ║  ✅ SUCCESS  {0}: {1} published; {2} branch(es) synchronized" -f $commandLabel, $MainBranch, $TargetCount)
            Write-Host ($line.PadRight(59) + '║') -ForegroundColor $theme.Success
        }
        Write-Host '  ╚════════════════════════════════════════════════════════╝' -ForegroundColor $theme.Success
        Write-Host '  ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨' -ForegroundColor $theme.Warning
    }

    $writeSuccessBannerForSummary = $writeSuccessBanner.GetNewClosure()

    $writeRunSummary = {
        param([Parameter(Mandatory)]$State, [string[]]$RecentLines, [string]$Name)
        $modeTag = if ($State.DryRun) { '[DRY-RUN]' } else { '[LIVE]' }
        $borderColor = if ($State.Result -eq 'SUCCESS') { $theme.Success } elseif ($State.Result -eq 'SIMULATED') { [ConsoleColor]::Magenta } else { $theme.Error }
        $targetCount = @($State.TargetBranches).Count; $integratedCount = @($State.IntegratedBranches).Count; $synchronizedCount = @($State.SynchronizedBranches).Count; $failedCount = @($State.FailedBranches).Count
        if ($State.Result -eq 'SUCCESS') { & $writeSuccessBannerForSummary -MainBranch $State.MainBranch -TargetCount $targetCount -MainPublished $State.MainPublished -Name $Name }
        Write-Host ''
        Write-Host "═══════════════════  GIT MERGE SUMMARY  $modeTag  ═══════════════════" -ForegroundColor $borderColor
        Write-Host ("  🏷  Result                : {0}" -f $State.Result) -ForegroundColor $borderColor
        Write-Host ("  Mode                      : {0}" -f $State.Mode)
        Write-Host ("  Repository                : {0}" -f $State.Repository)
        Write-Host ("  Main branch               : {0}" -f $State.MainBranch) -ForegroundColor $theme.MainBranch
        Write-Host ("  Worktrees                 : {0}" -f $State.WorktreeCount)
        Write-Host ("  Local branches            : {0}" -f $State.LocalBranchCount)
        Write-Host ("  Target branches           : {0}" -f $targetCount)
        if ($targetCount -gt 0) { Write-Host ("    Targets                 : {0}" -f (@($State.TargetBranches) -join ', ')) -ForegroundColor $theme.Info }
        Write-Host ("  Integrated into main      : {0} / {1}" -f $integratedCount, $targetCount) -ForegroundColor $(if ($integratedCount -eq $targetCount) { $theme.Success } else { $theme.Warning })
        if ($integratedCount -gt 0) { Write-Host ("    Integrated              : {0}" -f (@($State.IntegratedBranches) -join ', ')) -ForegroundColor $theme.Success }
        Write-Host ("  Synchronized branches     : {0} / {1}" -f $synchronizedCount, $targetCount) -ForegroundColor $(if ($synchronizedCount -eq $targetCount) { $theme.Success } else { $theme.Warning })
        if ($synchronizedCount -gt 0) { Write-Host ("    Synchronized            : {0}" -f (@($State.SynchronizedBranches) -join ', ')) -ForegroundColor $theme.Success }
        Write-Host ("  Failed branches           : {0}" -f $failedCount) -ForegroundColor $(if ($failedCount -eq 0) { [ConsoleColor]::Gray } else { $theme.Error })
        if ($failedCount -gt 0) { Write-Host ("    Failed                  : {0}" -f (@($State.FailedBranches) -join ', ')) -ForegroundColor $theme.Error }
        if (-not [string]::IsNullOrWhiteSpace($State.ConflictBranch)) { Write-Host ("  Conflict branch           : {0}" -f $State.ConflictBranch) -ForegroundColor $theme.Error }
        Write-Host ("  Main published            : {0}" -f $State.MainPublished)
        Write-Host ("  Temporary cleanup         : {0}" -f $State.CleanupStatus)
        Write-Host ("  Elapsed                   : {0:n2}s" -f $State.Elapsed.TotalSeconds)
        if (-not [string]::IsNullOrWhiteSpace($State.FailureReason)) { Write-Host ("  Failure reason            : {0}" -f $State.FailureReason) -ForegroundColor $theme.Error }
        if (-not $State.DryRun -and -not [string]::IsNullOrWhiteSpace($State.MainBranch) -and @($RecentLines).Count -gt 0) {
            Write-Host ''; Write-Host "── Recent commits on $($State.MainBranch) ──" -ForegroundColor $theme.Info
            foreach ($line in @($RecentLines)) { Write-Host "   $line" -ForegroundColor $theme.Info }
        }
        Write-Host ''; Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor $borderColor
        if ($State.Result -eq 'SUCCESS') { Write-Host "$Name finished." -ForegroundColor $theme.Success } elseif ($State.Result -eq 'SIMULATED') { Write-Host "$Name dry-run finished; no changes were made." -ForegroundColor ([ConsoleColor]::Magenta) } else { Write-Host "$Name stopped before full completion." -ForegroundColor $theme.Error }
    }

    New-GitMergeToolsVisualObject -Context $context -Icons $icons -WriteRunBanner ($writeRunBanner.GetNewClosure()) -WriteStage ($writeStage.GetNewClosure()) -WriteStatusLine ($writeStatusLine.GetNewClosure()) -WriteMiniProgress ($writeMiniProgress.GetNewClosure()) -WriteBranchTree ($writeBranchTree.GetNewClosure()) -WriteSuccessBanner ($writeSuccessBanner.GetNewClosure()) -WriteRunSummary ($writeRunSummary.GetNewClosure())
}

Export-ModuleMember -Function New-GitMergeToolsVisualRich
