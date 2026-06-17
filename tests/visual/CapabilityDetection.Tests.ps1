$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Test-Case 'rich env detection flags a bare console (no WT_SESSION/TERM_PROGRAM, TERM unset) as not-capable' {
    Import-Module (Join-Path $repoRoot 'GitMergeTools.Common.PowerShell7.psm1') -Force
    $saved = @{ WT = $env:WT_SESSION; TP = $env:TERM_PROGRAM; TERM = $env:TERM }
    try {
        Remove-Item Env:WT_SESSION -ErrorAction SilentlyContinue
        Remove-Item Env:TERM_PROGRAM -ErrorAction SilentlyContinue
        Remove-Item Env:TERM -ErrorAction SilentlyContinue
        $state = Test-GitMergeToolsPowerShell7RichVisualEnvironment
        $reasons = @($state.Reasons) -join ' | '
        Assert-Match 'Terminal capability' $reasons -Message 'a bare console should add the terminal-capability reason'
    }
    finally {
        if ($saved.WT) { $env:WT_SESSION = $saved.WT } else { Remove-Item Env:WT_SESSION -ErrorAction SilentlyContinue }
        if ($saved.TP) { $env:TERM_PROGRAM = $saved.TP } else { Remove-Item Env:TERM_PROGRAM -ErrorAction SilentlyContinue }
        if ($saved.TERM) { $env:TERM = $saved.TERM } else { Remove-Item Env:TERM -ErrorAction SilentlyContinue }
    }
}

Test-Case 'rich env detection does NOT add the terminal reason when WT_SESSION is set' {
    Import-Module (Join-Path $repoRoot 'GitMergeTools.Common.PowerShell7.psm1') -Force
    $saved = @{ WT = $env:WT_SESSION; TP = $env:TERM_PROGRAM; TERM = $env:TERM }
    try {
        $env:WT_SESSION = 'test-session'
        Remove-Item Env:TERM_PROGRAM -ErrorAction SilentlyContinue
        Remove-Item Env:TERM -ErrorAction SilentlyContinue
        $state = Test-GitMergeToolsPowerShell7RichVisualEnvironment
        $reasons = @($state.Reasons) -join ' | '
        Assert-False ($reasons -match 'Terminal capability') 'WT_SESSION present should NOT add the terminal reason'
    }
    finally {
        if ($saved.WT) { $env:WT_SESSION = $saved.WT } else { Remove-Item Env:WT_SESSION -ErrorAction SilentlyContinue }
        if ($saved.TP) { $env:TERM_PROGRAM = $saved.TP } else { Remove-Item Env:TERM_PROGRAM -ErrorAction SilentlyContinue }
        if ($saved.TERM) { $env:TERM = $saved.TERM } else { Remove-Item Env:TERM -ErrorAction SilentlyContinue }
    }
}

Test-Case 'pinned standard falls back to basic when console output is not UTF-8' {
    Import-Module (Join-Path $repoRoot 'GitMergeTools.Common.psm1') -Force
    $savedMode = $env:GITMERGE_VISUAL_MODE
    $savedEnc = [Console]::OutputEncoding
    try {
        $env:GITMERGE_VISUAL_MODE = 'standard'
        [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(1252)  # non-UTF-8
        $visual = New-GitMergeToolsVisual -CommandName 'gitmerge' -ScriptRoot $repoRoot -PSCommandPath (Join-Path $repoRoot 'gitmerge.ps1')
        Assert-Equal 'basic' $visual.VisualLevel -Message 'standard must degrade to basic on a non-UTF-8 console'
    }
    finally {
        if ($savedMode) { $env:GITMERGE_VISUAL_MODE = $savedMode } else { Remove-Item Env:GITMERGE_VISUAL_MODE -ErrorAction SilentlyContinue }
        [Console]::OutputEncoding = $savedEnc
    }
}
