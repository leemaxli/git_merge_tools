# Shared helper for smoke + characterization tests. NOT a test file (the runner globs *.Tests.ps1).
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)  # tests/smoke -> repo root

function Invoke-ProductCommand {
    # Dot-sources the product script (by its real path) into a fresh child scope and invokes the
    # function with CWD set to the sandbox repo. Returns the function's [bool] result.
    param([Parameter(Mandatory)][string]$Script, [Parameter(Mandatory)][string]$Func,
          [string]$Arg = '', [Parameter(Mandatory)]$Sandbox, [string]$VisualMode = 'basic')
    $prevCwd = (Get-Location).Path
    $prevVisual = $env:GITMERGE_VISUAL_MODE
    $prevSuppress = $env:GITMERGE_TOOLS_SUPPRESS_WARNING
    $prevHome = $env:GITMERGE_TOOLS_HOME
    try {
        Set-Location -LiteralPath $Sandbox.Repo
        $env:GITMERGE_VISUAL_MODE = $VisualMode
        $env:GITMERGE_TOOLS_SUPPRESS_WARNING = '1'
        # GITMERGE_TOOLS_HOME points the visual-module loader at the repo so it can find the
        # GitMergeTools.*.psm1 modules independent of profile/install locations.
        $env:GITMERGE_TOOLS_HOME = $repoRoot
        # Dot-source the REAL product file (not a [scriptblock]::Create from its text): a created
        # scriptblock has no file association, so $PSScriptRoot/$PSCommandPath are empty inside the
        # product's nested functions and its `Split-Path -Parent $PSCommandPath` throws. Dot-sourcing
        # the actual file gives the product the same $PSScriptRoot it gets when run as a script.
        # Load ALL three tools into one scope (as a real user profile does), so peer commands like
        # gitsync can resolve gitmerge. Dot-sourcing only defines functions (no load-time side effects).
        $invoker = {
            param($RepoRoot, $FuncName, $FuncArg)
            foreach ($s in 'gitmerge.ps1', 'gitsync.ps1', 'gitstatus.ps1') {
                $p = Join-Path $RepoRoot $s
                if (Test-Path -LiteralPath $p) { . $p }
            }
            $gmtResult = if ($FuncArg) { & $FuncName $FuncArg } else { & $FuncName }
            @($gmtResult | Where-Object { $_ -is [bool] }) | Select-Object -Last 1
        }
        $result = & $invoker $repoRoot $Func $Arg 2>&1 | Where-Object { $_ -is [bool] } | Select-Object -Last 1
        return [bool]$result
    }
    finally {
        Set-Location -LiteralPath $prevCwd
        $env:GITMERGE_VISUAL_MODE = $prevVisual
        $env:GITMERGE_TOOLS_SUPPRESS_WARNING = $prevSuppress
        $env:GITMERGE_TOOLS_HOME = $prevHome
    }
}

function Invoke-ProductCommandText {
    # Like Invoke-ProductCommand but returns ALL captured output (every stream) as one string,
    # for asserting on warnings/messages. (git failure warnings surface regardless of suppress.)
    param([Parameter(Mandatory)][string]$Script, [Parameter(Mandatory)][string]$Func,
        [string]$Arg = '', [Parameter(Mandatory)]$Sandbox, [string]$VisualMode = 'basic')
    $prevCwd = (Get-Location).Path
    $prevVisual = $env:GITMERGE_VISUAL_MODE
    $prevSuppress = $env:GITMERGE_TOOLS_SUPPRESS_WARNING
    $prevHome = $env:GITMERGE_TOOLS_HOME
    try {
        Set-Location -LiteralPath $Sandbox.Repo
        $env:GITMERGE_VISUAL_MODE = $VisualMode
        $env:GITMERGE_TOOLS_SUPPRESS_WARNING = '1'
        $env:GITMERGE_TOOLS_HOME = $repoRoot
        $invoker = {
            param($RepoRoot, $FuncName, $FuncArg)
            foreach ($s in 'gitmerge.ps1', 'gitsync.ps1', 'gitstatus.ps1') {
                $p = Join-Path $RepoRoot $s
                if (Test-Path -LiteralPath $p) { . $p }
            }
            if ($FuncArg) { & $FuncName $FuncArg } else { & $FuncName }
        }
        return (& $invoker $repoRoot $Func $Arg *>&1 | Out-String)
    }
    finally {
        Set-Location -LiteralPath $prevCwd
        $env:GITMERGE_VISUAL_MODE = $prevVisual
        $env:GITMERGE_TOOLS_SUPPRESS_WARNING = $prevSuppress
        $env:GITMERGE_TOOLS_HOME = $prevHome
    }
}
