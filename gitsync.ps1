<#
.SYNOPSIS
    Transactionally consolidates local branches through main, then pushes the
    updated main and synchronized branches to origin.
.DESCRIPTION
    gitsync reuses gitmerge for the local merge/synchronization phase. Before
    local refs are changed, it verifies that origin exists and that remote
    target branches do not contain commits missing from their local branches.
    After gitmerge succeeds, it pushes main and the selected target branches
    with a single atomic ordinary push.
.PARAMETER BranchName
    Empty selects the current branch. all or cross-all selects every local
    branch, including main/master.
    debug reports the plan without changing refs, worktrees, or remotes.
    Any other value selects one local branch.
#>
function gitsync {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'This is an interactive, colorized Git command.'
    )]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Position = 0)]
        [string]$BranchName = ''
    )

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
        $ErrorActionPreference = 'Continue'
        try {
            # Decode git stdout as UTF-8 regardless of the console code page (cp936/OEM on a redirected
            # or 5.1 stdout) so non-ASCII branch names round-trip byte-exact (#1); restored in finally.
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
            if ([string]::IsNullOrEmpty($WorkingDirectory)) {
                if ($MergeError) {
                    $rawOutput = @(& git @Arguments 2>&1)
                }
                elseif ($SuppressError) {
                    $rawOutput = @(& git @Arguments 2>$null)
                }
                else {
                    $rawOutput = @(& git @Arguments)
                }
            }
            else {
                if ($MergeError) {
                    $rawOutput = @(& git -C $WorkingDirectory @Arguments 2>&1)
                }
                elseif ($SuppressError) {
                    $rawOutput = @(& git -C $WorkingDirectory @Arguments 2>$null)
                }
                else {
                    $rawOutput = @(& git -C $WorkingDirectory @Arguments)
                }
            }
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousPreference
            [Console]::OutputEncoding = $previousOutputEncoding
        }

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output   = [string[]]@($rawOutput | ForEach-Object { $_.ToString() })
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

    function Test-GitMergeToolsSuppressWarningLocal {
        $truthy = @('1', 'true', 'TRUE', 'yes', 'YES', 'on', 'ON')
        return (($env:GITMERGE_TOOLS_SUPPRESS_WARNING -in $truthy) -or ($env:GITMERGE_VISUAL_SUPPRESS_WARNING -in $truthy))
    }

    function New-OptionalGitSyncVisual {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'New-OptionalGitSyncVisual loads an optional renderer and does not change Git state.'
        )]
        param()

        $basePath = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $PSCommandPath } else { $PSScriptRoot }
        $isWindowsRuntime = ($PSVersionTable.PSEdition -eq 'Desktop' -or $PSVersionTable.Platform -eq 'Win32NT' -or $IsWindows)
        $xdgPowerShell = if (-not [string]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME)) { Join-Path $env:XDG_CONFIG_HOME 'powershell' } else { $null }
        $homeConfigPowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path $HOME '.config') 'powershell' } else { $null }
        $homeDocumentsPowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path $HOME 'Documents') 'PowerShell' } else { $null }
        $windowsDocumentsPowerShell = if ($isWindowsRuntime) { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell' } else { $null }
        $windowsOneDrivePowerShell = if ($isWindowsRuntime -and -not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path (Join-Path $HOME 'OneDrive') 'Documents') 'PowerShell' } else { $null }
        $commonCandidates = @(
            $env:GITMERGE_TOOLS_COMMON_MODULE,
            (Join-Path $basePath 'GitMergeTools.Common.psm1'),
            $(if ($xdgPowerShell) { Join-Path $xdgPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($homeConfigPowerShell) { Join-Path $homeConfigPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($homeDocumentsPowerShell) { Join-Path $homeDocumentsPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($windowsDocumentsPowerShell) { Join-Path $windowsDocumentsPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($windowsOneDrivePowerShell) { Join-Path $windowsOneDrivePowerShell 'GitMergeTools.Common.psm1' })
        )
        foreach ($candidate in $commonCandidates) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
                try {
                    Import-Module $candidate -Force -ErrorAction Stop
                    return New-GitMergeToolsVisual -CommandName 'gitsync' -ScriptRoot $PSScriptRoot -PSCommandPath $PSCommandPath
                }
                catch {
                    $suppress = (Test-GitMergeToolsSuppressWarningLocal)
                    if (-not $suppress) {
                        Write-Warning "GitMergeTools.Common.psm1 could not initialize gitsync visuals; using built-in basic output. $($_.Exception.Message)"
                        Write-Host "  Set `$env:GITMERGE_TOOLS_COMMON_MODULE to the common module path, or place GitMergeTools.Common.psm1 in the PowerShell profile directory." -ForegroundColor Yellow
                        Write-Host "  Suppress notice: `$env:GITMERGE_TOOLS_SUPPRESS_WARNING='1'" -ForegroundColor DarkGray
                    }
                    return $null
                }
            }
        }

        $fallbackSuppress = (Test-GitMergeToolsSuppressWarningLocal)
        if (-not $fallbackSuppress) {
            Write-Warning "GitMergeTools.Common.psm1 was not found; gitsync is using built-in basic output."
            Write-Host "  Set `$env:GITMERGE_TOOLS_COMMON_MODULE to the common module path, or place GitMergeTools.Common.psm1 beside the git tool scripts." -ForegroundColor Yellow
            Write-Host "  Suppress notice: `$env:GITMERGE_TOOLS_SUPPRESS_WARNING='1'" -ForegroundColor DarkGray
        }
        return $null
    }

    $visual = New-OptionalGitSyncVisual

    function Write-RunBanner {
        param([bool]$DryRun)
        if ($null -ne $visual) {
            & $visual.WriteRunBanner -DryRun:$DryRun -Name 'gitsync'
            return
        }
        $color = if ($DryRun) { 'Magenta' } else { 'Cyan' }
        Write-Host ''
        Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor $color
        if ($DryRun) {
            Write-Host '║  GITSYNC DEBUG / DRY-RUN  Preview only; refs unchanged      ║' -ForegroundColor $color
        }
        else {
            Write-Host '║  GITSYNC  Transactional merge plus remote push              ║' -ForegroundColor $color
        }
        Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor $color
    }

    function Write-Stage {
        param(
            [string]$Title,
            [string]$Subtitle,
            [string]$StageIcon,
            [ConsoleColor]$Color = [ConsoleColor]::Cyan
        )
        if ($null -ne $visual) {
            & $visual.WriteStage -Title $Title -Subtitle $Subtitle -StageIcon $StageIcon -Color $Color
            return
        }
        Write-Host ''
        Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
        Write-Host "  $Title" -ForegroundColor $Color
        if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
            Write-Host "  $Subtitle" -ForegroundColor DarkGray
        }
        Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    }

    function Write-StatusLine {
        param(
            [string]$Marker,
            [string]$Message,
            [ConsoleColor]$Color = [ConsoleColor]::Gray
        )
        if ($null -ne $visual) {
            & $visual.WriteStatusLine -Marker $Marker -Message $Message -Color $Color
            return
        }
        Write-Host ("   {0,-3} {1}" -f $Marker, $Message) -ForegroundColor $Color
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

    function Resolve-GitMergeFunction {
        if (Get-Command gitmerge -CommandType Function -ErrorAction SilentlyContinue) {
            return $true
        }

        $basePath = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $PSCommandPath } else { $PSScriptRoot }
        $scriptPath = $null
        $isWindowsRuntime = ($PSVersionTable.PSEdition -eq 'Desktop' -or $PSVersionTable.Platform -eq 'Win32NT' -or $IsWindows)
        $xdgPowerShell = if (-not [string]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME)) { Join-Path $env:XDG_CONFIG_HOME 'powershell' } else { $null }
        $homeConfigPowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path $HOME '.config') 'powershell' } else { $null }
        $homeDocumentsPowerShell = if (-not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path $HOME 'Documents') 'PowerShell' } else { $null }
        $windowsDocumentsPowerShell = if ($isWindowsRuntime) { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell' } else { $null }
        $windowsOneDrivePowerShell = if ($isWindowsRuntime -and -not [string]::IsNullOrWhiteSpace($HOME)) { Join-Path (Join-Path (Join-Path $HOME 'OneDrive') 'Documents') 'PowerShell' } else { $null }
        $commonCandidates = @(
            $env:GITMERGE_TOOLS_COMMON_MODULE,
            (Join-Path $basePath 'GitMergeTools.Common.psm1'),
            $(if ($xdgPowerShell) { Join-Path $xdgPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($homeConfigPowerShell) { Join-Path $homeConfigPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($homeDocumentsPowerShell) { Join-Path $homeDocumentsPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($windowsDocumentsPowerShell) { Join-Path $windowsDocumentsPowerShell 'GitMergeTools.Common.psm1' }),
            $(if ($windowsOneDrivePowerShell) { Join-Path $windowsOneDrivePowerShell 'GitMergeTools.Common.psm1' })
        )
        foreach ($candidate in $commonCandidates) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
                try {
                    Import-Module $candidate -Force -ErrorAction Stop
                    $scriptPath = Resolve-GitMergeToolsScript -ScriptName 'gitmerge.ps1' -ExplicitPath $env:GITMERGE_SCRIPT -ScriptRoot $PSScriptRoot -PSCommandPath $PSCommandPath
                    break
                }
                catch {
                    $suppress = (Test-GitMergeToolsSuppressWarningLocal)
                    if (-not $suppress) {
                        Write-Warning "GitMergeTools.Common.psm1 could not resolve gitmerge.ps1. $($_.Exception.Message)"
                    }
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            $scriptPath = Join-Path $basePath 'gitmerge.ps1'
        }
        if (Test-Path -LiteralPath $scriptPath) {
            . $scriptPath
        }
        return ($null -ne (Get-Command gitmerge -CommandType Function -ErrorAction SilentlyContinue))
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

    function Write-SyncSummary {
        param(
            [string]$Result,
            [string]$Mode,
            [string]$Repository,
            [string]$MainBranch,
            [string[]]$TargetBranches,
            [string[]]$PushBranches,
            [string[]]$PushedBranches,
            [string]$FailureReason,
            [timespan]$Elapsed
        )

        $resultColor = if ($Result -eq 'SUCCESS') { [ConsoleColor]::Green } elseif ($Result -eq 'SIMULATED') { [ConsoleColor]::Magenta } else { [ConsoleColor]::Red }
        Write-Host ''
        Write-Host "═══════════════════  GIT SYNC SUMMARY  ═══════════════════" -ForegroundColor $resultColor
        Write-Host ("  Result          : {0}" -f $Result) -ForegroundColor $resultColor
        Write-Host ("  Mode            : {0}" -f $Mode)
        Write-Host ("  Repository      : {0}" -f $Repository)
        Write-Host ("  Main branch     : {0}" -f $MainBranch)
        Write-Host ("  Target branches : {0}" -f @($TargetBranches).Count)
        if (@($TargetBranches).Count -gt 0) {
            Write-Host ("    Targets       : {0}" -f (@($TargetBranches) -join ', ')) -ForegroundColor DarkGray
        }
        Write-Host ("  Push branches   : {0}" -f @($PushBranches).Count)
        if (@($PushBranches).Count -gt 0) {
            Write-Host ("    Push refs     : {0}" -f (@($PushBranches) -join ', ')) -ForegroundColor DarkGray
        }
        Write-Host ("  Pushed branches : {0} / {1}" -f @($PushedBranches).Count, @($PushBranches).Count) -ForegroundColor $(if (@($PushedBranches).Count -eq @($PushBranches).Count) { 'Green' } else { 'Yellow' })
        if (@($PushedBranches).Count -gt 0) {
            Write-Host ("    Pushed        : {0}" -f (@($PushedBranches) -join ', ')) -ForegroundColor Green
        }
        Write-Host ("  Elapsed         : {0:n2}s" -f $Elapsed.TotalSeconds)
        if (-not [string]::IsNullOrWhiteSpace($FailureReason)) {
            Write-Host ("  Failure reason  : {0}" -f $FailureReason) -ForegroundColor Red
        }
        Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor $resultColor
    }

    $startedAt = Get-Date
    $syncResult = 'FAILED'
    $repository = ''
    $mainBranch = ''
    $targetBranches = @()
    $pushBranches = @()
    $pushedBranches = [System.Collections.Generic.List[string]]::new()
    $failureReason = ''

    try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $failureReason = 'Git is not installed or is not available on PATH.'
        Write-Warning $failureReason
        return $false
    }
    if (-not (Resolve-GitMergeFunction)) {
        $failureReason = 'Cannot find gitmerge. Put gitmerge.ps1 beside gitsync.ps1 or load gitmerge first.'
        Write-Warning $failureReason
        return $false
    }

    $mode = Get-Mode $BranchName
    Write-RunBanner -DryRun ($mode -eq 'debug')
    $rootResult = Invoke-GitCommand '' @('rev-parse', '--show-toplevel') -SuppressError
    if ($rootResult.ExitCode -ne 0) {
        $failureReason = 'Current directory is not inside a Git repository.'
        Write-Warning $failureReason
        return $false
    }
    $repository = Get-FirstOutputLine $rootResult

    Write-Stage -Title 'REMOTE PREFLIGHT' -Subtitle 'Verify origin and remote branch safety before local refs change' -StageIcon 'REMOTE'
    Write-StatusLine -Marker '✓' -Message "Git root: $repository" -Color Green

    $headResult = Invoke-GitCommand $repository @('rev-parse', '--verify', 'HEAD') -SuppressError
    if ($headResult.ExitCode -ne 0) {
        $failureReason = 'Repository has no commits yet. Create an initial commit before running gitsync.'
        Write-Warning $failureReason
        return $false
    }

    foreach ($candidate in @('main', 'master')) {
        if (Test-LocalBranch $repository $candidate) {
            $mainBranch = $candidate
            break
        }
    }
    if (-not $mainBranch) {
        $failureReason = "Cannot find a local 'main' or 'master' branch."
        Write-Warning $failureReason
        return $false
    }

    $remote = Invoke-GitCommand $repository @('remote', 'get-url', 'origin') -SuppressError
    if ($remote.ExitCode -ne 0) {
        $failureReason = "gitsync requires an 'origin' remote before it can change local refs."
        Write-Warning $failureReason
        return $false
    }
    Write-StatusLine -Marker '✓' -Message 'Origin remote exists.' -Color Green

    $localBranches = Get-LocalBranch $repository
    if ($null -eq $localBranches) {
        $failureReason = 'Local branches could not be enumerated.'
        Write-Warning $failureReason
        return $false
    }
    $localBranches = @($localBranches)
    $managedBranches = @($localBranches | Where-Object {
            -not $_.StartsWith('gitmerge-tmp-', [System.StringComparison]::Ordinal)
        })

    if ($mode -eq 'current') {
        $currentBranch = Get-CurrentBranch $repository
        if ([string]::IsNullOrWhiteSpace($currentBranch)) {
            $failureReason = 'Current HEAD is detached; pass an explicit local branch name, all, or cross-all.'
            Write-Warning $failureReason
            return $false
        }
        Write-StatusLine -Marker '✓' -Message "Current branch: $currentBranch" -Color Green
        if ($currentBranch -ceq $mainBranch) {
            Write-Warning "Current branch is the main branch '$mainBranch'; gitsync will push main only."
            $targetBranches = @()
        }
        else {
            $targetBranches = @($currentBranch)
        }
    }
    elseif ($mode -eq 'single') {
        if ($BranchName -ceq $mainBranch) {
            Write-Warning "Selected branch is the main branch '$mainBranch'; gitsync will push main only."
            $targetBranches = @()
        }
        elseif (Test-LocalBranch $repository $BranchName) {
            $targetBranches = @($BranchName)
        }
        else {
            $failureReason = "Local branch '$BranchName' does not exist."
            Write-Warning $failureReason
            return $false
        }
    }
    else {
        $targetBranches = @($managedBranches)
    }
    # Unmerged-descendant ("sub-branch") guard (#10): mirror gitmerge's engine skip so gitsync never
    # pushes — nor reports as "synced" — a target the merge engine deliberately skips (its descendant's
    # work was never consolidated into main). gitmerge still emits the detailed warning during the merge.
    if (@($targetBranches).Count -gt 0) {
        $targetSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($t in $targetBranches) { [void]$targetSet.Add($t) }
        $keptTargets = [System.Collections.Generic.List[string]]::new()
        foreach ($target in $targetBranches) {
            $descendants = @($managedBranches | Where-Object {
                    $_ -cne $target -and $_ -cne $mainBranch -and -not $targetSet.Contains($_) -and
                    (Test-Ancestor -Repository $repository -Ancestor "refs/heads/$target" -Descendant "refs/heads/$_")
                })
            if ($descendants.Count -gt 0) {
                Write-StatusLine -Marker '✗' -Message "Skipping '$target': unmerged descendant branch(es): $($descendants -join ', '). It will not be consolidated or pushed; merge them back into '$target' (or select them too / use 'all') to include its work." -Color Yellow
            }
            else {
                $keptTargets.Add($target)
            }
        }
        $targetBranches = @($keptTargets.ToArray())
    }
    $pushBranches = Get-UniqueBranchList (@($mainBranch) + @($targetBranches))
    $skipLocalMerge = (($mode -eq 'single' -and $BranchName -ceq $mainBranch) -or ($mode -eq 'current' -and @($targetBranches).Count -eq 0))

    if ($mode -eq 'debug') {
        Write-StatusLine -Marker '◇' -Message 'Would fetch origin and verify remote branch ancestry before any local merge.' -Color Magenta
        Write-StatusLine -Marker '◇' -Message $(if ($skipLocalMerge) { "Would skip local merge because '$mainBranch' was selected directly." } else { 'Would run gitmerge for the selected local merge scope.' }) -Color Magenta
        Write-Stage -Title 'PUSH REMOTE' -Subtitle '[DRY-RUN] Would push main and synchronized branches to origin' -StageIcon 'PUSH' -Color Magenta
        Write-StatusLine -Marker '◇' -Message "Would push: $($pushBranches -join ', ')" -Color Magenta
        $syncResult = 'SIMULATED'
        return $true
    }

    $fetch = Invoke-GitCommand $repository @('-c', 'fetch.prune=false', '-c', 'fetch.pruneTags=false', 'fetch', 'origin') -MergeError
    if ($fetch.ExitCode -ne 0) {
        Write-GitFailure 'Fetch from origin failed' $fetch
        $failureReason = 'Fetch from origin failed.'
        return $false
    }
    Write-StatusLine -Marker '✓' -Message 'Fetched origin before local merge.' -Color Green

    $localMainRef = "refs/heads/$mainBranch"
    $remoteMainRef = "refs/remotes/origin/$mainBranch"
    if ((Get-RefHash $repository $remoteMainRef) -and
        -not (Test-Ancestor -Repository $repository -Ancestor $localMainRef -Descendant $remoteMainRef) -and
        -not (Test-Ancestor -Repository $repository -Ancestor $remoteMainRef -Descendant $localMainRef)) {
        $failureReason = "Local '$mainBranch' and origin/$mainBranch have diverged."
        Write-Warning $failureReason
        return $false
    }

    foreach ($branch in $targetBranches) {
        $localRef = "refs/heads/$branch"
        $remoteRef = "refs/remotes/origin/$branch"
        if ((Get-RefHash $repository $remoteRef) -and
            -not (Test-Ancestor -Repository $repository -Ancestor $remoteRef -Descendant $localRef)) {
            $failureReason = "origin/$branch has commits that are not present in local '$branch'."
            Write-Warning "$failureReason Merge or review that remote branch manually, then retry."
            return $false
        }
    }
    Write-StatusLine -Marker '✓' -Message "Remote branch preflight passed for: $($pushBranches -join ', ')" -Color Green

    if ($skipLocalMerge) {
        Write-StatusLine -Marker '✓' -Message "Selected '$mainBranch'; no local merge phase is required before push." -Color Green
    }
    else {
        $mergeResult = if ([string]::IsNullOrEmpty($BranchName)) {
            gitmerge
        }
        else {
            gitmerge $BranchName
        }
        $mergeOk = [bool](@($mergeResult | Where-Object { $_ -is [bool] }) | Select-Object -Last 1)
        if (-not $mergeOk) {
            $failureReason = 'Local gitmerge phase failed; nothing was pushed.'
            Write-Warning $failureReason
            return $false
        }
    }

    Write-Stage -Title 'PUSH REMOTE' -Subtitle 'Push main and synchronized local branches to origin with one atomic update' -StageIcon 'PUSH'
    $refspecs = @($pushBranches | ForEach-Object { "refs/heads/$($_):refs/heads/$($_)" })
    $push = Invoke-GitCommand $repository (@('push', '--atomic', 'origin') + $refspecs) -MergeError
    if ($push.ExitCode -ne 0) {
        Write-GitFailure 'Remote push failed; inspect the remote rejection and retry after reconciling it' $push
        $failureReason = 'Remote push failed.'
        return $false
    }
    foreach ($branch in $pushBranches) {
        $pushedBranches.Add($branch)
        Write-StatusLine -Marker '✓' -Message "Pushed '$branch' to origin/$branch." -Color Green
    }
    # The push above is the irreversible, authoritative result — mark SUCCESS now so a failure of the
    # best-effort remote-tracking refresh below can never misreport a completed push as FAILED (#2).
    $syncResult = 'SUCCESS'

    # Refresh remote-tracking refs (best-effort, non-destructive: never prune local tags/refs as a side
    # effect of a sync). A failure here is a warning, not a failure of the already-completed push.
    $refresh = Invoke-GitCommand $repository @('-c', 'fetch.prune=false', '-c', 'fetch.pruneTags=false', 'fetch', 'origin') -MergeError
    if ($refresh.ExitCode -ne 0) {
        Write-Warning 'Remote-tracking refresh after push failed; the push already succeeded. Run "git fetch origin" later to refresh.'
    }
    else {
        Write-StatusLine -Marker '✓' -Message 'Remote-tracking refs refreshed.' -Color Green
    }
    Write-Host 'gitsync finished.' -ForegroundColor Green
    return $true
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($repository)) {
            Write-SyncSummary -Result $syncResult -Mode $mode -Repository $repository -MainBranch $mainBranch -TargetBranches $targetBranches -PushBranches $pushBranches -PushedBranches $pushedBranches.ToArray() -FailureReason $failureReason -Elapsed ((Get-Date) - $startedAt)
        }
    }
}
