# GitMergeTools

[English](README.md) · **简体中文**

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

功能完整、测试充分(已知缺陷全部修复;两运行时测试全绿)。结构性重构(把共享 helper 抽成模块、
去掉命令间耦合)进行中。

## 许可证

[MIT](LICENSE)。
