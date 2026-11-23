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
and under a Kiosk policy (`bec99ba`). P4 is done: the clock shows its view's layout mode, Floating
or Tiled, read-only in the pill after the workspace dots, its glyph alone or nothing as the width
budget asks, and nothing until an answer confirms a mode or while the bar's own layout hides it
(`995d8e7` and `c15f561`). The owner passed the read-only checkpoint on 2026-11-21. P5 is done: the
placement script's layout provider prepares a bar's action on the app its menu was opened from and
applies a set, Tiled or Floating, through that preparation and the tiler's own start and teardown,
each request decided once and its completion told in the bar's frames (`cb27199`, `7d70287`), and
both ran in real sessions (`1d1536a`); #210's fix came first (`403941b`). P6 is complete. See P7
and the final checkpoint below for remaining validation and review. Read
[plan.md](plan.md) and the accepted
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
      recheck), nor does the legacy lane (`05e3631`, confirmed in P7 on stock KWin). A
      provider that is not capable answers `capable` false.
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

- [x] Display only confirmed view-scoped state; keep actions disabled until P5–P6 qualify them.
      The specification's item 7 pending state is the layout state's outcome pending; once
      unconfirmed, past its deadline, the bar shows no control that looks as if it works (item 8;
      [shell-topbar.md](../../docs/parts/shell-topbar.md#workspace-layout-state-layoutstateqml)). An
      answer can also outlive a failed or malformed publication: its state and the view it names
      stand until a later publication reaches the bar (P2's fourth item). Whether the bar may
      compare that view with its own turns on how the specification's rule that the placement script
      is the only authority for the view is read (decision 1's amendment,
      [g0-decisions.md](g0-decisions.md)).
      The control, `clock/contents/ui/LayoutControl.qml`, shows a mode only while the layout state's
      mode is tiled or floating; unknown, a pending query among them, and unavailable show nothing,
      so a state unconfirmed past its deadline shows no control at all. It offers no action: it is
      static text with no keyboard focus, and a click on it opens neither the calendar nor Overview
      (`995d8e7`; in a real session in p4/bar-proof). P2's pending mapping is restated for P4: the
      read-only bar asks at its start, when the output it asks for changes, which is also how the
      control returns once it may show again, and when its provider's lifetime changes or ends; each
      time nothing is confirmed for it yet, so it shows nothing while a query is pending. The
      specification's item 7 pending state follows an explicit request, P6's, where the outcome
      pending is the mapping's case. The view is not compared: the placement script is the only
      authority for it, and on a desktop switch the bar's own desktop and the provider's frame
      arrive separately, so a comparison would hide the control for a moment each time. A stale
      answer after a failed publication stays P2's documented limit, which P7's matrix can inject
      (p4/control-proof).
- [x] Preserve dots/calendar/wheel behavior and existing width-budget order; derive measured
      label/compact/hidden savings using existing design tokens.
      The control sits in the pill after the workspace dots, or first with one workspace, one pill
      padding from its neighbours, with the boards' values: the LiveChips 14 px glyph and 6 px gap,
      stroke 1.8, and Manrope 13 px 600 in the pill's text colour (`995d8e7`, `c15f561`). In a real
      session a click on the date still opens the calendar, the current dot still asks for Overview
      and a wheel over the date or the control still switches workspaces. The width budget keeps its
      order: the label goes at step 4 with the short date and the control at step 7 with the dots;
      `layoutSaving(level)` gives up the label's measured room, then the control's width and one
      pill padding, and `budgetSaving` adds it. On screens from 800 to 380 px wide the steps 0, 2,
      4, 5 and 7 came with the matching levels, and the budget's predicted widths were exact across
      the control's steps (p4/bar-proof).
- [x] Cover one desktop, narrow bars, dark/light, RTL, large text and tablet/vertical hiding.
      Wherever the bar's own layout hides the control, whatever the answer (the plan names tablet
      posture and vertical panels; whether a clock on the desktop is another is P4's to decide),
      leave the layout state idle and withdraw the saved request, as the user's choice does (P3),
      so that no frame and no save follow a bar showing nothing. A withdrawal stops the provider
      only at its next read, which waits for some bar's wake; to stop it at once, wake it after a
      withdrawal, which needs the component to wake without a request (`LayoutState.qml`, among
      P6's files rather than P4's).
      In real sessions on the owner-approved image: one workspace (no dots, the control first),
      narrow bars, the dark and light themes, right to left as `plasmashell -reverse` mirrors it,
      with English text (the pill mirrored, the label against its glyph), large text at a scale of
      1.6, and tablet posture, which hides the control, leaves the state idle, withdraws the request
      and wakes the provider (p4/bar-proof). A vertical panel is covered offscreen only. A clock
      outside a panel is not the top bar, so it is gated the same way (P4's decision). The
      withdrawal happens at start while the control may not show, when the user hides it and when
      the bar's layout does, and then wakes the provider through the component's new `wake()`, which
      its request path uses too (`c15f561`). One exception: at the width budget's step 7 the hidden
      control keeps the state asking, since idling it there would free the room the budget counts
      and let it show the control again, in a loop; a bar that narrow keeps receiving frames, as the
      part page says and a check with its mutant guards.

Verify: fail-first real-component assertions in the existing calendar view suite; build topbar.
Review isolated screenshots before enabling actions; offscreen renders are not live-mode proof.
Done on 2026-11-21: slice 1's control checks failed first in the existing calendar view suite, 28 of
28 against their parent, and slice 2's in the backend suite, 14 at 162 checks; every planted mutant
was caught, 29 and 37, and `tools/build.sh topbar` passed on each committed tree (the proofs
p4/control-proof and p4/bar-proof). Beyond the five files, slice 2 changed
`clock/contents/ui/LayoutState.qml` for the wake, as the third item foresaw, and put the clock's
checks in `clock/tests/calendar_backend_test.py`, beside P3's; slice 1 first made the view suite
wait for the calendar adapter (`8c47df8`). The isolated screenshots are in p4/bar-proof's `shots/`,
for the checkpoint below. Not run: a vertical panel and a clock outside a panel in a session, a
right-to-left language's text in a session, hover tooltips, the keyboard, which reaches the control
only with P6's menu, and several bars, which are P7's.

## Checkpoint: read-only state path

- [x] The actual provider/consumer path reports correct current-view state without mutations.
- [x] Owner reviews the state contract and visual states before explicit-request integration.

Ready for the owner's review on 2026-11-21. The state contract is the part page's layout state and
layout control sections; the visual states are the screenshots in p4/bar-proof's `shots/`: Floating,
Tiled, tablet posture, the light theme, large text, right to left, one workspace, the glyph alone at
steps 4 and 5 and nothing at step 7. To judge: the Floating glyph alone can read as an empty
checkbox, the two glyphs differing by one line about 1 px wide; the label keeps its room until step
4, after the global menu and the app name; each new query hides the control until its answer, so the
pill's width changes twice and, near a step boundary, the budget can step down and back; a bar at
step 7 keeps receiving frames; the view is not compared; and in a left-to-right layout the spare
width after "Tiled" sits before the date. For the first item: p3/wiring-proof and p4/bar-proof show
it on one bar; several bars and outputs are P7's.

Passed on 2026-11-21: asked whether to treat the checkpoint as passed, waived or still open, the
owner answered "Passed", the option stating that the state contract and the screenshots had been
reviewed. The first item rests on one bar, as the note above says; several bars and outputs stay
P7's.

## P5: Handle explicit, prepared mode requests in the provider

Dependencies: P1, P4 and the read-only state checkpoint above. Likely files: `placement/main.qml`, the
P1 provider component/helper, `kwin-tests/offscreen/tiling-harness.qml`,
`kwin-tests/offscreen/tiling_lifecycle_test.py`, `docs/parts/kwin.md` (five).

- [x] Prepare/validate the intended application and view without selecting a panel or arbitrary
      window; invalidate after an ordinary app focus change, departure, close or lost view.
      The provider prepares a bar's action in its one slot, for the bar's view and the app a shell
      applet popup was opened from, straight or from the shell's dock or desktop surface on that
      output while the app was remembered, as it follows KWin's activations (`cb27199`). A window
      counts as the shell's only with the PID the bus gives for the shell's connection, as an applet
      popup, dock or desktop window that is not a normal window, so no panel and no other window is
      taken; with no eligible app the prepare is done with no target, and a set Tiled through it is
      refused `no-target` unless its view is already tiled, which re-selecting leaves as it is. A
      later focus change or the popup's close, the target leaving the view, turning into no eligible
      app as KWin notifies it, or closing, the view's change and a new shell connection end the
      preparation, and its holder is told so at a newer revision; a change KWin does not notify, as
      of moveable or resizeable, is found by the slot's next check, at the latest when the set is
      handled ([kwin.md](../../docs/parts/kwin.md#the-layout-providers-state)). In real sessions the
      clock's calendar is such a popup, opened with the pointer or the keyboard, and a prepare from
      it took the app it was opened from, never the bar (`1d1536a`; p5/slice3-proof).
- [x] Make desired-mode requests idempotent, serialize competing mutations and distinguish
      pending, refused, busy and unconfirmed outcomes without blind mutation retries.
      A set acts only through the preparation its handle names, and each request is decided once:
      read again it gets its recorded completion and nothing is done again, another payload is
      refused `conflicting-request` and an older number `stale-request` (`cb27199`, `7d70287`). One
      mutation runs at a time, the shortcut's included: a set while a start is retried is refused
      `busy`, and a press of the shortcut cancels a set's retry, which is refused `cancelled`. A
      request's frames carry no completion while its start is retried, pending, then `done` or
      `refused` with the reason; with no answer by the bar's deadline the bar holds the mode
      unconfirmed, which is the bar's to show (P2's layout state, P6's menu). Nothing is retried
      blindly: the provider never repeats a set, and the tiler tries a start again only after an
      admission refused as busy or ineligible, at most eight times 50 ms apart, a set's tries each
      first checking the target, the captured view's existence, the lifetime and the shell
      (`7d70287`). In real sessions a set read again was not applied again (p5/slice3-proof).
- [x] Preserve cross-view teardown-on-refusal semantics, manual precedence, float restoration
      and placement memory; Floating on another view leaves its active session alone.
      The tiler applies a set through the shortcut's own start and teardown: Tiled on another view
      ends the session there first, and a refused start leaves it ended, reported, not rolled back;
      Floating ends the session only on the prepared view, so Floating on another view leaves that
      session alone, a case of the lifecycle suite's set run; the tiler's manual precedence and
      placement memory are unchanged, and the suite's runs for them pass unchanged (`7d70287`). In
      real sessions the floats came back after a transfer between two outputs; after one away from a
      desktop not shown, the old stack window kept the stack cell's size, as after the shortcut's
      own transfer, a behaviour older than P5 reported as #212 (p5/slice3-proof).
- [x] Prove mutating completion acknowledgements and timeouts, which testing.md listed as G0
      work ([g0-decisions.md](g0-decisions.md)); P0 shows only that a completion survives newer
      state frames.
      A set's completion is decided at once or when its retried start ends, and every later frame
      for the request carries it; one decided after its read moves the revision, so it is told in a
      frame of its own even when nothing else changed, and one a failed publication did not deliver
      goes out with the next (`7d70287`; planted mutants of the record and of the revision step
      caught). The time limit P5 proves is the tiler's: a retried start ends within its eight tries,
      refused `admission-refused` at the last (the lifecycle suite's set run). A call the shell
      never answers fails at KWin's documented bus timeout, 25 s, which no P5 case drives, and the
      bar's own deadline, past which its mode is unconfirmed, is P2's. The retirement ends the
      lifetime before any later outcome, so none follows the offline frames. In real sessions each
      set's completion came in the bar's frames, every set decided at once, so the retry window ran
      offline only (p5/slice3-proof).

Verify: fail-first lifecycle cases and relevant pure-rule tests; mutate key guards to prove the
new cases fail without them. Re-run the focused KWin build and tiling/placement/lifecycle suites.
Done on 2026-11-22: #210's fix came first, with the checkpoint (`53bbb3d`, `403941b`;
p5/start-proof). Slice 1's lifecycle cases failed first against their parent with 9 FAIL lines (its
node cases pin rules the parent already had) and slice 2's with 74; the planted mutants expected
caught were all caught, 104 of 112 and 146 of 156, the others shown equivalent with their reasons;
`tools/build.sh kwin`, the node suites, the lifecycle suite and five stability runs passed on each
committed tree (p5/slice1-proof, p5/slice2-proof), and the kwin build and the lifecycle suite on
slice 3's, whose one code change is a comment. Beyond the five files, #210's fix changed
`docs/DEFERRED.md`, slice 1 `kwin-tests/tiling.test.js` for the rules the provider leans on, and
slice 2 the test stand-in `kwin-tests/offscreen/stubs/org/kde/kwin/Workspace.qml`, for the
activities a retry checks. Slice 3 ran both slices in real sessions on the owner-approved image and
corrected the part page's account of a retry, with the provider's matching comment (`1d1536a`;
p5/slice3-proof). Not run natively: a retried start, which no set there needed; the real menu (P6);
two controls on one output and `busy` between bars (P7); hardware timing and XWayland apps.

## P6: Enable explicit user actions

Dependencies: P4–P5. Likely files: `clock/contents/ui/{LayoutControl,LayoutState,main}.qml`,
`clock/tests/calendar_view_test.py`, `docs/parts/shell-topbar.md` (five).

- [x] Floating/Tiled choices send explicit intent for the captured view and show bounded pending
      feedback; repeated selection is not a toggle, and a failed send is not confirmed state.
- [x] Support pointer and keyboard entry after panel focus, menu arrows/Return/Space/Escape,
      visible focus and accessible names without underlying calendar/workspace activation.
- [x] Preserve existing bindings; keep unsupported/unconfirmed profiles safely unavailable.

Verify: real-component fail-first calendar view cases plus relevant calendar/config regressions.
Review dark/light, compact and keyboard states against the existing boards/tokens.

Results: slices 1 to 4. The backend suite gains a case for each outcome of the action's table
(571 checks, 0 failures; 195 fail against the previous component, all new). The view suite gains
36 interactive-control and 36 menu checks (123 checks, 0 failures; 71 fail against the previous
control and the absent menu, all new). 21 planted mutants of the menu and control guards are all
caught by named cases. The wiring's cases run in the backend suite's fixture (10 fail against the
previous `main.qml`). A private session on the approved image (KWin 6.8.3-1.fc44.pf1, Qt 6.11.2)
passes 18 checks: the provider answers, the click opens the menu, Escape closes it and the panel
leaves keyboard navigation, both keyboard openings show the confirmed row's ring, the menu opens
over the calendar with the prepare's no-target and the blocked Tiled row, the wheel still switches
workspaces, the first open's first frame came 22 ms after the request, and the status line sits
under the rows in a top bar. The image has no screen reader, so the announcement's naming was not
checked there; an Escape between a choice and its read (T25) and a set from the menu were not
produced, as the session had no app window to tile. The dark/light, compact and keyboard states
are in the session's screenshots for the D14 review.

## Checkpoint: read-only path and explicit intent

- [x] Review P1–P6's source and tests, with no unresolved native-contract or state-ordering gap.
- [x] The read-only state path works end to end before action enablement.
- [ ] The plan's full acceptance matrix is mapped to automated or named isolated-session cases.

Results: the source review covered the action's state machine (`LayoutState.qml`'s `open()`,
`input()`, `choose()`, `close()`, `prepare()`, `sendSet()`, `moveAction()` and `settle()`), the
control's gate and focus, the menu's rows and focus, and the wiring's close paths, against the
design's table and the part pages; no unresolved native-contract or state-ordering gap was found.
The read-only path is P4's, checked end to end in the backend and view suites and in the session.
The acceptance matrix is P7's.

## P7: Qualify the complete feature

Dependencies: P6 and source review. Likely files: the G0 scenario/seed fixtures as needed,
`docs/parts/{shell-topbar,kwin}.md` (keep each change at most five files).

- [x] Run the accepted spec's focused build/tests/lints/license checks in the actual target
      environment; retain red/green and mutation evidence where applicable.
- [x] Run the real shell/fork acceptance matrix in independently named isolated sessions,
      including two bars/views, reload/restart, keyboard focus, refusal and late confirmation.
      Include the settings dialog itself: hiding the control through its Apply, and Apply on each
      page while a frame arrives, which P3 emulated from the dialog's code.
- [x] Include fair arbitration across bars and a mixed shell/KWin replacement matrix, which
      testing.md listed as G0 work, and an absent backend on a stock-KWin image, moved from G0
      item 3 ([g0-decisions.md](g0-decisions.md)).
- [x] Preserve evidence, screenshots, versions/OIDs and limits; no new script error/crash or
      native restoration/placement-memory regression in the tested scenarios.
- [x] Measure the publications' cost on real hardware, a physical disk rather than a container's
      virtual one, on a device the owner approves then (decision 1 as amended on 2026-11-21).
      The containers' storage turned out to be podman's overlay on ext4 on an NVMe SSD (read
      2026-11-22; by inference the same during P1's runs), not a virtual disk. On 2026-11-22, on the
      ThinkPad X13 Yoga Gen 4 the owner approved (all runs; the reading accepted beforehand), in
      private sessions of 56f7359's provider and clock: every idle one-frame publication under 50 ms
      from its script's start (the longest 16 ms of 126), and the idle 16-frame median 34 ms (p95 43
      ms, 3 of 180 over), so decision 1's reading holds. Under CPU load every 16-frame publication
      went over the limit, and under disk load those that met a synced copy did
      (`docs/parts/kwin.md`, the cost bullet). Proof: 2026-11-22-p7-hardware-cost. Not run: the
      container baseline and the save timing on archhost; the short confirmation on the final P7
      tree remains.

Results: the acceptance matrix is `acceptance.md`, each of the plan's fourteen rows mapped to its
suite cases and native runs, with the gaps named. The focused checks are verify-tip's fifteen steps
on each pushed commit (the builds with their QML lints, the suites, ruff, ShellCheck, the lint
fixtures and REUSE). The real shell/fork runs are P0's, P5's and P6's, each in an independently
named container session of the approved image. The P7 follow-up ran the real settings dialog
on the same image: Apply saved an edit on each of General, Calendar and Time zones after a provider
reload without overwriting the new request or response. Hiding the control through General's
Apply withdrew its request. Fair arbitration across two bars on one output
(`p7-arb-2`, 18 checks): each bar prepares in turn, the previous preparation ends on the focus
change, neither starves, no set is sent and both clocks keep the same mode. The provider's reload
and disable with the real clock (`p7-reload-1`, 11 checks): the clock goes unknown, the actions go
away and the control hides, then it answers again when the script is enabled. The KWin owner
replacement is G0 item 4's documented limit (no live consumer sees it). On Fedora 44 with Plasma
6.8.3 and Qt 6.11.2, the real clock and placement script from 24e24cc answered on stock KWin
6.8.3-1.fc44 (`unavailable`, no actions, control hidden). The same staged packages answered
`floating` on 6.8.3-1.fc44.pf1 (actions available, control visible). Both scenarios passed and the
process sweep left none. Both also reproduced the separate plasmashell teardown abort (#217).
The other evidence is the proof manifest
(`build/layout-probe/p6-s4/proof-manifest.json`), the sessions' checks and screenshots, and the
recorded versions. The branch changes the clock, the part pages and the task files; no native fork,
packaging, CI or unrelated change is in it, and the live backgrounds, captive portals and
notification modules are untouched.

Verify: the spec's exact commands, the qualified scenario runner and result checks. Record
missing tools or environments as incomplete validation, not pass. Do not use another session's
VM, image tag, candidate refs or build outputs; do not install on the owner's desktop.

## Final checkpoint

- [x] Each spec requirement has a source/test/evidence reference and its limits are explicit.
- [ ] Independent review and actionable findings are resolved; owner decides any merge.
- [x] No native fork, packaging/CI/release, unrelated-task or live-desktop change was introduced.
- [x] Live backgrounds, captive portals and notification work remain separate modules.

Results: `acceptance.md` maps the plan's matrix; the spec's requirements are in the part pages and
the suites. The independent review is not run: subagents are unavailable until 2026-11-24T12:00Z,
and the owner decides the merge. The branch changes the clock, the part pages and the task files;
no native fork, packaging, CI or unrelated change is in it, and the live backgrounds, captive
portals and notification modules are untouched.
