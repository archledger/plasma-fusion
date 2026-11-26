<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Spec: notification triage

Status: **Accepted on 2026-11-26**, with the decisions below approved to proceed. Module:
`notification-triage` in [CAPABILITY-MAP.md](CAPABILITY-MAP.md). Baseline: main
`b3f5a7505f3fd8e50f6d94025459cbfbd400fb60`, Plasma Workspace 6.8.3 (`v6.8.3`,
`4302f699329ebb155097beaab2d5aabbb21e33b3`), fork KWin `6.8.3-1.fc44.pf1`. No implementation is
included in this specification.

Evidence, all from 2026-11-26 and recorded in the project's shared ledger:

- **Focus-then-dismiss validation.** A throwaway test widget in private sessions, on stock KWin
  in a VM and on the fork KWin on a ThinkPad, with lock and shortcut-inhibitor cases.
- **Enter and Tab probe.** The same two machines and the same kind of test widget.
- **Research report** "Keyboard notification handling user needs": what KDE users ask for, how
  other systems handle banners from the keyboard, accessibility and design guidance, and
  interruption studies.

Every run used injected input in a private session. Nothing here has been tested with users,
on the physical keyboard or in a live desktop.

## Objective and assumptions

Let a user deal with the newest notification banner without leaving the keyboard. Today a banner
cannot be handled from the keyboard at all: the stock banner has no key handling, so it stays
until it times out or the pointer dismisses or opens it.

The module is described in the capability map as separate quick actions for dismissing and
activating the newest eligible notification, with shortcut assignments and the lock-screen
boundary preserved. This slice takes the two-step shape that replaced the one-key design:

- One configurable shortcut, **Focus notification banner**, with no default key binding.
- On the focused banner, **Escape** dismisses it into the history the way its own timeout would,
  and **Enter** does what a click on it does.
- The newest banner only. Choosing among several banners, a one-key dismiss and dismissing
  everything are later slices.

The benefit to claim is convenience and motor access. It is not less interruption: the studies
put the cost of an alert on its arrival, and none of them measures a keyboard path to a banner.

Why this shape:

- **It is the only one proven to respect the lock and inhibitor boundary.** Dismissal happens
  only when Escape reaches a banner that KWin has actually focused. A one-key dismiss needs its
  own proof of which banner it may act on while locked, which was not found.
- **Users asked for it, thinly.** [KDE Bug 439893](https://bugs.kde.org/show_bug.cgi?id=439893)
  (2021) asks for a shortcut that focuses the latest notification,
  [405639](https://bugs.kde.org/show_bug.cgi?id=405639) (2019) for the default action by key, and
  [381244](https://bugs.kde.org/show_bug.cgi?id=381244) (2017) for a way to dismiss "without
  superfine motor skills". The larger and more recent request is to dismiss everything
  ([500308](https://bugs.kde.org/show_bug.cgi?id=500308),
  [514072](https://bugs.kde.org/show_bug.cgi?id=514072)), which is a later slice.
- **Focus theft is the loudest complaint.** KDE reports from 2009 to 2025 describe banners that
  took focus on arrival, and a 2026 report describes typed text landing in another window after
  a notification. A banner that holds keyboard focus is a real active window, which is why focus
  must move only on the user's key press and go back afterwards.
- **It matches the closest precedents.** GNOME (Super+N, then Escape), Windows (Win+Shift+V,
  then Delete), Omarchy and VS Code all focus first and act second, and Material's snackbar
  guidance states the same pattern: no focus on arrival, a documented shortcut to move focus
  there, Escape to dismiss, then focus returns.
- **Dismissing should keep the notification.** GNOME's banner Escape acts as a timeout that keeps
  the notification. Mail and chat clients never make dismiss mean delete. In one phone study,
  44% of dismissed notifications were ones the same users rated important.

Four safeguards follow from the evidence and are not optional: arrival never moves focus; the
shortcut ships unassigned; focus returns to the window the user was in; Escape keeps the
notification.

Assumptions, each demonstrated by the probes:

1. A banner can be given real keyboard focus through the stock route that inline replies and
   pointer interaction already use.
2. On that banner, Escape ran the banner's own expiry once. The notification stayed in the
   history as expired and the previous window was active again.
3. Enter did what a click does: the default action once when there is one, nothing when there is
   none.
4. While the screen was locked, or a focused window held a keyboard-shortcut inhibitor, the
   shortcut did nothing. Locking while a banner was focused cancelled the focus.
5. A replacement while focused cancelled the interaction and returned focus to the previous
   window. A pointer focus change cancelled it without retargeting.
6. Tab from the focused banner moved keyboard focus to the banner's own controls.
7. Stock already pauses a banner's timer while the pointer rests on it, while its menu is open,
   and during an inline reply.

## User-visible contract

1. **Shortcut.** The notifications widget gains one global shortcut action, "Focus notification
   banner". It is listed with the widget's other shortcuts and assignable in System Settings,
   and it ships unassigned. No existing shortcut or action changes, including Fusion's own
   bindings. No on-screen hint is added in this slice.
2. **No eligible banner.** Nothing happens: no focus change, no message.
3. **Eligible banner.** The newest visible banner that shows a notification, whatever its
   urgency. Not eligible: a job popup, and a banner that is already handling keyboard input for
   a reply.
4. **Focus.** The banner becomes the active window and its content takes keyboard focus. A focus
   ring in the theme's focus colour is drawn around it and stays until the interaction ends. For
   that time the window the user was in is inactive, as with any other focus change. Stock
   behaviour on arrival is unchanged: a banner never takes focus by itself.
5. **Timer.** While the banner is focused, its timeout is paused, as it is while the pointer
   rests on it. It resumes when the interaction ends and the banner is still shown.
6. **Escape on the focused banner.** The banner is dismissed through its own expiry path, and
   the notification stays in the history. The sending application is told what the banner's
   timeout would tell it: nothing when the notification has actions or is resident, "expired"
   otherwise. The window that was active before the shortcut is active again. This is the
   explicit dismissal that the KDE guidelines require for a critical notification, so critical
   banners are eligible.
7. **Enter on the focused banner.** Return and Enter both act as a click: the application's
   default action if it supplied one, otherwise nothing. One press acts once; holding the key
   does not repeat the action.
8. **Keys inside the banner.** Tab and Shift+Tab move between the banner's controls as they do
   today. Escape dismisses the banner from its body and from its buttons. In the reply field
   Escape keeps its current behaviour, so a draft is not lost. No other key is given a meaning.
9. **The interaction ends by itself** when the banner is replaced, is closed, loses focus
   (pointer, another window, lock) or the screen locks. Nothing is dismissed or activated at
   that point and no other banner is targeted; the shortcut must be pressed again. Only a
   replacement that ends it while the banner is still focused returns focus to the previous
   window.
10. **Locked or inhibited.** No focus request is made while the screen is locked. A shortcut
    inhibitor held by the focused window keeps the shortcut from being dispatched, as for any
    global shortcut. The widget adds no check of its own.
11. **Held keys.** Activation happens on the first press. A key still held afterwards is
    delivered to the window that regains focus, as with any focus change.
12. **Stock fallback.** When the Fusion copy is not in force (see below), behaviour is exactly
    stock.

## Ownership and state boundary

KWin owns shortcut authorization, focus and the lock and inhibitor boundary. The notification
widget owns the banner, its timer, its expiry and the history. The feature keeps no claim of its
own about what may be dismissed.

The widget holds, per banner, at most one interaction state: not requested, requested, or
active. It records the previously active task when the shortcut is pressed and uses that record
only to restore focus after a replacement that ends an active interaction. It never restores
focus after the user's own focus change.

No new daemon, bus service, privilege or KWin change. Both probes ran on stock KWin and on the
fork without a compositor change.

## How it ships

The banner and its expiry belong to Plasma's stock notifications widget, a compiled plugin in
`plasma-workspace`. Three ways to change it were considered:

- **A Fusion-built copy of the stock plugin (chosen).** Fusion builds the stock notification
  applet from the matching upstream source with this change, and plasmashell loads it in place
  of the stock one.
- **A Plasma Workspace fork package**, as is done for KWin. Rejected: a whole-desktop package for
  one feature.
- **A KWin-side feature.** Rejected: the banner's expiry lives in the widget, and the compositor
  has no path to it.

This is the first Fusion part that stands in for a stock Plasma component. It follows the
pattern of the existing compiled parts, and it adds two requirements of its own:

- **Version-bound.** The copy is in force only while the installed `plasma-workspace` version is
  exactly the one it was built from. This is evaluated every time plasmashell starts. The
  existing login check alone does not satisfy it: it runs once per login, so a Plasma update
  followed by a plasmashell restart would otherwise load a mismatched copy. So the enforcement
  point runs before plasmashell picks its plugins: at any other version the copy is not put in
  front of the stock plugin, the stock plugin loads and the shortcut does not exist. A guard
  inside the copy, which keeps the feature off when the running version differs from the one it
  was built against, is kept as a second layer. On its own it would leave the copy in use with
  the feature off, so it does not replace that selection.
- **Packaging.** Adding a compiled part touches every channel's build. The capability map keeps
  packaging changes behind coordination first; the owner approved this one on 2026-11-26.

Proposed structure, to be confirmed by the implementation plan:

| Path | Responsibility |
|---|---|
| `packages/notifications-cpp/` | Build of the stock applet with the Fusion change, and its QML unit tests. |
| `tools/build.d/NN-notifications.sh` | Build step for the new part. |
| `packaging/<channel>/` | Build dependencies and a subpackage for the copy. |
| `tools/device/fusion-config.sh`, `tools/device/gate/` | Turning the copy on and off by version. |
| `tools/device/tests/vsession/` | The private-session scenarios, moved from the probes. |
| `docs/parts/notifications.md` | New part page, including the shortcut and how to bind it. |
| `CAPABILITY-MAP.md` | Status of `notification-triage`. |

Plasma 6.7 keeps stock behaviour. The first qualification target is Plasma 6.8.3 on Fedora 44,
the version the ThinkPad and the test VM run; the other channels follow afterwards.

## Code style

Keep the stock applet's structure and names; the change is small and should read as part of it.
Expose intent rather than acting from handlers where the surrounding QML does so. Use the
existing Kirigami focus colour and units for the focus ring, with no new token. User-visible text
is translatable. Files kept from KDE's source keep their licence and headers, as the lock screen
and task switcher parts do.

## Testing strategy

Fail-first QML tests for the selection rule, the interaction state and its cancel rules, the
timer pause, and the Escape and Enter handlers.

Private-session scenarios on the stock VM and on the ThinkPad, on the real Fusion copy rather
than the probe: the five modes already written for the probes (`stock`, `full`, `lock-idle`,
`lock-focused`, `activate`) as regressions, plus the cases the probes did not cover:

- **Eligibility:** critical and resident banners, a job popup, a banner in reply mode, and
  several banners at once, where only the newest is eligible.
- **Keys inside the banner:** Escape from a control inside the banner and from the reply field.
- **Timer:** the timeout stays paused while the banner is focused and resumes afterwards.
- **A real active window:** with Dim Inactive enabled, with a full-screen application in front,
  and with a different keyboard layout in that application, check what dims, what shows above
  what, and that the application's own state is back after the interaction.
- **Stock behaviour:** with the shortcut unassigned, and with the copy switched off, both must
  behave exactly like stock.
- **Version gate:** a matching and a different Plasma version.

A real-keyboard run in the live session, with the owner at the ThinkPad: press the shortcut,
Escape, Enter and Tab on the physical keyboard while test notifications arrive. The probes
injected input; this is the only step that covers the physical keyboard and the live desktop.

Before a merge, check that no new script error or compositor crash appears in any scenario, and
that the test application is left saved so the session tears down quietly. Do not borrow another
workstream's VMs or rebuild its images.

## Commands

Existing general checks, from the repository root:

```sh
tools/build.sh
tools/checks/tests/run.sh
reuse lint
ruff check
git diff --check
```

These are required validation commands, not results. The implementation plan must name the new
part's build step, its test suite and the isolated-session recipe before implementation. Missing
local tooling must be reported; do not install or silently skip it.

## Boundaries and success criteria

- **Always:** preserve existing shortcuts and stock behaviour on arrival; dismiss only on Escape
  at a focused banner; keep dismissed notifications in the history; add regressions for every
  rule above; keep a stock fallback; document behaviour and validation limits.
- **Ask first:** a new dependency or daemon, a native seam, any further packaging or CI change
  beyond this part, a live installation, a merge, a release, or use of a shared VM or test
  desktop.
- **Never:** focus on arrival, a default key binding that overrides an existing one, dismissing
  or activating without focus, changing how applications are told, weakening a check, or editing
  a generated file.

Complete means every rule in the user-visible contract is demonstrated on the Fusion copy on
both machines, the checks above pass on the tested revision, the part page agrees with the code,
and the physical-keyboard run is recorded. No claim extends beyond the tested versions.

## Decisions accepted on 2026-11-26

The research report ended with eight questions for this specification. Each was settled as
follows.

1. **Shipping.** The Fusion-built copy of the stock plugin, with its packaging change.
2. **Finding the shortcut.** The standard shortcuts page and the part page document it. A later
   slice may add a hint.
3. **Escape from the banner's controls.** It dismisses from the buttons and keeps its current
   behaviour in the reply field. Not yet tested; the implementation must test it first.
4. **Enter with no default action.** Nothing, as a click does today. KDE Bug 405639 asks for the
   banner to close instead; that is not adopted.
5. **Held keys.** A key held across an activation is typed into the window that gets focus back.
   This is accepted as ordinary focus behaviour. Preventing it would need compositor support and
   is not in this slice.
6. **Eligibility and the timer.** Every visible notification banner except job popups and
   banners in reply mode, and the timer paused while focused. Critical and resident banners and
   the timer pause were not exercised by the probes and need their own cases.
7. **Default binding.** None in this slice. Fusion's profile already binds Meta+N to the
   notification view, and a later slice may propose a binding of its own.
8. **Older banners and dismiss-all.** Newest only. Stepping to an older banner and dismissing
   everything are later slices.
9. **Channels.** Fedora 44 first; the other channels follow afterwards.
10. **Where the version rule is enforced.** Before plasmashell picks its plugins, so that at
    another version the stock plugin loads. A guard inside the copy is kept as a second layer
    and does not replace that selection: on its own it would leave the copy in use with the
    feature off. A review remark on this specification showed that the second of two allowed
    enforcement points could not deliver rule 12.

Left for the implementation plan: per-channel build requirements, the source of the stock tree,
the exact gate mechanism with its enforcement point, and the new test suites. The plan must prove that a copy which fails to
load leaves the user with a working stock notification widget at the next plasmashell start.
Proposing the change to KDE upstream is worth doing in parallel; it is the owner's own action and
not the delivery path.

Source references: [capability map](CAPABILITY-MAP.md),
[architecture](docs/ARCHITECTURE.md), [login check](docs/parts/gate.md),
[compiled parts](docs/parts/navigation-cpp.md), [plan](docs/PLAN.md).
