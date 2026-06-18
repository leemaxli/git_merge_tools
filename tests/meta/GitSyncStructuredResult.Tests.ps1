$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # tests/meta -> repo root

# gitsync used to recompute its push set independently of the merge engine (a duplicated #10 sub-branch
# skip), risking divergence: pushing -- and reporting as "synced" -- a branch the engine actually skipped.
# The engine already reports its real synchronized set, so gitsync must push exactly that (single source
# of truth). This is behavior-equivalent today (both applied the same #10 skip), so the behavioral guard
# is the existing gitsync suite (SyncSkipPush / GitSync / Utf8BranchCapture); these meta-scans pin the
# structural change so it can't silently regress, and confirm the now-dead engine param is gone.
Test-Case 'gitsync derives its push set from the engine''s synchronized result (single source of truth for #10)' {
    $text = Get-Content -LiteralPath (Join-Path $repoRoot 'gitsync.ps1') -Raw
    Assert-Match '\$mergeState\.SynchronizedBranches' $text -Message 'gitsync must push exactly what the engine reports as synchronized'
}

Test-Case 'the merge engine no longer carries the dead -RemoteAlreadyFetched parameter' {
    $merge = Get-Content -LiteralPath (Join-Path (Join-Path $repoRoot 'Modules') 'GitMergeTools.Merge.psm1') -Raw
    Assert-False ([bool]($merge -match 'RemoteAlreadyFetched')) -Message 'the unused -RemoteAlreadyFetched param must be removed from the engine'
    $gitsync = Get-Content -LiteralPath (Join-Path $repoRoot 'gitsync.ps1') -Raw
    Assert-False ([bool]($gitsync -match 'RemoteAlreadyFetched')) -Message 'gitsync must not reference the removed param'
}
