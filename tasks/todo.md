<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# One-window native ownership proof

## Status and source snapshot

This status was checked on 2026-11-09 against the maintained
[`archledger/kwin` branch `plasma-fusion`](https://github.com/archledger/kwin/tree/plasma-fusion),
at [`a0635787`](https://github.com/archledger/kwin/commit/a0635787ff19cec11f411f7f0049d3b3f77f1041).
That source is based on KWin 6.8.2. The 6.7.5/6.7.91 commits, image identifiers and test counts
below remain historical evidence for their own baselines, not new results for this source.

- Private ownership, exact-A requests, configure provenance and the maximize-only NT03.5a
  precursor are present. The four recorded decoration prerequisites are also present: guarded
  settings reads, guarded window traversal, deferred reconfiguration and borrowed factory lifetime.
- Fullscreen/returning-decoration restoration, explicit restore-action routing, NT04 completion,
  the production placement-provider bridge and the complete tiling policy remain open. Private
  request helpers do not expose a usable production tiler; the existing release action is not
  the planned exact-A restoration route.
- The original startup-initializer correction is integrated as
  [`9c6fb381`](https://github.com/archledger/kwin/commit/9c6fb38101e03606ee0024aab7c4df6edbdb5dce).
  The earlier notes that describe it as a separate unmerged branch refer to that earlier state.
- The later [floating-client-size correction](https://github.com/archledger/kwin/pull/1) preserves
  client size on same-output decoration-border changes. It does not complete returning-decoration
  restoration. Its qualification retains a baseline-reproducible startup Memcheck read with an
  unresolved cause; the historical fixed-hash profiles below do not establish a globally clean run.

This snapshot describes source and recorded qualification, not the current installation on a
particular device. Continue from the unchecked milestones below. The earlier design sections
describe the approved contract; they are not evidence that every proposed interface exists.

## Earlier NT02 progress notes

NT01 through NT02.4b2b, NT02.5a1, NT02.5a2a and NT02.5a2b1 are complete.
NT02.5a2b2a (the immutable fence) and NT02.5a2b2b1 (guarded commit) are also complete.
NT02.5a2b2b2a (restore field) is complete. The guarded committed-geometry prerequisite
NT02.5a2b2b3a and requested-state/output synchronization at NT02.5a2b2b3b1 are complete.
Backend geometry requests at NT02.5a2b2b3b2, the owned transient-request routing at
NT02.5a2b2b2b1, owned maximize normalization at NT02.5a2b2b2b2, owned fullscreen
normalization at NT02.5a2b2b2b3, the membership revision at NT02.5a2b2d1 and the guarded
normalization prerequisite at NT02.5a2b2d2 are complete; the guarded Tile/association ingress
NT02.5a2b2d3 was refined after its design consult into the qualified cancellation preparation
NT02.5a2b2d3p (complete), the guarded requested-association step NT02.5a2b2d3a (complete) and the guarded Tile
membership steps with their public entry points NT02.5a2b2d3b (complete), then the compatibility consumption
and the X11 specialization. The startup-initializer fix is integrated into the native branch.
No production tiler is enabled.
The startup Memcheck diagnostics mentioned below are closed: the two uninitialized values are
fixed with regressions on the private branch `fix/startup-initialization`
(`136c04f435704ce5d9d1593ea35913862f2572bb`, not merged), and the remaining 16-byte read is
Qt 6.11.2's deliberate AES short-string hash over-read, which the lane now avoids with the
`QT_HASH_SEED=0` profile described in docs/parts/kwin.md. Neither changes the native commits.

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
NT02.5a2b2b3b2 is signed native commit `59ae3174f07292f9667489eb9f57cc9c497e263a`:
414 Xdg checks, 947 results across 14 selected suites and nine compiled controls passed.
Under the labelled Memcheck lane profile the five new request functions show only the two known
startup initializer contexts of the base, which `fix/startup-initialization` addresses; no Qt
hash over-read and no context in the new code. The private
guarded request allocates its generation before taking its own checkpoint, reserves every budget
before the first mutation, synchronizes through the shared 3b1 writer, dispatches through the Xdg
backend shared with the legacy path, and reports immediate publications and queued configures
separately. After the first mutation a failed step is Superseded, never a no-effect refusal.
Queued means staged for the coalesced configure, not sent or completed; client completion still
runs the ordinary commit path. Toplevels only; popups, X11, internal and layer-shell windows are
refused without effects. Maximize normalization, transient-request routing and controller
admission remain later leaves.
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
| NT02.5a2b2b3b2 — complete | Implement guarded Window/Xdg backend geometry requests, consuming synchronized state and the publication result for immediate updates; qualify queued branches separately from client completion. | Window header/source, Xdg header/source, Xdg test: at most five; after 3b1 |
| NT02.5a2b2b2b1 — complete | Route the private transient request through the guarded restore, inline association and owned geometry steps. Carry the borrowed request through every child step so an authority lapse without a counter change supersedes without refresh; validate the geometry result's checkpoint through the final notifications; reject known headroom and unsupported backends before any effect. | `window.h`, `window.cpp`, `waylandwindow.cpp`, `xdgshellwindow.cpp`, Xdg test: five |
| NT02.5a2b2b2b2 — complete | Owned maximize normalization: the probe showed no A-contamination on this path (transient tiles report Custom) but an ordinary maximize released ownership through exitQuickTileMode and left the record Restoring. Now the toplevel decides before the first callback whether it acts as the owner (live ownership-validity predicate incl. the window's current desktop and output, separate from admission feasibility; released axes must be able to return to the managed extent under the client's size limits; no recorded-rectangle fallback), emits, revalidates fence, ownership and the versioned requested mode, writes the mode, revalidates after each decoration signal, keeps the tile and the restore field, requests maximized axes from the area and released axes exactly from the managed rectangle frozen beforehand through an ownership-generation owned geometry entry, and publishes the mode as a guarded obligation; no legacy fallthrough after an owned mutation. Fullscreen remains separate. | `window.h`, `window.cpp`, `xdgshellwindow.h`, `xdgshellwindow.cpp`, Xdg test: five |
| NT02.5a2b2b2b3 — complete | Owned fullscreen normalization: the probe showed the fullscreen path stored the managed rectangle as its own restore but released ownership through the public move-resize. Now the toplevel decides before the first callback whether it acts as the owner (same ownership-validity predicate; entering, no client-requested output other than the ownership's; exiting, every non-maximized axis must be able to return to the managed extent, exact when no server decoration returns and settled exactly right after the decoration is configured otherwise, a validated dispatch after a prefix the legacy path shares, where an extent the restored decoration cannot return to with unchanged client size hints hands the exit to the legacy path and changed hints end the operation). Entering stores the rectangle an owned exit returns to (managed, or maximize-area extents on maximized axes) through a guarded versioned fullscreen-restore writer and requests the fullscreen area through the owned geometry entry; exiting returns to that frozen rectangle, never to the stored field. The requested state and the requested output are versioned separately; the state write's publication is a guarded obligation; the explicit untile-or-restore action releases an owned fullscreen window on its first press (routed to the owning layer, which leaves a requested fullscreen state, acknowledged or pending, as the owner and releases only if that exit completed as the current intent; lifetime-retained). X11 remains separate. | `window.h`, `window.cpp`, `xdgshellwindow.h`, `xdgshellwindow.cpp`, `useractions.cpp`, Xdg test: six |
| NT02.5a2b2c — 2c1, 2c2a, 2c2bp and 2c2b complete | Add X11 specialization with explicit immediate-commit provenance and guarded maximize/geometry behavior: 2c1 (complete) the guarded geometry request published synchronously as the request's own write and the association write's publication (the immediate tile commit) through a carrier passed by parameter, with both committed changes budgeted before any mutation, the X11 rows of every guarded function flipped from legacy to guarded; 2c2 (next) the X11 normalization of a maximized window, which 2c1 refuses at the preflight so the legacy remainder keeps tiling it. 2c2 was split after its design consult: 2c2a (in progress) qualifies the X11 normalization for the undecorated window (X11 override of the normalization step and its predicate; the mode revision on X11Window with one saturating writer; the complete geometry constraints frozen in the receipt; the publication as the mode write's obligation with revalidation between its callback stages and before the outcome is decided; decorated, borderless-policy, fullscreen and invalid-prospective-restore windows refused mutation-free) and corrects the stale backend comment in the membership ingress; 2c2b routes the decoration reactions (border changes, creation, destruction) through the operation and qualifies them on decorated fixtures. 2c2a complete (the undecorated window). 2c2b refined after its consult into 2c2bp (prerequisite: the pure workspace-position decision extracted from checkWorkspacePosition with the wrapper's write order kept; a decoration generation in Window and a policy revision in X11Window) and 2c2b (the recorder passed explicitly through private helpers, revalidation inside each callback-producing helper, no block on the owned path, the reactions folded in order into a planned rectangle with the supported sequences bounded, the receipt after the transition against the validated incarnation and the post-transition borders, the frame-extents obligation keyed to the incarnation, the quick-tile exclusion). | X11 header/source, necessary Window interface changes, Tiles test: at most five; refine before coding |
| NT02.5a2b2d1 — complete | Membership revision in the assignment fence: every actual tile membership change of a window (ordinary or transient) advances a per-window saturating revision before its notification; the otherwise-valid public no-ops (manage of an existing member, unmanage/forget of a non-member on an ordinary tile) record the same intent under a documented conservative rule; refusals and internal evacuation misses record nothing; the fence records and compares the revision and treats saturation as exhausted; the transient admission snapshots the revision after its membership add and treats a change across its publication as supersession; the release records its removal before publishing. Public bodies otherwise unchanged; public-path reentrancy is an explicit exclusion. | `window.h`, `window.cpp`, `tile.cpp`, `transienttilecontroller.cpp`, Tiles test: five |
| NT02.5a2b2d2 — complete | Guarded maximized-to-tiled normalization prerequisite for ordinary assignment (refined after the design consult): a private virtual `normalizeMaximizeForAssignment(fence, provenance)` whose base refuses without effect (unsupported backend; X11 selects the legacy path before any mutation) and whose Xdg override makes its own recorded writes and guarded child calls (never the public unmaximize), honours the maximize recursion guard, refuses mutation-free (owner or active request, unresizable, rule-forced maximize, interactive or electric-border operation, recursion, headroom for its restore write and geometry work), returns AppliedCurrent with a fresh checkpoint and no stamp when the requested mode is already Restore, emits the about-to-change signal as a boundary, writes the mode under a publication obligation, treats each decoration signal and the borderless reconfiguration as boundaries, captures the restore with the exact legacy formula (only the axes that were not maximized; skipped when a quick tile is already requested), requests the legacy geometry (valid restore: centred and clamped to the minimum; invalid: client-chosen size) through the guarded request, and returns a receipt whose validity every later step checks: a constraint-carrying provenance (the requested-mode revision and the frozen size limits, by value, chained onto the incoming provenance) that a mode-away-and-back cannot revive; a child refusal after the mode write is Superseded, never Refused. No cancellation, evacuation, association or cleanup inside it; AppliedCurrent is the synchronous request, not the client's acknowledgement. | `window.h`, `window.cpp`, `xdgshellwindow.h`, `xdgshellwindow.cpp`, Xdg test: five |
| NT02.5a2b2d3p — complete | Qualified cancellation preparation (prerequisite found by the 2d3 design consult): a private cancellation variant returning a step result whose checkpoint is taken after the cancellation's own callback-free writes (the placement advance; for an owner, the release's transient membership removal and association detachment) and validated after the release's notifications and finalization, threaded through the controller's Release and the window's own revoke path without counting increments; the release itself completes exactly as today and the legacy helper keeps its body and bool. Consumers stamp intent with it after their mutation-free rejections and use its checkpoint as their entry fence; a release that cannot finalize leaves the owner in place and the consumer's entry refusal selects the legacy path. | `window.h`, `window.cpp`, `tiles/transienttilecontroller.h`, `tiles/transienttilecontroller.cpp`, Tiles test: five |
| NT02.5a2b2d3a — complete | Guarded requested-association step with a read-only preflight (never a grant): refusals before any mutation (transient tile, backend without guarded requests so X11 selects the legacy sequence, transient owner or active request, interactive operation, and when tiling a maximized window the normalization's own refusal predicate through a new virtual the Xdg backend shares with its 2d2 step) and an aggregate headroom budget for the whole selected path (normalization with its geometry request, restore capture, association change, final geometry request and publication); an equal association is an operation-owned no-op without a stamp; otherwise an entry snapshot, the 2d2 normalization when needed (its refusal after a passed preflight is Superseded), the restore capture through the guarded writer when entering tiling from no association, the requested-tile write with its checkpoint, then the obligation discharged before the result is finalized: the backend's quick-tile protocol state, a recheck (live window, unchanged non-exhausted association revision, target identity with its original presence, transient-generation state), the notification, and a terminal validation; callbacks invalidating the operation make it Superseded although the write stands; the geometry through the guarded request (no interactive adjustment: interactive operations are refused). Public `Window::requestTile`/`forgetTile` keep their own cancellation semantics and establish their own operation: Refused selects the legacy body before any mutation, Superseded stops. | `window.h`, `window.cpp`, `xdgshellwindow.h`, `xdgshellwindow.cpp`, Tiles test: five |
| NT02.5a2b2d3b — complete | Guarded Tile membership steps and public entry points: private manage/unmanage/forget steps with the mutation-free rejections first (transient tile, unresizable or applet window, off-desktop window, the window's association preflight when the desktop is active, the aggregate budget including one membership increment per worklist entry plus the addition); an existing-member private no-op returns AppliedCurrent without a stamp; evacuation over a worklist collected first, the Window retained, the destination, manager, desktop and the active-versus-inactive decision frozen and validated after every removal and addition notification (a desktop switch, reparenting, a target geometry change or a manager teardown terminates the operation; a destroyed source is skipped only while the checkpoint still validates; a destroyed destination is Superseded, never read as explicit null); then the association step chaining the last checkpoint. Public `Tile::manage`/`unmanage`/`forget`: the mutation-free rejections, then the qualified cancellation (a valid manual intent revokes automatic ownership before publishing new membership: a new ordering, documented and tested), their own fence, the private step; Refused selects the legacy body; Superseded stops and `manage` returns false; the closed public reentrancy is qualified to the guarded paths, the X11 and interactive legacy branches staying unqualified. | `tiles/tile.h`, `tiles/tile.cpp`, `window.h`, `window.cpp`, Tiles test: five |
| NT02.5a2b2d4 — complete | Compatibility-setter consumption: `setTileCompatibility` uses the guarded ingress and cleans only the captured original membership when the ingress applied and is current (absent: nothing; removed and re-added by callbacks: the revision stops cleanup; destroyed: skipped, never replaced by the callback-selected tile); direct `Tile::manage` keeps independent per-desktop memberships. X11 keeps the legacy sequence, selected before any guarded mutation, until NT02.5a2b2c. | `window.cpp`, Tiles test, Xdg test if needed: at most five |
| NT02.5a2b3 — complete | Consume the qualified management receipt and guard original-membership cleanup; retained references and X11 refusal cannot bypass admission. Reconciled after its design consult: the original-membership cleanup wording came from the compatibility assignment, which the setter now performs under guard; the leaf qualifies the admission's existing native operation without broadening eligibility (ordinary memberships ineligible, X11 refused before any reservation), consumes a checkpoint with an admission-bound provenance through the controller-only publication and the native request, resolves the request-borrowing provenance's lifetime (retention through the validation interval or translation into a stable generation-bound provenance before the request's destruction), preflights the whole synchronous path with its failure cleanup, and releases generation-specifically on supersession; plan section "Transient admission receipt". The prerequisite NT02.5a2b3p (the qualified continuation) is implemented; its review's advisory (the TransientApplication comment naming the final geometry-result checkpoint) is taken in this leaf. | Controller source, Window header/source, Xdg and Tiles tests: five changed files; header retained unchanged in the qualification inventory |
| NT02.5b — complete | Qualify actual controller-owned release state at every notification for pending and committed admission; retain the cancellation checkpoint across logical close and verify the deferred writer update wins only after destruction. Add eight selective Qt-property cancellation rows while retaining the direct matrix. No implementation or public API change; state/token/completion properties remain NT04 work. | `xdgshellwindow_test.cpp` only |

Do not expose a production adoption entry point between these units or before NT07. If the
selected implementation needs more files than a leaf permits, split that leaf before coding.

## NT03 — Preserve floating state on explicit release
Approved specification: [NT03-RESTORATION-SPEC.md](../docs/NT03-RESTORATION-SPEC.md).
Implementation plan and this breakdown were approved on 2026-11-05. NT03.0 through NT03.4
and the private maximize-only NT03.5a precursor are complete within the scopes recorded below.
The remaining NT03.5 mode work and NT03.6 action routing are not complete.
The old four-file allocation is replaced by these bounded leaves. Detailed dependency rationale
and verification profiles W/X are in [the plan](plan.md#nt03-implementation-sequence).

### NT03.0 — Characterize old-buffer placement — complete
- [x] Record pending-admission, newer-resize and old-configure ACK/commit sequences with exact
  serial/content/frame/requested-state observations and ordinary unowned controls.
- [x] Review a content-versus-placement decision table; preserve unsafe baseline observations
  without blessing them as required behavior or discarding valid client buffers.
- [x] State any serial-wrap/matcher limitation and stop dependent implementation if unresolved.
Verification: bounded diagnostic patch in a disposable Xdg test copy; profile X and retained
trace/hash receipts. No production fix or permanent unsafe oracle.
Dependencies: NT02.5b and implementation-plan approval.
Files: `autotests/integration/xdgshellwindow_test.cpp` in the disposable copy; evidence/recipe.
Result: [eight-row observations and accepted policy](nt03-old-buffer-characterization.md).

### NT03.1 — Query exact restoring reservations — complete
- [x] Add a mutation-free writer query for exact owner UUID, generation and Restoring phase.
- [x] Reject wrong/old tuples without changing map, provider or reservation state.
- [x] Preserve existing Owned/ordinary semantics; the query itself grants no restoration.
Verification: profile W, negative tuple/phase cases and a compiled equality/phase control;
profile I rebuilds the real library/integration targets before the full campaign.
Dependencies: implementation-plan approval; independent of the NT03.0 content policy.
Files: `src/tiles/transientplacementwriter.{h,cpp}`, `autotests/test_transientplacementwriter.cpp`.

### NT03.2 — Claim and retain one explicit attempt — complete
- [x] Claim a non-reusable, exhaustion-checked attempt for the exact eligible Owned generation,
  binding immutable A, context and writer identity before callbacks; no geometry is sent yet.
- [x] Reject promotion of generic Restoring records; cancel on newer intent/close and keep the
  record through detach/finalization boundaries without a self-retaining checkpoint.
- [x] Refuse unsupported initial modes/context before mutation, with no public routing change.
Verification: profile X; duplicate/reentrant claim, NoRequest boundary, loss/cancellation and
retained-close cases; compiled identity/cancellation controls and scoped memory checks.
Dependencies: NT03.1.
Files: `src/window.{h,cpp}`, `autotests/integration/xdgshellwindow_test.cpp`.

### Checkpoint — Restore identity
- [x] Exact reservation, one-shot identity and lifetime cases pass and have independent review.
- [x] Existing generic release/cancellation semantics are preserved; no restore geometry or action
  routing has been enabled.

### NT03.3 — Request exact A through private restoration authority
- [x] Add distinct restoration provenance and private normal-mode dispatch; publish allocated
  geometry-request identity to retained state before callback-producing work.
- [x] Revalidate the same claim at every boundary; distinguish Staged, Published and superseded
  outcomes, preserving partial writes and the writer barrier without retry or fallback.
- [x] Prove A differs from B and mutable restore fields; preserve ordinary ownership guards.
Verification: profile X and the 18-suite campaign; exact-target, callback supersession, headroom,
duplicate and lifecycle controls plus scoped memory checks. No delayed-configure safety claim yet.
Completed: 30 request rows (32 checks), 39 claim checks, 3 private Activities checks, full Xdg
653 checks and 1,677 checks across the 18-suite campaign passed without failures or skips.
Three scoped Memcheck profiles (32/39/3) reported no errors, contexts or suppressions under
the existing QT_HASH_SEED=0, leak-check-disabled profile. Seven compiled mutations were caught,
including lower-entry reuse during callbacks and generation publication delayed until after
synchronization. The request remains private; stale-configure safety is NT03.4 and completion
is NT04. Evidence: shared `2026-11-05-issue115-restore-request` artifacts and `tests.json`.
Dependencies: NT03.2 and the NT03.0 content-policy decision checkpoint.
Files: `src/window.{h,cpp}`, `src/xdgshellwindow.{h,cpp}`,
`autotests/integration/xdgshellwindow_test.cpp` (maximum five).

### NT03.4 — Block obsolete configure placement authority
- [x] NT03.4a prerequisite: exact serial matching with chronological prefix consumption;
  qualify ordinary, unknown/ambiguous and wrap-valued wire ACKs in a three-file slice.
  Qualified 1,694 checks across 18 suites; memory profiles 12/6/5/32 and six compiled controls
  passed. Prefix/selected-object destruction is guarded against close, nested commit and
  counter exhaustion. The wire fixture does not wrap libwayland's internal serial allocator.
- [x] Bind the restore identity into configure processing before obsolete geometry can regain
  compositor position/requested-state authority; implement the reviewed content policy.
- [x] Cover old admission/restore commits after new manual intent, including actual serial wrap;
  retain valid client-content processing and never finalize the reservation here.
- [x] Split any extra matcher/helper work before exceeding the source-file bound.
Verification: profile X and the 18-suite campaign; old-buffer, old-serial, wrap and no-ACK cases;
compiled missing-provenance controls and scoped memory checks.
Completed within the private normal-mode/fixed-context scope: 1,735 checks across 18 suites,
711 full-Xdg checks, five memory profiles (29/10/8/6/32) with no errors/contexts/suppressions,
and eleven compiled controls. Protected admission and restore wire cases cross MAX to zero;
the libwayland allocator itself is not advanced through wrap. Evidence is in the shared
`2026-11-05-issue115-configure-provenance` artifacts and `tests.json`.
Dependencies: NT03.0 decision table and NT03.3.
Files: `src/window.{h,cpp}`, `src/xdgshellwindow.{h,cpp}`,
`autotests/integration/xdgshellwindow_test.cpp` (maximum five).

### Checkpoint — Private request safety
- [x] Exact-A dispatch, stale-configure protection and newer-intent safety pass and are reviewed.
- [x] All paths remain private; no action routing, completion notification or barrier release.

### NT03.5 — Normalize owned modes without losing A
- [x] NT03.5a: private maximize-only normalization to A, with explicit stages and backend state
  binding; existing CSD/SSD only, fullscreen/borderless/returning-decoration paths refused.
  Qualified 1,777 checks across 18 suites, 753 full-Xdg checks, five memory profiles
  (43/3/32/39/3) with zero errors/contexts/suppressions and twelve compiled controls.
  Actual old maximize content, post-write publication, late intent and phase barriers are
  covered. Fullscreen and returning-decoration normalization remain unqualified.
- [x] Returning-decoration prerequisite: guard same-instance decoration settings reads against
  nested updates and destruction; keep each signal's payload stable. This does not complete
  bridge configuration, factory lifetime, decoration publication or restoration integration.
  Qualified 1,783 checks across 18 suites, two memory profiles (7/3) with zero reported errors
  and eight compiled controls; source, delta and final evidence reviews cleared this scope.
- [x] Returning-decoration prerequisite: recreate decorations over a callback-free snapshot of
  guarded windows, skip members deleted during the pass and hold the visited window through
  its callback. Collection and lifetime safety only; configuration authority, plugin-creation
  failures, factory ownership and restoration enablement stay open. Qualified 1,790 checks
  across 18 suites with seven traversal rows, one memory profile with zero reported errors,
  three compiled controls and a per-row legacy probe; reviews cleared this scope.
- [x] Returning-decoration prerequisite: defer a configuration change that a decoration plugin
  requests while the bridge loads a plugin, creates a decoration or recreates decorations, and
  apply the newest configuration with one queued follow-up once the outermost operation has
  unwound; changes at idle stay synchronous. Configuration reentry only; plugin-creation
  failures, factory ownership, unpublished decoration handoff and restoration enablement stay
  open. Qualified 1,795 checks across 18 suites with five reentry rows, one memory profile with
  zero reported errors and three compiled controls; on the unmodified bridge three rows kept a
  stale decoration and one crashed. Reviews cleared this scope.
- [x] Returning-decoration prerequisite: the bridge borrows the decoration plugin's factory
  (the plugin library's shared Qt root object) instead of deleting it on switch, disable or
  destruction; a factory destroyed elsewhere reads as no plugin until the next reconfiguration
  reloads it. Ownership only; null or failed creation, staged publication, Window handoff and
  restoration enablement stay open. Qualified 1,799 checks across 18 suites with four factory
  rows, one memory profile with zero reported errors and four compiled controls; on the
  unmodified bridge one row failed, one crashed on the deleted factory and two failed and then
  crashed at exit. Reviews cleared this scope.
- [x] NT03.5b: fullscreen and returning-decoration normalization under the explicit attempt
  (fork PR #8, squash 83ff56225f). An owned fullscreen window — pending, committed, combined with
  a maximize, or with a returning server or shadow decoration — restores to the captured floating
  frame A: the exit writes the requested state with its own publication obligation, clears the
  requested output as the owned and legacy exits do, re-seals the captured state around the
  decoration boundary, and routes a returning bordered decoration to the necessary extent checks,
  sealing the exact frame once configured. Movability and resizability are judged for the state
  after the mode write (the plain predicates refuse while fullscreen is merely requested); the
  dispatch gate refuses the requested state only, the committed state following the client's
  acknowledgement. Rules keeping fullscreen, an unfullscreenable window, or exhausted writers
  refuse the claim mutation-free. Qualified by a four-run chain on the fork (the intended-RED
  receipt, the implementation, the combined-mode and old-content rows, and the review-fix run;
  each of the last three an 18-suite campaign), an independent no-blocker review with all six
  findings fixed and re-verified, and new rows for pending/committed/SSD-returning/constraint
  refusals, the combined mode, the old-fullscreen-content replay and the named-output clear.
- [ ] Fullscreen supersession rows during the exit (a newer intent at each boundary of the
  fullscreen block specifically) and the later coverage rows: rules-driven refusal, a shadow
  fixture, an SSD combined mode, a client-named other output (two-output fixture).
- [ ] Complete obligations for writes already made; stop superseded paths without legacy fallthrough.
- [ ] Keep current owned mode and unowned controls passing; split mode-specific work if needed.
Verification: profile X and the 18-suite campaign; pending/committed mode, decoration, constraint,
callback-close and exact-A cases; mode/currentness controls and scoped memory checks.
Dependencies: NT03.4 request-safety checkpoint.
Files: `src/window.{h,cpp}`, `src/xdgshellwindow.{h,cpp}`,
`autotests/integration/xdgshellwindow_test.cpp` (maximum five).

### NT03.6 — Consume explicit restore actions safely
- [x] Route the qualified restore from explicit action dispatch (fork PR #10, squash 67adca155e):
  the untile-or-restore action on a record-holding window consumes as one qualified restoration
  attempt through the mode-capable claim, with a five-value consumption — not-owned keeps the
  ordinary ladder, started dispatches the captured floating frame, stopped retains the writes of
  a superseded prefix, in-flight consumes a duplicate without another attempt or legacy
  fallthrough, and no-start consumes an unsupported state with the ownership, geometry and modes
  unchanged. The orphaned release virtual the dispatcher replaced (no remaining caller) is
  deleted; the addressed window stays raised and focused as before. Qualified by two green fork
  campaigns (implementation head 2313ed948c, review-fix head 7d3fae3b5f), an independent
  approve-with-required-changes review fully addressed, and locally green XdgShellWindow,
  QuickTiling, Maximized and Tiles suites — the unowned ladder is unchanged text.
- [x] Consume in-flight/Restoring duplicates without another generation or ordinary fallthrough
  (the duplicate row pins the attempt sequence, the request generation and the absence of any
  new configure); generic manual revocation and teardown stay detach-only (the consumption fires
  only from the explicit action).
- [ ] Verify real action dispatch and newer manual intent — the dispatch rows cover the real
  `UntileOrRestoreOp`, duplicates, the unowned ladder, close (testOwnedFullScreen scenario 9,
  unchanged and green) and newer fullscreen intents at the dispatch boundaries; a dispatch-level
  manual-move row and the four later coverage rows remain, and the per-leaf Memcheck profiles
  for this and the NT03.5 slice are owed (the fork's weekly Memcheck on merged main covers the
  merged code in the interim). No provider, QML state API or production admission path is
  enabled.
Verification: profile X and the 18-suite campaign; real `UntileOrRestoreOp`, duplicate/reentrant,
unowned control, mode/close and stale callback cases; dispatch controls and scoped memory checks.
Dependencies: NT03.5.
Files: `src/window.{h,cpp}`, `src/xdgshellwindow.cpp`, `src/useractions.cpp`,
`autotests/integration/xdgshellwindow_test.cpp` (maximum five).

## Checkpoint A
- [ ] Baseline and candidate identities, native tests and static checks are recorded.
- [ ] Independent review finds no unresolved ownership, serialization or lifetime blocker.
- [ ] Integrated exact-A, mode, duplicate, stale-configure, close and ordinary-control proof passes;
  never-ACK remains pending, with no geometry-equality/timer completion shortcut.
- [ ] Required source groups are privately signed and archived; NT04 finalization remains separate.

## NT04 — Resolve asynchronous restoration
- [x] NT04a: the completion boundary (fork PR #11, squash e32f77f946; proof arms PR #12, squash
  8fffbae906). The acknowledged configure of the live restoration, committed by the client, is
  the only completion - the origin's kind, geometry generation, ownership generation and restore
  sequence must all be current, exactly mirroring the placement-authority policy. A cancelled
  attempt, a superseded request or an older configure's late acknowledgement never finalizes
  anything; the boundary clears the restoring record with its attempt, completes the writer's
  reservation (deferred record applied, restore watermark installed at the newest tracked
  sequence, per-key barrier released) and keeps the close cleanup connected so the watermark
  suppresses stale provider events until the window is destroyed. A configure-less (published,
  position-only) restoration records its shape at dispatch and settles on the client's next
  commit. Qualified by fail-first rows (the reservation-survives flip across four suites), the
  new completion suite (qualifying commit, never-ack, superseded, cancelled, barrier released,
  published position-only, controller destroyed before the acknowledgement, key released for a
  second window), two green campaigns per head, an independent no-blocker review with every
  finding fixed (the watermark-keep correction among them), a Codex finding fixed with its
  configure-less gap closed, and clean per-leaf Memcheck profiles for the three touched suites
  (artifacts/plasma-fusion/2026-11-11-nt035-nt036-memcheck-profiles, runs nt04-v1-*). The
  wrap-composition row is deferred with rationale: the in-order matching is proven at the wrap
  boundary and the boundary consumes the matched event's origin, never the serial value.
- [ ] Export the reviewed read-only state/completion contract; no raw protocol logger or timeout
  substitutes for native state. The record survives root/policy-module unload; reload cannot
  supersede it and an unresponsive client remains suppressed until completion or close.
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
