<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Native ownership proof for custom KWin

Status: the owner approved continuation of this first-milestone plan on 2026-11-02.
NT01 is complete; NT02.1 is the active leaf. The [scope](../docs/NATIVE-TILING-SPEC.md) does not enable the tiler.
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
