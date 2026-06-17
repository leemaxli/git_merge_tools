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

Export-ModuleMember -Function @(
    'Test-CleanWorktree',
    'Test-TemporaryWorktreeForCleanup',
    'Invoke-TemporaryCleanup',
    'Sync-MainFromOrigin',
    'Invoke-BranchFastForward'
)
