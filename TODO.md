# TODO / Roadmap

Status of GitMergeTools. Below the line is **done and tested** (green on PowerShell 7 and Windows
PowerShell 5.1); above it is the **leaned** backlog. The backlog has survived three anti-over-engineering
passes (the latest, 2026-06-18, was a code-grounded multi-agent review: 10 candidate items, only 2 cheap
safety-characterization tests survived adversarial verification). The merge engine (`Merge.psm1`) and git
primitives (`Core.psm1`) are lean and load-bearing; all remaining work is either a HARD-CONSTRAINT
regression-lock or deletion-driven simplification in the discovery / visual-plumbing layer.

## Backlog (leaned)

### Safety regression-locks (highest value; test-only, no production change)
- **`gitsync push --atomic` meta-scan** — a positive counterpart to `tests/meta/PushForceGuard.Tests.ps1`.
  `gitsync.ps1`'s single `push --atomic origin <refspecs>` is the *entire* remote-write path, and `--atomic`
  is the all-or-nothing guarantee that a multi-ref push can't partially clobber a collaborator. It has **zero
  test coverage** today — the flag (or a split into per-branch pushes) could be removed without turning a
  single test red. A cheap source-scan closes that silent-degradation hole. *(Do NOT build the runtime
  rejection/race test — advancing origin pre-run trips the divergence preflight before the push is reached,
  and the real fetch→push TOCTOU has no injection seam in the black-box harness.)*
- **`Test-TemporaryWorktreeForCleanup` negative-case tests** (`Merge.psm1`) — this guard is the sole gate
  before the tool's only destructive `git worktree remove --force`. Existing tests cover only the happy path;
  the refusal arms (non-matching branch name, mismatched path, locked record, case-sensitive branch compare)
  have no coverage, so a regression loosening the pattern/path check would be invisible yet could force-remove
  a user-owned path. Add a unit test asserting `$false` for each refusal arm (the exported-helper unit-test
  pattern already exists in `InProgressOpPreflight.Tests.ps1`). No production-code change.

### Deletion-driven simplification (engine + safety tests untouched)
- **Fold `Common` + `Common.PowerShell7` + `Common.PowerShell51` into one `GitMergeTools.Environment.psm1`**
  (inline `$PSVersionTable` branching for the `::new()`/`New-Object` one-liner); delete the two runtime
  modules AND the now-redundant inline fallback in Common. The search-dir / runtime-state / rich-probe logic
  exists in **triplicate** (Common delegates to PS7/51 *and* carries a third inline copy of the 9-entry
  candidate ladder, reachable only if a sibling `Modules/*.psm1` is absent — which never happens, since they
  ship together). ~150 lines and an entire dead load-path deleted, no behavior change.
- **Single-directory discovery for the visual loader**: collapse the three near-verbatim
  `New-OptionalGit{Merge,Sync,Status}Visual` functions (only the command-name string differs) to the same
  `$PSScriptRoot -> Split-Path $PSCommandPath -> $GITMERGE_TOOLS_HOME` (Modules/ then flat) cascade the
  Core/Merge preamble already uses; delete the XDG/.config/Documents/MyDocuments/OneDrive ladder (it is then
  rebuilt a 2nd time inside Common to resolve renderers — the "6-copy cascade").
- **Consolidate the suppress-warning env var to the single documented `GITMERGE_TOOLS_SUPPRESS_WARNING`**;
  delete the undocumented `GITMERGE_VISUAL_SUPPRESS_WARNING` twin and the OR-of-two-names logic across the
  4+ sites (Common + the three entry scripts + Visual.Common). README documents only the `_TOOLS_` name, so
  the twin is dead duplication with no deprecation concern. **Keep the `_TOOLS_` name** — do NOT rename to a
  bare `GITMERGE_SUPPRESS_WARNING` (that would break the published variable).

## Deferred (real but low priority — leave as notes, don't build now)
- **Full gitsync structured-result cleanup**: the data-safety subset shipped (v5.10.0 — gitsync pushes the
  engine's `SynchronizedBranches` verbatim). What remains is one redundant fetch round-trip (the preflight
  fetch is genuinely needed before local refs change) and gitsync's own `#10` skip (now redundant for the
  push set but still shaping the dry-run preview + preflight loop). Not a correctness/safety driver.
- **Delete the truly-undocumented visual-mode aliases** (`a`/`b`/`c`, `full`/`emoji`/`current`/`enhanced`/
  `fallback`/`plain`) — trivially deletable, but **keep `max`** (documented in README.en as the rich compat
  alias, pinned by `MaxFoldedToRich.Tests.ps1`; deleting it is a real if minor breaking change). Low value.
- **Non-English `LANG`/`LC_ALL` regression test** — can only pin the existing exit-code/`--porcelain`
  convention against regression (the tools deliberately never parse localized text); it cannot surface a real
  defect today. Cheap and plausibly justified by the cp936/GBK dev locale, but not a current bug.

## Descoped — over-engineered for a solo 3-command tool (deliberately NOT building)
- **`--` option terminator before user refs**: defends a threat that cannot occur — every ref is passed
  fully-qualified `refs/heads/<x>` built from git's own branch enumeration (#6), never raw user input, never
  a value that could start with `-`. Injection surface is effectively zero.
- **Read-only `check` keyword**: no gap to close — read-only inspection is already `gitstatus`, and
  `gitmerge debug` / `gitsync debug` are full dry-run plans (no ref/worktree/remote mutation). A third way to
  do the same thing only adds parsing surface.
- **Merge `Basic/Standard/Rich` into one `Visual.Renderers.psm1`**: cosmetic file-count reduction, not real
  dedup — the three renderers' bodies differ substantially per tier (ASCII vs box-drawing vs glyphs/color);
  merging removes no shared logic and forces a large churn diff on visually-sensitive, hard-to-test code.
- **`max` raw-ANSI/OSC truecolor effects** (gradients, OSC 8 / OSC 9;4, rounded panels): the only
  control-byte-emitting path; pure eye-candy. The `max` tier itself is folded into `rich`.
- **gitsync concurrency classification + two-process race meta-test**: the compare-and-swap `update-ref`
  already makes concurrent runs safe; this only rewords an outcome a solo user won't hit.
- **Startup reclamation of orphaned `gitmerge-tmp-*` worktrees** (user decision, 2026-06-18): orphans only
  occur on a crash; normal cleanup covers every other path, and a startup sweep risks removing a *concurrent*
  run's active temp worktree. Not worth the concurrency-classification machinery for a solo tool.
- **Kitchen-sink non-interactive profile** beyond the 3 shipped flags (transport timeouts, SSH BatchMode,
  color/quotepath/advice subset, `GIT_OPTIONAL_LOCKS`); **predictive MAX_PATH / ENOSPC `DriveInfo` prechecks**
  (let git fail cleanly); **ref NFC + `check-ref-format`** (refs come from git's own enumeration);
  **byte-consistency test** (only meaningful once raw-ANSI exists, which it won't); **per-stage Stopwatch
  badges + recursive branch tree**; **case-insensitive ref-collision gate**.
- **refuse-LFS/submodule/sparse/shallow gate**: stays descoped UNTIL a failing characterization test *proves*
  tree corruption through the throwaway-worktree merge — do not pre-build the gate.

> Why the descoped block is correct: the HARD CONSTRAINT is met *by construction* — the engine only runs
> `worktree add` / `merge` / `merge --abort` / `merge --ff-only` / `update-ref` / `worktree remove`, and
> publishes via compare-and-swap `update-ref` + `merge --ff-only` + `push --atomic`. It never runs
> `add`/`checkout`/`reset`/`commit -a`/`rm`. Every descoped item is enterprise defense against a threat this
> design already prevents.

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
  `git rev-parse --git-path`) (v5.7.0); gitsync pushes exactly the engine's reported synchronized set
  (single source of truth for the #10 skip) and the dead `-RemoteAlreadyFetched` param was removed
  (v5.10.0); a meta-test that permanently forbids `git push --force`/`--force-with-lease`.
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
  smoke/characterization/safety suites, a cross-runtime driver. **76 passing on both runtimes.**
