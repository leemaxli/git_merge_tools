$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # tests/meta -> repo root

# HARD CONSTRAINT (remote side): gitsync's remote writes are per-branch single-ref pushes (v7.3).
# Each push carries exactly one refspec; no multi-ref push means no --atomic is needed (and it
# would be wrong to require it on a single-ref push). The safety guarantee is now: each branch is
# pushed individually, and a rejection skips that branch (skip-on-reject, never forced).
# This meta-test pins the per-branch reality: every push in gitsync is a single-ref ordinary push
# (no --atomic, no --force, no + prefix); gitmerge/gitstatus must never push at all.
Test-Case 'gitsync uses per-branch single-ref push; gitmerge/gitstatus never push' {
    # Match the lowercase git argument 'push' case-SENSITIVELY (-cmatch) so the uppercase 'PUSH'
    # stage-icon string is not mistaken for a git push command.
    $sawPush = $false
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath (Join-Path $repoRoot 'gitsync.ps1'))) {
        $lineNo++
        if ($line -cmatch "'push'") {
            # Every push must be a single-ref push (exactly one refspec of the form refs/heads/B:refs/heads/B).
            # Multi-ref pushes are forbidden (they would require --atomic; per-branch design avoids them).
            Assert-False ([bool]($line -cmatch '--atomic')) "gitsync must not use --atomic (per-branch single-ref push design) (gitsync.ps1:$lineNo): $line"
            # Pushes must never be forced.
            Assert-False ([bool]($line -cmatch '--force')) "gitsync push must never carry --force (gitsync.ps1:$lineNo): $line"
            Assert-False ([bool]($line -cmatch 'force-with-lease')) "gitsync push must never carry --force-with-lease (gitsync.ps1:$lineNo): $line"
            Assert-False ([bool]($line -match '\+refs/')) "gitsync push refspec must never use + (force prefix) (gitsync.ps1:$lineNo): $line"
            $sawPush = $true
        }
    }
    Assert-True $sawPush 'gitsync must contain its per-branch push (its only remote write)'

    foreach ($script in 'gitmerge.ps1', 'gitstatus.ps1') {
        $text = Get-Content -LiteralPath (Join-Path $repoRoot $script) -Raw
        Assert-False ([bool]($text -cmatch "'push'")) -Message "$script must never push (gitmerge is local consolidation; gitstatus is read-only)"
    }

    # The engine modules carry no push at all -- pushing lives only in gitsync.
    foreach ($module in 'GitMergeTools.Core.psm1', 'GitMergeTools.Merge.psm1') {
        $text = Get-Content -LiteralPath (Join-Path (Join-Path $repoRoot 'Modules') $module) -Raw
        Assert-False ([bool]($text -cmatch "'push'")) -Message "$module must not push (the engine never touches the remote write path)"
    }
}
