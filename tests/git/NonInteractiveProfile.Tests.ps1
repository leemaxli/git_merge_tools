$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path (Join-Path $repoRoot 'Modules') 'GitMergeTools.Core.psm1') -Force

# Git-safety hardening: every git invocation through the shared Invoke-GitCommand runs under a
# non-interactive, long-path-safe profile so the tool can never block on a credential or editor prompt
# (a silent hang), never trips MAX_PATH on its own file operations, and never lets a user's recorded
# rerere resolution auto-resolve one of our throwaway integration merges (which would let a real
# conflict slip through and corrupt main's tree). The `-c` overrides are visible to `git config` /
# `git var` in the SAME process, so they are observable behaviorally.

Test-Case 'Invoke-GitCommand forces core.longpaths=true into every git process (Windows long-path safety)' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $r = Invoke-GitCommand $sb.Repo @('config', '--get', 'core.longpaths')
        Assert-Equal 'true' (Get-FirstOutputLine $r) -Message "core.longpaths must be forced on for the tool's own git calls"
    }
    finally { Remove-GitSandbox $sb }
}

Test-Case 'Invoke-GitCommand forces rerere.enabled=false (no recorded resolution auto-applied to our merges)' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $r = Invoke-GitCommand $sb.Repo @('config', '--get', 'rerere.enabled')
        Assert-Equal 'false' (Get-FirstOutputLine $r) -Message 'rerere must be disabled so conflict detection stays honest'
    }
    finally { Remove-GitSandbox $sb }
}

Test-Case 'Invoke-GitCommand runs git with a non-interactive editor (GIT_EDITOR=true, never opens an editor)' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        # `git var GIT_EDITOR` reports the editor git WOULD use (without launching it). Seed an
        # interactive-looking editor first so the test proves OUR profile overrides it to the no-op
        # `true` command, regardless of the ambient environment.
        $savedEditor = $env:GIT_EDITOR
        try {
            $env:GIT_EDITOR = 'sentinel-editor'
            $r = Invoke-GitCommand $sb.Repo @('var', 'GIT_EDITOR')
            Assert-Equal 'true' (Get-FirstOutputLine $r) -Message 'git must resolve a no-op editor so a merge can never block on an editor prompt'
        }
        finally {
            if ($null -eq $savedEditor) { Remove-Item -LiteralPath Env:GIT_EDITOR -ErrorAction SilentlyContinue } else { $env:GIT_EDITOR = $savedEditor }
        }
    }
    finally { Remove-GitSandbox $sb }
}

Test-Case 'Invoke-GitCommand restores ambient GIT_TERMINAL_PROMPT / GIT_EDITOR after the call (no global leak)' {
    $sb = New-GitSandbox
    try {
        $null = New-SandboxCommit -Sandbox $sb -FileName 'f.txt' -Content "base`n" -Message 'base'
        $savedPrompt = $env:GIT_TERMINAL_PROMPT
        $savedEditor = $env:GIT_EDITOR
        try {
            $env:GIT_TERMINAL_PROMPT = 'sentinel-prompt'
            $env:GIT_EDITOR = 'sentinel-editor'
            $null = Invoke-GitCommand $sb.Repo @('rev-parse', 'HEAD')
            Assert-Equal 'sentinel-prompt' $env:GIT_TERMINAL_PROMPT -Message 'GIT_TERMINAL_PROMPT must be restored, not leaked'
            Assert-Equal 'sentinel-editor' $env:GIT_EDITOR -Message 'GIT_EDITOR must be restored, not leaked'
        }
        finally {
            if ($null -eq $savedPrompt) { Remove-Item -LiteralPath Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue } else { $env:GIT_TERMINAL_PROMPT = $savedPrompt }
            if ($null -eq $savedEditor) { Remove-Item -LiteralPath Env:GIT_EDITOR -ErrorAction SilentlyContinue } else { $env:GIT_EDITOR = $savedEditor }
        }
    }
    finally { Remove-GitSandbox $sb }
}
