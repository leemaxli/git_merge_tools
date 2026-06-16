# `gitmerge.ps1` 视觉增强方案

> **目标**：在不改变脚本核心逻辑的前提下，通过扩展色彩体系、丰富图标语言、增加动态反馈等手段，提升终端输出的视觉层次感与可读性。
>
> **原则**：增量式改动，所有增强为可选附加，不影响现有功能。

---

## 一、当前视觉元素盘点

| 位置 | 函数 | 元素 | 评价 |
|------|------|------|------|
| L82-95 | `Write-RunBanner` | `╔══╗` / `╚══╝` 双线框 + 单色 | ✅ 结构清晰，❌ 颜色单调（仅 Cyan/Magenta 二选一） |
| L97-110 | `Write-Stage` | `───` 单线分隔 + 标题/副标题 | ✅ 层级分明，❌ 缺少图标多样性 |
| L112-119 | `Write-StatusLine` | `✓ → ◇ ✗ ↺` 状态标记 | ✅ 语义明确，❌ 标记数量有限 |
| L121-132 | `Write-SuccessBanner` | `██` 实心块横幅 | ✅ 视觉冲击力强，❌ 仅成功态有此待遇 |
| L134-208 | `Write-RunSummary` | 表格化总结 + git log 展示 | ✅ 信息密度高，❌ 缺少颜色梯度和图标点缀 |
| L69-80 | `Write-GitFailure` | `Write-Warning` + 灰色输出 | ✅ 错误突出，❌ 可增加图标/边框强化 |

---

## 二、增强方案（共 11 项）

### 2.1 扩展调色板 — 统一的色彩语义

**当前问题**：颜色值（`Cyan`、`Green`、`DarkGray` 等）散落在各处，缺乏统一的语义管理。

**改进方案**：在函数体顶部定义颜色主题哈希表，所有视觉函数引用主题键名而非硬编码颜色。

```powershell
# 在 gitmerge 函数体内，Write-RunBanner 之前添加
$ColorTheme = @{
    Banner          = 'Cyan'
    BannerDry       = 'Magenta'
    Stage           = 'Cyan'
    StageDry        = 'Magenta'
    Success         = 'Green'
    Warning         = 'Yellow'
    Error           = 'Red'
    Info            = 'DarkGray'
    Highlight       = 'White'
    Branch          = 'DarkYellow'
    Hash            = 'DarkCyan'
    Stats           = 'DarkMagenta'
    Timestamp       = 'DarkGray'
    Divider         = 'DarkGray'
    Progress        = 'Blue'
    MainBranch      = 'Green'
    TargetBranch    = 'Yellow'
    FailedBranch    = 'Red'
}
```

**改动影响**：约 15 处 `-ForegroundColor` 参数需替换为 `$ColorTheme.xxx`。

---

### 2.2 增强 `Write-RunBanner` — ASCII Art Git Logo + 双色标题框

**当前代码**（L82-95）：
```powershell
function Write-RunBanner {
    param([bool]$DryRun)
    $color = if ($DryRun) { 'Magenta' } else { 'Cyan' }
    Write-Host ''
    Write-Host '╔══════════════════════════════════════════════════════════════╗' -ForegroundColor $color
    if ($DryRun) {
        Write-Host '║  DEBUG / DRY-RUN  Transaction preview, no refs will change   ║' -ForegroundColor $color
    }
    else {
        Write-Host '║  GITMERGE  Transactional cross-merge and synchronization     ║' -ForegroundColor $color
    }
    Write-Host '╚══════════════════════════════════════════════════════════════╝' -ForegroundColor $color
    Write-Host ''
}
```

**改进版本**：

```powershell
function Write-RunBanner {
    param([bool]$DryRun)

    $frameColor  = if ($DryRun) { $ColorTheme.BannerDry }  else { $ColorTheme.Banner }
    $accentColor = if ($DryRun) { 'DarkMagenta' }          else { 'DarkCyan' }

    Write-Host ''

    # ASCII Art GIT Logo（使用 ANSI 艺术字风格）
    Write-Host '         ██████╗ ██╗████████╗' -ForegroundColor $frameColor
    Write-Host '        ██╔════╝ ██║╚══██╔══╝' -ForegroundColor $frameColor
    Write-Host '        ██║  ███╗██║   ██║   ' -ForegroundColor $frameColor
    Write-Host '        ██║   ██║██║   ██║   ' -ForegroundColor $frameColor
    Write-Host '        ╚██████╔╝██║   ██║   ' -ForegroundColor $frameColor
    Write-Host '         ╚═════╝ ╚═╝   ╚═╝   ' -ForegroundColor $frameColor
    Write-Host ''

    # 标题框
    Write-Host '╔════════════════════════════════════════════════════╗' -ForegroundColor $frameColor
    Write-Host '║                                                  ║' -ForegroundColor $frameColor
    if ($DryRun) {
        Write-Host '║  🔬 DRY-RUN — 事务预览，不改变任何引用               ║' -ForegroundColor $frameColor
    } else {
        Write-Host '║  🔀 GITMERGE — 事务性交叉合并与分支同步              ║' -ForegroundColor $frameColor
    }
    Write-Host '║                                                  ║' -ForegroundColor $frameColor
    Write-Host '╚════════════════════════════════════════════════════╝' -ForegroundColor $frameColor
    Write-Host ''
}
```

**视觉效果对比**：
```
【改造前】                          【改造后】
╔══════════════════════╗                  ██████╗ ██╗████████╗
║  GITMERGE  ...       ║                 ██╔════╝ ██║╚══██╔══╝
╚══════════════════════╝                 ██║  ███╗██║   ██║
                                         ██║   ██║██║   ██║
                                         ╚██████╔╝██║   ██║
                                          ╚═════╝ ╚═╝   ╚═╝

                                        ╔════════════════════════════╗
                                        ║  🔀 GITMERGE — 事务性...   ║
                                        ╚════════════════════════════╝
```

---

### 2.3 增强 `Write-Stage` — 阶段卡片式设计

**当前代码**（L97-110）：
```powershell
function Write-Stage {
    param(
        [string]$Title,
        [string]$Subtitle,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )
    Write-Host ''
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor $Color
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-Host "  $Subtitle" -ForegroundColor DarkGray
    }
    Write-Host '──────────────────────────────────────────────────────────────' -ForegroundColor DarkGray
}
```

**改进版本**：

```powershell
function Write-Stage {
    param(
        [string]$Title,
        [string]$Subtitle,
        [string]$StageIcon,          # 新增：阶段专属图标
        [ConsoleColor]$Color = 'Cyan'
    )
    Write-Host ''

    # 左右对称装饰线 + 中心图标
    $decoration = '━' * 8
    Write-Host "  $decoration  $StageIcon  $Title  $decoration" -ForegroundColor $Color

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-Host "    $Subtitle" -ForegroundColor $ColorTheme.Info
    }

    # 底部细线
    Write-Host '  ' + ('─' * 62) -ForegroundColor $ColorTheme.Divider
}
```

**各阶段图标映射表**：

| 阶段 | 图标 | 语义 | 调用行 |
|------|------|------|--------|
| PREFLIGHT | `🔍` | 检查/搜索 | ~507 |
| REMOTE SYNC | `☁️` | 云端同步 | ~609 |
| TEMPORARY INTEGRATION | `🧪` | 实验/暂存 | ~630 |
| PUBLISH MAIN | `🚀` | 发布/推进 | ~681 |
| SYNCHRONIZE BRANCHES | `🔄` | 循环同步 | ~706 |
| CLEANUP | `🧹` | 清理 | ~731 |

**调用方改动示例**：
```powershell
# 原调用
Write-Stage -Title '🔍  PREFLIGHT' -Subtitle 'Resolve repository, branches, and affected worktrees'

# 新调用
Write-Stage -Title 'PREFLIGHT' -Subtitle 'Resolve repository, branches, and affected worktrees' -StageIcon '🔍'
```

> **注意**：原 `$Title` 中内嵌的 emoji 建议移除，统一由 `-StageIcon` 参数管理。

---

### 2.4 增强 `Write-StatusLine` — 富状态指示器

**当前代码**（L112-119）：
```powershell
function Write-StatusLine {
    param(
        [string]$Marker,
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host ("   {0,-3} {1}" -f $Marker, $Message) -ForegroundColor $Color
}
```

**改进版本**：

```powershell
function Write-StatusLine {
    param(
        [string]$Marker,
        [string]$Message,
        [ConsoleColor]$Color = 'Gray'
    )

    # 标记 → 颜色映射表
    $markerColorMap = @{
        '✓'   = $ColorTheme.Success
        '✔'   = $ColorTheme.Success
        '→'   = 'Cyan'
        '◇'   = 'Magenta'
        '✗'   = $ColorTheme.Error
        '✘'   = $ColorTheme.Error
        '↺'   = $ColorTheme.Info
        '⚡'   = $ColorTheme.Warning
        '🎯'  = $ColorTheme.Highlight
        '📌'  = 'DarkCyan'
        '💡'  = 'DarkYellow'
        '⏱'   = $ColorTheme.Info
        '🔗'  = 'DarkCyan'
        '📦'  = 'Magenta'
        '⬆'   = 'Green'
        '⬇'   = 'Yellow'
    }

    $markerColor = if ($markerColorMap.ContainsKey($Marker)) {
        $markerColorMap[$Marker]
    } else {
        $Color
    }

    # 标记带方括号高亮
    Write-Host '  ' -NoNewline
    Write-Host ("[{0}]" -f $Marker) -ForegroundColor $markerColor -NoNewline
    Write-Host " $Message" -ForegroundColor $Color
}
```

**视觉对比**：
```
【改造前】                      【改造后】
   ✓   Git root: /repo            [✓] Git root: /repo       ← 标记为绿色
   →   Targets (3): a, b, c       [→] Targets (3): a, b, c  ← 标记为青色
   ✗   Could not synchronize      [✗] Could not synchronize ← 标记为红色
```

---

### 2.5 新增 — 实时迷你进度条 `Write-MiniProgress`

**用途**：在合并循环和同步循环中展示进度，给予用户实时反馈。

```powershell
function Write-MiniProgress {
    param(
        [Parameter(Mandatory)]
        [int]$Current,

        [Parameter(Mandatory)]
        [int]$Total,

        [string]$Label = 'Processing',

        [ConsoleColor]$Color = 'Cyan'
    )

    if ($Total -eq 0) { return }

    $barWidth = 20
    $filled   = [math]::Floor(($Current / $Total) * $barWidth)
    $empty    = $barWidth - $filled
    $bar      = ('█' * $filled) + ('░' * $empty)
    $pct      = '{0,3:P0}' -f ($Current / $Total)

    Write-Host '  ⏳ ' -NoNewline -ForegroundColor $ColorTheme.Info
    Write-Host $Label.PadRight(16) -NoNewline -ForegroundColor $ColorTheme.Info
    Write-Host " [$bar]" -NoNewline -ForegroundColor $Color
    Write-Host " $Current/$Total $pct" -ForegroundColor $ColorTheme.Info
}
```

**调用示例**（在合并循环 L642-664 中插入）：
```powershell
$mergeIndex = 0
foreach ($branch in $targetBranches) {
    $mergeIndex++
    Write-MiniProgress -Current $mergeIndex -Total $targetBranches.Count `
        -Label 'Merging' -Color 'Yellow'

    Write-Host "── Merge [$branch] → [$mainBranch] (staged) ──" -ForegroundColor Yellow
    # ... 原有合并逻辑 ...
}
```

**视觉效果**：
```
  ⏳ Merging         [████████░░░░░░░░░░░░] 2/5 40%
  ⏳ Synchronizing   [████████████████░░░░] 4/5 80%
```

---

### 2.6 新增 — 分支关系可视化树 `Write-BranchTree`

**用途**：在 Preflight 阶段展示分支拓扑，帮助用户直观理解将要合并的分支结构。

```powershell
function Write-BranchTree {
    param(
        [Parameter(Mandatory)]
        [string]$MainBranch,

        [Parameter(Mandatory)]
        [string[]]$TargetBranches
    )

    Write-Host ''
    Write-Host '  📂 分支拓扑预览:' -ForegroundColor $ColorTheme.Highlight

    # Main 分支（根节点）
    Write-Host '  ┌─ ' -NoNewline -ForegroundColor 'DarkGray'
    Write-Host "🏠 $MainBranch" -ForegroundColor $ColorTheme.MainBranch -NoNewline
    Write-Host ' (主分支)' -ForegroundColor $ColorTheme.Info

    # 目标分支（叶节点）
    for ($i = 0; $i -lt $TargetBranches.Count; $i++) {
        $prefix = if ($i -eq $TargetBranches.Count - 1) { '  └─ ' } else { '  ├─ ' }
        $branchColor = if ($i % 2 -eq 0) { $ColorTheme.TargetBranch } else { 'DarkYellow' }
        Write-Host $prefix -NoNewline -ForegroundColor 'DarkGray'
        Write-Host "🌿 $($TargetBranches[$i])" -ForegroundColor $branchColor
    }
    Write-Host ''
}
```

**调用位置**：在 Preflight 阶段（~L562）`Write-StatusLine` 打印目标分支列表之后插入：
```powershell
Write-BranchTree -MainBranch $mainBranch -TargetBranches $targetBranches
```

**视觉效果**：
```
  📂 分支拓扑预览:
  ┌─ 🏠 main (主分支)
  ├─ 🌿 feature/login
  ├─ 🌿 feature/payment
  └─ 🌿 fix/crash-on-null
```

---

### 2.7 增强 `Write-SuccessBanner` — 庆祝式动画效果

**当前代码**（L121-132）：
```powershell
function Write-SuccessBanner {
    param([string]$MainBranch, [int]$TargetCount, [string]$MainPublished)
    Write-Host ''
    Write-Host '██████████████████████████████████████████████████████████████' -ForegroundColor Green
    if ($TargetCount -eq 0 -or $MainPublished -eq 'NOT REQUIRED') {
        Write-Host '██  SUCCESS  Repository is current; nothing to merge          ██' -ForegroundColor Green
    }
    else {
        Write-Host ("██  SUCCESS  {0} published; {1} branch(es) synchronized" -f $MainBranch, $TargetCount) -ForegroundColor Green
    }
    Write-Host '██████████████████████████████████████████████████████████████' -ForegroundColor Green
}
```

**改进版本**：

```powershell
function Write-SuccessBanner {
    param(
        [string]$MainBranch,
        [int]$TargetCount,
        [string]$MainPublished
    )

    Write-Host ''

    if ($TargetCount -eq 0 -or $MainPublished -eq 'NOT REQUIRED') {
        # 无操作场景：简洁确认
        Write-Host '  ╭' + ('─' * 46) + '╮' -ForegroundColor $ColorTheme.Success
        Write-Host '  │  ✅  仓库已是最新状态，无需合并' + (' ' * 16) + '│' -ForegroundColor $ColorTheme.Success
        Write-Host '  ╰' + ('─' * 46) + '╯' -ForegroundColor $ColorTheme.Success
    } else {
        # 成功场景：庆祝横幅
        Write-Host '  ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨' -ForegroundColor $ColorTheme.Warning
        Write-Host '  ╔' + ('═' * 46) + '╗' -ForegroundColor $ColorTheme.Success
        Write-Host '  ║  ✅  SUCCESS' + (' ' * 31) + '║' -ForegroundColor $ColorTheme.Success
        Write-Host '  ║' + (' ' * 48) + '║' -ForegroundColor $ColorTheme.Success
        Write-Host ("  ║      📌 {0} 已发布" -f $MainBranch).PadRight(49) + '║' -ForegroundColor $ColorTheme.Success
        Write-Host ("  ║      🌿 {0} 个分支已同步" -f $TargetCount).PadRight(49) + '║' -ForegroundColor $ColorTheme.Success
        Write-Host '  ║' + (' ' * 48) + '║' -ForegroundColor $ColorTheme.Success
        Write-Host '  ╚' + ('═' * 46) + '╝' -ForegroundColor $ColorTheme.Success
        Write-Host '  ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨' -ForegroundColor $ColorTheme.Warning
    }

    Write-Host ''
}
```

**视觉效果**：
```
【无操作时】                          【成功时】
  ╭──────────────────────────────────────────────╮    ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨
  │  ✅  仓库已是最新状态，无需合并                │    ╔══════════════════════════════╗
  ╰──────────────────────────────────────────────╯    ║  ✅  SUCCESS                 ║
                                                      ║                              ║
                                                      ║      📌 main 已发布           ║
                                                      ║      🌿 3 个分支已同步        ║
                                                      ║                              ║
                                                      ╚══════════════════════════════╝
                                                      ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨ ✨
```

---

### 2.8 增强 `Write-RunSummary` — 彩色表格化

**当前代码**（L134-208）：散列式键值对输出，全部使用 `Write-Host` 逐行打印。

**改进版本**：

```powershell
function Write-RunSummary {
    param([Parameter(Mandatory)]$State)

    # 根据结果选择主题
    $theme = switch ($State.Result) {
        'SUCCESS'   { @{ Border = $ColorTheme.Success; Accent = 'DarkGreen'  } }
        'SIMULATED' { @{ Border = 'Magenta';           Accent = 'DarkMagenta' } }
        default     { @{ Border = $ColorTheme.Error;   Accent = 'DarkRed'    } }
    }

    $modeTag = if ($State.DryRun) { '[DRY-RUN] 🔬' } else { '[LIVE] ⚡' }
    $targetCount       = @($State.TargetBranches).Count
    $integratedCount   = @($State.IntegratedBranches).Count
    $synchronizedCount = @($State.SynchronizedBranches).Count
    $failedCount       = @($State.FailedBranches).Count

    # 成功时先显示庆祝横幅
    if ($State.Result -eq 'SUCCESS') {
        Write-SuccessBanner -MainBranch $State.MainBranch `
            -TargetCount $targetCount -MainPublished $State.MainPublished
    }

    Write-Host ''
    Write-Host ('  ' + ('═' * 58)) -ForegroundColor $theme.Border
    Write-Host ('  ║  📊 GIT MERGE SUMMARY  {0,-29}  ║' -f $modeTag) -ForegroundColor $theme.Border
    Write-Host ('  ' + ('─' * 58)) -ForegroundColor $theme.Accent

    # 表格行定义：标签、值、颜色
    $rows = @(
        @{ L = '🏷  结果'        ; V = $State.Result                ; C = $theme.Border },
        @{ L = '📂 仓库'        ; V = $State.Repository            ; C = $ColorTheme.Info },
        @{ L = '🏠 主分支'      ; V = $State.MainBranch            ; C = $ColorTheme.MainBranch },
        @{ L = '📐 模式'        ; V = $State.Mode                  ; C = $ColorTheme.Info },
        @{ L = '🌲 工作树数量'  ; V = $State.WorktreeCount         ; C = $ColorTheme.Info },
        @{ L = '🌿 本地分支数'  ; V = $State.LocalBranchCount      ; C = $ColorTheme.Info },
        @{ L = '🎯 目标分支数'  ; V = $targetCount                 ; C = 'Cyan' }
    )

    # 动态行（条件着色）
    $rows += @{
        L = '✅ 已集成'
        V = "$integratedCount / $targetCount"
        C = if ($integratedCount -eq $targetCount) { $ColorTheme.Success } else { $ColorTheme.Warning }
    }
    $rows += @{
        L = '🔄 已同步'
        V = "$synchronizedCount / $targetCount"
        C = if ($synchronizedCount -eq $targetCount) { $ColorTheme.Success } else { $ColorTheme.Warning }
    }
    $rows += @{
        L = '❌ 失败'
        V = $failedCount
        C = if ($failedCount -eq 0) { $ColorTheme.Info } else { $ColorTheme.Error }
    }
    $rows += @{
        L = '📡 主分支发布'
        V = $State.MainPublished
        C = if ($State.MainPublished -eq 'YES') { $ColorTheme.Success } else { $ColorTheme.Info }
    }
    $rows += @{
        L = '🧹 清理状态'
        V = $State.CleanupStatus
        C = if ($State.CleanupStatus -eq 'CLEAN') { $ColorTheme.Success } else { $ColorTheme.Error }
    }
    $rows += @{
        L = '⏱  耗时'
        V = '{0:n2}s' -f $State.Elapsed.TotalSeconds
        C = $ColorTheme.Info
    }

    # 渲染表格
    foreach ($row in $rows) {
        Write-Host ('  ║  {0,-20} : ' -f $row.L) -NoNewline -ForegroundColor $ColorTheme.Info
        Write-Host ('{0,-25}' -f $row.V) -ForegroundColor $row.C -NoNewline
        Write-Host ' ║' -ForegroundColor $theme.Border
    }

    # 失败原因行（条件显示）
    if (-not [string]::IsNullOrWhiteSpace($State.FailureReason)) {
        Write-Host ('  ║  {0,-20} : ' -f '💥 失败原因') -NoNewline -ForegroundColor $ColorTheme.Info
        Write-Host ('{0,-25}' -f $State.FailureReason) -ForegroundColor $ColorTheme.Error -NoNewline
        Write-Host ' ║' -ForegroundColor $theme.Border
    }

    # 冲突分支（条件显示）
    if (-not [string]::IsNullOrWhiteSpace($State.ConflictBranch)) {
        Write-Host ('  ║  {0,-20} : ' -f '⚔  冲突分支') -NoNewline -ForegroundColor $ColorTheme.Info
        Write-Host ('{0,-25}' -f $State.ConflictBranch) -ForegroundColor $ColorTheme.Error -NoNewline
        Write-Host ' ║' -ForegroundColor $theme.Border
    }

    Write-Host ('  ' + ('═' * 58)) -ForegroundColor $theme.Border

    # Recent commits（保留原有逻辑）
    if (-not $State.DryRun -and -not [string]::IsNullOrWhiteSpace($State.Repository) -and -not [string]::IsNullOrWhiteSpace($State.MainBranch)) {
        $recent = Invoke-GitCommand $State.Repository @('log', '--oneline', '-5', $State.MainBranch)
        if ($recent.ExitCode -eq 0 -and @($recent.Output).Count -gt 0) {
            Write-Host ''
            Write-Host '── Recent commits on ' -NoNewline -ForegroundColor $ColorTheme.Info
            Write-Host $State.MainBranch -ForegroundColor $ColorTheme.MainBranch -NoNewline
            Write-Host ' ──' -ForegroundColor $ColorTheme.Info
            foreach ($line in @($recent.Output)) {
                Write-Host "   📜 $line" -ForegroundColor $ColorTheme.Info
            }
        }
    }

    Write-Host ''
    Write-Host ('═' * 60) -ForegroundColor $theme.Border

    # 结果状态行
    switch ($State.Result) {
        'SUCCESS'   { Write-Host '✅ gitmerge finished.' -ForegroundColor $ColorTheme.Success }
        'SIMULATED' { Write-Host '🔬 gitmerge dry-run finished; no changes were made.' -ForegroundColor 'Magenta' }
        default     { Write-Host '❌ gitmerge stopped before full completion.' -ForegroundColor $ColorTheme.Error }
    }
}
```

**视觉效果**：
```
  ══════════════════════════════════════════════════════════════
  ║  📊 GIT MERGE SUMMARY  [LIVE] ⚡                          ║
  ──────────────────────────────────────────────────────────────
  ║  🏷  结果              : SUCCESS                          ║
  ║  📂 仓库              : /home/user/repo                  ║
  ║  🏠 主分支            : main                             ║
  ║  📐 模式              : all                              ║
  ║  🌲 工作树数量        : 3                                ║
  ║  🌿 本地分支数        : 5                                ║
  ║  🎯 目标分支数        : 5                                ║
  ║  ✅ 已集成            : 5 / 5                            ║  ← 绿色
  ║  🔄 已同步            : 5 / 5                            ║  ← 绿色
  ║  ❌ 失败              : 0                                ║
  ║  📡 主分支发布        : YES                              ║  ← 绿色
  ║  🧹 清理状态          : CLEAN                            ║  ← 绿色
  ║  ⏱  耗时              : 2.35s                            ║
  ══════════════════════════════════════════════════════════════
```

---

### 2.9 新增 — 阶段耗时徽章 `Write-StageElapsed`

**用途**：在每个阶段完成后打印耗时，颜色根据耗时长短变化（绿 < 1s / 黄 1~5s / 红 > 5s）。

```powershell
function Write-StageElapsed {
    param(
        [Parameter(Mandatory)]
        [string]$StageName,

        [Parameter(Mandatory)]
        [timespan]$Elapsed
    )

    $color = if ($Elapsed.TotalSeconds -lt 1) {
        $ColorTheme.Success
    } elseif ($Elapsed.TotalSeconds -lt 5) {
        $ColorTheme.Warning
    } else {
        $ColorTheme.Error
    }

    Write-Host ('  ⏱  {0} 耗时: {1:n1}s' -f $StageName, $Elapsed.TotalSeconds) -ForegroundColor $color
}
```

**调用方式**（在每个阶段开始前记录时间戳，结束后调用）：

```powershell
# Preflight 阶段示例
$stageStart = Get-Date
# ... Preflight 逻辑 ...
Write-StageElapsed -StageName 'Preflight' -Elapsed ((Get-Date) - $stageStart)
```

---

### 2.10 新增 — Nerd Font 可选增强

**用途**：通过环境变量 `$env:GITMERGE_NERDFONT=1` 启用 Nerd Font 专用图标，为安装了 Nerd Font 的终端（如 Windows Terminal + Cascadia Code NF）提供更精致的图标。

```powershell
# 在函数体顶部添加（在 $ColorTheme 定义之后）
$UseNerdFont = ($env:GITMERGE_NERDFONT -eq '1')

$Icons = if ($UseNerdFont) {
    @{
        Git     = "`u{E702}"   #  nf-dev-git
        Branch  = "`u{F418}"   #  nf-oct-git_branch
        Merge   = "`u{F419}"   #  nf-oct-git_merge
        Check   = "`u{F42E}"   #  nf-oct-check_circle
        Cross   = "`u{F42C}"   #  nf-oct-x_circle
        Sync    = "`u{F447}"   #  nf-oct-sync
        Rocket  = "`u{F475}"   #  nf-oct-rocket
        Trash   = "`u{F4AE}"   #  nf-oct-trash
        Warning = "`u{F4A3}"   #  nf-oct-alert
        Cloud   = "`u{F40F}"   #  nf-oct-cloud_upload
        Beaker  = "`u{F499}"   #  nf-oct-beaker
        Search  = "`u{F42D}"   #  nf-oct-search
    }
} else {
    @{
        Git     = '[git]'
        Branch  = '🌿'
        Merge   = '🔀'
        Check   = '✅'
        Cross   = '❌'
        Sync    = '🔄'
        Rocket  = '🚀'
        Trash   = '🧹'
        Warning = '⚠️'
        Cloud   = '☁️'
        Beaker  = '🧪'
        Search  = '🔍'
    }
}
```

**使用方式**：在各视觉函数中用 `$Icons.Check` 替代硬编码的 `✅`，实现一键切换图标集。

---

### 2.11 新增 — 失败/警告高亮卡片 `Write-ErrorCard`

**用途**：当出现合并冲突或失败时，用红色边框包裹错误详情，替代当前 `Write-Warning` 的简单输出。

```powershell
function Write-ErrorCard {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Detail
    )

    Write-Host ''
    Write-Host '  ┌' + ('─' * 58) + '┐' -ForegroundColor $ColorTheme.Error
    Write-Host ('  │  ❌ {0}' -f $Title).PadRight(61) + '│' -ForegroundColor $ColorTheme.Error

    if ($Detail) {
        # 自动换行处理长文本
        $maxDetailWidth = 54
        $detailLines = @()
        $remaining = $Detail
        while ($remaining.Length -gt $maxDetailWidth) {
            $detailLines += $remaining.Substring(0, $maxDetailWidth)
            $remaining = $remaining.Substring($maxDetailWidth)
        }
        if ($remaining.Length -gt 0) { $detailLines += $remaining }

        foreach ($line in $detailLines) {
            Write-Host ('  │     {0}' -f $line).PadRight(61) + '│' -ForegroundColor $ColorTheme.Info
        }
    }

    Write-Host '  └' + ('─' * 58) + '┘' -ForegroundColor $ColorTheme.Error
    Write-Host ''
}
```

**调用场景**：
- `Write-GitFailure` 调用后追加卡片展示
- 合并冲突时展示冲突分支信息
- Preflight 失败时展示具体原因

---

## 三、完整调用点改造映射表

| 行号 | 原调用 | 改造后调用 | 改动类型 |
|------|--------|-----------|----------|
| ~84 | `$color = if ($DryRun) { 'Magenta' } else { 'Cyan' }` | `$frameColor = if ($DryRun) { $ColorTheme.BannerDry } else { $ColorTheme.Banner }` | 引用调色板 |
| ~86-93 | 原 `Write-Host` 标题框 | ASCII Art Logo + 双色框 | 函数体替换 |
| ~98 | `[ConsoleColor]$Color = [ConsoleColor]::Cyan` | 添加 `[string]$StageIcon` 参数 | 签名扩展 |
| ~103-109 | 原分隔线 + 标题输出 | 左右对称装饰线 + 图标 | 函数体替换 |
| ~113 | `[ConsoleColor]$Color = [ConsoleColor]::Gray` | 添加标记颜色映射表 | 函数体扩展 |
| ~118 | `Write-Host ("   {0,-3} {1}" -f ...)` | 方括号标记格式 | 格式替换 |
| ~121-132 | `Write-SuccessBanner` | 双场景（无操作/成功）差异化横幅 | 函数体重写 |
| ~134-208 | `Write-RunSummary` | 主题色边框 + 图标表格 + 条件行 | 函数体重写 |
| ~507 | `Write-Stage -Title '🔍  PREFLIGHT' ...` | `Write-Stage -Title 'PREFLIGHT' -StageIcon $Icons.Search ...` | 添加 `-StageIcon` |
| ~509 | 在 Preflight 完成后 | `Write-BranchTree` 调用 | 新增调用 |
| ~562 后 | 目标分支列表输出后 | `Write-BranchTree` 调用 | 新增调用 |
| ~609 | `Write-Stage -Title '🌐  REMOTE SYNC' ...` | `Write-Stage -Title 'REMOTE SYNC' -StageIcon $Icons.Cloud ...` | 添加 `-StageIcon` |
| ~630 | `Write-Stage -Title '🔀  TEMPORARY INTEGRATION' ...` | `Write-Stage -Title 'TEMPORARY INTEGRATION' -StageIcon $Icons.Beaker ...` | 添加 `-StageIcon` |
| ~642 前 | 合并循环开始 | `$mergeIndex = 0` 初始化 + `Write-MiniProgress` | 新增进度条 |
| ~643 | 合并循环内 | `$mergeIndex++; Write-MiniProgress` | 新增进度条 |
| ~681 | `Write-Stage -Title '📌  PUBLISH MAIN' ...` | `Write-Stage -Title 'PUBLISH MAIN' -StageIcon $Icons.Rocket ...` | 添加 `-StageIcon` |
| ~706 | `Write-Stage -Title '🔄  SYNCHRONIZE BRANCHES' ...` | `Write-Stage -Title 'SYNCHRONIZE BRANCHES' -StageIcon $Icons.Sync ...` | 添加 `-StageIcon` |
| ~708 前 | 同步循环开始 | `$syncIndex = 0` 初始化 + `Write-MiniProgress` | 新增进度条 |
| ~709 | 同步循环内 | `$syncIndex++; Write-MiniProgress` | 新增进度条 |
| ~731 | `Write-Stage -Title '🧹  CLEANUP' ...` | `Write-Stage -Title 'CLEANUP' -StageIcon $Icons.Trash ...` | 添加 `-StageIcon` |
| 各 `Write-GitFailure` | 错误输出 | 追加 `Write-ErrorCard` | 新增调用 |
| 各阶段结束 | — | 添加 `Write-StageElapsed` | 新增调用 |

---

## 四、优先级实施路线图

| 优先级 | 编号 | 改进项 | 预估工作量 | 影响范围 |
|--------|------|--------|-----------|----------|
| 🔴 P0 | 2.1 | 统一调色板 | 15 min | 全局一致性，为后续所有改动铺路 |
| 🔴 P0 | 2.3 | 阶段图标多样化 | 15 min | 视觉层次提升最明显 |
| 🟡 P1 | 2.4 | 富状态标记扩展 | 20 min | 信息密度和可读性提升 |
| 🟡 P1 | 2.6 | 分支树可视化 | 25 min | 功能性与美观兼备 |
| 🟡 P1 | 2.7 | 庆祝动画效果 | 10 min | 成功反馈更愉悦 |
| 🟢 P2 | 2.2 | ASCII Art Logo | 10 min | 品牌辨识度提升 |
| 🟢 P2 | 2.5 | 迷你进度条 | 20 min | 长任务实时反馈 |
| 🟢 P2 | 2.8 | 彩色表格化 Summary | 30 min | 收尾阶段出彩 |
| 🔵 P3 | 2.9 | 阶段耗时徽章 | 10 min | 性能可观测性 |
| 🔵 P3 | 2.10 | Nerd Font 适配 | 15 min | 高端终端体验 |
| 🔵 P3 | 2.11 | 错误卡片 | 10 min | 错误信息更醒目 |

> **建议实施节奏**：先完成 P0+P1（约 1.5 小时），即可获得显著的视觉提升。

---

## 五、兼容性注意事项

| 项目 | 说明 |
|------|------|
| **终端检测** | `$host.UI.RawUI` 可判断是否支持 VT100 转义序列；Windows 10 1903+ 和 Windows Terminal 原生支持完整 Unicode |
| **编码** | 脚本需保存为 **UTF-8 with BOM**，确保 emoji 在 PowerShell 5.1 中正常显示 |
| **降级策略** | 当终端不支持完整 Unicode 时，通过 `$Icons` 哈希表自动回退到纯 ASCII 标记（如 `[OK]` / `[FAIL]` / `[*]`） |
| **颜色总数** | `[ConsoleColor]` 枚举仅 16 色，避免过度依赖颜色区分信息（应结合图标、位置、粗细共同传达语义） |
| **性能** | `Write-Host` 在高频循环中会影响性能；进度条更新建议每 100ms 最多刷新一次 |
| **后退兼容** | 所有改动均为**增量式**——新增函数、扩展参数；不删除现有函数签名中的任何参数；如需回退，删除新增函数和参数即可 |
| **PowerShell 版本** | 所有语法兼容 PowerShell 5.1+ 和 PowerShell 7+ |
| **非交互式环境** | 当 `$host.UI.RawUI` 不可用（如 CI/CD 管道）时，建议通过检测自动降级为纯文本输出 |

---

## 六、快速验收清单

实施完成后，按以下场景验证视觉效果：

- [ ] **正常合并**：`gitmerge all` → 检查 ASCII Logo、阶段图标、进度条、Summary 表格、成功横幅
- [ ] **空仓库**：无目标分支时 → 检查 "无需合并" 横幅
- [ ] **Dry-run**：`gitmerge debug` → 检查 Magenta 主题 + 模拟标记
- [ ] **单分支**：`gitmerge feature/xxx` → 检查分支树仅显示一个叶子节点
- [ ] **冲突场景**：故意制造冲突 → 检查红色错误卡片 + 冲突分支高亮
- [ ] **Nerd Font**：`$env:GITMERGE_NERDFONT=1; gitmerge debug` → 检查专用图标
- [ ] **非交互终端**：`powershell -NonInteractive -Command gitmerge debug` → 检查不崩溃、输出可读
- [ ] **PowerShell 5.1**：在传统 conhost 中测试 → 确保 Emoji 正常渲染

---

> 📅 文档版本：v1.0
> 📝 适用范围：`gitmerge.ps1` (当前版本，L1-L756)
> 👤 作者：AI-assisted analysis
