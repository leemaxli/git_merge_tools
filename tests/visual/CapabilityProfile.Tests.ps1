$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path (Join-Path $repoRoot 'Modules') 'GitMergeTools.Common.psm1') -Force

# ---- pure color-level resolver ----
Test-Case 'color level: redirected => 0 (no color into a non-tty stream)' {
    Assert-Equal 0 (Resolve-GitMergeToolsColorLevel -IsRedirected $true -NoColor $false -ColorTerm 'truecolor' -WtSession '' -Term 'xterm-256color' -WindowsBuild 0) -Message 'redirected must force 0'
}
Test-Case 'color level: NO_COLOR => 0' {
    Assert-Equal 0 (Resolve-GitMergeToolsColorLevel -IsRedirected $false -NoColor $true -ColorTerm 'truecolor' -WtSession 'x' -Term '' -WindowsBuild 22000) -Message 'NO_COLOR must force 0'
}
Test-Case 'color level: TERM=dumb => 0' {
    Assert-Equal 0 (Resolve-GitMergeToolsColorLevel -IsRedirected $false -NoColor $false -ColorTerm '' -WtSession '' -Term 'dumb' -WindowsBuild 0) -Message 'dumb terminal => 0'
}
Test-Case 'color level: COLORTERM=truecolor => 3' {
    Assert-Equal 3 (Resolve-GitMergeToolsColorLevel -IsRedirected $false -NoColor $false -ColorTerm 'truecolor' -WtSession '' -Term 'xterm' -WindowsBuild 0) -Message 'truecolor COLORTERM => 3'
}
Test-Case 'color level: WT_SESSION present => 3 (Windows Terminal sets no COLORTERM)' {
    Assert-Equal 3 (Resolve-GitMergeToolsColorLevel -IsRedirected $false -NoColor $false -ColorTerm '' -WtSession 'abc' -Term '' -WindowsBuild 0) -Message 'WT_SESSION => 3'
}
Test-Case 'color level: Windows build >= 14931 => 3' {
    Assert-Equal 3 (Resolve-GitMergeToolsColorLevel -IsRedirected $false -NoColor $false -ColorTerm '' -WtSession '' -Term '' -WindowsBuild 19045) -Message 'modern Windows build => 3'
}
Test-Case 'color level: TERM=*-256color => 2' {
    Assert-Equal 2 (Resolve-GitMergeToolsColorLevel -IsRedirected $false -NoColor $false -ColorTerm '' -WtSession '' -Term 'xterm-256color' -WindowsBuild 0) -Message '256color TERM => 2'
}
Test-Case 'color level: plain interactive TTY => 1' {
    Assert-Equal 1 (Resolve-GitMergeToolsColorLevel -IsRedirected $false -NoColor $false -ColorTerm '' -WtSession '' -Term 'xterm' -WindowsBuild 0) -Message 'plain tty => 1 (16-color)'
}

# ---- capability profile gatherer ----
Test-Case 'capability profile returns all fields with correct types and clamped width' {
    $p = Get-GitMergeToolsCapabilityProfile
    foreach ($f in 'IsRedirected', 'NoColor', 'IsCI', 'HasVT', 'UnicodeOk', 'ColorLevel', 'Width') {
        Assert-True ($null -ne $p.PSObject.Properties[$f]) -Message "profile missing field $f"
    }
    Assert-True ($p.ColorLevel -ge 0 -and $p.ColorLevel -le 3) -Message 'ColorLevel in 0..3'
    Assert-True ($p.Width -ge 40 -and $p.Width -le 110) -Message 'Width clamped to 40..110'
    Assert-True ($p.IsRedirected -is [bool]) -Message 'IsRedirected is bool'
}
Test-Case 'capability profile honors NO_COLOR (present => NoColor true => ColorLevel 0)' {
    $saved = [Environment]::GetEnvironmentVariable('NO_COLOR')
    try {
        $env:NO_COLOR = '1'
        $p = Get-GitMergeToolsCapabilityProfile
        Assert-True $p.NoColor -Message 'NO_COLOR present => NoColor true'
        Assert-Equal 0 $p.ColorLevel -Message 'NO_COLOR => ColorLevel 0'
    }
    finally {
        if ($null -ne $saved) { $env:NO_COLOR = $saved } else { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
    }
}
Test-Case 'capability profile detects CI' {
    $saved = $env:CI
    try {
        $env:CI = 'true'
        $p = Get-GitMergeToolsCapabilityProfile
        Assert-True $p.IsCI -Message 'CI env => IsCI true'
    }
    finally {
        if ($null -ne $saved) { $env:CI = $saved } else { Remove-Item Env:CI -ErrorAction SilentlyContinue }
    }
}
