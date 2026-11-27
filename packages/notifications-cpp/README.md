<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Plasma Fusion notification applet

A Fusion-built copy of Plasma's own notification applet. It is built and tested here. Whether a
machine uses it in place of the stock plugin will be decided by a version gate that is not written
yet (the version rule below); this package alone enables nothing.

## Origin

`src/` is **Plasma's notification applet**, `applets/notifications` in
[plasma-workspace](https://invent.kde.org/plasma/plasma-workspace) tag **v6.8.3**
(commit 4302f699329ebb155097beaab2d5aabbb21e33b3), by Kai Uwe Broulik, Marco Martin and others.
Every file keeps its original copyright lines and licence. Most files are
`GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL`; `globalshortcuts.*` are
`GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL`; `fileinfo.*`, `filemenu.*`, `jobaggregator.*` and
`thumbnailer.*` are `LGPL-2.1-or-later`; `components/DraggableFileArea.qml` and
`components/ThumbnailStrip.qml` are `LGPL-2.0-or-later`. The licence texts are in `LICENSES/` here
and in the repository's root.

`Messages.sh`, KDE's translation-extraction script, is not copied: this repository has no
translation catalogue step. `UPSTREAM-FILES` lists the QML files the linters skip because they
are upstream code.

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
  (`SPEC-notification-triage.md`): which banner the shortcut takes, how one banner's interaction
  moves between its states, and what Escape and Enter do on it.
- `src/bannertriageversion.h`: new. The version rule as code.
- `src/globalshortcuts.h`, `src/globalshortcuts.cpp`: the "Focus notification banner" shortcut
  action, which exists only while the running Plasma is the one this copy was built from, and
  `reportTriage`, through which the applet's QML reports the steps of the triage to the applet's
  debug category.
- `src/global/Globals.qml`: taking the newest banner that may be taken when the shortcut is
  pressed, and recording the window to return to.
- `src/NotificationPopup.qml`: the interaction with one banner: keyboard focus, the focus ring,
  the report of where the keyboard focus is inside it, the timer pause, Escape and Enter (Enter
  only from the banner's content itself).
- `src/components/NotificationReplyField.qml`: in a banner, the keyboard focus reaching the
  reply field starts the reply, as a click on it does.
- `tests/`: the plugin test, the directory guard's test, the Qt Tests of the rules, the version
  rule and the shortcut; the private-session scenarios.

## Version rule

The copy may stand in for the stock plugin only while the installed `plasma-workspace` version is
exactly the one it was built from, `6.8.3`. The wrapper build names that version in its
`built-against` record, beside the Plasma version the build found and Qt's. Nothing in this
package enforces the rule or enables the copy on a machine.

## Updating the copy

When the tested Plasma version changes, copy the tree again from that tag, prove every file
verbatim against the tag's blob ids, apply the changes listed above again, and set
`PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION` in `CMakeLists.txt` to the new version.
