<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Workspace layout control checklist

Status: plan accepted on 2026-11-17; P0 is done, and G0 passed on 2026-11-20, when the owner
confirmed the final receipt's four decisions. P1 is done: the placement script's layout provider
keeps its state, holds its identity name, reads the bars' requests, publishes their answers,
follows their views and measures its shell calls (`9d7c42a` to `79bb8f0`); on 2026-11-21 the owner
amended decision 1's time-limit condition, and the transport passed its native recheck on the
released fork, `v6.8.3-pf1`. P2 is done: the clock's layout state takes only its current
provider's answers to its own requests, notices a provider lost with no frame and gives each
request a deadline (`62993e6` to `ddf4533`). P3 is done: the clock's settings gain the control's
visibility choice and the two transport fields, each page refreshing what it does not edit
(`e111375`), and the clock asks for its output's layout state, saving each request before the
wake and withdrawing it while the control is hidden, which ran natively through a shell restart
and under a Kiosk policy (`bec99ba`). P4 is next. Read [plan.md](plan.md) and the accepted
[specification](../../SPEC-workspace-layout-control.md).
Existing native task files are untouched.
Paths below are relative to the repository. Proposed new files are not claimed to exist.

Path abbreviations: `clock/` = `packages/plasmoids/org.plasmafusion.clockpill/`;
`placement/` = `packages/kwin/scripts/plasmafusion-placement/contents/ui/`;
`kwin-tests/` = `packages/kwin/tests/`.

## P0: Prove the real transport and lifecycle boundary

Dependencies: owner approval of the plan (given). Scope: test-only, the original five fixtures
under `tools/tests/layout-control/` plus one separately approved private-bus lifecycle runner.
The transient identity-only alias and sixth runner were approved on 2026-11-17.
Focused test modules were subsequently approved that day, preserving the entry command and all
original 98 cases. No production changes.
The owner approved fixture-owned orderly teardown and strict cleanup qualification on
2026-11-18 (UTC), preserving all 122 cases then present. Shared harness/Qt/native/image/security
and live-desktop changes remain excluded; G0 is still a separate gate.

- [x] Prove wake-up, correlated state exchange and script/shell/KWin lifetime invalidation in a
      real isolated shell/fork pair; include stale retained fields and negative controls.
- [x] Prove keyboard target preparation, competing-bar ordering and timeout/late reply cases,
      or record the exact failure rather than invent a native API or polling fallback. The
      timeout cases are the query cases; mutating timeouts are P5.
- [x] Bound and serialize the read/publish pipeline and count publications; show, without a
      mutation, that a request's completion, decided once, survives newer state frames while the
      target's validity is re-checked separately ([g0-decisions.md](g0-decisions.md)).
- [x] Record the supported contract, versions, image identity, traces and pass/fail receipt.
      Final receipt for the owner's review: [g0-receipt.md](g0-receipt.md) (2026-11-20; it replaces
      the interim of 2026-11-19). Decisions on the interim and the order of the P0 work:
      [g0-decisions.md](g0-decisions.md).
- [x] Before the final sweep: the layout-control tests create their scratch directories under a
      hard-coded directory in `/tmp`, which fails wherever that directory is missing; use the
      default temporary directory, which follows `TMPDIR`.
- [x] Follow-up: the bridge's target waits print nothing on a timeout, in the keyboard-entry
      scenario as in the target steps, so the log locates a failure only by the last PASS line
      before it; name the failing wait. Each now prints one FAIL line naming itself, what it
      waited for and the log of its last check (2026-11-20).

Verify: run the proposed G0 commands in `plan.md` after creating the fixtures; the scenario exits
nonzero on a missing/incorrect observation. No SSH or live desktop. Review the receipt before P1.

## Checkpoint G0

- [x] Every transport/lifecycle claim has actual evidence, including negative controls.
- [x] The chosen contract fits the accepted no-native-change/no-daemon/no-polling boundary.
- [x] Owner reviews the receipt and any design changes before production integration.

Passed on 2026-11-20: the owner reviewed [g0-receipt.md](g0-receipt.md) and confirmed its four
decisions, decision 1 after the click reproduction and with its publication time limit (P1).

## P1: Expose authoritative provider snapshots

Dependencies: G0. Likely files: `placement/main.qml`, a feature-owned provider component/helper,
`kwin-tests/offscreen/tiling-harness.qml`, `kwin-tests/offscreen/tiling_lifecycle_test.py`,
`docs/parts/kwin.md` (at most five).

- [x] Publish capability, view-scoped mode and lifecycle/order information from the existing
      tiler; startup, shortcut, native teardown and unload produce the required state changes.
      The state, its revision and lifetime (`05e3631`), the identity name (`64ec9ab`), the
      requests read (`4eb907e`), the answers published (`f6e47c7`) and the views followed
      (`79e4e34`); the lifecycle suite checks the revision at every toggle, untoggle and native
      teardown, and the unload runs see the provider go offline once, before the teardown.
- [x] Preserve writer/placement/restoration behavior and avoid redundant per-frame publication.
      The node suites and the existing lifecycle runs pass at every slice; a widget is written
      again only when what its frame says changes, and the lifecycle suite counts publications
      (`f6e47c7`, `79e4e34`).
- [x] Match the proven transport exactly; absent/refused native support never reports ready.
      The probe's transport (`64ec9ab`, `4eb907e`, `f6e47c7`), stricter where G0's findings and the
      reviews asked: every request version-checked, reads only from a unique shell connection. A
      refused registration never reports capable (`9d7c42a`; shown offscreen and natively in the
      recheck), nor does the legacy lane (`05e3631`; by reading the code alone, as the offscreen
      stand-in always has the fork's API), and a provider that is not capable answers `capable`
      false. The absent backend's native run, on a stock-KWin image, is P7's.
- [x] Meet the conditions in [g0-decisions.md](g0-decisions.md), among them: publish only for a
      new request or changed state, keep the read/publish pipeline bounded and serialized,
      version-check every request, keep a single publisher and keep the alias an identity-only
      lifetime fence. Shortcut updates moved here from G0 item 3.
      P1's part is met in `9d7c42a` to `79bb8f0`. The provider's record of what each bar was told
      starts empty in each lifetime and never comes from a saved answer. The one publisher is the
      provider the placement script creates: KWin refuses a second load under a name already loaded
      (the fork's `src/scripting/scripting.cpp` at `v6.8.3-pf1`), and a copy under another name or a
      leftover probe stays decision 2's limit. The consumers' part is P2's (below), rejecting
      retained answers and not depending on the observed output-loss placement (the receipt's
      finding 10); a mutating request taking effect at most once is P5's.
- [x] Keep each publication under a time limit that P1 proposes, and measure publication length
      in the lifecycle tests: the shell handles no input while it serves one (decision 1,
      confirmed on 2026-11-20, amended on 2026-11-21).
      The limit is 50 ms (`79bb8f0`): every read and publication is measured, and one over it is
      said. It is watched, not guaranteed, as the shell saves the widget configuration to disk
      inside each publication; the condition is now short in typical conditions, measured and
      warned, with a hardware measurement in P7 ([g0-decisions.md](g0-decisions.md)).
- [x] Recheck the transport natively on the fork P1 targets (the receipt's finding 11). Slices 3 to
      4d had run natively on KWin `6.8.2-3.fc44.pf5`, and slices 1 and 2 had no run of their own.
      On 2026-11-21, on an owner-approved image with the fork's `6.8.3-1.fc44.pf1` (P0's image but
      for KWin, the lint tools and their dependencies), the identity name, request read,
      publication, views on one and two outputs and time-limit runs repeated their last `pf5` runs
      on the same seeds, with the same checks and, lengths aside, the same provider lines but for
      the time-limit warnings, which both images give. The placement script's refused registration
      (slice 1's) ran natively for the first time, on both images: while a test script holds the
      fork's provider slot, the placement script says so once, keeps its name and answers not
      capable; freeing the slot leaves that lifetime not capable, and a reload then registers a new
      lifetime. With the test script inert, the six checks that need the slot held fail. Slice 2's
      state, revision and lifetime are checked in every frame, as in the later slices' `pf5` runs.

Verify: fail-first rows in the real-script lifecycle suite; run the spec's `tools/build.sh kwin`,
tiling/placement node tests and offscreen lifecycle command.

## P2: Consume fresh state without UI side effects

Dependencies: P1. Likely files: `clock/contents/ui/LayoutState.qml` (new),
`clock/tests/calendar_backend_test.py`, `clock/tests/calendar_view_test.py`,
`docs/parts/shell-topbar.md` (at most four).

- [x] Start unknown; accept only the current consumer/provider/view and non-regressing state.
      Each instance starts unknown, asks as a consumer of its own and takes only the provider's
      version-1 frame for its current request and output, checked on the session bus; the first
      answer binds the request to its lifetime, and only that lifetime's newer revisions follow
      (`62993e6`).
- [x] Treat outcomes separately from state, including same-provider reordering and timeout/late
      confirmation; no persistent field alone can authorize an action or mode label.
      `outcome` (idle, pending, answered or refused) is kept apart from the state. Frames are
      checked one at a time, only the newest of one lifetime waiting, and none at or below the
      revision last taken counts; the answer an earlier instance was given never counts, so a saved
      field alone gives no mode (`62993e6`). Past its deadline a pending request is unconfirmed,
      and a late answer still counts (`ddf4533`).
- [x] Invalidate correctly on observed provider loss/replacement without an idle polling loop.
      Another lifetime's answer and the bound lifetime's offline frame make the bar unknown and
      ask again (`62993e6`). A lifetime lost with no frame is seen with no polling: the bar watches
      the session bus's `NameOwnerChanged` through the workspace plugin's `SignalWatcher`, and the
      bound identity name or KWin's name changing hands, released or handed straight on, or KWin's
      name moving from the owner of a frame being checked, makes it ask again (`ffe39ac`).
- [x] Accept what P1's provider sends (its reviews): refused frames, a null view and possibly an
      empty activity, an answer to a new request at an unchanged revision, and a frame pushed at a
      newer revision with no request of its own. Expect no automatic retry after a failed or
      malformed publication, as a wake sends again, and do not depend on the observed output-loss
      placement (the receipt's finding 10).
      All five are taken (`62993e6`). A publication that fails or is malformed leaves a pending
      request to its deadline: the bar asks only at its start, on an output change and on the
      lifetime changes above, never as a retry, and a late answer still counts (`ddf4533`). An
      answered bar keeps that answer, its state and the view it names, until a later publication
      reaches it, which may wait for the provider's next read and so for a wake
      (`docs/parts/kwin.md`, the publication and time-limit runs); P4 takes that case. The bar asks
      for its own output by name, again whenever that changes, and an output KWin does not have is
      unavailable, so it assumes nothing of where output loss moves the panel (`62993e6`).
- [x] Wake the provider when a clock starts: at login the provider's first read usually comes before
      the shell has started. Under a Kiosk policy that refuses the shell's scripting, no answer
      comes, so fall back to unknown or unavailable on the bar's own deadline (the specification's
      items 7 and 8, with P3). If the bars come to wake on view changes, revisit the provider's info
      lines per read and publication and its warning per failed read.
      The bar wakes the provider after each request, once its owner has saved it (`62993e6`). When
      no answer comes, under such a Kiosk policy, with no placement script or stock KWin, or after a
      failed wake, the request is unconfirmed at the bar's own deadline and its mode stays unknown
      (`ddf4533`; offscreen, as no answer at all and as a failed wake). The same fallback in the
      clock, once it carries the fields, is P3's (below). The bars wake only for requests of their
      own, never on a desktop or activity switch, which the provider pushes, so its info lines and
      warning need no revisit.

Verify: fail-first cases in existing calendar suites, on private buses as specified; include a
retained-field bootstrap and provider-owner replacement control. No window operations.
Done on 2026-11-21: each slice's suite failed first against its parent, on a private bus (the proofs
p2/layout-state-proof, p2/lost-provider-proof and p2/deadline-proof). The retained-field bootstrap
is `62993e6`'s. The owner-replacement controls are `62993e6`'s, where no offline frame of the bound
lifetime counts from KWin's new owner (since `ffe39ac`, KWin's name leaving unbinds the bar first,
so the case now checks the lifetime it was bound to), and `ffe39ac`'s, where KWin's name handed
straight on makes the bar ask again. No case operates a window. Nothing ran natively, as nothing
uses the component yet; that starts in P3 (below).

## P3: Add clock configuration without stale writes

Dependencies: P2. Files: `clock/contents/config/main.xml`, the three existing
`clock/contents/ui/Config{General,Calendar,TimeZones}.qml` pages, and
`clock/tests/calendar_config_test.py` (five).

- [x] Add the user visibility choice and only the private fields the G0 contract needs.
      `showLayoutControl` (Bool, default true), with General's checkbox "Show the dynamic tiling
      control", independent of the workspace dots, and the two fields the provider reads and
      writes, `layoutRequest` and `layoutResponse` (String, empty), all in General and nothing
      else (`e111375`).
- [x] Preserve every page's complete key/default declarations and refresh keys it does not edit.
      Each of the three pages declares every key and its default, which the build's page check
      enforces, and refreshes in `saveConfig()` each key it has no control for; of the new keys,
      General refreshes the two fields, Calendar and Time zones all three (`e111375`).
- [x] Opening/applying any configuration page cannot replay a request or replace fresher state.
      No page writes as it opens. On each, Apply replays no earlier request and replaces no answer
      written while the page was open, and on Calendar and Time zones it undoes no visibility
      choice made meanwhile; the dialog's `open()` and Apply are emulated from plasma-desktop's
      code at v6.7.5 and v6.8.3 (`e111375`). Hiding the control through Apply still withdraws the
      request, although Apply writes the choice before the page's copy of the request (`bec99ba`).
- [x] Take P2's hand-offs. Add the clock's `requested` handler, which saves each request before the
      wake, and its `response` binding, with the save per frame that declaring the field costs
      (decision 1's amendment); the component's owner, `clock/contents/ui/main.qml`, is not yet
      among the files above. Then run the plan's matrix row "Cold start or shell restart with old
      saved fields" in a real session: unknown until a fresh exchange. That run is also the wake's
      first native call with its explicit signature, `(s)`. Under a Kiosk policy that refuses the
      shell's scripting, or with system-immutable widgets, the provider's reads fail, and the clock
      must still end unconfirmed at its deadline, as P2's fifth item shows offscreen for the
      component (the specification's items 7 and 8).
      The clock writes each request to `layoutRequest` and saves it before the wake, binds the
      component's `response` to `layoutResponse` and asks for its own output; while the control is
      hidden it asks nothing and withdraws its saved request, so that from the provider's next read
      no frame, and no save, follows it (`bec99ba`). In a real session on the owner-approved image
      with the fork's `6.8.3-1.fc44.pf1`, P1's recheck image, after a shell restart with the old
      answer saved the clock was unknown and asked afresh as another consumer; with no provider it
      was unconfirmed at its deadline, and a new provider lifetime's late answer then counted. The
      wake's call with `(s)` failed nowhere. In the three native runs each publication, the answer's
      field declared, took 2 to 38 ms from its script's start to its answer (4 to 39 ms from its
      call), in a container; its cost on real hardware is P7's to measure. Under the Kiosk policy,
      desktop scripting was refused, the provider's reads failed and the clock ended unconfirmed at
      its deadline, said once in the shell's log (p3/wiring-proof). System-immutable widgets are
      refused by the same call ("Widgets are locked", plasma-workspace v6.8.3
      `shell/shellcorona.cpp:1995-1997`), so the clock's side is the same; that case was not run
      natively.

Verify: fail-first configuration regressions, `tools/build.sh topbar` key checks and the spec's
calendar configuration command. Test visibility and private-field changes while a page is open.
Done on 2026-11-21: each slice's suite failed first against its parent, on a private bus (slice 1:
13 failures, and 8 with the new schema but the parent's pages, where the page check found 18
missing declarations; slice 2: 7), and `tools/build.sh topbar` with its key checks and the spec's
calendar configuration command passed on each committed tree (the proofs p3/settings-proof and
p3/wiring-proof). The changes while a page is open are slice 1's Apply cases above. Beyond the
five files, both slices updated `docs/parts/shell-topbar.md`, as a behaviour change must
(AGENTS.md), and slice 2 wired the component into `clock/contents/ui/main.qml`, which P4 lists,
with its cases in `clock/tests/calendar_backend_test.py`. Not run: the real settings dialog, whose
`open()` and Apply are emulated (P7, below), and the withdrawal at start in a session, shown
offscreen only.

## P4: Show a read-only mode control

Dependencies: P2–P3. Likely files: `clock/contents/ui/main.qml`,
`clock/contents/ui/LayoutControl.qml` (new), `clock/contents/ui/WidthBudget.qml`,
`clock/tests/calendar_view_test.py`, `docs/parts/shell-topbar.md` (five).

- [ ] Display only confirmed view-scoped state; keep actions disabled until P5–P6 qualify them.
      The specification's item 7 pending state is the layout state's outcome pending; once
      unconfirmed, past its deadline, the bar shows no control that looks as if it works (item 8;
      [shell-topbar.md](../../docs/parts/shell-topbar.md#workspace-layout-state-layoutstateqml)). An
      answer can also outlive a failed or malformed publication: its state and the view it names
      stand until a later publication reaches the bar (P2's fourth item). Whether the bar may
      compare that view with its own turns on how the specification's rule that the placement script
      is the only authority for the view is read (decision 1's amendment,
      [g0-decisions.md](g0-decisions.md)).
- [ ] Preserve dots/calendar/wheel behavior and existing width-budget order; derive measured
      label/compact/hidden savings using existing design tokens.
- [ ] Cover one desktop, narrow bars, dark/light, RTL, large text and tablet/vertical hiding.
      Wherever the bar's own layout hides the control, whatever the answer (the plan names tablet
      posture and vertical panels; whether a clock on the desktop is another is P4's to decide),
      leave the layout state idle and withdraw the saved request, as the user's choice does (P3),
      so that no frame and no save follow a bar showing nothing. A withdrawal stops the provider
      only at its next read, which waits for some bar's wake; to stop it at once, wake it after a
      withdrawal, which needs the component to wake without a request (`LayoutState.qml`, among
      P6's files rather than P4's).

Verify: fail-first real-component assertions in the existing calendar view suite; build topbar.
Review isolated screenshots before enabling actions; offscreen renders are not live-mode proof.

## Checkpoint: read-only state path

- [ ] The actual provider/consumer path reports correct current-view state without mutations.
- [ ] Owner reviews the state contract and visual states before explicit-request integration.

## P5: Handle explicit, prepared mode requests in the provider

Dependencies: P1, P4 and the read-only state checkpoint above. Likely files: `placement/main.qml`, the
P1 provider component/helper, `kwin-tests/offscreen/tiling-harness.qml`,
`kwin-tests/offscreen/tiling_lifecycle_test.py`, `docs/parts/kwin.md` (five).

- [ ] Prepare/validate the intended application and view without selecting a panel or arbitrary
      window; invalidate after an ordinary app focus change, departure, close or lost view.
- [ ] Make desired-mode requests idempotent, serialize competing mutations and distinguish
      pending, refused, busy and unconfirmed outcomes without blind mutation retries.
- [ ] Preserve cross-view teardown-on-refusal semantics, manual precedence, float restoration
      and placement memory; Floating on another view leaves its active session alone.
- [ ] Prove mutating completion acknowledgements and timeouts, which testing.md listed as G0
      work ([g0-decisions.md](g0-decisions.md)); P0 shows only that a completion survives newer
      state frames.

Verify: fail-first lifecycle cases and relevant pure-rule tests; mutate key guards to prove the
new cases fail without them. Re-run the focused KWin build and tiling/placement/lifecycle suites.

## P6: Enable explicit user actions

Dependencies: P4–P5. Likely files: `clock/contents/ui/{LayoutControl,LayoutState,main}.qml`,
`clock/tests/calendar_view_test.py`, `docs/parts/shell-topbar.md` (five).

- [ ] Floating/Tiled choices send explicit intent for the captured view and show bounded pending
      feedback; repeated selection is not a toggle, and a failed send is not confirmed state.
- [ ] Support pointer and keyboard entry after panel focus, menu arrows/Return/Space/Escape,
      visible focus and accessible names without underlying calendar/workspace activation.
- [ ] Preserve existing bindings; keep unsupported/unconfirmed profiles safely unavailable.

Verify: real-component fail-first calendar view cases plus relevant calendar/config regressions.
Review dark/light, compact and keyboard states against the existing boards/tokens.

## Checkpoint: read-only path and explicit intent

- [ ] Review P1–P6's source and tests, with no unresolved native-contract or state-ordering gap.
- [ ] The read-only state path works end to end before action enablement.
- [ ] The plan's full acceptance matrix is mapped to automated or named isolated-session cases.

## P7: Qualify the complete feature

Dependencies: P6 and source review. Likely files: the G0 scenario/seed fixtures as needed,
`docs/parts/{shell-topbar,kwin}.md` (keep each change at most five files).

- [ ] Run the accepted spec's focused build/tests/lints/license checks in the actual target
      environment; retain red/green and mutation evidence where applicable.
- [ ] Run the real shell/fork acceptance matrix in independently named isolated sessions,
      including two bars/views, reload/restart, keyboard focus, refusal and late confirmation.
      Include the settings dialog itself: hiding the control through its Apply, and Apply on each
      page while a frame arrives, which P3 emulated from the dialog's code.
- [ ] Include fair arbitration across bars and a mixed shell/KWin replacement matrix, which
      testing.md listed as G0 work, and an absent backend on a stock-KWin image, moved from G0
      item 3; building that image needs the owner's approval ([g0-decisions.md](g0-decisions.md)).
- [ ] Preserve evidence, screenshots, versions/OIDs and limits; no new script error/crash or
      native restoration/placement-memory regression in the tested scenarios.
- [ ] Measure the publications' cost on real hardware, a physical disk rather than a container's
      virtual one, on a device the owner approves then (decision 1 as amended on 2026-11-21).

Verify: the spec's exact commands, the qualified scenario runner and result checks. Record
missing tools or environments as incomplete validation, not pass. Do not use another session's
VM, image tag, candidate refs or build outputs; do not install on the owner's desktop.

## Final checkpoint

- [ ] Each spec requirement has a source/test/evidence reference and its limits are explicit.
- [ ] Independent review and actionable findings are resolved; owner decides any merge.
- [ ] No native fork, packaging/CI/release, unrelated-task or live-desktop change was introduced.
- [ ] Live backgrounds, captive portals and notification work remain separate modules.
