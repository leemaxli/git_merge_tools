# TODO / Roadmap

Status of GitMergeTools. Everything below the line is **done and tested** (suite green on PowerShell 7
and Windows PowerShell 5.1); above the line is the remaining backlog.

## Backlog

### P3 — Structural refactor (largest remaining piece)
- Extract a shared `GitMergeTools.Core.psm1` (single source of truth: one `Invoke-GitCommand`,
  ref/branch/worktree helpers, `Get-Mode`, `Resolve-MainBranch`). The three commands currently carry
  drifted copies. **Do this first** — lowest-risk, highest-certainty slice.
- Extract the transactional merge engine into `GitMergeTools.Merge.psm1`; make the three commands thin
  peers and **remove the `gitsync → gitmerge` call**. **Gate behind characterization tests** that prove
  behavior-equivalence on the safety path (CAS / ancestor / clean-worktree / cleanup); land in one piece.
- Fold runtime/visual detection (`Common` + `PowerShell7/51`) into `GitMergeTools.Environment.psm1`.
- Single-directory module discovery (drop the XDG/Documents/OneDrive ladder). Note: the override var
  changes from `GITMERGE_TOOLS_COMMON_MODULE` (a file) to `GITMERGE_TOOLS_HOME` (a dir) — document it.
- Remove dead code (`$icons` tables, `RuntimeLevel`) and the legacy visual-mode aliases.

### Git-safety hardening (lands with the engine unification)
- Neutralize inherited `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`/… and pin `git -C <root>`.
- A centralized non-interactive git profile — **core subset only**: `GIT_TERMINAL_PROMPT=0`,
  non-interactive credentials, `GIT_SSH_COMMAND='ssh -o BatchMode=yes'`, transport timeouts,
  `GIT_EDITOR=true`, `color.ui=false`/`core.quotepath=false` for machine reads, `rerere` off,
  `GIT_OPTIONAL_LOCKS=0`. Respect signing/hooks (preflight + fail-closed); never blanket `--no-verify`.
- Preflight: refuse on in-progress ops (rebase/cherry-pick/revert/bisect — **all** of them, resolved
  per-worktree via `git rev-parse --git-path`); refuse **LFS / submodule / sparse-checkout** (these can
  publish a wrong tree to main). *(shallow/partial clones are allowed — they don't corrupt the tree.)*
- gitsync: structured result + report-only on push rejection + clean-fail on lock/CAS concurrency;
  a meta-test grepping push args to permanently forbid `--force`.
- Idempotent startup reclamation of orphaned `gitmerge-tmp-*` worktrees (incl. macOS realpath in the guard).
- `ref` NFC normalization for comparison keys; `--` option terminator + `check-ref-format` on user refs.
- A byte-consistency test: machine output (`--porcelain` / exit codes) identical across visual tiers.

### Visual polish
- Wire the upgrade advisory into `gitsync`/`gitstatus`; consolidate to a single
  `GITMERGE_SUPPRESS_WARNING` (keep the old names as deprecated aliases); add a read-only `check` keyword.
- Per-stage Stopwatch timing badges + a recursive branch-topology tree in the **rich** tier
  (plain-text, capture-safe).

## Descoped — over-engineering, deliberately not building
- **`max`-tier raw ANSI/OSC effects** (OSC 9;4 taskbar progress, truecolor gradients, rounded panels):
  zero information gain for a seconds-long local git op, highest output-stream-leak risk. The `max`
  shell/gate stays (it degrades cleanly to `rich`); its raw-byte content is deferred indefinitely. Until
  then, the "upgrade to max" advisory should note that `max` currently renders identically to `rich`.
- **ENOSPC `DriveInfo` predictive precheck** and **MAX_PATH predictive length fast-fail**: fragile
  (TOCTOU / threshold-guessing). Keep only `-c core.longpaths=true`, let git fail cleanly, and let the
  startup reclamation sweep the orphan. Classify ENOSPC at runtime only if cheap.
- **Case-insensitive ref-collision refuse**: requires a user to create twin refs; at most a cheap
  piggyback check inside the preflight loop, not a dedicated gate.
- **The full `max` leak-test matrix**: deferred together with the raw-byte content it guards.

---

## Done

- **Bug fixes (each with a red→green regression test, green on both runtimes):**
  - `#1` UTF-8 decode of git output — non-ASCII branch names survive a cp936/GBK redirected stdout
    (otherwise `merge`/`push refs/heads/<name>` targeted the wrong ref).
  - `#2`-twin — `gitmerge` fetch is non-destructive; never prunes local-only tags.
  - `#3` — `gitsync` honors the `#10` unmerged-descendant skip in its push set (no misreport).
  - `#4` — `gitstatus` no longer folds git stderr into parsed porcelain output (no phantom branches).
  - `#5` — display-width-aware banner truncation/padding for CJK & emoji.
  - earlier defects: rich `$stageIcon`/`$StageIcon` crash; `gitsync` false-FAIL + destructive prune;
    terminal-capability detection; `standard` UTF-8 gate; silent-mode truthiness; module reload;
    fully-qualified refs; `merge --abort` guard; unmerged-descendant skip (`#10`).
- **Features:** 4-tier `max/rich/standard/basic` selection gated on a capability profile; upgrade
  advisory (in `gitmerge`); display-width helpers (`Get-GitMergeToolsDisplayWidth` /
  `Format-GitMergeToolsFixedWidth`).
- **Tests:** dependency-free harness (no Pester), hermetic sandboxed repos + a path-containment guard,
  smoke/characterization/safety suites, and a cross-runtime driver. **54 passing on both runtimes.**
