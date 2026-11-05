<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Native ownership proof for custom KWin

Status: the owner approved continuation of this first-milestone plan on 2026-11-02.
NT01 through NT02.4b2b and NT02.5a are complete, including the transient admission's consumption
of the qualified continuation. NT02.5b also completes test-only release/cancellation qualification
on the actual controller-owned Xdg fixture.
The owner approved [the NT03 specification](../docs/NT03-RESTORATION-SPEC.md) on 2026-11-05.
The owner approved the NT03 implementation sequence on 2026-11-05. NT03.0 is complete;
NT03.1's exact reservation query, NT03.2's explicit claim and NT03.3's private request are
qualified within their scopes. NT03.4 is next; later work retains its per-leaf validation gates.
The [scope](../docs/NATIVE-TILING-SPEC.md) does not enable the tiler.

### Compatibility assignment

Split NT02.5 before changing its public boundary. First preserve the previous manual assignment
when a destination refuses management. Cover both direct and Qt-property calls, Wayland and X11,
and keep successful active/inactive-desktop assignment and explicit-null behavior unchanged.
Direct Tile::manage preserves independent per-desktop memberships; the deprecated Window setter
has distinct successful cleanup semantics and must not silently become equivalent to it.

The next leaf handles cancellation and callback lifetime, not merely a guarded old Tile pointer.
It must protect the Window and target, preserve newer intent even for equal-null cancellation,
and distinguish a destroyed target from an explicit null. Existing native attempt sequence
numbers cannot be reused as a cancellation stamp. Subsequent cleanup must be qualified against
the original association rather than adopting callback-selected state. A separate Xdg leaf uses
real controller-owned membership and pending records to test these boundaries; it does not claim
restoration completion. New public state/token/completion properties remain at NT04.

Split a2 into the cancellation boundary (a2a) and post-management cleanup (a2b). The first uses
the existing Xdg fixture within its three-file bound. A private saturating continuation revision
advances for every cancellation, including no-ops, and actual committed-association changes.
The release's own direct detach does not advance that revision. This detects committed-only
replacement and replacement-then-null callbacks without treating normal revocation as newer
intent. The cancellation helper retains the Window while checking its result; true means only
that this continuation remains current, not that restoration or reservation cleanup finished.
The compatibility setter separately retains the Window and target and checks geometry intent
after cancellation. Post-management cleanup remains unqualified until a2b.

A2b starts with a separate lifetime-only correction: keep the captured previous Tile weakly
guarded across management, and skip its cleanup if it was destroyed. This does not qualify
newer intent. The subsequent native-operation design must pass a private per-call token or
receipt through Tile membership and Window request/geometry/commit boundaries. It must record
owned changes before notifications and reject foreign changes without refreshing a superseded
token. Public reentrant calls cannot inherit it. X11's immediate commit needs explicit treatment;
do not guess how many revision increments a successful management operation should produce.
The operation result must distinguish refusal, current success and supersession. Final cleanup
may touch only the captured original membership and must also stop on reentrant replacement.
The existing three-file caller-only bound cannot implement that contract; establish the actual
core/backend file groups before coding it. Keep arbitrary deletion inside unchanged Tile
traversal outside any claim until the relevant callee boundaries are hardened.

The first b2 leaf establishes only `TileAssignmentFence`, an immutable native snapshot with a
private Window factory. It retains exactly one Window reference, records identity, placement,
requested/committed association and geometry-request counters, plus guarded original Tile
pointers and non-null presence flags. Construction and queries perform no cancellation,
revision advancement, association mutation or notification. Currentness requires the same live
Window, unsaturated matching counters and surviving matching original associations. The fence
is noncopyable/nonmovable and has no refresh, mutation grant, QML API or asynchronous use.
This is a dependency-only leaf, not yet an assignment token or management receipt. Membership
changes/no-ops that do not advance Window counters were outside its detection contract until the
membership revision of NT02.5a2b2d1 (below).

After this three-file prerequisite, separately review Window/Xdg native steps, X11 specialization
and Tile membership/ingress in groups of at most five files each. The first production consumer
is the owned-native-step work, not the compatibility setter. Preserve maximized-to-tiled behavior:
normalization and X11's immediate commit need explicit owned provenance. Never infer it from a
matching destination or refresh a checkpoint after arbitrary callbacks.

The first native mutation leaf is a guarded committed-association step, not a complete
assignment operation. Its private writer retains Window independently and uses the input fence
only before callbacks. Validate the fence, then compare the raw target with the current requested
association before dereferencing it; reject transient targets. For an actual change, refuse if
the committed or placement revision would reach MAX. Matching no-ops at MAX-1 remain valid.

Reuse the existing committed-association writer. Guarded writes capture an owned output fence
after their two counter updates and before tileChanged. Recheck that same fence after tileChanged
and quickTileModeChanged. Return AppliedCurrent with a checkpoint only if it remains current;
otherwise return Superseded without rollback or a newly refreshed checkpoint. Preflight refusal
returns Refused without mutation. The input fence may be destroyed by a callback and is never
read afterward. Legacy public and tagged-transient commit paths retain their existing behavior
and do not allocate checkpoints. Native normalization, geometry, membership and general mutation
provenance remain subsequent leaves.

Before whole-request normalization, add the geometry-restore storage step in Window h/cpp and
the Xdg test. Its private writer copies the desired rectangle, validates the input fence and
holds Window independently. Actual changes, through either the public setter or guarded helper,
advance the placement-continuation revision before the restore notification. The setter must
not cancel transient work, untile or request geometry. Equal field writes remain true no-ops;
they are not a new high-level placement intent.

For a changed guarded write, reject MAX-1 headroom before mutation, then capture the output
checkpoint after the field/revision write and before notification. Revalidate afterward without
refresh or rollback. MAX-2 changes and equal MAX-1 writes are supported; an initially saturated
fence is invalid. Preserve existing rectangle values, including empty/invalid sentinels; this is
state storage, not feasibility validation. Reuse neutral AssignmentStepResult/Outcome names for
the two private field writers rather than duplicating the result shape. Maximize state, keyboard
and fullscreen restore stores, backend geometry and whole-request provenance remain later work.

The next geometry prerequisite is the complete Wayland committed-geometry publication boundary,
not another requested-association storage helper. Keep the implementation shared with the legacy
`updateGeometry()` path. Its private guarded entry retains Window, reads the borrowed fence once,
then uses an independent entry snapshot while computing geometry/output values. Before writes,
revalidate that snapshot, the geometry-update generation and the original output identity.

Actual guarded geometry/output changes require placement and geometry-update counter headroom.
Write committed client/frame/buffer/output state and version actual changes before capturing the
publication checkpoint, updating rules or notifying observers. At every callback boundary check
that checkpoint, the publication generation and the expected output's identity and lifetime.
Live supersession preserves pending notifications; logical close discards them. Never refresh
after foreign callbacks or roll back callback-selected state.

An explicitly invoked guarded update with unchanged geometry may drain pending notifications.
That drain takes a new geometry-update generation without advancing placement; nested drains
therefore supersede the older publisher. A true no-op has neither pending entries nor changed
geometry/output and does not advance either counter. Legacy no-ops retain their existing behavior.
Guarded output-only changes are real changes. Refuse would-exhaust counters before mutation or
pending-entry consumption. This boundary does not submit or complete a client configure.

Version actual `Window::setOutput()` changes before their signal so output round trips cannot
hide behind final pointer equality. Equal output writes remain no-ops. Limit this leaf to Window
header/source, Wayland header/source and the Xdg test. The later
Window/Xdg request group consumes publication results in its immediate branch and separately
qualifies queued requests/output synchronization. Recheck private-helper access and the actual
header/source group before that implementation; split rather than silently exceeding five files.
Maximize normalization follows those steps.

Split the geometry-request layer at its output-synchronization boundary. The first real mutation
step synchronizes requested rectangle/output/scale/transform/color using frozen target values and
an explicit stack-local guarded context. It does not allocate a geometry-request generation,
cancel transient ownership, submit backend geometry or emit requestedGeometryChanged. Refuse an
existing transient owner or active transient request without effects. Hooks may queue configures;
that is not delivery or client completion.

Version actual requested-state/property changes and pending-synchronization transitions before
callbacks in shared legacy/private writers. Guarded calls replace their checkpoint only adjacent
to an owned write, and validate after each virtual hook and signal. Public callbacks inherit no
context. Preserve unfinished synchronization on interruption; a subsequent explicit call can
finish it. Exact frozen write counts determine headroom before the first mutation; never return
Refused after applying a prefix. Equal fully synchronized state is a no-op. This four-file leaf
also gives XdgSurfaceWindow narrow native access to the existing publication helper so the next
backend request group need not introduce an access-only change.

### Controller-owned release qualification

NT02.5b adds no state API or implementation path. Two rows observe every release notification for
pending and actually committed controller-owned admission. Each observes the same generation and
floating frame, Restoring/releasing state, detached controller/membership/associations, the writer
barrier and no new geometry request. The exact notification order is checked; a scheduled state
configure is not forbidden. Cancellation can return a current continuation while its record stays
Restoring, which is not restoration completion.

The returned checkpoint then retains the Window across logical close. Its continuation is stale,
but the identity and writer barrier survive until the checkpoint is dropped and QObject destruction
finishes. A same-key manual update submitted after release remains deferred until that destruction;
the source UUID exercises the writer protocol, not another live provider/client.

The existing compatibility-cancellation fixture keeps its direct rows and adds only eight property
rows: pending/committed crossed with unchanged, equal-null cancellation, committed-only replacement
and replacement-to-null. A true Qt property-write result proves dispatch, not successful placement.
Existing assertions decide whether the older operation stopped and newer intent survived. Public
state/token/completion properties remain NT04, actual restoration remains NT03.

### NT03 implementation sequence

Keep the existing NT02 implementation and qualification intact. The approved NT03 specification
separates request initiation from NT04 completion and requires stale-configure placement safety
before action routing. The former four-file NT03 allocation is superseded by the explicit leaves
in `tasks/todo.md`; no leaf may silently grow beyond five source/test files.

Dependency order:

```text
NT03.0 characterize old-buffer/placement behavior
  -> checkpoint: accept the content-versus-placement decision table ----+
NT03.1 exact writer reservation query                                 |
  -> NT03.2 explicit claim and surviving restore-attempt record
  -> checkpoint: identity, cancellation and lifetime proof ------------+
  -> NT03.3 private normal-mode guarded request (both checkpoints)
  -> NT03.4 configure provenance and stale-placement protection (also requires NT03.0)
  -> checkpoint: request safety, still no action routing
  -> NT03.5 guarded mode normalization
  -> NT03.6 consumed-action routing
  -> Checkpoint A: integrated request-facing qualification
  -> NT04: native completion and reservation finalization
```

Work is serial on the existing private branch and isolated ThinkPad build. Review can run against
a frozen candidate, but no build, mutation copy or source update may race another writer of that
source/build. Preserve the installed `.pf2` desktop. An isolated successful precursor is not an
installable or complete tiler.
Start with NT03.0 to expose the highest uncertainty. If its decision is blocked, the independent
writer query and no-geometry record primitive may proceed after plan approval; backend mechanics
and routing remain blocked.

NT03.0 is a bounded characterization, not a fix. Use a disposable test copy to record content size,
frame position, requested rectangle, serial order and association state when an old buffer is
committed with a newer resize outstanding. Include pending admission and ordinary unowned
controls. Preserve unsafe observations as evidence, not permanent tests asserting that unsafe
behavior is required. The decision table must distinguish accepted client content from obsolete
compositor placement. If this cannot be resolved, NT03.3 and dependent work remain blocked;
only NT03.1/NT03.2 may proceed. Do not invent a rule.
The completed observations and accepted narrow policy are in
[`nt03-old-buffer-characterization.md`](nt03-old-buffer-characterization.md). This closes the
characterization gate, not the later stale-configure implementation or serial-wrap proof.

NT03.1 is a read-only exact-tuple query in the writer. It verifies owner UUID, generation and
Restoring phase without changing a reservation or map. It does not turn a provider revision,
`isReserved` boolean or caller assertion into permission. Existing Owned and ordinary writer
behavior stays unchanged.

NT03.2 makes explicit restoration an individually claimed operation in the Window record. It
binds immutable A, Window/ownership/attempt identities and native context, with exhaustion and
normal-mode eligibility checked before mutation. Generic revocation still grants no restore
permission. The record must survive its own detach/finalization boundaries, and cancellation must
invalidate the claim before later work. Do not store a Window-retaining fence inside the record.
This leaf sends no restore geometry and is not wired to public action dispatch.

NT03.3 dispatches an exact-A request only through the private claim and distinct restoration
provenance. Record the allocated geometry-request generation before callback-producing work.
Carry the same authority across each guarded step; never reconstitute it from a callback's
current state. Stage and Published outcomes are distinguished, and failures after a prefix are
superseded rather than mutation-free refusals. Ordinary ownership guards remain strict.
Consume the original claim checkpoint by value. A consumed duplicate refuses without cancelling
the first request. The lower entry independently requires an active wrapper, an unused native
generation, exact A and MoveResize mode. Xdg preflight accepts pending admission geometry but
requires no pending gravity. Verify generation publication in synchronization callbacks as well
as backend callbacks, and reject reentrant lower-entry reuse while the first wrapper is active.
The precursor remains private and must not be called safe against delayed configures until
NT03.4 passes.

NT03.4 connects that identity to native configure processing. Use the accepted NT03.0 policy:
valid client content is not rejected merely because its old configure has lost placement
authority. Prevent old admission/restore configures from restoring position, requested-state or
completion authority after a newer action. Test actual serial wrap for every matching operation
that depends on ordering. If the existing matcher or a required helper forces another file group,
split and review it before editing; do not preserve the size limit by omitting the hard case.
Reservation finalization remains absent.

NT03.5 qualifies maximize/fullscreen normalization under the same explicit intent. Preserve A
while requested-mode and decoration changes run, validate actual prospective constraints/scale,
and discharge notifications for writes already made. Unsupported cases stop without a legacy
fallback after mutation. Do not replace previously covered owned mode behavior with the limited
normal-mode precursor. Keep mode-specific child steps independently testable within the leaf;
split the leaf if it no longer fits one focused change.

NT03.6 alone wires the qualified operation into explicit action dispatch. Use a typed distinction
between unhandled/no-record and consumed, with separate no-start/staged/published/superseded
outcomes. Existing transient records consume duplicate or unsupported actions without starting
again or reaching ordinary fullscreen/tile/maximize fallthrough. Keep the existing Owned-only
query semantics; preserve unrelated/unowned action behavior and user shortcuts. Generic manual
revocation and teardown remain detach-only. No production provider/admission or new QML API is
enabled by this routing.

Every implementation leaf needs meaningful fail-first or compiled negative-control evidence,
actual changed-line formatting and affected native tests. Runtime changes run the selected
18-suite campaign in the pinned environment; reuse unchanged evidence only with explicit source
and binary bindings. Use the existing memory lane for the affected lifecycle functions and
retain its profile limitations. Review and a signed private checkpoint precede the next leaf.

Verification profiles used in the task list (inside the existing container):

```sh
# W: writer behavior and exact tuple handling
cmake --build /build --parallel 4 --target testTransientPlacementWriter
ctest --test-dir /build --output-on-failure --no-tests=error --timeout 120 \
  -R '^kwin-testTransientPlacementWriter$'
# X: Window/backend/action behavior, including new explicitly enumerated rows
cmake --build /build --parallel 4 --target kwin testXdgShellWindow
ctest --test-dir /build --output-on-failure --no-tests=error --timeout 120 \
  -R '^kwin-testXdgShellWindow$'
# I: rebuild the actual library and all selected integration targets before the full campaign
cmake --build /build --parallel 4 --target kwin kill testTiles testXdgShellWindow \
  testQuickTiling testMoveResize testFractionalScaling testX11Window testDecorationInput \
  testDontCrashEmptyDeco testDontCrashAuroraeDestroyDeco testOutputChanges testMaximized \
  testScreenChanges testOffscreenQuickView testInternalWindow testTabBox \
  testTransientPlacementWriter testPlacement testTransientPlacement
ctest --test-dir /build --output-on-failure --no-tests=error --timeout 120 \
  -R '^kwin-test(X11Window|DecorationInput|DontCrashEmptyDeco|DontCrashAuroraeDestroyDeco|Tiles|XdgShellWindow|QuickTiling|MoveResize|FractionalScaling|OutputChanges|Maximized|ScreenChanges|OffscreenQuickView|InternalWindow|TabBox|TransientPlacementWriter|Placement|TransientPlacement)$'
```

Profile W compiles the writer source into its unit-test target separately. It is not proof that
the integration library was rebuilt. Apply profile I after runtime changes and verify actual
loaded-library and source identities; never reuse pre-existing binaries for a changed writer.

The formatting and scoped Memcheck commands and environment are recorded in
the approved specification and prior qualified recipes. No commands above are newly executed
results. The task list names negative controls and acceptance boundaries, not merely green exit
codes. Native REUSE omissions remain reported, never recategorized as a pass.

Checkpoint A requires a source-bound integrated proof of exact A, older-command supersession,
duplicate handling, content-versus-placement behavior, mode handling, close/lifetime safety and
unchanged ordinary controls. A never-ACK client must remain pending. This checkpoint does not
clear the writer barrier, qualify production deployment or complete NT04.

### Workspace and transient-root registry

Keep the controller as the sole QObject root owner. TileManager gains a weak active index by
desktop plus weak lifetime tracking for roots retired from lookup but awaiting deletion. Shared
metadata carries guarded root/controller identities, desktop/generation and a destroying flag;
it owns no QObject. The concrete root sets that flag before destructor callbacks. Final
registration validates the complete tuple after construction and before treeChanged; the
pre-allocation availability check is only advisory. Unregistration removes lookup by exact tuple
before clearing controller identity, but lifetime tracking lasts until actual destruction.

Close registration before manager draining; exclude a removed desktop through its ordinary-root
cleanup. Extract active and retired root metadata into value snapshots before callbacks. Local
cleanup must finish the captured roots even if the manager is deleted, while draining-flag
cleanup may touch only a surviving manager. Recheck the live destroying flag after controller
clear before deleting a surviving captured root. Never select a replacement through the index.
Keep an in-progress flag in the same shared metadata so a nested drain skips a root already
being cleared, even before its destructor starts; the outer local cleanup still finishes it.
Temporary desktop exclusion is restored only by the drain that acquired it and only if the
manager survives. The native prepare-for-removal entry point is C++ only, not invokable from QML.
The controller's existing leaf unlink ordering permits context cleanup of a retired ancestor
without recursively deleting a still-parented leaf.

Native lookup uses registered live trees and actual membership, never a Window record alone.
Keep manual/quick maps, model, picking and saveSettings separate. forgetWindow holds the Window
through callback-producing release and uses guarded desktop snapshots plus non-inserting lookup.
The registry/controller leaf is four files; Workspace ownership and output-removal transactions
follow separately. The latter must settle unique_ptr ownership before callbacks, block nested
output updates while retaining a pending update, and close all removed registrations before
the first drain. No native writer/provider is instantiated in these leaves.

Workspace integration is two commits: ownership/shutdown, then output reconciliation. Keep
LogicalOutput as the TileManager QObject owner and index managers with QPointer, not a competing
unique_ptr. Explicitly delete surviving guarded managers at the existing removal points. A
deleted manager on a still-active output must be recreated at a defined reconciliation point;
getters remain read-only and may return null until then.

The ownership leaf also guards Window's manager/root consumers and the scripting wrapper.
Unavailable non-None tiling requests are refused rather than interpreted as untile; explicit
None requests retain their release behavior. Output transfer without a destination manager
forgets the old association before ordinary geometry transfer, but stops if a callback closes
the Window or selects a newer placement. Shutdown tests use the actual test-application
destructor in an isolated child process and return a post-destructor verdict to the parent.

Output reconciliation runs synchronously while idle. Nested requests set a pending bit and a
single owned zero-delay timer schedules the later pass after cleanup. Consume pending work only
at entry; cancel queued work during terminal shutdown. Freeze the input values needed by a pass
before callbacks and retain both backend and logical outputs, releasing logical holds before
backend holds. Close registration on all removed managers before any drain callback. Revalidate
manager/root/desktop/Window guards before continuing ordinary evacuation. These guarantees cover
the new drain/Workspace boundaries, not arbitrary deletion inside unchanged ordinary Tile
methods.

Split output integration into NT02.4b2a (queued, retained and frozen reconciliation) and
NT02.4b2b (batch drain and guarded evacuation/Workspace continuations). Both use three files.
The completion guard runs after every temporary lifetime release, including Window references,
so destruction callbacks can only record pending work. Captured Windows stay alive for the pass
to prevent raw-key address reuse in old-output mappings. The second leaf also snapshots and
guards Windows inside desktopResized/rearrange instead of retaining raw iterators across calls.
This is consistent input and lifetime handling for one reconciliation pass, not an atomic
global snapshot: some public LogicalOutput accessors still delegate to the live backend.

### Public release routing

Existing tokenless Tile::unmanage(Window*) and Tile::forget(Window*) target membership current
at dispatch. For transient tiles, delegate through a protected virtual hook whose base default
rejects. The concrete controller-owned leaf verifies its controller, leaf identity, member and
nonzero ownership generation before capturing that generation and requesting release. Public
manage and the other transient mutation guards remain rejecting.

The hook must retain only guarded receiver/controller references across callbacks and inspect
only the guarded receiver afterward. unmanage reports whether this call removed membership,
not whether persistence finalized; repeated unmanage returns false and repeated forget is
harmless. Both public methods return immediately after routing, so they cannot resume ordinary
geometry work after a callback invalidates their generation. Closing windows may still detach;
the writer barrier remains through QObject destruction. This leaf requests no restoration
geometry and does not fabricate completion.

The public methods carry no caller generation and cannot infer historical external intent.
Generation binding protects the dispatched operation and the existing generation-bearing
Window/controller paths. Tests must distinguish these guarantees and cover stale generations
after release/readmission without inventing a new tokenless-API promise. Keep four files by
using the existing Xdg integration target for real Window/writer fixtures.

### Writer-qualified admission and surviving records

Split the reservation/attempt lifetime from callback-producing membership. Window owns the one
native record; the controller holds references, not another mutable copy. The record keeps the
original floating frame and native context immutable, the writer/provider binding, a Window-
allocated non-reusable ownership generation, and sticky native request progress. Allocation is
separate from native attempt consumption; cancelling preparation never permits generation reuse.

Preparation reserves the exact writer snapshot. Activation revalidates the original native
snapshot and the writer's current provider incarnation/revision synchronously, then publishes
Owned and a sealed NoRequest attempt before any membership notification. Queued provider-retired
signals are not freshness evidence. The native request publishes Requested into the surviving
record before its first geometry mutation, not only when returning a receipt.

Revocation enters Restoring before removal or manual-record callbacks. Prepared may use ordinary
cancellation. An activated attempt proven not to have entered geometry may use the one-shot
NoRequest finalizer even when no native request call began. Requested/uncertain attempts retain
their record and writer barrier for the later restoration implementation; do not invent a
completion event. A failed writer cleanup retains the native record. Close retains suppression
through `closed`; QObject-destruction cleanup captures UUID/writer identity without dereferencing
destroyed Window fields. Writer lifetime must cover outstanding records; writer loss is terminal
unavailability and cannot authorize re-adoption through a replacement.

The writer becomes an explicit internal C++ library dependency, still non-installed and not QML
registered. Integration tests link that same implementation and metadata instead of compiling a
second writer into the executable. A small read-only incarnation/revision predicate belongs at
the writer boundary. Keep the record/attempt leaf to Window h/cpp, writer header, integration
CMake and Xdg tests; if a proper implementation needs another file, revise the bound first.

The following membership leaf adds guarded private notifications, detaches before structural
teardown, and refuses late transient commits after revocation. It rechecks the original frame,
context, target and writer binding after every callback. Controller tree/lifetime changes must
not discard the Window record. Actual restoration request/completion, Workspace ownership,
public release routing and production enablement remain later gates.

Before membership, add a bounded native configure-provenance leaf. A configure's Tile QPointer
can become null after tree destruction; null alone cannot distinguish that stale transient
commit from a real untile. Preserve the originating transient ownership identity in outgoing
configure state and reject revoked/stale commits, including an actual delayed ACK/commit after
node deletion. Ignore a stale transient association rather than substituting a null/ordinary
commit that could erase a newer manual association. This does not implement restoration serial
completion. Keep this leaf to Window h/cpp, Xdg h/cpp and the Xdg test.
The provenance belongs to the requested association that installed the tile, not the latest
attempted generation (which can advance on rejection). Preserve it when a QPointer becomes null;
replace or clear it only with explicit association intent. Keep public commitTile for ordinary
callers and use a protected tagged entry point for native configure delivery. Successful tagged
commits require a live exact Owned record and writer reservation, without a weaker test-only path.

Membership then separates revocation, structural detach, notifications and persistence
finalization. Mark Restoring/cancel first, attempt the writer transition, clear the controller
index/member list and only matching Window associations without notifications, then emit
guarded notifications and attempt NoRequest finalization. Failure or Requested progress must
not prevent structural detach or discard the record. Closing windows still detach structurally
but never finalize persistence before QObject destruction. Do not call public requestTile(null)
to forget an association, since that requests restoration geometry.

Direct node destruction marks the node as destroying and invalidates publication before
callbacks. Empty memberships and sever structural/QObject links before outward notification;
never emit from the dying node, and never recursively delete its parent inline. Preserve normal
windowAdded/windowRemoved-before-windowsChanged ordering with checks between signals. Provisional
admission and published membership are explicit transaction stages, not competing authorities.

Require one desktop matching the selected tree. Activities compiled out or explicitly unused
by Workspace have a distinguished default context. A running Activities service requires a
known effective current activity; ambiguous/all-activity state is refused when multiple actual
activities exist. Unknown/NotRunning service state is not evidence of a singleton context.

Implement structural release as a narrow controller Release lifetime guard, analogous to the
existing Mutation guard. Its constructor holds only the Window and performs callback-free
revocation/unlink/association clearing. Capture the original cleanup kind: Prepared cancellation
must not become beginRestore or proof finalization. Clear the Window record's controller link
with the controller index. Finish notifications explicitly after structural teardown, rechecking
the Window generation and current association before each signal; finish/destructor fallback is
idempotent and must not dereference a destroyed controller or node. A Requested record that cannot
finalize does not make structural clear fail. Never emit treeChanged during controller destruction.

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

### Owned request provenance

NT02.5a2b2b2b1 moves the private transient request onto the guarded primitives without changing
its receipt contract. The restore write uses the guarded restore writer; the requested association
is installed inline between a validated fence and an immediate checkpoint, with no callback in
between; the geometry uses an owned form of the guarded geometry request that takes the exact
active request, derives its target from it and always dispatches a full move-resize. Ordinary
callers never inherit that exemption.

The request's external authority can lapse without any Window counter changing, so each step
result borrows the request and every child step (restore writer, synchronized output-property
writes, Xdg dispatcher, Wayland publication) validates it next to its checkpoint. The carrier
joins the result only after the callback-free rectangle write: the request predicate cannot hold
between generation allocation and that write. Request and ownership-record progress become
Requested at allocation, before the first synchronized write, and stay so whatever follows. The
geometry result's checkpoint also validates the quick-tile update and the final requested-tile
notification, so a handler that changes fenced state with authority intact supersedes the attempt.

Headroom known before any effect (request generation, association revision with room for install
and removal, a backend without a guarded dispatcher) is rejected in preflight; a restore-writer
refusal is rejected without effects; any later child refusal supersedes and removes only this
attempt's association. Request-bound results are locals that die before the uniquely owned request.

### Owned maximize normalization

The probe on the real controller fixture (NT02.5a2b2b2b2) showed no A-contamination on the
maximize path: a transient tile reports a Custom quick-tile mode, so the legacy restore capture is
skipped, and the placement key stays frozen while reserved. The defect was release: every maximize
called `exitQuickTileMode()`, which reached the controller's release through the tile, left the
record Restoring with nothing completing the restore, and the later unmaximize returned to floating
A rather than the managed rectangle.

The owned maximize operation is generation-bound and decided before the first callback. It is
selected only for an ordinary toggle (no caller-supplied restore rectangle, no interactive or
electric-border operation) on a live record that passes a new ownership-validity predicate: same
Window and generation, Owned phase, nothing executing or releasing, writer/provider/reservation
valid, live transient tile holding this window in a current manager/output/desktop context, the
window's own current context (single desktop equal to the recorded one, move-resize output equal
to the recorded output), and the requested association unchanged. Admission feasibility is not
reused, because an owner may be maximized; a tile or context that is no longer usable selects the
legacy path, which releases as before, never the recorded adoption rectangle. The managed rectangle
is frozen from the tile before any callback, and the plan is mode-aware: each axis the toggle
releases must be able to return to the managed extent under the client's size limits (frame-size
constraint equal to the managed extent); otherwise the legacy path is selected, and an owner is
never silently enlarged or recentred. Infeasibility that arises after a callback stops the owned
continuation instead of falling through: the revalidation before the mode write includes it, and
the owned geometry entry carries it as the operation's own constraint, which the ownership-kind
provenance evaluates at every child boundary (synchronization, dispatch, publication), because a
client's size-hint change touches neither the Window fence nor the ownership record.

The owned path emits `maximizedAboutToChange`, then revalidates the Window fence, the ownership and
a requested-mode revision advanced by every requested-mode write (legacy and owned), so a nested
round trip cannot revive an older continuation; only then does it write the mode. Each decoration
signal is a callback boundary of its own: the decorated window is held by a guarded pointer, the
recursion flag is reset by scope, and the operation revalidates after every emission, including
the decoration's identity. It never writes the restore field and never leaves the tile. Maximized
axes span the maximize area; released axes return exactly to the frozen managed extent, requested
through an owned geometry entry keyed by the ownership generation. The step-result carrier is a
tagged provenance, exclusively the borrowed adoption request or the ownership generation,
validated by every child step. Publishing the mode to the client is the mode write's own
obligation, discharged while that write is current whatever happened to the geometry, and it
reports no success; after supersession nothing falls through to the legacy path. The
acknowledgement of the maximize configure still commits a kept association. The requested-mode
revision is discriminated by a row that exhausts the publication generation first, so a nested
round trip writes modes without any fenced change. Fullscreen and X11 remain separate; the
combined maximize/fullscreen contract is not claimed.

### Owned fullscreen normalization

The probe on the same fixture (NT02.5a2b2b2b3) showed that the fullscreen path already stored
the managed rectangle as its own restore field and returned to it; the defect was again the
release: the public move-resize cancelled the native request and revoked the ownership on entry,
so the exit happened with the ownership gone and nothing completing the restore.

The owned fullscreen operation reuses the ownership-validity predicate, the owned geometry entry
and the provenance constraint of the maximize operation, with four differences the design review
required. First, the fullscreen restore field is a legacy consumer's memory (the placement tracker
reads it, and a legacy exit after a release returns to it), so the owned entry still writes it,
through a guarded, versioned writer that shares its body with the maximize restore writer: every
change of the field, including the legacy setter's, advances the continuation revision, the
checkpoint is taken after the write and before the notification and is never refreshed, so a
handler's replacement, or a change away and back, stands and ends the operation. The value written
is the rectangle an owned exit returns to: the managed rectangle, or the maximize-area extents on
the maximized axes of a retained requested maximize mode, so a later legacy exit stays consistent
with that mode; the owned exit returns to that rectangle frozen before the first callback, never
to the stored field. Second, the decoration an exit restores does not exist while fullscreen, and
`configureDecoration()` creates it through plugin code: it is a callback boundary, with the
Window lifetime retained and a full revalidation after it. The plan checks the exit's return
feasibility (every non-maximized axis returning exactly to the managed extent under the client's
size limits) with the undecorated conversion, which is exact when no server decoration returns,
and with the returning decoration's enforced minimum as a necessary condition otherwise; the exact
check runs right after the decoration is configured: the exit's dispatch is validated after a
prefix (the state write and the decoration configuration) that the legacy path shares. An extent
the restored decoration cannot return to, with the client's size hints equal to the plan's, is the
exit's predictable effect, not a supersession, so the legacy exit takes the operation over and
releases as before; changed hints are a handler's newer intent and end the operation where it
stands, and a superseded owned operation never reaches the legacy tail. The hint comparison is
deliberately narrow (rule limits and the decoration's state are separate inputs the exact check
reflects), and no hook exists at that boundary, so supersession there is covered by the
revalidation's control, not by a row. Third, the
requested state and the requested output are versioned separately: the state revision backs the
publication obligation (a nested output-only client request returns early from the state write and
publishes nothing, so it must not suppress the outer publication), while the intent revision,
advanced by both, together with the frozen identity and presence of the requested output (a
destroyed output nulls the pointer without any write), backs the geometry; on entry a client-
requested output other than the one the ownership lives on selects the legacy path, which moves and
releases as before. Fourth, the explicit untile-or-restore action releases an owned fullscreen
window on its first press: the owned exit to the managed rectangle, then the release, in one
dispatch. The dispatch routes an owned window (a new public accessor of the ownership generation)
to the owning layer, which leaves a requested fullscreen state, acknowledged or still pending, as
the owner and releases only if that exit completed as the current intent (the owned operation
reports Legacy, Stopped or Applied; equal final values prove nothing, since a nested round trip
ending not fullscreen holds the newer intent and survives); a pending entry is left before the
release, so its stale configure commits no association and the newer placement lands; the window's
lifetime is retained across the exit, a closed window is not touched, and windows without
ownership keep the one-step semantics. No legacy un-fullscreen requests the stored field over the
restoration intent. The acknowledgement path is unchanged. Completion of the restoration after a
release and X11 remain later leaves.

### Membership revision in the assignment fence

NT02.5a2b2d (guarded Tile membership/ingress) was refined, after a design consult, into four
leaves: the membership revision (NT02.5a2b2d1), a guarded maximized-to-tiled normalization
prerequisite for ordinary assignment (NT02.5a2b2d2, with its own receipt and requested-mode
currentness, because the public `setMaximize` legitimately invalidates an input fence and a
fence taken afterwards would absorb arbitrary callbacks), the guarded Tile/association ingress
(NT02.5a2b2d3: refusals including an unsupported backend before any mutation, a stable evacuation
worklist with retained Window and guarded destination/source/manager/desktop identities,
validation after each membership notification, a requested-association step whose quick-tile
protocol state and notification obligation are defined after partial failure, and public entry
points that establish their own operation after stamping intent) and the compatibility setter's
consumption (NT02.5a2b2d4: cleanup only of the captured original membership, X11 on the legacy
sequence selected before any guarded mutation).

The revision (NT02.5a2b2d1) is a per-window saturating counter. Every actual membership change of
the window, ordinary (`Tile::add`/`remove`) or transient (the controller's admission add and the
release's removal), advances it before the corresponding notification, so a guarded writer's
checkpoint taken after the write and before the callbacks sees its own change and any later one
as foreign; `TileAssignmentFence` records and compares it and treats saturation as exhausted, so
no later fence of that window is current again. The otherwise-valid public membership no-ops
record the same intent under a documented conservative same-window rule: managing an existing
member (after the transient and resizability refusals), unmanaging or forgetting a non-member of
an ordinary tile. Refusals (a transient target, an unresizable window, a window not on the
tile's desktop) and the internal misses of an evacuation record nothing, and the equal
requested-tile paths keep their existing cancellation stamp rather than a duplicate. The transient
admission publishes its membership before any of its fences exist, so it snapshots the revision
after the transient add and treats a change across that publication as supersession instead of
absorbing a foreign membership or a public no-op made by a callback. Public paths keep their
bodies; public-path reentrancy through them (a stale public continuation resuming after a nested
public re-management) is an explicit exclusion until the public entry points establish their own
operation in NT02.5a2b2d3.

### Guarded normalization prerequisite

NT02.5a2b2d2 provides the maximized-to-tiled normalization an ordinary guarded ingress needs: the
public `setMaximize(false, false)` legitimately invalidates an input fence (its restore write and
geometry request advance fenced counters), and a fence taken afterwards would absorb arbitrary
callbacks, so the ingress needs a step that records its own changes and returns a receipt whose
validity every later step checks. The step is a private virtual
`normalizeMaximizeForAssignment(fence, provenance)`; the base implementation refuses without
effect (an unsupported backend, X11 included), so the ingress selects the legacy path before any
mutation, and a refusal is never permission to fall through after an earlier mutation. The Xdg
override makes its own recorded writes and guarded child calls, never the public unmaximize, and
honours the maximize recursion guard at entry. It refuses, mutation-free, a transient owner or an
active request (an ingress that must revoke ownership does so at its public cancellation boundary
first), an unresizable or applet-popup window, a rule-forced maximize, an interactive or
electric-border operation, and insufficient headroom for the whole operation (a budget covering
the restore capture's placement increment plus the guarded request's worst-case synchronization
writes and committed change, so a shortage known at entry refuses before any write); it returns
AppliedCurrent with a fresh checkpoint and no stamp when the requested mode is already Restore
(requested, not acknowledged). Otherwise it takes its own snapshot of the validated entry state
(the caller's fence is borrowed and never read after the first callback), emits the about-to-change
signal as a boundary (fenced state, provenance, requested-mode revision and the effective size
limits must still hold before the mode write), writes the requested mode (advancing its revision)
under a publication obligation discharged only while that write is current, treats each decoration
signal as a boundary, and crosses the borderless reconfiguration as its own transition: the policy
it set, the client's rule-checked limits and the fenced state must hold across it, and the receipt
is then established against the effective limits after it (a client decoration-preference change
inside that transition's own handlers is absorbed by design, since the geometry is computed only
afterwards under the resulting limits). It captures the restore with the exact legacy formula
(refreshing only the axes that were not maximized in the old mode, skipped when a quick tile is
already requested) through the guarded restore writer, and requests the legacy geometry (a valid
restore: its size clamped to the minimum and centred on the restore per axis; an invalid one: the
maximize area's origin and a zero size the client chooses) through the guarded request. Its
receipt is the request's result carrying a constraint-kind provenance: the requested-mode revision
and the effective size limits the geometry was computed under, by value, chained onto the incoming
provenance (every provenance kind evaluates its chained constraint), evaluated by every child
boundary and by every later ingress step; a mode change away and back cannot revive it, and a
property-only size-limit change at the geometry boundary supersedes the frozen request instead of
letting an obsolete rectangle through.
A child refusal after the mode write is Superseded, never Refused. The helper performs no
cancellation, evacuation, association or cleanup; AppliedCurrent means its synchronous request
completed while current, not that the client acknowledged unmaximizing. X11's immediate commit
remains outside its qualification.

### Guarded ingress refinement

The design consult on NT02.5a2b2d3 accepted its split into three five-file leaves and fixed the
contracts. A read-only preflight is never a reservation: before any membership mutation the
ingress budgets the whole selected path (the membership removals and addition, the normalization
with its own geometry request, the restore capture, the requested-association change, the final
geometry request and its publication), and a child refusal after a mutation is the operation's
supersession, never a fallback. The public cancellation boundary must yield a qualified
continuation: the legacy helper only checks its placement revision while an ownership release
emits notifications that can change the membership revision, so a fence taken afterwards would
absorb foreign intent; NT02.5a2b2d3p therefore adds a cancellation variant whose checkpoint is
taken after the cancellation's own callback-free writes and validated after the release's
notifications, threaded through the controller's release and the window's own revoke path
without counting increments. A valid manual assignment intent revokes automatic ownership before
publishing new membership, after the existing mutation-free rejections and never because an
invalid destination was named; `Window::requestTile` keeps its own cancellation semantics. The
requested-association write carries an obligation discharged before the result is finalized (the
backend's quick-tile protocol state, a recheck of the live window, the unchanged non-exhausted
association revision, the target identity with its original presence and the transient-generation
state, then the notification and a terminal validation); callbacks that invalidate the operation
make it Superseded although the write stands, and X11, whose protocol state commits immediately,
is excluded before any mutation. The evacuation worklist is stable but not authority: the
destination, source, manager, desktop and the active-versus-inactive decision are frozen and
validated after every notification, a destroyed source is skipped only while the checkpoint still
validates, and a destroyed destination is never read as explicit null. Private no-ops do not
duplicate the public intent stamp. Public `manage` returns true only for a current successful
management; the interactive untiling adjustment stays on the legacy path, which the guarded path
never reaches because interactive operations are refused; the closed public reentrancy is
qualified to the guarded paths, the X11 and interactive legacy branches staying unqualified.

The step-level consult on NT02.5a2b2d3a added: the normalization's mutation-free refusal is a
refusal of the association step only while nothing of that step had an effect (a Tile ingress that
already mutated membership translates it into its own supersession); a nonzero transient-generation
marker is refused by the read-only preflight rather than cleared, so the equal-association no-op is
a genuine no-op; the destination's identity and original presence are captured before the first
callback, including the public cancellation, and validated before every dereference; the
normalization's checkpoint and its receipt provenance are both carried forward; the public entry
points keep a single stamp (the qualified cancellation) with the legacy body after the cancel moved
verbatim into a private remainder selected on a refusal without effect, and the exhaustion edge
keeps the legacy cancellation as an explicit legacy exclusion; the forget step has its own complete
preflight including the headroom of its one association change; the aggregate placement bound
(twice the guarded request's worst case) is a conservative bound revalidated after callbacks, never
a count of expected increments.

The step-level consult on NT02.5a2b2d3b added: the backend refusal applies unconditionally before
any membership mutation (inactive management without evacuation, an unmanagement that clears no
association and a membership-only forget would otherwise mutate before discovering an unsupported
follow-up); the removal follow-ups are preflighted read-only before the removal (the null
association when an unmanagement clears this requested tile, the forget step's own refusals), a
later refusal still mapping to supersession; the outer quick-tile boundary uses the qualified
preparation and verifies its currentness before entering the public management, so two stamps are
acceptable only with currentness between them, and no caller infers an inherited preparation; the
frozen context covers the window's desktop membership, the destination manager's identity and live
output, the original parent's identity and presence, the planned active decision and the target
geometry, validated after every individual notification; the worklist is collected without
callbacks and the callback-driven visitor is never reused for mutation; a destroyed unprocessed
source that held the window changed its membership and ends the operation, while a benign deletion
after an operation-owned removal leaves the checkpoint current; a manager's teardown flag is set
only by its destructor, so destination validity is checked against live workspace state (its
manager, output and desktop) rather than that flag alone, and source outputs need not remain
registered for an evacuation; public existing-member management, non-member unmanagement and
forgetting keep their membership-only stamps without cancellation, while a deleted member is
released through the legacy membership-only removal (the workspace's removal notification relies
on it) and a deleted window is never reported as managed, not even as an existing member; a
window's requested tile destroyed during an ingress after its evacuation supersedes the ingress
(an incomplete, superseded assignment: the membership stands, no association is published over
the vanished one, the public management returns false) where legacy published the destination; a
new membership through the public entry point carries the qualified cancellation's placement
stamp even on an inactive destination without evacuation, as a new manual intent; the public management returns
false on supersession, which also stops the compatibility setter's unconditional cleanup until
NT02.5a2b2d4 qualifies it; the destination's guarded identity is captured before the cancellation
and no legacy remainder is entered after it disappeared.

The step-level consult on NT02.5a2b2d4 added: the setter captures the destination's frozen
context (the same predicate the public management uses) before the first callback, validates it
after the qualified preparation and chains it into the ingress's provenance, since the private
ingress would otherwise accept a destination changed during the cancellation as fresh; the complete
selected path is preflighted before any guarded membership mutation, including the original
membership's cleanup (one membership increment reserved in the ingress's headroom and the null
association's read-only preflight when the original stays requested), and a capacity consumed by a
later callback stops the setter without rollback, never switching to legacy cleanup after the
ingress applied; both the ingress and the cleanup are consumed on currentness (AppliedCurrent and
the result still current), the cleanup chains the ingress's checkpoint and provenance, and any other
cleanup outcome ends the setter with no public retry, fallback, replacement target or refreshed
checkpoint; `Tile` befriends `Window` for the private steps; the setter's equal-association marker
clearing stays as public behaviour after its stamp, distinct from the private no-op's refusal; the
cleanup is the guarded unmanagement (removal plus the null association when the captured original
is still requested), never membership-only; legacy fallback only at the initial refusal, unsupported
backend and exhaustion boundaries, with the full legacy sequence (its own cancellation) and the
legacy remainder (after the qualified cancellation) kept distinct, their extra stamps part of the
exclusion; the property write's boolean means Qt accepted the write, not that the assignment
completed. The source review added: the explicit post-preparation context check is observable only
where a decision precedes the ingress (the equal path, the known-shortage selection), since the
chained provenance stops the ingress at its entry anyway; a null target runs no ingress, so the
cleanup's own membership increment is preflighted by the setter (a known shortage selects the
legacy remainder, as for a destination); the ingress reserve is zero or one, nothing
general-purpose; a superseded ingress is an incomplete assignment whose writes stand, distinct from
a refusal. The explicit post-preparation context check is kept as required but is not
independently discriminable: the only callbacks during the preparation are the release's, and
either the chained provenance or the release's own verdict stops the setter just the same.

The step-level consult on NT02.5a2b2c split the X11 specialization: NT02.5a2b2c1 qualifies the
guarded geometry request and the association, forget, membership and setter paths for X11 windows
that need no unmaximize (a maximized X11 window is refused by the association step's preflight and
keeps the legacy remainder until NT02.5a2b2c2, the X11 normalization). Required: the X11 guarded
geometry body is X11's own (the Wayland publication helper is not reusable), preserving the native
rounding, the frame/client/buffer conversion, the buffer scale and output selection, the native
configure and the rule, stacking, shape and geometry notifications, validating after
`frameGeometryAboutToChange` and before the prepared values are written, versioning the committed
publication and sealing the carrier before the changed signals, and revalidating between them;
never the public move-resize from the guarded dispatcher. X11 is not unconditionally synchronous:
an unmanaged window and blocked geometry updates are refused by the read-only predicate before the
shared request writes its rectangle and before any parent mutation, and rechecked at the dispatch
(a block raised by a callback supersedes rather than reporting a publication). The immediate tile
commit is the association write's own publication through a hook that takes the carrier by
parameter (never an ambient current operation): a guarded entry validates the incoming
continuation before committing, leaves an equal committed tile alone without a fresh checkpoint,
seals only its own write and checks the full currentness (checkpoint and provenance) after
`tileChanged`. The operation's sticky result stays apart from the association-write obligation: a
superseded geometry request still publishes the still-current association, without resurrecting
the operation; only a successful operation adopts the commit's checkpoint, after validating the
incoming one; no fresh full-operation checkpoint after arbitrary callbacks. Two committed changes
are budgeted before parent mutation: the committed geometry inside the request (already reserved)
and the committed association in the obligation (a committed-association revision and one more
placement increment, for the forget step too). Commit first, then `requestedTileChanged`, with
the association's revision, target identity and presence and the marker rechecked after the
commit's callbacks. Public X11 paths keep their cancellation boundary and legacy ordering; the
exclusion is removed only for the newly qualified cases. The source review added: the X11 body
keeps undelivered notifications for the next committed update, as the Wayland publication does,
and revalidates at every boundary (a newer update or the closure ends the frame's announcements);
the commit writer validates the full carrier, checkpoint and provenance, before its secondary
notification; the forget step's terminal validation sets Superseded explicitly, since the
publication promoted its carrier; the stale backend comment in the membership ingress is deferred
to NT02.5a2b2c2. Its follow-up added: an unchanged guarded publication delivers what an older
superseded frame left pending under its own versioned, validated continuation (a repeated
unchanged guarded request must not report success over stale consumers), and the revalidation
after the first notification is controlled rather than described as indistinguishable, since its
removal also removes the closure-triggered clearing.

### X11 normalization split

The design consult on NT02.5a2b2c2 (the X11 normalization) found that X11's decoration
transition writes geometry synchronously: `createDecoration` and `destroyDecoration` call the
public move-resize, and a real decoration's border reaction to the maximize signals reaches
`checkWorkspacePosition`, which calls it too, so the Xdg override's rule that the written fence
holds across every decoration signal would supersede every decorated X11 window's normalization
under Breeze, which the pipeline's container loads for the Tiles suite's default X11 fixtures.
The reviewer rejected crossing that transition with a by-value validation: the public move-resize
advances the request generation as well as the placement revision, so no clause set separates the
operation's own reaction from a foreign public move inside a callback, and a fresh checkpoint
afterwards cannot establish which writes belonged to the normalization. The preferred design
routes the identified internal reactions through the operation (a scoped recorder that suppresses
the known reactions without granting ambient ownership to public calls, covering creation,
destruction and border changes, preserving gravitation, the client/frame conversion, the
workspace-position effects, the frame extents and the notification obligations, with receipts and
budget coverage for any retained internal write and a bounded recorder lifetime bound to the
decoration identity); a mutation-free exclusion is accepted as a temporary bound, not as the
completion of decorated X11 normalization. The leaf is split accordingly. NT02.5a2b2c2a
qualifies the X11 normalization for the undecorated window (the client-decorated X11 application;
fixtures through the motif no-decoration hint) and refuses, mutation-free and documented, a
decorated window and the borderless-maximized policy; NT02.5a2b2c2b routes the decoration
reactions explicitly and qualifies them on Breeze-decorated fixtures, including the borderless
recreation and a foreign public move inside a decoration callback.

Contract of NT02.5a2b2c2a, from the consult. X11 overrides `normalizeMaximizeForAssignment` and
`canNormalizeMaximizeForAssignment`; the ingress, its preflight and the compatibility setter
already call them, so the maximized undecorated X11 window leaves the legacy remainder without a
change to those paths. X11's mode is requested and effective at once, so the revision lives on
`X11Window` (one saturating writer for every runtime write of the mode, the legacy `maximize`
included; initialized normally; pinned by the receipt so a change away and back cannot revive
it). The receipt freezes X11's complete geometry constraints by value, not the minimum and maximum
alone: the size hints (minimum, maximum, resize increments, base size, aspect), the
strict-geometry rule and the decoration state, since `constrainClientSize` reads them all; a
relevant change at any boundary supersedes. Mutation-free refusals: the decoration recursion
guard, an owner or an active request, an unresizable or applet-popup window, an interactive or
electric-border operation, a rule-forced maximize, an unsupported request (unmanaged, blocked), a
fullscreen window (the legacy Restore branch would send it to the fullscreen area, which is no
normalization for tiling; a fullscreen assignment whose mode is already Restore is not excluded
by this), a decorated window or the borderless-maximized policy (2c2b), an invalid prospective
restore rectangle (the stored values on the maximized axes merged with the current ones on the
others; the whole stored rectangle being invalid is not by itself a refusal), and the headroom
clauses. A requested mode already Restore is the operation-owned no-op with a fresh checkpoint
and a receipt. Otherwise: the entry snapshot, `maximizedAboutToChange(Restore)` as the first
boundary (fenced state, provenance, revision, constraints), the mode write through the writer,
and from there every stop is Superseded, never Refused (a restore validity lost after the write
included). The restore capture follows the legacy block exactly (the non-maximized axes refreshed
from the entry geometry, skipped while a quick tile is requested) through the guarded restore
writer, before the decoration transition point; the final rectangle is read after that point, as
the legacy Restore branch reads its starting geometry after the decoration reactions, with the
maximized axes taken literally from the restore and the size through `constrainFrameSize` with
the any-size mode; the request uses the move-resize mode (never the current mode's accidental
equivalence) through the guarded request, and an applied request marks the window placed. The
publication is the mode write's own obligation, gated by the live window and the specific
revision independently of the geometry's outcome, in the legacy order: the NET state (a property
write without callbacks), `updateAllowedActions` (which emits signals, so the live window and the
revision are rechecked after it), the maximize rules, and `maximizedChanged` last; the obligation
completes before the returned outcome is decided, and the result's currentness is re-evaluated
after it so a callback of the publication cannot leave a stale success. The override takes no
geometry-update block (the guarded body is the single committed publication and refuses while
blocked). The stale backend comment in the membership ingress is corrected in this leaf. Tests in
the Tiles suite: a function for the override with the supported path on undecorated fixtures and
the exclusions on the default decorated fixtures; the flipped ingress and setter rows on
undecorated maximized fixtures; a decorated maximized X11 window stays on the legacy remainder,
documented; a control per clause. The source review added: the first boundary's constraints
clause is independently discriminable (its removal lets the mode be written before the receipt
rejects the change), so it is controlled rather than described as caught later; rows lapse the
incoming provenance inside the first boundary and change the resize increments, the aspect
presence and the base-size presence synchronously inside the restore notification (the client
writes the hints and round-trips, the window re-reads them through its hints object), each with
a control omitting that clause or field; the recursion guard is stated as reachable through a
cross-window decoration callback and not exercised; the owner, active-request and allowed-actions
statements are unexercised coverage, not equivalence.

### X11 decoration transition

The design consult on NT02.5a2b2c2b accepted routing the identified internal decoration reactions
through the normalization with a scoped recorder, with these Required corrections, which fix the
contract. Recording scope is separate from call ownership: the recorder is passed explicitly
through the normalization's private policy, update, create and destroy helpers, and the public
entry points keep their ordinary behaviour, so a foreign policy change or decoration invalidation
inside a callback still writes through the public paths and is detected by the written fence; the
border-signal hook records its identified reaction (the workspace check and the frame-extents
update) only for the recorded decoration incarnation. Every callback-producing helper on the owned
path revalidates before continuing (the decoration's own notification, the input-shape and
border-radius updates, the shadow update, the policy notification), so a closure or a replacement
inside any of them stops the obsolete helper. The owned path takes no geometry-update block, since
the unblock sends a configure even when every write was recorded; the public path keeps its block.
The reactions are folded, in their legacy order, into a planned rectangle that starts at the entry
geometry: a creation or destruction maps it through the same gravitation and frame/client
conversion the legacy write would apply, and a recorded workspace check maps it through the pure
computation; the final rectangle takes the maximized axes from the restore and the others from
the planned rectangle, is constrained and requested once, so the X11 body commits the client and
buffer rectangles under the new borders with accurate notifications for the committed result
(including a client change with the frame unchanged), fabricates no notification for a rectangle
never installed, and leaves the legacy path unchanged without a recorder. The supported reaction
sequences are bounded explicitly (the kept decoration's border reactions; the borderless
recreation's creation, update check and any border reaction after it); any other recorded sequence
supersedes. The receipt is established after the transition only once the authorized changes are
validated: the written fence, the provenance and the mode revision; the client-side constraints
unchanged (the rule-checked limits, the increments, the base size and aspect with their presence,
the strict-geometry rule, the client frame extents, the Xwayland scale); the exact decoration
incarnation and policy transition, through a saturating decoration generation advanced by every
decoration change and a saturating policy revision advanced by every policy write, so an
away-and-back change cannot hide; the post-transition border metrics, which the receipt pins with
the rest. The frame-extents update is an obligation keyed to the decoration incarnation,
discharged whatever the geometry's outcome, so a superseded request never leaves the extents
describing the old decoration and an obsolete recorder never overwrites a newer decoration's
extents. A requested quick tile or another special state at the workspace check is refused
mutation-free until its restore-field effects are supported. The budget stays unchanged only if
the settled implementation adds no guarded write needing a reservation. Qualification on
Breeze-decorated fixtures adds: a foreign public policy change or recreation during the owned
transition; a closure or replacement from the decoration, shadow or border-radius notifications; a
late decoration replacement during the final client-geometry notification ending Superseded; the
frame extents consistent after a supersession; the client-observed configure count (no unblock
configure); the quick-tile exclusion; a client change with the frame unchanged when the borders
are restored.

The leaf is split. NT02.5a2b2c2bp (prerequisite) extracts the pure workspace-position computation
from `Window::checkWorkspacePosition` as a bounded decision: nothing for the deleted, dock, desktop
and unplaceable early returns, the special-state branch left to the legacy wrapper (it also writes
the fullscreen and maximize restore fields), and otherwise the rectangle after the strut, edge,
offscreen, size-constraint and rule checks; the wrapper keeps its write order and callback
semantics by requesting that rectangle; it also adds the decoration generation in `Window`
(advanced by every decoration change) and the policy revision in `X11Window` (advanced by every
policy write), each with its saturating writer. NT02.5a2b2c2b then routes the transition as
above.
The implementation of NT02.5a2b2c2b added, from its runs: the recorder's currentness closure is
defined on the checkpoint minted after the restore capture, not on the fence before it; the
recorder is bound to a newly created decoration before that decoration's initial state is
applied, since the application announces the borders and would otherwise take the legacy path;
the supported recreation sequence therefore allows border reactions between the creation and the
update's own check; and the decorated rows force a normal border size, because the automatic
border size follows Breeze's recommendation of none, under which a maximized and a restored
decoration have the same borders and no border reaction occurs.
The source review added: the installation behind the decoration setter is an owned path in the
base window that reports the installed incarnation's generation at its commit, before any observer
runs, and withholds its final notification once that incarnation is gone, the public setter
unchanged; the recorder expects, at every boundary, the incarnation and the policy revision it
recorded for, advanced only by its own creation and the operation's own policy write, so a foreign
policy-only change or a bare generation advance on the kept decoration ends the operation at the
next boundary and the later maximize signals are not emitted; the recorder's active scope ends
before the geometry request; each helper's own obligations (the shadow, the frame extents, the
policy's rules and notification) follow its own write's currentness, not the operation's; the
frame-extents obligation is gated by the recorded incarnation's identity and generation; the
quick-tile exclusion covers the borderless recreation, undecorated at entry; and the post-transition
comparisons are a redundant layer behind the closure's clauses, with the controls targeting the
clauses through rows that observe a suppressed notification or a counted property write.

### Transient admission receipt

The design consult on NT02.5a2b3 reconciled the roadmap row with what the compatibility setter
already implements: its "original-membership cleanup" wording came from the compatibility
assignment, which `Window::setTileCompatibility` now performs under guard, and it is no permission
to turn the automatic admission into a manual-tile takeover. The leaf qualifies the admission's
existing native operation and broadens no eligibility. An ordinary membership anywhere stays
ineligible (`freeOfNativeMembership`; the ownership contract makes an existing manual association
ineligible, and removing memberships first would change both the eligibility and the meaning of
the persisted floating frame); cleanup means releasing this attempt's captured transient
membership and matching associations through the generation-specific release, preserving a manual
membership or association a callback installed, never public untiling or the ordinary
unmanagement step. X11 stays refused before any reservation or membership: the backend boundary is
`canStartTransientTileRequest()`, false on X11, checked by the ownership preparation before it
allocates or reserves and by the controller's complete preflight before any provisional admission
mutation, the window-level checks kept as defence in depth; the guarded ordinary geometry support
of NT02.5a2b2c does not establish transient admission support, and no X11 override is added.

Receipt consumption: the membership-only revision check (a bare revision pointer closure for the
publication) is replaced by a checkpoint minted after the admission's own callback-free writes
(the ownership activation and the membership add) with an admission-bound provenance, carried
through the controller-only add and publication path (the ordinary `manageForAssignment` is not
called on the transient tile and its transient-target rejection is not weakened) and through the
native request. The geometry result's provenance of kind Request borrows the request pointer that
`requestTransientTile` consumes and destroys, so the admission cannot simply return that result:
either the request is retained for the whole validation interval, or its validated continuation is
translated, before the destruction, into a stable generation-bound provenance that preserves the
checkpoint (never a checkpoint replaced after callbacks). The transient request receipt keeps its
progress, ownership generation, native sequence and NoRequest proof; the assignment result
supplements that restoration evidence. The stable admission provenance binds the controller, tree
and leaf identity with the generation, the exact window and ownership generation (not merely the
controller's current window), the writer and provider incarnation, the reservation and the frozen
native context, and the admission's continuing validity; where `transientOwnershipIsCurrent`
rejects an executing owner, the provenance appropriate to each lifecycle phase is chosen rather
than bypassing that condition.

Preflight and ordering: before the ownership activation or the membership publication, the
admission validates a live, current tree, leaf, manager, output and desktop with no teardown or
competing admission; the window's eligibility, unique identity, one matching desktop and activity
and the placement key; no ordinary membership anywhere, no requested or committed association, no
owner, no active request, no unresolved transient marker; the backend's admission readiness, the
settled native geometry, a finite floating frame and a feasible target; the frozen writer,
provider and map revision with the durable reservation through the existing writer protocol; and
the headroom for the entire selected synchronous path including its structural failure cleanup
(the membership: the transient addition and a possible release removal, so the entry revision
below the sentinel minus two; the requested association: the install and a possible detach,
likewise; the placement: the restore capture plus the guarded request's bound; the geometry
request and update generations: the request and a possible synchronous publication; the ownership
and native sequence under their non-reuse and exhaustion rules), never only the successful prefix,
the later asynchronous commit headroom kept distinct. After the activation and the addition the
operation's own writes are sealed before `windowAdded`; the full currentness is validated after
`windowAdded`, after `windowsChanged`, through the native request and after the final publication;
Accepted requires a successful native receipt and a current continuation; a later failure is
Superseded with the generation-specific release, never a fallback or a refreshed authority, and
Requested progress still retains the record and the barrier when the restoration cannot finish.

Files: the controller's header and source, Window's header and source, and the Xdg test, where
the controller admission fixtures are (the consult assumed the Tiles test; the Tiles suite holds
the membership-during-admission rows and the X11 fixtures, so the X11 refusal row goes there as
a sixth file); the affected Xdg suite rows (the delayed commits, the NoRequest finalization) run
alongside. The receipt-lifetime prerequisite is split out rather than weakened
to fit the bound. Rows: the membership publication superseded at each notification including
counter-free context and provenance changes; the controller, leaf, window or writer destroyed
during the admission; the ordinary-membership rejection on active and inactive desktops and other
outputs; the X11 rejection with no reservation, membership or association effect; a known headroom
shortage before the publication; a callback-installed manual placement surviving the failed
admission's cleanup; a retained old request or receipt and a delayed commit after revocation or
readmission; a NoRequest failure against a Requested failure with the right persistence barrier;
a success that goes stale at the last callback.

The confirmation split the leaf. NT02.5a2b3p (prerequisite, Window and its test only; the
controller untouched, no admission broadened, no release policy changed, no claim that the
controller consumes the result yet) produces the safe qualified continuation alongside the
existing transient request receipt through an internal aggregate or guarded overload, the
receipt's progress, identity and NoRequest proof preserved. Translation rules: the borrowed
Request-kind continuation is validated while the request still exists; its checkpoint is preserved
exactly (no fence minted after the request's callbacks); the borrowed authority is replaced by
bindings that survive the request's destruction (values, guarded identities, a stable constraint;
never a closure calling the request's authority through the destroyed request); the result is
revalidated after the request's destruction, after the executing flag is cleared and after any
release or finalization callback, before current success is exported; the exact ownership
generation and the native attempt sequence are bound (the same window and controller identity is
insufficient after a release and readmission); a successful receipt is evidence of that attempt,
not permission to replay it; and the later controller caller gets an explicit way to supply its
stable admission constraint, window-only checks never silently substituted for the controller,
tree and admission bindings. Phases: Prepared is reservation only (no completed-application
continuation, no ownership exemption); Owned and activated before execution may support the
controller's provisional membership continuation but is no evidence that the request completed;
Owned and executing validates internally through the live request and exports no terminal current
success; Owned with the request finished exports a current qualification only after the execution
ended, the active request is cleared and the exact attempt, checkpoint, reservation and admission
constraints still validate; Restoring or releasing invalidates the application-success
qualification while progress and proof are preserved for the release machinery; a closed window,
a removed record, a lost writer or controller, or a superseded attempt invalidates it, never
refreshed or retargeted. The existing Ownership provenance with a stable constraint may express the
finished phase if its rejection of executing and releasing owners stays intact; the terminal
descriptor may be constructed before the destruction, its successful validation happens after.
The initial untiled readiness predicate is not reused after the request installed its association,
and generic owner validity (which permits later owner operations) is not the full continuation
predicate. Its rows drive the ownership preparation, activation and application directly with
the real writer protocol, the real backend checks and a narrowly scoped test request whose
authority callbacks own stable test state, and prove: the request's destructor ran before the
returned qualification is checked; success stays current after that destruction; geometry,
membership, association and stable-authority changes invalidate it; Prepared, executing,
restoring or releasing and revoked states yield no completed current success; a release and
readmission cannot make an old receipt current again; reentrancy from the request's destructor can
invalidate the result; failed and Requested attempts keep the right progress and barrier semantics.
The controller fixtures stay regression coverage during the prerequisite and become the direct
qualification suite when NT02.5a2b3 consumes the carrier.

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

The controller remains the root's QObject parent and the sole deletion authority. Reviewed
NT02.4 integration adds a weak manager index and pre-destruction drain rather than changing
parentage, preserving one unambiguous owner and the already-tested deletion model.

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
