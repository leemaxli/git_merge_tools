. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

Test-Case 'gitstatus all does not fold a git stderr warning into the parsed branch list (#4 porcelain hygiene)' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        New-SandboxBranch -Sandbox $sb -Name 'feature/a'
        New-SandboxBranch -Sandbox $sb -Name 'feature/b'
        # A broken loose ref makes `git for-each-ref refs/heads/` print a warning to stderr (exit 0,
        # stdout still lists only the real refs). If gitstatus's Invoke-GitCommand folds stderr into
        # Output (the #4 `2>&1` drift), that warning line becomes a phantom "branch" and inflates the
        # parsed branch count from 3 to 4.
        $brokenRef = Join-Path $sb.Repo '.git/refs/heads/zzz-broken'
        [System.IO.File]::WriteAllText($brokenRef, ('0' * 40) + "`n")

        $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Arg 'all' -Sandbox $sb
        # main + feature/a + feature/b = 3 real branches; the stderr warning must NOT be counted.
        Assert-Match 'Target branches : 3' $out -Message 'porcelain reads must not fold git stderr into parsed Output (a warning became a phantom branch)'
    }
    finally { Remove-GitSandbox $sb }
}
