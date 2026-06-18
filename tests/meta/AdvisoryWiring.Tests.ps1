$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # tests/meta -> repo root

# Visual polish / consistency: all three entry commands must surface the upgrade advisory at end-of-run.
# It is silent unless a tier was pinned (GITMERGE_VISUAL_MODE) but not reached and notices aren't
# suppressed, so a user who pins a tier their environment can't render gets the same "how to reach it"
# guidance from every command, not just gitmerge. The call is guarded by Get-Command, so it is a no-op
# when the Common module isn't loaded.
Test-Case 'every entry command wires the upgrade advisory (gitmerge/gitsync/gitstatus)' {
    foreach ($script in 'gitmerge.ps1', 'gitsync.ps1', 'gitstatus.ps1') {
        $text = Get-Content -LiteralPath (Join-Path $repoRoot $script) -Raw
        Assert-Match 'Write-GitMergeToolsUpgradeAdvisory' $text -Message "$script must surface the upgrade advisory at end-of-run"
    }
}
