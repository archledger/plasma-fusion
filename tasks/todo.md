<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# One-window native ownership proof

NT01 through NT02.4b2b, NT02.5a1, NT02.5a2a and NT02.5a2b1 are complete.
NT02.5a2b2a (the immutable fence) and NT02.5a2b2b1 (guarded commit) are also complete.
NT02.5a2b2b2a (restore field) is complete. The guarded committed-geometry prerequisite
NT02.5a2b2b3a and requested-state/output synchronization at NT02.5a2b2b3b1 are complete.
Backend geometry requests at NT02.5a2b2b3b2 are next, before maximize normalization.
No production tiler is enabled.

NT02.1 is signed native commit `9d7d5c18fbe56c6dc212f4799469ba897a8c168c`: 23 writer
Qt results, five compiled mutation controls, full KWin library linking and 448 selected core
regressions passed. Independent review is clear. The writer has no live desktop instance.
NT02.2 is signed native commit `1f766a12369b20d22e4dc59cab508a2fbd8d324a`: 31 tile
checks, 488 results across 12 freshly built suites, and three compiled guard-removal controls
passed. Independent review is clear. Public transient membership calls fail closed until the
controller routes them safely; no transient node is exposed to desktop callers.
NT02.3a is signed native commit `0c301ae3e6aef34ec1ec8877fd55882bed795ab1`: 69 tile checks,
526 results across the selected 12 suites, and two compiled generation/reentry controls passed.
Static review is clear. This establishes empty-tree authority only, not window admission.
NT02.3b1 is signed native commit `18de7379804172e945c5856f82d1241f4bb41707`: 36 writer
checks, 539 selected regression results, and three compiled guard controls passed. Review is
clear. Prepared reservations can be cancelled without pretending that restoration occurred.
NT02.3b2.1 is signed native commit `e6ec2d49c5ff1eea37666f4b84e867eea5d9a704`:
87 Xdg checks, 610 results across 14 selected suites, and three compiled controls passed.
Review is clear. Native request/commit callbacks are guarded, but transient admission is not enabled.
NT02.3b2.2 is signed native commit `218181ba258e21416c53875848483166e8c7dc95`:
117 Xdg checks, 640 selected regression results, four compiled mutation controls and private-access
compiler probes passed. Review is clear. The private request receipt does not enable admission.
NT02.3b2.3a is signed native commit `20e1946ef1c47a1a4156b8ff04322ad1c15f50ec`:
118 Xdg checks, 641 selected regression results and proof-access compiler probes passed.
Window-issued NoRequest evidence is opaque and bound to strictly increasing ownership history.
NT02.3b2.3b is signed native commit `af615955314f1af4902a3a8f69e03ad7713fd330`:
132 Xdg checks, 655 results across the 14 selected suites and six compiled mutation controls
passed. Review is clear, including the tracked-owner coverage correction. The finalizer consumes
native proof once; actual controller admission is not part of this leaf.
NT02.3b2.4a is signed native commit `20be704c9d0bc24bc23e46bdd3b51ccda22c2133`:
150 Xdg checks, 673 results across 14 selected suites and seven compiled mutation controls
passed. The Window-owned record retains immutable state and sticky native progress, with one
shared NoRequest proof. Review is clear. Controller membership is not yet wired.
NT02.3b2.4b1 is signed native commit `72272fe5bdfda82be6eb196d4a948bbe52d1a2d6`:
155 Xdg checks, 678 results across 14 selected suites and seven compiled mutation controls
passed. Association-bound configure provenance survives Tile deletion and rejects stale commits
without erasing another association. Review is clear; physical restoration remains unqualified.
NT02.3b2.4b2 is signed native commit `f0c8c63c2e705bae643055718b1347907b412782`:
185 Xdg checks, 708 results across 14 selected suites and nine compiled controls passed.
Writer-qualified internal admission and guarded structural detachment are implemented; pending
records survive teardown. Review is clear. Public release routing, Workspace integration and
actual restoration remain later work.
NT02.3c is signed native commit `923cc849af85b719937d77d45a82922e96883a57`:
196 Xdg checks, 719 results across 14 selected suites and seven compiled controls passed.
Public transient unmanage/forget now route through a guarded generation-bound controller call.
Removal does not claim restoration completion. Review is clear; ordinary Tile behavior is unchanged.
NT02.4a is signed native commit `d31c0bb80992570f97ba87cdb3f20e64d092027b`:
209 Xdg checks, 732 results across 14 selected suites and seven compiled controls passed.
The weak active/retired registry supports native lookup and callback-safe draining without
changing manual layout storage. Review is clear; Workspace ownership is not yet integrated.
NT02.4b1 is signed native commit `5b9f749503f05004a65ee3eeeed15be95f261aa7`:
220 Xdg checks, 743 results across 14 selected suites and nine compiled controls passed.
Workspace now owns an idle controller, closes registration before shutdown callbacks and
reclaims guarded managers before outputs. Missing-manager consumers and callback-selected
placement are covered. Review is clear; output reconciliation remains NT02.4b2.
NT02.4b2a is signed native commit `a4eeaba545ea77c76cea3e73a98538b0b5daf7bc`:
231 Xdg checks, 754 results across 14 selected suites and eight compiled controls passed.
Output updates now retain pending work and use held identities and captured pass inputs.
Caller-side backend snapshots survive bookkeeping. Review is clear; batch draining and guarded
Workspace evacuation/continuations remain NT02.4b2b.
NT02.4b2b is signed native commit `c498fa2d8bfeded63376b682a4f29318f88b09e8`:
243 Xdg checks, 766 results across 14 selected suites and seven compiled controls passed.
Removed contexts drain before output notification. Guarded Window/tile snapshots preserve
continuations, newer callback placement and valid multi-desktop migration. Review is clear;
compatibility-entry-point checks, restoration and the real provider bridge remain later work.
NT02.5a1 is signed native commit `7f48df9b95a07e326c997e038e7a426917716a5e`:
75 Tiles checks, 772 results across 14 selected suites and two compiled controls passed.
Refused compatibility destinations preserve the previous manual assignment; successful
cross-desktop and null assignments remain unchanged. Review is clear. Callback lifetime,
newer-intent protection and actual owned-state coverage remain NT02.5a2/b.
NT02.5a2a is signed native commit `82baba9decab2228a1303cbfd360eafe8295b401`:
267 Xdg checks, 796 results across 14 selected suites and four compiled controls passed.
Cancellation continuations now reject newer intent and target destruction with guarded lifetime.
Removing the helper hold produces the intended freed-Window read under Memcheck. Candidate and
startup control retain unresolved startup diagnostics; no globally clean memory gate is claimed.
Review is clear within this boundary. Post-management cleanup remains NT02.5a2b.
NT02.5a2b1 is signed native commit `0e2d1e412d040d1580880ed27af29cf8a6206813`:
79 Tiles checks and 800 results across 14 selected suites passed. Matched Memcheck runs
with the same test binary remove the three sampled freed-previous-Tile contexts; unrelated
startup diagnostics remain. Review is clear for this lifetime-only fix. Native-operation
provenance and newer-intent-safe cleanup remain NT02.5a2b2/b3.
NT02.5a2b2a is signed native commit `7ecc7e48bb6d28ad5fc3d13152f9f6adf9e298e3`:
288 Xdg checks, 821 results across 14 selected suites and six compiled controls passed.
The private immutable fence retains Window lifetime and validates captured versioned state;
it grants no mutation authority. Its guarded commit-step consumer is recorded below. Review is clear.
Membership ingress, native-step provenance and compatibility-setter receipt consumption remain later.
NT02.5a2b2b1 is signed native commit `2f49932725e8af61a281d8fc35a210744c2fd5a7`:
313 Xdg checks, 846 results across 14 selected suites and nine compiled controls passed.
The private commit writer returns a current checkpoint only after both notification boundaries.
Refusal, saturation, null/no-op behavior, borrowed-input lifetime and legacy behavior are covered.
The reordered-target control produces a specific freed-target read under Memcheck; candidate
startup diagnostics remain unresolved. No request/geometry or compatibility integration exists.
NT02.5a2b2b2a is signed native commit `0d1e0b99117e53575d792732e3e36e37d38cf971`:
335 Xdg checks, 868 results across 14 selected suites and nine compiled controls passed.
The shared restore-field writer versions actual changes before notification without cancelling
ownership or requesting geometry; no-ops and invalid/empty sentinels retain their semantics.
Private results now share AssignmentStepResult/Outcome names. Full normalization remains later.
NT02.5a2b2b3a is signed native commit `776ce4da5e02e47feaf31cdce7a38561e49faf5a`:
361 Xdg checks, 894 results across 14 selected suites and nine compiled controls passed.
The shared committed-geometry publisher guards entry, output lifetime and each notification;
explicit pending-only drains take a new publication generation. Actual legacy output changes
are versioned, closing an output-roundtrip gap reproduced before the fix. This is not a geometry
request or client-completion guarantee. Startup memory diagnostics remain unresolved.
NT02.5a2b2b3b1 is signed native commit `a0cb13a7c8888062edb28e96946cacd55ae7c699`:
384 Xdg checks, 917 results across 14 selected suites and nine compiled controls passed.
Frozen requested-state/output synchronization now has exact headroom, per-write checkpoints,
versioned pending transitions and refusal of active transient ownership. The pending-only nested
completion case is isolated. This does not allocate request identity or dispatch backend geometry.
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
- [x] Native lookup finds that owner without adding it to manual serialization or picking.
- [x] The test control without transient lookup fails; candidate and ordinary tile controls pass.
Verification: focused `testTiles` cases, a refusal table for each predicate, non-mutation
snapshots, manual-tree/config comparisons and native suite. Native fixtures do not prove disk sync.
Dependencies: NT01.

Run these leaf units in order, not as one large change. Each has focused tests in the same unit:

| Unit | Outcome and acceptance | Source-file bound |
|---|---|---|
| NT02.1 — complete | Native writer primitive uses the existing file; incarnation/revision rejection, map-versus-persisted revisions, sync/readback failure and same-key priority at both close and completion pass real temporary-file tests. Provider replacement gets the dirty map without granting admission. No QML provider or adoption is enabled. | New writer header/source, source CMake, unit-test source and its CMake: five |
| NT02.2 — complete | Immutable transient kind and public mutation guards reject direct manage/geometry/resize changes; ordinary Tile behavior is unchanged. | `tile.h`, `tile.cpp`, `tiles_test.cpp`: three |
| NT02.3a — complete | Controller creates and owns an empty transient root/leaf; only generation-bound private operations may change its geometry. Stale requests and reentrant clear/context destruction stop further notifications. No window can be attached yet. | New controller header/source, source CMake, `tiles_test.cpp`: four |
| NT02.3b1 — complete | Add a prepared/owned reservation handoff: verify the expected key, provider incarnation/revision and uniqueness at activation; permit cancellation only before ownership; retain legitimate deferred updates on cancellation. | Writer header/source and writer test: three |
| NT02.3b2.1 — complete | Native geometry operations stop superseded continuations and survive callback closure; cover immediate and queued resize paths, nested partial requests, and committed-geometry notifications. | `window.h`, `window.cpp`, `xdgshellwindow.cpp`, `waylandwindow.cpp`, existing integration test: five |
| NT02.3b2.2 — complete | Add a private transient-request transaction with sticky request progress and authoritative Xdg pending-state inspection. Reject unsupported or stale admission before mutation. | `window.h/.cpp`, `xdgshellwindow.h/.cpp`, existing integration test: five |
| NT02.3b2.3a — complete | Mint an opaque, noncopyable NoRequest proof from the native Window receipt. Bind Window identity, canonical owner generation and native attempt; reject proofs after a newer private attempt or during close. No writer mutation yet. | `window.h/.cpp`, writer header, existing integration test: four |
| NT02.3b2.3b — complete | Consume that proof once to finalize the exact Owned/Restoring reservation without a synthetic restore event. Preserve close suppression and deferred-update ordering; test with real Window receipts. | Writer header/source, integration test and its source linkage: four |
| NT02.3b2.4a — complete | Establish the Window-owned reservation/attempt record, non-reusable generation allocation, synchronous provider validation and activated-before-request NoRequest proof. Publish sticky progress before geometry; preserve failures and close suppression. Link integration tests to the single native writer. No controller membership yet. | `window.h/.cpp`, writer header, integration CMake and Xdg test: five |
| NT02.3b2.4b1 — complete | Preserve transient ownership provenance in outgoing native configure state and reject stale tile commits even after the Tile QPointer becomes null. Ordinary native commits remain unchanged; no controller admission yet. | `window.h/.cpp`, `xdgshellwindow.h/.cpp`, Xdg test: five |
| NT02.3b2.4b2 — complete | Add writer-qualified controller admission and two-phase guarded membership/detach using the surviving Window record and immutable snapshot. | Controller header/source, `window.h/.cpp`, Xdg test: five |
| NT02.3c — complete | Route public transient unmanage/forget into generation-checked controller release; no ambient authorization flag, and callbacks cannot resume an obsolete mutation. | `tile.h`, `tile.cpp`, controller source, Xdg integration test: four |
| NT02.4a — complete | Index controller-owned transient roots weakly in TileManager; use actual membership for lookup/forget, unregister by exact identity, and drain before desktop/manager teardown without changing manual serialization/picking. | TileManager header/source, controller source, Xdg integration test: four |
| NT02.4b1 — complete | Workspace owns the idle controller; use guarded manager indexing with one QObject owner, close registration for shutdown, and safely reclaim or reconcile missing managers. Missing-manager consumers refuse tiling without accidentally releasing placement. | Workspace header/source, Window source, scripting wrapper source and Xdg integration test: five |
| NT02.4b2a — complete | Serialize output reconciliation with a retained pending pass and freeze input values while retaining backend/logical output and captured Window lifetimes. | Workspace header/source and Xdg integration test: three |
| NT02.4b2b — complete | Close all removed registrations before draining; guard ordinary evacuation and Workspace window continuations through output removal. | Workspace header/source and Xdg integration test: three (two needed) |
| NT02.5a1 — complete | Refused compatibility destinations preserve the previous manual membership, requested state and geometry; retain successful active/inactive-desktop and explicit-null behavior. | `window.cpp`, `tiles_test.cpp`: two |
| NT02.5a2a — complete | Guard the compatibility continuation after cancellation against Window/target destruction, newer cancellation or geometry intent, and committed-only changes. Use actual pending/committed ownership fixtures. | `window.h`, `window.cpp`, `xdgshellwindow_test.cpp`: three |
| NT02.5a2b1 — complete | Guard the captured previous Tile against destruction after target management; preserve successful legacy cleanup. This is lifetime protection only, not newer-intent qualification. | `window.cpp`, `tiles_test.cpp`: two |
| NT02.5a2b2a — complete | Establish an immutable, noncopyable Window-bound lifetime/revision fence with a private factory, saturated-counter refusal and original-association presence flags. Observation only: no mutation grants or setter integration. | `window.h`, `window.cpp`, `xdgshellwindow_test.cpp`: three |
| NT02.5a2b2b1 — complete | Implement a private guarded committed-association step. Validate the input fence and requested target, reject would-exhaust changes, capture output before notifications, and return Refused/Superseded/AppliedCurrent without changing legacy commits. | `window.h`, `window.cpp`, `xdgshellwindow_test.cpp`: three |
| NT02.5a2b2b2a — complete | Implement a private guarded geometry-restore field step. Version actual legacy/private changes before notification, preserve no-op/sentinel semantics, and never cancel ownership or request geometry from the storage setter. | `window.h`, `window.cpp`, `xdgshellwindow_test.cpp`: three |
| NT02.5a2b2b3a — complete | Guard Wayland committed client/frame/buffer/output publication, including explicit pending-notification drain, callback supersession and output lifetime. Version actual legacy output changes to detect round trips. This is not a geometry request or client completion. | `window.h/.cpp`, `waylandwindow.h/.cpp`, Xdg test: five |
| NT02.5a2b2b3b1 — complete | Guard requested-rectangle/output-property synchronization with frozen output values, exact headroom and callback checks; retain pending obligations without cancelling ownership or inventing request identity. Prepare narrow Xdg access to the publication helper. | `window.h/.cpp`, `waylandwindow.h`, Xdg test: four |
| NT02.5a2b2b3b2 | Implement guarded Window/Xdg backend geometry requests, consuming synchronized state and the publication result for immediate updates; qualify queued branches separately from client completion. | Window header/source, Xdg header/source, Xdg test: at most five; after 3b1 |
| NT02.5a2b2b2b | Implement explicit owned Window/Xdg request and normalization steps using the completed field and geometry primitives. Validate before mutation and reject foreign activity without refresh. | Window header/source, Xdg header/source, Xdg test: at most five; after 3b |
| NT02.5a2b2c | Add X11 specialization with explicit immediate-commit provenance and guarded maximize/geometry behavior. | X11 header/source, necessary Window interface changes, Tiles test: at most five; refine before coding |
| NT02.5a2b2d | Add guarded Tile membership/ingress and original-membership cleanup. Public reentrant calls inherit no token; relevant membership no-ops supersede the older operation. | Tile header/source, necessary Window plumbing, Tiles test: at most five; refine before coding |
| NT02.5a2b3 | Consume the qualified management receipt and guard original-membership cleanup; retained references and X11 refusal cannot bypass admission. | Bound after NT02.5a2b2 establishes the actual native operation |
| NT02.5b | Use the actual controller-owned Xdg fixture to verify release ordering, cancellation supersession and retained state. New public state/token/completion properties remain NT04 work. | `window.h`, `window.cpp`, `xdgshellwindow_test.cpp`: three |

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
