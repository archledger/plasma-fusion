<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Implementation plan: workspace layout control

Status: **Accepted on 2026-11-17.** The [specification](../../SPEC-workspace-layout-control.md) is
accepted, including its two refinements. P0 is authorized; later review gates still apply.
Tasks are in [todo.md](todo.md). The owner selected this separate folder to preserve the existing
native-tiling `tasks/plan.md` and `tasks/todo.md`.

## Objective and scope

Add a truthful Floating/Tiled control to the desktop clock/workspace area. Preserve one active
tiling session, the native restoration and placement-memory contracts, current shortcuts and
the existing dots/calendar behavior. Portal sign-in, notification actions and live backgrounds
are separate work.

The dependency graph is:

```text
G0: real transport/lifecycle proof
  -> provider snapshot and consumer-state rules
  -> read-only state path
  -> explicit, fenced mode requests
  -> accessible menu and width/config integration
  -> adversarial regression and real-session qualification
```

The first checkpoint is deliberately early. Do not build UI on a transport that only works in
a stand-in. A failed G0 returns a concrete blocker for scope review, not a native fork patch,
daemon, polling loop or weakened freshness rule.

## Source evidence and limits

Inspected at Plasma Fusion main `44412a8901bf15c9f467fd5675795ee42fc3ffb7`:

- The placement script owns `tiler.session` and the accepted provider. Its `toggle()` ends an
  old session before trying admission on another view. A transfer refusal is not rollback.
- Its four `ShortcutHandler`s are sequence-less. Existing KWin-to-shell traffic uses
  `DBusCall` to `org.kde.PlasmaShell.evaluateScript`.
- The clock already uses session-bus calls and resolves the current desktop for its bar's
  screen. `WorkspaceDots.qml` owns its current-dot/Overview behavior.
- `WidthBudget.qml` computes levels 0–7 without trying successive layouts. New label savings
  must be accounted for; do not add a layout feedback loop or reorder its existing steps.
- The real-script lifecycle and clock-view tests run in the existing build workflow.

Version-matched upstream source, inspected read-only:

- [KWin 6.8.3 ShortcutHandler](https://invent.kde.org/plasma/kwin/-/blob/v6.8.3/src/scripting/shortcuthandler.cpp)
  registers a QAction with KGlobalAccel and connects its trigger to the QML handler.
- [KWin 6.8.3 DBusCall](https://invent.kde.org/plasma/kwin/-/blob/v6.8.3/src/scripting/dbuscall.h)
  provides asynchronous outgoing method calls; it is not an arbitrary method-export API.
- [KWin Script XML](https://invent.kde.org/plasma/kwin/-/blob/v6.8.3/src/scripting/org.kde.kwin.Script.xml)
  exports run/stop, not the placement script's private tiler object.
- [Plasma 6.8.3 Applet scripting](https://invent.kde.org/plasma/plasma-workspace/-/blob/v6.8.3/shell/scripting/applet.cpp)
  routes known configuration items through the live configuration scheme. It saves them too:
  such data cannot be accepted as live state without a fresh exchange.
- [Plasma 6.8.3 SignalWatcher](https://invent.kde.org/plasma/plasma-workspace/-/blob/v6.8.3/components/dbus/dbussignalwatcher.h)
  can receive D-Bus signals in QML.
- [Plasma 6.8.3 service watcher](https://invent.kde.org/plasma/plasma-workspace/-/blob/v6.8.3/components/dbus/dbusservicewatcher.cpp)
  watches registration/unregistration. Its Boolean is not an owner-identity fence.

Context7 returned mostly master-source material, so the tagged sources above take precedence.
The host currently has plasma-workspace 6.8.2 and Qt 6.12.0; that is not the target qualification
environment. The repository's tested-version record is Plasma 6.8.3/Qt 6.11.2. Neither a source
read nor the installed QML type descriptions proves the proposed bridge works.

## G0: preferred transport candidate, not a proven interface

First test a sequence-less, dedicated wake-up action through the existing KGlobalAccel path.
It must not invoke the existing blind toggle or acquire a default key. The placement script
would read small per-widget request envelopes through shell scripting and publish confirmed
state through each intended widget's declared response field. The argument-less wake-up may
coalesce: it must discover outstanding requests from live clock widgets, not rely on one
global slot that a second bar can overwrite. Bound and serialize the read/publish pipeline.

Separate request and response fields; never use one overwriteable mailbox for both directions.
These fields are transport data, not saved preferences or authority. A new consumer starts
unknown and must reject retained data until a fresh exchange establishes its current lifetime.
Do not publish the native writer's ownership token as a client credential.

This candidate needs an actual two-process proof of:

1. Wake-up dispatch into the real declarative script, not just a successful D-Bus send.
2. Delivery to the intended live widget, with fresh consumer/provider lifetimes and ordering.
3. Native capability/refusal reporting, and updates from the existing shortcut.
4. Invalidation on script disable/reload, shell restart and KWin owner replacement. Do not
   assume a generic service Boolean or an internal C++ `runningChanged` is a public script signal.
5. No idle polling, script reload as a command mechanism, global reconfigure per action, new
   daemon or new native endpoint.

The concrete envelope encoding, lifecycle identifiers and invalidation path are unresolved
until G0. Record source, packet/event traces, controls and failure cases. Review that receipt
before settling the contract. If the candidate cannot satisfy the accepted spec, stop here.

## Contract to establish after G0

Keep one small, feature-owned protocol. Its minimum semantics are:

- Explicit query/prepare/set intent, never a toggle inferred from the last click.
- Protocol version, consumer lifetime, provider lifetime, request identity and state ordering.
  State revision and request completion are distinct: an old state snapshot must not replace
  newer state, but dropping it must not lose a relevant completion acknowledgement.
- View identity is desktop id, activity id and output identity, checked by the provider.
  An index, geometry rectangle or pointer location alone is insufficient.
- A prepared application target stays inside KWin as a guarded reference. No app titles,
  placement records or unnecessary window identifiers cross the boundary.
- Same request identity and payload means the same intent. Reject a reused identity with a
  different payload. Serialize mutations in the provider; a competing request gets a bounded
  busy/refused outcome and fresh state, not a second uncontrolled operation.
- A timeout means unconfirmed, not failed or cancelled. Do not retry a mutation blindly.
  Reconcile against fresh state; accept a late authoritative update only if it passes all
  lifetime/view/order checks.
- Bound message size, outstanding work and retained outcomes. Reject malformed/unknown
  protocol versions and modes before any action; serialize data with proper escaping, not
  interpolated executable fragments.

For keyboard entry after panel focus, investigate retaining the last eligible application
activation per view inside the placement script. `Workspace.windowActivated` is present in the
tagged wrapper. A prepared target must still be alive and eligible in the captured view;
another application activation, window departure or view loss invalidates it. Never pick an
arbitrary stacking-order window as a fallback. Test the actual focus event order before
accepting this policy.

Use explicit desired-mode handling around the existing start/untoggle policy. Floating on a
different view is a no-op; same confirmed mode is a no-op. On a cross-view transfer, report any
old-session teardown even if new admission fails. Do not add transactional restoration of the
old session.

## UI and layout

Build a separate, feature-owned menu/control using existing Fusion tokens. Keep the normal
desktop pill height, focus treatment and motion behavior; use the available row hit area rather
than inventing a new panel size. Support pointer, Tab, Return/Space, arrow keys and Escape.

Derive full-label, compact-label and hidden states from measured width savings. Account for
the added control in the clock's existing budget calculation without changing the current
collapse order. Hiding the control must not prevent the existing shortcut from working.
Review dark/light, large-text, RTL, one-desktop and crowded-bar screenshots before qualification.
Keep it hidden in tablet posture, vertical panels and an unconfirmed/unsupported profile.

The user setting and private transport fields must be declared consistently across all three
clock configuration pages. Apply in another page must not restore old transport data or undo
the user's visibility choice. Configuration export/import must not make retained envelopes
actionable after reload.

## Required acceptance matrix

| Case | Required observation |
|---|---|
| Cold start or shell restart with old saved fields | Unknown until a fresh exchange; no replayed mutation. |
| Stock/absent/disabled/refused backend | No functioning-looking toggle and no geometry fallback. |
| Existing shortcut on/off | Every relevant bar follows authoritative state. |
| Floating requested on B while A is tiled | A stays tiled. |
| Tiled transfer A→B with B refused | No false Tiled on B; bars report A's completed teardown. |
| Keyboard entry after panel focus | Eligible intended app, or safe refusal; never the panel. |
| App focus change/close/departure while menu open | Prepared target rejected rather than redirected. |
| Two controls for one view; two bars for different views | Idempotence and provider serialization, no double toggle. |
| Same provider/view, out-of-order replies | No state regression or lost matching completion. |
| Timeout followed by late confirmation | Unconfirmed outcome reconciles; no blind repeated mutation. |
| Provider reload/disable, KWin owner replacement | Old lifetime rejected and availability invalidated. |
| Output removal or activity/desktop switch | No wrong-view operation or stale reference. |
| Manual snap/maximize/fullscreen, placement memory | Existing behavior and floating records preserved. |
| UI input and constrained layout | Dots/calendar/wheel unchanged; keyboard/RTL/text/focus correct. |

Use the actual lifecycle and clock suites for production integration. Extend a stand-in only
to match an observed API, not to make a guessed transport pass. Final qualification uses the
real shell and fork in an independently named isolated session.

## Verification and isolation

Run the accepted spec's focused build, lifecycle, calendar, lint and license commands after the
affected changes. The new G0 fixtures/scenario must have an explicit runner and nonzero failure
exit. The following is the proposed isolated invocation once those fixtures exist:

```sh
STAGE="$PWD/build/layout-control-stage" tools/build.sh topbar kwin
python3 tools/tests/layout-control/prepare_seed.py \
  --stage "$PWD/build/layout-control-stage" --output "$PWD/build/layout-control-seed"
PFV_IMAGE="${PF_LAYOUT_IMAGE:?Set an independently prepared, pinned test image ID}" \
  PFV_DRI=0 tools/vsession/cvsession.sh \
  "layout-control-probe-$(date -u +%Y%m%dT%H%M%S)" \
  tools/tests/layout-control/scenario-bridge.sh "$PWD/build/layout-control-seed" 1440x900 180
```

`prepare_seed.py` and `scenario-bridge.sh` are proposed files, not existing commands or results.
The image must provide the required real shell/fork pair, with recorded versions/checksums,
and must not replace or modify another workstream's tag, image, VM or build outputs.
`PFV_DRI=0` is suitable for protocol traces, not screenshots; final visual qualification needs
a separately verified rendering path through the existing harness.

The existing calendar backend runner used by P2 is:

```sh
QT_QPA_PLATFORM=offscreen dbus-run-session \
  --config-file=packages/kwin/tests/offscreen/session-bus.conf -- \
  python3 packages/plasmoids/org.plasmafusion.clockpill/tests/calendar_backend_test.py
```

Do not use `packages/kwin/tests/vsession/make-seed.sh` blindly: it currently SSHes to the
ThinkPad for a Python path and expects a full stage. The new local seed fixture must perform
no SSH, install, change to the live HOME or use of the logged-in display/session bus.

Full REUSE and ruff are absent on the host. Establish an isolated existing-tool environment
without changing shared images or installing host packages, or report the unavailable check;
do not weaken it. Do not add CI wiring or dependencies without coordination.

## Review gates and stops

1. Owner reviews this conditional plan before G0 work.
2. Review G0's real receipt and chosen contract before production integration.
3. Review the read-only state path and explicit-request tests before enabling the menu.
4. Review final source, real-session evidence and remaining limitations before requesting merge.

No commit, PR, merge, release, package build or live installation is implied by a passed probe.
Preserve the concurrent KWin alignment/packaging/CI/candidate/VM work and all existing task files.
