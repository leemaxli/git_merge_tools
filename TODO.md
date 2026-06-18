# TODO / Roadmap

Status of GitMergeTools. Below the line is **done and tested** (green on PowerShell 7 and Windows
PowerShell 5.1); above it is the **leaned** backlog after the 2026-06-18 anti-over-engineering review —
roughly half the prior backlog was enterprise gold-plating for a solo-maintained, 3-command tool and has
been cut or deferred. What remains is the cheap, high-value core plus deletion-driven simplification.

## Backlog (leaned)

### Architecture slimming (deletion-driven; the merge engine + its safety tests are untouched)
- **Fold `Common` + `Common.PowerShell7` + `Common.PowerShell51` into one `GitMergeTools.Environment.psm1`**
  (inline `$PSVersionTable` branching for the New-Object/::new() difference); delete the two runtime modules
  AND the now-redundant inline fallback in Common. Biggest dedup: the module-discovery cascade currently
  exists in **6 copies** (Common + PS7/51 + the three entry scripts).
- **Single-directory discovery**: collapse to `$PSScriptRoot -> Split-Path $PSCommandPath -> $GITMERGE_TOOLS_HOME`
  (already used by the Core import); delete the XDG/.config/Documents/MyDocuments/OneDrive ladder in all
  three entry scripts. *(Optional, lower priority)* merge `Basic/Standard/Rich` into one `Visual.Renderers.psm1`.

### Git-safety hardening (cheap core only — hangs on Core's unified `Invoke-GitCommand`)
- gitsync **structured result**: the engine returns its actual synchronized set and gitsync pushes exactly
  that — closes the skip/push divergence and removes the dead `-RemoteAlreadyFetched` param, the redundant
  `#10` double-compute, and the double-fetch. Regression test.
- `--` option terminator before user refs in plumbing calls (cheap injection guard).
- Startup idempotent reclamation of orphaned `gitmerge-tmp-*` worktrees (reuses the existing strict path+
  pattern verifier). macOS `/var`->`/private/var` realpath normalization only if/when actually run on macOS.

### Visual polish (cheap wins)
- Consolidate to a single `GITMERGE_SUPPRESS_WARNING` (pick one name, delete the others — solo tool, no
  deprecation layer). Delete the legacy visual-mode aliases outright. *(Optional)* a read-only `check`
  keyword.

### P4 — verification
- Encoding/i18n edge tests: non-ASCII branch names (done — `Utf8BranchCapture`) and Unicode/space repo
  paths (done — `I18nRepoPath`, v5.9.0) guard the cp936/GBK Windows dev env. **Remaining:** a non-English
  `LANG`/`LC_ALL` test (the tools already key on exit codes + `--porcelain`, so this only pins that
  convention against regression).

## Descoped — over-engineered for a solo 3-command tool (deliberately NOT building)
- **`max` raw-ANSI/OSC effects** (truecolor gradients, OSC 8 / OSC 9;4, rounded panels): the only
  control-byte-emitting code path in the whole tool, pure eye-candy. The `max` tier itself is folded into `rich`.
- **gitsync concurrency classification + two-process race meta-test**: the compare-and-swap `update-ref`
  already makes concurrent runs safe; this only rewords an outcome a solo user won't hit.
- **Kitchen-sink non-interactive profile** beyond the 3 cheap flags (transport timeouts, SSH BatchMode,
  color/quotepath/advice subset, `GIT_OPTIONAL_LOCKS`); **predictive MAX_PATH / ENOSPC `DriveInfo` prechecks**
  (let git fail cleanly + the startup sweep handles the orphan); **ref NFC + `check-ref-format`** (refs come
  from git's own enumeration); **refuse-LFS/submodule/sparse gate** (first *prove* it corrupts main's tree
  with one characterization test, then decide — don't pre-build the gate); **byte-consistency test** (only
  meaningful once raw-ANSI exists, which it won't); **per-stage Stopwatch badges + recursive branch tree**;
  **case-insensitive ref-collision gate**.

---

## Done

- **P3 structural refactor (on main):** `GitMergeTools.Core.psm1` (single source of truth for git
  primitives) + `GitMergeTools.Merge.psm1` (the `Invoke-GitMergeConsolidation` transactional engine); all
  three commands are thin peers on one engine — **the `gitsync → gitmerge` call is gone**. A characterization
  net (`EngineTransaction.Tests.ps1`) locks the engine's safety invariants across the extraction.
- **Architecture slimming (on main):** folded the `max` tier into `rich` and deleted it — `max` stays a
  compatibility alias for `rich` (v5.4.0); moved all `GitMergeTools.*.psm1` modules into a `Modules/`
  subfolder with the entry commands staying top-level (loaders prefer `Modules/`, flat layout still
  tolerated) (v5.5.0).
- **Git-safety hardening (done):** inherited `GIT_DIR`/`GIT_WORK_TREE`/… neutralization in the unified
  `Invoke-GitCommand`; a non-interactive, long-path-safe per-call profile (`GIT_TERMINAL_PROMPT=0`,
  `GIT_EDITOR=true`, `-c core.longpaths=true`, `-c rerere.enabled=false`; the env vars are captured and
  restored, so there is no global leak) (v5.6.0); an in-progress-op preflight that refuses an affected
  worktree mid-merge/rebase/cherry-pick/revert (markers resolved per-worktree via
  `git rev-parse --git-path`) (v5.7.0); a meta-test that permanently forbids
  `git push --force`/`--force-with-lease`.
- **Bug fixes (each red→green, both runtimes):** `#1` UTF-8 decode of git output (non-ASCII branch names
  survive cp936/GBK); `#2`-twin non-destructive `gitmerge` fetch; `#3` gitsync honors the `#10` skip in its
  push set; `#4` gitstatus doesn't fold stderr into porcelain; `#5` display-width-aware banner truncation;
  the upgrade advisory is silent at the optimal tier and specific when a pinned tier isn't reached; plus the
  earlier defect sweep (rich crash, terminal detection, standard gate, suppress truthiness, module reload,
  qualified refs, `merge --abort` guard, `#10` sub-branch skip).
- **Encoding hygiene:** all non-ASCII PowerShell sources are UTF-8-with-BOM (or pure-ASCII), guarded by a
  BOM meta-test.
- **Features:** capability-gated visual selection + upgrade advisory (surfaced by all three commands —
  gitmerge/gitsync/gitstatus, v5.8.0); display-width helpers.
- **Tests:** dependency-free harness (no Pester), hermetic sandboxed repos + path-containment guard,
  smoke/characterization/safety suites, a cross-runtime driver. **74 passing on both runtimes.**
