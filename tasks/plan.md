<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Native ownership proof for custom KWin

Status: the owner approved continuation of this first-milestone plan on 2026-11-02.
NT01 through NT02.3b2.3b are complete; NT02.3b2.4 is next.
The [scope](../docs/NATIVE-TILING-SPEC.md) does not enable the tiler.

### Proven NoRequest finalization

Split proof issuance from writer consumption so neither leaf needs a broad cross-module diff.
Window alone mints an opaque, noncopyable proof attached to a genuine private receipt that has
NoRequest progress. A valid private attempt gets its native sequence before eligibility checks,
so native rejection can also prove that no automatic geometry request was issued. Nested,
wrong-window, closed or exhausted attempts cannot mint usable proof.

The proof binds the Window UUID, ownership generation (canonical decimal text at the writer
boundary), and native private-attempt sequence. It holds a Window-generated read-only validity
check using a guarded Window reference. Closure is checked from native deletion state, not the
delivery order of `closed` handlers. A newer private attempt invalidates an older proof; ordinary
manual geometry does not. Shared proof handles share one consumed bit, preventing replay.
Window also retains the last consumed ownership generation for its entire lifetime. A new native
attempt must have a strictly greater ownership generation; an equal or older generation gets no
proof and cannot replace the earlier attempt's Requested history. This survives controller
replacement. Test Requested followed by a same-generation rejected attempt explicitly.

The writer accepts proof only for the matching Owned or Restoring reservation. It must reject
null, replayed, superseded and closing-window proof without releasing the key. Prepared still
uses ordinary cancellation. Successful finalization applies the latest valid deferred update,
preserves per-key ordering and clears the reservation without adding a restoration watermark
or writing a synthetic completion event. A failed application leaves proof unconsumed.
Manual revocation must move the writer to Restoring before a callback records the user's new
geometry; Owned deliberately suppresses such writes. Test this ordering in a real restore-field
callback before consuming NoRequest proof. The finalizer must not reconstruct an update that was
incorrectly submitted while still Owned. Production dispatch wiring remains a later gate.

Keep the proof carrier in the lightweight writer header with a private Window-only constructor;
Window's header uses a forward declaration and an opaque shared handle. The proof is not QML
registered or caller-populated. Integration tests create real native receipts; their target may
compile the writer source just as the existing standalone writer suite does, without exporting
a new public writer ABI solely for testing. Both leaves retain full native linking/regressions.

### Native geometry boundary before admission

The next integration touches Window and Wayland request ordering, so split it before coding.
First protect ordinary native geometry operations from stale reentrant continuations. Use a
monotonic request generation for each move/resize intent, including equal rectangles, and retain
the Window for the duration of the call. Check deletion and request generation after synchronous
callbacks and before the outer request continues. A newer nested partial move/resize must carry
the whole currently requested rectangle, including any size or position it inherited from the
outer request, rather than dropping that pending part when the outer continuation stops.
Track specifically whether that resize still awaits native submission. Xdg clears this flag
immediately before applying or queueing it, with no intervening callback. Promote a nested Move
only while that flag is set, not merely because requested and committed sizes differ. Ordinary
Moves during an already queued resize retain their existing behavior.

Committed geometry notifications need a distinct update generation: a nested queued request
must not suppress notifications for a frame that really changed. Advance that generation only
when client, frame or buffer geometry changes; stop old notifications if a newer committed update
or closure occurred. Preserve the earliest undelivered old value for each notification in shared
per-window pending state. A nested committed update inherits those pending notifications, so an
output A-to-B transition is still announced if a buffer callback moves the window again within B.
Clear each pending field before emitting its signal; drop net-zero undelivered changes.

Hold the Window through the enclosing Xdg commit dispatch as well as explicit requests. Check
deletion after callback-producing steps before accessing protocol or configure state again.
Counter exhaustion refuses a new operation rather than reusing an identity. Cover nested
same-rectangle intent, unsubmitted versus already-queued resize, immediate placement, queued
resize, output notification handoff, and closure during requests and actual client commits.

This geometry-safety leaf does not admit transient windows. The next leaf adds the private native
transaction receipt and authoritative Xdg pending-state inspection. That receipt distinguishes
superseded ownership from whether any requested geometry changed. A following writer leaf
allows only proven no-request finalization, including an already-revoked Restoring generation;
close still retains suppression through QObject destruction. Only then wire actual admission
and its persistent restoration record. No public authorization flag or callback may grant a
transient request; test access must not become a production admission bypass.

### Private native request boundary

NT02.3b2.2 adds a private Window request path callable only by the controller and trusted native
tests. A sealed, noncopyable request object binds the Window, transient Tile, ownership generation
and controller validity check; it has no public constructor or QML exposure. The validity check
is read-only and must not enter an event loop. Existing public `requestTile` rejects a transient
destination, so policy code cannot bypass this path.
The helper takes unique ownership of the request for the entire call. Its controller reference
is guarded; controller destruction cannot destroy the checker while Window is using it. Only
one private request may be active per Window. Nested private entry is rejected without replacing
the outer request; ordinary nested native actions remain permitted.

Window returns a receipt separating outcome from sticky progress: rejected/superseded/applied,
and no automatic request/the automatic geometry-request path entered. Progress becomes Requested
immediately before this request's first `setMoveResizeGeometry`, not after `moveResize` returns.
It remains Requested even for an equal rectangle, or if a callback supersedes or closes the window.
Public geometry/tile intent, including equal/no-op untile intent, cancels the in-flight authority.
Nested ordinary geometry remains
allowed; the old transient continuation must stop without blocking that newer operation.
Cancellation precedes relevant public early returns in geometry, tile, compatibility, forget
and quick-tile actions. The automatic exemption is passed to the exact native geometry call,
never inferred from an ambient flag. On supersession, clear only a requested Tile installed by
this attempt and still equal to it; do not undo newer geometry, restore fields or another Tile.

Before mutation, Xdg checks its actual configure timer, queue, acknowledged configure/serial and
pending commit state, rather than inferring readiness from rectangle equality. Restrict this
first path to a live ordinary movable/resizable Wayland toplevel, no existing requested/committed
tile, maximize, fullscreen or interactive operation, and an unchanged floating snapshot. Check
the resulting padded target against both size-constraint axes and frame/client snapping. Refuse
unsupported clients, infeasible targets or stale controller authority without requesting geometry.
Initial preflight and continuation checks are distinct: continuation allows this attempt's own
requested association/configure, but still requires exact attempt identity, live authority and
context, an unchanged target rectangle and feasible current constraints. Tree generation alone
does not freeze that target. Applied means this request boundary completed, not client ACK,
commit or persistence acknowledgment.

Tests use a narrowly scoped friend to supply native authority and inspect private receipts; no
production test switch or freely writable authorization flag is added. A receipt is evidence for
the subsequent no-request finalizer, not permission to release a real owned reservation here.
Membership, persistence admission and actual restoration-record integration remain later leaves.

### Reservation handoff before window admission

The writer needs a cancellable preparation boundary before controller callbacks can run.
Split NT02.3b into this small writer prerequisite and the actual window-admission slice.
`reserve` binds the expected canonical key, frame, provider incarnation and revision, persists A,
and enters Prepared. `activateReservation` requires that same current provider/revision and key
uniqueness, then enters Owned without callbacks. The controller must revalidate its native window
snapshot before activation and before the first geometry request. No window mutation is added in
the writer prerequisite.

`cancelReservation` is available only in Prepared, including after provider retirement. It
releases the key without inventing a restore-completion event. Legitimate updates received while
prepared are deferred, including updates from the same window, and the latest native intent is
applied when preparation is cancelled. An active/restoring reservation cannot use this shortcut.
`beginRestore` requires Owned or Restoring; the normal restoration and close rules remain intact.
A generation-bound ownership query is true only in Owned, allowing adoption to stop after a
callback moves the reservation into Restoring. Existing writer fixtures explicitly activate
before exercising owned/restoring behavior; no assertions or failure cases are removed.

Before NT02.3b2 is implemented, resolve its post-activation/pre-request cancellation boundary:
membership and native restore-field notifications can run before any geometry request exists.
That path must use proven callback-safe ordering or an explicit native no-request abort, not
`completeRestore` for an event that never occurred. This remains a blocking integration criterion;
the isolated writer phase API is not by itself proof of a safe window-admission sequence.

Acceptance covers wrong-key refusal before persistence, cancellation and stale generations,
activation after provider/revision changes or a new same-key window, deferred-update priority,
and refusal to cancel active ownership. The real provider and native Window integration stay
disabled until their later gates.

### NT02.3 implementation order

Build the empty native tree before allowing it to own a window. `TransientTileController` is an
internal QObject with no invokable methods or QML registration. Its first API creates one empty
root/leaf for an existing manager and desktop, updates normalized geometry for the current
generation, and clears that generation. It neither reserves a placement key nor requests window
geometry. Window admission and writer integration remain unavailable until the next leaf.

The controller owns the QObject tree, observes manager/desktop lifetimes, and invalidates its
generation before deleting nodes. The concrete `TransientTile` implementation stays private to
the controller source. It does not call the existing protected `insertChild`, which may evacuate
members into the manual tree. The initial root/leaf links are built privately while empty.

Private geometry operations carry the current generation plus guarded controller/node/context
identities. After each signal, revalidate those identities before emitting another signal or
doing further work. A callback may clear the tree or destroy its context; the outer operation
then returns `Superseded`. Public inherited setters remain rejecting throughout. An in-flight
operation rejects another geometry update rather than interleaving; clear is allowed to revoke it.
Generation exhaustion refuses new trees, and a generation is never reused within a controller.
Creation is also rejected while any operation or clear is unwinding. Shutdown becomes terminal
before deleting nodes, and operation cleanup holds only a guarded controller pointer so a callback
may destroy the controller without a later write into freed state. A concrete node invalidates
its controller record at the start of its derived destructor, before Tile can emit structural
notifications. Direct leaf destruction retires its remaining empty root through deferred deletion.

In this slice the controller is the root's QObject parent and the sole deletion authority. The
manager-parented integration belongs to NT02.4 and must preserve one unambiguous owner.

Tests cover invalid normalized geometry/context, stale generation, direct property rejection,
ordinary tree isolation, callback clear/reentry, context destruction, and controller teardown.
Include direct root/leaf deletion and controller deletion during a geometry notification.
This qualifies only empty-tree authority/lifetime, not occupied destruction or restoration.
NT02.3b/3c add those paths within their own source-file bounds before NT02.4 exposes native lookup.
Execution checklist: [todo.md](todo.md). Umbrella tracker: [#115](https://github.com/archledger/plasma-fusion/issues/115).

## First deliverable

An explicitly selected ordinary window can enter one transient managed rectangle and leave it
without changing saved custom layouts, losing its floating position, or contaminating placement
memory. Existing native actions retain priority. No master/stack algorithm or settings UI yet.

Use a new source/build lane on the ThinkPad after the current `.pf2` build releases its resources.
Do not change that build's inputs, the running desktop, or the retained private experiments.
The new baseline is the exact requestedGeometry-plus-opacity source used by the validated `.pf2`
packages, not the old experimental candidate or the version string alone.

## Proposed architecture

### Native ownership, not a geometry adapter

Prefer a compositor-owned transient root, indexed separately from the manual and quick roots.
The current `TileManager::tileForWindow()` only searches quick and manual roots; its
`saveSettings()` serializes manual roots. Separate transient storage must participate in native
lookup, release and teardown without entering manual layout serialization or manual tile picking.
Use the existing tile/window transitions rather than a timer that repeatedly assigns geometry.

This is a design candidate, not a confirmed new API. NT01 must validate the lookup and transition
semantics before NT02 implements it. If separate storage cannot satisfy the contract without a
second competing owner, stop and revise the design rather than adding more observers.

### Ownership and restoration state

Keep a single native record for the active ownership and its restoration boundary. Distinguish
unowned, owned and restoration-pending states. Reject duplicate adoption and stale ownership
requests. The first proof accepts one ordinary window on one desktop and one Activity; sticky,
already tiled/maximized/fullscreen and forced-rule cases are refused without modification.

Admission is a non-mutating check of both requested and committed tile, maximize and fullscreen
states, outstanding transitions, move/resize restrictions and target-size feasibility. Do not
call a method that unmaximizes or constrains the window to discover whether it was eligible.
Revalidate this snapshot when any asynchronous preparation completes. A later constraint change
revokes ownership through the native safe-release path; the rule wins without a geometry loop.

Before the first automatic geometry request, require an acknowledged persistence handoff for the
exact current floating frame A, window identity and snapshot generation. An earlier saved frame P
is insufficient. Use the existing placement store, not a second competing journal. Refuse
adoption during an unresolved quiet period, write, identity collision or failed/unavailable
provider; do not force recording past ordinary guards. NT01 must prove the store's actual sync
and readback semantics. NT07 provides the end-to-end implementation; native tests before it do
not establish crash-safe admission. Test P != A, close-before-restore and compositor interruption.

Capture floating state before adoption. While owned, maximize/fullscreen returns to the managed
rectangle; explicit Restore or disable releases to the appropriate floating frame. Manual
move/resize and quick tiling revoke automatic ownership without a later stale restore overriding
the manual result. Output transfer uses a documented transform for the saved floating frame;
it must not promote the automatic frame to the floating baseline.

Classify intent at command dispatch, not from the resulting maximize/fullscreen state. The
version-matched `Options::UntileOrRestoreOp` is the explicit release command; ordinary
`MaximizeOp`, horizontal/vertical toggles and `FullScreenOp` retain ownership when returning to
the managed rectangle. Internal unmaximize calls do not become release commands. NT01 maps
decoration, menu, shortcut and programmatic entry points before NT05 changes dispatch; preserve
all existing binding values, including unbound actions.

### Native settledness and Fusion placement memory

Expose a versioned, read-only owned-or-restoring state and its completion notification to the
Fusion placement consumer. Names and the export mechanism are selected in NT01, not assumed to
exist. Resolve Wayland completion using KWin's actual configure/ACK/commit processing, including
superseded requests and serial wrap; do not attach a raw protocol logger in the product.

The consumer suppresses automatic-frame recording during ownership/restoration and re-evaluates
normal recording when native restoration completes. Preserve its ordinary eligibility, quiet
period and rule guards. If the provider is unavailable or incompatible, refuse adoption rather
than disabling placement memory for every ordinary stock window.

The reviewed NT01 contract replaces the candidate asynchronous write handshake with a single
native `TransientPlacementWriter` for the same existing file in qualified sessions. A registered
provider submits validated per-key updates under an incarnation/revision; the writer owns batching,
sync/readback and reservations. Stock keeps the legacy path. Hot-switching a live legacy writer
is unsupported; qualification requires the matched provider from a fresh session. NT02's first
unit tests this protocol before any adoption unit, and NT07 connects the real consumer.

Map availability is not durable-admission availability: provider replacement receives the current
in-memory map and its persisted/dirty revision status even when saving fails. Only adoption waits
for successful sync/readback. At close or restoration completion, the latest deferred manual
winner outranks synthetic restore recording; a native event watermark admits a genuinely later
manual change by the prior owner rather than trusting callback arrival order.

KWin's own `PlacementTracker` is a second capture/replay authority. Its output-layout replay must
not capture or restore automatic geometry over the native floating snapshot. NT06A establishes
the interaction before Checkpoint B, including layout-away-and-back while owned and restoring.
Source inspection proves that replay exists, not that the current filtering is unsafe; test it.

### Teardown and restart

Release native ownership while its output and desktop context is still valid. Activity membership
changes and movement to a different desktop end the first proof's ownership; do not auto-adopt on
the destination. Current-workspace visibility changes alone must not overwrite floating memory.

On orderly owner unload, release before deleting roots. On compositor interruption, transient
ownership is not reconstructed from `kwinrc`. The restart test checks unchanged saved layouts and
that newly mapped clients use preserved floating-placement data. It must separately report any
application-specific session-restoration behavior rather than claiming the old process survived.

Restoration state and suppression belong to the surviving window/compositor, not the transient
root or unloading policy module. Deleting a root never signals restoration completion. Reload
cannot adopt a window with an outstanding prior restoration generation. If a client never
acknowledges, keep it restoration-pending without recording its automatic frame or clearing it
on a timeout; close discards only the native record, leaving the acknowledged floating snapshot.
Test unload-before-ACK, unload/reload during restoration and a permanently unresponsive client.

All callbacks can be reentrant. QObject parenting and guarded observation are not substitutes
for holding a window alive across native operations that emit signals. Use established KWin
lifetime patterns, recheck after callbacks, and test closure of both the target and related windows.

## Ordered execution and gates

1. NT01: pin the baseline, compare the two ownership designs, and define the native contract.
2. NT02.1–NT02.5, then NT03: establish the writer primitive, guarded transient nodes, native
   lookup/adoption and simple release with regression controls.
3. Checkpoint A: independent review and native tests before expanding transitions.
4. NT04–NT05: settle asynchronous restores and integrate native/manual command intents.
5. NT06A then NT06: reconcile native placement replay, then handle removal/context changes.
6. Checkpoint B: native lifecycle and memory-check evidence, with no new contexts over baseline.
7. NT07: integrate the admission-persistence handoff and placement recording. Real adoption
   remains unavailable until this gate passes; earlier native test fixtures are not a substitute.
8. NT08: test unload/restart and qualify the complete one-window proof in isolated sessions.
9. Checkpoint C: decide whether the milestone is complete; #115 stays open for the full tiler.

Each implementation change needs a failing regression before correction, a passing focused run,
relevant full native suites and static checks. Preserve both source hashes and executed binary
identity. Use distinct control and candidate build directories to avoid stale object reuse.
No task may silently expand beyond five source files; split it while preserving its acceptance.

## Resources, compatibility and publication

- Run one native build/test lane at a time on the ThinkPad, within the established four-CPU and
  8-GiB build budget. No new runtime dependencies or host package installs for the proof.
- Keep all tests in private buses, homes and virtual-output sessions. Actual hotplug, logout or
  compositor replacement is a later, separately scoped qualification step.
- First establish the pinned 6.7.5 result. Any changed Fusion consumer also needs the supported
  beta lane or a documented unavailable-provider result there before broader compatibility claims.
- Prior private candidate6 and iteration8 evidence identify regressions to retain. They do not
  automatically qualify the new source; security-sensitive material remains private.
- Sign any commits through the established minihost route. Do not publish packages, submit upstream
  changes, merge, close #115 or enable automatic tiling as a side effect of this plan.

## Risks and explicit stops

| Risk | Required response |
|---|---|
| Native lookup still misses transient ownership | Stop adoption work; repair the ownership model first. |
| Restoring geometry equals a stale tile commit | Require configure-generation evidence, not equality or delay. |
| A callback destroys a target, owner or context | Reproduce in a lifetime test and fix at the native operation boundary. |
| Restart or a failed restore loses the only floating record | Keep adoption unavailable until preservation is proven. |
| Persisted P differs from current floating A | Require the exact acknowledged A snapshot before adoption; test interruption. |
| Root/module unload outlives the restore request | Keep suppression/completion in window-owned state until native completion or close. |
| Native placement replay conflicts with Fusion's store | Qualify both capture/replay authorities before context-removal completion. |
| Unsupported rule or multi-membership window | Refuse adoption; no corrective loop or silent constraint removal. |
| Public export would change existing ABI assumptions | Rebuild and test all consumers; do not infer compatibility from a version. |

## Source grounding

Version-matched KWin source inspected for this plan: `src/tiles/tilemanager.{h,cpp}`,
`src/window.cpp`, and `src/workspace.cpp` at upstream
`ab7df7ccb7c6af20f4b279cd6220f7cd3d2267d7`. Private deltas are kept separate.
Public references:

- <https://invent.kde.org/plasma/kwin/-/blob/v6.7.5/src/tiles/tilemanager.cpp>
- <https://invent.kde.org/plasma/kwin/-/blob/v6.7.5/src/window.cpp>
- <https://invent.kde.org/plasma/kwin/-/blob/v6.7.5/src/workspace.cpp>
- <https://doc.qt.io/qt-6/qpointer.html>
- <https://doc.qt.io/qt-6/qobject.html#destroyed>

The Qt documentation confirms that guarded pointers observe destruction; they do not establish
the native operation lifetime. NT01 must verify the actual version's implementation and callers.
