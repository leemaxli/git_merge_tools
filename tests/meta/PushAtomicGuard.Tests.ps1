$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # tests/meta -> repo root

# HARD CONSTRAINT (remote side): gitsync's ONLY remote write is a single `git push --atomic`, so a
# multi-ref push lands all-or-nothing -- a partial push could clobber a collaborator's branch. That one
# token is the entire remote-side guarantee, so this meta-test pins it: every push in gitsync must be
# atomic, and gitmerge/gitstatus must never push at all. (The positive twin of PushForceGuard's --force ban.)
Test-Case 'gitsync push is --atomic; gitmerge/gitstatus never push' {
    # Match the lowercase git argument 'push' case-SENSITIVELY (-cmatch) so the uppercase 'PUSH' stage-icon
    # string is not mistaken for a git push.
    $sawAtomicPush = $false
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath (Join-Path $repoRoot 'gitsync.ps1'))) {
        $lineNo++
        if ($line -cmatch "'push'") {
            Assert-Match '--atomic' $line -Message "every gitsync push must be --atomic (gitsync.ps1:$lineNo): $line"
            $sawAtomicPush = $true
        }
    }
    Assert-True $sawAtomicPush 'gitsync must contain its atomic push (its only remote write)'

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
