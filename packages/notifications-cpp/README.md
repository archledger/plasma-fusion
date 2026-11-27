<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Plasma Fusion notification applet

A Fusion-built copy of Plasma's own notification applet. The optional Fedora
`plasma-fusion-notifications` package installs it outside Qt's ordinary plugin path. The startup
gate decides whether a managed plasmashell launch uses it in place of stock. Installing the
package alone does not change a user's desktop; apply it with `plasma-fusion setup`.

## Origin

`src/` is **Plasma's notification applet**, `applets/notifications` in
[plasma-workspace](https://invent.kde.org/plasma/plasma-workspace) tag **v6.8.3**
(commit 4302f699329ebb155097beaab2d5aabbb21e33b3), by Kai Uwe Broulik, Marco Martin and others.
Every file keeps its original copyright lines and licence. Most files are
`GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL`; `globalshortcuts.*` are
`GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL`; `fileinfo.*`, `filemenu.*`, `jobaggregator.*` and
`thumbnailer.*` are `LGPL-2.1-or-later`; `components/DraggableFileArea.qml` and
`components/ThumbnailStrip.qml` are `LGPL-2.0-or-later`. The licence texts are in `LICENSES/` here
and in the repository's root. The Fedora RPM includes the current publisher copies of
[GPL 2.0](https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt),
[LGPL 2.0](https://www.gnu.org/licenses/old-licenses/lgpl-2.0.txt) and
[LGPL 2.1](https://github.com/gpg/libgcrypt/blob/master/COPYING.LIB), without the historical
postal address. The source notices and license expressions are unchanged.

`Messages.sh`, KDE's translation-extraction script, is not copied: this repository has no
translation catalogue step, so the name of the new shortcut is not translated.
`UPSTREAM-FILES` lists the QML files the QML checks skip because they are upstream code. Three of
them carry Plasma Fusion changes and stay listed, so those lines are outside the checks; with the
three unlisted, on 2026-11-27, the checks found one line, KDE's own (the `TapHandler` of
`src/NotificationPopup.qml`).

Plasma Fusion changes (each marked "Plasma Fusion" in the file):

- `CMakeLists.txt`: the wrapper build around the stock one. It installs the plugin under
  `PF_NOTIFICATIONS_PLUGIN_DIR`, which must be an absolute path that, symbolic links resolved, is
  neither Qt's own plugin directory nor inside it, nor KDE's own when that is another directory,
  and that holds no character CMake reads with a meaning of its own (`cmake/PluginDirGuard.cmake`).
  The build installs to the directory the guard resolved: the string checked is the string
  installed.
- `src/CMakeLists.txt`: a licence header above the stock build file, which has none, and the
  banner triage rules among the QML sources.
- `src/global/BannerTriage.js`: new. The rules of the banner keyboard triage
  (`SPEC-notification-triage.md`) as functions of plain values, each with its rows in the Qt
  Test: which banner the shortcut takes, which window is recorded to return to and where it is
  when it is asked for, how one banner's interaction moves between its states, what makes a
  banner the same notification, and what Escape and Enter do on it.
- `src/bannertriageversion.h`: new. The version rule as code.
- `src/globalshortcuts.h`, `src/globalshortcuts.cpp`: the "Focus notification banner" shortcut
  action, which exists only while the running Plasma is the one this copy was built from, and
  `reportTriage`, through which the applet's QML reports the steps of the triage to the applet's
  debug category.
- `src/global/Globals.qml`: taking the newest banner that may be taken when the shortcut is
  pressed, and recording the window to return to: the task model's own active task, by the ids
  the task model knows it by, looked up when it is asked for. The record of an earlier request
  stands when the shortcut takes a newer banner while an older one is still taken.
- `src/NotificationPopup.qml`: the interaction with one banner: keyboard focus, the focus ring
  (drawn around the banner, in the window's padding) and a report of where it is, the report of
  where the keyboard focus is inside it, the timer pause, Escape and Enter (Enter only from the
  banner's content itself).
- `src/components/NotificationReplyField.qml`: in a banner, the keyboard focus reaching the
  reply field starts the reply, as a click on it does. This and the report of the keyboard focus
  are in force whenever the copy is in force, at any Plasma version and also with the shortcut
  unassigned (`SPEC-notification-triage.md`, rule 13); the version rule covers the shortcut alone.
- `tests/`: the plugin test, the directory guard's test, the Qt Tests of the rules, the version
  rule and the shortcut (which runs only on the private session bus its driver makes); the
  private-session scenarios, with `ring.py`.

## Version rule

The copy may stand in for the stock plugin only while the installed `plasma-workspace` version is
exactly the one it was built from, `6.8.3`. The wrapper build names that version in its
`built-against` record, beside the Plasma version the build found and Qt's. Nothing in this
package enforces the rule or enables the copy on a machine.

## Updating the copy

When the tested Plasma version changes, copy the tree again from that tag, prove every file
verbatim against the tag's blob ids, apply the changes listed above again, and set
`PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION` in `CMakeLists.txt` to the new version.
