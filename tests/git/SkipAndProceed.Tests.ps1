. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# skip-and-proceed (v7.1 star engine): with all, a SPOKE branch whose worktree is dirty is SKIPPED with
# a warning -- the rest still merge. The HUB (current branch) being dirty ABORTS the run. These tests
# exercise both cases under the v7.1 star semantics.

Test-Case 'gitmerge all (v7.1 star): dirty HUB (current branch) aborts; spokes untouched' {
    # v7.1: hub = current branch. Hub dirty => abort, nothing changes.
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'feature/clean' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/clean') | Out-Null
        $cClean = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "clean work`n" -Message 'clean work'
        New-SandboxBranch -Sandbox $sb -Name 'feature/dirty-hub' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/dirty-hub') | Out-Null   # HUB = feature/dirty-hub
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty`n" -Encoding utf8
        $hubBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/dirty-hub'
        $cleanBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/clean'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-False $ok 'gitmerge all must abort when the HUB (current) worktree is dirty'
        Assert-Equal $hubBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/dirty-hub') -Message 'dirty hub branch must be untouched'
        Assert-Equal $cleanBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/clean') -Message 'clean spoke must also be untouched (aborted)'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitmerge all still ABORTS when MAIN is checked out as HUB and its worktree is dirty' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $c1
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "ahead`n" -Message 'ahead'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null                          # current = main
        Set-Content -LiteralPath (Join-Path $sb.Repo 'f.txt') -Value "dirty edit`n" -Encoding utf8  # MAIN worktree dirty
        $mainBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main'

        $ok = Invoke-ProductCommand -Script 'gitmerge.ps1' -Func 'gitmerge' -Arg 'all' -Sandbox $sb
        Assert-False $ok 'gitmerge must abort when the current (hub) branch worktree is dirty'
        Assert-Equal $mainBefore (Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/main') -Message 'hub must be unchanged when its worktree is dirty'
    } finally { Remove-GitSandbox $sb }
}
