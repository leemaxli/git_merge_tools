[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'Write-GitFailure renders interactive console diagnostics for the git commands.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseShouldProcessForStateChangingFunctions',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'These helpers wrap read-only git plumbing and string utilities; they change no state.'
)][Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSProvideCommentHelp',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'Single source of truth for the shared git primitives consumed by all three commands.'
)]
param()

# GitMergeTools.Core.psm1 -- the single source of truth for the git primitives that gitmerge / gitsync /
# gitstatus all consume (previously copy-pasted and drifted across the three entry scripts). No UI beyond
# the Write-GitFailure diagnostic; no merge-engine logic (that lives in the command / future Merge module).

function Invoke-GitCommand {
    param(
        [AllowEmptyString()]
        [string]$WorkingDirectory,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$MergeError,

        [switch]$SuppressError
    )

    $previousPreference = $ErrorActionPreference
    $previousOutputEncoding = [Console]::OutputEncoding
    # Neutralize inherited locating env vars (GIT_DIR/GIT_WORK_TREE/...): a leaked one silently points
    # git at the WRONG repository and bypasses the path-based containment guard. Captured here and
    # restored in finally, so there is no global side effect.
    $gitLocatorNames = @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_COMMON_DIR')
    $savedGitLocators = @{}
    foreach ($locatorName in $gitLocatorNames) {
        $savedGitLocators[$locatorName] = [Environment]::GetEnvironmentVariable($locatorName)
        if ($null -ne $savedGitLocators[$locatorName]) { Remove-Item -LiteralPath "Env:$locatorName" -ErrorAction SilentlyContinue }
    }
    # Non-interactive profile: fail fast instead of blocking on a credential prompt, and never spawn an
    # editor. Both are inherited env vars (highest precedence), captured here and restored in finally so
    # there is no global side effect.
    $nonInteractiveEnv = @{ GIT_TERMINAL_PROMPT = '0'; GIT_EDITOR = 'true' }
    $savedNonInteractiveEnv = @{}
    foreach ($envName in @($nonInteractiveEnv.Keys)) {
        $savedNonInteractiveEnv[$envName] = [Environment]::GetEnvironmentVariable($envName)
        Set-Item -LiteralPath "Env:$envName" -Value $nonInteractiveEnv[$envName] -ErrorAction SilentlyContinue
    }
    # Per-invocation config overrides (visible to git for this process only): long-path safety on the
    # tool's own file operations (a no-op off Windows), and rerere disabled so a user's recorded conflict
    # resolution can never silently auto-resolve one of our throwaway integration merges.
    $gitConfigArgs = @('-c', 'core.longpaths=true', '-c', 'rerere.enabled=false')
    $ErrorActionPreference = 'Continue'
    try {
        # Decode git stdout as UTF-8 regardless of the console code page (cp936/OEM on a redirected or
        # 5.1 stdout) so non-ASCII branch names round-trip byte-exact (#1); restored in finally.
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        if ([string]::IsNullOrEmpty($WorkingDirectory)) {
            if ($MergeError) {
                $rawOutput = @(& git @gitConfigArgs @Arguments 2>&1)
            }
            elseif ($SuppressError) {
                $rawOutput = @(& git @gitConfigArgs @Arguments 2>$null)
            }
            else {
                $rawOutput = @(& git @gitConfigArgs @Arguments)
            }
        }
        else {
            if ($MergeError) {
                $rawOutput = @(& git -C $WorkingDirectory @gitConfigArgs @Arguments 2>&1)
            }
            elseif ($SuppressError) {
                $rawOutput = @(& git -C $WorkingDirectory @gitConfigArgs @Arguments 2>$null)
            }
            else {
                $rawOutput = @(& git -C $WorkingDirectory @gitConfigArgs @Arguments)
            }
        }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
        [Console]::OutputEncoding = $previousOutputEncoding
        foreach ($locatorName in $gitLocatorNames) {
            if ($null -ne $savedGitLocators[$locatorName]) { Set-Item -LiteralPath "Env:$locatorName" -Value $savedGitLocators[$locatorName] -ErrorAction SilentlyContinue }
        }
        foreach ($envName in @($savedNonInteractiveEnv.Keys)) {
            if ($null -eq $savedNonInteractiveEnv[$envName]) { Remove-Item -LiteralPath "Env:$envName" -ErrorAction SilentlyContinue }
            else { Set-Item -LiteralPath "Env:$envName" -Value $savedNonInteractiveEnv[$envName] -ErrorAction SilentlyContinue }
        }
    }

    $output = @($rawOutput | ForEach-Object { $_.ToString() })
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = [string[]]$output
    }
}

function Get-FirstOutputLine {
    param([Parameter(Mandatory)]$Result)
    $lines = @($Result.Output)
    if ($lines.Count -eq 0) { return $null }
    return $lines[0].Trim()
}

function Write-GitFailure {
    param(
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)]$Result
    )
    Write-Warning "$Context (git exit $($Result.ExitCode))"
    foreach ($line in @($Result.Output)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host "  $line" -ForegroundColor DarkGray
        }
    }
}

function Test-LocalBranch {
    param([string]$Repository, [string]$Name)
    $result = Invoke-GitCommand $Repository @(
        'show-ref', '--verify', '--quiet', "refs/heads/$Name"
    ) -SuppressError
    return ($result.ExitCode -eq 0)
}

function Get-CurrentBranch {
    param([string]$Repository)
    $result = Invoke-GitCommand $Repository @(
        'symbolic-ref', '--quiet', '--short', 'HEAD'
    ) -SuppressError
    if ($result.ExitCode -ne 0) { return $null }
    return Get-FirstOutputLine $result
}

function Get-LocalBranch {
    param([string]$Repository)
    $result = Invoke-GitCommand $Repository @(
        'for-each-ref', '--format=%(refname:short)', 'refs/heads/'
    )
    if ($result.ExitCode -ne 0) {
        Write-GitFailure 'Cannot enumerate local branches' $result
        return $null
    }
    return @($result.Output | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        } | Sort-Object -Unique)
}

function Get-WorktreeRecord {
    param([string]$Repository)
    $result = Invoke-GitCommand $Repository @('worktree', 'list', '--porcelain')
    if ($result.ExitCode -ne 0) {
        Write-GitFailure 'Cannot enumerate worktrees' $result
        return $null
    }

    $records = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($line in @($result.Output) + '') {
        if ([string]::IsNullOrEmpty($line)) {
            if ($null -ne $current) {
                $records.Add([pscustomobject]$current)
                $current = $null
            }
            continue
        }

        if ($line.StartsWith('worktree ', [System.StringComparison]::Ordinal)) {
            $current = @{
                Path     = $line.Substring(9)
                Branch   = $null
                Detached = $false
                Locked   = $false
                LockReason = ''
                Prunable = $false
            }
            continue
        }

        if ($null -eq $current) { continue }
        if ($line.StartsWith('branch refs/heads/', [System.StringComparison]::Ordinal)) {
            $current.Branch = $line.Substring(18)
        }
        elseif ($line -eq 'detached') {
            $current.Detached = $true
        }
        elseif ($line.StartsWith('locked', [System.StringComparison]::Ordinal)) {
            $current.Locked = $true
            if ($line.Length -gt 7) {
                $current.LockReason = $line.Substring(7)
            }
        }
        elseif ($line.StartsWith('prunable', [System.StringComparison]::Ordinal)) {
            $current.Prunable = $true
        }
    }
    return $records.ToArray()
}

function Find-BranchWorktree {
    param([object[]]$Worktrees, [string]$Branch)
    return @($Worktrees | Where-Object { $_.Branch -ceq $Branch }) | Select-Object -First 1
}

function Get-RefHash {
    param([string]$Repository, [string]$Ref)
    $result = Invoke-GitCommand $Repository @('rev-parse', '--verify', $Ref) -SuppressError
    if ($result.ExitCode -ne 0) { return $null }
    return Get-FirstOutputLine $result
}

function Test-Ancestor {
    param([string]$Repository, [string]$Ancestor, [string]$Descendant)
    $result = Invoke-GitCommand $Repository @(
        'merge-base', '--is-ancestor', $Ancestor, $Descendant
    ) -SuppressError
    return ($result.ExitCode -eq 0)
}

function Get-Mode {
    param([string]$Name)
    switch ($Name) {
        { [string]::IsNullOrWhiteSpace($_) } { 'current'; break }
        'all' { 'all'; break }
        'cross-all' { 'all'; break }
        'debug' { 'debug'; break }
        default { 'single' }
    }
}

function Get-UniqueBranchList {
    param([string[]]$Branches)
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($branch in $Branches) {
        if (-not [string]::IsNullOrWhiteSpace($branch) -and $set.Add($branch)) {
            $result.Add($branch)
        }
    }
    return $result.ToArray()
}

Export-ModuleMember -Function @(
    'Invoke-GitCommand',
    'Get-FirstOutputLine',
    'Write-GitFailure',
    'Test-LocalBranch',
    'Get-CurrentBranch',
    'Get-LocalBranch',
    'Get-WorktreeRecord',
    'Find-BranchWorktree',
    'Get-RefHash',
    'Test-Ancestor',
    'Get-Mode',
    'Get-UniqueBranchList'
)
