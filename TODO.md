# TODO / Roadmap

Status of GitMergeTools. Everything below the line is **done and tested** (suite green on PowerShell 7
and Windows PowerShell 5.1); above the line is the remaining backlog.

## Backlog

### P3 — Structural refactor (largest remaining piece)
- Extract the duplicated helpers (copy-pasted across `gitmerge.ps1`/`gitsync.ps1`/`gitstatus.ps1`)
  into a shared `GitMergeTools.Core.psm1` (single source of truth: `Invoke-GitCommand`, ref/branch/
  worktree helpers, `Get-Mode`, `Resolve-MainBranch`, …).
- Extract the transactional merge engine into `GitMergeTools.Merge.psm1`; make the three commands
  thin peers that consume it. **Remove the `gitsync → gitmerge` call** (they should be siblings on a
  shared engine, not one invoking the other).
- Fold the runtime/visual detection (`Common` + `PowerShell7/51`) into `GitMergeTools.Environment.psm1`.
- Remove dead code (unused `$icons` tables, `RuntimeLevel`) and legacy aliases / env vars.
- Single-directory module discovery (drop the XDG/Documents/OneDrive path ladder).

### Git-safety hardening (lands with / after the engine unification)
- Force UTF-8 decoding of captured git output, independent of console code page (cp936/OEM on 5.1
  otherwise mojibakes non-ASCII branch names → wrong/skipped branch).
- Neutralize inherited `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`/… and pin `git -C <root>`.
- One centralized non-interactive git-invocation profile (per command class): credential/pager/
  color/optional-locks/`safe.directory`/gpg/hooks/rerere/timeouts — applied via `-c`/env, never by
  mutating user config.
- Preflight gates before creating the temp worktree: refuse on in-progress operations
  (rebase/cherry-pick/revert/bisect), refuse unsupported repos (submodule/LFS/sparse/shallow/partial),
  case-insensitive ref collisions, and MAX_PATH / disk-space (ENOSPC) fast-fail.
- gitsync: return a structured result; report-only (no rollback) on push rejection with clear
  messaging; classify lock conflicts as clean-fail concurrency outcomes.
- Idempotent startup reclamation of orphaned `gitmerge-tmp-*` worktrees (finally is not guaranteed
  under Ctrl-C/SIGTERM/SIGKILL); macOS `/var`→`/private/var` realpath fix in the cleanup guard.

### Visual polish (`max` tier)
- Distinctive `max`-tier effects through a single gated raw-ANSI/OSC sink: 24-bit truecolor
  (gradients, Okabe-Ito palette), OSC 8 hyperlinks, OSC 9;4 taskbar/tab progress, dim/reverse.
- Per-component upgrades that degrade cleanly: rounded-corner panels, recursive branch-topology tree,
  reverse-video SUCCESS pill, per-stage Stopwatch timing badges, display-width-aware truncation.
- Wire the upgrade advisory into the `gitsync` / `gitstatus` summaries too (currently `gitmerge` only).
- Consolidate the suppress env var to a single `GITMERGE_SUPPRESS_WARNING`; add a `check` keyword
  (env/config/capability report) and a config dump under `debug`.

### Verification
- Full cross-runtime regression + edge tests for encoding, locale/i18n (non-ASCII branch names, repo
  paths with spaces/Unicode), and concurrency.

---

## Done

- **Defects fixed (each with a red→green regression test):**
  - rich-mode crash from a `$stageIcon`/`$StageIcon` variable-name collision
  - gitsync reporting a successful push as `FAILED`; destructive prune-on-sync
  - terminal-capability detection treating a bare console as rich-capable
  - `standard` tier rendering without a UTF-8 gate
  - silent-mode env var only matching the literal `1`
  - redundant runtime-module reloads
  - bareword refs that a same-named tag/remote could shadow → now fully-qualified
  - unconditional `git merge --abort` (now guarded by an actual merge-in-progress check)
- **Features:** 4-tier `max/rich/standard/basic` visual selection gated on a capability profile;
  upgrade advisory (in `gitmerge`); skip-with-warning for a target that has an unmerged descendant branch.
- **Tests:** a dependency-free harness (no Pester) with hermetic, sandboxed throwaway repos + a
  path-containment guard, smoke/characterization/safety tests, and a cross-runtime driver.
