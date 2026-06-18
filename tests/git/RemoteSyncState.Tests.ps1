$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulesRoot = Join-Path $repoRoot 'Modules'
Import-Module (Join-Path $modulesRoot 'GitMergeTools.Core.psm1') -Force
Import-Module (Join-Path $modulesRoot 'GitMergeTools.Merge.psm1') -Force

# Pure classifier behind the gitsync REMOTE PULL phase (v6.x): how does local <branch> relate to
# origin/<branch>? Remote-tracking refs are set directly with update-ref so each state is deterministic
# without standing up a real remote.
function Set-SandboxOriginRef {
    param($Sandbox, [string]$Branch, [string]$Hash)
    Invoke-SandboxGit $Sandbox.Repo @('update-ref', "refs/remotes/origin/$Branch", $Hash) | Out-Null
}

Test-Case 'Get-RemoteBranchSyncState: UpToDate when origin == local' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "a`n" -Message 'c1'
        Set-SandboxOriginRef $sb 'main' $c1
        Assert-Equal 'UpToDate' (Get-RemoteBranchSyncState -Repository $sb.Repo -Branch 'main') -Message 'equal refs => UpToDate'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'Get-RemoteBranchSyncState: UpToDate when origin branch is absent (nothing to pull)' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "a`n" -Message 'c1'
        Assert-Equal 'UpToDate' (Get-RemoteBranchSyncState -Repository $sb.Repo -Branch 'main') -Message 'no origin branch => nothing to pull'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'Get-RemoteBranchSyncState: LocalAhead when local has commits origin lacks' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "a`n" -Message 'c1'
        Set-SandboxOriginRef $sb 'main' $c1
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "b`n" -Message 'c2'   # local ahead
        Assert-Equal 'LocalAhead' (Get-RemoteBranchSyncState -Repository $sb.Repo -Branch 'main') -Message 'origin behind => LocalAhead'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'Get-RemoteBranchSyncState: FastForwardable when origin is ahead (true FF)' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "a`n" -Message 'c1'
        $c2 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "b`n" -Message 'c2'
        Set-SandboxOriginRef $sb 'main' $c2
        Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null    # local back to c1, origin = c2
        Assert-Equal 'FastForwardable' (Get-RemoteBranchSyncState -Repository $sb.Repo -Branch 'main') -Message 'origin ahead (FF) => FastForwardable'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'Get-RemoteBranchSyncState: Diverged when local and origin moved independently' {
    $sb = New-GitSandbox
    try {
        $c1 = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "a`n" -Message 'c1'
        $cOrigin = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "origin`n" -Message 'origin side'
        Set-SandboxOriginRef $sb 'main' $cOrigin
        Invoke-SandboxGit $sb.Repo @('reset', '--hard', $c1) | Out-Null
        $null = New-SandboxCommit -Sandbox $sb -FileName 'g.txt' -Content "local`n" -Message 'local side'  # diverges from cOrigin
        Assert-Equal 'Diverged' (Get-RemoteBranchSyncState -Repository $sb.Repo -Branch 'main') -Message 'both moved => Diverged'
    } finally { Remove-GitSandbox $sb }
}
