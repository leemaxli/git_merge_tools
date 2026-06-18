$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path (Join-Path $repoRoot 'Modules') 'GitMergeTools.Visual.Common.psm1') -Force

# #5: banner/box truncation used String.Length (UTF-16 code units), so CJK/wide titles overflowed the
# frame and a surrogate pair could be cut in half. Truncation/padding must be display-width aware.
Test-Case 'Get-GitMergeToolsDisplayWidth counts CJK/wide as 2 columns and ASCII as 1' {
    Assert-Equal 5 (Get-GitMergeToolsDisplayWidth 'abcde') -Message 'ascii: 1 column each'
    $twoCjk = [string][char]0x6D4B + [string][char]0x8BD5   # two Han chars = 4 columns
    Assert-Equal 4 (Get-GitMergeToolsDisplayWidth $twoCjk) -Message 'two CJK = 4 columns'
}

Test-Case 'Format-GitMergeToolsFixedWidth truncates by display width, never overflows, never splits a surrogate pair' {
    Assert-Equal 'abcde' (Format-GitMergeToolsFixedWidth 'abcdefgh' 5) -Message 'ascii truncates to exactly N columns'

    $cjk = -join (1..4 | ForEach-Object { [char]0x6D4B })   # 4 wide chars = 8 columns
    $r = Format-GitMergeToolsFixedWidth $cjk 5
    Assert-Equal 5 (Get-GitMergeToolsDisplayWidth $r) -Message 'wide content truncates/pads to exact display width (no overflow)'

    $emoji = [char]::ConvertFromUtf32(0x1F500)              # wide, a surrogate pair (2 columns)
    Assert-Equal ' ' (Format-GitMergeToolsFixedWidth $emoji 1) -Message 'a 2-column glyph cannot fit in 1 column; pad, never emit half a surrogate'

    Assert-Equal 4 (Get-GitMergeToolsDisplayWidth (Format-GitMergeToolsFixedWidth 'ab' 4)) -Message 'narrow content is padded to exact display width'
}
