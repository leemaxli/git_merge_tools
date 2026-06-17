# Hermetic, disposable git repos for tests. Never touches the real repo or user/global git config.
Set-StrictMode -Version Latest

$script:Sandboxes = [System.Collections.Generic.List[string]]::new()

function Test-IsWindowsRuntime {
    # $IsWindows is undefined on Windows PowerShell 5.1, so derive it portably.
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return $true }
    if ($null -ne (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue)) { return [bool]$IsWindows }
    return ($PSVersionTable.Platform -eq 'Win32NT')
}

function Get-CanonicalPath {
    param([Parameter(Mandatory)][string]$Path)
    # Resolve symlinks (macOS /var -> /private/var) and normalize, on both runtimes.
    $full = [System.IO.Path]::GetFullPath($Path)
    try {
        $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if ($null -ne $item.PSObject.Properties['Target'] -and $item.Target) {
            $resolved = (Resolve-Path -LiteralPath $full -ErrorAction Stop).ProviderPath
            if ($resolved) { $full = [System.IO.Path]::GetFullPath($resolved) }
        }
    } catch { }
    return $full.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Invoke-SandboxGit {
    # Runs git with UTF-8 stdout/stderr decoding (independent of console code page) and returns ExitCode + Output.
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string[]]$Arguments)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'git'
    $all = @('-C', $RepoPath) + $Arguments
    if ($psi.PSObject.Properties['ArgumentList']) {
        foreach ($a in $all) { [void]$psi.ArgumentList.Add($a) }
    } else {
        # Windows PowerShell 5.1 / .NET Framework: no ArgumentList — build a quoted string.
        $psi.Arguments = ($all | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' } else { $_ }
        }) -join ' '
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $errTask = $p.StandardError.ReadToEndAsync()   # read stderr async to avoid pipe-buffer deadlock
        $out = $p.StandardOutput.ReadToEnd()
        $errOut = $errTask.GetAwaiter().GetResult()
        $p.WaitForExit()
        $code = $p.ExitCode
    } finally { $p.Dispose() }
    $lines = @()
    foreach ($chunk in @($out, $errOut)) {
        if (-not [string]::IsNullOrEmpty($chunk)) { $lines += ($chunk -split "`r?`n") }
    }
    return [pscustomobject]@{ ExitCode = $code; Output = [string[]]@($lines | Where-Object { $_ -ne '' }) }
}

function New-GitSandbox {
    # Returns @{ Root; Repo; Home }. Creates a hermetic repo with main checked out at one commit.
    [CmdletBinding()]
    param([string]$DefaultBranch = 'main')

    $id = [guid]::NewGuid().ToString('N')
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "gmt-tests-$id"
    $homeDir = Join-Path $root 'home'
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path $homeDir -Force | Out-Null
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    $script:Sandboxes.Add($root)

    # Hermetic git environment (spec §21). Process-scoped env; each test sets these before git runs.
    $env:HOME = $homeDir
    if (Test-IsWindowsRuntime) { $env:USERPROFILE = $homeDir }
    $env:XDG_CONFIG_HOME = (Join-Path $homeDir '.config')
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $env:GIT_CONFIG_GLOBAL = (Join-Path $homeDir '.gitconfig')
    $env:GIT_CONFIG_SYSTEM = if (Test-IsWindowsRuntime) { 'NUL' } else { '/dev/null' }
    foreach ($v in 'GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_COMMON_DIR') {
        Remove-Item -LiteralPath "Env:$v" -ErrorAction SilentlyContinue
    }
    $env:GIT_AUTHOR_NAME = 'GMT Test'; $env:GIT_AUTHOR_EMAIL = 'gmt@test.local'
    $env:GIT_COMMITTER_NAME = 'GMT Test'; $env:GIT_COMMITTER_EMAIL = 'gmt@test.local'
    $env:GIT_AUTHOR_DATE = '2020-01-01T00:00:00 +0000'; $env:GIT_COMMITTER_DATE = '2020-01-01T00:00:00 +0000'

    # Sandbox-local config: identity + allow operating on this tree regardless of owner.
    Set-Content -LiteralPath $env:GIT_CONFIG_GLOBAL -Value "[user]`n`tname = GMT Test`n`temail = gmt@test.local`n[init]`n`tdefaultBranch = $DefaultBranch`n[safe]`n`tdirectory = *`n" -Encoding ascii

    $init = Invoke-SandboxGit $repo @('init', '-b', $DefaultBranch)
    if ($init.ExitCode -ne 0) { throw "git init failed: $($init.Output -join '; ')" }

    return [pscustomobject]@{ Root = $root; Repo = $repo; Home = $homeDir; DefaultBranch = $DefaultBranch }
}

function Assert-PathInSandbox {
    # The containment guard: throw unless $Path is inside $Sandbox.Root (canonicalized).
    param([Parameter(Mandatory)]$Sandbox, [Parameter(Mandatory)][string]$Path)
    $rootC = Get-CanonicalPath $Sandbox.Root
    $pathC = Get-CanonicalPath $Path
    $sep = [System.IO.Path]::DirectorySeparatorChar
    if ($pathC -ne $rootC -and -not $pathC.StartsWith($rootC + $sep, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "REFUSING: path '$pathC' is outside sandbox '$rootC'"
    }
}

function New-SandboxCommit {
    param([Parameter(Mandatory)]$Sandbox, [string]$FileName = 'file.txt', [Parameter(Mandatory)][string]$Content, [string]$Message = 'commit')
    $full = Join-Path $Sandbox.Repo $FileName
    Assert-PathInSandbox $Sandbox $full
    Set-Content -LiteralPath $full -Value $Content -Encoding utf8
    $add = Invoke-SandboxGit $Sandbox.Repo @('add', '--', $FileName)
    if ($add.ExitCode -ne 0) { throw "git add failed: $($add.Output -join '; ')" }
    $commit = Invoke-SandboxGit $Sandbox.Repo @('commit', '-m', $Message)
    if ($commit.ExitCode -ne 0) { throw "git commit failed: $($commit.Output -join '; ')" }
    return (Invoke-SandboxGit $Sandbox.Repo @('rev-parse', 'HEAD')).Output[0]
}

function New-SandboxBranch {
    param([Parameter(Mandatory)]$Sandbox, [Parameter(Mandatory)][string]$Name, [string]$StartPoint = 'HEAD')
    $r = Invoke-SandboxGit $Sandbox.Repo @('branch', '--', $Name, $StartPoint)
    if ($r.ExitCode -ne 0) { throw "git branch failed: $($r.Output -join '; ')" }
}

function Get-SandboxRef {
    param([Parameter(Mandatory)]$Sandbox, [Parameter(Mandatory)][string]$Ref)
    $r = Invoke-SandboxGit $Sandbox.Repo @('rev-parse', '--verify', '--quiet', $Ref)
    if ($r.ExitCode -ne 0) { return $null }
    return $r.Output[0]
}

function Remove-GitSandbox {
    param([Parameter(Mandatory)]$Sandbox)
    Remove-SandboxPath $Sandbox.Root
    [void]$script:Sandboxes.Remove($Sandbox.Root)
}

function Remove-SandboxPath {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    # Windows: .git pack/idx files are read-only; clear attrs before delete, then bounded retry.
    try {
        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Attributes = 'Normal' } catch { }
        }
    } catch { }
    for ($i = 0; $i -lt 5; $i++) {
        try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop; return }
        catch { Start-Sleep -Milliseconds 150 }
    }
    Write-Warning "Could not remove sandbox path: $Path"
}

function Clear-AllSandboxes {
    foreach ($root in @($script:Sandboxes.ToArray())) { Remove-SandboxPath $root }
    $script:Sandboxes = [System.Collections.Generic.List[string]]::new()
}

Export-ModuleMember -Function Test-IsWindowsRuntime, Get-CanonicalPath, Invoke-SandboxGit, New-GitSandbox, `
    Assert-PathInSandbox, New-SandboxCommit, New-SandboxBranch, Get-SandboxRef, Remove-GitSandbox, Clear-AllSandboxes
