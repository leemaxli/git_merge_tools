[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'The engine emits a few plain progress/diagnostic lines; richer output is the caller renderer.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseShouldProcessForStateChangingFunctions',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'State changes are guarded by THE HARD CONSTRAINT invariants (ancestor/CAS/clean-worktree/path-verified cleanup).'
)][Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSProvideCommentHelp',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'Transactional merge-engine helpers shared by the git commands.'
)]
param()

# GitMergeTools.Merge.psm1 — the transactional merge engine's safety-critical helpers, shared by the
# commands (currently gitmerge; gitsync becomes a peer consumer in a later slice). These carry the
# HARD-CONSTRAINT invariants: ancestor-guarded fast-forwards, compare-and-swap ref updates, affected-
# worktree cleanliness, and path+pattern-verified temporary-worktree cleanup. No UI beyond a few plain
# progress lines; the caller supplies the rich renderer. Depends on Core for the git primitives.
Import-Module (Join-Path $PSScriptRoot 'GitMergeTools.Core.psm1') -ErrorAction Stop

function Get-WorktreeInProgressOperation {
    # Returns a human operation name ('a merge' / 'a rebase' / 'a cherry-pick' / 'a revert') if the
    # worktree is mid-operation, else $null. Each operation drops a marker in the worktree's OWN git dir;
    # resolving every marker via `git rev-parse --git-path` keeps this correct for linked worktrees, whose
    # state lives under .git/worktrees/<name>/ rather than the repository root.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Worktree)

    if ($null -eq $Worktree -or [string]::IsNullOrWhiteSpace($Worktree.Path) -or -not (Test-Path -LiteralPath $Worktree.Path)) {
        return $null
    }
    $markers = @(
        @{ Name = 'MERGE_HEAD'; Op = 'a merge' },
        @{ Name = 'CHERRY_PICK_HEAD'; Op = 'a cherry-pick' },
        @{ Name = 'REVERT_HEAD'; Op = 'a revert' },
        @{ Name = 'REBASE_HEAD'; Op = 'a rebase' },
        @{ Name = 'rebase-merge'; Op = 'a rebase' },
        @{ Name = 'rebase-apply'; Op = 'a rebase' }
    )
    foreach ($marker in $markers) {
        $resolved = Invoke-GitCommand $Worktree.Path @('rev-parse', '--git-path', $marker.Name) -SuppressError
        if ($resolved.ExitCode -ne 0) { continue }
        $markerPath = Get-FirstOutputLine $resolved
        if ([string]::IsNullOrWhiteSpace($markerPath)) { continue }
        if (-not [System.IO.Path]::IsPathRooted($markerPath)) {
            $markerPath = [System.IO.Path]::GetFullPath((Join-Path $Worktree.Path $markerPath))
        }
        if (Test-Path -LiteralPath $markerPath) { return $marker.Op }
    }
    return $null
}

function Get-RemoteBranchSyncState {
    # Pure classifier driving the gitsync REMOTE PULL phase (v6.x): how does local <Branch> relate to
    # origin/<Branch>?  Returns:
    #   'UpToDate'        - equal, or no origin branch (nothing to pull)
    #   'LocalAhead'      - origin is a strict ancestor of local (normal push case)
    #   'FastForwardable' - local is a strict ancestor of origin (a safe pull would advance local)
    #   'Diverged'        - neither is an ancestor of the other
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Branch
    )

    $localRef = "refs/heads/$Branch"
    $remoteRef = "refs/remotes/origin/$Branch"
    $localHash = Get-RefHash $Repository $localRef
    $remoteHash = Get-RefHash $Repository $remoteRef
    if (-not $remoteHash) { return 'UpToDate' }       # nothing on origin to pull
    if (-not $localHash) { return 'FastForwardable' } # origin has it, local doesn't (a pull would create it)
    if ($localHash -eq $remoteHash) { return 'UpToDate' }
    if (Test-Ancestor -Repository $Repository -Ancestor $remoteRef -Descendant $localRef) { return 'LocalAhead' }
    if (Test-Ancestor -Repository $Repository -Ancestor $localRef -Descendant $remoteRef) { return 'FastForwardable' }
    return 'Diverged'
}

function Get-RemoteMergeTree {
    # In-memory merge probe for the gitsync REMOTE PULL phase (Stage 4): would merging origin/<Branch>
    # into local <Branch> apply with NO conflict?  `git merge-tree --write-tree` performs a real merge
    # entirely in the object store -- it touches NO worktree and changes NO ref -- exiting 0 (and printing
    # the merged tree OID) when clean, or 1 when conflicting. Returns the merged tree OID on a clean merge,
    # else $null. The caller turns that tree into a merge commit (commit-tree) only when it decides to apply.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Branch
    )

    $result = Invoke-GitCommand $Repository @(
        'merge-tree', '--write-tree', "refs/heads/$Branch", "refs/remotes/origin/$Branch"
    ) -MergeError
    if ($result.ExitCode -ne 0) { return $null }   # 1 = conflict, >1 = error -> not cleanly mergeable
    return Get-FirstOutputLine $result
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
    # Refuse a worktree that is mid-operation BEFORE the porcelain check, so the diagnostic names the
    # actual operation (a merge/rebase/cherry-pick/revert) rather than just calling it "uncommitted".
    $inProgress = Get-WorktreeInProgressOperation -Worktree $Worktree
    if ($inProgress) {
        Write-Warning "Affected worktree has $inProgress in progress: $($Worktree.Path)"
        Write-Host '  Finish or abort it (e.g. git merge --abort / git rebase --abort), then retry.' -ForegroundColor DarkGray
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
    # Non-destructive fetch: never prune local-only tags/refs as a side effect of a user's
    # fetch.prune/fetch.pruneTags config (#2's twin; mirrors gitsync's hardened fetch).
    $fetch = Invoke-GitCommand $Repository @('-c', 'fetch.prune=false', '-c', 'fetch.pruneTags=false', 'fetch', 'origin') -MergeError
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

function Invoke-GitMergeConsolidation {
    # The transactional consolidation engine, shared by gitmerge and gitsync. Renders in-transaction
    # progress through the caller's $Visual; mutates the caller-supplied $RunState (including its actual
    # SynchronizedBranches set, which gitsync pushes verbatim) and returns $true/$false. The caller owns
    # the run banner (before) and the run summary (after).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive, colorized engine output.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$BranchName = '',
        [Parameter(Mandatory)]$RunState,
        $Visual
    )

    function Write-Stage {
        param([string]$Title, [string]$Subtitle, [string]$StageIcon, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
        if ($null -ne $Visual) {
            & $Visual.WriteStage -Title $Title -Subtitle $Subtitle -StageIcon $StageIcon -Color $Color
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
        param([string]$Marker, [string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
        if ($null -ne $Visual) {
            & $Visual.WriteStatusLine -Marker $Marker -Message $Message -Color $Color
            return
        }
        Write-Host ("   {0,-3} {1}" -f $Marker, $Message) -ForegroundColor $Color
    }

    function Write-MiniProgress {
        param([int]$Current, [int]$Total, [string]$Label, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
        if ($null -ne $Visual) {
            & $Visual.WriteMiniProgress -Current $Current -Total $Total -Label $Label -Color $Color
        }
    }

    function Write-BranchTree {
        param([string]$MainBranch, [string[]]$TargetBranches)
        if ($null -ne $Visual) {
            & $Visual.WriteBranchTree -MainBranch $MainBranch -TargetBranches $TargetBranches
        }
    }

    $mode = Get-Mode $BranchName

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

Export-ModuleMember -Function @(
    'Get-WorktreeInProgressOperation',
    'Get-RemoteBranchSyncState',
    'Get-RemoteMergeTree',
    'Test-CleanWorktree',
    'Test-TemporaryWorktreeForCleanup',
    'Invoke-TemporaryCleanup',
    'Sync-MainFromOrigin',
    'Invoke-BranchFastForward',
    'Invoke-GitMergeConsolidation'
)
