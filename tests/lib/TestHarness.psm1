# Dependency-free test harness for GitMergeTools. Works on Windows PowerShell 5.1 and PowerShell 7+.
Set-StrictMode -Version Latest

$script:Results = [System.Collections.Generic.List[object]]::new()

function Reset-TestState {
    $script:Results = [System.Collections.Generic.List[object]]::new()
}

class AssertionError : System.Exception {
    AssertionError([string]$m) : base($m) {}
}

function New-AssertionError([string]$Message) {
    # Cross-version: class-based exception works on 5.1 and 7.
    return [AssertionError]::new($Message)
}

function Assert-True {
    param([Parameter(Mandatory)]$Condition, [string]$Message = 'Expected condition to be true')
    if (-not $Condition) { throw (New-AssertionError $Message) }
}

function Assert-False {
    param([Parameter(Mandatory)]$Condition, [string]$Message = 'Expected condition to be false')
    if ($Condition) { throw (New-AssertionError $Message) }
}

function Assert-Equal {
    param([Parameter(Position = 0)]$Expected, [Parameter(Position = 1)]$Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        $m = if ($Message) { $Message } else { "Expected '<$Expected>' but got '<$Actual>'" }
        throw (New-AssertionError $m)
    }
}

function Assert-Match {
    param([Parameter(Position = 0)][string]$Pattern, [Parameter(Position = 1)][string]$Text, [string]$Message)
    if ($Text -notmatch $Pattern) {
        $m = if ($Message) { $Message } else { "Expected '<$Text>' to match /$Pattern/" }
        throw (New-AssertionError $m)
    }
}

function Test-Case {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory, Position = 1)][scriptblock]$Body,
        [switch]$KnownFail
    )
    $err = $null
    try { & $Body } catch { $err = $_ }

    if ($KnownFail) {
        # A KnownFail that fails is the expected (documented-bug) state => 'xfail' (counts as ok).
        # A KnownFail that PASSES means the bug was fixed => 'xpass' (counts as failure so we flip it).
        $status = if ($err) { 'xfail' } else { 'xpass' }
    }
    else {
        $status = if ($err) { 'fail' } else { 'pass' }
    }

    $script:Results.Add([pscustomobject]@{
        Name    = $Name
        Status  = $status
        Error   = if ($err) { $err.Exception.Message } else { '' }
    })

    $color = switch ($status) { 'pass' { 'Green' } 'xfail' { 'DarkYellow' } 'xpass' { 'Red' } default { 'Red' } }
    $tag = switch ($status) { 'pass' { 'PASS ' } 'fail' { 'FAIL ' } 'xfail' { 'XFAIL' } 'xpass' { 'XPASS' } }
    Write-Host ("  [{0}] {1}" -f $tag, $Name) -ForegroundColor $color
    if ($err) { Write-Host ("         -> {0}" -f $err.Exception.Message) -ForegroundColor DarkGray }
}

function Write-TestSummary {
    # Returns the process exit code (0 = success).
    $pass  = @($script:Results | Where-Object { $_.Status -eq 'pass' }).Count
    $fail  = @($script:Results | Where-Object { $_.Status -eq 'fail' }).Count
    $xfail = @($script:Results | Where-Object { $_.Status -eq 'xfail' }).Count
    $xpass = @($script:Results | Where-Object { $_.Status -eq 'xpass' }).Count
    Write-Host ''
    Write-Host ("Summary: {0} passed, {1} failed, {2} xfail (known bugs), {3} xpass (FIX DETECTED -> flip the test)" -f $pass, $fail, $xfail, $xpass)
    # xpass is a failure: a -KnownFail test started passing, so the test must be un-flagged.
    if ($fail -gt 0 -or $xpass -gt 0) { return 1 }
    return 0
}

Export-ModuleMember -Function Reset-TestState, Assert-True, Assert-False, Assert-Equal, Assert-Match, Test-Case, Write-TestSummary
