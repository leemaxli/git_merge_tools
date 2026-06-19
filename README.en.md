# GitMergeTools

[:cn: 简体中文](README.md) · :us: **English**

![version](https://img.shields.io/badge/version-v7.4.0-blue) [![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Safe, transactional Git branch consolidation** — three cross-platform PowerShell commands with an auto-degrading, capability-aware visual layer.

## What it is

GitMergeTools provides three commands for consolidating local Git branches without data loss:

| Command | Mode | What it does |
|---------|------|--------------|
| `gitmerge` | **Local only** | Transactional local branch consolidation: validates all merges in a throwaway worktree, fast-forwards real refs only after every merge succeeds |
| `gitsync` | **With remote** | Same topology as gitmerge, but additionally safe-pulls each involved `origin/<branch>` before, then pushes each branch's own `origin/<branch>` after (per-branch, single-ref, never forced) |
| `gitstatus` | **Read-only** | Enhanced status, recent commit log (with chain graph), and branch-vs-`origin/<branch>` comparisons; never changes refs |

**Safety first:** the tools never force-move or delete branches, never `reset`/`rebase`, never force-push. Every ref move is a fast-forward or compare-and-swap, validated in a throwaway worktree first; any failure changes nothing.

**Requirements:** PowerShell 7.x (preferred) or Windows PowerShell 5.1; git 2.x. Cross-platform goal: Windows / Linux / macOS.

## Install & setup

Clone the repository (or download it) and keep this layout:

```
GitMergeTools/
├─ gitmerge.ps1
├─ gitsync.ps1
├─ gitstatus.ps1
└─ Modules/
   └─ GitMergeTools.*.psm1
```

Dot-source the three scripts from your PowerShell profile (`$PROFILE`):

```powershell
# in $PROFILE (add to both profiles if you use pwsh 7 and 5.1)
. 'C:\path\to\GitMergeTools\gitmerge.ps1'
. 'C:\path\to\GitMergeTools\gitsync.ps1'
. 'C:\path\to\GitMergeTools\gitstatus.ps1'
```

If `$PSScriptRoot` can't resolve (e.g. functions pasted directly into a profile), set an env-var override:

```powershell
$env:GITMERGE_TOOLS_HOME = 'C:\path\to\GitMergeTools'
```

## The three commands

### gitmerge — local-only consolidation

Converges branches bidirectionally to their union commit, **entirely locally** (no fetch, no pull, no push). All merges are validated in a throwaway temporary worktree; real refs are fast-forwarded only after every merge succeeds.

### gitsync — with remote sync

Identical topology to gitmerge, but additionally performs a safe pull of each involved `origin/<branch>` before consolidation (fast-forward or conflict-free merge), then pushes each converged branch to its own `origin/<branch>` afterward (single-ref ordinary push; rejected pushes are skipped, never forced).

### gitstatus — read-only status

Shows working-tree status, a recent commit log with a chain graph, and per-branch ahead/behind counts against `origin/<branch>`. Never modifies any ref or remote state.

## Parameters & topologies

All three commands share the same argument forms:

| Argument | Topology | Description |
|----------|----------|-------------|
| *(empty)* | **2-branch** | Current branch ↔ `main`, bidirectional convergence to their union |
| `{branch}` | **2-branch** | Current branch ↔ named branch, bidirectional, de-main-centered |
| `all` | **Star** | Current branch (hub) absorbs every other branch; each spoke reverse-merges the hub's original commit |
| `cross-all` | **Mesh** | Every branch converges to one union commit |
| `debug` | **Dry-run** | Dry-run of `cross-all`: reports the plan, changes nothing |

### Star vs Mesh illustrated

```
Star (gitmerge all):           Mesh (gitmerge cross-all):

   spoke-A                        branch-A ─┐
      ↑↓                                    ├─→ [union commit]
   [HUB] ←→ spoke-B              branch-B ─┤       ↑
      ↑↓                                    │   (all branches
   spoke-C                        branch-C ─┘  fast-forward here)

hub = current branch, absorbs    all branches converge to one union
every spoke                      conflict → fail-fast (nothing changes)
each spoke = original-hub ∪ spoke dirty branch → skip, rest converge
conflicting/dirty spoke → skip
hub dirty → abort entire run
```

**Sub-branch skip:** if a target branch has an unmerged descendant (a "sub-branch" with uncommitted-back work), it is skipped with a warning rather than silently consolidated.

## Usage examples

```powershell
# --- gitmerge ---

# Converge current branch and main bidirectionally (most common)
gitmerge

# Converge current branch and feature/login bidirectionally
gitmerge feature/login

# Current branch (hub) absorbs all others (star topology)
gitmerge all

# All branches converge to one union commit (mesh topology)
gitmerge cross-all

# Preview the cross-all plan without changing anything
gitmerge debug

# --- gitsync ---

# Pull + merge + push: current branch and main
gitsync

# Pull + merge + push: all branches, star topology
gitsync all

# Pull + merge + push: all branches, mesh topology
gitsync cross-all

# --- gitstatus ---

# Show current branch status and recent log
gitstatus

# Show ahead/behind for all branches
gitstatus all
```

## Safety model

**Hard constraint (non-negotiable):** no code path may delete, overwrite, force-move, `reset`, `rebase`, or non-atomically push in a way that could lose work or corrupt a repository.

Specific guarantees:

- **No force-push / reset / rebase:** all pushes are ordinary single-ref `git push`; rejected by the remote → skipped, never `--force`.
- **Throwaway worktree validation:** every merge is validated in a one-shot temporary worktree; real refs advance only after every merge succeeds.
- **Fast-forward / compare-and-swap:** real ref moves are either fast-forwards or compare-and-swap `update-ref` calls (guarding against concurrent writers).
- **Conflict handling:**
  - `all` (star): conflicting or dirty spoke → skip and proceed; dirty hub → abort.
  - `cross-all` (mesh): any conflict → fail-fast abort, nothing changes.
  - 2-branch: conflict → refuse, all refs remain untouched.
- **Conflicts are never auto-resolved:** the tool always stops and prompts the user.
- **Dirty working trees:** any branch with uncommitted changes is skipped (batch modes) or triggers a refusal (single-branch mode).

## Visuals & summary

### Visual tiers

Output auto-detects terminal capabilities and picks the richest tier that renders safely, degrading high → low. Machine-relevant output (exit codes, git errors) is always tier-independent.

| Tier | Requires | Look |
|------|----------|------|
| `rich` | UTF-8 output + a Unicode-capable terminal | emoji + Unicode box-drawing + color |
| `standard` | UTF-8 output | Unicode box-drawing, no emoji |
| `basic` | — | pure ASCII, no color |

Pin a tier with `GITMERGE_VISUAL_MODE` (`rich`/`standard`/`basic`); `auto` (default) selects automatically.

### Run banner & summary

Every run displays:
- **Banner:** version + repository URL + author, in aligned box format
- **Summary header:** version + `[LIVE]` (real run) or `[DRY-RUN]` (debug mode)
- **Invocation parameter:** which argument / topology was used
- **Workflow chain:** a compact display of pipeline stages
- **Notices/Warnings:** a consolidated block of notices and warnings
- **Recent log:** recent commits with a commit-chain graph, tier-aware color/emoji

### Environment variables

| Var | Values | Meaning |
|-----|--------|---------|
| `GITMERGE_VISUAL_MODE` | `auto` (default) \| `rich` \| `standard` \| `basic` | Pin a visual tier (`max` is still accepted as a compatibility alias for `rich`) |
| `GITMERGE_TOOLS_SUPPRESS_WARNING` | truthy (`1`/`true`/`yes`/`on`) | Silence tier/upgrade notices; git errors/warnings always surface |
| `GITMERGE_TOOLS_HOME` | path | Install-folder override for module discovery |

## Version history

> Current version: **v7.4.0**. Early v1–v3 predate Git tracking and are a summarized retrospective; from v4 on, the history follows the Git commit log.
>
> **History-trimming rule:** the current major lists every sub-version; each older major keeps 3–6 milestone sub-versions (fewer the older); majors more than 5 back get a single one-line summary.

**v7.x — Topology redefinition: star / mesh, de-main-centered (current)**
- **v7.4** — UX & quality: run banner shows version, repo URL, and author in aligned box format; unified summary header (version + `[LIVE]`/`[DRY-RUN]`) across all three commands; summary now shows the invocation parameter, a compact workflow chain, and a consolidated notices/warnings section; richer recent-log with a commit-chain graph and tier-aware color/emoji; plus the dead through-main engine removed and shared helpers extracted.
- **v7.3** — `gitsync` adopts the new topologies + **per-branch remote sync**: each mode (2-branch / all / cross-all) = the matching `gitmerge` topology, wrapped with a safe pull of every involved `origin/<branch>` before, and a per-branch single-ref ordinary push of each converged branch's own `origin/<branch>` after (skip-on-reject, never forced) — replacing the old "through-main + one atomic push" model. An unsafe `main` or star hub aborts.
- **v7.2** — `gitmerge cross-all` becomes a **de-main-centered full mesh**: all branches converge to one union commit; a merge conflict → fail-fast abort (nothing changed); a dirty-worktree branch → skipped; `gitmerge debug` is now a dry-run of that mesh.
- **v7.1** — `gitmerge all` becomes a **current-branch star**: the hub absorbs all branches; each spoke reverse-merges the hub's original commit; conflicting/dirty spokes skip, dirty hub aborts.
- **v7.0** — `gitmerge` (empty / `{branch}`) becomes **bidirectional convergence of the current branch and the target**, de-main-centered.

**v6.x — Remote sync: pull, not just push**
- **v6.8.0** — Recent commit log grows from 5 to 10 entries; `gitsync` summary gains its missing recent-commits block.
- **v6.7.1** — Test-only: safety regression-locks for the two most dangerous operations (gitsync `push --atomic` meta-scan and negative-case tests for `Test-TemporaryWorktreeForCleanup`).
- **v6.7.0** — Skip-and-proceed (gitsync): non-main branches that can't be safely pulled are skipped and the rest synced; never force-pushed.
- **v6.4.1** — Safety fix: two worktree-free pull paths now compare-and-swap against the tip captured at classify time, closing a between-pass concurrency race.
- **v6.4.0** — Stage 4: checked-out branches with a clean worktree can also be auto-merged without conflict; safe-sync rollout complete.
- **v6.0.0** — Critical gap fix: `gitsync` no longer hard-errors when origin is ahead; new REMOTE PULL phase classifies each branch and stops with an actionable `ACTION NEEDED` prompt instead of a cryptic failure.

**v5.x — Modularization, engine unification & hardening**
- **v5.5.0–v5.10.0** — Non-interactive git profile, in-progress-op preflight, encoding/i18n tests, modules moved into `Modules/`.
- **v5.4.0** — Folded `max` tier into `rich` (`max` stays a compatibility alias); visual tiers are now `rich/standard/basic`.
- **v5.1.0–v5.3.1** — Extracted `Core.psm1` + `Merge.psm1`; three commands become thin peers on one engine (removed `gitsync → gitmerge` coupling); git-safety hardening.
- **v5.0.0** — UTF-8 capture, non-destructive fetch, porcelain hygiene, dead-code removal.
- **v4.x** — Claude-driven hardening & open-source release: dependency-free test system, capability profile + 4-tier visual selection, git-safety hardening, bilingual README + MIT license + GitHub release.

**v3.x — ~3 milestones (Git adoption + visual progression):** the `rich` tier took shape (emoji, Unicode box-drawing); began using Git for version control; `max` top-tier experiments.

**v2.x — Three commands & basic visuals (one-line summary):** the three-command shape emerged (`gitmerge` + `gitsync` + `gitstatus`), with basic visuals (stage headers, status lines, result summary).

**v1.x — Genesis (one-line summary):** the first `gitmerge`: a single script consolidating local branches through `main` (transactional temporary-worktree integration, `--ff-only` advancement).

## License

[MIT](LICENSE) © Leemax Li
