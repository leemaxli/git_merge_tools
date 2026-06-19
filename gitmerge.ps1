<#
.SYNOPSIS
    Transactionally consolidates local branches through main.
.DESCRIPTION
    Merges one or all local branches into a temporary integration branch.
    Main is advanced only after every requested merge succeeds. Selected
    branches are then fast-forwarded to main. The caller's location is never
    changed, and no push, reset, rebase, or user-branch deletion is performed.
.PARAMETER BranchName
    Empty selects the current branch. all or cross-all selects every local
    branch, including main/master.
    debug reports the plan without changing refs, worktrees, or remotes.
    Any other value selects one local branch.
.EXAMPLE
    gitmerge
    gitmerge all
    gitmerge debug
    gitmerge feature/example
#>
function gitmerge {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'This is an interactive, colorized Git command.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$BranchName = ''
    )

    # Load the shared modules: Core (git primitives: Invoke-GitCommand, ref/branch/worktree helpers,
    # Get-Mode, ...) and Merge (the transactional engine helpers). The .psm1 modules live in a Modules/
    # subfolder beside the command scripts; a flat layout is still tolerated. Resolution: this script's
    # folder -> its command path's folder -> $env:GITMERGE_TOOLS_HOME. Both modules are mandatory.
    $gmtModuleDir = $null
    foreach ($gmtDir in @($PSScriptRoot, (Split-Path -Parent $PSCommandPath), $env:GITMERGE_TOOLS_HOME)) {
        if ([string]::IsNullOrWhiteSpace($gmtDir)) { continue }
        foreach ($gmtSub in @((Join-Path $gmtDir 'Modules'), $gmtDir)) {
            if (Test-Path -LiteralPath (Join-Path $gmtSub 'GitMergeTools.Core.psm1')) { $gmtModuleDir = $gmtSub; break }
        }
        if ($gmtModuleDir) { break }
    }
    if (-not $gmtModuleDir) {
        Write-Warning 'GitMergeTools.Core.psm1 was not found beside this command (set $env:GITMERGE_TOOLS_HOME to its folder).'
        return $false
    }
    Import-Module (Join-Path $gmtModuleDir 'GitMergeTools.Core.psm1') -ErrorAction Stop
    Import-Module (Join-Path $gmtModuleDir 'GitMergeTools.Merge.psm1') -ErrorAction Stop

    function Test-GitMergeToolsSuppressWarningLocal {
        $truthy = @('1', 'true', 'TRUE', 'yes', 'YES', 'on', 'ON')
        return (($env:GITMERGE_TOOLS_SUPPRESS_WARNING -in $truthy) -or ($env:GITMERGE_VISUAL_SUPPRESS_WARNING -in $truthy))
    }

    function New-OptionalGitMergeVisual {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'New-OptionalGitMergeVisual loads an optional renderer and does not change Git state.'
        )]
        param()

        $basePath = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $PSCommandPath } else { $PSScriptRoot }
        $isWindowsRuntime = ($PSVersionTable.PSEdition -eq 'Desktop' -or $PSVersionTable.Platform -eq 'Win32NT' -or $IsWindows)
        $xdgPowerShell = if (-not [string]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME)) { Join-Path $env:XDG_CONFIG_HOME 'powershell' } else { $null }
        $homeConfigPowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path $HOME '.config') 'powershell' } else { $null }
        $homeDocumentsPowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path $HOME 'Documents') 'PowerShell' } else { $null }
        $windowsDocumentsPowerShell = if ($isWindowsRuntime) { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell' } else { $null }
        $windowsOneDrivePowerShell = if ($isWindowsRuntime -and -not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path (Join-Path $HOME 'OneDrive') 'Documents') 'PowerShell' } else { $null }
        $commonCandidates = @(
            $env:GITMERGE_TOOLS_COMMON_MODULE,
            (Join-Path (Join-Path $basePath 'Modules') 'GitMergeTools.Common.psm1'),
            (Join-Path $basePath 'GitMergeTools.Common.psm1'),
            $(if ($xdgPowerShell) { Join-Path $xdgPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($homeConfigPowerShell) { Join-Path $homeConfigPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($homeDocumentsPowerShell) { Join-Path $homeDocumentsPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($windowsDocumentsPowerShell) { Join-Path $windowsDocumentsPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($windowsOneDrivePowerShell) { Join-Path $windowsOneDrivePowerShell 'GitMergeTools.Common.psm1' })
        )
        foreach ($candidate in $commonCandidates) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
                try {
                    Import-Module $candidate -Force -ErrorAction Stop
                    return New-GitMergeToolsVisual -CommandName 'gitmerge' -ScriptRoot $PSScriptRoot -PSCommandPath $PSCommandPath
                }
                catch {
                    $suppress = (Test-GitMergeToolsSuppressWarningLocal)
                    if (-not $suppress) {
                        Write-Warning "GitMergeTools.Common.psm1 could not initialize gitmerge visuals; using built-in basic output. $($_.Exception.Message)"
                        Write-Host "  Set `$env:GITMERGE_TOOLS_COMMON_MODULE to the common module path, or place GitMergeTools.Common.psm1 in the PowerShell profile directory." -ForegroundColor Yellow
                        Write-Host "  Suppress notice: `$env:GITMERGE_TOOLS_SUPPRESS_WARNING='1'" -ForegroundColor DarkGray
                    }
                    return $null
                }
            }
        }

        $fallbackSuppress = (Test-GitMergeToolsSuppressWarningLocal)
        if (-not $fallbackSuppress) {
            Write-Warning "GitMergeTools.Common.psm1 was not found; gitmerge is using built-in basic output."
            Write-Host "  Set `$env:GITMERGE_TOOLS_COMMON_MODULE to the common module path, or place GitMergeTools.Common.psm1 beside the git tool scripts." -ForegroundColor Yellow
            Write-Host "  Suppress notice: `$env:GITMERGE_TOOLS_SUPPRESS_WARNING='1'" -ForegroundColor DarkGray
        }
        return $null
    }

    $visual = New-OptionalGitMergeVisual

    function Write-RunBanner {
        param([bool]$DryRun)
        if ($null -ne $visual) {
            & $visual.WriteRunBanner -DryRun:$DryRun -Name 'gitmerge'
            return
        }
        $color = if ($DryRun) { 'Magenta' } else { 'Cyan' }
        Write-Host ''
        Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor $color
        if ($DryRun) {
            Write-Host '║  DEBUG / DRY-RUN  Transaction preview, no refs will change   ║' -ForegroundColor $color
        }
        else {
            Write-Host '║  GITMERGE  Transactional cross-merge and synchronization     ║' -ForegroundColor $color
        }
        Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor $color
        Write-Host ''
    }

    function Write-SuccessBanner {
        param([int]$ConvergedCount)
        if ($null -ne $visual) {
            & $visual.WriteSuccessBanner -ConvergedCount $ConvergedCount -Name 'gitmerge'
            return
        }
        Write-Host ''
        Write-Host '██████████████████████████████████████████████████████████████' -ForegroundColor Green
        if ($ConvergedCount -eq 0) {
            Write-Host '██  SUCCESS  Repository is current; nothing to merge          ██' -ForegroundColor Green
        }
        else {
            Write-Host ("██  SUCCESS  {0} branch(es) converged" -f $ConvergedCount) -ForegroundColor Green
        }
        Write-Host '██████████████████████████████████████████████████████████████' -ForegroundColor Green
    }

    function Write-RunSummary {
        param([Parameter(Mandatory)]$State)

        if ($null -ne $visual) {
            $recentLines = @()
            if (-not $State.DryRun -and -not [string]::IsNullOrWhiteSpace($State.Repository) -and -not [string]::IsNullOrWhiteSpace($State.MainBranch)) {
                $recentLines = Get-RecentCommitLines -Repository $State.Repository -Branch $State.MainBranch
            }
            & $visual.WriteRunSummary -State $State -RecentLines $recentLines -Name 'gitmerge'
            if (Get-Command Write-GitMergeToolsUpgradeAdvisory -ErrorAction SilentlyContinue) {
                Write-GitMergeToolsUpgradeAdvisory -Visual $visual
            }
            return
        }

        $modeTag = if ($State.DryRun) { '[DRY-RUN]' } else { '[LIVE]' }
        $resultColor = switch ($State.Result) {
            'SUCCESS' { [ConsoleColor]::Green }
            'SIMULATED' { [ConsoleColor]::Magenta }
            default { [ConsoleColor]::Red }
        }
        $convergedList = [System.Collections.Generic.List[string]]::new()
        foreach ($b in @($State.IntegratedBranches)) { if (-not $convergedList.Contains($b)) { $convergedList.Add($b) } }
        foreach ($b in @($State.SynchronizedBranches)) { if (-not $convergedList.Contains($b)) { $convergedList.Add($b) } }
        $convergedCount = $convergedList.Count
        $skippedCount = @($State.SkippedBranches).Count
        $failedCount = @($State.FailedBranches).Count

        if ($State.Result -eq 'SUCCESS') {
            Write-SuccessBanner -ConvergedCount $convergedCount
        }

        Write-Host ''
        Write-Host "═══════════════════  GIT MERGE SUMMARY  $modeTag  ═══════════════════" -ForegroundColor Cyan
        Write-Host ("  Result                    : {0}" -f $State.Result) -ForegroundColor $resultColor
        Write-Host ("  Mode                      : {0}" -f $State.Mode)
        Write-Host ("  Repository                : {0}" -f $State.Repository)
        Write-Host ("  Current branch            : {0}" -f $State.MainBranch)
        Write-Host ("  Worktrees                 : {0}" -f $State.WorktreeCount)
        Write-Host ("  Local branches            : {0}" -f $State.LocalBranchCount)
        Write-Host ("  Converged branches        : {0}" -f $convergedCount) -ForegroundColor $(if ($convergedCount -gt 0) { 'Green' } else { 'Gray' })
        if ($convergedCount -gt 0) {
            Write-Host ("    Converged               : {0}" -f ($convergedList -join ', ')) -ForegroundColor Green
        }
        Write-Host ("  Skipped branches          : {0}" -f $skippedCount)
        if ($skippedCount -gt 0) {
            Write-Host ("    Skipped                 : {0}" -f (@($State.SkippedBranches) -join ', ')) -ForegroundColor DarkGray
        }
        Write-Host ("  Failed branches           : {0}" -f $failedCount) -ForegroundColor $(if ($failedCount -eq 0) { 'Gray' } else { 'Red' })
        if ($failedCount -gt 0) {
            Write-Host ("    Failed                  : {0}" -f (@($State.FailedBranches) -join ', ')) -ForegroundColor Red
        }
        if (-not [string]::IsNullOrWhiteSpace($State.ConflictBranch)) {
            Write-Host ("  Conflict branch           : {0}" -f $State.ConflictBranch) -ForegroundColor Red
        }
        Write-Host ("  Temporary cleanup         : {0}" -f $State.CleanupStatus)
        Write-Host ("  Elapsed                   : {0:n2}s" -f $State.Elapsed.TotalSeconds)
        if (-not [string]::IsNullOrWhiteSpace($State.FailureReason)) {
            Write-Host ("  Failure reason            : {0}" -f $State.FailureReason) -ForegroundColor Red
        }

        if (-not $State.DryRun -and -not [string]::IsNullOrWhiteSpace($State.Repository) -and -not [string]::IsNullOrWhiteSpace($State.MainBranch)) {
            $recent = Get-RecentCommitLines -Repository $State.Repository -Branch $State.MainBranch
            if (@($recent).Count -gt 0) {
                Write-Host ''
                Write-Host "── Recent commits on $($State.MainBranch) ──" -ForegroundColor DarkGray
                foreach ($line in @($recent)) {
                    Write-Host "   $line" -ForegroundColor DarkGray
                }
            }
        }

        Write-Host ''
        Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Cyan
        if ($State.Result -eq 'SUCCESS') {
            Write-Host 'gitmerge finished.' -ForegroundColor Green
        }
        elseif ($State.Result -eq 'SIMULATED') {
            Write-Host 'gitmerge dry-run finished; no changes were made.' -ForegroundColor Magenta
        }
        else {
            Write-Host 'gitmerge stopped before full completion.' -ForegroundColor Red
        }
    }

    $mode = Get-Mode $BranchName

    $startedAt = Get-Date
    $runState = [pscustomobject]@{
        DryRun                = ($mode -eq 'debug')
        Mode                  = $mode
        Result                = 'FAILED'
        Repository            = ''
        MainBranch            = ''
        WorktreeCount         = 0
        LocalBranchCount      = 0
        TargetBranches        = [System.Collections.Generic.List[string]]::new()
        IntegratedBranches    = [System.Collections.Generic.List[string]]::new()
        SynchronizedBranches  = [System.Collections.Generic.List[string]]::new()
        FailedBranches        = [System.Collections.Generic.List[string]]::new()
        SkippedBranches       = [System.Collections.Generic.List[string]]::new()
        ConflictBranch        = ''
        MainPublished         = 'NO'
        CleanupStatus         = 'NOT REQUIRED'
        FailureReason         = ''
        Elapsed               = [timespan]::Zero
        SummaryEnabled        = $false
    }

    Write-RunBanner -DryRun $runState.DryRun

    try {
        $engineResult = if ($mode -in @('current', 'single')) {
            @(Invoke-TwoBranchMerge -BranchName $BranchName -RunState $runState -Visual $visual) |
                Where-Object { $_ -is [bool] } | Select-Object -Last 1
        }
        elseif ($mode -eq 'all') {
            @(Invoke-StarMerge -RunState $runState -Visual $visual) |
                Where-Object { $_ -is [bool] } | Select-Object -Last 1
        }
        elseif ($mode -eq 'cross-all') {
            @(Invoke-MeshMerge -RunState $runState -Visual $visual) |
                Where-Object { $_ -is [bool] } | Select-Object -Last 1
        }
        elseif ($mode -eq 'debug') {
            @(Invoke-MeshMerge -RunState $runState -Visual $visual -DryRun) |
                Where-Object { $_ -is [bool] } | Select-Object -Last 1
        }
        else {
            # Defensive backstop: Get-Mode returns only 'current'/'single'/'all'/'cross-all'/'debug',
            # so this branch is unreachable in normal operation.
            $runState.FailureReason = "Unknown mode '$mode'."
            Write-Warning $runState.FailureReason
            $false
        }
        return [bool]$engineResult
    }
    finally {
        if ($runState.SummaryEnabled) {
            $runState.Elapsed = (Get-Date) - $startedAt
            Write-RunSummary -State $runState
        }
    }
}
