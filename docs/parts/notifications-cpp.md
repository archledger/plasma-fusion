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
  a click does: the default action if there is one, otherwise nothing, once per press. In the
  reply field Escape keeps its stock behaviour.
- **The interaction ends by itself** when the banner is replaced, is closed or loses focus, or
  when the screen locks. Nothing is dismissed then and no other banner is taken; only a
  replacement that ends a focused interaction gives the previous window its focus back.

The decisions are in one file, `src/global/BannerTriage.js`, as pure functions; the stock QML
(`src/global/Globals.qml`, `src/NotificationPopup.qml`) only applies them. The applet reports
each step through its debug category (`org.kde.plasma.notifications.debug`) as
`banner triage "<step>"`: `triage-available`, `shortcut-ignored-no-banner`, `focus-requested`,
`focus-granted`, `dismissed-by-escape`, `activated-by-enter`, `focus-restored`,
`focus-restore-skipped`, `ended lost`, `ended hidden`, `ended replaced` and `ended not-granted`.
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
| `notifications-triage-rules` | `tests/triagetest.cpp`: the rules of `BannerTriage.js` through a small QML holder, offscreen: choosing the banner (7 cases), the transitions between idle, requested and active (14), Escape (5) and Enter (5) |
| `notifications-triage-version` | `tests/versiontest.cpp`: the version rule, versions in and a decision out |
| `notifications-triage-shortcut` | `tests/shortcuttest.cpp`: `GlobalShortcuts` itself; the focus action exists at the built-from version and at no other |

The tests are configured with the package (`BUILD_TESTING=ON`); the packages are built
with them off.

To see where the plugin would be installed:

```sh
DESTDIR="$PWD/build/notifications-stage" cmake --install build/notifications
find build/notifications-stage -type f
```

The plugin lands under `libexec/plasma-fusion/qt6/plugins/plasma/applets/` and its record
under `share/plasma-fusion/built-against/notifications`. Nothing is installed into a plugin
directory of Qt's own.

## Private session

`tests/vsession/scen-notifications.sh` runs the applet in an isolated session twice: once with
Plasma's installed applet (`stock`) and once with the built copy put in front of it through
`QT_PLUGIN_PATH` (`copy`). Both modes run the same checks, so a difference between them is the
copy's doing. `tests/vsession/README.md` has the commands.

Demonstrated on 2026-11-26, each mode with `scenario rc=0`, `session rc=0` and `left: none`, and
every check a `PASS`:

| Machine | `stock` | `copy` |
|---|---|---|
| Stock VM: KWin and Plasma Workspace `6.8.3-1.fc44` | 6 checks | 7 checks |
| ThinkPad: KWin `6.8.3-1.fc44.pf1`, Plasma Workspace `6.8.3-1.fc44` | 6 checks | 7 checks |

In both `copy` sessions plasmashell mapped the staged plugin, verified by SHA-256, where the
`stock` sessions mapped the installed one. The receipts the test application saw were identical
in both modes on each machine: a banner without actions that times out reports reason 1, a click
on a banner with a default action runs the action once and reports reason 3, and closing a
notification reports reason 3. The shell logs held no script error. The device baseline of the
ThinkPad was the same before the run and after the cleanup. The runs are recorded in the shared
ledger under `2026-11-26-notification-triage-spec/evidence/part-a/`.

## What is not covered

- No package installs the copy, and no setup step enables it.
- The enforcement point of the version rule is not written.
- The `compiled` and `sanitizers` workflows build and test the part without installing it.
- The triage itself has run so far in one private session in the Fedora 44 test container on the
  build host: the test chord focused a banner, Escape dismissed it with KWrite active again, and
  Enter ran a default action once. Its own session scenarios, on the stock VM and on the ThinkPad,
  are the next change.
- The private sessions used injected input and a synthetic sender. The physical keyboard, the
  live desktop and real applications were not exercised.
