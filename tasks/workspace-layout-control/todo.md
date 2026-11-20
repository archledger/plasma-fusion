<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Workspace layout control checklist

Status: plan accepted on 2026-11-17; P0 is done, and G0 passed on 2026-11-20, when the owner
confirmed the final receipt's four decisions; P1 has not started; no production integration. Read
[plan.md](plan.md) and the accepted [specification](../../SPEC-workspace-layout-control.md).
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

- [ ] Publish capability, view-scoped mode and lifecycle/order information from the existing
      tiler; startup, shortcut, native teardown and unload produce the required state changes.
- [ ] Preserve writer/placement/restoration behavior and avoid redundant per-frame publication.
- [ ] Match the proven transport exactly; absent/refused native support never reports ready.
- [ ] Meet the conditions in [g0-decisions.md](g0-decisions.md), among them: publish only for a
      new request or changed state, keep the read/publish pipeline bounded and serialized,
      version-check every request, keep a single publisher and keep the alias an identity-only
      lifetime fence. Shortcut updates moved here from G0 item 3.
- [ ] Keep each publication under a time limit that P1 proposes, and measure publication length
      in the lifecycle tests: the shell handles no input while it serves one (decision 1,
      confirmed on 2026-11-20).

Verify: fail-first rows in the real-script lifecycle suite; run the spec's `tools/build.sh kwin`,
tiling/placement node tests and offscreen lifecycle command.

## P2: Consume fresh state without UI side effects

Dependencies: P1. Likely files: `clock/contents/ui/LayoutState.qml` (new),
`clock/tests/calendar_backend_test.py`, `clock/tests/calendar_view_test.py`,
`docs/parts/shell-topbar.md` (at most four).

- [ ] Start unknown; accept only the current consumer/provider/view and non-regressing state.
- [ ] Treat outcomes separately from state, including same-provider reordering and timeout/late
      confirmation; no persistent field alone can authorize an action or mode label.
- [ ] Invalidate correctly on observed provider loss/replacement without an idle polling loop.

Verify: fail-first cases in existing calendar suites, on private buses as specified; include a
retained-field bootstrap and provider-owner replacement control. No window operations.

## P3: Add clock configuration without stale writes

Dependencies: P2. Files: `clock/contents/config/main.xml`, the three existing
`clock/contents/ui/Config{General,Calendar,TimeZones}.qml` pages, and
`clock/tests/calendar_config_test.py` (five).

- [ ] Add the user visibility choice and only the private fields the G0 contract needs.
- [ ] Preserve every page's complete key/default declarations and refresh keys it does not edit.
- [ ] Opening/applying any configuration page cannot replay a request or replace fresher state.

Verify: fail-first configuration regressions, `tools/build.sh topbar` key checks and the spec's
calendar configuration command. Test visibility and private-field changes while a page is open.

## P4: Show a read-only mode control

Dependencies: P2–P3. Likely files: `clock/contents/ui/main.qml`,
`clock/contents/ui/LayoutControl.qml` (new), `clock/contents/ui/WidthBudget.qml`,
`clock/tests/calendar_view_test.py`, `docs/parts/shell-topbar.md` (five).

- [ ] Display only confirmed view-scoped state; keep actions disabled until P5–P6 qualify them.
- [ ] Preserve dots/calendar/wheel behavior and existing width-budget order; derive measured
      label/compact/hidden savings using existing design tokens.
- [ ] Cover one desktop, narrow bars, dark/light, RTL, large text and tablet/vertical hiding.

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
- [ ] Include fair arbitration across bars and a mixed shell/KWin replacement matrix, which
      testing.md listed as G0 work, and an absent backend on a stock-KWin image, moved from G0
      item 3; building that image needs the owner's approval ([g0-decisions.md](g0-decisions.md)).
- [ ] Preserve evidence, screenshots, versions/OIDs and limits; no new script error/crash or
      native restoration/placement-memory regression in the tested scenarios.

Verify: the spec's exact commands, the qualified scenario runner and result checks. Record
missing tools or environments as incomplete validation, not pass. Do not use another session's
VM, image tag, candidate refs or build outputs; do not install on the owner's desktop.

## Final checkpoint

- [ ] Each spec requirement has a source/test/evidence reference and its limits are explicit.
- [ ] Independent review and actionable findings are resolved; owner decides any merge.
- [ ] No native fork, packaging/CI/release, unrelated-task or live-desktop change was introduced.
- [ ] Live backgrounds, captive portals and notification work remain separate modules.
