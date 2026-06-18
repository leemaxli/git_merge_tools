<#
.SYNOPSIS
    Safely pulls each involved origin/<branch>, runs the same per-mode topology
    as gitmerge, then pushes each converged branch to its own origin/<branch>.
.DESCRIPTION
    gitsync runs the shared transactional consolidation engine directly (no
    separate gitmerge call). It supports the same three topologies as gitmerge:

      (default / <branch>) 2-branch: current branch <-> named branch (or main).
      all                  Star:     current branch is the hub; all others are spokes.
      cross-all            Mesh:     every local managed branch converges with every other.

    Before changing any local ref, gitsync fetches origin and classifies each
    involved branch: safe (up-to-date, fast-forwardable, or cleanly diverged) or
    unsafe (conflicting diverge, or diverged with a dirty worktree). Unsafe main
    or an unsafe hub (in 'all' mode) aborts the entire run — nothing is changed.
    Unsafe non-hub spokes in all/cross-all are skipped and the rest proceed.

    After local consolidation succeeds, each converged branch is pushed to its
    own origin/<branch> with a single-ref ordinary push (never forced). A push
    rejected by origin is reported and skipped; other branches are still pushed.
.PARAMETER BranchName
    Empty (default): consolidate current branch with main.
    all:             star topology — current branch is the hub.
    cross-all:       mesh topology — all managed local branches.
    debug:           report the plan without changing refs, worktrees, or remotes.
    Any other value: 2-branch consolidation of current branch with the named branch.
#>
function gitsync {
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

    # Load the shared modules: Core (git primitives) and Merge (the transactional engine — gitsync now
    # runs the same engine directly instead of calling gitmerge). The .psm1 modules live in a Modules/
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

    function New-OptionalGitSyncVisual {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'New-OptionalGitSyncVisual loads an optional renderer and does not change Git state.'
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
                    return New-GitMergeToolsVisual -CommandName 'gitsync' -ScriptRoot $PSScriptRoot -PSCommandPath $PSCommandPath
                }
                catch {
                    $suppress = (Test-GitMergeToolsSuppressWarningLocal)
                    if (-not $suppress) {
                        Write-Warning "GitMergeTools.Common.psm1 could not initialize gitsync visuals; using built-in basic output. $($_.Exception.Message)"
                        Write-Host "  Set `$env:GITMERGE_TOOLS_COMMON_MODULE to the common module path, or place GitMergeTools.Common.psm1 in the PowerShell profile directory." -ForegroundColor Yellow
                        Write-Host "  Suppress notice: `$env:GITMERGE_TOOLS_SUPPRESS_WARNING='1'" -ForegroundColor DarkGray
                    }
                    return $null
                }
            }
        }

        $fallbackSuppress = (Test-GitMergeToolsSuppressWarningLocal)
        if (-not $fallbackSuppress) {
            Write-Warning "GitMergeTools.Common.psm1 was not found; gitsync is using built-in basic output."
            Write-Host "  Set `$env:GITMERGE_TOOLS_COMMON_MODULE to the common module path, or place GitMergeTools.Common.psm1 beside the git tool scripts." -ForegroundColor Yellow
            Write-Host "  Suppress notice: `$env:GITMERGE_TOOLS_SUPPRESS_WARNING='1'" -ForegroundColor DarkGray
        }
        return $null
    }

    $visual = New-OptionalGitSyncVisual

    function Write-RunBanner {
        param([bool]$DryRun)
        if ($null -ne $visual) {
            & $visual.WriteRunBanner -DryRun:$DryRun -Name 'gitsync'
            return
        }
        $color = if ($DryRun) { 'Magenta' } else { 'Cyan' }
        Write-Host ''
        Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor $color
        if ($DryRun) {
            Write-Host '║  GITSYNC DEBUG / DRY-RUN  Preview only; refs unchanged      ║' -ForegroundColor $color
        }
        else {
            Write-Host '║  GITSYNC  Transactional merge plus remote push              ║' -ForegroundColor $color
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

    function Write-SyncSummary {
        param(
            [string]$Result,
            [string]$Mode,
            [string]$Repository,
            [string]$MainBranch,
            [string[]]$TargetBranches,
            [string[]]$PushBranches,
            [string[]]$PushedBranches,
            [string]$FailureReason,
            [timespan]$Elapsed
        )

        $resultColor = if ($Result -eq 'SUCCESS') { [ConsoleColor]::Green } elseif ($Result -eq 'SIMULATED') { [ConsoleColor]::Magenta } elseif ($Result -eq 'ACTION NEEDED') { [ConsoleColor]::Yellow } else { [ConsoleColor]::Red }
        Write-Host ''
        Write-Host "═══════════════════  GIT SYNC SUMMARY  ═══════════════════" -ForegroundColor $resultColor
        Write-Host ("  Result          : {0}" -f $Result) -ForegroundColor $resultColor
        Write-Host ("  Mode            : {0}" -f $Mode)
        Write-Host ("  Repository      : {0}" -f $Repository)
        $originUrl = Get-RemoteUrl -Repository $Repository
        Write-Host ("  Remote (origin) : {0}" -f $(if ([string]::IsNullOrWhiteSpace($originUrl)) { '(no origin remote)' } else { $originUrl }))
        Write-Host ("  Main branch     : {0}" -f $MainBranch)
        Write-Host ("  Target branches : {0}" -f @($TargetBranches).Count)
        if (@($TargetBranches).Count -gt 0) {
            Write-Host ("    Targets       : {0}" -f (@($TargetBranches) -join ', ')) -ForegroundColor DarkGray
        }
        Write-Host ("  Push branches   : {0}" -f @($PushBranches).Count)
        if (@($PushBranches).Count -gt 0) {
            Write-Host ("    Push refs     : {0}" -f (@($PushBranches) -join ', ')) -ForegroundColor DarkGray
        }
        Write-Host ("  Pushed branches : {0} / {1}" -f @($PushedBranches).Count, @($PushBranches).Count) -ForegroundColor $(if (@($PushedBranches).Count -eq @($PushBranches).Count) { 'Green' } else { 'Yellow' })
        if (@($PushedBranches).Count -gt 0) {
            Write-Host ("    Pushed        : {0}" -f (@($PushedBranches) -join ', ')) -ForegroundColor Green
        }
        Write-Host ("  Elapsed         : {0:n2}s" -f $Elapsed.TotalSeconds)
        if (-not [string]::IsNullOrWhiteSpace($FailureReason)) {
            Write-Host ("  Failure reason  : {0}" -f $FailureReason) -ForegroundColor Red
        }
        if ($Mode -ne 'debug' -and -not [string]::IsNullOrWhiteSpace($Repository) -and -not [string]::IsNullOrWhiteSpace($MainBranch)) {
            $recent = Invoke-GitCommand $Repository @('log', '--oneline', '-10', $MainBranch) -SuppressError
            if ($recent.ExitCode -eq 0 -and @($recent.Output).Count -gt 0) {
                Write-Host ''
                Write-Host "── Recent commits on $MainBranch ──" -ForegroundColor DarkGray
                foreach ($line in @($recent.Output)) {
                    Write-Host "   $line" -ForegroundColor DarkGray
                }
            }
        }
        Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor $resultColor
    }

    $startedAt = Get-Date
    $syncResult = 'FAILED'
    $repository = ''
    $mainBranch = ''
    $targetBranches = @()
    $pushBranches = @()
    $pushedBranches = [System.Collections.Generic.List[string]]::new()
    $failureReason = ''

    try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $failureReason = 'Git is not installed or is not available on PATH.'
        Write-Warning $failureReason
        return $false
    }

    $mode = Get-Mode $BranchName
    Write-RunBanner -DryRun ($mode -eq 'debug')
    $rootResult = Invoke-GitCommand '' @('rev-parse', '--show-toplevel') -SuppressError
    if ($rootResult.ExitCode -ne 0) {
        $failureReason = 'Current directory is not inside a Git repository.'
        Write-Warning $failureReason
        return $false
    }
    $repository = Get-FirstOutputLine $rootResult

    Write-Stage -Title 'REMOTE PREFLIGHT' -Subtitle 'Verify origin and remote branch safety before local refs change' -StageIcon 'REMOTE'
    Write-StatusLine -Marker '✓' -Message "Git root: $repository" -Color Green

    $headResult = Invoke-GitCommand $repository @('rev-parse', '--verify', 'HEAD') -SuppressError
    if ($headResult.ExitCode -ne 0) {
        $failureReason = 'Repository has no commits yet. Create an initial commit before running gitsync.'
        Write-Warning $failureReason
        return $false
    }

    foreach ($candidate in @('main', 'master')) {
        if (Test-LocalBranch $repository $candidate) {
            $mainBranch = $candidate
            break
        }
    }
    if (-not $mainBranch) {
        $failureReason = "Cannot find a local 'main' or 'master' branch."
        Write-Warning $failureReason
        return $false
    }

    $remote = Invoke-GitCommand $repository @('remote', 'get-url', 'origin') -SuppressError
    if ($remote.ExitCode -ne 0) {
        $failureReason = "gitsync requires an 'origin' remote before it can change local refs."
        Write-Warning $failureReason
        return $false
    }
    Write-StatusLine -Marker '✓' -Message 'Origin remote exists.' -Color Green

    $localBranches = Get-LocalBranch $repository
    if ($null -eq $localBranches) {
        $failureReason = 'Local branches could not be enumerated.'
        Write-Warning $failureReason
        return $false
    }
    $localBranches = @($localBranches)
    $managedBranches = @($localBranches | Where-Object {
            -not $_.StartsWith('gitmerge-tmp-', [System.StringComparison]::Ordinal)
        })

    # Compute the INVOLVED branch set per mode (v7.3 topology).
    # current: X = mainBranch (empty BranchName) or BranchName; involved = {current} or {current, X}.
    # single:  X = BranchName; involved = {mainBranch} or {mainBranch, X} (mainBranch is current by convention).
    # all:     involved = {current} + others (star topology: current is hub).
    # cross-all: involved = all managed (mesh topology).
    # The sub-branch guard is owned by the topology engines for all/cross-all; gitsync no longer needs it.
    $currentBranch = Get-CurrentBranch $repository
    if (($mode -eq 'current' -or $mode -eq 'all') -and [string]::IsNullOrWhiteSpace($currentBranch)) {
        $failureReason = 'Current HEAD is detached; pass an explicit local branch name, all, or cross-all.'
        Write-Warning $failureReason
        return $false
    }

    $involved = @()
    $skipLocalMerge = $false

    if ($mode -eq 'current') {
        Write-StatusLine -Marker '✓' -Message "Current branch: $currentBranch" -Color Green
        # X = mainBranch when BranchName is empty. If X == current, pure push-only (no local merge).
        $X = $mainBranch
        if ($X -ceq $currentBranch) {
            $skipLocalMerge = $true
            $involved = @($currentBranch)
            Write-StatusLine -Marker '✓' -Message "Current branch is main ('$mainBranch'); gitsync will push main only." -Color Green
        }
        else {
            $involved = Get-UniqueBranchList @($currentBranch, $X)
        }
    }
    elseif ($mode -eq 'single') {
        if ($BranchName -ceq $mainBranch) {
            $skipLocalMerge = $true
            $involved = @($mainBranch)
            Write-StatusLine -Marker '✓' -Message "Selected branch is main ('$mainBranch'); gitsync will push main only." -Color Green
        }
        elseif (Test-LocalBranch $repository $BranchName) {
            # 2-branch: current + BranchName; resolve current for the involved set.
            if ([string]::IsNullOrWhiteSpace($currentBranch)) {
                # Detached HEAD but explicit branch selected: just use mainBranch + BranchName.
                $involved = Get-UniqueBranchList @($mainBranch, $BranchName)
            }
            else {
                $involved = Get-UniqueBranchList @($currentBranch, $BranchName)
            }
        }
        else {
            $failureReason = "Local branch '$BranchName' does not exist."
            Write-Warning $failureReason
            return $false
        }
    }
    elseif ($mode -eq 'all') {
        # Star: hub = current; spokes = all other managed.
        $otherManaged = @($managedBranches | Where-Object { $_ -cne $currentBranch })
        $involved = Get-UniqueBranchList (@($currentBranch) + $otherManaged)
        Write-StatusLine -Marker '✓' -Message "Current branch (hub): $currentBranch" -Color Green
    }
    elseif ($mode -eq 'cross-all') {
        # Mesh: all managed branches.
        $involved = Get-UniqueBranchList @($managedBranches)
    }
    else {
        # debug mode: use all managed (computed below in the debug block).
        $involved = Get-UniqueBranchList @($managedBranches)
    }

    # pushBranches initially = involved (will be refined post-merge from engine RunState).
    $pushBranches = @($involved)
    # targetBranches for summary = involved minus current/hub if mode is 2-branch or star.
    if ($mode -eq 'current' -or $mode -eq 'single') {
        $targetBranches = @($involved | Where-Object { $_ -cne ($currentBranch,$mainBranch | Select-Object -First 1) })
    }
    elseif ($mode -eq 'all') {
        $targetBranches = @($involved | Where-Object { $_ -cne $currentBranch })
    }
    else {
        $targetBranches = @($involved)
    }

    if ($mode -eq 'debug') {
        Write-StatusLine -Marker '◇' -Message 'Would fetch origin and verify remote branch ancestry before any local merge.' -Color Magenta
        Write-StatusLine -Marker '◇' -Message $(if ($skipLocalMerge) { "Would skip local merge because main was selected directly." } else { 'Would run the matching topology engine for the selected local merge scope.' }) -Color Magenta
        Write-Stage -Title 'PUSH REMOTE' -Subtitle '[DRY-RUN] Would push each converged branch to its own origin/<branch>' -StageIcon 'PUSH' -Color Magenta
        Write-StatusLine -Marker '◇' -Message "Would push (per-branch): $($involved -join ', ')" -Color Magenta
        $syncResult = 'SIMULATED'
        return $true
    }

    $fetch = Invoke-GitCommand $repository @('-c', 'fetch.prune=false', '-c', 'fetch.pruneTags=false', 'fetch', 'origin') -MergeError
    if ($fetch.ExitCode -ne 0) {
        Write-GitFailure 'Fetch from origin failed' $fetch
        $failureReason = 'Fetch from origin failed.'
        return $false
    }
    Write-StatusLine -Marker '✓' -Message 'Fetched origin before local merge.' -Color Green

    # REMOTE PULL phase (v6.x): bring origin updates into local where SAFE, else stop with ACTION NEEDED.
    # All-or-nothing + fail-fast: classify every branch READ-ONLY first; if ANY branch cannot be safely
    # synced at this stage, change nothing and prompt. Only when the whole set is safe do we mutate.
    #   Stage 2: FastForwardable + NOT checked out anywhere      -> CAS update-ref FF (no tree to disturb)
    #   Stage 3: FastForwardable + checked out + CLEAN worktree   -> merge --ff-only in that worktree
    #            FastForwardable + checked out + DIRTY worktree   -> prompt (never touch a dirty tree)
    #            Diverged                                         -> prompt (Stage 4 handles no-conflict)
    $worktrees = @(Get-WorktreeRecord $repository)
    $pullPlan = [System.Collections.Generic.List[object]]::new()
    $needManual = [System.Collections.Generic.List[object]]::new()
    $skipBranches = [System.Collections.Generic.List[string]]::new()
    foreach ($branch in $involved) {
        switch (Get-RemoteBranchSyncState -Repository $repository -Branch $branch) {
            'FastForwardable' {
                $branchWorktree = Find-BranchWorktree $worktrees $branch
                if ($null -eq $branchWorktree) {
                    # Capture the tips the FF decision is based on; the apply CAS-checks against these so a
                    # concurrent move between classify and apply refuses instead of orphaning a commit.
                    $pullPlan.Add([pscustomobject]@{
                            Branch = $branch; Method = 'ref'; Worktree = $null
                            LocalHash = (Get-RefHash $repository "refs/heads/$branch")
                            RemoteHash = (Get-RefHash $repository "refs/remotes/origin/$branch")
                        })
                }
                elseif (Test-CleanWorktree $branchWorktree) {
                    $pullPlan.Add([pscustomobject]@{ Branch = $branch; Method = 'worktree'; Worktree = $branchWorktree })
                }
                else {
                    $needManual.Add([pscustomobject]@{ Branch = $branch; Message = "origin/$branch is ahead of local '$branch', but its worktree ($($branchWorktree.Path)) is not clean (see above). Make it clean, then retry  (or:  git pull --ff-only origin $branch)." })
                }
            }
            'Diverged' {
                $mergeTree = Get-RemoteMergeTree -Repository $repository -Branch $branch
                if ($null -eq $mergeTree) {
                    $needManual.Add([pscustomobject]@{ Branch = $branch; Message = "origin/$branch and local '$branch' have diverged with conflicts. Reconcile manually (review/merge), then retry." })
                }
                else {
                    $branchWorktree = Find-BranchWorktree $worktrees $branch
                    if ($null -eq $branchWorktree) {
                        # not checked out -> worktree-free commit-tree + CAS update-ref (Stage 4a). Capture
                        # the exact tips the merge tree was computed from; the apply builds the merge commit
                        # on, and CAS-checks against, these -- so a concurrent move refuses (no stale tree).
                        $pullPlan.Add([pscustomobject]@{
                                Branch = $branch; Method = 'merge-ref'; Worktree = $null; Tree = $mergeTree
                                LocalHash = (Get-RefHash $repository "refs/heads/$branch")
                                RemoteHash = (Get-RefHash $repository "refs/remotes/origin/$branch")
                            })
                    }
                    elseif (Test-CleanWorktree $branchWorktree) {
                        # checked out + clean -> merge --no-edit in the worktree (Stage 4b).
                        $pullPlan.Add([pscustomobject]@{ Branch = $branch; Method = 'merge-worktree'; Worktree = $branchWorktree; Tree = $mergeTree })
                    }
                    else {
                        $needManual.Add([pscustomobject]@{ Branch = $branch; Message = "origin/$branch and local '$branch' have diverged, but its worktree ($($branchWorktree.Path)) is not clean (see above). Make it clean, then retry." })
                    }
                }
            }
        }
    }
    if ($needManual.Count -gt 0) {
        $mainUnsafe = @($needManual | Where-Object { $_.Branch -ceq $mainBranch })
        # HUB unsafe (all mode): current branch is the star hub -- it is never skippable.
        $hubUnsafe = ($mode -eq 'all') -and (@($needManual | Where-Object { $_.Branch -ceq $currentBranch }).Count -gt 0)
        # MAIN unsafe, HUB unsafe, or a single explicitly-selected branch is unsafe -> ABORT, change nothing.
        # (With all/cross-all there are other branches to proceed with, so non-main/non-hub targets are skipped.)
        if ($mainUnsafe.Count -gt 0 -or $hubUnsafe -or $mode -notin @('all','cross-all')) {
            Write-Stage -Title 'ACTION NEEDED' -Subtitle 'origin has updates that cannot be safely auto-pulled; nothing was changed' -StageIcon 'REMOTE' -Color Yellow
            foreach ($entry in $needManual) { Write-StatusLine -Marker '!' -Message $entry.Message -Color Yellow }
            Write-StatusLine -Marker 'i' -Message 'Nothing was changed. Resolve the above, then re-run gitsync.' -Color DarkGray
            $syncResult = 'ACTION NEEDED'
            return $false
        }
        # all/cross-all + only non-main targets unsafe -> SKIP them (exclude from pull, consolidation, and
        # push) and proceed with the rest (skip-and-proceed). Each skipped branch is left untouched.
        foreach ($entry in $needManual) {
            Write-StatusLine -Marker '✗' -Message "Skipping '$($entry.Branch)': $($entry.Message)" -Color Yellow
            [void]$skipBranches.Add($entry.Branch)
        }
    }
    if ($pullPlan.Count -gt 0) {
        Write-Stage -Title 'REMOTE PULL' -Subtitle 'Fast-forward local branches from origin (safe: not checked out, or checked out and clean)' -StageIcon 'REMOTE'
        foreach ($item in $pullPlan) {
            $remoteRef = "refs/remotes/origin/$($item.Branch)"
            if ($item.Method -eq 'ref') {
                # Worktree-free fast-forward: CAS against the CAPTURED Pass-1 local tip (Move-BranchRefSafely
                # refuses, changing nothing, if the branch moved concurrently or the move isn't a true FF).
                if (-not (Move-BranchRefSafely -Repository $repository -Branch $item.Branch -ExpectedOldHash $item.LocalHash -NewHash $item.RemoteHash)) {
                    $failureReason = "origin/$($item.Branch) could not be fast-forwarded safely: local '$($item.Branch)' changed during the sync. Nothing was pushed; re-run gitsync."
                    Write-Warning $failureReason
                    return $false
                }
            }
            elseif ($item.Method -eq 'merge-ref') {
                # Worktree-free clean merge (not checked out): build the merge commit on the CAPTURED local
                # tip (so its tree matches the merge-tree-validated tree), then CAS-advance against that tip.
                $commit = Invoke-GitCommand $repository @('commit-tree', $item.Tree, '-p', $item.LocalHash, '-p', $item.RemoteHash, '-m', "Merge origin/$($item.Branch) into $($item.Branch)") -MergeError
                if ($commit.ExitCode -ne 0) {
                    Write-GitFailure "Cannot create the merge commit for '$($item.Branch)'" $commit
                    $failureReason = "Failed to merge origin/$($item.Branch) into '$($item.Branch)'."
                    return $false
                }
                $mergeCommit = Get-FirstOutputLine $commit
                if (-not (Move-BranchRefSafely -Repository $repository -Branch $item.Branch -ExpectedOldHash $item.LocalHash -NewHash $mergeCommit)) {
                    $failureReason = "origin/$($item.Branch) could not be merged safely: local '$($item.Branch)' changed during the sync. Nothing was pushed; re-run gitsync."
                    Write-Warning $failureReason
                    return $false
                }
            }
            elseif ($item.Method -eq 'merge-worktree') {
                # checked out + clean: a real merge in the worktree (already validated clean by merge-tree).
                # git merge re-validates against the LIVE worktree tip, so a concurrent change fails safely.
                $merge = Invoke-GitCommand $item.Worktree.Path @('merge', '--no-edit', $remoteRef) -MergeError
                if ($merge.ExitCode -ne 0) {
                    # Defensive: should not happen after a clean merge-tree, but never leave a half-merge behind.
                    $mergeInProgress = (Invoke-GitCommand $item.Worktree.Path @('rev-parse', '--verify', '-q', 'MERGE_HEAD') -SuppressError).ExitCode -eq 0
                    if ($mergeInProgress) { [void](Invoke-GitCommand $item.Worktree.Path @('merge', '--abort') -MergeError) }
                    Write-GitFailure "Cannot merge origin/$($item.Branch) into '$($item.Branch)'" $merge
                    $failureReason = "Failed to merge origin/$($item.Branch) into '$($item.Branch)'."
                    return $false
                }
            }
            else {
                # 'worktree' = fast-forward in the checked-out worktree; merge --ff-only re-validates live.
                $merge = Invoke-GitCommand $item.Worktree.Path @('merge', '--ff-only', $remoteRef) -MergeError
                if ($merge.ExitCode -ne 0) {
                    Write-GitFailure "Cannot fast-forward '$($item.Branch)' from origin/$($item.Branch)" $merge
                    $failureReason = "Failed to fast-forward '$($item.Branch)' from origin."
                    return $false
                }
            }
            $how = if ($item.Method -eq 'merge-ref' -or $item.Method -eq 'merge-worktree') { 'clean merge' } else { 'fast-forward' }
            Write-StatusLine -Marker '✓' -Message "Pulled origin/$($item.Branch) into local '$($item.Branch)' ($how)." -Color Green
        }
    }
    Write-StatusLine -Marker '✓' -Message "Remote is in sync or behind local for: $($involved -join ', '). Proceeding." -Color Green

    if ($skipLocalMerge) {
        Write-StatusLine -Marker '✓' -Message "Selected main directly; no local merge phase is required before push." -Color Green
        # Push just the involved branches (main only in this case).
        $pushBranches = @($involved)
    }
    else {
        # Route to the matching topology engine (v7.3): Invoke-TwoBranchMerge / Invoke-StarMerge /
        # Invoke-MeshMerge. Each engine is the same reviewed safety machinery gitmerge uses; gitsync
        # passes pull-unsafe branches in -ExcludeBranches so the engine skips them (skip-and-proceed).
        $mergeState = [pscustomobject]@{
            DryRun = $false; Mode = $mode; Result = 'FAILED'; Repository = ''
            MainBranch = ''; WorktreeCount = 0; LocalBranchCount = 0
            TargetBranches = [System.Collections.Generic.List[string]]::new()
            IntegratedBranches = [System.Collections.Generic.List[string]]::new()
            SynchronizedBranches = [System.Collections.Generic.List[string]]::new()
            FailedBranches = [System.Collections.Generic.List[string]]::new()
            SkippedBranches = [System.Collections.Generic.List[string]]::new()
            ConflictBranch = ''; MainPublished = 'NO'; CleanupStatus = 'NOT REQUIRED'
            FailureReason = ''; Elapsed = [timespan]::Zero; SummaryEnabled = $false
        }
        if ($mode -eq 'current' -or $mode -eq 'single') {
            $mergeOk = [bool](@(Invoke-TwoBranchMerge -BranchName $BranchName -RunState $mergeState -Visual $visual) |
                Where-Object { $_ -is [bool] } | Select-Object -Last 1)
        }
        elseif ($mode -eq 'all') {
            $mergeOk = [bool](@(Invoke-StarMerge -RunState $mergeState -Visual $visual -ExcludeBranches $skipBranches.ToArray()) |
                Where-Object { $_ -is [bool] } | Select-Object -Last 1)
        }
        else {
            # cross-all -> mesh
            $mergeOk = [bool](@(Invoke-MeshMerge -RunState $mergeState -Visual $visual -ExcludeBranches $skipBranches.ToArray()) |
                Where-Object { $_ -is [bool] } | Select-Object -Last 1)
        }
        if (-not $mergeOk) {
            $failureReason = if ([string]::IsNullOrWhiteSpace($mergeState.FailureReason)) { 'Local merge phase failed; nothing was pushed.' } else { $mergeState.FailureReason }
            Write-Warning $failureReason
            return $false
        }
        # Push exactly the engine-converged branches: IntegratedBranches + SynchronizedBranches.
        # The engine is the single source of truth for skips, so we never push a branch the engine dropped.
        $pushBranches = Get-UniqueBranchList (@($mergeState.IntegratedBranches) + @($mergeState.SynchronizedBranches))
        if (@($pushBranches).Count -eq 0) {
            # Engine returned success but synced nothing (e.g. already up-to-date): push the involved set.
            $pushBranches = @($involved | Where-Object { $skipBranches -notcontains $_ })
        }
    }

    Write-Stage -Title 'PUSH REMOTE' -Subtitle 'Push each converged branch to its own origin/<branch> (per-branch, skip-on-reject)' -StageIcon 'PUSH'
    # Per-branch single-ref push (v7.3): one push per branch; a rejected ref is skipped, never forced.
    # This replaces the old single atomic push of main+targets: pushes are now topology-matched and
    # per-branch, so a rejection on one branch does not block the others.
    $failedPush = [System.Collections.Generic.List[string]]::new()
    foreach ($branch in $pushBranches) {
        $pushB = Invoke-GitCommand $repository @('push', 'origin', "refs/heads/$($branch):refs/heads/$($branch)") -MergeError
        if ($pushB.ExitCode -eq 0) {
            $pushedBranches.Add($branch)
            Write-StatusLine -Marker '✓' -Message "Pushed '$branch' to origin/$branch." -Color Green
        }
        else {
            Write-GitFailure "Push of '$branch' was rejected; skipping it (re-run after reconciling)" $pushB
            $failedPush.Add($branch)
        }
    }
    if ($failedPush.Count -gt 0) {
        Write-StatusLine -Marker '!' -Message "Rejected pushes (not forced): $($failedPush -join ', '). Re-run after reconciling." -Color Yellow
    }
    # Mark SUCCESS as soon as any branch was pushed -- the merge already happened; partial push is still
    # a completed merge. A full push-failure (all rejected) is still SUCCESS for the local merge.
    $syncResult = 'SUCCESS'

    # Refresh remote-tracking refs (best-effort, non-destructive: never prune local tags/refs as a side
    # effect of a sync). A failure here is a warning, not a failure of the already-completed push.
    $refresh = Invoke-GitCommand $repository @('-c', 'fetch.prune=false', '-c', 'fetch.pruneTags=false', 'fetch', 'origin') -MergeError
    if ($refresh.ExitCode -ne 0) {
        Write-Warning 'Remote-tracking refresh after push failed; the push already succeeded. Run "git fetch origin" later to refresh.'
    }
    else {
        Write-StatusLine -Marker '✓' -Message 'Remote-tracking refs refreshed.' -Color Green
    }
    Write-Host 'gitsync finished.' -ForegroundColor Green
    return $true
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($repository)) {
            Write-SyncSummary -Result $syncResult -Mode $mode -Repository $repository -MainBranch $mainBranch -TargetBranches $targetBranches -PushBranches $pushBranches -PushedBranches $pushedBranches.ToArray() -FailureReason $failureReason -Elapsed ((Get-Date) - $startedAt)
            # Surface the visual upgrade advisory (no-op unless a tier was pinned but not reached, and not
            # suppressed), consistent with gitmerge so every command gives the same guidance.
            if ($null -ne $visual -and (Get-Command Write-GitMergeToolsUpgradeAdvisory -ErrorAction SilentlyContinue)) {
                Write-GitMergeToolsUpgradeAdvisory -Visual $visual
            }
        }
    }
}
