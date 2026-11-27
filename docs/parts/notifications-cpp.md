<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Notification applet copy

`packages/notifications-cpp` is Plasma's own notification applet, built by Plasma Fusion from the
upstream source of one Plasma version. Its origin is recorded in
`packages/notifications-cpp/README.md`. The behaviour it is meant to add, the banner keyboard
triage, is specified in `SPEC-notification-triage.md`.

The Fedora build produces a separate `plasma-fusion-notifications` RPM. Neither profile pulls it
in. On Fedora, install it at the same version and release as `plasma-fusion`, then run
`plasma-fusion setup` in your session. The next systemd-managed start checks whether the copy can
be used. In **System Settings → Keyboard → Shortcuts**, search for **Focus notification banner**
and assign a key. It has no default binding. Arch, Debian and Nix do not ship the copy.

The RPM does not pin Plasma Workspace. It still has Fedora's generated library dependencies;
if a Qt upgrade cannot satisfy the applet's private Qt ABI, rebuild the optional RPM or remove
it so the update can proceed. The startup gate does not affect package resolution.

## What it is

- The plugin `org.kde.plasma.notifications`, with the stock metadata. Plasma takes an applet's id
  from its file name when the metadata does not state one, as the stock metadata does not, so only
  this name lets the copy stand in for the stock applet.
- Installed by default under `<prefix>/lib64/libexec/plasma-fusion/qt6/plugins/plasma/applets/`
  on Fedora, a directory Plasma Fusion owns. The build stops unless `PF_NOTIFICATIONS_PLUGIN_DIR`
  is an absolute path that, symbolic links resolved, is neither Qt's own plugin directory nor
  inside it, nor KDE's own when that is another directory (`cmake/PluginDirGuard.cmake`); the
  directory the plugin itself lands in must be neither inside them nor the stock plugin's own,
  wherever a link to it leads, since landing on the stock plugin's file would replace it. A value
  is refused that would be installed against the installation prefix (a relative one, where it may
  be Qt's directory), that a link brings to the same directory under another name, or that holds a
  character CMake reads with a meaning of its own (a generator expression, a backslash, a leading
  `~`), because `install()` would take it differently from a path check. The build installs to the
  directory the guard resolved, so the string checked is the string installed. A link at the
  plugin's own path is refused too: the install would replace the link with the copy. The
  directory is absolute, so `cmake --install --prefix` does not move the plugin; `DESTDIR` works.
- A `built-against` record naming the Plasma version of the source (`6.8.3`), the Plasma version
  the build found and the Qt version, beside the records of the other compiled parts.
- The banner keyboard triage of `SPEC-notification-triage.md`, added to the stock applet in
  marked changes (below). Nothing else about the applet changes.

## Version rule

The copy may stand in for the stock plugin only while the installed `plasma-workspace` version is
exactly the one it was built from. `PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION` in the package's
`CMakeLists.txt` names that version; it is written into the plugin, and the record names it
beside the Plasma version the build found: a copy of one version's source compiled against
another version's libraries is not to be used either. The startup gate checks both versions,
the effective Fusion theme, and the applet's ability to load before an individual managed
plasmashell launch. See [the gate](gate.md#commands). The plugin also has its own rule: the
focus shortcut exists only while
the running Plasma is the version the copy was built from (`src/bannertriageversion.h`). That
rule keeps the feature off at another version. On its own it would leave the copy in use with the
feature off, so it does not replace the gate. The build's minimum versions are floors, not exact
pins: a newer Plasma in the build root must not fail the build, because the gate, not the build,
decides whether the copy is used. The floors are those of the stock source's own build, Qt 6.11
and Frameworks 6.30 (plasma-workspace v6.8.3, `CMakeLists.txt`): what a system needs to build it
at all.

## Banner keyboard triage

The copy carries the banner keyboard triage of `SPEC-notification-triage.md`:

- **One shortcut, "Focus notification banner"**, listed with the applet's other shortcuts and
  unassigned until the user binds it. It exists only while the running Plasma is the one this copy
  was built from (the version rule above); at any other version the stock shortcuts are all there
  is.
- **The newest visible banner that may be taken** gets keyboard focus when the shortcut is
  pressed: never a job popup, never a banner that is handling a reply. Arrival still moves no
  focus. A focus ring in the theme's focus colour is drawn around the banner, on the frame of its
  window, while the banner holds keyboard focus, and the banner's timeout is paused for that
  time, as it is while the pointer rests on it. The banner gets the keyboard focus also when it
  already accepts it, because the pointer rests on one it has clicked, and another window is
  active: KWin makes a Plasma window active when it changes to accepting keyboard focus, and
  only then, so for such a request the window is made to accept it a second time.
- **Escape** on that banner dismisses it through its own expiry, so the notification stays in the
  history, and the window that was active before the shortcut is active again. **Enter** does what
  a click does: the default action if there is one, otherwise nothing, once per press, and only
  while the banner's content itself has the keyboard focus. With a button or the reply field
  focused, the keys are theirs: a button is pressed with Space, as in stock, and in the reply
  field Escape keeps the text and Return sends it. From the banner's other controls, the close
  button included, Escape dismisses; on the Send button of the reply it keeps its stock
  behaviour, as it does in the field. The keyboard focus reaching the reply field starts the
  reply, as a click on it does.
- **The interaction ends by itself** when the banner is replaced, is closed or loses focus, or
  when the screen locks. Nothing is dismissed then and no other banner is taken. Only a
  replacement that ends a focused interaction in which no reply was started asks for the previous
  window back; with a reply started, the keyboard stays with the banner. A replacement is seen by
  the update time, which KDE resets on every replacement, and by the text, not by the actions:
  KDE clears those when the application leaves the bus, and that is no replacement. The window
  asked for is the window that had the keyboard focus at the request, a window itself, also when
  it is one of several windows of an application (a group of windows cannot be activated). It is
  still found after the task model has moved it meanwhile, into a group or out of one. When
  the shortcut takes a newer banner while an older one is still taken, the window from before the
  first press stays the one recorded. When there is nothing to ask for, because that window is
  gone or never was one, the banner stays the active window and takes no key: the widget does not
  guess a window.

The decisions are in one file, `src/global/BannerTriage.js`, as functions of plain values: which
banner may be taken, which window is recorded and where it is when it is asked for, how the
interaction moves between its states, what makes a banner the same notification, and what Escape
and Enter do. The stock QML (`src/global/Globals.qml`, `src/NotificationPopup.qml`) only applies
them. The window that had the keyboard focus is the task model's own `activeTask`, recorded by
the ids the model knows it by (`WinIdList`) and looked up when it is asked for: while a banner is
taken the model may move the window, into a group when its application opens a second window, or
out of one when the other window closes, and an index would then name the group, which cannot be
activated, or nothing at all. The reply field (`src/components/NotificationReplyField.qml`)
carries one property that marks it and the handler that starts the reply when the keyboard focus
reaches the field. The applet reports each step through its debug category
(`org.kde.plasma.notifications.debug`) as `banner triage "<step>"`: `triage-available`,
`shortcut-ignored-no-banner`, `focus-requested`, `focus-granted`, `focus-within inside=... <item>`
(each move of the keyboard focus inside the banner), `dismissed-by-escape`, `activated-by-enter`,
`ring-geometry <x> <y> <width> <height> <padding ...> <colour>` (where the banner's window is
drawn, in the pixels of the screen, when the ring appears), `focus-restore-requested` (the applet
asked KWin to activate the window recorded at the request; KWin decides), `focus-restore-skipped`,
`ended lost`, `ended hidden`, `ended replaced` and `ended not-granted`. A report names a banner by
its notification id and an item by its type; none carries a summary or a draft. The
private-session scenarios read these lines.

Two of these changes are not behind the version rule. Wherever the copy is in force, at any Plasma
version and also with the shortcut unassigned, the reply field starts the reply when the keyboard
focus reaches it (rule 13 of the specification), and each move of the keyboard focus is reported.
The version rule keeps the shortcut off at another version; it does not turn the copy back into
stock.

To give the shortcut a key, as a user would: in System Settings, in the Keyboard Shortcuts page,
search for "Focus notification banner" and assign it a key combination. It ships unassigned, and
Fusion's own bindings, Meta+N for the notification view among them, are not touched. The private
sessions bind their test chord through the shortcut daemon's D-Bus interface, which is where
System Settings writes a binding too.

If the gate falls back to stock, KDE may still show the saved shortcut in System Settings.
Pressing it under stock does not focus or dismiss a banner. Fusion leaves the saved binding
alone, and it works again once the copy is loaded.

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
name: it loads, it provides `org.kde.plasma.notifications`, its file name is the stock plugin's,
and its QML is in its resources. The standalone `plasma-fusion-notifications-check ABSOLUTE_PLUGIN`
performs the load, identity and resource checks without creating the applet or instantiating its
QML. `notifications-plugin-check-cli` tests its exit status with the built applet, missing and
unloadable files, a renamed real applet, and invalid arguments. The checker is staged with the
component and installed by the optional Fedora RPM.

`notifications-plugin-dir-guard` is the directory guard's unit test, 53 cases: 38 on a tree of
directories and symbolic links, among them a system with a merged
`/usr`, links to links and the spellings `install()` would take differently; and 15 through the
wrapper's own lines, which it reads from `CMakeLists.txt` and configures in a small project
without a compiler, typed in the ways a cache variable can be, to read the destination from the
generated install script and to see that an allowed copy leaves the stand-in for the stock plugin
untouched. It needs no compiler and no packages. Three Qt Tests cover the code that is not QML:

| Test | What it runs |
|---|---|
| `notifications-triage-rules` | `tests/triagetest.cpp`: the rules of `BannerTriage.js` through a small QML holder, offscreen, 61 cases: choosing the banner (7), the window to record when the shortcut is pressed, also while a taken banner is the active window (7), the transitions between idle, requested and active (16), what makes a banner the same notification (7), where a recorded window is when it is asked for, in a group or out of one (9), which banners may be taken (4), Escape (5) and Enter (6); and on real items, whether the item that has the keyboard focus is in the reply field |
| `notifications-triage-version` | `tests/versiontest.cpp`: the version rule, 13 versions in and a decision out, among them a longer number that begins with the built version, a fourth part, a distribution's release and a leading `v`; the rows are built from the version of the build |
| `notifications-triage-shortcut` | `tests/shortcuttest.cpp`: `GlobalShortcuts` itself; the focus action exists at the built-from version, with no key, and at no other, and the two stock actions in both cases. It runs only through `tests/run-shortcut-test.sh`, on the private session bus that driver makes, and refuses any other: the class registers its actions with the global shortcut daemon under the shell's component name, so on the bus of a real desktop the test would reach the desktop's own shortcuts. |

The tests are configured with the package (`BUILD_TESTING=ON`); the packages are built
with them off. `notifications-triage-shortcut` needs `dbus-run-session` and is left out without
it; `tools/tests/ctest-required.sh` then fails the build, as for the settings module's tests.

To see where the plugin would be installed:

```sh
DESTDIR="$PWD/build/notifications-stage" cmake --install build/notifications
find build/notifications-stage -type f
```

The plugin lands under `lib64/libexec/plasma-fusion/qt6/plugins/plasma/applets/` on Fedora, and
its record under `share/plasma-fusion/built-against/notifications`. Nothing is installed into a
plugin directory of Qt's own.

## Private session

`tests/vsession/scen-notifications.sh` runs the applet in an isolated session in nine modes
(`tests/vsession/README.md`): `stock` and `copy`, the control, and seven for the banner keyboard
triage. The control runs Plasma's installed applet and the built copy through the same checks of
stock behaviour, so a difference between them is the copy's doing. The applet plasmashell mapped
is recorded in every mode: the installed one in `stock`, the staged plugin by SHA-256 otherwise.

Run on 2026-11-27 in the Fedora 44 test container on the build host, on the stock VM and on the
ThinkPad, at `db2fd53`, the last commit of this change that touches the applet, with one kit: each mode
with `scenario rc=0`, `session rc=0` and `left: none`, and every check a `PASS`. The numbers are
the checks each mode passed, the same in all three places:

| Mode | Checks | What it showed |
|---|---|---|
| `stock` | 20 | The applet plasmashell maps is the installed one: exactly one file, under `/usr`, owned by a package of plasma-workspace. It has no "Focus notification banner" action; the test chord moves no focus; a banner without actions that times out and a closed notification tell the application, a click runs a default action once. |
| `copy` | 22 | The copy lists the action, and it ships unassigned, as the daemon's empty reply shows; the chord moves no focus; the same stock behaviour as `stock`. |
| `full` | 54 | With no banner the shortcut is ignored. Arrival moves no focus. The shortcut gives a banner keyboard focus, and the focus ring is on the frame of the banner's window and on none of its content; Escape dismisses it, KWrite is active again and the application is told nothing. A replacement while focused ends the interaction, asks for the previous window and is not taken: also when it keeps the summary and the text, and also when the previous window is one of two windows of one application. A click into KWrite ends the interaction; a later Escape in KWrite dismisses nothing and the banner can still be closed by the application. |
| `lock-idle` | 15 | Before the lock the chord reaches the applet, which ignores it with no banner. Locked with no banner focused: the shortcut is not dispatched, and a later Escape dismisses nothing. |
| `lock-focused` | 12 | Locked while a banner is focused: the interaction ends, and a later Escape dismisses nothing. |
| `activate` | 55 | Enter gives the application the same two receipts as a click for a banner with a default action; for one without, and for one without but with the application's window open, both leave it told nothing and the banner where it is. A held Return activates once. A resident banner stays after Enter and keeps the keyboard focus: a held Return acts once while it stays, a second, separate Return acts again, the keypad's Enter acts as well, and Escape still dismisses it. |
| `buttons` | 57 | Tab moves the keyboard focus from the content to a control inside the banner and invokes nothing; Escape from a control dismisses; Space on the action's button invokes exactly that action. Return on a focused action button of a banner that also has a default action invokes nothing and is not taken as Enter on the banner; in the reply field of such a banner Return sends the reply and is not taken as Enter either. With the reply open, Escape from the banner's close button dismisses; in the reply field Escape keeps the draft and Return sends it. A replacement while a reply is being typed ends the interaction without asking for the previous window, and what is typed next arrives in the reply. |
| `timer` | 16 | A three-second banner is still focused four seconds after the shortcut took it; the shortcut again asks for nothing; after a click ends the interaction the timeout resumes and the banner expires, the application told nothing. |
| `eligible` | 126 | Escape on a banner without actions, normal and critical, tells the application "expired" once. Critical and resident banners are taken and dismissed by Escape. A job popup and a banner whose reply is open are not taken, and KWrite stays active. Of two banners the newer one is named by its id. The shortcut again asks for no second focus, and a replacement still gives KWrite its focus back. An application that leaves the bus is no replacement: its banner stays taken and Escape still dismisses it. When the shortcut takes a newer banner while an older one is still taken, the window from before the first press is the one returned to; when that window is gone, nothing is asked for, the banner stays the active window and takes no key. While a banner is taken, the other window of the recorded window's group closes: the recorded window is still the one asked for, and it is active again. With the pointer on the banner the keyboard focus arrives at once. A banner that already accepts keyboard focus, because the pointer rests on one it has clicked, is given it by the shortcut while another window is active. A banner closed while focused, and one closed right after the request, restore nothing. |

Every mode ends with one check that the shell log holds no script error.

| Machine | KWin | Plasma Workspace | The applet plasmashell mapped in the copy's modes |
|---|---|---|---|
| Stock VM (a throwaway overlay of the provisioned image) | `6.8.3-1.fc44` | `6.8.3-1.fc44` | the staged plugin, by SHA-256 |
| ThinkPad | `6.8.3-1.fc44.pf1` | `6.8.3-1.fc44` | the staged plugin, by SHA-256 |
| Fedora 44 test container on the build host | `6.8.3-1.fc44` | `6.8.3-1.fc44` | the staged plugin, by SHA-256 |

The runs are recorded in the shared ledger under
`2026-11-26-notification-triage-spec/evidence/part-c-after-automated-review-20261127/`, each with
the kit's checksums, with the sanitizer job on the same commit and with sixteen mutants, each
caught by the check meant for it. The case of the closing group was watched red first, on the
build of the commit before the fix, which is kept beside them. The ThinkPad's desktop processes
were the same before its run and after the cleanup.

One change to the scenario came after that commit: the `stock` mode requires the applet plasmashell
maps to be owned by a package of plasma-workspace, where it had accepted a package query that
named nothing. With it that mode ran once more in the three places: the same 20 checks, every one
a `PASS`, kept in `stock-owner-check/` with the run that fails at that check when a package that
owns nothing is expected. The runs before the review fixes are under
`evidence/part-b/` and `evidence/part-b-review-fixes/`; those of the code with the review fixes,
before the automated reviews of it, under `evidence/part-b-after-review-20261127/`.

While this change was being made, two cases of the `eligible` mode failed once each, in the first
runs of their kind and on builds since shown to be the committed code: after the shortcut took a
newer banner while an older one was still taken, a replacement of the newer one did not ask for
the recorded window; and an application's leaving the bus was taken for a replacement. Neither
recurred: up to the ThinkPad's run of `611a8f2` the first case had passed in 37 later runs of the
mode and the second in 25, each in 45 repetitions of its steps in a stress scenario, and both
passed in every run of the mode made since. Among the earlier runs were six made with the host
under heavy load, fresh builds running beside the sessions, and others with diagnostic reports in
the applet. The outputs of the two failing runs were not kept, and the cause was not found.

## What is not covered

- The optional Fedora package does not install or configure the copy on other distributions.
- A direct plasmashell start does not use the startup gate.
- The `compiled` and `sanitizers` workflows build and test the part without installing it.
- The runs on the stock VM were made on the same hardware as the container ones (both on the build
  host, under KVM), with stock KWin; the ThinkPad with the fork KWin is the one run on other
  hardware.
- A keyboard-shortcut inhibitor held by the focused window is not in the scenarios. The earlier
  probes showed on both machines that the shortcut is not dispatched then; the widget adds no
  check of its own.
- That a dismissed notification is in the history is not read: the history is in the applet's
  memory. The scenarios check what it implies and keep screenshots.
- A real active window in every respect: no case runs with Dim Inactive enabled, with a full-screen
  application in front of the window that had the keyboard focus, or with another keyboard layout
  in that window.
- A request that KWin does not grant within 1.5 seconds, and a replacement that arrives while the
  request is still pending. The case of a banner closed right after the request closes it before
  or after the grant as the run goes, and asserts what holds either way.
- The window that had the keyboard focus when it is not a task (a window that skips the taskbar,
  the desktop): nothing is recorded then, and after a replacement the banner stays the active
  window.
- A second window of the recorded window's application appearing while a banner is taken. KWin
  activates every window that appears under its default setting, and that ends the interaction as
  a lost focus. That the window is then found inside its group is in the unit tests of the rules,
  and the `full` mode asks for a window that is inside a group.
- What the user finds after unlocking: the harness never unlocks a session.
- Whether Return presses a control under a desktop's own platform theme; the private sessions
  have the style of the test image. On the installed applet, Return was not pressed on a focused
  control.
- The name of the shortcut in any language but English: the package has no catalogue step.
- The Plasma Fusion lines of the three upstream QML files that carry them (`Globals.qml`,
  `NotificationPopup.qml`, `NotificationReplyField.qml`) are outside the four QML checks, which
  skip every file listed in `UPSTREAM-FILES`. With the three unlisted, on 2026-11-27, the checks
  found one line, KDE's own.
- The private sessions used injected input and a synthetic sender. The physical keyboard, the
  live desktop and real applications were not exercised.
