. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.4-B: Engine message recording tests.
# Verifies that Add-RunMessage calls in Invoke-TwoBranchMerge and Invoke-MeshMerge
# produce messages that surface in the basic summary's Notices & warnings section.
# Tests use Invoke-ProductCommandText (basic tier) to capture all output.

# ---------------------------------------------------------------------------
# TwoBranch: target == current -> NOTICE in summary
# ---------------------------------------------------------------------------

Test-Case 'gitmerge naming current branch: NOTICE reminder appears in summary' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        # gitmerge main (current == X) -> should succeed with a NOTICE
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'main' -Sandbox $sb
        Assert-Match 'NOTICE' $out -Message 'summary must contain NOTICE when target is the current branch'
        Assert-Match 'main' $out -Message 'the branch name must appear in the notice'
        Assert-Match 'nothing to merge' $out -Message 'the notice must mention nothing to merge'
    } finally { Remove-GitSandbox $sb }
}

# ---------------------------------------------------------------------------
# TwoBranch: conflict -> WARNING in summary
# ---------------------------------------------------------------------------

Test-Case 'gitmerge {branch} conflict: WARNING names the conflict branch in summary' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $null = New-SandboxBranch -Sandbox $sb -Name 'feature-x'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature-x') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "feature side`n" -Message 'feature edit'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "main side`n" -Message 'main edit'
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'feature-x' -Sandbox $sb
        Assert-Match 'WARNING' $out -Message 'summary must contain WARNING for a merge conflict'
        Assert-Match 'feature-x' $out -Message 'the conflict branch name must appear in the warning'
        Assert-Match '[Cc]onflict' $out -Message 'the word conflict must appear in the warning'
    } finally { Remove-GitSandbox $sb }
}

# ---------------------------------------------------------------------------
# Mesh (cross-all): conflict -> WARNING in summary
# ---------------------------------------------------------------------------

Test-Case 'gitmerge cross-all conflict: WARNING names the conflict branch in summary' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $null = New-SandboxBranch -Sandbox $sb -Name 'branch-x'
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-x') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "x side`n" -Message 'x edit'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "main side`n" -Message 'main edit'
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        Assert-Match 'WARNING' $out -Message 'cross-all summary must contain WARNING for a mesh conflict'
        Assert-Match 'branch-x' $out -Message 'the conflict branch name must appear in the warning'
        Assert-Match '[Cc]onflict' $out -Message 'the word conflict must appear in the warning'
    } finally { Remove-GitSandbox $sb }
}

# ---------------------------------------------------------------------------
# Mesh (cross-all): locked/untouchable worktree -> NOTICE in summary (v7.5.0: skip is for untouchable only)
# ---------------------------------------------------------------------------

Test-Case 'gitmerge cross-all dirty worktree skip: NOTICE names the skipped branch in summary' {
    # v7.5.0: mere uncommitted changes no longer cause a skip in PASS 0. OVERLAPPING dirty changes
    # that would be overwritten by the FF produce a WARNING (not a NOTICE) at apply time.
    # This test verifies that when an OVERLAPPING uncommitted change causes branch-a to be skipped
    # at apply, the branch name appears in the output with a WARNING (which is also a form of notice).
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        # branch-a starts at base; adds a.txt
        $null = New-SandboxBranch -Sandbox $sb -Name 'branch-a'
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-a') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "a`n" -Message 'a work'
        # branch-b starts at base; adds b.txt
        $null = New-SandboxBranch -Sandbox $sb -Name 'branch-b'
        Invoke-SandboxGit $sb.Repo @('switch', 'branch-b') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'b.txt' -Content "b`n" -Message 'b work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
        # Add a linked worktree for branch-a; dirty it on b.txt (OVERLAPPING: the union adds b.txt
        # to branch-a, so the FF would overwrite this uncommitted change -> branch-a is skipped + WARNING).
        $wtA = Join-Path $sb.Root 'wt-a'
        Invoke-SandboxGit $sb.Repo @('worktree', 'add', $wtA, 'branch-a') | Out-Null
        Set-Content -LiteralPath (Join-Path $wtA 'b.txt') -Value "dirty-b`n" -Encoding utf8
        $out = Invoke-ProductCommandText -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'cross-all' -Sandbox $sb
        # With overlapping dirty change, branch-a is skipped at apply with a WARNING message
        Assert-True ($out -match 'branch-a') 'the skipped branch name must appear in the output'
        Assert-True ($out -match 'commit or stash') 'the output must advise commit or stash'
        Invoke-SandboxGit $sb.Repo @('worktree', 'remove', '--force', $wtA) | Out-Null
    } finally { Remove-GitSandbox $sb }
}