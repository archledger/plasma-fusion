<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Spec: notification triage

Status: **Accepted on 2026-11-26**, with decisions 1 to 10 below approved to proceed; decisions
11 to 17 are proposed and wait for the owner. Module:
`notification-triage` in [CAPABILITY-MAP.md](CAPABILITY-MAP.md). Baseline: main
`b3f5a7505f3fd8e50f6d94025459cbfbd400fb60`, Plasma Workspace 6.8.3 (`v6.8.3`,
`4302f699329ebb155097beaab2d5aabbb21e33b3`), fork KWin `6.8.3-1.fc44.pf1`. No implementation is
included in this specification.

Evidence, all from 2026-11-26 and kept in the project's own records, which are not part of
this repository:

- **Focus-then-dismiss validation.** A throwaway test widget in private sessions, on stock KWin
  in a VM and on the fork KWin on a ThinkPad, with lock and shortcut-inhibitor cases.
- **Enter and Tab probe.** The same two machines and the same kind of test widget.
- **Research report** "Keyboard notification handling user needs": what KDE users ask for, how
  other systems handle banners from the keyboard, accessibility and design guidance, and
  interruption studies.

Every run used injected input in a private session. Nothing here has been tested with users,
on the physical keyboard or in a live desktop.

## Objective and assumptions

Let a user deal with the newest notification banner without leaving the keyboard. Today the
keyboard cannot reach a banner: nothing gives one keyboard focus, and the stock banner has no key
handling of its own, so it stays until it times out or the pointer dismisses or opens it.

The module was described in the capability map as separate quick actions for dismissing and
activating the newest eligible notification, with shortcut assignments and the lock-screen
boundary preserved; the map's row now says what this slice does. This slice takes the two-step
shape that replaced the one-key design:

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
shortcut ships unassigned; the keyboard goes back to the window the user was in when the
interaction ends by a replacement, by the widget's request or by KWin's own order; Escape keeps
the notification.

Assumptions. The first six were demonstrated by the probes; the seventh is a reading of the
stock source.

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
   urgency. Newest is by the time its notification first arrived, so that a replacement does not
   make a banner newer. Not eligible: a job popup, and a banner in which a reply has been
   started. A banner that is not eligible is passed over: with the newest banner in a reply, the
   shortcut takes the next older eligible one.
4. **Focus.** The banner becomes the active window and its content takes keyboard focus. A focus
   ring in the theme's focus colour is drawn around it and stays until the interaction ends. For
   that time the window the user was in is inactive, as with any other focus change. Stock
   behaviour on arrival is unchanged: a banner never takes focus by itself.
5. **Timer.** While the banner is focused, its timeout is paused, as it is while the pointer
   rests on it. It resumes when the interaction ends and the banner is still shown, from the full
   length of its timeout, as it does after the pointer leaves it.
6. **Escape on the focused banner.** The banner is dismissed through its own expiry path, and
   the notification stays in the history. The sending application is told what that path tells
   it after a timeout: nothing when the notification is resident, or has actions and is not
   transient; "expired" otherwise. Urgency changes nothing in that rule: a critical banner
   without actions is told "expired" although it has no timeout, and one that is resident, or has
   actions and is not transient, is told nothing like any other. After the
   dismissal the widget asks for nothing: KWin's own focus order makes the window that was active
   before the shortcut active again when it still exists, and chooses another when it does not.
   This is the explicit dismissal that the KDE guidelines require for a critical notification, so
   critical banners are eligible.
7. **Enter on the focused banner.** While the banner's content itself has the keyboard focus,
   Return and Enter both act as a click: the application's default action if it supplied one,
   otherwise nothing. One press acts once; holding the key does not repeat the action.
8. **Keys inside the banner.** Tab and Shift+Tab move between the banner's controls. A control
   that has the keyboard focus is pressed with Space, as in stock; Return does nothing there,
   and neither key is taken as Enter on the banner. Escape dismisses the banner from its body and
   from its other controls. In the reply field, and on its Send button, Escape keeps its stock
   behaviour, which is nothing, so a draft is not lost while the keyboard focus is there; from
   another control it dismisses, and a draft left in the field goes with the banner, as it does
   when the banner is closed by its own button. Starting a reply keeps the banner taken: its
   timeout stays paused and Escape still dismisses it from its other controls. No other key is
   given a meaning, and nothing brings the keyboard back to the content but taking the banner
   again.
9. **The interaction ends by itself** when the banner is replaced, is closed, is hidden because
   it no longer fits, loses focus (the pointer, another window) or the screen locks, and when
   KWin has not granted the focus 1.5 seconds after the request. Nothing is dismissed or
   activated at that point and no other banner is targeted; the shortcut must be pressed again.
   Only a replacement that ends a focused interaction makes the widget ask for the window it
   recorded, and only when no reply has been started in the banner: with a reply started, the
   keyboard stays with the banner, as it does in stock. When there is nothing to ask for, because
   the recorded window is gone or never was one, the banner stays the active window and takes no
   key; a click, or the shortcut again, brings the keyboard back.
10. **Locked or inhibited.** KWin does not deliver the shortcut while the screen is locked, so
    no focus request is made; locking while a banner is taken ends the interaction. After
    unlocking, the banner may be the active window again, not taken: the shortcut must be pressed
    again. A shortcut inhibitor held by the focused window keeps the shortcut from being
    dispatched, as for any global shortcut. The widget adds no check of its own.
11. **Held keys.** Activation happens on the first press. A key still held afterwards is
    delivered to the window that regains focus, as with any focus change. This is an accepted
    limitation (decision 5).
12. **Stock fallback.** When the Fusion copy is not in force (see below), the stock plugin is
    the code that runs. The binding a user gave the shortcut is kept by the shortcut daemon, not
    by the copy; what System Settings then shows for it is for the gate to settle.
13. **With the copy in force and the shortcut unassigned.** The banner then differs from stock in
    one way: when the keyboard focus reaches a banner's reply field, the reply starts, as it does
    on a click, so that Tab cannot type into a banner that is not replying. Everything else is
    stock's.

## Ownership and state boundary

KWin owns shortcut authorization, focus and the lock and inhibitor boundary. The notification
widget owns the banner, its timer, its expiry and the history. The feature keeps no claim of its
own about what may be dismissed.

The widget holds, per banner, at most one interaction state: not requested, requested, or
active. When the shortcut is pressed it records the window that has the keyboard focus, unless
that window is one of its own taken banners, in which case the earlier record stands; the record
is a window, never a banner. It uses that record only after a replacement that ends a focused
interaction in which no reply was started. It never restores focus after the user's own focus
change. A request that KWin has not granted within 1.5 seconds is dropped. The applet's debug
reports name a banner by its notification id and an item by its type; none carries the text of a
notification or of a reply.

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

  The copy is built from KDE's source at that version, not from a distribution's package: a fix
  that a distribution applies to this applet is not in the copy until the copy is rebuilt from it.
- **Packaging.** Adding a compiled part touches every channel's build. The capability map keeps
  packaging changes behind coordination first; the owner approved this one on 2026-11-26.

Structure, as the two implementation pull requests have it:

| Path | Responsibility |
|---|---|
| `packages/notifications-cpp/` | The stock applet with the Fusion change, its build, the directory guard and its record. |
| `packages/notifications-cpp/tests/` | The Qt Tests, the guard's unit test and the private-session scenarios. |
| `packaging/fedora/plasma-fusion.spec` | The build requirements, until the second plan adds a subpackage per channel. |
| `tools/device/gate/` | Turning the copy on and off by version: the second plan's. |
| `docs/parts/notifications-cpp.md` | The part page, including the shortcut and how to bind it. |
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

Fail-first tests for what can be tested off a desktop: the selection rule, the window inside a
group, the interaction state and its cancel rules, the Escape and Enter handlers and the walk to
the reply field (Qt Tests over the rules file), the version rule, the shortcut action on a
private session bus, and the directory guard with its configure. The timer pause and the focus
ring cannot be tested off a desktop: the timer pause has a session mode, and the ring has
screenshots only.

Private-session scenarios on the stock VM and on the ThinkPad, on the real Fusion copy rather
than the probe, in nine modes: `stock`, `copy`, `full`, `lock-idle`, `lock-focused`, `activate`,
`buttons`, `timer` and `eligible`. They must cover:

- **Eligibility:** critical and resident banners, a job popup, a banner in which a reply has
  started, and several banners at once, where only the newest eligible one is taken.
- **What the application is told:** Escape on a banner without actions that is not resident,
  normal and critical, tells it "expired" once; on one with actions that is not transient, a
  critical one among them, it is told nothing, and on a resident one it is told nothing too.
- **Keys inside the banner:** Escape from a control inside the banner and from the reply field;
  Return on a focused control and in the reply field; both Enter keys on the banner.
- **Timer:** the timeout stays paused while the banner is focused and resumes afterwards.
- **Ways the interaction ends:** a replacement, a close while focused, a move to a newer banner,
  the lock.

Not covered by them, and not claimed: a real active window with Dim Inactive enabled, with a
full-screen application in front, or with a different keyboard layout in that application; a
shortcut inhibitor on the copy; a transient banner with actions on Escape, which that path tells
"expired"; rule 13 outside an interaction, since the reply field is reached by the keyboard only
in the `buttons` mode; what the user finds after unlocking; the translation of the action's name;
and whether Return presses a control under the desktop's own platform theme.

Rule 12 is demonstrated by neither: it is the gate's, in the second plan, whose test must show
that at another Plasma version the stock plugin is the one mapped, after an update followed by a
plasmashell restart without a new login, and after a failed load.

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
- **Never:** focus on arrival, a default key binding in this slice or at any time one that
  overrides an existing one, dismissing or activating without focus, telling an application
  something about its notification that its own expiry path would not, weakening a check, or
  editing a generated file.

Complete means rules 1 to 11 and 13 are demonstrated on the Fusion copy on both machines, apart
from the cases the scenarios do not cover (listed above), rule 12 by the gate's test once the gate
exists, the checks above pass on the tested revision, the part page agrees with the code, and the
physical-keyboard run is recorded. No claim extends beyond the tested versions.

## Decisions accepted on 2026-11-26

The research report ended with eight questions for this specification. They were settled on
2026-11-26 as follows; the ninth and the tenth were added the same day.

1. **Shipping.** The Fusion-built copy of the stock plugin, with its packaging change.
2. **Finding the shortcut.** The standard shortcuts page and the part page document it. A later
   slice may add a hint.
3. **Escape from the banner's controls.** It dismisses from the buttons and keeps its current
   behaviour in the reply field. The implementation tested it first (the `buttons` mode).
4. **Enter with no default action.** Nothing, as a click does today. KDE Bug 405639 asks for the
   banner to close instead; that is not adopted.
5. **Held keys.** A key held across an activation is typed into the window that gets focus back.
   This is accepted as ordinary focus behaviour. Preventing it would need compositor support and
   is not in this slice.
6. **Eligibility and the timer.** Every visible notification banner except job popups and
   banners in which a reply has started, and the timer paused while focused. Critical and
   resident banners and the timer pause were not exercised by the probes; the `eligible` and
   `timer` modes are their cases.
7. **Default binding.** None in this slice. Fusion's profile already binds Meta+N to the
   notification view, and a later slice may propose a binding of its own.
8. **Older banners and dismiss-all.** Newest only. Stepping to an older banner and dismissing
   everything are later slices.
9. **Channels.** Fedora 44 first; the other channels follow afterwards.
10. **Where the version rule is enforced.** Before plasmashell picks its plugins, so that at
    another version the stock plugin loads. A guard inside the copy is kept as a second layer
    and does not replace that selection: on its own it would leave the copy in use with the
    feature off. A review remark on this specification showed that the second of the two
    enforcement points it first allowed could not deliver rule 12.

The implementation plan settled the build requirements of Fedora's specification, the source of
the stock tree (KDE's, at the version above) and the test suites. Left for the second plan: the
gate with its enforcement point and its test, a subpackage for each channel, and what System
Settings shows for the shortcut after the copy leaves. Because the notification service itself is
provided by this applet, a copy that fails to load leaves the session without any notification
widget until plasmashell starts again; so the plan must show that such a copy is not selected in
the first place (it is tried before plasmashell picks its plugins) or that the stock widget is
back within the same session. Proposing the change to KDE upstream is worth doing in parallel;
it is the owner's own action and not the delivery path. The second plan is specified in
[SPEC-notification-gate.md](SPEC-notification-gate.md), proposed on 2026-11-27.

## Proposed on 2026-11-27, to be accepted with the implementation

An independent review of this specification and of the two pull requests that build on it found
rules that said something the accepted code deliberately does not do, and cases nobody had ruled
on. The rules above now say what the code does; these are the choices behind that wording, each
to be accepted or changed by the owner.

11. **A replacement hands the keyboard back at once.** When a notification is replaced while its
    banner is taken, the interaction ends and the previous window is asked for at once. A key
    pressed right after lands in that window. This is accepted as the price of ending the
    interaction on a replacement, as the held key of decision 5 is.
12. **Any replacement counts**, also a re-send with identical content. An application that
    re-sends its notification every second makes the shortcut unusable on that notification: its
    banner would be taken and released again each second.
13. **A reply started in a taken banner.** A replacement then ends the interaction without asking
    for the previous window, so that typing goes on in the reply field. Escape from another
    control still dismisses the banner, and a draft left in the field goes with it. The
    alternative, no Escape while the banner holds reply text, was not taken: the close button of
    stock drops the draft as well.
14. **A critical banner without actions is told "expired"** by Escape, which its own timeout
    would never do, because it has none. It is the same dismissal as for any other banner.
15. **The record of the previous window survives a move to a newer banner.** When the shortcut is
    pressed again while a banner is taken and a newer one is eligible, the newer one is taken and
    the window from before the first press stays recorded. With nothing to ask for (the window is
    gone, or never was one), the banner stays the active window and takes no key; the widget does
    not guess a window.
16. **The keyboard focus reaching a banner's reply field starts the reply** whenever the copy is
    in force, also with the shortcut unassigned (rule 13).
17. **Enter acts only from the banner's content, and a control is pressed with Space** (rules 7
    and 8), as stock does in the private sessions. Whether Return presses a control under the
    desktop's own platform theme was not checked.

Source references: [capability map](CAPABILITY-MAP.md),
[architecture](docs/ARCHITECTURE.md), [login check](docs/parts/gate.md),
[compiled parts](docs/parts/navigation-cpp.md), [plan](docs/PLAN.md).
