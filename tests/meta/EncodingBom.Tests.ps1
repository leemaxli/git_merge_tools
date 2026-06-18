$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # tests/meta -> repo root

# AGENTS.md convention (WinPS 5.1 parse safety): a PowerShell source file that contains any non-ASCII
# byte MUST be saved as UTF-8 WITH a BOM, or Windows PowerShell 5.1 decodes it with the system ANSI
# code page (cp936/GBK here) and mis-parses it. This guard scans every product + test script so the
# convention can't silently regress (it would have caught Core.psm1's BOM-less em-dash).
Test-Case 'every PowerShell source containing non-ASCII has a UTF-8 BOM (WinPS 5.1 parse safety)' {
    $files = Get-ChildItem -Path $repoRoot -Recurse -File |
        Where-Object { $_.Extension -in '.ps1', '.psm1' -and $_.FullName -notmatch '[\\/]\.git[\\/]' }
    foreach ($file in $files) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasNonAscii = $false
        foreach ($b in $bytes) { if ($b -gt 127) { $hasNonAscii = $true; break } }
        $rel = $file.FullName.Substring($repoRoot.Length + 1)
        if ($hasNonAscii) {
            Assert-True $hasBom "non-ASCII PowerShell source must be UTF-8 with BOM for WinPS 5.1: $rel"
        }
    }
}
