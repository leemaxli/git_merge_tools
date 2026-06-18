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
    } finally { Remove-GitSandbox $ctx.Sandbox }
}

Test-Case 'gitsync Stage 4: a not-checked-out diverged branch with CONFLICTS still prompts; nothing changed' {
    $ctx = New-NotCheckedOutDivergedSandbox -Conflict
    try {
        $out = Invoke-ProductCommandText -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'all' -Sandbox $ctx.Sandbox
        Assert-Match 'ACTION NEEDED' $out -Message 'a conflicting divergence must never be auto-merged'
        Assert-Equal $ctx.LocalTip (Get-SandboxRef -Sandbox $ctx.Sandbox -Ref 'refs/heads/feature/x') -Message 'feature/x must be unchanged on a conflicting divergence'
    } finally { Remove-GitSandbox $ctx.Sandbox }
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
