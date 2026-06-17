. (Join-Path (Split-Path -Parent $PSScriptRoot) 'smoke/Commands.Smoke.Tests.ps1.helper.ps1')

# Git-safety hardening: an inherited GIT_DIR / GIT_WORK_TREE / ... silently points git at the WRONG
# repository and bypasses the path-based containment guard entirely. The shared Invoke-GitCommand must
# neutralize these locating env vars (captured + restored) so commands always act on the resolved repo.
Test-Case 'an inherited GIT_DIR is neutralized; the command still resolves the real repo' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $prev = $env:GIT_DIR
        try {
            $env:GIT_DIR = (Join-Path $sb.Root 'bogus-not-a-git-dir')   # a leaked, wrong GIT_DIR
            $out = Invoke-ProductCommandText -Script 'gitstatus.ps1' -Func 'gitstatus' -Sandbox $sb
            Assert-Match 'Git root:' $out -Message 'a leaked GIT_DIR must be neutralized so the real repo resolves'
            Assert-False ([bool]($out -match 'not inside a Git repository')) 'a leaked GIT_DIR must not derail repository resolution'
        }
        finally {
            if ($null -eq $prev) { Remove-Item -LiteralPath Env:GIT_DIR -ErrorAction SilentlyContinue } else { $env:GIT_DIR = $prev }
        }
    }
    finally { Remove-GitSandbox $sb }
}
