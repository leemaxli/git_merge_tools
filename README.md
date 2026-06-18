# GitMergeTools

:cn: **简体中文** · [:us: English](README.en.md)

**当前版本 v6.5.0** · 见下方[版本历史](#版本历史)

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

功能完整、测试充分(已知缺陷全部修复;两运行时 97 项测试全绿)。**结构性重构主体已完成**:已抽出
`Core.psm1`(git 原语)与 `Merge.psm1`(事务引擎),三条命令成为同一引擎上的薄壳并去除了命令间耦合;
后续的环境模块合并与 git 安全加固按路线图推进中。

## 版本历史

> 当前版本:**v6.5.0**。早期 v1–v3 在引入 Git 之前,为概述性追溯;v4 起依 Git 提交历史编写。

**v6.x —— 远端同步:不止 push,还能 pull(当前)**
- **v6.5.0** —— `gitsync` / `gitstatus` 的运行 summary 现在会显示**远端位置**(origin URL),而不仅是本地仓库路径——让你看清在和哪儿同步/对比。
- **v6.4.1** —— 安全修复(由对 v6.x 代码的对抗式审查发现):两条无 worktree 的 pull 路径现在对**分类时捕获**的分支 tip 做 compare-and-swap(经新的 `Move-BranchRefSafely`,带真正的 fast-forward 守护),而非重新读取的 tip。这堵住了一个跨阶段竞态:在两阶段之间被**并发**写入推进的分支可能被横向强移(丢弃新提交)或合并到陈旧树上。已 checkout 的路径本就安全(实时 `git merge` 会重新校验)。
- **v6.4.0** —— Stage 4(已 checkout):分叉无冲突自动合并现在也覆盖**已 checkout 且工作树干净**的分支(最常见情形——你的*当前*分支与 origin 分叉),在同样的 `merge-tree` 内存验证后用 `merge --no-edit` 应用。工作树脏或合并有冲突仍提示。至此安全同步全部落地:`gitsync` 会自动 pull/merge 所有不冒险丢失你工作的情形(fast-forward 与无冲突合并),其余(工作树脏、冲突分叉)则提示——绝不 reset、rebase 或 force-push。
- **v6.3.0** —— Stage 4(未 checkout 分支):对**未 checkout** 且已与 origin 分叉的分支,`gitsync` 在**合并无冲突**时自动**合并** —— 用 `git merge-tree` 在内存中验证(不碰 worktree、不动 ref),再用 `commit-tree` + compare-and-swap `update-ref` 无 worktree 地应用。有冲突的分叉绝不自动解决,仍提示。
- **v6.2.0** —— Stage 3:对**已 checkout 且工作树干净**的领先分支,`gitsync` 也会自动 fast-forward 拉取(在该 worktree 内 `merge --ff-only`)—— 覆盖"当前分支落后于 origin"这一最常见情形。工作树脏则绝不触碰,仍然提示。
- **v6.1.0** —— Stage 2:当 origin 领先的分支**未在任何 worktree 被 checkout** 时,`gitsync` 现在会自动 fast-forward 拉取它(compare-and-swap `update-ref` —— 最安全的 pull,没有工作树需要扰动)。REMOTE PULL 阶段 all-or-nothing:先对所有分支只读分类,只要还有任一分支无法安全同步(已 checkout 的 fast-forward,或已分叉),就不改动任何东西并提示。
- **v6.0.0** —— 关键缺失修复:`gitsync` 不再在 `origin` 领先于(或分叉于)本地分支时硬性报错。新增 **REMOTE PULL 阶段**,对每个将同步的分支分类(`UpToDate`/`LocalAhead`/`FastForwardable`/`Diverged`),需要 pull 时以可操作的 **`ACTION NEEDED`** 提示(如 `git pull --ff-only origin <分支>`)停下 —— 且不改动任何东西 —— 取代晦涩的失败。这是分阶段推出的 Stage 1;安全的**自动 pull**(先 fast-forward,再用临时 worktree 验证的干净合并)将随后续 v6.x 子版本到来。`gitmerge` 不变。

**v5.x —— 模块化、引擎统一与持续加固**(已精简;逐版本细节见 Git 提交历史)
- **v5.5.0–v5.10.0** —— 瘦身 + git 安全一波:模块移入 `Modules/` 子文件夹;非交互、长路径安全的 git 配置(`GIT_TERMINAL_PROMPT=0`、`GIT_EDITOR=true`、`core.longpaths`、关闭 `rerere`);操作进行中预检(拒绝处于 merge/rebase/cherry-pick/revert 中的 worktree);三命令统一给出升级建议;编码/国际化路径测试;`gitsync` 严格按引擎已同步集合推送。
- **v5.4.0** —— 反过度设计:把 `max` 顶档并入 `rich` 并删除(`max` 保留为兼容别名);视觉档位精简为 `rich/standard/basic`。
- **v5.1.0–v5.3.1** —— 模块化与加固:抽出 `Core.psm1`(git 原语)+ `Merge.psm1`(事务引擎),三命令成为同一引擎上的薄壳(**移除 `gitsync → gitmerge` 调用**);开启 git 安全加固(中和 `GIT_DIR`/定位变量);修复升级建议。
- **v5.0.0** —— 潜伏缺陷清扫:强制 UTF-8 捕获 git 输出(非 ASCII 分支名)、非破坏性 fetch、`gitstatus` porcelain 卫生、按显示宽度截断;裁掉过度设计、清理死代码。

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
