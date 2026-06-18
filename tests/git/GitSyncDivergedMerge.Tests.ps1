. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v6.x Stage 4: a DIVERGED branch (origin and local both moved) is auto-merged WHEN the merge is clean
# (no conflict). Validation is in-memory via `git merge-tree --write-tree` (no worktree, no ref change);
# for a not-checked-out branch the merge commit is created worktree-free via `commit-tree` and the ref is
# advanced with a compare-and-swap `update-ref`. A conflicting merge is never auto-resolved -- it prompts.

function New-NotCheckedOutDivergedSandbox {
    # feature/x (NOT checked out) diverged from origin. $SameFile controls clean (different files) vs
    # conflicting (same file) divergence.
    param([switch]$Conflict)
    $sb = New-GitSandbox
    $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
    New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $c1
    Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
    $originFile = if ($Conflict) { 'shared.txt' } else { 'b.txt' }
    $cOrigin = New-SandboxCommit -Sandbox $sb -FileName $originFile -Content "origin side`n" -Message 'origin work'
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'feature/x') | Out-Null         # origin/feature/x = cOrigin
    Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null
    $localFile = if ($Conflict) { 'shared.txt' } else { 'a.txt' }
    $cLocal = New-SandboxCommit -Sandbox $sb -FileName $localFile -Content "local side`n" -Message 'local work'
    Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null                      # feature/x NOT checked out
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin; Base = $c1; OriginTip = $cOrigin; LocalTip = $cLocal }
}

Test-Case 'gitsync Stage 4: auto-merges a not-checked-out diverged branch when the merge is clean' {
    $ctx = New-NotCheckedOutDivergedSandbox
    try {
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-True $ok 'a clean divergent merge should auto-merge and complete'
        $anc1 = Invoke-SandboxGit $ctx.Sandbox.Repo @('merge-base', '--is-ancestor', $ctx.OriginTip, 'refs/heads/feature/x')
        Assert-Equal 0 $anc1.ExitCode -Message "origin's commit must be an ancestor of merged feature/x"
        $anc2 = Invoke-SandboxGit $ctx.Sandbox.Repo @('merge-base', '--is-ancestor', $ctx.LocalTip, 'refs/heads/feature/x')
        Assert-Equal 0 $anc2.ExitCode -Message "local's commit must be an ancestor of merged feature/x"
        # CONTENT binding: the worktree-free merge builds the commit from merge-tree's tree via commit-tree;
        # ancestry alone would pass even if a side's content were dropped. Assert BOTH sides' files survive.
        Assert-Equal 0 (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/feature/x:a.txt')).ExitCode -Message "merged tree must contain local's a.txt (not just be a descendant)"
        Assert-Equal 0 (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/feature/x:b.txt')).ExitCode -Message "merged tree must contain origin's b.txt (not just be a descendant)"
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitsync all SKIPS a not-checked-out diverged branch with conflicts and proceeds; that branch unchanged' {
    # skip-and-proceed (v6.7.0): a conflicting non-main target is never auto-merged, but with all/cross-all
    # it is SKIPPED (not a whole-run abort) so the rest still sync.
    $ctx = New-NotCheckedOutDivergedSandbox -Conflict
    try {
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-Match 'Skipping' $out -Message 'the conflicting branch must be skipped (not abort the whole run)'
        Assert-False ([bool]($out -match 'ACTION NEEDED')) 'all-mode must skip-and-proceed, not stop with ACTION NEEDED for a non-main conflict'
        Assert-Equal $ctx.LocalTip (Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/feature/x') -Message 'the conflicting branch must be untouched (skipped)'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitsync all skips a conflicting non-main branch but still syncs a safe sibling' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $origin = Join-Path $sb.Root 'origin.git'
        Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
        # feature/safe: origin ahead (FF), not checked out -> should auto-pull + sync.
        New-SandboxBranch -Sandbox $sb -Name 'feature/safe' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/safe') | Out-Null
        $safeTip = New-SandboxCommit -Sandbox $sb -FileName 'safe.txt' -Content "safe`n" -Message 'safe work'
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'feature/safe') | Out-Null
        Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null
        # feature/bad: diverged with conflict, not checked out -> should be skipped.
        New-SandboxBranch -Sandbox $sb -Name 'feature/bad' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/bad') | Out-Null
        $badOrigin = New-SandboxCommit -Sandbox $sb -FileName 'shared.txt' -Content "origin side`n" -Message 'bad origin'
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'feature/bad') | Out-Null
        Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null
        $badLocal = New-SandboxCommit -Sandbox $sb -FileName 'shared.txt' -Content "local side`n" -Message 'bad local'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $sb
        Assert-True $ok 'gitsync all should skip the conflicting branch and still complete'
        $anc = Invoke-SandboxGit $sb.Repo @('merge-base', '--is-ancestor', $safeTip, 'refs/heads/feature/safe')
        Assert-Equal 0 $anc.ExitCode -Message 'the safe sibling must be pulled + synced'
        Assert-Equal $badLocal (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/bad') -Message 'the conflicting branch must be untouched (skipped)'
        $ls = Invoke-SandboxGit $sb.Repo @('ls-remote', $origin, 'refs/heads/feature/bad')
        Assert-Match ([regex]::Escape($badOrigin)) ((@($ls.Output) -join ' ')) -Message 'origin/feature/bad must be unchanged (not force-pushed)'
    } finally { Remove-GitSandbox $sb }
}

function New-CheckedOutDivergedSandbox {
    # main (CHECKED OUT) diverged from origin. -Conflict = same-file (conflicting); -Dirty = leave an
    # uncommitted tracked change in the worktree.
    param([switch]$Conflict, [switch]$Dirty)
    $sb = New-GitSandbox
    $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    $origin = Join-Path $sb.Root 'origin.git'
    Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
    $originFile = if ($Conflict) { 'shared.txt' } else { 'b.txt' }
    $cOrigin = New-SandboxCommit -Sandbox $sb -FileName $originFile -Content "origin side`n" -Message 'origin work'
    Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null              # origin/main = cOrigin
    Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null
    $localFile = if ($Conflict) { 'shared.txt' } else { 'a.txt' }
    $cLocal = New-SandboxCommit -Sandbox $sb -FileName $localFile -Content "local side`n" -Message 'local work'  # main = cLocal, checked out
    if ($Dirty) { Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty edit`n" -Encoding utf8 }
    return [pscustomobject]@{ Sandbox = $sb; Origin = $origin; Base = $c1; OriginTip = $cOrigin; LocalTip = $cLocal }
}

Test-Case 'gitsync Stage 4b: auto-merges a checked-out CLEAN diverged branch via a worktree merge' {
    $ctx = New-CheckedOutDivergedSandbox
    try {
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-True $ok 'a clean divergent merge on the checked-out branch should auto-merge and complete'
        $anc1 = Invoke-SandboxGit $ctx.Sandbox.Repo @('merge-base', '--is-ancestor', $ctx.OriginTip, 'refs/heads/main')
        Assert-Equal 0 $anc1.ExitCode -Message "origin's commit must be an ancestor of merged main"
        $anc2 = Invoke-SandboxGit $ctx.Sandbox.Repo @('merge-base', '--is-ancestor', $ctx.LocalTip, 'refs/heads/main')
        Assert-Equal 0 $anc2.ExitCode -Message "local's commit must be an ancestor of merged main"
        # CONTENT binding (worktree merge): both sides' files must actually be present in the merged tree.
        Assert-Equal 0 (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/main:a.txt')).ExitCode -Message "merged main must contain local's a.txt"
        Assert-Equal 0 (Invoke-SandboxGit $ctx.Sandbox.Repo @('cat-file', '-e', 'refs/heads/main:b.txt')).ExitCode -Message "merged main must contain origin's b.txt"
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitsync Stage 4b: a checked-out diverged branch with a DIRTY worktree still prompts; nothing changed' {
    $ctx = New-CheckedOutDivergedSandbox -Dirty
    try {
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-Match 'ACTION NEEDED' $out -Message 'a dirty worktree must never be auto-merged'
        Assert-Equal $ctx.LocalTip (Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/main') -Message 'local main must be unchanged when its worktree is dirty'
    } finally { Remove-GitSandbox $ctx.Sandbox }
}
