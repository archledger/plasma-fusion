<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# NT03.0: content and placement decision

Status: characterization completed; the narrow policy below passed independent review.
Native baseline: `0eb27d9eb6b8ad0feb8554b5c763c488f7a67c7b`. No native implementation changed.

## Measured behavior

A disposable Xdg test copy exercised eight cases: unowned or generically released controller
ownership, newer move or resize, and old ACK request before or after the newer intent. The old
buffer was committed only after the newer intent. Assertions checked fixture/protocol validity,
not whether the measured behavior was a safe restoration contract.

The diagnostic passed 10 Qt checks; the full copied Xdg suite passed 594 with no failures, skips
or blacklisting. Its production library was byte-identical to the main baseline. A scoped
Memcheck run passed the same ten checks with zero errors/contexts/suppressions and the same
selected geometry/state observations. That memory result uses QT_HASH_SEED=0 and leak checking
off; it is not an AES-path or leak-free claim.

| Newer intent | Old content commit | New requested rectangle |
|---|---|---|
| Resize | Old buffer size and old configure position appear in the committed frame | Preserved; the later current commit reaches it |
| Move | Old buffer size is accepted at the already-moved position | Preserved |

Both patterns held for unowned and released-owner rows, and for both ACK request orders.
The controller's padded B differed from the ordinary B, so this is a behavior-pattern comparison,
not a pixel-identical A/B test. In released-owner rows the old tile association did not return,
and the Restoring record and writer barrier remained.

ACK alone changed no observed geometry. This is protocol request ordering, not proof of two
different compositor-side ACK application times: `xdg_surface_ack_configure` stores pending
state, and `XdgSurfaceInterfacePrivate::apply()` emits `configureAcknowledged` on surface commit
(`src/wayland/xdgshell.cpp`). `handleNextWindowGeometry()` starts from current position and may
then apply configure bounds/gravity. The move path clears queued position flags; the resize
path retains them (`src/xdgshellwindow.cpp`).

## Accepted policy for subsequent implementation

This is a design decision motivated by the observations, not behavior already implemented by
the baseline. It applies to protected restoration only; ordinary unowned behavior is preserved.

| Classification | Content/size | Compositor placement and requested state | Completion |
|---|---|---|---|
| Genuine ordinary configure | Existing behavior | Existing behavior | No restore authority implied |
| Identified obsolete admission/restore configure in protected flow | Accept valid content under normal protocol rules | Do not use obsolete bounds/gravity or synchronize current requested geometry from it; retain current committed origin for that content | Cannot complete restoration |
| Exact current restore identity and request generation | Normal validation | Only the current authorized restore may supply placement | NT04 still needs its native completion proof |
| Lost/unknown provenance within protected flow | Do not reject valid content wholesale | No ordinary-placement fallback and no borrowing the latest restore token | Cannot complete restoration |

The current committed origin is not necessarily the pending requested origin. Do not jump content
to a future requested position merely because a newer resize is outstanding. Accepting old
content is not by itself a new manual intent and must not cancel a newer asynchronous restore.
Conversely, this policy never authorizes refreshing a stale synchronous checkpoint.

## Limits and re-entry gates

- No actual restore attempt or metadata was implemented. A normal newer request after generic
  revocation was the observation vehicle; R3/R4 need their own discriminating RED/GREEN tests.
- No serial wrap, decoration/scale transition, output removal or second live provider was tested.
  R4 must exercise actual wrap and any matcher changes before claiming its path safe.
- No rendered-pixel inspection occurred; accepted buffer dimensions and native geometry were
  observed. The ordinary resize frame history is not, by itself, a product bug.
- The raw log, 58 snapshots, parser with row/stage uniqueness checks, source hashes and memory
  evidence are retained under the shared `2026-11-05-issue115-old-buffer-characterization` artifact.

This closes NT03.0's characterization/decision gate. NT03.1 and NT03.2 can proceed under the
approved plan. It does not qualify restoration, public action routing, NT04 completion or deployment.
