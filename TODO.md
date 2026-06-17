# TODO / Roadmap

Status of GitMergeTools. Everything below the line is **done and tested** (suite green on PowerShell 7
and Windows PowerShell 5.1); above the line is the remaining backlog.

## Backlog

### P3 — Structural refactor (largest remaining piece)
- ✅ **Done (on main):** shared `GitMergeTools.Core.psm1` — single source of truth for the git primitives
  (Invoke-GitCommand, ref/branch/worktree helpers, Get-Mode, …); all three commands consume it.
- ⏳ Extract the transactional merge engine into `GitMergeTools.Merge.psm1`; make the commands thin peers
  and **remove the `gitsync → gitmerge` call**, gated behind the characterization tests (CAS / ancestor /
  clean-worktree / cleanup), landed in one piece. *The self-contained engine safety helpers are already
  extracted; the orchestration body + the gitsync→gitmerge removal are the remaining sub-step.*
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
- **MAX_PATH (Windows) fast-fail**: before creating the temp worktree, refuse with a clear, actionable
  message when the temp base path is already near the 260-char limit (or long paths are disabled), and
  pass `-c core.longpaths=true` on the tool's own git calls. Path-LENGTH check only — no DriveInfo/disk probe.
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

### Optional enhancements (nice-to-have, not scheduled)
- **`max`-tier raw ANSI/OSC effects** (OSC 9;4 taskbar progress, truecolor gradients, rounded panels):
  optional top-tier polish — real value but low priority. The `max` gate already exists and degrades
  cleanly to `rich`; until the effects land, the "upgrade to max" advisory should note `max` currently
  renders identically to `rich`. Build behind a single gated raw-ANSI/OSC sink **plus its leak-test matrix**
  (redirected/CI/NO_COLOR ⇒ zero ESC/OSC/CR bytes) when desired.

## Descoped — over-engineering, deliberately not building
- **ENOSPC `DriveInfo` predictive precheck**: fragile (TOCTOU / threshold-guessing) — a whole disk-space
  probe for a rare case. Let git fail cleanly and let the startup reclamation sweep the orphan; classify
  ENOSPC at runtime only if cheap. *(MAX_PATH fast-fail is a path-LENGTH check and IS scheduled above.)*
- **Case-insensitive ref-collision refuse**: requires a user to create twin refs; at most a cheap
  piggyback check inside the preflight loop, not a dedicated gate.

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
  smoke/characterization/safety suites, and a cross-runtime driver. **57 passing on both runtimes.**
