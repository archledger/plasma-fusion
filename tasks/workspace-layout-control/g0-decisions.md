<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# G0 decisions: workspace layout transport

Recorded on 2026-11-19 (UTC). The [interim receipt](g0-receipt.md) left four decisions to the
owner. It recommended an order of work and set out options for decision 3, but gave no answers
to decisions 1, 2 and 4. On 2026-11-19 the owner replied "Let proceed with your recommendation",
delegating the answers. The agent wrote the answers below that day and adopted them under that
delegation; the owner had not seen them before. The owner's review of the final G0 receipt
(todo.md, "Checkpoint G0") is therefore the owner's first review of them: the final receipt lists
each answer, including the changes to the G0 definition, for confirmation, and the owner can
revise any of them. Nothing here starts P1, changes production code or clears G0.

The receipt describes the probe at `e1977ac`. Since then, `49c65f2` covers a refused native
registration and makes the probe take its public label from a value independent of the native
token, as the receipt's P1 finding 2 suggests. P1 must do the same.

## 1. The transport is the basis for P1

Decision: yes. Saved request and response fields, a sequence-less wake-up and `evaluateScript`
on the captured unique shell connection carry P1's state.

Reasons: plan.md calls this the preferred candidate, and neither plan.md nor the receipt
identifies another inside plan.md's boundary, which excludes a native fork patch, a daemon,
polling and any new native RPC or object export. G0 items 1 and 2 are shown (item 2 for
read-only state on one panel), items 3 and 4 in part, and item 5 holds in the fixtures (receipt,
"G0 obligations"). The receipt states the cost: each request costs one save and one wake-up;
each scan costs a shell-owner lookup (in target mode also a PID lookup), two shell script calls
(read and publish) and one save per widget with a readable request; and each online frame costs
its receiver two `GetNameOwner` calls. In `v06`, 12 consumer requests and 16 wake-ups, the
driver's included, came with 39 publications to both widgets: 78 response saves. That cost is
acceptable only if publications stay rare.

Conditions on P1, from that cost, todo.md's P1 and the receipt's findings for P1:

- Publish only in reply to a new request or when the state a consumer holds has changed; a scan
  with unchanged state saves nothing. P1's lifecycle tests count publications.
- Keep the read/publish pipeline bounded and serialized, as P0 shows it first (decision 3).
- Version and check every request, not only target-mode `prepare` and `validate` (finding 1).
- Reject retained fields at start, and apply a saved mutating request at most once per request
  identity, however often it is read (findings 3 and 4).
- Keep the provider logic in the placement script, which owns the native registration and
  `tiler.session` (finding 6); consumers do not depend on the observed output-loss placement
  (finding 7).

Risk found later in P0: a publication is an `evaluateScript` call that the shell serves on its main
thread, and in the target scenario's instrumented runs a pointer click sent while one ran usually
lost its button events (`docs/DEFERRED.md`, the pointer button events row). If that holds outside
the test session, users' clicks on panel widgets could be lost the same way while P1 publishes. The
test scenario only works around it; the final receipt reports it for the owner's review of this
decision.

## 2. The identity alias is the production lifetime fence

Decision: yes, as a fence between provider lifetimes, not as authentication.

What it shows: a consumer accepts an online frame only when both `org.kde.KWin` and the frame's
alias are owned by the connection the frame names, and an offline frame only when `org.kde.KWin`
is owned by that connection and the connection and alias are the ones the consumer is bound to
(consumer.qml, `verifyPending`). For online frames that shows the provider lifetime the frame
claims is alive on the current KWin connection, and the probe shows that replayed frames of an
earlier lifetime and frames naming another backend are rejected. It does not show who wrote the
frame: an unsandboxed process with access to the user's session bus can call the shell's
`evaluateScript` and write a response field, as the probe's own injection tests do.

Why that is acceptable: such a process can equally drive KWin and the shell through their public
D-Bus interfaces, so authenticating the writer would add no boundary against it. A sandboxed
client whose filtered bus excludes the shell and KWin cannot write frames either; KWin also
withholds its restricted Wayland interfaces from sandboxed clients (fork tag
`v6.8.2-pf5`, `src/wayland_server.cpp`). Frames do carry the handle and lease that a consumer
sends back to act on a prepared target, and such a process can read and resend them. They give
it nothing it could not already do, because the provider checks the lifetime, the view and its
own guarded target before it acts (plan.md, "Contract to establish after G0").

Limit: the fence tells lifetimes apart, not scripts. Any KWin script runs on KWin's connection
and can request an alias that passes both owner checks. If a leftover probe or a second copy of
the placement script also published, consumers would drop one lifetime and bind to the other on
every frame. That stays inside the trust boundary, but P1 must keep a single publisher; the alias
does not enforce one.

Conditions: the alias stays identity-only, with no objects or methods; it is requested without
queueing and released at teardown; and its name derives from the independent lifetime label,
never from the native token.

## 3. Where the open items are met

| Open item | Where | Effect on the G0 definition |
|---|---|---|
| Bounded, serialized read/publish pipeline | P0: fix the probe (await each publication before the next read; bound the default reader as target mode is bounded) and count publications | None; it stays in plan.md's G0 section |
| A completion that newer state frames keep | P0, with a non-mutating `prepare`: its completion, decided once, is repeated unchanged in every later frame for that consumer until its request advances, while the target's validity is re-checked and reported separately (below) | Added to G0: it answers the receipt's question about plan.md's stop rule |
| Refused backend | P0: done in `49c65f2` (`--refused-backend-probe`) | None |
| Absent backend (no API, or no writer) | P0 unit cases (done in `49c65f2`); a native run on a stock-KWin image in P7 | G0 accepts unit evidence for this case (below) |
| Updates from the existing shortcut | P1, whose first item already requires them, before any UI | Moved out of G0 item 3 |
| Probe widgets on two bars, competing-bar ordering | P0 | None (todo.md, P0) |
| Restarts with a current target-mode seed | P0, through `lifecycle.py` | None (G0 item 4) |
| Keyboard entry after panel focus | P0, once a way to give the panel keyboard focus in the isolated session is found | None (todo.md, P0) |
| Mutating acknowledgements and timeouts | P5, with the first mutating requests | None in plan.md or todo.md; testing.md's G0 list is corrected |
| Fair arbitration; mixed shell/KWin replacement matrix | P7 qualification | None in plan.md or todo.md; testing.md's G0 list is corrected |

todo.md's P0 "timeout/late reply cases" are the query cases that `v22` shows. The specification
asks for "delayed state replies within the same provider/view, and a timeout followed by late
authoritative confirmation", and adds "An old reply must not overwrite a newer confirmed state."
Mutating timeouts belong to P5.

The receipt asked how plan.md's stop rule bears on acknowledgements. The contract says: "State
revision and request completion are distinct: an old state snapshot must not replace newer
state, but dropping it must not lose a relevant completion acknowledgement." Each widget has one
response field, which a newer frame overwrites, and the probe re-checks every saved request on
every scan: in `v06` one `prepare` was ready at revision 75 and `stale-context` at revision 77.
Whether the transport can still deliver a completion is a transport question, so G0 answers it
without a mutation:

- Fixed: the completion of a consumer's `prepare`, decided once when the provider first handles
  that request, either accepted with its handle or refused with its reason.
- Re-checked: whether the prepared target is still valid, reported separately from the
  completion, so a stale handle is still refused as in `w22` and `v06`.
- Shown: after the decision, frames that something else caused, another consumer's request or a
  context change, still carry the same completion, including a newer frame that overwrote the one
  that first carried it.

If the transport cannot keep a completion this way, G0 stops there instead of leaving the risk to
P5, after P1 to P4 would already rest on it.

Reasons for the other moves: the shortcut updates need the placement script to publish, which P0
excludes. Mutating acknowledgements need mutating requests; in P0 the probe would have to admit
windows, which its own contract forbids. Fair arbitration and the replacement matrix qualify the
complete feature rather than the transport.

The absent-backend unit cases run `registerNative()`'s branches against a fake `Workspace`. They
cannot show that the whole provider script loads, and that consumers settle on `unsupported`, on
a KWin without the fork, which is every installation without it. P0 makes no image change, so
that run waits for P7, and building a stock-KWin test image needs the owner's approval then.

## 4. Final native sweep

Decision: yes. At the last G0 tree every scope runs natively again, together with the
process-replacement runs, and a final receipt bound to that tree replaces the interim one for
the owner's review.

## Order of the remaining P0 work

The receipt recommended answering the decisions first and then the P0 fixture cases, starting
with the two that need a way to produce their state. This order keeps that idea and puts the
changes to publication before the scenarios that depend on it.

1. A time-boxed check of how to give the panel keyboard focus in the isolated session. It is the
   only item whose feasibility is unknown, and it does not depend on the others. If no way is
   found, the exact failure is recorded (todo.md, P0) for the stop rule to weigh.
2. The bounded, serialized read/publish pipeline. It changes publication in every mode, and
   counting publications gives P0 evidence for decision 1's cost condition.
3. The completion that newer state frames keep. It adds to the frame, so it comes before the
   scenarios that check frames.
4. Probe widgets on two bars with competing requests, on the final publication path.
5. Restarts with a current target-mode seed through `lifecycle.py`, once the frame and pipeline
   are final, so the restart covers them.
6. Keyboard entry after panel focus, if step 1 found a way.
7. The final sweep and the final receipt.
