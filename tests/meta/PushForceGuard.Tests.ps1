$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # tests/meta -> repo root

# HARD CONSTRAINT guard: no code path may ever push with --force / --force-with-lease. This meta-test
# scans the git-invoking source so a future refactor can never silently reintroduce a force-push. The
# only --force permitted anywhere is `git worktree remove --force` (the tool's own temp-worktree teardown).
Test-Case 'no git push uses --force / --force-with-lease; the only --force is the temp-worktree removal' {
    $modulesRoot = Join-Path $repoRoot 'Modules'
    $files = @(
        ('gitmerge.ps1', 'gitsync.ps1', 'gitstatus.ps1' | ForEach-Object { Join-Path $repoRoot $_ })
        ('GitMergeTools.Core.psm1', 'GitMergeTools.Merge.psm1' | ForEach-Object { Join-Path $modulesRoot $_ })
    )

    foreach ($file in $files) {
        Assert-True (Test-Path -LiteralPath $file) -Message "source file must exist: $file"
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $file)) {
            $lineNo++
            Assert-False ([bool]($line -match 'force-with-lease')) "--force-with-lease is forbidden ($([IO.Path]::GetFileName($file)):$lineNo)"
            if ($line -match '(^|[^A-Za-z])--force([^A-Za-z]|$)') {
                Assert-False ([bool]($line -match '\bpush\b')) "push must never carry --force ($([IO.Path]::GetFileName($file)):$lineNo): $line"
                Assert-Match 'worktree' $line -Message "the only allowed --force is 'git worktree remove --force' ($([IO.Path]::GetFileName($file)):$lineNo): $line"
            }
        }
    }
}
