<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# One-window native ownership contract

Status: reviewed NT01 contract for isolated implementation, not an implemented API.
Names below are proposed additions.
Baseline: [NT01 source and runtime](../tasks/nt01-baseline.md).
This document narrows the approved [scope](NATIVE-TILING-SPEC.md); it does not enable tiling.

## Selected boundary

Put transient ownership inside KWin. Introduce a `TransientTile` derived directly from `Tile`,
not from `CustomTile` or its `RootTile`. Give `Tile` an immutable internal kind distinguishing
transient nodes from manual and quick nodes. For existing native tiled-state/Restore dispatch,
transient leaves report `QuickTileFlag::Custom`; the internal kind, not that shared flag, decides
their ownership and destruction rules. No new public quick-tile bit is needed.

`TileManager` parents separate transient roots indexed by desktop. They have no `TileModel` and
never enter the manual root map, position picker, JSON serializer or saved `kwinrc` layout.
The initial root has one leaf for the selected window; structure changes are controller-only.

`Workspace` owns a `TransientTileController` and the placement writer described below. Each Window
owns its authoritative native ownership/restoration record; the controller keeps references or
index entries, not a second mutable copy. Records survive tile managers, policy modules and
controller teardown without keeping those objects alive. The session writer must outlive
outstanding records; its destruction is terminal unavailability, not permission to re-adopt via
a replacement writer. Neither controller nor record keeps a dead output alive.
Use the established native lifetime rules around calls that emit signals; `QPointer` observes
destruction but does not keep an object alive across a reentrant operation.

Before clearing tile managers, `Workspace` explicitly shuts the controller down. While the
session is live, output removal detaches its transient memberships before `outputRemoved`
observers and before manager destruction. The tile manager's desktop-removal path detaches before
deleting that desktop's roots; its destructor performs idempotent fallback detachment before
setting `tearingDown`. A transient node's destructor also requests fallback detachment if needed.
All such paths empty memberships before the `Tile` base destructor runs. The transient-kind
branch never falls back to assigning a manual tile. Session shutdown cancels native ownership
without sending new requests through a half-destroyed workspace; the persisted A remains intact.

The previous external-root adapter is rejected as the product boundary: its roots are absent
from native lookup, eviction and output/desktop teardown. Adding more geometry observers would
not fix that ownership gap. Existing native transitions remain the implementation path.

## Proposed interface

The C++ controller provides non-mutating admission inspection, one adoption attempt, and explicit
release for a particular ownership generation. It returns a typed result: accepted, unavailable,
ineligible, busy, invalid geometry, stale snapshot, missing persistence acknowledgment or
synchronously superseded.
No failure is reported as a successful no-op.

An accepted adoption means KWin accepted the request, not that a Wayland client has committed it.
Release means ownership was revoked and restoration started, not that restoration finished.
Repeat release for the same generation is harmless; an old generation never affects a new owner.
No automatic retry or timer-driven placement is part of this interface.

Proposed read-only window properties are `transientTilingState` and `transientTilingToken`:

| State | Meaning | May normal placement memory record this window? |
|---|---|---|
| None | No ownership or restoration is outstanding | Subject to recording guards and intent watermark |
| Owned | Automatic ownership exists, including a pending tile configure | No |
| Restoring | Ownership ended but its native restoration is outstanding | No |

The token is opaque text to QML, not a JavaScript number. A native monotonic generation binds it
to the actual window and admission snapshot; generation exhaustion rejects new work rather than
wrapping. A state-change/completion notification lets the consumer re-evaluate recording.
Precise public exposure is additive and version-gated. It must not advertise a usable tiler while
the persistence bridge is absent. C++ tests may inject a test provider; no production bypass or
QML setter for acknowledgment is permitted. ABI changes require rebuilt consumers, not a claim
that equal version strings imply compatibility.

## One writer and provider incarnation

For the qualified custom-KWin session, move the existing placement file's writer into one
compositor-owned `TransientPlacementWriter`. It uses existing KConfig and the existing version-1 JSON
format at `plasmafusion-placementrc`; it is not a second file or journal. The paired QML provider
retains its existing eligibility/quiet-period policy and rounding, but submits typed record
updates to this writer rather than calling Plasma's `evaluateScript`. Stock KWin keeps its
unchanged legacy path. Switching a live legacy writer to native mode is not supported: initial
qualification and deployment require a fresh paired KWin/Plasma session with the matching
package-provided placement script selecting native mode before its first write. If that startup
and provider version cannot be established, admission stays unavailable. Arbitrary user scripts
or external editors writing the same file are outside this sole-writer contract; this is not a
claim that KWin can discover every external writer.

The writer accepts only one registered provider QObject. Registration gets a native incarnation
token; destruction retires it before a replacement can register. Every submission carries that
token, a strictly increasing provider revision, the source window identity, canonical key and
already rounded rectangle. Revisions/tokens are opaque to QML where numeric precision matters.
Retired or out-of-order submissions are rejected, including calls from a destruction callback.
There is no direct-write fallback in native mode.

The native writer owns the authoritative in-memory map and pending updates. It coalesces
ordinary updates using one flush timer; it does not queue work in another process. A provider
reload cannot abandon an asynchronous Plasma write because native mode creates none.

Keep two map revisions: `mapRevision` identifies the current in-memory map and
`persistedRevision` identifies the last successfully synced/read-back map. Deferred reserved-key
events have their own intent sequence and do not change the visible map until their barrier ends.
Provider replacement retires the old incarnation, then immediately receives the current map,
both revisions and its dirty status. It does not require a successful flush. Already accepted
ordinary updates remain available for best-effort restoration, and unchanged valid records stay
usable despite an unrelated ENOSPC, lock or write failure. No legacy writer is re-enabled.

Durable **admission** is separate: before granting a reservation, complete the pending flush,
require `KConfig::sync()` success and verify A with a fresh, non-shared read. A failed flush/read
keeps the map dirty and refuses adoption, but does not block ordinary reading or restoration.
A replacement provider submits updates against its new incarnation and published map revision,
never an independently cached full-map replacement. A successful later flush advances
`persistedRevision` and can make admission eligible again.

Admission and writer mutation run on the compositor thread with a reentrancy guard. The guarded
flush/readback/grant region does not enter an event loop or emit provider callbacks. Reentrant
calls are refused, not silently queued as a second adoption. Publish notifications only after
the transaction state is committed. Normal writes for other keys remain independent.

The test provider uses this same reservation/incarnation protocol with a controlled backend,
not an unconditional acknowledgment boolean. Add its tested native state primitive before any
native adoption unit in NT02;
connecting the real QML provider remains NT07 work. No real adoption is enabled in between.

## Admission transaction

Only one explicitly selected ordinary window is managed in this proof. Check without modifying
the window: liveness, unique identity, one desktop and Activity, current output/context generation,
movability/resizability, both requested and committed tile/maximize/fullscreen state, pending
native transitions, and a finite feasible target rectangle. An existing manual tile association
on another desktop also makes the window ineligible. No unmaximize or resize may be used as a
capability test.

Admission uses this sequence:

1. Capture floating frame A and the window/context snapshot. There must be no outstanding native
   geometry transition. The initial proof rejects ambiguous per-app placement identities.
2. Wait for the existing placement consumer to become ready through its ordinary write path.
   Do not force recording during its quiet period or bypass eligibility/rule checks.
3. Freeze the key against ordinary updates, drain accepted pending updates through the native
   writer, require explicit sync success, and independently read the existing placement file.
   Its entry must equal A for the same provider incarnation, revision and native snapshot.
   Otherwise release the tentative reservation and refuse adoption without changing geometry.
   A successful legacy D-Bus reply is insufficient: the read-only control returned `true` with P.
4. Revalidate the complete native snapshot before any automatic geometry or owner mutation.
   Reject if the window, context, target or consumer revision changed.
5. Atomically bind the granted reservation to the ownership generation and enter Owned. This is
   the adoption linearization point, before membership or geometry notifications are emitted.
   Then attach the native membership and request geometry through controller-only operations.

After every signal-emitting operation, check liveness, the exact ownership generation, current
context, and owned-operation constraints again. Do not reuse the initial untiled predicate after
the operation has intentionally changed tiling state. A callback-triggered release, close,
context change or constraint change prevents the outer adoption from continuing. Return
`Superseded` rather than `Accepted`; if geometry was already requested, the surviving record
performs restoration. A retained window reference alone does not preserve eligibility.

## Global key conflicts and close precedence

Use exactly `Placement.appId`: desktop-file basename, remove a trailing lowercase `.desktop`,
then lowercase; fall back to resource class. Preserve its test vectors. Key uniqueness is global
across all live windows eligible for placement recording, not restricted to the current desktop
or Activity. A must also be exactly representable by `Placement.valid` without rounding and
within its size limits. Refuse non-representable fractional A in this proof.

While K is reserved, accepted writes for other keys proceed normally. A new eligible instance
with K, or a relevant identity change, revokes the owner. Legitimate manual record updates from
other K instances are kept as the latest deferred update by accepted revision; they do not replace
persisted A until the owner has either completed restoration or been destroyed. An unresponsive
owner keeps K reserved, even though that delays another same-app update; it does not block other
keys. Closing that owner releases this barrier after close dispatch/destruction.

On owner close, invalidate adoption but retain native suppression through all `closed` handlers
and until QObject destruction. Its automatic rectangle is never a valid close update. Only
then clear its record/reservation and apply the newest eligible deferred same-key manual update,
if any. That later manual update wins over A; the old owner's close does not win over it. If no
such update exists, A remains. Submissions from a destroyed source or retired incarnation are
rejected. A legitimate ordinary-window close update must have been validated and accepted while
that source was still alive and unowned; its immutable pending data may survive destruction.

The same priority applies on **restoration completion**, not only on close. If a deferred manual
update M exists, make M the key's winner when releasing the reservation. The restored owner's
completion-generated A must not overwrite it, even if that callback has a newer provider revision.
Keep a per-window restoration-event watermark: completion-generated geometry, its delayed
notifications and a close without a new eligible geometry change cannot replace M.

Stamp geometry origin/order inside the native transition before emitting notifications; do not
trust a provider-supplied "manual" label or use arrival order as user intent. A genuinely later,
eligible non-restoration geometry change by the previous owner advances that native watermark,
clears its post-restoration recording hold, and may become the new per-app winner. This includes
the explicit later user move/resize test. Other unowned windows retain ordinary recording rules.
Without a deferred manual winner, completion may re-record the restored frame subject to all
normal guards. The rule prevents a synthetic restore from winning; it does not suppress later
legitimate user changes indefinitely.

The native writer merges validated per-key updates, never a stale provider's full-map snapshot.
This prevents delayed whole-map flushes from restoring an automatic B or clobbering other keys.

If the provider is missing, readback fails, the file is invalid/immutable, or P differs from A,
adoption is unavailable. Keep the ordinary stock placement behavior. The contract covers a
compositor interruption, not power failure or arbitrary external edits to the owner's settings.

## All transient mutation entry points

`Tile::manage()` rejects transient receivers before any eviction or membership change. The
controller uses a distinct private, non-invokable management operation with an explicit native
operation token, not an ambient/thread-local bypass that a reentrant callback could inherit.
Its internal steps perform the post-notification checks above.

Public transient `unmanage()` routes to generation-checked manual release. Compatibility writes
to `Window.tile` reject a transient destination before touching the previous tile; writing null
for the current transient owner routes to release. A normal manual-tile destination revokes the
automatic generation before normal assignment. Retained tile references follow these same rules.

Transient geometry, padding, minimum-size, resize and structure mutations are controller-only.
Guard the base non-virtual setters/invokables as well as derived methods; subclass shadowing
alone does not cover inherited Qt properties. The one-window node starts with fixed padding and
structure. Internal geometry updates use explicit private operations, never a publicly writable
authorization flag. Direct `forget()`/destruction paths use the controller's detach protocol.

Reject X11 adoption before reservation, eviction or any mutation, including compatibility
assignment and direct retained-tile calls. Manual frame setters, native interactive actions and
normal tile assignment must revoke automatic ownership through their documented native paths;
NT05 tests their intent without treating every internal geometry update as a manual action.

## Native transitions and restoration

Before emitting removal or geometry notifications, change Owned to Restoring. Save A until native
completion or window destruction. Never derive A from a later automatic rectangle B.

| Intent | Ownership outcome |
|---|---|
| Explicit `UntileOrRestoreOp` or policy disable | Release and restore the appropriate floating A |
| Ordinary maximize/fullscreen toggle back | Keep ownership and return to its managed rectangle |
| Internal unmaximize during a native operation | Not an explicit release command |
| Manual move/resize or manual/quick tile assignment | Revoke ownership; the user's new placement wins |
| Output transfer | Revoke the first proof's ownership and transform saved floating A once |
| Output removal or desktop/Activity membership change | Revoke before context destruction; use native fallback placement |
| Close | Suppress all close recording; discard tracking at QObject destruction |

Map intent at native action dispatch, including decoration operations chosen by
`operationMaxButtonClick`, menu actions and existing shortcuts. Do not replace bindings or infer
intent from the final maximize state. Preserve custom and unbound actions.

Wayland completion is associated with KWin's sent configure and the committed surface, not merely
receipt of an ACK, geometry equality or a delay. Capture the ownership generation in outgoing
configure state and accept completion only for the current restoration. A superseded tile commit
must not clear it. Copy needed metadata before callbacks can invalidate configure objects.
Exercise actual serial wrap in integration tests; an internal generation does not by itself fix
the baseline compositor's serial ordering.

Root/module unload leaves Restoring in the surviving compositor/window record. Reload cannot
adopt over it. A client that never commits stays suppressed; no timeout declares restoration
successful. A later manual action supersedes the expected target/generation so an old restore
cannot overwrite it. On close, A stays protected through close dispatch as defined above.

On compositor restart, transient ownership is not restored from `kwinrc`. Newly mapped windows
use the ordinary placement record. Test with P != A and an actual interrupted compositor as well
as orderly unload. Do not claim that a disconnected client's old process survived the restart.

## Native placement tracker and persistence

KWin's `PlacementTracker` independently captures requested geometry and replays it when output
layouts change. Protecting only Fusion's file is insufficient. NT06A must test this path before
choosing a correction: owned and restoring windows must not acquire a replayable B or have A
overwritten by output-layout restoration. Ordinary unmanaged windows retain existing behavior.

The Fusion consumer suppresses owned/restoring windows, then applies its usual eligibility,
quiet-period, sibling and rule guards on completion. A legitimate later manual location must be
recorded at completion when eligible, rather than only at close. Unknown native protocol/state
refuses automatic adoption; it must not disable all ordinary window memory.

The initial mutation tests use a controlled Wayland client. X11 gets explicit refusal/unmanaged
regression cases first; managed X11 support cannot be claimed without its own native completion
and constraint proof. This distinction must remain visible in the milestone report.

## Regression map and gates

| Retained evidence or requirement | New-source verification owner |
|---|---|
| Saved tree/restart and manual membership characterization | NT02 and NT08: unchanged manual model and serialized configuration |
| Registered versus external-root ownership controls | NT02: lookup, eviction and single ownership |
| Pending release, already acknowledged configure, later commit | NT03/NT04: generation-bound restoration and original A |
| Foreign/pending output transfer and callback lifetime tests | NT06: native transfer/removal and related-window closure |
| Settled/pending output and desktop removal-release controls | NT06: release before context destruction |
| Iteration8 `rel`, `own`, `sc`, `src`, `ua`, `ms`, `rl`, `scl` | NT04/NT07: release, close, stale/late commits, relayout and suppression |
| Iteration8 `mv`, `rr`, and its no-re-record mutation | NT07: later manual move and completion-triggered recording |
| Iteration8 `nom` | NT07: missing provider refuses adoption; normal memory still works |
| Newly required P != A and interrupted restart | NT07/NT08: exact persisted admission snapshot survives interruption |
| Unload/reload before commit and never-ACK client | NT04/NT08: restoration survives the policy/root lifetime |
| Native output-layout away/back and different current desktops | NT06A/NT06: tracker replay, one transform and one release |
| Constraints, identity collisions and stale admission snapshots | NT02/NT07: refusal before mutation and safe revocation |
| Provider retirement/reload, pending flush and readback failure | Admission primitive/NT07: incarnation fence and no stale full-map write |
| Callback cancels/closes/changes context during adoption | NT02: no continuation after supersession |
| Retained transient tile setters/manage and compatibility assignment | NT02/NT05: no controller/admission bypass |
| Same-key manual move followed by owner close during restoration | NT07: close-time suppression and latest eligible deferred update wins |
| Same-key manual move followed by restoration completion | NT02.1/NT07: synthetic A cannot overwrite M; a later genuine owner move N may win |
| Failed flush followed by provider replacement | NT02.1/NT07: ordinary map remains usable with dirty status; admission stays refused until successful sync/readback |

These are mappings, not new passing results. Keep all baseline controls and source-bound failure
receipts. Missing cases remain blockers. The first implementation gate is NT02's native
adoption/refusal/lookup proof, with production adoption unavailable until NT07 completes.

## Source references

- KWin baseline `src/tiles/{tile,tilemanager,customtile}.{h,cpp}`: ownership, notifications,
  persistence and destruction.
- `src/window.cpp`, `src/xdgshellwindow.cpp`: requested versus committed state and configure flow.
- `src/useractions.cpp`, `src/decorations/decoratedwindow.cpp`: command intent and custom bindings.
- `src/workspace.cpp`, `src/placementtracker.cpp`: output evacuation and layout replay.
- Plasma Workspace v6.7.5 `shell/scripting/{configgroup,scriptengine_v1}.cpp` and
  `shell/shellcorona.cpp`: configuration wrapper and D-Bus call lifetime.
- KConfig v6.31.0 `src/core/kconfig.cpp`: sync can fail; the wrapper does not return that result.

The baseline evidence pins these versions and source hashes. No older private patch or current
upstream behavior is substituted for the selected `.pf2` source.
