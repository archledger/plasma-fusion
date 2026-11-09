<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# NT03: explicit floating restoration

Status: owner approved the specification and implementation plan on 2026-11-05.
Work follows the bounded tasks and gates; production activation remains prohibited.
Native baseline: `0eb27d9eb6b8ad0feb8554b5c763c488f7a67c7b`.
Planning baseline: `1262b4478a476da76c71ef9b62c2e64c06d324a4`.

This refines [the ownership contract](NATIVE-TILING-CONTRACT.md) and the NT03/NT04 boundary in
[the roadmap](../tasks/todo.md). It does not mark either milestone complete or enable tiling.
Source observations and build recipes below belong to the pinned planning baseline. Use the
[status and source snapshot](../tasks/todo.md#status-and-source-snapshot) for current progress.

## Objective and approved decisions

An explicit restore returns an automatically managed window to the floating frame A captured at
admission, not its managed rectangle B or a later mutable restore field. A newer manual action
always wins. Ownership and the writer barrier survive until qualified completion or destruction.

Approved decisions:

1. Restoration has its own generation-bound authority. Existing Owned authority is not weakened.
2. A private precursor supports ordinary mode, fixed context and exactly feasible A. It is not
   full NT03 completion and does not replace existing action routing or regress owned
   maximize/fullscreen behavior. Broader routing follows only after those modes are qualified.
3. Stale-configure placement safety is required before an exposed restore-start path is accepted.
   It cannot be postponed wholesale to NT04's completion work.
4. NT03 starts and qualifies the native request. NT04 proves native completion and finalizes the
   writer reservation. Staged, sent and completed remain distinct states.
5. The old four-file NT03 scope is revised explicitly. Implementation groups must still be small,
   independently tested and reviewed; this draft does not approve one large combined patch.

## Source observations at the planning baseline

- `Workspace::performWindowOperation`, `useractions.cpp`: UntileOrRestore recognizes Owned only.
  A Restoring record can otherwise fall through to ordinary fullscreen/tile/maximize behavior.
- `Window::releaseOwnedPlacement` and the Xdg override: current release ends through public
  untiling. The Xdg override first handles requested fullscreen; neither is a dedicated A request.
- `Window::TransientOwnership`: A and ownership identity survive release. No restoration-attempt
  identity is currently recorded.
- `requestMoveResizeGuarded`: ordinary/Operation provenance refuses outstanding ownership;
  Ownership provenance requires an Owned record and live tile. Neither authorizes Restoring work.
- `handleCommit`/`handleNextWindowGeometry`: configure-derived geometry is processed before the
  role commit's transient association check. Protecting only the tile association is insufficient.
- `AssignmentRequestDispatch::Queued` means staged for a coalesced configure, not sent or complete.

These are source observations, not newly executed restoration tests. Existing NT02.5b evidence
remains valid for its unchanged source and scope.

## Internal contract

### Intent and dispatch

Generic revocation stays detach-only. Manual movement, ordinary tile assignment, close and
context teardown must not implicitly request A. Only an explicit restore intent may claim a new
restore attempt against the exact current Owned generation.

Action handling must distinguish whether an action was consumed from whether restoration started:

| Situation | Handling |
|---|---|
| No transient record | Preserve the existing ordinary action path |
| Eligible Owned generation, no prior claim | Claim once and attempt qualified restoration |
| Claim in progress, or record already Restoring | Consume without another attempt or legacy fallthrough |
| Unsupported state before mutation | Consume and report no start; do not pretend restoration occurred |
| Authority lost after a prefix | Stop as superseded; retain applied state and pending protection |

Do not broaden `ownedTransientPlacementGeneration()` to include Restoring. Do not turn an
existing Restoring record from a manual action or teardown into permission to restore A.
Policy disable is a future explicit caller, not an automatic reinterpretation of every tree
clear. Its integration must preserve safe detach even when no qualified restoration can start.

### Claim, lifetime and provenance

Claim the explicit attempt before the first callback. Bind it to:

- the exact Window identity and ownership generation;
- a non-reusable, exhaustion-checked restore-attempt identity;
- immutable A and the selected native output/desktop/context;
- the same writer and exact reservation owner/generation, using a narrow writer-owned query;
- the allocated geometry-request generation, recorded before callback-producing geometry work;
- the operation's mode/constraint/decoration assumptions and cancellation state.

Use a distinct restoration provenance in the guarded request path. It must validate the relevant
Restoring record without requiring the detached controller or tile to stay alive. Public or
ordinary calls cannot manufacture or inherit that authority. An `isReserved(window)` boolean
alone is not proof of the correct reservation generation; `ownsReservation()` is intentionally
false after the writer enters Restoring.

Keep checkpoints stack-bounded or in external result carriers. Never put a Window-retaining
`TileAssignmentFence` inside that Window's own ownership record: that creates a retention cycle.
After callbacks, revalidate the original authority rather than minting fresh authority from the
current state. Writer loss, identity loss, close and unsupported context changes stop the attempt;
none permits re-adoption through a replacement writer or automatic retry.

### Target and mode policy

For the private first precursor, require ordinary requested and committed modes, a stable context
and exactly representable/feasible A. Refuse before mutation when those conditions cannot be
proved. Do not clamp, recapture from B, rewrite A or use a corrective loop.

This limited precursor cannot replace currently covered owned fullscreen/maximize actions.
Their restoration path must separately qualify normalization before full action routing: preserve
A across requested-mode writes, prospective decoration changes and callbacks; validate the actual
post-transition constraints and scale; discharge required notifications for writes already made;
then request A under the same explicit intent. Existing normalization helpers return toward the
managed rectangle or reject owners and are not interchangeable with a restore-to-A operation.

Output transfer/removal and other context transformation policy remain the later native-context
milestone. A missing/changed context must not resurrect a detached tree or silently pick a new A.

### Requested geometry and obsolete configures

An accepted request may be synchronously Published or only Staged. Neither by itself clears the
record or reservation in NT03. There is no synchronous event-loop wait for the client.

Carry restoration identity into the configure path early enough to decide whether an acknowledged
configure may influence compositor placement. An old admission or restore configure cannot regain
position, requested-state or completion authority after a newer restore/manual action. Match actual
native ordering and identity; do not rely on nullable tile pointers, raw geometry equality or time.

Do not reject valid surface content wholesale to solve a placement problem. Before implementing
the configure guard, characterize an old-sized buffer committed while a newer resize is pending.
Specify separately which client content/size updates remain valid and which compositor-controlled
position/requested-state changes are obsolete. The characterization and selected policy are now
recorded in [NT03.0](../tasks/nt03-old-buffer-characterization.md); the guard was not implemented
at that characterization baseline.
Any dependency on serial selection must also be tested at wrap; the
existing unsigned comparison is not assumed to provide the required ordering proof.

### Completion boundary

NT03 may prove that A is requested and that a controlled client can reach it. A private
request-only precursor must be labelled as such, not as full restoration qualification.

NT04 owns the matching native completion that ends protection, including queued and immediate
publication cases, superseded configures, serial wrap, unload, never-ACK and close. ACK alone,
equal geometry, a successful setter return or elapsed time never authorizes finalization.
Until that boundary is qualified, the record and reservation stay pending; newer manual intent
invalidates old authority without letting an old completion overwrite it.

## Source ownership and size limits

Likely source groups, subject to the approved implementation plan:

| Area | Relevant files |
|---|---|
| Record, restore authority, cancellation and guarded request | `src/window.h`, `src/window.cpp` |
| Exact restoration-reservation query | `src/tiles/transientplacementwriter.h`, `.cpp`, its unit test |
| Configure provenance, stale placement and mode normalization | `src/xdgshellwindow.h`, `.cpp` |
| Consumed versus unhandled explicit action | `src/useractions.cpp` |
| Native controlled-client proof | `autotests/integration/xdgshellwindow_test.cpp` |

The union may span nine files. Do not squeeze it into the old four-file row or hide a dependency.
Each implementation leaf should touch at most five source/test files, with a coherent tested
contract. `tilemanager.cpp` is not presumed necessary for the fixed-context precursor. No task
breakdown or runtime edit starts until this specification is approved.

## Testing and commands

Use the existing Fedora 44 / Qt 6.11.2 isolated ThinkPad build and local OCI image ID
`8e21595bc487be7fec1bed0acaf240e20846b44c213cf0256e11cea8d8d78eae`. Commands below run inside
the existing container with candidate source at `/source` and build at `/build`, never against
the installed compositor:

```sh
cmake --build /build --parallel 4 --target kwin testXdgShellWindow testTransientPlacementWriter
ctest --test-dir /build --output-on-failure --no-tests=error --timeout 120 \
  -R '^kwin-test(XdgShellWindow|TransientPlacementWriter)$'
```

Run the existing full 18-suite campaign after material runtime changes. Enumerate new test rows
and verify their execution: merely passing an unchanged suite is not NT03 evidence. Apply the
established changed-line formatter on the source host:

```sh
git diff --check
git diff -U0 --no-color HEAD -- '*.cpp' '*.h' | python3 /usr/share/clang/clang-format-diff.py -p1
```

Use the existing targeted Memcheck lane with unique labels and exact source/binary hashes.
Its QT_HASH_SEED=0, leak-check-disabled result is not an AES-path, leak-free or production claim.
Keep REUSE and recipe checks; do not hide the inherited native licensing omissions.

Minimum acceptance cases:

- A differs from B and from deliberately altered mutable restore fields; only A is selected.
- Pending/committed admission; Staged/Published restore; duplicate action during callbacks and
  after dispatch; no extra attempt/generation or legacy fallback.
- New manual move/resize, stamped equal-null cancellation, committed-only replacement and roundtrip
  invalidate old restore authority before and after configure emission.
- Old admission/restore configures cannot regain placement authority; valid content remains
  accepted under the characterized policy; actual serial-wrap cases exercise any matching logic.
- Root/controller destruction after detach does not discard the record; output/context loss stops
  unsupported placement without resurrection.
- Close at each callback boundary, with an externally retained checkpoint: suppression through
  logical close, release only at qualified completion/destruction, correct deferred manual winner.
- Changed constraints, prospective decoration/scale and counter exhaustion fail safely. No failure
  after a mutated prefix is mislabeled as a mutation-free refusal.
- Existing owned fullscreen/maximize and unowned Wayland/X11 behavior remain covered and unchanged
  until a separately qualified replacement is integrated. X11 transient admission stays refused.

Use fail-first cases and compiled negative controls. Keep evidence for interrupted and failed
runs. Review each source group independently before private signing.

## Style and operating boundaries

Match the existing KDE C++ style and lifetime pattern after validating a non-null Window:

```cpp
window->ref();
const auto lifetime = qScopeGuard([window]() {
    window->unref();
});
```

- Always: preserve A and newer intent, bound counters, check callbacks, record exact evidence.
- Ask first: change this scope, start implementation, add dependencies, alter public contracts,
  merge, install, deploy or perform disruptive hardware tests.
- Never: replace stock KWin implicitly, enable production tiling, weaken tests, invent completion,
  store a self-retaining fence, retry unknown outcomes or submit upstream without approval.

## Approval and characterization status

The owner approved the five decisions above and the implementation plan. NT03.0's bounded
characterization and narrow policy passed review; R3/R4 were subsequent implementation gates,
whose results are recorded in the roadmap. The observations are not permission to drop
content, guess at serial ordering, relax stale-placement safety or claim restoration completed.
