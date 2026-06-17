# GitMergeTools

[:cn: 简体中文](README.md) · :us: **English**

**Current version v5.2.0** · see [Version history](#version-history) below

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
pwsh tests/Invoke-CrossRuntime.ps1         # runs the suite under pwsh 7 and Windows PowerShell 5.1
pwsh tests/Invoke-GitMergeToolsTests.ps1   # current runtime only
```

## Status

Functional and fully tested (all known defects fixed; 57-test suite green on both runtimes). **The
core of the structural refactor is done**: `Core.psm1` (git primitives) and `Merge.psm1` (the
transactional engine) are extracted, the three commands are thin peers on one engine with no
cross-command coupling; the remaining environment-module merge and git-safety hardening are in progress.

## Version history

> Current version: **v5.2.0**. Early v1–v3 predate Git tracking and are a summarized retrospective;
> from v4 on, the history follows the Git commit log.

**v5.x — Modularization & engine unification (current)**
- **v5.2.0** — Extracted the `Merge.psm1` transactional engine; `gitmerge`/`gitsync` became thin peers on one engine, **removing the `gitsync → gitmerge` call**.
- **v5.1.0** — Extracted `Core.psm1` (single source of truth for git primitives), consumed by all three commands; added a characterization test net for the merge engine.
- **v5.0.0** — Latent-bug sweep: force UTF-8 capture of git output (non-ASCII branch names), non-destructive `gitmerge` fetch, `gitsync` honoring the sub-branch skip, `gitstatus` not folding stderr into porcelain, display-width-aware banner truncation; plus over-engineering descoped and dead code removed.

**v4.x — Claude-driven hardening & open-source release**
- **v4.3.0** — Public release: bilingual README (Chinese default), MIT license, roadmap; published to GitHub.
- **v4.2.0** — Git-safety hardening: fully-qualified refs (no tag/remote shadowing), `merge --abort` guard, `gitsync` result ordering & non-destructive fetch, unmerged-descendant skip.
- **v4.1.0** — Visual/runtime: fixed the rich crash, terminal-capability detection, the `standard` UTF-8 gate, truthy suppress parsing; added the capability profile, 4-tier `max/rich/standard/basic` selection, and the upgrade advisory.
- **v4.0.0** — Dependency-free test system: hermetic throwaway repos, a path-containment guard, a cross-runtime driver, and characterization tests.

**v3.x — Visual progression & Git adoption (early retrospective)**
- **v3.2** — `max` top-tier experiments (truecolor / terminal-escape effects).
- **v3.1** — The `rich` tier took shape: emoji, Unicode box-drawing, per-stage colored output.
- **v3.0** — Began using Git for version control; the visual layer evolved from plain text toward tiered rendering.

**v2.x — Three commands & basic visuals (retrospective)**
- **v2.2** — Basic visual style: stage headers, status lines, a result summary.
- **v2.1** — First `gitstatus` (read-only enhanced status).
- **v2.0** — Added `gitsync` and `gitpush` alongside `gitmerge` (atomic push; later folded into `gitsync`).

**v1.x — Genesis (retrospective, pre-Git)**
- **v1.1** — Transactional temporary-worktree integration; `--ff-only` advancement.
- **v1.0** — The first `gitmerge`: a single script consolidating local branches through `main`.

## License

[MIT](LICENSE).
