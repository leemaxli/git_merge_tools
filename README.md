# GitMergeTools

:cn: **简体中文** · [:us: English](README.en.md)

**当前版本 v5.3.1** · 见下方[版本历史](#版本历史)

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

## 安装

把所有 `*.ps1` 和 `GitMergeTools.*.psm1` 放在同一个文件夹,然后在 PowerShell 配置文件里 dot-source
这三个命令(如果 PowerShell 7 和 Windows PowerShell 5.1 都用,就在两个配置文件根目录都加):

```powershell
# 在 $PROFILE 中
. 'C:\path\to\GitMergeTools\gitmerge.ps1'
. 'C:\path\to\GitMergeTools\gitsync.ps1'
. 'C:\path\to\GitMergeTools\gitstatus.ps1'
```

如果加载方式导致 `$PSScriptRoot` 无法解析(例如把函数直接粘贴进配置文件),把 `GITMERGE_TOOLS_HOME`
设为安装目录。

## 视觉档位

输出会自动探测终端能力,选取能安全渲染的最高档,由高到低降级。与机器相关的输出(退出码、git 错误)
始终与档位无关。

| 档位 | 要求 | 外观 |
|------|------|------|
| `max` | truecolor + VT + UTF-8 输出,交互式(非重定向/CI),未设 `NO_COLOR` | 顶档(truecolor 效果) |
| `rich` | UTF-8 输出 + Unicode 可渲染终端 | emoji + Unicode 框线 + 颜色 |
| `standard` | UTF-8 输出 | Unicode 框线,无 emoji |
| `basic` | —— | 纯 ASCII,无色 |

## 环境变量

| 变量 | 取值 | 含义 |
|------|------|------|
| `GITMERGE_VISUAL_MODE` | `auto`(默认) `\| max \| rich \| standard \| basic` | 固定视觉档位;仍做能力校验(达不到的档位会降级)。 |
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

功能完整、测试充分(已知缺陷全部修复;两运行时 57 项测试全绿)。**结构性重构主体已完成**:已抽出
`Core.psm1`(git 原语)与 `Merge.psm1`(事务引擎),三条命令成为同一引擎上的薄壳并去除了命令间耦合;
后续的环境模块合并与 git 安全加固按路线图推进中。

## 版本历史

> 当前版本:**v5.3.1**。早期 v1–v3 在引入 Git 之前,为概述性追溯;v4 起依 Git 提交历史编写。

**v5.x —— 模块化、引擎统一与持续加固(当前)**
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
