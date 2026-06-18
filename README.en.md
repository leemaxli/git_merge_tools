# GitMergeTools

[:cn: 简体中文](README.md) · :us: **English**

**Current version v6.8.0** · see [Version history](#version-history) below

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

**Remote ahead (new in v6.0):** when `origin/<branch>` is ahead of (or has diverged from) your local
branch, `gitsync` now stops with an actionable **`ACTION NEEDED`** prompt telling you to pull first —
instead of failing cryptically — and changes nothing. Automatic *safe* pulling (fast-forward only, then
clean merges) is rolling out incrementally across v6.x.

## Install

Keep the three command scripts (`gitmerge.ps1`, `gitsync.ps1`, `gitstatus.ps1`) at the top of the
install folder, with the `Modules/` subfolder holding the `GitMergeTools.*.psm1` modules right beside
them (the repository's own layout):

```
GitMergeTools/
├─ gitmerge.ps1
├─ gitsync.ps1
├─ gitstatus.ps1
└─ Modules/
   └─ GitMergeTools.*.psm1
```

Then dot-source the three commands from your PowerShell profile (do this in **both** the PowerShell 7
and Windows PowerShell 5.1 profile roots if you use both):

```powershell
# in $PROFILE
. 'C:\path\to\GitMergeTools\gitmerge.ps1'
. 'C:\path\to\GitMergeTools\gitsync.ps1'
. 'C:\path\to\GitMergeTools\gitstatus.ps1'
```

The loaders look for the modules in the `Modules/` subfolder first and still tolerate a flat layout
(everything in one folder). If the commands are loaded in a way where `$PSScriptRoot` can't resolve
(e.g. pasted directly into a profile), set `GITMERGE_TOOLS_HOME` to the install folder.

## Visual tiers

Output auto-detects the terminal's capabilities and picks the richest tier that renders safely,
degrading high → low. Machine-relevant output (exit codes, git errors) is always independent of the tier.

| Tier | Requires | Look |
|------|----------|------|
| `rich` | UTF-8 output + a Unicode-capable terminal | top tier: emoji + Unicode box-drawing + color |
| `standard` | UTF-8 output | Unicode box-drawing, no emoji |
| `basic` | — | pure ASCII, no color |

## Environment variables

| Var | Values | Meaning |
|-----|--------|---------|
| `GITMERGE_VISUAL_MODE` | `auto` (default) `\| rich \| standard \| basic` | Pin a visual tier; still capability-checked (a pinned tier that can't render degrades). (`max` is still accepted as a compatibility alias for `rich`.) |
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

Functional and fully tested (all known defects fixed; 103-test suite green on both runtimes). **The
core of the structural refactor is done**: `Core.psm1` (git primitives) and `Merge.psm1` (the
transactional engine) are extracted, the three commands are thin peers on one engine with no
cross-command coupling; the remaining environment-module merge and git-safety hardening are in progress.

## Version history

> Current version: **v6.8.0**. Early v1–v3 predate Git tracking and are a summarized retrospective;
> from v4 on, the history follows the Git commit log.
> Old-history trimming: versions more than 5 majors back keep only their major (`.0`) line (at v6.x, v1 keeps just v1.0).

**v6.x — Remote sync: pull, not just push (current)**
- **v6.8.0** — All three commands' run summaries now show 10 recent commits (was 5); `gitsync`'s summary gains a "recent commits" block it previously lacked.
- **v6.7.1** — Test-only: safety regression-locks for the two most dangerous operations — a meta-scan pinning gitsync's `push --atomic` (and that gitmerge/gitstatus/engine never push), and negative-case tests for `Test-TemporaryWorktreeForCleanup`, the gate before the only `git worktree remove --force`.
- **v6.7.0** — Skip-and-proceed (gitsync): with `all`/`cross-all`, `gitsync` now **skips** a non-main branch that can't be safely pulled (dirty worktree, or a conflicting divergence) and syncs the rest, instead of aborting the whole run. The skipped branch is excluded from the pull, the consolidation, **and** the push (never force-pushed) and is left untouched. A single explicitly-selected branch, or an unsafe `main`, still stops with `ACTION NEEDED`.
- **v6.6.0** — Skip-and-proceed (engine): `gitmerge`/`gitsync` with `all`/`cross-all` no longer abort the whole run when a *non-main* target branch's worktree can't safely participate (dirty, or mid-merge/rebase/cherry-pick/revert) — that branch is **skipped with a warning** and the rest still consolidate (consistent with the `#10` sub-branch skip). A dirty or in-progress **main** worktree still aborts, since everything is consolidated through main.
- **v6.5.0** — The `gitsync` / `gitstatus` run summary now shows the **remote location** (origin URL), not just the local repository path — so you can see where you're syncing/comparing against.
- **v6.4.1** — Safety fix (found by an adversarial review of the v6.x code): the two worktree-free pull paths now compare-and-swap against the branch tip **captured at classify time** (via the new `Move-BranchRefSafely`, with a true-fast-forward guard) instead of a freshly re-read tip. This closes a between-pass race where a branch advanced by a *concurrent* writer could be force-moved sideways (orphaning the new commit) or merged onto a stale tree. The checked-out paths were already safe (a live `git merge` re-validates).
- **v6.4.0** — Stage 4 (checked-out): the divergent clean-merge auto-sync now also covers a **checked-out branch with a clean worktree** — the common case where your *current* branch has diverged from origin — applied via `merge --no-edit` after the same in-memory `merge-tree` validation. A dirty worktree or a conflicting merge still prompts. This completes the safe-sync rollout: `gitsync` now auto-pulls/merges every case it can do without risking your work (fast-forwards and conflict-free merges), and prompts for the rest (dirty worktree, conflicting divergence) — never resetting, rebasing, or force-pushing.
- **v6.3.0** — Stage 4 (not-checked-out): `gitsync` auto-*merges* a **not-checked-out** branch that has diverged from origin **when the merge is clean** — validated in-memory with `git merge-tree` (no worktree touched, no ref changed), then applied worktree-free via `commit-tree` + a compare-and-swap `update-ref`. Conflicting divergences are never auto-resolved; they still prompt.
- **v6.2.0** — Stage 3: `gitsync` also auto fast-forward-pulls a branch that *is* checked out, when its worktree is **clean** (via `merge --ff-only` in that worktree) — covering the common case of the current branch trailing origin. A dirty worktree is never touched; it still prompts.
- **v6.1.0** — Stage 2: `gitsync` now *auto* fast-forward-pulls a branch that origin is ahead of when that branch is **not checked out** in any worktree (a compare-and-swap `update-ref` — the safest pull, no working tree to disturb). The REMOTE PULL phase is all-or-nothing: it classifies every branch read-only first, and if any branch still can't be safely synced (a checked-out fast-forward, or a divergence) it changes nothing and prompts.
- **v6.0.0** — Critical gap fix: `gitsync` no longer hard-errors when `origin` is ahead of (or diverged from) a local branch. A new **REMOTE PULL phase** classifies each branch it will sync (`UpToDate`/`LocalAhead`/`FastForwardable`/`Diverged`) and, when a pull is required, stops with an actionable **`ACTION NEEDED`** prompt (e.g. `git pull --ff-only origin <branch>`) — changing nothing — instead of a cryptic failure. This is Stage 1 of a staged rollout; automatic *safe* pulling (fast-forward-only, then throwaway-worktree-validated clean merges) arrives in later v6.x sub-versions. `gitmerge` is unchanged.

**v5.x — Modularization, engine unification & hardening** (condensed; full per-version detail in the Git log)
- **v5.5.0–v5.10.0** — Slimming + git-safety wave: modules moved into a `Modules/` subfolder; a non-interactive, long-path-safe git profile (`GIT_TERMINAL_PROMPT=0`, `GIT_EDITOR=true`, `core.longpaths`, `rerere` off); an in-progress-op preflight (refuse a worktree mid-merge/rebase/cherry-pick/revert); the upgrade advisory surfaced from all three commands; encoding/i18n path tests; and `gitsync` pushing exactly the engine's synchronized set.
- **v5.4.0** — Anti-over-engineering: folded the `max` tier into `rich` and deleted it (`max` stays a compatibility alias); visual tiers are now `rich/standard/basic`.
- **v5.1.0–v5.3.1** — Modularization & hardening: extracted `Core.psm1` (git primitives) + `Merge.psm1` (the transactional engine), making the three commands thin peers on one engine (**removed the `gitsync → gitmerge` call**); began git-safety hardening (`GIT_DIR`/locating-env neutralization); upgrade-advisory fix.
- **v5.0.0** — Latent-bug sweep: UTF-8 capture of git output (non-ASCII branch names), non-destructive fetch, `gitstatus` porcelain hygiene, display-width-aware truncation; over-engineering descoped and dead code removed.

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
- **v1.0** — The first `gitmerge`: a single script consolidating local branches through `main` (transactional temporary-worktree integration, `--ff-only` advancement).

## License

[MIT](LICENSE).
