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

    function Invoke-GitCommand {
        param(
            [AllowEmptyString()]
            [string]$WorkingDirectory,

            [Parameter(Mandatory)]
            [string[]]$Arguments,

            [switch]$MergeError,

            [switch]$SuppressError
        )

        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            if ([string]::IsNullOrEmpty($WorkingDirectory)) {
                if ($MergeError) {
                    $rawOutput = @(& git @Arguments 2>&1)
                }
                elseif ($SuppressError) {
                    $rawOutput = @(& git @Arguments 2>$null)
                }
                else {
                    $rawOutput = @(& git @Arguments)
                }
            }
            else {
                if ($MergeError) {
                    $rawOutput = @(& git -C $WorkingDirectory @Arguments 2>&1)
                }
                elseif ($SuppressError) {
                    $rawOutput = @(& git -C $WorkingDirectory @Arguments 2>$null)
                }
                else {
                    $rawOutput = @(& git -C $WorkingDirectory @Arguments)
                }
            }
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }

        $output = @($rawOutput | ForEach-Object { $_.ToString() })
        return [pscustomobject]@{
            ExitCode = $exitCode
            Output   = [string[]]$output
        }
    }

    function Get-FirstOutputLine {
        param([Parameter(Mandatory)]$Result)
        $lines = @($Result.Output)
        if ($lines.Count -eq 0) { return $null }
        return $lines[0].Trim()
    }

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

    function Write-GitFailure {
        param(
            [Parameter(Mandatory)][string]$Context,
            [Parameter(Mandatory)]$Result
        )
        Write-Warning "$Context (git exit $($Result.ExitCode))"
        foreach ($line in @($Result.Output)) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-Host "  $line" -ForegroundColor DarkGray
            }
        }
    }

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

    function Write-MiniProgress {
        param(
            [int]$Current,
            [int]$Total,
            [string]$Label,
            [ConsoleColor]$Color = [ConsoleColor]::Cyan
        )
        if ($null -ne $visual) {
            & $visual.WriteMiniProgress -Current $Current -Total $Total -Label $Label -Color $Color
        }
    }

    function Write-BranchTree {
        param([string]$MainBranch, [string[]]$TargetBranches)
        if ($null -ne $visual) {
            & $visual.WriteBranchTree -MainBranch $MainBranch -TargetBranches $TargetBranches
        }
    }

    function Write-SuccessBanner {
        param([string]$MainBranch, [int]$TargetCount, [string]$MainPublished)
        if ($null -ne $visual) {
            & $visual.WriteSuccessBanner -MainBranch $MainBranch -TargetCount $TargetCount -MainPublished $MainPublished -Name 'gitmerge'
            return
        }
        Write-Host ''
        Write-Host '██████████████████████████████████████████████████████████████' -ForegroundColor Green
        if ($TargetCount -eq 0 -or $MainPublished -eq 'NOT REQUIRED') {
            Write-Host '██  SUCCESS  Repository is current; nothing to merge          ██' -ForegroundColor Green
        }
        else {
            Write-Host ("██  SUCCESS  {0} published; {1} branch(es) synchronized" -f $MainBranch, $TargetCount) -ForegroundColor Green
        }
        Write-Host '██████████████████████████████████████████████████████████████' -ForegroundColor Green
    }

    function Write-RunSummary {
        param([Parameter(Mandatory)]$State)

        if ($null -ne $visual) {
            $recentLines = @()
            if (-not $State.DryRun -and -not [string]::IsNullOrWhiteSpace($State.Repository) -and -not [string]::IsNullOrWhiteSpace($State.MainBranch)) {
                $recent = Invoke-GitCommand $State.Repository @('log', '--oneline', '-5', $State.MainBranch)
                if ($recent.ExitCode -eq 0 -and @($recent.Output).Count -gt 0) {
                    $recentLines = @($recent.Output)
                }
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
        $targetCount = @($State.TargetBranches).Count
        $integratedCount = @($State.IntegratedBranches).Count
        $synchronizedCount = @($State.SynchronizedBranches).Count
        $failedCount = @($State.FailedBranches).Count

        if ($State.Result -eq 'SUCCESS') {
            Write-SuccessBanner -MainBranch $State.MainBranch -TargetCount $targetCount -MainPublished $State.MainPublished
        }

        Write-Host ''
        Write-Host "═══════════════════  GIT MERGE SUMMARY  $modeTag  ═══════════════════" -ForegroundColor Cyan
        Write-Host ("  Result                    : {0}" -f $State.Result) -ForegroundColor $resultColor
        Write-Host ("  Mode                      : {0}" -f $State.Mode)
        Write-Host ("  Repository                : {0}" -f $State.Repository)
        Write-Host ("  Main branch               : {0}" -f $State.MainBranch)
        Write-Host ("  Worktrees                 : {0}" -f $State.WorktreeCount)
        Write-Host ("  Local branches            : {0}" -f $State.LocalBranchCount)
        Write-Host ("  Target branches           : {0}" -f $targetCount)
        if ($targetCount -gt 0) {
            Write-Host ("    Targets                 : {0}" -f (@($State.TargetBranches) -join ', ')) -ForegroundColor DarkGray
        }
        Write-Host ("  Integrated into main      : {0} / {1}" -f $integratedCount, $targetCount) -ForegroundColor $(if ($integratedCount -eq $targetCount) { 'Green' } else { 'Yellow' })
        if ($integratedCount -gt 0) {
            Write-Host ("    Integrated              : {0}" -f (@($State.IntegratedBranches) -join ', ')) -ForegroundColor Green
        }
        Write-Host ("  Synchronized branches     : {0} / {1}" -f $synchronizedCount, $targetCount) -ForegroundColor $(if ($synchronizedCount -eq $targetCount) { 'Green' } else { 'Yellow' })
        if ($synchronizedCount -gt 0) {
            Write-Host ("    Synchronized            : {0}" -f (@($State.SynchronizedBranches) -join ', ')) -ForegroundColor Green
        }
        Write-Host ("  Failed branches           : {0}" -f $failedCount) -ForegroundColor $(if ($failedCount -eq 0) { 'Gray' } else { 'Red' })
        if ($failedCount -gt 0) {
            Write-Host ("    Failed                  : {0}" -f (@($State.FailedBranches) -join ', ')) -ForegroundColor Red
        }
        if (-not [string]::IsNullOrWhiteSpace($State.ConflictBranch)) {
            Write-Host ("  Conflict branch           : {0}" -f $State.ConflictBranch) -ForegroundColor Red
        }
        Write-Host ("  Main published            : {0}" -f $State.MainPublished)
        Write-Host ("  Temporary cleanup         : {0}" -f $State.CleanupStatus)
        Write-Host ("  Elapsed                   : {0:n2}s" -f $State.Elapsed.TotalSeconds)
        if (-not [string]::IsNullOrWhiteSpace($State.FailureReason)) {
            Write-Host ("  Failure reason            : {0}" -f $State.FailureReason) -ForegroundColor Red
        }

        if (-not $State.DryRun -and -not [string]::IsNullOrWhiteSpace($State.Repository) -and -not [string]::IsNullOrWhiteSpace($State.MainBranch)) {
            $recent = Invoke-GitCommand $State.Repository @('log', '--oneline', '-5', $State.MainBranch)
            if ($recent.ExitCode -eq 0 -and @($recent.Output).Count -gt 0) {
                Write-Host ''
                Write-Host "── Recent commits on $($State.MainBranch) ──" -ForegroundColor DarkGray
                foreach ($line in @($recent.Output)) {
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

    function Test-LocalBranch {
        param([string]$Repository, [string]$Name)
        $result = Invoke-GitCommand $Repository @(
            'show-ref', '--verify', '--quiet', "refs/heads/$Name"
        ) -SuppressError
        return ($result.ExitCode -eq 0)
    }

    function Get-CurrentBranch {
        param([string]$Repository)
        $result = Invoke-GitCommand $Repository @(
            'symbolic-ref', '--quiet', '--short', 'HEAD'
        ) -SuppressError
        if ($result.ExitCode -ne 0) { return $null }
        return Get-FirstOutputLine $result
    }

    function Get-LocalBranch {
        param([string]$Repository)
        $result = Invoke-GitCommand $Repository @(
            'for-each-ref', '--format=%(refname:short)', 'refs/heads/'
        )
        if ($result.ExitCode -ne 0) {
            Write-GitFailure 'Cannot enumerate local branches' $result
            return $null
        }
        return @($result.Output | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            } | Sort-Object -Unique)
    }

    function Get-WorktreeRecord {
        param([string]$Repository)
        $result = Invoke-GitCommand $Repository @('worktree', 'list', '--porcelain')
        if ($result.ExitCode -ne 0) {
            Write-GitFailure 'Cannot enumerate worktrees' $result
            return $null
        }

        $records = [System.Collections.Generic.List[object]]::new()
        $current = $null
        foreach ($line in @($result.Output) + '') {
            if ([string]::IsNullOrEmpty($line)) {
                if ($null -ne $current) {
                    $records.Add([pscustomobject]$current)
                    $current = $null
                }
                continue
            }

            if ($line.StartsWith('worktree ', [System.StringComparison]::Ordinal)) {
                $current = @{
                    Path     = $line.Substring(9)
                    Branch   = $null
                    Detached = $false
                    Locked   = $false
                    LockReason = ''
                    Prunable = $false
                }
                continue
            }

            if ($null -eq $current) { continue }
            if ($line.StartsWith('branch refs/heads/', [System.StringComparison]::Ordinal)) {
                $current.Branch = $line.Substring(18)
            }
            elseif ($line -eq 'detached') {
                $current.Detached = $true
            }
            elseif ($line.StartsWith('locked', [System.StringComparison]::Ordinal)) {
                $current.Locked = $true
                if ($line.Length -gt 7) {
                    $current.LockReason = $line.Substring(7)
                }
            }
            elseif ($line.StartsWith('prunable', [System.StringComparison]::Ordinal)) {
                $current.Prunable = $true
            }
        }
        return $records.ToArray()
    }

    function Find-BranchWorktree {
        param([object[]]$Worktrees, [string]$Branch)
        return @($Worktrees | Where-Object { $_.Branch -ceq $Branch }) | Select-Object -First 1
    }

    function Test-CleanWorktree {
        param([Parameter(Mandatory)]$Worktree)
        if ($Worktree.Locked) {
            $reason = if ([string]::IsNullOrWhiteSpace($Worktree.LockReason)) { '' } else { ": $($Worktree.LockReason)" }
            Write-Warning "Worktree for '$($Worktree.Branch)' is locked$reason. Path: $($Worktree.Path)"
            Write-Host "  If the lock is stale, run: git worktree unlock '$($Worktree.Path)'" -ForegroundColor DarkGray
            return $false
        }
        if ($Worktree.Prunable -or -not (Test-Path -LiteralPath $Worktree.Path)) {
            Write-Warning "Worktree for '$($Worktree.Branch)' is unavailable: $($Worktree.Path)"
            return $false
        }
        $status = Invoke-GitCommand $Worktree.Path @(
            'status', '--porcelain', '--untracked-files=normal'
        )
        if ($status.ExitCode -ne 0) {
            Write-GitFailure "Cannot inspect worktree '$($Worktree.Path)'" $status
            return $false
        }
        if (@($status.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            Write-Warning "Affected worktree has uncommitted changes: $($Worktree.Path)"
            return $false
        }
        return $true
    }

    function Get-RefHash {
        param([string]$Repository, [string]$Ref)
        $result = Invoke-GitCommand $Repository @('rev-parse', '--verify', $Ref) -SuppressError
        if ($result.ExitCode -ne 0) { return $null }
        return Get-FirstOutputLine $result
    }

    function Test-Ancestor {
        param([string]$Repository, [string]$Ancestor, [string]$Descendant)
        $result = Invoke-GitCommand $Repository @(
            'merge-base', '--is-ancestor', $Ancestor, $Descendant
        ) -SuppressError
        return ($result.ExitCode -eq 0)
    }

    function Test-TemporaryWorktreeForCleanup {
        param(
            [string]$Repository,
            [string]$WorktreePath,
            [string]$TemporaryBranch
        )

        if ([string]::IsNullOrWhiteSpace($WorktreePath) -or [string]::IsNullOrWhiteSpace($TemporaryBranch)) {
            return $false
        }
        if ($TemporaryBranch -notmatch '^gitmerge-tmp-[0-9a-f]{32}$') {
            return $false
        }

        $expectedPath = [System.IO.Path]::GetFullPath(
            (Join-Path ([System.IO.Path]::GetTempPath()) $TemporaryBranch)
        ).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $actualPath = [System.IO.Path]::GetFullPath($WorktreePath).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        if (-not [string]::Equals($actualPath, $expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }

        $worktrees = Get-WorktreeRecord $Repository
        if ($null -eq $worktrees) { return $false }
        $record = @($worktrees | Where-Object {
                $recordPath = [System.IO.Path]::GetFullPath($_.Path).TrimEnd(
                    [System.IO.Path]::DirectorySeparatorChar,
                    [System.IO.Path]::AltDirectorySeparatorChar
                )
                [string]::Equals($recordPath, $actualPath, [System.StringComparison]::OrdinalIgnoreCase)
            }) | Select-Object -First 1

        if ($null -eq $record) { return $false }
        if ($record.Locked) { return $false }
        return ($record.Branch -ceq $TemporaryBranch)
    }

    function Invoke-TemporaryCleanup {
        param(
            [string]$Repository,
            [string]$WorktreePath,
            [string]$TemporaryBranch
        )

        $cleanupOk = $true
        if (-not [string]::IsNullOrEmpty($WorktreePath) -and (Test-Path -LiteralPath $WorktreePath)) {
            if (-not (Test-TemporaryWorktreeForCleanup -Repository $Repository -WorktreePath $WorktreePath -TemporaryBranch $TemporaryBranch)) {
                Write-Warning "Refusing to remove unverified worktree path '$WorktreePath'."
                $cleanupOk = $false
            }
            else {
                $remove = Invoke-GitCommand $Repository @('worktree', 'remove', $WorktreePath) -MergeError
                if ($remove.ExitCode -ne 0) {
                    $forcedRemove = Invoke-GitCommand $Repository @('worktree', 'remove', '--force', $WorktreePath) -MergeError
                    if ($forcedRemove.ExitCode -ne 0) {
                        Write-GitFailure "Cannot remove verified temporary worktree '$WorktreePath'" $forcedRemove
                        $cleanupOk = $false
                    }
                }
            }
        }

        if (-not [string]::IsNullOrEmpty($TemporaryBranch)) {
            $temporaryRef = "refs/heads/$TemporaryBranch"
            $temporaryHash = Get-RefHash $Repository $temporaryRef
            if ($temporaryHash) {
                $delete = Invoke-GitCommand $Repository @(
                    'update-ref', '-d', $temporaryRef, $temporaryHash
                ) -MergeError
                if ($delete.ExitCode -ne 0) {
                    Write-GitFailure "Cannot delete temporary branch '$TemporaryBranch'" $delete
                    $cleanupOk = $false
                }
            }
        }
        return $cleanupOk
    }

    function Sync-MainFromOrigin {
        param(
            [string]$Repository,
            [string]$MainBranch,
            $MainWorktree
        )

        $remote = Invoke-GitCommand $Repository @('remote', 'get-url', 'origin') -SuppressError
        if ($remote.ExitCode -ne 0) {
            Write-Host "No origin remote; using local '$MainBranch'." -ForegroundColor DarkGray
            return $true
        }

        Write-Host 'Fetching origin...' -ForegroundColor DarkGray
        $fetch = Invoke-GitCommand $Repository @('fetch', 'origin', '--prune') -MergeError
        if ($fetch.ExitCode -ne 0) {
            Write-GitFailure 'Fetch from origin failed' $fetch
            return $false
        }

        $remoteRef = "refs/remotes/origin/$MainBranch"
        $remoteHash = Get-RefHash $Repository $remoteRef
        if (-not $remoteHash) {
            Write-Host "origin/$MainBranch does not exist; using local main." -ForegroundColor DarkGray
            return $true
        }

        $localRef = "refs/heads/$MainBranch"
        $localHash = Get-RefHash $Repository $localRef
        if ($localHash -eq $remoteHash) { return $true }
        if (Test-Ancestor -Repository $Repository -Ancestor $remoteRef -Descendant $localRef) {
            Write-Host "Local '$MainBranch' is ahead of origin/$MainBranch." -ForegroundColor DarkGray
            return $true
        }
        if (-not (Test-Ancestor -Repository $Repository -Ancestor $localRef -Descendant $remoteRef)) {
            Write-Warning "Local '$MainBranch' and origin/$MainBranch have diverged."
            return $false
        }

        if ($null -ne $MainWorktree) {
            $advance = Invoke-GitCommand $MainWorktree.Path @(
                'merge', '--ff-only', "refs/remotes/origin/$MainBranch"
            ) -MergeError
        }
        else {
            $advance = Invoke-GitCommand $Repository @(
                'update-ref', '-m', 'gitmerge: fast-forward from origin',
                $localRef, $remoteHash, $localHash
            ) -MergeError
        }
        if ($advance.ExitCode -ne 0) {
            Write-GitFailure "Cannot fast-forward '$MainBranch' from origin" $advance
            return $false
        }
        return $true
    }

    function Invoke-BranchFastForward {
        param(
            [string]$Repository,
            [string]$Branch,
            [string]$MainBranch,
            [object[]]$Worktrees
        )

        $branchRef = "refs/heads/$Branch"
        $mainRef = "refs/heads/$MainBranch"
        $oldHash = Get-RefHash $Repository $branchRef
        $mainHash = Get-RefHash $Repository $mainRef
        if (-not $oldHash -or -not $mainHash) { return $false }
        if ($oldHash -eq $mainHash) { return $true }
        if (-not (Test-Ancestor -Repository $Repository -Ancestor $branchRef -Descendant $mainRef)) {
            Write-Warning "'$Branch' is not an ancestor of '$MainBranch'; refusing to move it."
            return $false
        }

        $branchWorktree = Find-BranchWorktree $Worktrees $Branch
        if ($null -ne $branchWorktree) {
            if (-not (Test-CleanWorktree $branchWorktree)) { return $false }
            $advance = Invoke-GitCommand $branchWorktree.Path @(
                'merge', '--ff-only', "refs/heads/$MainBranch"
            ) -MergeError
        }
        else {
            $advance = Invoke-GitCommand $Repository @(
                'update-ref', '-m', "gitmerge: fast-forward $Branch to $MainBranch",
                $branchRef, $mainHash, $oldHash
            ) -MergeError
        }
        if ($advance.ExitCode -ne 0) {
            Write-GitFailure "Cannot fast-forward '$Branch' to '$MainBranch'" $advance
            return $false
        }
        return $true
    }

    $mode = switch ($BranchName) {
        { [string]::IsNullOrWhiteSpace($_) } { 'current'; break }
        'all' { 'all'; break }
        'cross-all' { 'all'; break }
        'debug' { 'debug'; break }
        default { 'single' }
    }

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

        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            $runState.FailureReason = 'Git is not installed or is not available on PATH.'
            Write-Warning $runState.FailureReason
            return $false
        }

        $rootResult = Invoke-GitCommand '' @('rev-parse', '--show-toplevel') -SuppressError
        if ($rootResult.ExitCode -ne 0) {
            $runState.FailureReason = 'Current directory is not inside a Git repository.'
            Write-Warning $runState.FailureReason
            return $false
        }
        $repository = Get-FirstOutputLine $rootResult
        $runState.Repository = $repository
        $runState.SummaryEnabled = $true

        Write-Stage -Title 'PREFLIGHT' -Subtitle 'Resolve repository, branches, and affected worktrees' -StageIcon 'SCAN'
        Write-StatusLine -Marker '✓' -Message "Git root: $repository" -Color Green

        $headResult = Invoke-GitCommand $repository @('rev-parse', '--verify', 'HEAD') -SuppressError
        if ($headResult.ExitCode -ne 0) {
            $runState.FailureReason = 'Repository has no commits yet. Create an initial commit before running gitmerge.'
            Write-Warning $runState.FailureReason
            return $false
        }

        $mainBranch = $null
        foreach ($candidate in @('main', 'master')) {
            if (Test-LocalBranch $repository $candidate) {
                $mainBranch = $candidate
                break
            }
        }
        if (-not $mainBranch) {
            $runState.FailureReason = "Cannot find a local 'main' or 'master' branch."
            Write-Warning $runState.FailureReason
            return $false
        }
        $runState.MainBranch = $mainBranch
        Write-StatusLine -Marker '✓' -Message "Main branch: $mainBranch" -Color Green

        $localBranches = Get-LocalBranch $repository
        if ($null -eq $localBranches) {
            $runState.FailureReason = 'Local branches could not be enumerated.'
            Write-Warning $runState.FailureReason
            return $false
        }
        $localBranches = @($localBranches)
        if ($localBranches.Count -eq 0) {
            $runState.FailureReason = 'No local branches could be enumerated.'
            Write-Warning $runState.FailureReason
            return $false
        }
        $managedBranches = @($localBranches | Where-Object {
            -not $_.StartsWith('gitmerge-tmp-', [System.StringComparison]::Ordinal)
        })

        if ($mode -eq 'current') {
            $currentBranch = Get-CurrentBranch $repository
            if ([string]::IsNullOrWhiteSpace($currentBranch)) {
                $runState.FailureReason = 'Current HEAD is detached; pass an explicit local branch name, all, or cross-all.'
                Write-Warning $runState.FailureReason
                return $false
            }
            Write-StatusLine -Marker '✓' -Message "Current branch: $currentBranch" -Color Green
            if ($currentBranch -ceq $mainBranch) {
                Write-Warning "Current branch is the main branch '$mainBranch'; gitmerge has no branch to consolidate."
                $targetBranches = @()
            }
            else {
                $targetBranches = @($currentBranch)
            }
        }
        elseif ($mode -eq 'single') {
            if ($BranchName -ceq $mainBranch) {
                Write-Warning "Selected branch is the main branch '$mainBranch'; gitmerge has no branch to consolidate."
                $targetBranches = @()
            }
            elseif (-not (Test-LocalBranch $repository $BranchName)) {
                $runState.FailureReason = "Local branch '$BranchName' does not exist."
                Write-Warning $runState.FailureReason
                return $false
            }
            else {
                $targetBranches = @($BranchName)
            }
        }
        else {
            $targetBranches = @($managedBranches)
        }

        # Unmerged-descendant ("sub-branch") guard (#10): skip a selected target that has a descendant
        # branch (not itself selected) carrying unmerged commits, and warn. gitmerge never loses that
        # work; this just avoids silently consolidating a branch whose children would be left behind.
        if (@($targetBranches).Count -gt 0) {
            $targetSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($t in $targetBranches) { [void]$targetSet.Add($t) }
            $keptTargets = [System.Collections.Generic.List[string]]::new()
            foreach ($target in $targetBranches) {
                $descendants = @($managedBranches | Where-Object {
                        $_ -cne $target -and $_ -cne $mainBranch -and -not $targetSet.Contains($_) -and
                        (Test-Ancestor -Repository $repository -Ancestor "refs/heads/$target" -Descendant "refs/heads/$_")
                    })
                if ($descendants.Count -gt 0) {
                    $runState.SkippedBranches.Add($target)
                    Write-StatusLine -Marker '✗' -Message "Skipping '$target': unmerged descendant branch(es): $($descendants -join ', '). Merge them back into '$target' (or select them too / use 'all') to include its work." -Color Yellow
                }
                else {
                    $keptTargets.Add($target)
                }
            }
            $targetBranches = @($keptTargets.ToArray())
        }

        $runState.LocalBranchCount = $managedBranches.Count
        foreach ($branch in $targetBranches) { $runState.TargetBranches.Add($branch) }

        Write-StatusLine -Marker '✓' -Message "Local branches: $($managedBranches.Count)" -Color Green
        if ($targetBranches.Count -eq 0) {
            $noTargetMsg = if (@($runState.SkippedBranches).Count -gt 0) {
                'All selected branches were skipped (unmerged descendants); nothing consolidated.'
            }
            else { 'No branch consolidation is required.' }
            Write-StatusLine -Marker '✓' -Message $noTargetMsg -Color Green
            $runState.Result = 'SUCCESS'
            $runState.MainPublished = 'NOT REQUIRED'
            return $true
        }
        Write-StatusLine -Marker '→' -Message "Targets ($($targetBranches.Count)): $($targetBranches -join ', ')" -Color Yellow
        Write-BranchTree -MainBranch $mainBranch -TargetBranches $targetBranches

        $worktrees = Get-WorktreeRecord $repository
        if ($null -eq $worktrees) {
            $runState.FailureReason = 'Git worktrees could not be enumerated.'
            Write-Warning $runState.FailureReason
            return $false
        }
        $worktrees = @($worktrees)
        if ($worktrees.Count -eq 0) {
            $runState.FailureReason = 'No Git worktrees could be enumerated.'
            Write-Warning $runState.FailureReason
            return $false
        }
        $runState.WorktreeCount = $worktrees.Count
        Write-StatusLine -Marker '✓' -Message "Worktrees discovered: $($worktrees.Count)" -Color Green
        $mainWorktree = Find-BranchWorktree $worktrees $mainBranch

        $affectedWorktrees = @($worktrees | Where-Object {
            $_.Branch -ceq $mainBranch -or $_.Branch -cin $targetBranches
        })
        $preflightOk = $true
        foreach ($worktree in $affectedWorktrees) {
            if (-not (Test-CleanWorktree $worktree)) { $preflightOk = $false }
        }
        if (-not $preflightOk) {
            $runState.FailureReason = 'No refs were changed because an affected worktree is not clean.'
            Write-Warning $runState.FailureReason
            return $false
        }
        Write-StatusLine -Marker '✓' -Message 'Affected worktrees are clean.' -Color Green

        if ($mode -eq 'debug') {
            Write-Stage -Title 'REMOTE SYNC' -Subtitle '[DRY-RUN] Would fetch origin when configured' -StageIcon 'REMOTE' -Color Magenta
            Write-StatusLine -Marker '◇' -Message "Would synchronize origin/$mainBranch when fast-forwardable." -Color Magenta
            Write-Stage -Title 'TEMPORARY INTEGRATION' -Subtitle '[DRY-RUN] Would stage all merges before publishing main' -StageIcon 'MERGE' -Color Magenta
            $mergeIndex = 0
            foreach ($branch in $targetBranches) {
                $mergeIndex++
                Write-MiniProgress -Current $mergeIndex -Total $targetBranches.Count -Label 'Merging' -Color Yellow
                Write-Host "── Merge [$branch] → [$mainBranch] (simulated) ──" -ForegroundColor Yellow
                Write-StatusLine -Marker '◇' -Message "Would merge '$branch' in a temporary worktree." -Color Magenta
                $runState.IntegratedBranches.Add($branch)
            }
            Write-Stage -Title 'PUBLISH MAIN' -Subtitle '[DRY-RUN] Would fast-forward main only after all merges succeed' -StageIcon 'PUSH' -Color Magenta
            Write-StatusLine -Marker '◇' -Message "Would publish the integrated commit to '$mainBranch'." -Color Magenta
            Write-Stage -Title 'SYNCHRONIZE BRANCHES' -Subtitle '[DRY-RUN] Would fast-forward each target branch to main' -StageIcon 'SYNC' -Color Magenta
            $syncIndex = 0
            foreach ($branch in $targetBranches) {
                $syncIndex++
                Write-MiniProgress -Current $syncIndex -Total $targetBranches.Count -Label 'Synchronizing' -Color Cyan
                Write-StatusLine -Marker '◇' -Message "Would synchronize '$branch' to '$mainBranch'." -Color Magenta
                $runState.SynchronizedBranches.Add($branch)
            }
            $runState.Result = 'SIMULATED'
            $runState.MainPublished = 'NOT REQUIRED'
            return $true
        }

        Write-Stage -Title 'REMOTE SYNC' -Subtitle "Fetch origin and fast-forward '$mainBranch' when possible" -StageIcon 'REMOTE'
        if (-not (Sync-MainFromOrigin -Repository $repository -MainBranch $mainBranch -MainWorktree $mainWorktree)) {
            $runState.FailureReason = 'Remote synchronization failed or main has diverged.'
            return $false
        }
        Write-StatusLine -Marker '✓' -Message "Remote synchronization check completed for '$mainBranch'." -Color Green

        $startingMainHash = Get-RefHash $repository "refs/heads/$mainBranch"
        if (-not $startingMainHash) {
            $runState.FailureReason = "Cannot resolve '$mainBranch'."
            Write-Warning $runState.FailureReason
            return $false
        }

        do {
            $suffix = [guid]::NewGuid().ToString('N')
            $temporaryBranch = "gitmerge-tmp-$suffix"
        } while (Test-LocalBranch $repository $temporaryBranch)
        $temporaryWorktree = Join-Path ([System.IO.Path]::GetTempPath()) $temporaryBranch
        $integrationReady = $false
        $published = $false

        try {
            Write-Stage -Title 'TEMPORARY INTEGRATION' -Subtitle 'Merge every target before changing the real main branch' -StageIcon 'MERGE'
            Write-StatusLine -Marker '→' -Message "Creating temporary branch '$temporaryBranch'." -Color Cyan
            $create = Invoke-GitCommand $repository @(
                'worktree', 'add', '-b', $temporaryBranch, $temporaryWorktree, "refs/heads/$mainBranch"
            ) -MergeError
            if ($create.ExitCode -ne 0) {
                Write-GitFailure 'Cannot create the integration worktree' $create
                $runState.FailureReason = 'Cannot create the temporary integration worktree.'
                return $false
            }
            Write-StatusLine -Marker '✓' -Message "Temporary worktree: $temporaryWorktree" -Color Green

            $mergeIndex = 0
            foreach ($branch in $targetBranches) {
                $mergeIndex++
                Write-MiniProgress -Current $mergeIndex -Total $targetBranches.Count -Label 'Merging' -Color Yellow
                Write-Host "── Merge [$branch] → [$mainBranch] (staged) ──" -ForegroundColor Yellow
                $merge = Invoke-GitCommand $temporaryWorktree @(
                    'merge', '--no-edit', '-m', "Merge branch '$branch' into $mainBranch", "refs/heads/$branch"
                ) -MergeError
                if ($merge.ExitCode -ne 0) {
                    Write-GitFailure "Merge conflict or failure in '$branch'" $merge
                    $runState.ConflictBranch = $branch
                    $runState.FailedBranches.Add($branch)
                    $runState.FailureReason = "Temporary integration failed while merging '$branch'."
                    $mergeInProgress = (Invoke-GitCommand $temporaryWorktree @('rev-parse', '--verify', '-q', 'MERGE_HEAD') -SuppressError).ExitCode -eq 0
                    if ($mergeInProgress) {
                        $abort = Invoke-GitCommand $temporaryWorktree @('merge', '--abort') -MergeError
                        if ($abort.ExitCode -ne 0) {
                            Write-GitFailure 'Cannot abort the temporary merge; leaving temporary state for manual inspection' $abort
                        }
                    }
                    Write-Warning "Main and target refs were not changed. Resolve '$branch' manually, then retry."
                    return $false
                }
                $runState.IntegratedBranches.Add($branch)
                Write-StatusLine -Marker '✓' -Message "Integrated '$branch' into the staged main history." -Color Green
            }
            $integrationReady = $true

            $currentMainHash = Get-RefHash $repository "refs/heads/$mainBranch"
            if ($currentMainHash -ne $startingMainHash) {
                $runState.FailureReason = "'$mainBranch' changed during integration; refusing to publish a stale result."
                Write-Warning $runState.FailureReason
                return $false
            }

            $integrationHash = Get-RefHash $repository "refs/heads/$temporaryBranch"
            if (-not $integrationHash -or -not (Test-Ancestor -Repository $repository -Ancestor $mainBranch -Descendant $temporaryBranch)) {
                $runState.FailureReason = 'The temporary integration result is not a fast-forward of main.'
                Write-Warning $runState.FailureReason
                return $false
            }

            Write-Stage -Title 'PUBLISH MAIN' -Subtitle 'Advance the real main branch to the verified integration commit' -StageIcon 'PUSH'
            $publish = $null
            if ($null -ne $mainWorktree) {
                if (-not (Test-CleanWorktree $mainWorktree)) {
                    $runState.FailureReason = 'The main worktree changed after preflight.'
                    return $false
                }
                $publish = Invoke-GitCommand $mainWorktree.Path @(
                    'merge', '--ff-only', "refs/heads/$temporaryBranch"
                ) -MergeError
            }
            else {
                $publish = Invoke-GitCommand $repository @(
                    'update-ref', '-m', 'gitmerge: publish integration result',
                    "refs/heads/$mainBranch", $integrationHash, $startingMainHash
                ) -MergeError
            }
            if ($publish.ExitCode -ne 0) {
                Write-GitFailure "Cannot publish integration result to '$mainBranch'" $publish
                $runState.FailureReason = "Cannot publish the integration result to '$mainBranch'."
                return $false
            }
            $published = $true
            $runState.MainPublished = 'YES'
            Write-StatusLine -Marker '✓' -Message "Published integrated history to '$mainBranch'." -Color Green

            Write-Stage -Title 'SYNCHRONIZE BRANCHES' -Subtitle 'Fast-forward each selected branch to the published main commit' -StageIcon 'SYNC'
            $failedUpdates = [System.Collections.Generic.List[string]]::new()
            $syncIndex = 0
            foreach ($branch in $targetBranches) {
                $syncIndex++
                Write-MiniProgress -Current $syncIndex -Total $targetBranches.Count -Label 'Synchronizing' -Color Cyan
                Write-Host "── Synchronize [$mainBranch] → [$branch] ──" -ForegroundColor Yellow
                if (-not (Invoke-BranchFastForward -Repository $repository -Branch $branch -MainBranch $mainBranch -Worktrees $worktrees)) {
                    $failedUpdates.Add($branch)
                    $runState.FailedBranches.Add($branch)
                    Write-StatusLine -Marker '✗' -Message "Could not synchronize '$branch'." -Color Red
                }
                else {
                    $runState.SynchronizedBranches.Add($branch)
                    Write-StatusLine -Marker '✓' -Message "Synchronized '$branch' to '$mainBranch'." -Color Green
                }
            }

            if ($failedUpdates.Count -gt 0) {
                Write-Warning "Main was updated, but these branches could not be fast-forwarded: $($failedUpdates -join ', ')"
                $runState.FailureReason = "Main was published, but one or more target branches could not be synchronized."
                return $false
            }

            $runState.Result = 'SUCCESS'
            return $true
        }
        finally {
            Write-Stage -Title 'CLEANUP' -Subtitle 'Remove temporary worktree and branch' -StageIcon 'CLEAN'
            $cleanupOk = Invoke-TemporaryCleanup -Repository $repository -WorktreePath $temporaryWorktree -TemporaryBranch $temporaryBranch
            $runState.CleanupStatus = if ($cleanupOk) { 'CLEAN' } else { 'FAILED' }
            if ($cleanupOk) {
                Write-StatusLine -Marker '✓' -Message 'Temporary integration state removed.' -Color Green
            }
            else {
                Write-StatusLine -Marker '✗' -Message 'Temporary cleanup was incomplete.' -Color Red
                if ([string]::IsNullOrWhiteSpace($runState.FailureReason)) {
                    $runState.FailureReason = 'Temporary cleanup was incomplete.'
                }
                $runState.Result = 'FAILED'
            }
            if ($integrationReady -and -not $published) {
                Write-StatusLine -Marker '↺' -Message 'Staged integration was discarded without changing main.' -Color DarkGray
            }
        }
    }
    finally {
        if ($runState.SummaryEnabled) {
            $runState.Elapsed = (Get-Date) - $startedAt
            Write-RunSummary -State $runState
        }
    }
}
