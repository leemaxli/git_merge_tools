. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.3: gitsync uses per-branch topology engines (2-branch / star / mesh). The old sub-branch guard
# in gitsync itself is removed; the 2-branch engine (Invoke-TwoBranchMerge) intentionally has NO
# sub-branch skip (a 2-branch converge of current+X is a pure fast-forward of X -- it loses no work
# from any descendant of X; descendants simply stay where they are with all their commits intact).
# The engine comment (Invoke-TwoBranchMerge Step 7 NOTE) explains the design decision.
# What gitsync DOES guarantee: it pushes exactly what the engine converged (IntegratedBranches +
# SynchronizedBranches), and feature/A-child (which was never part of this run) stays untouched.
Test-Case 'gitsync 2-branch: converges current+feature/A; feature/A-child is untouched (not pushed, not lost)' {
    $sb = New-GitSandbox
    try {
        $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $origin = Join-Path $sb.Root 'origin.git'
        Invoke-SandboxGit $sb.Repo @('init', '--bare', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('remote', 'add', 'origin', $origin) | Out-Null
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'main') | Out-Null
        # feature/A: ahead of main; push to origin too so no origin-diverge issue.
        New-SandboxBranch -Sandbox $sb -Name 'feature/A' -StartPoint $base
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/A') | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'a.txt' -Content "A`n" -Message 'A work'
        Invoke-SandboxGit $sb.Repo @('push', 'origin', 'feature/A') | Out-Null
        $aLocalBefore = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/A'
        # feature/A-child: descends from feature/A with extra unmerged work (NOT selected in this run).
        New-SandboxBranch -Sandbox $sb -Name 'feature/A-child' -StartPoint 'feature/A'
        Invoke-SandboxGit $sb.Repo @('switch', 'feature/A-child') | Out-Null
        $childTipBefore = New-SandboxCommit -Sandbox $sb -FileName 'c.txt' -Content "child`n" -Message 'child work'
        Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null

        # gitsync feature/A: 2-branch engine converges main and feature/A bidirectionally.
        # feature/A-child is a descendant of feature/A but is NOT part of this run (not selected).
        $ok = Invoke-ProductCommand -Script 'gitsync.ps1' -Func 'gitsync' -Arg 'feature/A' -Sandbox $sb
        Assert-True $ok 'gitsync 2-branch of main+feature/A should succeed (feature/A-child is irrelevant to 2-branch)'

        # feature/A-child must be untouched (not pushed, not moved, not lost).
        $childTipAfter = Get-SandboxRef -Sandbox $sb -Ref 'refs/heads/feature/A-child'
        Assert-Equal $childTipBefore $childTipAfter -Message 'feature/A-child must be unchanged: not part of this 2-branch run'

        # feature/A-child must NOT be pushed to origin (only the converged branches are pushed).
        $ls = Invoke-SandboxGit $sb.Repo @('ls-remote', $origin, 'refs/heads/feature/A-child')
        Assert-Equal '' ((@($ls.Output) -join ' ').Trim()) -Message 'feature/A-child must not be pushed (was not part of this run)'

        # feature/A must be pushed (it was converged by the 2-branch engine).
        $lsA = Invoke-SandboxGit $sb.Repo @('ls-remote', $origin, 'refs/heads/feature/A')
        Assert-False ([string]::IsNullOrWhiteSpace((@($lsA.Output) -join ' ').Trim())) 'feature/A must be pushed (it was converged)'
    }
    finally { Remove-GitSandbox $sb }
}
