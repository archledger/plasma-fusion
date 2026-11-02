<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# One-window native ownership proof

NT01 and NT02.1 are complete; NT02.2 and later tasks are unstarted. No tiler is enabled.

NT02.1 is signed native commit `9d7d5c18fbe56c6dc212f4799469ba897a8c168c`: 23 writer
Qt results, five compiled mutation controls, full KWin library linking and 448 selected core
regressions passed. Independent review is clear. The writer has no live desktop instance.
Do not mark historical prototype tests as completion of a task here.

## NT01 — Establish the baseline and native contract
- [x] Pin the exact `.pf2` source, dependencies and binary identities in a separate lane.
- [x] Compare compositor-owned transient roots with the prior external owner, then document lookup,
  window-owned restoration lifetime, command intent, persistence acknowledgment, native tracker
  replay, serialization, version-gate and context-change semantics.
- [x] Map every existing regression to the contract; obtain independent design review before NT02.
Verification: source/patch hashes, native test registration, baseline suite receipts and review.
Dependencies: validated `.pf2` baseline; no concurrent heavy ThinkPad job.
Files: contract document, baseline manifest and isolated build recipe (maximum three).

## NT02 — Establish native transient ownership
- [ ] A selected eligible window enters exactly one transient owner; duplicate/ineligible adoption
  is refused with no manual layout or other-window changes. Admission checks requested and
  committed state, pending transitions, move/resize restrictions and rectangle feasibility;
  real adoption stays unavailable before NT07's exact-snapshot persistence acknowledgment.
- [ ] Native lookup finds that owner without adding it to manual serialization or picking.
- [ ] The test control without transient lookup fails; candidate and ordinary tile controls pass.
Verification: focused `testTiles` cases, a refusal table for each predicate, non-mutation
snapshots, manual-tree/config comparisons and native suite. Native fixtures do not prove disk sync.
Dependencies: NT01.

Run these leaf units in order, not as one large change. Each has focused tests in the same unit:

| Unit | Outcome and acceptance | Source-file bound |
|---|---|---|
| NT02.1 — complete | Native writer primitive uses the existing file; incarnation/revision rejection, map-versus-persisted revisions, sync/readback failure and same-key priority at both close and completion pass real temporary-file tests. Provider replacement gets the dirty map without granting admission. No QML provider or adoption is enabled. | New writer header/source, source CMake, unit-test source and its CMake: five |
| NT02.2 | Immutable transient kind and public mutation guards reject direct manage/geometry/resize changes; ordinary Tile behavior is unchanged. | `tile.h`, `tile.cpp`, `tiles_test.cpp`: three |
| NT02.3 | Concrete transient nodes/controller empty membership before destruction and retain restoration state; callback cancellation stops further mutation and returns Superseded. | One new header/source pair, source CMake, `tiles_test.cpp`: four |
| NT02.4 | Workspace owns controller lifetime; TileManager registers/evacuates only transient storage without changing manual serialization/picking. | Workspace and TileManager header/source pairs plus `tiles_test.cpp`: five |
| NT02.5 | Window compatibility assignment and transient state exposure cannot bypass admission; retained references and X11 refusal are covered before any transient window is exposed. | `window.h`, `window.cpp`, `tiles_test.cpp`: three |

Do not expose a production adoption entry point between these units or before NT07. If the
selected implementation needs more files than a leaf permits, split that leaf before coding.

## NT03 — Preserve floating state on explicit release
- [ ] Capture floating A before adoption; release/disable returns to A instead of automatic B.
- [ ] Repeated release and stale ownership requests have no effect on a later manual placement.
- [ ] Closing during release leaves no stale ownership entry or invalid native access.
Verification: settled-release RED/GREEN, duplicate/stale operations and callback-closure controls.
Dependencies: NT02.
Files: KWin `src/window.{h,cpp}`, `src/tiles/tilemanager.cpp`, `tiles_test.cpp` (maximum four).

## Checkpoint A
- [ ] Baseline and candidate identities, native tests and static checks are recorded.
- [ ] Independent review finds no unresolved ownership, serialization or lifetime blocker.

## NT04 — Resolve asynchronous restoration
- [ ] Keep restoration pending across old tile commits, superseded configures and serial wrap.
- [ ] Clear only on the native completion boundary associated with the current restore generation.
- [ ] Export the reviewed read-only state/completion contract; no raw protocol logger or timeout
  substitutes for native state. The record survives root/policy-module unload; reload cannot
  supersede it and an unresponsive client remains suppressed until completion or close.
Verification: controlled configure/ACK/commit tests, late-close, move-during-settle,
unload-before-ACK, unload/reload-during-restoration and never-ACK cases.
Dependencies: Checkpoint A.
Files: KWin `src/xdgshellwindow.{h,cpp}`, `src/window.{h,cpp}`,
`autotests/integration/xdgshellwindow_test.cpp` (maximum five).

## NT05 — Respect native and manual transitions
- [ ] Maximize/fullscreen returns to the managed rectangle while owned; explicit Restore releases.
- [ ] Manual move/resize and quick tiling take precedence, with no later stale restoration.
- [ ] Wayland and X11 controls preserve ordinary behavior and existing shortcut bindings.
Verification: command-intent matrix distinguishing `UntileOrRestoreOp` from ordinary
maximize/fullscreen toggles, decoration/menu/shortcut paths and internal state changes; full/partial
maximize, quick-tile and manual geometry cases. Changed constraints win through safe release.
Dependencies: NT04.
Files: KWin `src/window.cpp`, `src/xdgshellwindow.cpp`, `src/useractions.cpp`, `tiles_test.cpp`,
`xdgshellwindow_test.cpp` (maximum five; split if other files are needed).

## NT06A — Qualify native placement capture and replay
- [ ] Determine whether existing `PlacementTracker` filtering preserves the original floating
  snapshot during ownership/restoration; change it only if a discriminating regression fails.
- [ ] Output-layout-away-and-back never replays an automatic frame over the restored floating
  frame, whether the client is settled or restoration-pending.
- [ ] Ordinary native layout restoration and manual changes remain unchanged in matched controls.
Verification: capture/replay source audit, owned/restoring layout round trips and stock controls.
Dependencies: NT05.
Files: KWin `src/placementtracker.{h,cpp}`, `autotests/integration/outputchanges_test.cpp`
(maximum three; refine the test location against actual registration in NT01).

## NT06 — Release before context destruction
- [ ] Source-output/desktop removal releases while required context is alive, for pending and
  settled clients; missing/stale contexts fail safely.
- [ ] Output transfers preserve translated floating state; desktop/Activity membership changes
  revoke ownership without automatic adoption on the destination.
- [ ] Window/owner destruction during callbacks and related-window closure are lifetime-safe.
Verification: existing removal/transfer controls plus context-generation and closure tests;
matched memory-check baseline with no new error contexts. Include a transfer between outputs
whose current desktops differ; transform the saved floating frame and release ownership once.
Dependencies: NT06A.
Files: KWin `src/tiles/tilemanager.cpp`, `src/workspace.cpp`, `src/virtualdesktops.cpp`,
`tiles_test.cpp`, `outputchanges_test.cpp` (maximum five; split if required).

## Checkpoint B
- [ ] Relevant native suites pass with zero unexpected failures/skips/blacklists.
- [ ] Independent review and lifetime checks cover the actual new source, not an old prototype.
- [ ] Native tracker capture/replay and window-owned asynchronous unload state are qualified.

## NT07 — Protect Fusion placement memory
- [ ] Automatic and pending-restoration rectangles never enter floating-placement memory,
  including close-before-restore and late tile commits.
- [ ] Native completion re-evaluates recording with the ordinary quiet-period/eligibility guards;
  a legitimate later manual move is recorded before close.
- [ ] Missing/incompatible native capability refuses adoption while ordinary stock placement
  continues unchanged. Before any automatic geometry, bind an acknowledged/read-back A snapshot
  to the current window identity/generation; refuse quiet, unsaved or ambiguous-key cases.
Verification: placement unit tests and matched isolated-session controls, including the prior
re-record control, P != A, failed/late acknowledgment, changed snapshot and incompatible-provider
cases; changed consumers checked in the beta lane. Prove persistence, not just in-memory state.
Use the native writer in qualified sessions, including destructor/close paths; no direct legacy
D-Bus fallback. Test provider retirement/replacement, global same-key conflicts across desktops
and Activities, deferred manual update followed by owner close **and** restoration completion,
then a genuinely later owner move, and non-representable A refusal. A failed flush must permit
provider replacement and ordinary restore of an unrelated valid key; only adoption stays blocked
until a successful retry and readback. Native event origin, not provider callback order, determines
whether the restored owner may record again.
Dependencies: Checkpoint B.
Files: Fusion placement `contents/ui/{main.qml,Placement.js}`,
`packages/kwin/tests/placement.test.js`, one isolated scenario, `docs/parts/kwin.md` (maximum five).

## NT08 — Qualify unload and restart preservation
- [ ] Orderly owner unload releases before roots are destroyed; no test process remains.
- [ ] Restart preserves manual-layout configuration and floating-placement data; newly mapped
  clients do not inherit automatic placement from persisted owner state. Start from persisted
  P != current A and exercise both orderly restart and an interrupted compositor.
- [ ] Run the complete one-window matrix from pinned sources; record unsupported cases and
  keep #115 open for the remaining tiler work.
Verification: isolated-session reload/restart comparison, full native/Fusion checks, review.
Dependencies: NT07.
Files: at most three isolated test/evidence files plus `docs/DEFERRED.md` and milestone report.

## Checkpoint C
- [ ] Native ownership, asynchronous restoration, transitions and persistence gates all pass.
- [ ] No settings UI, master/stack policy, host activation or public release was added implicitly.
- [ ] Owner reviews the milestone evidence before the next feature or deployment scope.
