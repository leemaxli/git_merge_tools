. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# v7.3.1: after the Get-Mode 'all'/'cross-all' split, gitstatus must show the ahead/behind comparison for
# BOTH all and cross-all (not just all) -- both report every branch, so both should show the comparison.
function New-TwoBranchStatusSandbox {
    $sb = New-GitSandbox
    $base = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
    New-SandboxBranch -Sandbox $sb -Name 'feature/x' -StartPoint $base
    Invoke-SandboxGit $sb.Repo @('switch', 'feature/x') | Out-Null
    [void](New-SandboxCommit -Sandbox $sb -FileName 'x.txt' -Content "x`n" -Message 'x work')
    Invoke-SandboxGit $sb.Repo @('switch', 'main') | Out-Null
    return $sb
}

Test-Case 'gitstatus cross-all shows the ahead/behind comparison (like all)' {
    $sb = New-TwoBranchStatusSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Arg 'cross-all' -Sandbox $sb
        Assert-Match 'vs main' $out -Message 'cross-all must show the vs-main comparison for non-main branches'
    } finally { Remove-GitSandbox $sb }
}

Test-Case 'gitstatus all still shows the ahead/behind comparison' {
    $sb = New-TwoBranchStatusSandbox
    try {
        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Arg 'all' -Sandbox $sb
        Assert-Match 'vs main' $out -Message 'all must show the vs-main comparison'
    } finally { Remove-GitSandbox $sb }
}
