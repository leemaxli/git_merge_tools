<#
.SYNOPSIS
    Shows enhanced Git status, recent log, and branch comparisons.
.DESCRIPTION
    Empty selects the current branch. all or cross-all selects every local
    branch, including main/master. A branch name selects that local branch.
    The script is read-only: it does not fetch, merge, reset, push, or modify refs.
.PARAMETER BranchName
    Empty selects the current branch. all or cross-all selects every local
    branch, including main/master.
#>
function gitstatus {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'This is an interactive, colorized Git command.'
    )]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Position = 0)]
        [string]$BranchName = ''
    )

    # Load the shared git primitives (Core). The .psm1 modules live in a Modules/ subfolder beside the
    # command scripts; a flat layout is still tolerated. Resolution: this script's folder -> its command
    # path's folder -> $env:GITMERGE_TOOLS_HOME. Core is mandatory; without it the command cannot run safely.
    $gmtCoreModule = $null
    foreach ($gmtDir in @($PSScriptRoot, (Split-Path -Parent $PSCommandPath), $env:GITMERGE_TOOLS_HOME)) {
        if ([string]::IsNullOrWhiteSpace($gmtDir)) { continue }
        foreach ($gmtSub in @((Join-Path $gmtDir 'Modules'), $gmtDir)) {
            $gmtCandidate = Join-Path $gmtSub 'GitMergeTools.Core.psm1'
            if (Test-Path -LiteralPath $gmtCandidate) { $gmtCoreModule = $gmtCandidate; break }
        }
        if ($gmtCoreModule) { break }
    }
    if (-not $gmtCoreModule) {
        Write-Warning 'GitMergeTools.Core.psm1 was not found beside this command (set $env:GITMERGE_TOOLS_HOME to its folder).'
        return $false
    }
    Import-Module $gmtCoreModule -ErrorAction Stop

    function Test-GitMergeToolsSuppressWarningLocal {
        $truthy = @('1', 'true', 'TRUE', 'yes', 'YES', 'on', 'ON')
        return (($env:GITMERGE_TOOLS_SUPPRESS_WARNING -in $truthy) -or ($env:GITMERGE_VISUAL_SUPPRESS_WARNING -in $truthy))
    }

    function New-OptionalGitStatusVisual {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'New-OptionalGitStatusVisual loads an optional renderer and does not change Git state.'
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
                    return New-GitMergeToolsVisual -CommandName 'gitstatus' -ScriptRoot $PSScriptRoot -PSCommandPath $PSCommandPath
                }
                catch {
                    $suppress = (Test-GitMergeToolsSuppressWarningLocal)
                    if (-not $suppress) {
                        Write-Warning "GitMergeTools.Common.psm1 could not initialize gitstatus visuals; using built-in basic output. $($_.Exception.Message)"
                        Write-Host "  Set `$env:GITMERGE_TOOLS_COMMON_MODULE to the common module path, or place GitMergeTools.Common.psm1 in the PowerShell profile directory." -ForegroundColor Yellow
                        Write-Host "  Suppress notice: `$env:GITMERGE_TOOLS_SUPPRESS_WARNING='1'" -ForegroundColor DarkGray
                    }
                    return $null
                }
            }
        }

        $fallbackSuppress = (Test-GitMergeToolsSuppressWarningLocal)
        if (-not $fallbackSuppress) {
            Write-Warning "GitMergeTools.Common.psm1 was not found; gitstatus is using built-in basic output."
            Write-Host "  Set `$env:GITMERGE_TOOLS_COMMON_MODULE to the common module path, or place GitMergeTools.Common.psm1 beside the git tool scripts." -ForegroundColor Yellow
            Write-Host "  Suppress notice: `$env:GITMERGE_TOOLS_SUPPRESS_WARNING='1'" -ForegroundColor DarkGray
        }
        return $null
    }

    $visual = New-OptionalGitStatusVisual

    function Write-RunBanner {
        param([bool]$DryRun)
        if ($null -ne $visual) {
            & $visual.WriteRunBanner -DryRun:$DryRun -Name 'gitstatus'
            return
        }
        $color = if ($DryRun) { 'Magenta' } else { 'Cyan' }
        Write-Host ''
        Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor $color
        if ($DryRun) {
            Write-Host '║  GITSTATUS DEBUG / DRY-RUN  Preview only                   ║' -ForegroundColor $color
        }
        else {
            Write-Host '║  GITSTATUS  Enhanced status, log, and comparisons          ║' -ForegroundColor $color
        }
        Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor $color
    }

    function Write-Stage {
        param(
            [string]$Title,
            [string]$Subtitle,
            [string]$StageIcon,
            [ConsoleColor]$Color = [ConsoleColor]::Cyan
        )
        if ($null -ne $visual) {
            & $visual.WriteStage -Title $Title -Subtitle $Subtitle -StageIcon $StageIcon -Color $Color
            return
        }
        Write-Host ''
        Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
        Write-Host "  $Title" -ForegroundColor $Color
        if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
            Write-Host "  $Subtitle" -ForegroundColor DarkGray
        }
        Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    }

    function Write-StatusLine {
        param(
            [string]$Marker,
            [string]$Message,
            [ConsoleColor]$Color = [ConsoleColor]::Gray
        )
        if ($null -ne $visual) {
            & $visual.WriteStatusLine -Marker $Marker -Message $Message -Color $Color
            return
        }
        Write-Host ("   {0,-3} {1}" -f $Marker, $Message) -ForegroundColor $Color
    }

    function Get-AheadBehind {
        param([string]$Repository, [string]$Left, [string]$Right)
        if (-not (Get-RefHash -Repository $Repository -Ref $Left)) {
            return $null
        }
        if (-not (Get-RefHash -Repository $Repository -Ref $Right)) {
            return $null
        }
        $result = Invoke-GitCommand $Repository @('rev-list', '--left-right', '--count', "$Left...$Right") -SuppressError
        if ($result.ExitCode -ne 0) { return $null }
        $parts = ((Get-FirstOutputLine $result) -split '\s+') | Where-Object { $_ -ne '' }
        if ($parts.Count -lt 2) { return $null }
        return [pscustomobject]@{
            LeftOnly  = [int]$parts[0]
            RightOnly = [int]$parts[1]
        }
    }

    function Get-BranchSnapshot {
        param(
            [string]$Repository,
            [string]$Branch,
            [string]$MainBranch,
            [object[]]$Worktrees
        )

        $worktree = Find-BranchWorktree -Worktrees $Worktrees -Branch $Branch
        $statusLines = @()
        $dirtyCount = 0
        $worktreePath = ''
        $statusAvailable = $false
        if ($null -ne $worktree -and -not $worktree.Locked -and (Test-Path -LiteralPath $worktree.Path)) {
            $worktreePath = $worktree.Path
            $status = Invoke-GitCommand $worktree.Path @('status', '--short', '--branch', '--untracked-files=normal')
            if ($status.ExitCode -eq 0) {
                $statusAvailable = $true
                $statusLines = @($status.Output)
                $dirtyCount = @($statusLines | Where-Object { $_ -notmatch '^## ' -and -not [string]::IsNullOrWhiteSpace($_) }).Count
            }
        }

        $logLines = Get-RecentCommitLines -Repository $Repository -Branch $Branch -Decorate
        $mainCompare = if ($Branch -ceq $MainBranch) {
            [pscustomobject]@{ LeftOnly = 0; RightOnly = 0 }
        }
        else {
            Get-AheadBehind -Repository $Repository -Left $MainBranch -Right $Branch
        }
        $originRef = "refs/remotes/origin/$Branch"
        $originCompare = Get-AheadBehind -Repository $Repository -Left $originRef -Right $Branch

        return [pscustomobject]@{
            Branch          = $Branch
            WorktreePath    = $worktreePath
            StatusAvailable = $statusAvailable
            DirtyCount      = $dirtyCount
            StatusLines     = [string[]]$statusLines
            LogLines        = [string[]]@($logLines)
            MainBehind      = if ($null -eq $mainCompare) { $null } else { $mainCompare.LeftOnly }
            MainAhead       = if ($null -eq $mainCompare) { $null } else { $mainCompare.RightOnly }
            OriginBehind    = if ($null -eq $originCompare) { $null } else { $originCompare.LeftOnly }
            OriginAhead     = if ($null -eq $originCompare) { $null } else { $originCompare.RightOnly }
        }
    }

    function Write-BranchSnapshot {
        param([Parameter(Mandatory)]$Snapshot, [bool]$ShowComparison)

        $dirtyColor = if ($Snapshot.DirtyCount -eq 0) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
        Write-Stage -Title "BRANCH $($Snapshot.Branch)" -Subtitle 'Enhanced git status and recent log' -StageIcon 'STATUS'
        if ($Snapshot.StatusAvailable) {
            Write-StatusLine -Marker '✓' -Message "Worktree: $($Snapshot.WorktreePath)" -Color Green
            Write-StatusLine -Marker $(if ($Snapshot.DirtyCount -eq 0) { '✓' } else { '→' }) -Message "Working tree changes: $($Snapshot.DirtyCount)" -Color $dirtyColor
            foreach ($line in @($Snapshot.StatusLines)) {
                Write-Host "   $line" -ForegroundColor DarkGray
            }
        }
        else {
            Write-StatusLine -Marker '◇' -Message 'No checked-out worktree for this branch; status is ref-only.' -Color Yellow
        }

        if ($ShowComparison) {
            $mainText = if ($null -eq $Snapshot.MainAhead) { 'unavailable' } else { "ahead $($Snapshot.MainAhead), behind $($Snapshot.MainBehind) vs main" }
            $originText = if ($null -eq $Snapshot.OriginAhead) { 'no origin tracking ref' } else { "ahead $($Snapshot.OriginAhead), behind $($Snapshot.OriginBehind) vs origin" }
            Write-StatusLine -Marker '↔' -Message $mainText -Color Cyan
            Write-StatusLine -Marker '↕' -Message $originText -Color Cyan
        }

        Write-Host ''
        Write-Host '  Recent log' -ForegroundColor Cyan
        foreach ($line in @($Snapshot.LogLines)) {
            Write-Host "   $line" -ForegroundColor DarkGray
        }
    }

    function Write-StatusSummary {
        param(
            [string]$Result,
            [string]$Mode,
            [string]$Repository,
            [string]$MainBranch,
            [object[]]$Snapshots,
            [timespan]$Elapsed
        )

        $dirtyBranches = @($Snapshots | Where-Object { $_.DirtyCount -gt 0 })
        $checkedOutBranches = @($Snapshots | Where-Object { $_.StatusAvailable })
        $originTracked = @($Snapshots | Where-Object { $null -ne $_.OriginAhead })
        Write-Host ''
        Write-Host '═══════════════════  GIT STATUS SUMMARY  ═══════════════════' -ForegroundColor Cyan
        Write-Host ("  Result          : {0}" -f $Result) -ForegroundColor $(if ($Result -eq 'SUCCESS') { 'Green' } else { 'Red' })
        Write-Host ("  Mode            : {0}" -f $Mode)
        Write-Host ("  Repository      : {0}" -f $Repository)
        $originUrl = Get-RemoteUrl -Repository $Repository
        Write-Host ("  Remote (origin) : {0}" -f $(if ([string]::IsNullOrWhiteSpace($originUrl)) { '(no origin remote)' } else { $originUrl }))
        Write-Host ("  Main branch     : {0}" -f $MainBranch)
        Write-Host ("  Target branches : {0}" -f @($Snapshots).Count)
        if (@($Snapshots).Count -gt 0) {
            Write-Host ("    Targets       : {0}" -f (@($Snapshots | ForEach-Object { $_.Branch }) -join ', ')) -ForegroundColor DarkGray
        }
        Write-Host ("  Checked out     : {0} / {1}" -f $checkedOutBranches.Count, @($Snapshots).Count)
        Write-Host ("  Dirty branches  : {0}" -f $dirtyBranches.Count) -ForegroundColor $(if ($dirtyBranches.Count -eq 0) { 'Green' } else { 'Yellow' })
        Write-Host ("  Origin tracked  : {0} / {1}" -f $originTracked.Count, @($Snapshots).Count)
        Write-Host ("  Elapsed         : {0:n2}s" -f $Elapsed.TotalSeconds)
        Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Cyan

        if (@($Snapshots).Count -gt 1) {
            Write-Host ''
            Write-Host '═══════════════════  COMPARISON SUMMARY  ═══════════════════' -ForegroundColor Magenta
            foreach ($snapshot in @($Snapshots)) {
                $mainText = if ($null -eq $snapshot.MainAhead) { 'main comparison unavailable' } else { "main +$($snapshot.MainAhead) / -$($snapshot.MainBehind)" }
                $originText = if ($null -eq $snapshot.OriginAhead) { 'origin none' } else { "origin +$($snapshot.OriginAhead) / -$($snapshot.OriginBehind)" }
                Write-Host ("  {0,-28} {1,-18} {2,-18} dirty {3}" -f $snapshot.Branch, $mainText, $originText, $snapshot.DirtyCount)
            }
            Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor Magenta
        }
    }

    $startedAt = Get-Date
    $mode = Get-Mode $BranchName
    $repository = ''
    $mainBranch = ''
    Write-RunBanner -DryRun ($mode -eq 'debug')

    try {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Warning 'Git is not installed or is not available on PATH.'
            return $false
        }

        $rootResult = Invoke-GitCommand '' @('rev-parse', '--show-toplevel') -SuppressError
        if ($rootResult.ExitCode -ne 0) {
            Write-Warning 'Current directory is not inside a Git repository.'
            return $false
        }
        $repository = Get-FirstOutputLine $rootResult

        Write-Stage -Title 'PREFLIGHT' -Subtitle 'Resolve repository, current branch, targets, and worktrees' -StageIcon 'SCAN'
        Write-StatusLine -Marker '✓' -Message "Git root: $repository" -Color Green

        $mainBranch = $null
        foreach ($candidate in @('main', 'master')) {
            if (Test-LocalBranch $repository $candidate) {
                $mainBranch = $candidate
                break
            }
        }
        if (-not $mainBranch) {
            Write-Warning "Cannot find a local 'main' or 'master' branch."
            return $false
        }
        Write-StatusLine -Marker '✓' -Message "Main branch: $mainBranch" -Color Green

        $localBranches = Get-LocalBranch $repository
        if ($null -eq $localBranches) {
            Write-Warning 'Local branches could not be enumerated.'
            return $false
        }
        $managedBranches = @($localBranches | Where-Object {
                -not $_.StartsWith('gitmerge-tmp-', [System.StringComparison]::Ordinal)
            })

        if ($mode -eq 'current') {
            $currentBranch = Get-CurrentBranch $repository
            if ([string]::IsNullOrWhiteSpace($currentBranch)) {
                Write-Warning 'Current HEAD is detached; pass an explicit local branch name, all, or cross-all.'
                return $false
            }
            Write-StatusLine -Marker '✓' -Message "Current branch: $currentBranch" -Color Green
            $targetBranches = @($currentBranch)
        }
        elseif ($mode -eq 'single') {
            if (-not (Test-LocalBranch $repository $BranchName)) {
                Write-Warning "Local branch '$BranchName' does not exist."
                return $false
            }
            $targetBranches = @($BranchName)
        }
        else {
            $targetBranches = @($managedBranches)
        }

        Write-StatusLine -Marker '✓' -Message "Local branches: $($managedBranches.Count)" -Color Green
        Write-StatusLine -Marker '→' -Message "Targets ($($targetBranches.Count)): $($targetBranches -join ', ')" -Color Yellow

        if ($mode -eq 'debug') {
            Write-Stage -Title 'STATUS PREVIEW' -Subtitle 'Would render status, log, and comparisons' -StageIcon 'STATUS' -Color Magenta
            return $true
        }

        $worktrees = Get-WorktreeRecord $repository
        if ($null -eq $worktrees) {
            Write-Warning 'Git worktrees could not be enumerated.'
            return $false
        }

        $snapshots = [System.Collections.Generic.List[object]]::new()
        foreach ($branch in $targetBranches) {
            $snapshot = Get-BranchSnapshot -Repository $repository -Branch $branch -MainBranch $mainBranch -Worktrees $worktrees
            $snapshots.Add($snapshot)
            Write-BranchSnapshot -Snapshot $snapshot -ShowComparison ($mode -in @('all', 'cross-all'))
        }

        Write-StatusSummary -Result 'SUCCESS' -Mode $mode -Repository $repository -MainBranch $mainBranch -Snapshots $snapshots.ToArray() -Elapsed ((Get-Date) - $startedAt)
        return $true
    }
    finally {
        # No cleanup is required; gitstatus is read-only. Surface the visual upgrade advisory (no-op
        # unless a tier was pinned but not reached, and not suppressed), consistent with gitmerge/gitsync.
        if ($null -ne $visual -and -not [string]::IsNullOrWhiteSpace($repository) -and (Get-Command Write-GitMergeToolsUpgradeAdvisory -ErrorAction SilentlyContinue)) {
            Write-GitMergeToolsUpgradeAdvisory -Visual $visual
        }
    }
}
