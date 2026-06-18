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

function Move-BranchRefSafely {
    # Advance a local branch to NewHash with a compare-and-swap update-ref, but ONLY if BOTH hold:
    #   (a) NewHash is a true fast-forward of ExpectedOldHash (descends it) -- never orphans a commit; and
    #   (b) the ref is still exactly ExpectedOldHash (the value the decision was based on).
    # The gitsync worktree-free pull paths ('ref' fast-forward, 'merge-ref' clean-merge) call this with the
    # hashes captured at classify time, so a branch advanced by a concurrent writer between classify and
    # apply makes (b) fail and we refuse, changing nothing -- closing the between-pass data-loss race.
    # Returns $true only when the ref was advanced. Mirrors Invoke-BranchFastForward's ancestor+CAS guard.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$ExpectedOldHash,
        [Parameter(Mandatory)][string]$NewHash,
        [string]$Message = 'gitsync: sync from origin'
    )

    if ($ExpectedOldHash -eq $NewHash) { return $true }   # already there; nothing to do
    if (-not (Test-Ancestor -Repository $Repository -Ancestor $ExpectedOldHash -Descendant $NewHash)) {
        return $false   # not a fast-forward of the decided-on tip -> never move sideways
    }
    $update = Invoke-GitCommand $Repository @(
        'update-ref', '-m', $Message, "refs/heads/$Branch", $NewHash, $ExpectedOldHash
    ) -MergeError
    return ($update.ExitCode -eq 0)   # CAS: fails (no change) if the ref moved off ExpectedOldHash
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
        $Visual,
        [string[]]$ExcludeBranches = @()
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

        # Caller-supplied exclusions (gitsync passes origin-pull-unsafe targets here -- e.g. a conflicting
        # divergence it already warned about): drop them from the consolidation set (skip-and-proceed).
        if (@($ExcludeBranches).Count -gt 0 -and @($targetBranches).Count -gt 0) {
            $excludeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($excluded in $ExcludeBranches) { [void]$excludeSet.Add($excluded) }
            $keptAfterExclude = [System.Collections.Generic.List[string]]::new()
            foreach ($target in $targetBranches) {
                if ($excludeSet.Contains($target)) {
                    if (-not $runState.SkippedBranches.Contains($target)) { $runState.SkippedBranches.Add($target) }
                }
                else { $keptAfterExclude.Add($target) }
            }
            $targetBranches = @($keptAfterExclude.ToArray())
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

        # MAIN must be clean -- everything is consolidated through it; an unclean main aborts the run.
        if ($null -ne $mainWorktree -and -not (Test-CleanWorktree $mainWorktree)) {
            $runState.FailureReason = "No refs were changed because the '$mainBranch' worktree is not clean."
            Write-Warning $runState.FailureReason
            return $false
        }
        # A TARGET whose worktree can't safely participate (dirty / mid-operation) is SKIPPED with a
        # warning -- the rest still consolidate (skip-and-proceed, consistent with the #10 sub-branch skip).
        $cleanTargets = [System.Collections.Generic.List[string]]::new()
        foreach ($target in $targetBranches) {
            $targetWorktree = Find-BranchWorktree $worktrees $target
            if ($null -ne $targetWorktree -and -not (Test-CleanWorktree $targetWorktree)) {
                if (-not $runState.SkippedBranches.Contains($target)) { $runState.SkippedBranches.Add($target) }
                Write-StatusLine -Marker '✗' -Message "Skipping '$target': its worktree is not clean (see above). Commit/stash it, then re-run to include it." -Color Yellow
            }
            else {
                $cleanTargets.Add($target)
            }
        }
        $targetBranches = @($cleanTargets.ToArray())
        # Keep the run-state target list in sync with what will actually be consolidated.
        $runState.TargetBranches.Clear()
        foreach ($branch in $targetBranches) { $runState.TargetBranches.Add($branch) }
        if ($targetBranches.Count -eq 0) {
            Write-StatusLine -Marker '✓' -Message 'All selected branches were skipped; nothing to consolidate.' -Color Green
            $runState.Result = 'SUCCESS'
            $runState.MainPublished = 'NOT REQUIRED'
            return $true
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

function Invoke-TwoBranchMerge {
    # 2-branch bidirectional merge engine (v7.0): merges the current branch and target X so BOTH
    # converge to their union. De-main-centered: main is touched only when it IS current or X.
    # Safety machinery mirrors Invoke-GitMergeConsolidation: throwaway worktree -> merge --no-edit
    # to validate and build the union -> staleness CAS re-check -> fast-forward BOTH real refs ->
    # cleanup in finally. Never resets, rebases, or force-moves anything.
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
        Write-Host '----------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host "  $Title" -ForegroundColor $Color
        if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
            Write-Host "  $Subtitle" -ForegroundColor DarkGray
        }
        Write-Host '----------------------------------------------------------' -ForegroundColor DarkGray
    }

    function Write-StatusLine {
        param([string]$Marker, [string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
        if ($null -ne $Visual) {
            & $Visual.WriteStatusLine -Marker $Marker -Message $Message -Color $Color
            return
        }
        Write-Host ("   {0,-3} {1}" -f $Marker, $Message) -ForegroundColor $Color
    }

    # Step 1: Resolve repository.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $RunState.FailureReason = 'Git is not installed or is not available on PATH.'
        Write-Warning $RunState.FailureReason
        return $false
    }
    $rootResult = Invoke-GitCommand '' @('rev-parse', '--show-toplevel') -SuppressError
    if ($rootResult.ExitCode -ne 0) {
        $RunState.FailureReason = 'Current directory is not inside a Git repository.'
        Write-Warning $RunState.FailureReason
        return $false
    }
    $repository = Get-FirstOutputLine $rootResult
    $RunState.Repository = $repository
    $RunState.SummaryEnabled = $true

    Write-Stage -Title 'PREFLIGHT' -Subtitle 'Resolve repository, branches, and affected worktrees' -StageIcon 'SCAN'
    Write-StatusLine -Marker 'i' -Message "Git root: $repository" -Color Green

    # Step 2: HEAD must have a commit; get current branch.
    $headResult = Invoke-GitCommand $repository @('rev-parse', '--verify', 'HEAD') -SuppressError
    if ($headResult.ExitCode -ne 0) {
        $RunState.FailureReason = 'Repository has no commits yet. Create an initial commit before running gitmerge.'
        Write-Warning $RunState.FailureReason
        return $false
    }
    $current = Get-CurrentBranch $repository
    if ([string]::IsNullOrWhiteSpace($current)) {
        $RunState.FailureReason = 'Current HEAD is detached; pass an explicit branch, all, or cross-all.'
        Write-Warning $RunState.FailureReason
        return $false
    }
    Write-StatusLine -Marker 'i' -Message "Current branch: $current" -Color Green

    # Step 3: Resolve X.
    $X = $null
    if ([string]::IsNullOrWhiteSpace($BranchName)) {
        foreach ($candidate in @('main', 'master')) {
            if (Test-LocalBranch $repository $candidate) { $X = $candidate; break }
        }
        if (-not $X) {
            $RunState.FailureReason = "Cannot find a local 'main' or 'master' branch."
            Write-Warning $RunState.FailureReason
            return $false
        }
    }
    else {
        $X = $BranchName
        if (-not (Test-LocalBranch $repository $X)) {
            $RunState.FailureReason = "Local branch '$X' does not exist."
            Write-Warning $RunState.FailureReason
            return $false
        }
    }
    Write-StatusLine -Marker 'i' -Message "Target branch: $X" -Color Green

    # Step 4: X == current -> reminder no-op.
    if ($X -ceq $current) {
        Write-StatusLine -Marker 'i' -Message "Target '$X' is the current branch; nothing to merge." -Color DarkGray
        $RunState.Result = 'SUCCESS'
        $RunState.MainBranch = $current
        $RunState.MainPublished = 'NOT REQUIRED'
        return $true
    }

    # Step 5: Get worktree records.
    $worktrees = Get-WorktreeRecord $repository
    if ($null -eq $worktrees) {
        $RunState.FailureReason = 'Git worktrees could not be enumerated.'
        Write-Warning $RunState.FailureReason
        return $false
    }
    $worktrees = @($worktrees)
    $RunState.WorktreeCount = $worktrees.Count
    $curWt = Find-BranchWorktree $worktrees $current
    $xWt = Find-BranchWorktree $worktrees $X

    # Step 6: Preflight cleanliness (no main requirement; just current and X worktrees).
    if ($null -ne $curWt -and -not (Test-CleanWorktree $curWt)) {
        $RunState.FailureReason = "No refs were changed because the '$current' worktree is not clean."
        Write-Warning $RunState.FailureReason
        return $false
    }
    if ($null -ne $xWt -and -not (Test-CleanWorktree $xWt)) {
        $RunState.FailureReason = "No refs were changed because the '$X' worktree is not clean."
        Write-Warning $RunState.FailureReason
        return $false
    }
    Write-StatusLine -Marker 'i' -Message 'Affected worktrees are clean.' -Color Green

    # Step 7: Capture old tips.
    # NOTE: The #10 sub-branch skip guard is intentionally ABSENT here. In the 2-branch path,
    # advancing X to the union is a pure fast-forward — it loses no work from any descendant of X.
    # Descendants simply stay where they are (untouched) with all their commits intact.
    # The #10 guard remains in Invoke-GitMergeConsolidation (used by all/cross-all/gitsync) where
    # it protects against silently consolidating mid-flight work through main.
    $curOld = Get-RefHash $repository "refs/heads/$current"
    $xOld = Get-RefHash $repository "refs/heads/$X"
    if (-not $curOld -or -not $xOld) {
        $RunState.FailureReason = 'Cannot resolve branch tip hashes.'
        Write-Warning $RunState.FailureReason
        return $false
    }

    # Step 8: Create throwaway worktree at current's tip.
    $suffix = $null
    do {
        $suffix = [guid]::NewGuid().ToString('N')
        $temporaryBranch = "gitmerge-tmp-$suffix"
    } while (Test-LocalBranch $repository $temporaryBranch)
    $temporaryWorktree = Join-Path ([System.IO.Path]::GetTempPath()) $temporaryBranch

    try {
        Write-Stage -Title 'TEMPORARY MERGE' -Subtitle "Build and validate the union of '$current' and '$X' before touching real refs" -StageIcon 'MERGE'
        Write-StatusLine -Marker '->' -Message "Creating temporary branch '$temporaryBranch' at '$current'." -Color Cyan
        $create = Invoke-GitCommand $repository @(
            'worktree', 'add', '-b', $temporaryBranch, $temporaryWorktree, "refs/heads/$current"
        ) -MergeError
        if ($create.ExitCode -ne 0) {
            Write-GitFailure 'Cannot create the temporary merge worktree' $create
            $RunState.FailureReason = 'Cannot create the temporary merge worktree.'
            return $false
        }
        Write-StatusLine -Marker 'i' -Message "Temporary worktree: $temporaryWorktree" -Color Green

        # Step 9: Merge X into the throwaway to build the union.
        $merge = Invoke-GitCommand $temporaryWorktree @(
            'merge', '--no-edit', '-m', "Merge branch '$X' into '$current'", "refs/heads/$X"
        ) -MergeError
        if ($merge.ExitCode -ne 0) {
            Write-GitFailure "Merge conflict or failure merging '$X' into '$current'" $merge
            $RunState.ConflictBranch = $X
            $RunState.FailureReason = "Conflict merging '$X' into '$current'."
            $mergeInProgress = (Invoke-GitCommand $temporaryWorktree @('rev-parse', '--verify', '-q', 'MERGE_HEAD') -SuppressError).ExitCode -eq 0
            if ($mergeInProgress) {
                $abort = Invoke-GitCommand $temporaryWorktree @('merge', '--abort') -MergeError
                if ($abort.ExitCode -ne 0) {
                    Write-GitFailure 'Cannot abort the temporary merge; leaving temporary state for manual inspection' $abort
                }
            }
            Write-Warning "No refs were changed. Resolve the conflict in '$X' manually, then retry."
            return $false
        }

        # Step 10: Get union tip; sanity-check descent.
        $unionTip = Get-RefHash $repository "refs/heads/$temporaryBranch"
        if (-not $unionTip) {
            $RunState.FailureReason = 'Cannot resolve union tip hash after merge.'
            Write-Warning $RunState.FailureReason
            return $false
        }
        if (-not (Test-Ancestor -Repository $repository -Ancestor "refs/heads/$current" -Descendant "refs/heads/$temporaryBranch")) {
            $RunState.FailureReason = "The union does not descend '$current' — internal sanity check failed."
            Write-Warning $RunState.FailureReason
            return $false
        }
        if (-not (Test-Ancestor -Repository $repository -Ancestor "refs/heads/$X" -Descendant "refs/heads/$temporaryBranch")) {
            $RunState.FailureReason = "The union does not descend '$X' — internal sanity check failed."
            Write-Warning $RunState.FailureReason
            return $false
        }
        Write-StatusLine -Marker 'i' -Message "Union tip verified at $($unionTip.Substring(0,8))..." -Color Green

        # Step 11: Staleness re-check (concurrency guard).
        $curNow = Get-RefHash $repository "refs/heads/$current"
        $xNow = Get-RefHash $repository "refs/heads/$X"
        if ($curNow -ne $curOld -or $xNow -ne $xOld) {
            $RunState.FailureReason = "'$current' or '$X' changed during the merge; refusing to publish a stale result."
            Write-Warning $RunState.FailureReason
            return $false
        }

        # Step 12: Apply — fast-forward both real refs to unionTip.
        # Order: X first, then current. If X's FF fails, current is still untouched (all-or-nothing).
        # current is the caller's checked-out branch in the clean repo; its FF is near-certain to succeed.
        Write-Stage -Title 'PUBLISH' -Subtitle "Fast-forward '$X' then '$current' to the union" -StageIcon 'PUSH'

        # Fast-forward X (use worktree ff-only if checked out, else CAS update-ref).
        $xApplyOk = $false
        if ($null -ne $xWt) {
            # Re-check X's cleanliness immediately before touching it (mirrors the re-check on current).
            if (-not (Test-CleanWorktree $xWt)) {
                $RunState.FailureReason = "The '$X' worktree changed after preflight."
                Write-Warning $RunState.FailureReason
                return $false
            }
            $xApply = Invoke-GitCommand $xWt.Path @('merge', '--ff-only', $unionTip) -MergeError
            $xApplyOk = ($xApply.ExitCode -eq 0)
            if (-not $xApplyOk) {
                Write-GitFailure "Cannot fast-forward '$X' to union" $xApply
                $RunState.FailureReason = "Cannot fast-forward '$X' to the union."
                Write-Warning $RunState.FailureReason
                return $false
            }
        }
        else {
            $xApplyOk = Move-BranchRefSafely -Repository $repository -Branch $X -ExpectedOldHash $xOld -NewHash $unionTip -Message "gitmerge: converge with '$current'"
            if (-not $xApplyOk) {
                $RunState.FailureReason = "Cannot advance '$X' to the union (CAS failed — concurrent change?)."
                Write-Warning $RunState.FailureReason
                return $false
            }
        }
        Write-StatusLine -Marker 'i' -Message "Fast-forwarded '$X' to the union." -Color Green
        $RunState.SynchronizedBranches.Add($X)

        # Fast-forward current (it is checked out in curWt or we use update-ref CAS).
        $curApplyOk = $false
        if ($null -ne $curWt) {
            # Re-check cleanliness before touching it.
            if (-not (Test-CleanWorktree $curWt)) {
                $RunState.FailureReason = "The '$current' worktree changed after preflight."
                Write-Warning $RunState.FailureReason
                return $false
            }
            $curApply = Invoke-GitCommand $curWt.Path @('merge', '--ff-only', $unionTip) -MergeError
            $curApplyOk = ($curApply.ExitCode -eq 0)
            if (-not $curApplyOk) {
                Write-GitFailure "Cannot fast-forward '$current' to union" $curApply
                $RunState.FailureReason = "Cannot fast-forward '$current' to the union."
                Write-Warning $RunState.FailureReason
                return $false
            }
        }
        else {
            $curApplyOk = Move-BranchRefSafely -Repository $repository -Branch $current -ExpectedOldHash $curOld -NewHash $unionTip -Message "gitmerge: converge with '$X'"
            if (-not $curApplyOk) {
                $RunState.FailureReason = "Cannot advance '$current' to the union (CAS failed — concurrent change?)."
                Write-Warning $RunState.FailureReason
                return $false
            }
        }
        Write-StatusLine -Marker 'i' -Message "Fast-forwarded '$current' to the union." -Color Green
        $RunState.IntegratedBranches.Add($current)

        # Step 13: Record success.
        $RunState.Result = 'SUCCESS'
        $RunState.MainBranch = $current
        $RunState.MainPublished = 'NOT REQUIRED'
        Write-StatusLine -Marker 'i' -Message "Converged '$current' and '$X' to the union." -Color Green
        return $true
    }
    finally {
        # Step 14: Always clean up the throwaway.
        Write-Stage -Title 'CLEANUP' -Subtitle 'Remove temporary worktree and branch' -StageIcon 'CLEAN'
        $cleanupOk = Invoke-TemporaryCleanup -Repository $repository -WorktreePath $temporaryWorktree -TemporaryBranch $temporaryBranch
        $RunState.CleanupStatus = if ($cleanupOk) { 'CLEAN' } else { 'FAILED' }
        if ($cleanupOk) {
            Write-StatusLine -Marker 'i' -Message 'Temporary merge state removed.' -Color Green
        }
        else {
            Write-StatusLine -Marker 'x' -Message 'Temporary cleanup was incomplete.' -Color Red
            if ([string]::IsNullOrWhiteSpace($RunState.FailureReason)) {
                $RunState.FailureReason = 'Temporary cleanup was incomplete.'
            }
            $RunState.Result = 'FAILED'
        }
    }
}

function Invoke-StarMerge {
    # v7.1 star engine: current branch T is the hub; every other managed branch is a spoke.
    # PASS 1: classify each spoke (skip if worktree dirty or conflicts with originalT).
    # PASS 2a: build the hub union in a throwaway (skip spokes that conflict with accumulator).
    # PASS 2b: apply -- advance hub to union; reverse-merge originalT into each clean spoke.
    # Safety: all real-ref moves are FF (merge --ff-only) or Move-BranchRefSafely CAS or
    # commit-tree-derived CAS. Hub union built/validated in throwaway before any real ref moves.
    # Conflicts skip (merge --abort, no partial state). finally-cleanup always runs.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive, colorized engine output.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
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
        Write-Host '----------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host "  $Title" -ForegroundColor $Color
        if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
            Write-Host "  $Subtitle" -ForegroundColor DarkGray
        }
        Write-Host '----------------------------------------------------------' -ForegroundColor DarkGray
    }

    function Write-StatusLine {
        param([string]$Marker, [string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
        if ($null -ne $Visual) {
            & $Visual.WriteStatusLine -Marker $Marker -Message $Message -Color $Color
            return
        }
        Write-Host ("   {0,-3} {1}" -f $Marker, $Message) -ForegroundColor $Color
    }

    # Step 1: Resolve repository.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $RunState.FailureReason = 'Git is not installed or is not available on PATH.'
        Write-Warning $RunState.FailureReason
        return $false
    }
    $rootResult = Invoke-GitCommand '' @('rev-parse', '--show-toplevel') -SuppressError
    if ($rootResult.ExitCode -ne 0) {
        $RunState.FailureReason = 'Current directory is not inside a Git repository.'
        Write-Warning $RunState.FailureReason
        return $false
    }
    $repository = Get-FirstOutputLine $rootResult
    $RunState.Repository = $repository
    $RunState.SummaryEnabled = $true

    Write-Stage -Title 'PREFLIGHT' -Subtitle 'Resolve repository, hub branch, and spokes' -StageIcon 'SCAN'
    Write-StatusLine -Marker 'i' -Message "Git root: $repository" -Color Green

    # Must have at least one commit.
    $headResult = Invoke-GitCommand $repository @('rev-parse', '--verify', 'HEAD') -SuppressError
    if ($headResult.ExitCode -ne 0) {
        $RunState.FailureReason = 'Repository has no commits yet. Create an initial commit before running gitmerge.'
        Write-Warning $RunState.FailureReason
        return $false
    }

    # Hub T = current branch (detached HEAD aborts).
    $T = Get-CurrentBranch $repository
    if ([string]::IsNullOrWhiteSpace($T)) {
        $RunState.FailureReason = 'Current HEAD is detached; checkout a branch before running gitmerge all.'
        Write-Warning $RunState.FailureReason
        return $false
    }
    $RunState.MainBranch = $T
    Write-StatusLine -Marker 'i' -Message "Hub (current): $T" -Color Green

    # Enumerate managed branches: local branches minus temp branches.
    $allLocal = Get-LocalBranch $repository
    if ($null -eq $allLocal) {
        $RunState.FailureReason = 'Cannot enumerate local branches.'
        Write-Warning $RunState.FailureReason
        return $false
    }
    $managed = @($allLocal | Where-Object { $_ -notmatch '^gitmerge-tmp-' })
    $others = @($managed | Where-Object { $_ -ne $T })
    $RunState.LocalBranchCount = $managed.Count

    if ($others.Count -eq 0) {
        Write-StatusLine -Marker 'i' -Message "No other branches; nothing to merge." -Color DarkGray
        $RunState.Result = 'SUCCESS'
        $RunState.MainPublished = 'NOT REQUIRED'
        return $true
    }
    Write-StatusLine -Marker 'i' -Message "Spokes ($($others.Count)): $($others -join ', ')" -Color Green
    foreach ($b in $others) { [void]$RunState.TargetBranches.Add($b) }

    # Step 3: Get worktrees; preflight the HUB.
    $worktrees = Get-WorktreeRecord $repository
    if ($null -eq $worktrees) {
        $RunState.FailureReason = 'Git worktrees could not be enumerated.'
        Write-Warning $RunState.FailureReason
        return $false
    }
    $worktrees = @($worktrees)
    $RunState.WorktreeCount = $worktrees.Count
    $curWt = Find-BranchWorktree $worktrees $T

    # Hub dirty => abort entire run (hub failure is not skip-and-proceed).
    if ($null -ne $curWt -and -not (Test-CleanWorktree $curWt)) {
        $RunState.FailureReason = "No refs were changed because the '$T' hub worktree is not clean."
        Write-Warning $RunState.FailureReason
        return $false
    }
    Write-StatusLine -Marker 'i' -Message "Hub worktree clean." -Color Green

    # Step 4: Capture originalT tip (never changes during this run's logic).
    $originalT = Get-RefHash $repository "refs/heads/$T"
    if (-not $originalT) {
        $RunState.FailureReason = "Cannot resolve hub tip hash for '$T'."
        Write-Warning $RunState.FailureReason
        return $false
    }
    Write-StatusLine -Marker 'i' -Message "Hub original tip: $($originalT.Substring(0,8))..." -Color Green

    # Step 5: PASS 1 -- classify spokes (read-only, mutate nothing).
    Write-Stage -Title 'CLASSIFY SPOKES' -Subtitle 'Identify clean spokes vs. skip (dirty worktree / conflicts with hub)' -StageIcon 'SCAN'
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($B in $others) {
        $bWt = Find-BranchWorktree $worktrees $B
        if ($null -ne $bWt -and -not (Test-CleanWorktree $bWt)) {
            [void]$RunState.SkippedBranches.Add($B)
            Write-StatusLine -Marker '!' -Message "Skip '$B': worktree not clean." -Color Yellow
            Write-Warning "Skipping '$B': its worktree is not clean."
            continue
        }
        # Probe merge of originalT + B in-memory (no worktree, no ref change).
        $mtResult = Invoke-GitCommand $repository @('merge-tree', '--write-tree', $originalT, "refs/heads/$B") -MergeError
        if ($mtResult.ExitCode -ne 0) {
            [void]$RunState.SkippedBranches.Add($B)
            Write-StatusLine -Marker '!' -Message "Skip '$B': conflicts with hub baseline." -Color Yellow
            Write-Warning "Skipping '$B': conflicts with the hub baseline (merge-tree exit $($mtResult.ExitCode))."
            continue
        }
        $spokeMergeTree = Get-FirstOutputLine $mtResult
        $bOld = Get-RefHash $repository "refs/heads/$B"
        [void]$candidates.Add([pscustomobject]@{ Branch = $B; Worktree = $bWt; Old = $bOld; Tree = $spokeMergeTree })
        Write-StatusLine -Marker 'i' -Message "Candidate spoke: '$B' (tip $($bOld.Substring(0,8))...)" -Color Green
    }

    # Declare throwaway vars before the try block so the finally can always reference them.
    $temporaryBranch = $null
    $temporaryWorktree = $null

    if ($candidates.Count -eq 0) {
        Write-StatusLine -Marker 'i' -Message 'All spokes skipped; nothing to merge into hub.' -Color Yellow
        $RunState.Result = 'SUCCESS'
        $RunState.MainPublished = 'NOT REQUIRED'
        $RunState.CleanupStatus = 'CLEAN'
        return $true
    }

    # Step 6: PASS 2a -- build hub accumulator in a throwaway.
    $suffix = $null
    do {
        $suffix = [guid]::NewGuid().ToString('N')
        $temporaryBranch = "gitmerge-tmp-$suffix"
    } while (Test-LocalBranch $repository $temporaryBranch)
    $temporaryWorktree = Join-Path ([System.IO.Path]::GetTempPath()) $temporaryBranch

    try {
        Write-Stage -Title 'BUILD HUB UNION' -Subtitle "Merge spokes into throwaway at hub '$T' (real refs untouched)" -StageIcon 'MERGE'
        Write-StatusLine -Marker '->' -Message "Creating temporary branch '$temporaryBranch' at '$T'." -Color Cyan
        $create = Invoke-GitCommand $repository @(
            'worktree', 'add', '-b', $temporaryBranch, $temporaryWorktree, "refs/heads/$T"
        ) -MergeError
        if ($create.ExitCode -ne 0) {
            Write-GitFailure 'Cannot create the temporary merge worktree' $create
            $RunState.FailureReason = 'Cannot create the temporary merge worktree.'
            return $false
        }
        Write-StatusLine -Marker 'i' -Message "Temporary worktree: $temporaryWorktree" -Color Green

        $hubMergedB = [System.Collections.Generic.List[object]]::new()
        foreach ($c in $candidates) {
            $merge = Invoke-GitCommand $temporaryWorktree @(
                'merge', '--no-edit', '-m', "Merge '$($c.Branch)' into '$T'", "refs/heads/$($c.Branch)"
            ) -MergeError
            if ($merge.ExitCode -ne 0) {
                # Sibling/accumulator conflict -- skip ENTIRELY (no reverse merge either).
                $mergeInProgress = (Invoke-GitCommand $temporaryWorktree @('rev-parse', '--verify', '-q', 'MERGE_HEAD') -SuppressError).ExitCode -eq 0
                if ($mergeInProgress) {
                    [void](Invoke-GitCommand $temporaryWorktree @('merge', '--abort') -MergeError)
                }
                [void]$RunState.SkippedBranches.Add($c.Branch)
                Write-StatusLine -Marker '!' -Message "Skip '$($c.Branch)': conflicts with another branch already merged into the hub." -Color Yellow
                Write-Warning "Skipping '$($c.Branch)': conflicts with another branch already merged into the hub."
                continue
            }
            [void]$hubMergedB.Add($c)
            Write-StatusLine -Marker 'i' -Message "Merged '$($c.Branch)' into throwaway hub." -Color Green
        }

        # Hub union tip.
        $hubUnion = Get-RefHash $repository "refs/heads/$temporaryBranch"
        if (-not $hubUnion) {
            $RunState.FailureReason = 'Cannot resolve hub union tip after throwaway merges.'
            Write-Warning $RunState.FailureReason
            return $false
        }
        # Sanity: union descends originalT.
        if (-not (Test-Ancestor -Repository $repository -Ancestor $originalT -Descendant "refs/heads/$temporaryBranch")) {
            $RunState.FailureReason = "Hub union does not descend hub original tip -- internal sanity check failed."
            Write-Warning $RunState.FailureReason
            return $false
        }
        Write-StatusLine -Marker 'i' -Message "Hub union tip: $($hubUnion.Substring(0,8))..." -Color Green

        # Step 7: PASS 2b -- staleness re-check then apply real refs.
        Write-Stage -Title 'APPLY' -Subtitle 'Advance hub to union; reverse-merge originalT into each spoke' -StageIcon 'PUSH'

        # Staleness re-check (concurrency guard).
        $tNow = Get-RefHash $repository "refs/heads/$T"
        if ($tNow -ne $originalT) {
            $RunState.FailureReason = "Hub '$T' changed during the merge; refusing to publish a stale result."
            Write-Warning $RunState.FailureReason
            return $false
        }

        # Drop any candidate whose ref moved concurrently.
        $applyList = [System.Collections.Generic.List[object]]::new()
        foreach ($c in $hubMergedB) {
            $bNow = Get-RefHash $repository "refs/heads/$($c.Branch)"
            if ($bNow -ne $c.Old) {
                Write-StatusLine -Marker '!' -Message "Drop '$($c.Branch)' from apply: concurrent change detected." -Color Yellow
                Write-Warning "Skipping '$($c.Branch)': it changed concurrently; not applying reverse merge."
                [void]$RunState.SkippedBranches.Add($c.Branch)
            }
            else {
                [void]$applyList.Add($c)
            }
        }

        # 7a: Advance hub T to hubUnion.
        if ($hubUnion -eq $originalT) {
            Write-StatusLine -Marker 'i' -Message "Hub already current; nothing absorbed." -Color DarkGray
        }
        else {
            $hubAdvanceOk = $false
            if ($null -ne $curWt) {
                # Re-check cleanliness immediately before touching it.
                if (-not (Test-CleanWorktree $curWt)) {
                    $RunState.FailureReason = "Hub '$T' worktree changed after preflight."
                    Write-Warning $RunState.FailureReason
                    return $false
                }
                $hubApply = Invoke-GitCommand $curWt.Path @('merge', '--ff-only', $hubUnion) -MergeError
                $hubAdvanceOk = ($hubApply.ExitCode -eq 0)
                if (-not $hubAdvanceOk) {
                    Write-GitFailure "Cannot fast-forward hub '$T' to union" $hubApply
                    $RunState.FailureReason = "Cannot fast-forward hub '$T' to the union."
                    Write-Warning $RunState.FailureReason
                    return $false
                }
            }
            else {
                $hubAdvanceOk = Move-BranchRefSafely -Repository $repository -Branch $T -ExpectedOldHash $originalT -NewHash $hubUnion -Message "gitmerge: star -- advance hub '$T' to union"
                if (-not $hubAdvanceOk) {
                    $RunState.FailureReason = "Cannot advance hub '$T' to union (CAS failed -- concurrent change?)."
                    Write-Warning $RunState.FailureReason
                    return $false
                }
            }
            Write-StatusLine -Marker 'i' -Message "Hub '$T' advanced to union." -Color Green
            [void]$RunState.IntegratedBranches.Add($T)
        }

        # 7b: Reverse-merge originalT into each spoke (skip-and-proceed per branch).
        foreach ($c in $applyList) {
            $B = $c.Branch
            $bOld = $c.Old

            # Case 1: B already contains originalT (originalT is ancestor of B).
            if (Test-Ancestor -Repository $repository -Ancestor $originalT -Descendant "refs/heads/$B") {
                Write-StatusLine -Marker 'i' -Message "Spoke '$B' already contains hub original; no reverse merge needed." -Color DarkGray
                [void]$RunState.SynchronizedBranches.Add($B)
                continue
            }

            # Case 2: B is ancestor of originalT => fast-forward B to originalT.
            if (Test-Ancestor -Repository $repository -Ancestor "refs/heads/$B" -Descendant $originalT) {
                $ffOk = $false
                if ($null -ne $c.Worktree) {
                    if (-not (Test-CleanWorktree $c.Worktree)) {
                        Write-StatusLine -Marker '!' -Message "Skip reverse-merge for '$B': worktree not clean (post-pass1 change)." -Color Yellow
                        Write-Warning "Skipping reverse merge for '$B': worktree changed after Pass 1."
                        [void]$RunState.SkippedBranches.Add($B)
                        continue
                    }
                    $ffApply = Invoke-GitCommand $c.Worktree.Path @('merge', '--ff-only', $originalT) -MergeError
                    $ffOk = ($ffApply.ExitCode -eq 0)
                }
                else {
                    $ffOk = Move-BranchRefSafely -Repository $repository -Branch $B -ExpectedOldHash $bOld -NewHash $originalT -Message "gitmerge: star -- fast-forward spoke '$B' to hub original"
                }
                if (-not $ffOk) {
                    Write-StatusLine -Marker '!' -Message "Skip '$B': cannot fast-forward to hub original." -Color Yellow
                    Write-Warning "Skipping '$B': fast-forward to hub original failed."
                    [void]$RunState.SkippedBranches.Add($B)
                    continue
                }
                Write-StatusLine -Marker 'i' -Message "Spoke '$B' fast-forwarded to hub original." -Color Green
                [void]$RunState.SynchronizedBranches.Add($B)
                continue
            }

            # Case 3: Diverged -- build the merge commit worktree-free (using Pass-1 validated tree).
            # The tree was validated by merge-tree(originalT, B) in Pass 1 => clean.
            # commit-tree: parents = bOld (spoke's old tip), originalT. The result descends bOld => CAS ok.
            if ($null -ne $c.Worktree) {
                # Spoke is checked out: do a real merge in its worktree.
                if (-not (Test-CleanWorktree $c.Worktree)) {
                    Write-StatusLine -Marker '!' -Message "Skip reverse-merge for '$B': worktree not clean (post-pass1 change)." -Color Yellow
                    Write-Warning "Skipping reverse merge for '$B': worktree changed after Pass 1."
                    [void]$RunState.SkippedBranches.Add($B)
                    continue
                }
                $wMerge = Invoke-GitCommand $c.Worktree.Path @('merge', '--no-edit', $originalT) -MergeError
                if ($wMerge.ExitCode -ne 0) {
                    # Surprise conflict (should not happen after clean merge-tree, but guard anyway).
                    $mergeInProgress = (Invoke-GitCommand $c.Worktree.Path @('rev-parse', '--verify', '-q', 'MERGE_HEAD') -SuppressError).ExitCode -eq 0
                    if ($mergeInProgress) {
                        [void](Invoke-GitCommand $c.Worktree.Path @('merge', '--abort') -MergeError)
                    }
                    Write-StatusLine -Marker '!' -Message "Skip '$B': surprise conflict during worktree reverse merge." -Color Yellow
                    Write-Warning "Skipping '$B': surprise conflict during reverse merge in its worktree."
                    [void]$RunState.SkippedBranches.Add($B)
                    continue
                }
                Write-StatusLine -Marker 'i' -Message "Spoke '$B' reverse-merged (worktree) with hub original." -Color Green
                [void]$RunState.SynchronizedBranches.Add($B)
            }
            else {
                # Spoke is NOT checked out: worktree-free commit-tree path (mirror gitsync.ps1:435-446).
                $commitMsg = "Merge '$T' (original) into '$B'"
                $commitResult = Invoke-GitCommand $repository @(
                    'commit-tree', $c.Tree, '-p', $bOld, '-p', $originalT, '-m', $commitMsg
                ) -MergeError
                if ($commitResult.ExitCode -ne 0) {
                    Write-GitFailure "Cannot create reverse-merge commit for '$B'" $commitResult
                    Write-StatusLine -Marker '!' -Message "Skip '$B': commit-tree for reverse merge failed." -Color Yellow
                    [void]$RunState.SkippedBranches.Add($B)
                    continue
                }
                $mergeCommit = Get-FirstOutputLine $commitResult
                $casOk = Move-BranchRefSafely -Repository $repository -Branch $B -ExpectedOldHash $bOld -NewHash $mergeCommit -Message "gitmerge: star -- reverse-merge hub original into spoke '$B'"
                if (-not $casOk) {
                    Write-StatusLine -Marker '!' -Message "Skip '$B': CAS failed for reverse merge (concurrent change?)." -Color Yellow
                    Write-Warning "Skipping '$B': CAS for reverse merge failed (concurrent change?)."
                    [void]$RunState.SkippedBranches.Add($B)
                    continue
                }
                Write-StatusLine -Marker 'i' -Message "Spoke '$B' reverse-merged (worktree-free) with hub original." -Color Green
                [void]$RunState.SynchronizedBranches.Add($B)
            }
        }

        # Step 8: Record success.
        $RunState.Result = 'SUCCESS'
        $RunState.MainPublished = 'NOT REQUIRED'
        Write-StatusLine -Marker 'i' -Message "Star merge complete. Hub='$T'; synchronized $($RunState.SynchronizedBranches.Count) spoke(s); skipped $($RunState.SkippedBranches.Count)." -Color Green
        return $true
    }
    finally {
        Write-Stage -Title 'CLEANUP' -Subtitle 'Remove temporary worktree and branch' -StageIcon 'CLEAN'
        $cleanupOk = Invoke-TemporaryCleanup -Repository $repository -WorktreePath $temporaryWorktree -TemporaryBranch $temporaryBranch
        $RunState.CleanupStatus = if ($cleanupOk) { 'CLEAN' } else { 'FAILED' }
        if ($cleanupOk) {
            Write-StatusLine -Marker 'i' -Message 'Temporary merge state removed.' -Color Green
        }
        else {
            Write-StatusLine -Marker 'x' -Message 'Temporary cleanup was incomplete.' -Color Red
            if ([string]::IsNullOrWhiteSpace($RunState.FailureReason)) {
                $RunState.FailureReason = 'Temporary cleanup was incomplete.'
            }
            $RunState.Result = 'FAILED'
        }
    }
}

Export-ModuleMember -Function @(
    'Get-WorktreeInProgressOperation',
    'Get-RemoteBranchSyncState',
    'Get-RemoteMergeTree',
    'Move-BranchRefSafely',
    'Test-CleanWorktree',
    'Test-TemporaryWorktreeForCleanup',
    'Invoke-TemporaryCleanup',
    'Sync-MainFromOrigin',
    'Invoke-BranchFastForward',
    'Invoke-GitMergeConsolidation',
    'Invoke-TwoBranchMerge',
    'Invoke-StarMerge'
)
