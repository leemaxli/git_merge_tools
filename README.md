# GitMergeTools

:cn: **简体中文** · [:us: English](README.en.md)

**当前版本 v6.4.0** · 见下方[版本历史](#版本历史)

跨平台 PowerShell 工具,用于**安全、事务式**地在本地把 Git 分支经 main 整合,并带一套按终端能力
自动降级的视觉层。可运行于 **PowerShell 7+**(优先)与 **Windows PowerShell 5.1**,支持
Windows / Linux / macOS。

> **核心保证:** 这些工具绝不强制移动或删除你的分支,绝不 `reset`/`rebase`,推送只用
> `git push --atomic`。只有当**每一个**被请求的合并都在临时 worktree 中成功后,`main` 才会推进;
> 任何失败都不会改动任何东西。若工作树有未提交改动、或合并产生冲突,操作会拒绝执行并保持所有 ref 不变。

## 命令

| 命令 | 作用 |
|------|------|
| `gitmerge` | 事务式地把本地分支经 `main`/`master` 整合:把选定分支合并进一个临时 worktree,只有全部合并成功后,才把真正的 `main` 快进,再把选定分支快进到它。 |
| `gitsync` | 先校验远端安全,再做同样的本地整合,然后用单条 `git push --atomic` 把 `main` 和已同步分支推到 `origin`。 |
| `gitstatus` | 只读的增强 status、近期 log,以及"分支 vs main / 分支 vs origin"的对比。绝不改动 ref。 |

**参数形式**(三个命令通用):

- *(空)* —— 当前分支
- `all` / `cross-all` —— 所有本地分支(含 `main`/`master`)
- `debug` —— 干跑:只报告计划,不改动 ref、worktree 或远端
- *其它任意值* —— 指定的那一个本地分支

如果某个目标分支带有**未合并的后代分支**(一个尚未合并回来的「子分支」),它会被**跳过并给出警告**,
而不是被悄悄整合。

**远端领先(v6.0 新增):** 当 `origin/<分支>` 领先于(或已与)你的本地分支分叉时,`gitsync` 现在会以
可操作的 **`ACTION NEEDED`** 提示你先 pull —— 而不是给出晦涩的错误 —— 且不改动任何东西。安全的**自动
pull**(先 fast-forward,再临时-worktree 验证的干净合并)正随 v6.x 逐步推出。

## 安装

把三个命令脚本(`gitmerge.ps1`、`gitsync.ps1`、`gitstatus.ps1`)放在安装文件夹顶层,旁边保留装着
`GitMergeTools.*.psm1` 模块的 `Modules/` 子文件夹(即本仓库自身的布局):

```
GitMergeTools/
├─ gitmerge.ps1
├─ gitsync.ps1
├─ gitstatus.ps1
└─ Modules/
   └─ GitMergeTools.*.psm1
```

然后在 PowerShell 配置文件里 dot-source 这三个命令(如果 PowerShell 7 和 Windows PowerShell 5.1
都用,就在两个配置文件根目录都加):

```powershell
# 在 $PROFILE 中
. 'C:\path\to\GitMergeTools\gitmerge.ps1'
. 'C:\path\to\GitMergeTools\gitsync.ps1'
. 'C:\path\to\GitMergeTools\gitstatus.ps1'
```

加载器会先在 `Modules/` 子文件夹里找模块,同时仍兼容扁平布局(全部放在同一文件夹)。如果加载方式
导致 `$PSScriptRoot` 无法解析(例如把函数直接粘贴进配置文件),把 `GITMERGE_TOOLS_HOME` 设为安装目录。

## 视觉档位

输出会自动探测终端能力,选取能安全渲染的最高档,由高到低降级。与机器相关的输出(退出码、git 错误)
始终与档位无关。

| 档位 | 要求 | 外观 |
|------|------|------|
| `rich` | UTF-8 输出 + Unicode 可渲染终端 | 最高档:emoji + Unicode 框线 + 颜色 |
| `standard` | UTF-8 输出 | Unicode 框线,无 emoji |
| `basic` | —— | 纯 ASCII,无色 |

## 环境变量

| 变量 | 取值 | 含义 |
|------|------|------|
| `GITMERGE_VISUAL_MODE` | `auto`(默认) `\| rich \| standard \| basic` | 固定视觉档位;仍做能力校验(达不到的档位会降级)。(`max` 作为 `rich` 的兼容别名仍被接受。) |
| `GITMERGE_TOOLS_SUPPRESS_WARNING` | 真值(`1`/`true`/`yes`/`on`) | 静默档位/升级提示。git 错误/警告始终输出。 |
| `GITMERGE_TOOLS_HOME` | 路径 | 模块发现的安装目录覆盖。 |

当你固定了一个当前环境达不到的档位,结束 summary 会说明如何达到它(除非已静默)。

## 测试

无依赖 —— 不需要 Pester。测试在 OS 临时目录下的一次性 Git 仓库里运行,带密封的 Git 环境和路径
containment 守护,两个运行时都跑:

```powershell
pwsh tests/Invoke-CrossRuntime.ps1         # 在 pwsh 7 和 Windows PowerShell 5.1 下各跑一遍
pwsh tests/Invoke-GitMergeToolsTests.ps1   # 仅当前运行时
```

## 状态

功能完整、测试充分(已知缺陷全部修复;两运行时 91 项测试全绿)。**结构性重构主体已完成**:已抽出
`Core.psm1`(git 原语)与 `Merge.psm1`(事务引擎),三条命令成为同一引擎上的薄壳并去除了命令间耦合;
后续的环境模块合并与 git 安全加固按路线图推进中。

## 版本历史

> 当前版本:**v6.4.0**。早期 v1–v3 在引入 Git 之前,为概述性追溯;v4 起依 Git 提交历史编写。

**v6.x —— 远端同步:不止 push,还能 pull(当前)**
- **v6.4.0** —— Stage 4(已 checkout):分叉无冲突自动合并现在也覆盖**已 checkout 且工作树干净**的分支(最常见情形——你的*当前*分支与 origin 分叉),在同样的 `merge-tree` 内存验证后用 `merge --no-edit` 应用。工作树脏或合并有冲突仍提示。至此安全同步全部落地:`gitsync` 会自动 pull/merge 所有不冒险丢失你工作的情形(fast-forward 与无冲突合并),其余(工作树脏、冲突分叉)则提示——绝不 reset、rebase 或 force-push。
- **v6.3.0** —— Stage 4(未 checkout 分支):对**未 checkout** 且已与 origin 分叉的分支,`gitsync` 在**合并无冲突**时自动**合并** —— 用 `git merge-tree` 在内存中验证(不碰 worktree、不动 ref),再用 `commit-tree` + compare-and-swap `update-ref` 无 worktree 地应用。有冲突的分叉绝不自动解决,仍提示。
- **v6.2.0** —— Stage 3:对**已 checkout 且工作树干净**的领先分支,`gitsync` 也会自动 fast-forward 拉取(在该 worktree 内 `merge --ff-only`)—— 覆盖"当前分支落后于 origin"这一最常见情形。工作树脏则绝不触碰,仍然提示。
- **v6.1.0** —— Stage 2:当 origin 领先的分支**未在任何 worktree 被 checkout** 时,`gitsync` 现在会自动 fast-forward 拉取它(compare-and-swap `update-ref` —— 最安全的 pull,没有工作树需要扰动)。REMOTE PULL 阶段 all-or-nothing:先对所有分支只读分类,只要还有任一分支无法安全同步(已 checkout 的 fast-forward,或已分叉),就不改动任何东西并提示。
- **v6.0.0** —— 关键缺失修复:`gitsync` 不再在 `origin` 领先于(或分叉于)本地分支时硬性报错。新增 **REMOTE PULL 阶段**,对每个将同步的分支分类(`UpToDate`/`LocalAhead`/`FastForwardable`/`Diverged`),需要 pull 时以可操作的 **`ACTION NEEDED`** 提示(如 `git pull --ff-only origin <分支>`)停下 —— 且不改动任何东西 —— 取代晦涩的失败。这是分阶段推出的 Stage 1;安全的**自动 pull**(先 fast-forward,再用临时 worktree 验证的干净合并)将随后续 v6.x 子版本到来。`gitmerge` 不变。

**v5.x —— 模块化、引擎统一与持续加固**
- **v5.10.0** —— git 安全/去重:`gitsync` 现在严格按合并引擎报告的已同步集合推送(引擎是 #10 子分支跳过的唯一真源),而非独立重算的集合 —— 消除推送/跳过分歧风险。移除了引擎上已失效的 `-RemoteAlreadyFetched` 参数。行为等价,由既有 gitsync 测试守护。
- **v5.9.0** —— 编码/国际化测试覆盖:新增回归测试,证明工具能在路径含空格或非 ASCII(中日韩)字符的仓库上整合与读取 —— 二者在 cp936/GBK 的 Windows 开发环境中都很常见。
- **v5.8.0** —— 一致性打磨:`gitsync` 与 `gitstatus` 现在和 `gitmerge` 一样在运行结束时给出视觉档位升级建议(除非你固定了当前环境无法渲染的档位且未静默,否则保持沉默)。
- **v5.7.0** —— git 安全预检:整合引擎现在会在受影响的 worktree 处于操作进行中(合并/变基/拣选/回退)时提前拒绝,并指明具体操作,而非笼统报告"有未提交改动"。标记经 `git rev-parse --git-path` 按 worktree 解析,对链接 worktree 同样正确。
- **v5.6.0** —— git 安全加固:经统一 `Invoke-GitCommand` 的每次 git 调用现都运行于非交互、长路径安全的配置下 —— `GIT_TERMINAL_PROMPT=0`(凭据提示时快速失败而非挂起)、`GIT_EDITOR=true`(绝不弹出编辑器)、`-c core.longpaths=true`(Windows 长路径安全)、`-c rerere.enabled=false`(已记录的冲突解决绝不会悄悄自动解决我们的一次性集成合并)。两个环境变量捕获后恢复,无全局副作用。
- **v5.5.0** —— 仓库整理:入口命令(`gitmerge`/`gitsync`/`gitstatus`)留在顶层,所有 `GitMergeTools.*.psm1` 模块移入 `Modules/` 子文件夹(PowerShell 约定)。加载器优先查找 `Modules/`,同时仍兼容扁平布局,既有安装不受影响。
- **v5.4.0** —— 架构瘦身(反过度设计):**把 `max` 顶档并入 `rich` 并删除该档**(原 `max` 只是 rich 的重打标签,truecolor/OSC 效果作为镀金砍掉);`GITMERGE_VISUAL_MODE=max` 保留为 `rich` 的兼容别名。视觉档位精简为 `rich/standard/basic`。
- **v5.3.1** —— 修复升级建议:当环境已达最优(`max` + PowerShell 7)时**不再弹出任何升级建议**;建议仅在**显式固定的档位未达成**时出现,且指出**具体缺失的能力项**(原先以 `rich` 为基准,在更高的 `max` 档下误报为"未启用 rich")。
- **v5.3.0** —— git 安全加固开篇:在统一的 `Invoke-GitCommand` 里**中和继承的 `GIT_DIR`/`GIT_WORK_TREE`/…** 定位变量(捕获后清空、用后恢复),防止泄漏的环境变量把 git 指向错误仓库、绕过路径 containment 守护。
- **v5.2.0** —— 抽出 `Merge.psm1` 事务引擎;`gitmerge`/`gitsync` 成为同一引擎上的薄壳,**移除 `gitsync → gitmerge` 调用**。
- **v5.1.0** —— 抽出 `Core.psm1`(git 原语唯一真源),三命令共用;为合并引擎补全特征化测试网。
- **v5.0.0** —— 潜伏缺陷清扫:强制 UTF-8 捕获 git 输出(非 ASCII 分支名)、`gitmerge` 非破坏性 fetch、`gitsync` 遵守子分支跳过、`gitstatus` 不把 stderr 混入 porcelain、按显示宽度的横幅截断;并裁掉过度设计、清理死代码。

**v4.x —— Claude 强化与开源发布**
- **v4.3.0** —— 公开发布:双语 README(中文默认)、MIT 许可证、路线图;发布到 GitHub。
- **v4.2.0** —— Git 安全加固:全限定 ref(防同名 tag/remote 遮蔽)、`merge --abort` 守护、`gitsync` 结果顺序与非破坏性 fetch、未合并后代分支跳过。
- **v4.1.0** —— 视觉/运行时:修 rich 崩溃、终端能力探测、`standard` UTF-8 门槛、静默真值解析;引入能力画像、4 档 `max/rich/standard/basic` 选择与升级建议。
- **v4.0.0** —— 无依赖测试体系:沙箱化一次性仓库、路径 containment 守护、跨运行时驱动与特征化测试。

**v3.x —— 视觉进阶与 Git 化(早期追溯)**
- **v3.2** —— `max` 顶档实验(truecolor / 终端转义效果探索)。
- **v3.1** —— `rich` 档成型:emoji、Unicode 框线、分阶段彩色输出。
- **v3.0** —— 开始用 Git 做版本控制;视觉层从纯文本走向分档渲染。

**v2.x —— 三命令与基础视觉(追溯)**
- **v2.2** —— 基础视觉:阶段标题、状态行、结果摘要。
- **v2.1** —— `gitstatus` 雏形(只读增强 status)。
- **v2.0** —— 在 `gitmerge` 外新增 `gitsync` 与 `gitpush`(原子推送,后并入 `gitsync`)。

**v1.x —— 起源(追溯,Git 之前)**
- **v1.1** —— 事务式临时 worktree 集成、`--ff-only` 推进。
- **v1.0** —— 最初的 `gitmerge`:把本地分支经 `main` 整合的单一脚本。

## 许可证

[MIT](LICENSE)。
