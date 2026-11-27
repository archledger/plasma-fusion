<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Notification applet: private sessions

`scen-notifications.sh` runs Plasma's notification applet in an isolated session (`tools/vsession`)
and checks the built copy: that it behaves like the installed applet wherever the banner keyboard
triage is not at work, and what the triage does. It is test tooling, never installed, and must
never run against a logged-in desktop.

## Modes

`make-seed.sh` writes the mode into the session's HOME (`pf-notif/mode`):

| Mode | What it checks |
|---|---|
| `stock` | Plasma's installed applet. It has no "Focus notification banner" action, so the test chord moves no focus. Then stock behaviour: a banner without actions that times out tells the application, a click on a banner with a default action runs it once, a closed notification is told. |
| `copy` | The built copy, put in front of the stock plugin through `QT_PLUGIN_PATH`. Its "Focus notification banner" action is listed with the applet's shortcuts and ships unassigned, so the chord still moves no focus; the same stock checks follow. A difference between this mode and `stock` is the copy's doing. |
| `full` | The triage end to end (`SPEC-notification-triage.md`): with no banner the shortcut is ignored; a banner's arrival moves no focus; the shortcut gives the newest banner keyboard focus, and the focus ring is on the banner's frame and on none of its content (read off a screenshot); Escape dismisses it and KWrite is active again; a replacement while focused ends the interaction and gives the previous window its focus back, also when the replacement keeps the summary and the text, and also when that window is one of two windows of the same application; a click into KWrite ends the interaction without dismissing. |
| `lock-idle` | Before the lock the chord is shown to reach the applet: with no banner it is ignored. With the screen locked and no banner focused, the shortcut is not dispatched and a later Escape dismisses nothing. |
| `lock-focused` | With the screen locked while a banner is focused, the interaction ends and a later Escape dismisses nothing. |
| `activate` | Enter does what a click does, for a banner with a default action, one without, and one without but with the application's window open: the application is told the same. A held Return activates once. A resident banner stays after Enter and keeps the keyboard focus: a held Return acts once while it stays, each separate press acts again, the keypad's Enter acts as well, and Escape still dismisses. |
| `buttons` | Tab moves the keyboard focus from the banner's content to a control inside it and invokes nothing; Escape from a control dismisses; Space on the action's button is that button's own click; Return on a focused action button of a banner that also has a default action invokes nothing and is not taken as Enter on the banner, and in the reply field of such a banner Return sends the reply and is not taken as Enter either; with the reply open, Escape from the banner's close button dismisses; in the reply field itself Escape keeps the draft, which Return then sends; a replacement while a reply is being typed ends the interaction without asking for the previous window, and what is typed next arrives in the reply. |
| `timer` | A three-second banner is still shown four seconds after the shortcut gave it focus; once a click ends the interaction the timeout resumes and the banner expires. |
| `eligible` | Escape on a banner without actions, normal and critical, tells the application "expired" once. Critical and resident banners are taken and dismissed; a job popup and a banner whose reply is open are not; of two banners the newer one is named; the shortcut pressed again changes nothing; an application that leaves the bus is no replacement, so its banner stays taken and Escape still dismisses it; when the shortcut takes a newer banner while an older one is still taken, the window from before the first press is the one returned to; when the window recorded is gone, nothing is asked for: the banner stays the active window and takes no key; with the pointer on the banner the keyboard focus arrives at once; a banner closed while it has the keyboard focus, and one closed right after the request, restore nothing. |

## Build, seed, run

Build the part and install it to a stage first (`docs/parts/notifications-cpp.md`, "Build and
test"). Then, on the test device:

```sh
p=packages/notifications-cpp
for mode in stock copy full lock-idle lock-focused activate buttons timer eligible; do
    bash $p/tests/vsession/make-seed.sh build/notifications-stage "/var/tmp/pfv-notif-$mode-seed" notif "$mode"
done
```

`PFV_BASE` (default `/var/tmp`) must be where the session HOME will live, because `QT_PLUGIN_PATH`
names it literally. For each mode, copy that seed to the session's HOME and start the session:

```sh
mode=full
rm -rf "/var/tmp/pfv-notif" && mkdir -p "/var/tmp/pfv-notif"
cp -a "/var/tmp/pfv-notif-$mode-seed/." "/var/tmp/pfv-notif/home/"
bash tools/vsession/vsession.sh notif $p/tests/vsession/scen-notifications.sh 1440x900 200
```

The two lock modes need a lock-capable session: run them with `PFV_LOCK=1` in the environment.
Never type a password into that lock screen; the session ends locked.

Session names must be unique on the host. For the ThinkPad from the laptop, `tools/vsession/remote.sh`
takes the seed directory instead and fetches the results. In the Fedora 44 test container on a build
host, `tools/vsession/cvsession.sh` does the same with the seed as its third argument.

## What a run does

Every mode adds a panel with the notification applet and opens a document in KWrite, so that an
ordinary window has the keyboard focus. The triage modes then bind a test chord (Meta+Ctrl+Alt+PageDown)
to "Focus notification banner" the way a user would in System Settings, through the shortcut
daemon's D-Bus interface. Input is injected through KWin, and what the applet does is read from
its own reports (`banner triage "<step>"` in the shell log, through the applet's debug category),
from the receipts the test application (`sender.py`) gets over the notification interface, and
from the active window, which a KWin script prints. A report names a banner by its notification id
and an item by its type; none carries a summary or a draft. Each observation of KWin has a token
of its own, so a late answer cannot pass for a new one.

The test application can also send the other shapes of banner: one without a `desktop-entry`
hint, a critical or a resident one (hints), one with a reply action (the single action
`inline-reply`), and a job popup, which it makes through the job-view server that the applet
itself owns on the session bus. Where a case needs an application that leaves the bus, a second
instance of it is started (`sender-2.log` holds its receipts).

Windows are acted on through KWin's own scripting where the pointer would be in the way: by the
first characters of a window's caption, a window is made active or closed.

`ring.py` reads a screenshot with the standard library only and says whether the focus colour is
on the frame of the banner's window, one pixel in from each of its four sides, and on no pixel of
the window's content. The applet reports the window's place and size, its padding and the focus
colour when the ring appears (`ring-geometry`).

Three things were learned about stock here and are written into the scenarios:

- The controls inside a banner are pressed with Space. In the copy, Return does nothing on a
  focused button and is not taken as a click on the banner (the `buttons` mode); on the installed
  applet it was not pressed.
- A banner whose only action is a reply shows the reply field itself, not a button; the keyboard
  focus reaching that field starts the reply, as a click does.
- Stock resumes a banner's timeout when the pointer leaves it in small steps. This harness moves
  the pointer in one jump, and that does not deliver the leave, so a banner the pointer has rested
  on keeps its timeout paused for the rest of the run. The `timer` mode keeps the pointer off the
  banner.

## What a run does not show

- That a dismissed notification is in the history. The history lives in the applet's memory and
  cannot be read from outside; the scenarios check what it implies (the banner is gone and the
  application is told nothing, where a close would have told it) and keep screenshots.
- The screen while it is locked, beyond what the applet reports: KWin does not deliver the
  shortcut, and no step is logged.
- An inhibitor of keyboard shortcuts held by the focused window. The probes covered it on the
  stock VM and on the ThinkPad; its helper was not carried into this repository.
- A real active window in every respect: none of the cases has Dim Inactive enabled, a
  full-screen application in front of the window, or another keyboard layout in it.
- A request that KWin does not grant within 1.5 seconds, and a replacement that arrives while the
  request is still pending. The case of a banner closed right after the request runs the close
  before or after the grant as the run goes, and asserts only what holds either way.
- What the user finds after unlocking: the harness never unlocks a session.
- The physical keyboard, the live desktop and real applications.

## Reading a run

The session's `out/` directory holds `checks.txt` (one `PASS` or `FAIL` line per check),
`scenario.log` (the checks again, a line with the counts, then `scenario rc=0` and `session
rc=0`), `teardown.log` (`left: none`), `mapped-applet.txt`, `packages.txt`,
`active-windows.txt`, `sender.log` with every receipt, and the screenshots. A mode passes only when the scenario and the session returned zero, teardown left
no process, and every line of `checks.txt` is `PASS`. A step that must succeed stops its mode when
it fails: the checks after it could mean nothing. Keep the `out/` directory with the applet's
identity and the package versions as the record of the run.
