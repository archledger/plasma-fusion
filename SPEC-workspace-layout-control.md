<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Spec: workspace layout control

Status: **Accepted on 2026-11-17**, including the refusal and adversarial-test refinements below.
Module: `workspace-layout-control` in
[CAPABILITY-MAP.md](CAPABILITY-MAP.md). Baseline: main
`44412a8901bf15c9f467fd5675795ee42fc3ffb7`. No implementation is included in this specification.

## Objective and assumptions

Make Fusion's existing dynamic tiler discoverable from the top bar without requiring a user to
assign a shortcut. A compact control beside workspace navigation reports the current view's
mode and offers explicit **Floating** and **Tiled** choices.

Scope accepted for this first slice:

- This is a desktop/laptop control, hidden in tablet posture and on vertical panels.
- A view is the virtual desktop, activity and output together, as in the existing tiler.
- **Floating** means Fusion's dynamic tiler does not own this view. It does not mean every
  window floats: manual snapping, maximize, full screen and window rules keep their behavior.
- The existing one-active-session contract remains. Selecting Tiled on another view moves the
  one session there, restoring the old session as the current shortcut does.
- There is no new default key binding. The existing Tile Workspace shortcut still works and
  its changes are reflected by the control.
- A clock-widget setting can hide the control independently of the workspace dots. It is
  shown by default only after the runtime confirms that supported tiling is available.

## User-visible contract

1. Put the control beside the workspace dots, or before the date/time when there is only one
   desktop. Do not replace the current-dot click that opens Overview or the date/time click
   that opens the calendar.
2. Report the mode for that bar's own output and current desktop/activity, not whichever
   output last answered or currently holds the pointer. A session on another view must not
   make this control read Tiled.
3. The control opens a menu with explicit Floating/Tiled choices and a check on the confirmed
   mode. Re-selecting that mode is a no-op, not a toggle.
4. Selecting Floating ends only the session in this view. If another view owns the one
   session, it is left alone.
5. Selecting Tiled uses an eligible application window from the intended view. Opening the
   menu must not cause a panel, calendar or unrelated window to become the master. If there
   is no suitable target, refuse safely and give a concise reason.
6. Capture and validate the intended view for an action. A desktop/activity switch, output
   removal, window close or focus change while the menu is open must not redirect the action
   to another view or use a stale window reference.
7. Show a pending state during an unconfirmed request and prevent duplicate submissions.
   Never show Tiled merely because a click or message send succeeded. A refusal does not mark
   the requested view Tiled; every bar reflects authoritative state, including any old-session
   teardown already completed during a cross-view transfer. No transactional rollback is
   promised. Loss of the state provider makes the mode unknown/unavailable.
8. Stock KWin, an absent/disabled placement script or an unsupported native interface must
   not expose a functioning-looking tiling toggle. Do not auto-enable scripts, install a
   profile or make geometry writes as a fallback.
9. Narrow bars may collapse the label before hiding the control. Any compact control keeps
   an accessible mode name. Do not overlap neighboring widgets, hide the clock, or silently
   change the width-budget order; resolve the exact presentation in the reviewed design.
10. The menu works with pointer and keyboard, supports Escape, has visible focus and
    accessible names, and does not forward a click or wheel event to the calendar/workspace
    actions behind it. Keep RTL, large-text and reduced-motion behavior.

## Ownership and state boundary

The placement script owns tiler policy and remains the only authority for capability, view,
pending intent and session mode. The clock widget is a consumer, not a second tiler.

The current source has no shell-facing layout-state protocol. Its transport is an engineering
decision for the implementation plan, not an API assumed to exist here. The plan must prove:

- a fresh initial state when the clock or placement script starts or reloads;
- updates after the existing shortcut, native teardown and relevant view changes;
- invalidation across provider replacement, script disable and KWin restart;
- rejection of stale replies and actions from an earlier provider or view;
- idempotent explicit mode requests with bounded completion/failure handling;
- no persisted setting treated as live truth, geometry-based inference or idle polling loop;
- no app titles, notification text or placement-memory records published unnecessarily.

Prefer existing in-process/session-bus infrastructure. No new daemon, privilege, dependency or
native fork contract is approved. If a reliable boundary cannot be built within that scope,
stop and bring back the specific gap rather than weakening these guarantees.

## Tech stack and affected structure

The repository supports Plasma 6.7/6.8. `packaging/tested-versions.txt` records Plasma 6.8.3 and
Qt 6.11.2; native tiling remains capability-gated to the maintained fork. QML/JavaScript own
these two parts; Python/PySide6 and node run their existing isolated suites.

| Path | Responsibility |
|---|---|
| `packages/plasmoids/org.plasmafusion.clockpill/contents/ui/` | Clock/workspace presentation and interaction. |
| `packages/plasmoids/org.plasmafusion.clockpill/contents/config/` | User-visible clock configuration. |
| `packages/plasmoids/org.plasmafusion.clockpill/tests/` | Clock UI and configuration regressions. |
| `packages/kwin/scripts/plasmafusion-placement/contents/ui/` | Authoritative tiler state and explicit requests. |
| `packages/kwin/tests/` and `tests/offscreen/` beneath it | Pure rules and real-script lifecycle tests. |
| `packages/common/` | Existing metrics, focus, color and motion conventions. |
| `docs/parts/shell-topbar.md`, `docs/parts/kwin.md` | Maintained behavior documentation. |

Do not edit copied/generated QML in a stage directory. Keep the bridge and UI separable so
their state/lifecycle tests do not require starting a real desktop.

## Code style

Follow the surrounding QML's explicit properties, named signals and four-space indentation.
For example, `WorkspaceDots.qml` already exposes intent rather than changing the desktop:

```qml
required property int currentIndex
signal switchRequested(int index)
signal overviewRequested()
```

Keep the same separation for layout intent. Use existing Fusion metrics, colors and motion
tokens; no new palette, font, arbitrary animation duration or endless animation. Use
translatable text and the repository's SPDX headers. Follow the existing script's window
lifetime guards and restoration/placement-memory rules instead of duplicating them.

## Testing strategy

Add fail-first coverage for mode/view selection, idempotence, capability gating, stale reply
rejection and provider replacement. Exercise the real placement script in its offscreen
lifecycle harness, including refusal, pending admission, cancellation and native teardown.
Do not replace those cases with a mock that merely assumes the bridge is callable.

Exercise the actual clock control: both choices, keyboard and pointer operation, Escape,
focus visibility, one desktop, two outputs, RTL, long translations/large text, width pressure,
tablet/vertical hiding and unavailable state. Verify the existing dots, calendar and wheel
actions still work and configuration pages preserve keys they do not edit.

The technical plan must explicitly cover:

- Keyboard entry after the panel has already acquired focus, not only a pointer opening while
  an application remains active.
- Competing requests from two bars, including two controls for the same view.
- Delayed state replies within the same provider/view, and a timeout followed by late
  authoritative confirmation. An old reply must not overwrite a newer confirmed state.

Before a merge, use a separately named isolated Plasma session to test the actual boundary
between plasmashell and KWin. Check a shortcut change, script reload, a refused admission and
an output/view change, with no new script error or compositor crash. Offscreen stand-ins alone
do not qualify this boundary. Do not borrow another workstream's VMs or rebuild its images.

## Commands

Existing relevant commands, from the repository root:

```sh
STAGE="$PWD/build/layout-control-stage" tools/build.sh topbar kwin
node packages/kwin/tests/tiling.test.js
node packages/kwin/tests/placement.test.js
QT_QPA_PLATFORM=offscreen \
  python3 packages/kwin/tests/offscreen/tiling_lifecycle_test.py \
  "$PWD/build/layout-control-stage/.local/share/kwin"
node --test packages/plasmoids/org.plasmafusion.clockpill/tests/formats.test.js \
  packages/plasmoids/org.plasmafusion.clockpill/tests/calendar.test.js
QT_QPA_PLATFORM=offscreen dbus-run-session \
  --config-file=packages/kwin/tests/offscreen/session-bus.conf -- \
  python3 packages/plasmoids/org.plasmafusion.clockpill/tests/calendar_view_test.py \
  "$PWD/build/layout-control-stage"
QT_QPA_PLATFORM=offscreen dbus-run-session \
  --config-file=packages/kwin/tests/offscreen/session-bus.conf -- \
  python3 packages/plasmoids/org.plasmafusion.clockpill/tests/calendar_config_test.py
tools/checks/tests/run.sh
tools/checks/shellcheck.sh
ruff check
reuse lint
git diff --check
```

These are required validation commands, not results. The implementation plan must name any
new suite and the isolated-session recipe before implementation. Missing local tooling must
be reported; do not install or silently skip it. Coordinate before changing CI wiring.

## Boundaries and success criteria

- **Always:** preserve placement memory, float restoration, manual-window precedence and
  existing shortcuts; add meaningful regressions; document behavior and validation limits.
- **Ask first:** a new dependency/daemon, native seam, packaging/CI change, live installation,
  merge, release or use of a shared VM/test desktop.
- **Never:** optimistic success labels, geometry-based mode detection, weakening tests,
  automatic tiling, changing the one-session contract, or touching unrelated worktrees.

Complete means all user-visible and state-boundary criteria above are demonstrated, relevant
checks pass on the tested revision, the two part pages agree with the implementation, and
isolated runtime evidence covers the real cross-process path. No performance or compatibility
claim extends beyond the recorded measurements and tested versions.

## Remaining decisions before implementation

- Placement/default/fallback behavior and the meaning of Floating above are accepted.
- In the subsequent plan, establish the supported state/intent transport against the actual
  Plasma/KWin versions. Prove it without a native fork change or identify the blocker.
- Derive the exact visual presentation from the existing boards/tokens and review its
  dark/light, compact and keyboard states before shipping.

Source references: [top-bar behavior](docs/parts/shell-topbar.md),
[tiler behavior and deliberate limits](docs/parts/kwin.md),
[native tiling contract](docs/NATIVE-TILING-CONTRACT.md),
[Qt Menu behavior](https://doc.qt.io/qt-6/qml-qtquick-controls-menu.html). Qt documentation was
consulted for keyboard/menu expectations; it does not establish the missing state transport.
