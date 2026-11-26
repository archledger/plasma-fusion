<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Notification applet copy

`packages/notifications-cpp` is Plasma's own notification applet, built by Plasma Fusion from the
upstream source of one Plasma version. Its origin is recorded in
`packages/notifications-cpp/README.md`. The behaviour it is meant to add, the banner keyboard
triage, is specified in `SPEC-notification-triage.md`.

Status: **built and tested, not packaged and not enabled on any machine.** Standing in for the
stock plugin needs a version gate that runs before plasmashell picks its plugins. Until that
exists, nothing puts the copy in front of the stock plugin.

## What it is

- The plugin `org.kde.plasma.notifications`, with the stock metadata. Plasma takes an applet's id
  from its file name when the metadata does not state one, as the stock metadata does not, so only
  this name lets the copy stand in for the stock applet.
- Installed under `libexec/plasma-fusion/qt6/plugins/plasma/applets/`, a directory Plasma Fusion
  owns. The build stops unless `PF_NOTIFICATIONS_PLUGIN_DIR` is an absolute path that, symbolic
  links resolved, is neither Qt's own plugin directory nor inside it
  (`cmake/PluginDirGuard.cmake`), and the directory the plugin itself lands in must be neither
  inside Qt's nor the stock plugin's own, wherever a link to it leads: landing on the stock
  plugin's file would replace it. A relative value would be installed against the installation
  prefix, where it may be Qt's directory, a link reaches the same directory under another name,
  and a link at the plugin's own path would be installed through.
- A `built-against` record with `plasma-workspace=6.8.3` and the Qt version of the build, beside
  the records of the other compiled parts.
- The banner keyboard triage of `SPEC-notification-triage.md`, added to the stock applet in
  marked changes (below). Nothing else about the applet changes.

## Version rule

The copy may stand in for the stock plugin only while the installed `plasma-workspace` version is
exactly the one it was built from. `PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION` in the package's
`CMakeLists.txt` names that version; it is written into the plugin and into its record. This
package does not enforce the rule. The build's minimum versions are floors, not exact pins: a
newer Plasma in the build root must not fail the build, because the gate, not the build, decides
whether the copy is used. The floors are those of the stock source's own build, Qt 6.11 and
Frameworks 6.30 (plasma-workspace v6.8.3, `CMakeLists.txt`): what a system needs to build it at
all.

## Banner keyboard triage

The copy carries the banner keyboard triage of `SPEC-notification-triage.md`:

- **One shortcut, "Focus notification banner"**, listed with the applet's other shortcuts and
  unassigned until the user binds it. It exists only while the running Plasma is the one this copy
  was built from (the version rule above); at any other version the stock shortcuts are all there
  is.
- **The newest visible banner that may be taken** gets keyboard focus when the shortcut is
  pressed: never a job popup, never a banner that is handling a reply. Arrival still moves no
  focus. A focus ring in the theme's focus colour shows while the banner holds keyboard focus, and
  the banner's timeout is paused for that time, as it is while the pointer rests on it.
- **Escape** on that banner dismisses it through its own expiry, so the notification stays in the
  history, and the window that was active before the shortcut is active again. **Enter** does what
  a click does: the default action if there is one, otherwise nothing, once per press, and only
  while the banner's content itself has the keyboard focus. With a button or the reply field
  focused, the keys are theirs: a button is pressed with Space, as in stock, and in the reply
  field Escape keeps the text and Return sends it. From every other control of the banner, the
  close button included, Escape dismisses. The keyboard focus reaching the reply field starts the
  reply, as a click on it does.
- **The interaction ends by itself** when the banner is replaced, is closed or loses focus, or
  when the screen locks. Nothing is dismissed then and no other banner is taken; only a
  replacement that ends a focused interaction asks for the previous window back. A replacement is
  seen by the update time, which KDE resets on every replacement, and by the text and the
  actions; the window asked for is a window itself, also when it is one of several windows of an
  application (a group of windows cannot be activated).

The decisions are in one file, `src/global/BannerTriage.js`, as pure functions; the stock QML
(`src/global/Globals.qml`, `src/NotificationPopup.qml`) only applies them, and the reply field
(`src/components/NotificationReplyField.qml`) carries one property that marks it. The applet
reports each step through its debug category (`org.kde.plasma.notifications.debug`) as
`banner triage "<step>"`: `triage-available`, `shortcut-ignored-no-banner`, `focus-requested`,
`focus-granted`, `focus-within inside=... <item>` (each move of the keyboard focus inside the
banner), `dismissed-by-escape`, `activated-by-enter`, `focus-restore-requested` (the applet asked
KWin to activate the window recorded at the request; KWin decides), `focus-restore-skipped`,
`ended lost`, `ended hidden`, `ended replaced` and `ended not-granted`. A report names a banner by
its notification id and an item by its type; none carries a summary or a draft.
The private-session scenarios read these lines.

KWin owns the lock and inhibitor boundary, and the applet adds no check of its own: a locked
screen or a shortcut inhibitor keeps the shortcut from being dispatched, as for any global
shortcut.

## Build and test

The build requirements are the applet's own, read from `packaging/fedora/plasma-fusion.spec` by
`dnf builddep`. To do what the `compiled` workflow does, in a `fedora:44` container:

```sh
dnf install -y git dnf-plugins-core rpm-build ninja-build gcc-c++ dbus-daemon nodejs python3-gobject kf6-kconfig systemd
dnf builddep -y packaging/fedora/plasma-fusion.spec
cmake -S packages/notifications-cpp -B build/notifications -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=ON
cmake --build build/notifications
tools/tests/ctest-required.sh packages/notifications-cpp build/notifications
ctest --test-dir build/notifications --output-on-failure
```

`notifications-plugin` loads the built plugin and checks that it is the stock applet under its own
name: it loads, it provides `org.kde.plasma.notifications`, and its file name is the stock
plugin's. `notifications-plugin-dir-guard` is the directory guard's unit test: on a tree of
directories and symbolic links, 21 cases, each refused or allowed with the expected words; it
needs no compiler and no packages. Three Qt Tests cover the code that is not QML:

| Test | What it runs |
|---|---|
| `notifications-triage-rules` | `tests/triagetest.cpp`: the rules of `BannerTriage.js` through a small QML holder, offscreen: choosing the banner (7 cases), the window that had the keyboard focus inside a group of windows (9), the transitions between idle, requested and active (14), Escape (5) and Enter (6); and on real items, whether the item that has the keyboard focus is in the reply field |
| `notifications-triage-version` | `tests/versiontest.cpp`: the version rule, versions in and a decision out |
| `notifications-triage-shortcut` | `tests/shortcuttest.cpp`: `GlobalShortcuts` itself; the focus action exists at the built-from version and at no other. It runs through `tests/run-shortcut-test.sh` on a private session bus: the class registers its actions with the global shortcut daemon under the shell's component name, so on the bus of a real desktop the test would reach the desktop's own shortcuts. |

The tests are configured with the package (`BUILD_TESTING=ON`); the packages are built
with them off. `notifications-triage-shortcut` needs `dbus-run-session` and is left out without
it; `tools/tests/ctest-required.sh` then fails the build, as for the settings module's tests.

To see where the plugin would be installed:

```sh
DESTDIR="$PWD/build/notifications-stage" cmake --install build/notifications
find build/notifications-stage -type f
```

The plugin lands under `libexec/plasma-fusion/qt6/plugins/plasma/applets/` and its record
under `share/plasma-fusion/built-against/notifications`. Nothing is installed into a plugin
directory of Qt's own.

## Private session

`tests/vsession/scen-notifications.sh` runs the applet in an isolated session in nine modes
(`tests/vsession/README.md`): `stock` and `copy`, the control, and seven for the banner keyboard
triage. The control runs Plasma's installed applet and the built copy through the same checks of
stock behaviour, so a difference between them is the copy's doing. The applet plasmashell mapped
is recorded in every mode: the installed one in `stock`, the staged plugin by SHA-256 otherwise.

Run on 2026-11-26 on the stock VM and on the ThinkPad, and in the Fedora 44 test container on
the build host, each mode with `scenario rc=0`, `session rc=0` and `left: none`, and every check
a `PASS`. The numbers are the checks each mode passed, the same on all three:

| Mode | Checks | What it showed |
|---|---|---|
| `stock` | 19 | The installed applet has no "Focus notification banner" action; the test chord moves no focus; a banner without actions that times out and a closed notification tell the application, a click runs a default action once. |
| `copy` | 21 | The copy lists the action, unassigned; the chord moves no focus; the same stock behaviour as `stock`. |
| `full` | 52 | With no banner the shortcut is ignored. Arrival moves no focus. The shortcut gives a banner keyboard focus; Escape dismisses it, KWrite is active again and the application is told nothing. A replacement while focused ends the interaction, asks for the previous window and is not taken: also when it keeps the summary and the text, and also when the previous window is one of two windows of one application. A click into KWrite ends the interaction; a later Escape in KWrite dismisses nothing and the banner can still be closed by the application. |
| `lock-idle` | 12 | Locked with no banner focused: the shortcut is not dispatched, and a later Escape dismisses nothing. |
| `lock-focused` | 11 | Locked while a banner is focused: the interaction ends, and a later Escape dismisses nothing. |
| `activate` | 52 | Enter gives the application the same two receipts as a click for a banner with a default action; for one without, and for one without but with the application's window open, both leave it told nothing and the banner where it is. A held Return activates once. A resident banner stays after Enter; a second, separate Enter acts again, and Escape still dismisses it. |
| `buttons` | 34 | Tab lands inside the banner and invokes nothing; Escape from a control dismisses; Space on the action's button invokes exactly that action and is not taken as Enter on the banner; with the reply open, Escape from the banner's close button dismisses; in the reply field Escape keeps the draft and Return sends it. |
| `timer` | 15 | A three-second banner is still focused four seconds after the shortcut took it; the shortcut again asks for nothing; after a click ends the interaction the timeout resumes and the banner expires, the application told nothing. |
| `eligible` | 55 | Critical and resident banners are taken and dismissed by Escape. A job popup and a banner whose reply is open are not taken, and KWrite stays active. Of two banners the newer one is named by its id. The shortcut again asks for no second focus, and a replacement still gives KWrite its focus back. With the pointer on the banner the keyboard focus arrives at once. A banner closed right after the request restores nothing. |

No shell log held a script error in any mode.

| Machine | KWin | Plasma Workspace | The applet plasmashell mapped in the copy's modes |
|---|---|---|---|
| Stock VM (a throwaway overlay of the provisioned image) | `6.8.3-1.fc44` | `6.8.3-1.fc44` | the staged plugin, by SHA-256 |
| ThinkPad | `6.8.3-1.fc44.pf1` | `6.8.3-1.fc44` | the staged plugin, by SHA-256 |
| Fedora 44 test container on the build host | `6.8.3-1.fc44` | `6.8.3-1.fc44` | the staged plugin, by SHA-256 |

The runs on the VM and on the ThinkPad are recorded in the shared ledger under
`2026-11-26-notification-triage-spec/evidence/part-b-review-fixes/`, each with the kit's
checksums; the earlier runs, before the review fixes, are under `evidence/part-b/`. The
container's runs are kept as the table of one sweep of all nine modes.

## What is not covered

- No package installs the copy, and no setup step enables it.
- The enforcement point of the version rule is not written.
- The `compiled` and `sanitizers` workflows build and test the part without installing it.
- The runs on the stock VM were made on the same hardware as the container ones (both on the build
  host, under KVM), with stock KWin; the ThinkPad with the fork KWin is the one run on other
  hardware.
- A keyboard-shortcut inhibitor held by the focused window is not in the scenarios. The earlier
  probes showed on both machines that the shortcut is not dispatched then; the widget adds no
  check of its own.
- That a dismissed notification is in the history is not read: the history is in the applet's
  memory. The scenarios check what it implies and keep screenshots.
- The private sessions used injected input and a synthetic sender. The physical keyboard, the
  live desktop and real applications were not exercised.
