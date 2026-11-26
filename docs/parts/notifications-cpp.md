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
  (`cmake/PluginDirGuard.cmake`): landing on the stock plugin's path would replace the stock
  file. A relative value would be installed against the installation prefix, where it may be Qt's
  directory, and a link reaches the same directory under another name.
- A `built-against` record with `plasma-workspace=6.8.3` and the Qt version of the build, beside
  the records of the other compiled parts.
- In this first change the copy is the stock applet as it is. It changes no behaviour.

## Version rule

The copy may stand in for the stock plugin only while the installed `plasma-workspace` version is
exactly the one it was built from. `PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION` in the package's
`CMakeLists.txt` names that version; it is written into the plugin and into its record. This
package does not enforce the rule. The build's minimum versions are floors, not exact pins: a
newer Plasma in the build root must not fail the build, because the gate, not the build, decides
whether the copy is used.

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
directories and symbolic links, 18 cases, each refused or allowed with the expected words; it
needs no compiler and no packages. The tests are configured with the package (`BUILD_TESTING=ON`);
the packages are built with them off.

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
- The private sessions used injected input and a synthetic sender. The physical keyboard, the
  live desktop and real applications were not exercised.
