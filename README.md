# GitMergeTools

:cn: **简体中文** · [:us: English](README.en.md)

![version](https://img.shields.io/badge/version-v7.5.0-blue) [![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**安全、事务式的 Git 分支整合工具** — 三条跨平台 PowerShell 命令,带按终端能力自动降级的视觉层。

## 这是什么

GitMergeTools 提供三条命令,用于在不破坏任何数据的前提下整合本地 Git 分支:

| 命令 | 模式 | 作用 |
|------|------|------|
| `gitmerge` | **仅本地** | 事务式本地分支整合:在一次性 worktree 中完成所有合并验证,仅当全部成功后才快进真实 ref |
| `gitsync` | **含远端** | 先安全拉取各分支的 `origin/<分支>`,再做与 gitmerge 相同的本地整合,然后逐分支推送到 `origin` |
| `gitstatus` | **只读** | 增强的 status、近期提交 log,以及分支 vs `origin/<分支>` 的对比;绝不改动 ref |

**安全第一:**工具绝不强制移动或删除分支,绝不 `reset`/`rebase`,绝不 force-push。所有 ref 移动都是快进或 compare-and-swap,且在临时 worktree 验证通过后才执行;任何失败都不会改动任何东西。

**运行时要求:** PowerShell 7.x(首选)或 Windows PowerShell 5.1;git 2.x。目标支持 Windows / Linux / macOS。

## 安装与配置

把仓库 clone 到本地(或直接下载),保持以下布局:

```
GitMergeTools/
├─ gitmerge.ps1
├─ gitsync.ps1
├─ gitstatus.ps1
└─ Modules/
   └─ GitMergeTools.*.psm1
```

在 PowerShell 配置文件(`$PROFILE`)中 dot-source 三个脚本:

```powershell
# 在 $PROFILE 中（若同时使用 pwsh 7 和 5.1，两个配置文件都加）
. 'C:\path\to\GitMergeTools\gitmerge.ps1'
. 'C:\path\to\GitMergeTools\gitsync.ps1'
. 'C:\path\to\GitMergeTools\gitstatus.ps1'
```

若 `$PSScriptRoot` 无法解析（如把函数粘贴进配置文件），设环境变量覆盖:

```powershell
$env:GITMERGE_TOOLS_HOME = 'C:\path\to\GitMergeTools'
```

## 三条命令

### gitmerge — 仅本地整合

把分支整合到一个双向收敛的并集提交,**完全在本地**进行(不 fetch、不 pull、不 push)。在一次性临时 worktree 中验证所有合并;仅当全部成功后才快进真实 ref。

### gitsync — 含远端同步

与 gitmerge 的拓扑完全相同,但额外在整合前对每个涉及的 `origin/<分支>` 做安全拉取(fast-forward 或无冲突合并),整合后逐分支推送各自的 `origin/<分支>`(单 ref 普通推送;被拒即跳过,绝不 force)。

### gitstatus — 只读状态

显示工作树 status、近期提交 log(含提交链图)、以及每个分支与 `origin/<分支>` 的超前/落后对比。绝不改动任何 ref 或远端状态。

## 参数与拓扑

三条命令使用相同的参数形式:

| 参数 | 拓扑 | 说明 |
|------|------|------|
| *(空)* | **2-branch** | 当前分支 ↔ `main` 双向收敛至并集 |
| `{分支名}` | **2-branch** | 当前分支 ↔ 指定分支,双向收敛,去 main 中心 |
| `all` | **Star(星形)** | 当前分支(hub)吸收所有其它分支,每个 spoke 反向合并 hub 的原始提交 |
| `cross-all` | **Mesh(网状)** | 所有分支收敛到同一并集提交 |
| `debug` | **Dry-run** | `cross-all` 的干跑:报告计划,不改动任何东西 |

### Star(星形)vs Mesh(网状)图示

```
Star (gitmerge all):           Mesh (gitmerge cross-all):

   spoke-A                        branch-A ─┐
      ↑↓                                    ├─→ [union commit]
   [HUB] ←→ spoke-B              branch-B ─┤       ↑
      ↑↓                                    │   (all branches
   spoke-C                        branch-C ─┘  fast-forward here)

hub = 当前分支，吸收所有 spokes     所有分支收敛到同一并集
每个 spoke = original-hub ∪ spoke  冲突 → fail-fast（什么都不改）
冲突/脏 spoke → 跳过，其余继续     脏分支 → 跳过，其余继续收敛
hub 自身脏 → 中止整次运行
```

**sub-branch 跳过:** 若某目标分支有未合并的后代分支,它会被跳过并给出警告,而不是被悄悄整合。

## 使用示例

```powershell
# --- gitmerge ---

# 把当前分支与 main 双向收敛（最常用）
gitmerge

# 把当前分支与 feature/login 双向收敛
gitmerge feature/login

# 当前分支(hub)吸收所有其它分支（star 拓扑）
gitmerge all

# 所有分支收敛到同一并集（mesh 拓扑）
gitmerge cross-all

# 查看 cross-all 的计划，不做任何改动
gitmerge debug

# --- gitsync ---

# 拉取+整合+推送：当前分支与 main 双向收敛
gitsync

# 拉取+整合+推送：所有分支 star 拓扑
gitsync all

# 拉取+整合+推送：所有分支 mesh 拓扑
gitsync cross-all

# --- gitstatus ---

# 查看当前分支状态与近期 log
gitstatus

# 查看所有分支的超前/落后对比
gitstatus all
```

## 安全模型

**核心约束（不可违反）:** 工具绝不威胁或污染 git 状态或用户数据。

具体保证:

- **无 force-push / reset / rebase:** 所有推送都是普通 `git push`(单 ref),被远端拒绝时跳过,永不用 `--force`。
- **临时 worktree 验证:** 每次合并先在一次性临时 worktree 中完成;只有全部成功后才快进真实 ref。
- **快进 / Compare-and-swap:** 真实 ref 移动只做快进或 compare-and-swap `update-ref`(防并发竞态)。
- **冲突处理:**
  - `all`(star): 冲突或脏 spoke → 跳过并继续(skip-and-proceed);hub 脏 → 中止。
  - `cross-all`(mesh): 任意冲突 → fail-fast 中止,什么都不改。
  - 2-branch: 冲突 → 拒绝执行,所有 ref 保持不变。
- **从不自动解决冲突:** 有冲突一律停下并提示,让用户决定。
- **脏工作树:** 任何有未提交改动的分支都不会被合并;它会被跳过(批量模式)或触发拒绝(单分支模式)。

## 视觉层与 Summary

### 视觉档位

输出自动探测终端能力,选取能安全渲染的最高档,由高到低降级:

| 档位 | 要求 | 外观 |
|------|------|------|
| `rich` | UTF-8 输出 + Unicode 可渲染终端 | emoji + Unicode 框线 + 颜色 |
| `standard` | UTF-8 输出 | Unicode 框线,无 emoji |
| `basic` | — | 纯 ASCII,无色 |

用 `GITMERGE_VISUAL_MODE` 固定档位(`rich`/`standard`/`basic`);`auto`(默认)自动选择。

### 运行 Banner 与 Summary

每次运行显示:
- **Banner:** 版本号 + 仓库 URL + 作者,对齐方框格式
- **Summary 标题:** 版本 + `[LIVE]`(真实运行)或 `[DRY-RUN]`(debug 模式)
- **调用参数:** 本次使用的参数/拓扑
- **工作流链:** 紧凑的阶段链展示
- **Notices/Warnings:** 整合的注意事项与警告块
- **近期提交:** 带提交链图的最近 log,按档位着色/加 emoji

### 环境变量

| 变量 | 取值 | 含义 |
|------|------|------|
| `GITMERGE_VISUAL_MODE` | `auto`(默认) \| `rich` \| `standard` \| `basic` | 固定视觉档位(`max` 作为 `rich` 的兼容别名仍被接受) |
| `GITMERGE_TOOLS_SUPPRESS_WARNING` | 真值(`1`/`true`/`yes`/`on`) | 静默档位/升级提示；git 错误/警告始终输出 |
| `GITMERGE_TOOLS_HOME` | 路径 | 模块发现的安装目录覆盖 |

## 版本历史

> 当前版本: **v7.5.0**。早期 v1–v3 在引入 Git 之前,为概述性追溯;v4 起依 Git 提交历史编写。
>
> **历史精简规则:** 当前大版本列出所有子版本;往前每个大版本保留 3–6 个里程碑子版本(越旧越少);超过 5 个大版本之前的旧版本仅保留一行大版本摘要。

**v7.x — 拓扑重定义:star / mesh,去 main 中心(当前)**
- **v7.5.0** — 修复:未提交的改动**不再预先阻断**合并操作。引擎只拒绝真正不可触碰的状态(worktree 锁定 / 不可用 / 合并-变基-cherry-pick-revert 进行中);普通脏 worktree 由 `git merge --ff-only` 在 apply 时仲裁——非重叠改动快进成功(改动保留),重叠改动快进被拒绝(无任何损失)。不需要移动的分支(已在并集顶端)永不被碰触。新增 `Test-WorktreeUsable` 辅助函数。
- **v7.4.1** — 修复:`gitmerge cross-all` 在**当前分支工作树脏**时改为明确中止(提示先 commit/stash),不再静默跳过当前分支、把其余分支"收敛"成一个什么都没合并的假成功——当前分支是 cross-all 的核心,与 star 的 hub、2-branch 的当前分支处理一致。
- **v7.4** — UX 与质量:运行 Banner 显示版本、仓库 URL 和作者,对齐方框格式;三条命令统一 Summary 标题(版本 + `[LIVE]`/`[DRY-RUN]`);Summary 新增调用参数展示、紧凑工作流链、整合的 Notices/Warnings 块;近期 log 增加提交链图和按档位着色/emoji;移除已死的 through-main 引擎并抽出共享 helper。
- **v7.3** — `gitsync` 全面采用新拓扑 + **逐分支远端同步**:每种参数(2-branch / all / cross-all)= 对应的 `gitmerge` 拓扑,外加合并前安全拉取每个涉及的 `origin/<分支>`、合并后**逐分支推送**其各自的 `origin/<分支>`(单 ref 普通推送,被拒即跳过、绝不 force);取代"经 main + 一次 atomic 推送"的旧模型。不安全的 main 或星形 hub 则中止。
- **v7.2** — `gitmerge cross-all` 改为**去 main 中心的全网状(mesh)**:所有分支收敛到同一并集提交;合并冲突 → fail-fast 中止,脏 worktree 分支 → 跳过;`gitmerge debug` 改为该 mesh 的 dry-run。
- **v7.1** — `gitmerge all` 改为**当前分支星形(star)**:hub 吸收所有分支,每个 spoke 反向合并 hub 的原始提交;冲突/脏 spoke 跳过、hub 脏则中止。
- **v7.0** — `gitmerge`(空参 / `{分支}`)改为**当前分支 ↔ 目标分支双向收敛**,去 main 中心。

**v6.x — 远端同步:不止 push,还能 pull**
- **v6.8.0** — 近期提交记录由 5 条增至 10 条;`gitsync` summary 补上近期提交块。
- **v6.7.1** — 测试:补两个最危险操作的安全回归锁(gitsync `push --atomic` meta-scan + `Test-TemporaryWorktreeForCleanup` 负例)。
- **v6.7.0** — skip-and-proceed(gitsync):无法安全拉取的非 main 分支跳过、其余照常同步,绝不 force-push。
- **v6.4.1** — 安全修复:两条无 worktree 拉取路径改为对分类时捕获的 tip 做 compare-and-swap,堵住跨阶段并发竞态。
- **v6.4.0** — Stage 4:已 checkout 且工作树干净的分叉分支也可自动无冲突合并;安全同步全部落地。
- **v6.0.0** — 关键修复:不再对 origin 领先情形硬性报错;新增 REMOTE PULL 阶段分类 + `ACTION NEEDED` 提示。

**v5.x — 模块化、引擎统一与持续加固**
- **v5.5.0–v5.10.0** — 非交互 git 配置、操作进行中预检、编码/i18n 测试、模块移入 `Modules/`。
- **v5.4.0** — `max` 档并入 `rich`(`max` 保留为兼容别名);视觉档位精简为 `rich/standard/basic`。
- **v5.1.0–v5.3.1** — 抽出 `Core.psm1` + `Merge.psm1`,三命令成为同一引擎上的薄壳;移除 `gitsync → gitmerge` 耦合;git 安全加固。
- **v5.0.0** — 强制 UTF-8 捕获、非破坏性 fetch、porcelain 卫生、清理死代码。
- **v4.x** — Claude 驱动的加固 + 开源发布:无依赖测试体系、能力画像与 4 档视觉选择、Git 安全加固、双语 README + MIT 许可证 + GitHub 发布。

**v3.x — 约 3 个里程碑(Git 化 + 视觉进阶):** `rich` 档成型(emoji、Unicode 框线)、开始用 Git 做版本控制、`max` 顶档实验。

**v2.x — 三命令格局与基础视觉(概述):** 三命令格局成形(`gitmerge` + `gitsync` + `gitstatus` 雏形),加入基础视觉(阶段标题/状态行/结果摘要)。

**v1.x — 起源(概述):** 最初的单脚本 `gitmerge`,事务式临时 worktree、`--ff-only` 快进。

## 许可证

[MIT](LICENSE) © Leemax Li
