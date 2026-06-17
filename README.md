# GitMergeTools

Cross-platform PowerShell helpers for **safe, transactional** local Git branch consolidation —
with an auto-degrading, capability-aware visual layer. Runs on **PowerShell 7+** (preferred) and
**Windows PowerShell 5.1**, on Windows / Linux / macOS.

> **Core guarantee:** these tools never force-move or delete your branches, never `reset`/`rebase`,
> and only ever push with `git push --atomic`. Main advances only after *every* requested merge
> succeeds in a throwaway worktree; on any failure nothing is changed. If a working tree is dirty or
> a merge conflicts, the operation refuses and leaves all refs untouched.

## Commands

| Command | What it does |
|---------|--------------|
| `gitmerge` | Transactionally consolidates local branches through `main`/`master`: merges the selected branch(es) into a temporary worktree, and only after all merges succeed fast-forwards the real `main`, then fast-forwards the selected branches to it. |
| `gitsync` | Verifies the remote is safe, runs the same local consolidation, then pushes `main` + the synchronized branches to `origin` with a single `git push --atomic`. |
| `gitstatus` | Read-only enhanced status, recent log, and branch-vs-main / branch-vs-origin comparison. Never changes refs. |

**Argument forms** (same for all three):

- *(empty)* — the current branch
- `all` / `cross-all` — every local branch (incl. `main`/`master`)
- `debug` — dry-run: report the plan without changing refs, worktrees, or remotes
- *any other value* — that one local branch

A target branch that has an **unmerged descendant** branch (a "sub-branch" with work not yet merged
back) is **skipped with a warning** rather than silently consolidated.

## Install

Put all the `*.ps1` and `GitMergeTools.*.psm1` files in one folder, then dot-source the three
commands from your PowerShell profile (do this in **both** the PowerShell 7 and Windows PowerShell 5.1
profile roots if you use both):

```powershell
# in $PROFILE
. 'C:\path\to\GitMergeTools\gitmerge.ps1'
. 'C:\path\to\GitMergeTools\gitsync.ps1'
. 'C:\path\to\GitMergeTools\gitstatus.ps1'
```

If the commands are loaded in a way where `$PSScriptRoot` can't resolve (e.g. pasted directly into a
profile), set `GITMERGE_TOOLS_HOME` to the install folder.

## Visual tiers

Output auto-detects the terminal's capabilities and picks the richest tier that renders safely,
degrading high → low. Machine-relevant output (exit codes, git errors) is always independent of the tier.

| Tier | Requires | Look |
|------|----------|------|
| `max` | truecolor + VT + UTF-8 output, interactive (not redirected/CI), `NO_COLOR` unset | top tier (truecolor effects) |
| `rich` | UTF-8 output + a Unicode-capable terminal | emoji + Unicode box-drawing + color |
| `standard` | UTF-8 output | Unicode box-drawing, no emoji |
| `basic` | — | pure ASCII, no color |

## Environment variables

| Var | Values | Meaning |
|-----|--------|---------|
| `GITMERGE_VISUAL_MODE` | `auto` (default) `\| max \| rich \| standard \| basic` | Pin a visual tier; still capability-checked (a pinned tier that can't render degrades). |
| `GITMERGE_TOOLS_SUPPRESS_WARNING` | truthy (`1`/`true`/`yes`/`on`) | Silence tier/upgrade notices. Git errors/warnings always surface. |
| `GITMERGE_TOOLS_HOME` | path | Install-folder override for module discovery. |

When you pin a tier the environment can't reach, the end-of-run summary explains how to reach it
(unless suppressed).

## Tests

Dependency-free — no Pester required. Tests run in throwaway Git repos under the OS temp dir with a
hermetic Git environment and a path-containment guard, on both runtimes:

```powershell
pwsh tests/Invoke-CrossRuntime.ps1     # runs the suite under pwsh 7 and Windows PowerShell 5.1
pwsh tests/Invoke-GitMergeToolsTests.ps1   # current runtime only
```

## Status

Functional and fully tested (all known defects fixed; suite green on both runtimes). A structural
refactor (extracting shared helpers into modules, removing cross-command coupling) is in progress.

## License

[MIT](LICENSE).
