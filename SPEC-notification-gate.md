<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Spec: notification applet gate

Status: **Proposed on 2026-11-27**, waiting for the owner. It is the second plan that
[SPEC-notification-triage.md](SPEC-notification-triage.md) left (its rule 12 and decision 10): the
enforcement point of the version rule and its test, the package that ships the copy, and what
System Settings shows for the shortcut. Baseline: main
`e498f115cf6f697b21143456f10f5f53db5af8b1`, Plasma Workspace 6.8.3. Nothing of it is built.

## Objective

The banner keyboard triage is merged (#223, #224, #225) and reaches no desktop: no package builds
the copy, and nothing decides whether it may stand in for the stock applet. After this plan a
desktop with the package has the triage, and after a Plasma update it has stock's notifications
again at the next start of plasmashell through its unit, with or without a new login. That order
matters because the notification service itself is this applet: a copy that was not built for the
running Plasma leaves the session without notifications until plasmashell starts again, and so
does one that cannot load with the installed libraries.

## Approaches considered

**Where the decision is made.**

1. **Once per login**, by the login check. Least code, and what this document first said. Not
   taken: the accepted specification has the rule evaluated every time plasmashell starts, because
   a Plasma update followed by a plasmashell restart would otherwise load a copy that was not
   built for it. An environment file is read once per login and cannot do that.
2. **At every start of plasmashell through its systemd user unit**: two start commands run
   before plasmashell starts, and a stop command removes the link when that plasmashell ends
   (chosen). The start commands run at login, at every restart through the unit and after every
   crash, and they change nothing in how plasmashell itself is started. Any other start of
   plasmashell finds stock, because the link exists only while a plasmashell started through the
   unit runs.
3. **Inside plasmashell's start command**, by a wrapper that replaces the unit's `ExecStart`.
   Rejected: the wrapper has to repeat Plasma's own start command, which a Plasma update may
   change.

**The bar.**

1. **The version rule alone.** The installed `plasma-workspace` is compared with the copy's
   record. A copy that cannot load with the installed libraries, with the version unchanged, is
   found only when plasmashell fails to show the applet.
2. **The version rule and a load check** (chosen). As 1, and the copy is also loaded once outside
   plasmashell, with the installed libraries, before it is put in front. One small helper, run
   once after each package change.

The owner let this plan proceed on the recommended bar (2026-11-27).

## The bar

The copy is put in front of the stock applet only when all of these hold. They are read before
every start of plasmashell through its unit.

1. **Installed.** The copy's plugin and its built-against record
   (`/usr/share/plasma-fusion/built-against/notifications`) are there.
2. **The version.** The installed `plasma-workspace` has the version of the record's
   `source-plasma-workspace` and of its `plasma-workspace`. Both are named: a copy of one
   version's source compiled against another version's libraries is not put in front on a machine
   that runs the source version. The comparison is of upstream versions; a distribution's rebuild
   does not count as another version.
3. **Loaded once.** A helper shipped with the package, `plasma-fusion-notifications-check`, has
   loaded the copy with the installed libraries and found what the plugin test of the repository
   finds: the plugin loads, its metadata says it is the stock applet, and the QML resources that
   plasmashell loads from it are there. It does not build the QML. A copy whose QML plasmashell
   cannot build passes this rule; that is the case of decision 10.
4. **Proposed, the owner's word: the theme.** The Global Theme in use is Plasma Fusion Dark or
   Light, read as the login check reads it. Under another theme the copy steps aside with the
   other Fusion parts, and its shortcut with it.

There is no rule of a tested series here. The login check's rule of that name is computed once,
when `fusion-config.sh` deploys, and from KWin's version; it would not be read at a start of
plasmashell. The copy needs none: rule 2 admits exactly the version the copy was built from.

When any rule fails, the copy is not in front: the stock applet loads and the shortcut does not
exist. For the version rule and the load rule the user is told once, each time the copy steps
aside after it was in front, through a notification of the copy's own (below): "Plasma changed
under Plasma Fusion, or the notification applet could not be loaded. The banner keyboard shortcut
is off until Plasma Fusion is updated." That text holds also when the version could not be read,
which counts as another version. The theme rule is silent, since the user chose the theme, and so
is a missing record or plugin, as a missing decoration plugin is. The wording is the owner's to
change. When the bar holds again at a later start the copy is in front again without a
notification, as the other parts are switched back on.

## How the copy is put in front

The stock plugin's file is never replaced. The copy stays under
`/usr/lib64/libexec/plasma-fusion/qt6/plugins`, where no Qt application looks for plugins.

- **One directory of Fusion's own is in the plugin path of the session**, always while the copy's
  package is applied: `~/.local/share/plasma-fusion/notifications/plugins`. An environment file,
  `~/.config/plasma-workspace/env/plasma-fusion-notifications.sh`, prepends it to
  `QT_PLUGIN_PATH`. It is read once per login, by `startplasma`, as Fusion's other environment
  files are, and it sets that one variable.
- **The copy is in that directory only by a link**, at
  `plasma/applets/org.kde.plasma.notifications.so`, to the installed plugin. The link is what
  makes the copy the first notification applet plasmashell finds. The selector makes it; the first
  start command and the stop command remove it; nothing else writes it.
- **Three commands of the same drop-in manage the link.** plasmashell runs as the user unit
  `plasma-plasmashell.service` (in Plasma 6.8.3: `ExecStart=/usr/bin/plasmashell --no-respawn`,
  restarted on failure, a start timeout of 40 seconds). A drop-in for that unit in the user's
  systemd directory, `~/.config/systemd/user/plasma-plasmashell.service.d/20-plasma-fusion-notifications.conf`,
  adds, in this order:

      [Service]
      ExecStartPre=-/usr/bin/rm -f "<the link>"
      ExecStartPre=-/usr/libexec/plasma-fusion/plasma-fusion-notifications-select
      ExecStopPost=-/usr/bin/rm -f "<the link>"

  (the link's path written out from the user's data directory, with each `%` doubled, as
  `fusion-config.sh` writes the login check's unit). The leading `-` keeps a failure of a command
  from keeping plasmashell from starting or stopping.

  The first command removes the link and needs nothing from the package. So stock is in front
  whenever anything goes wrong before the second has made the link again: a selector that is
  missing, that cannot run, or that is killed before it has made the link. The first command also
  clears a link left by a session that died while plasmashell ran, since the stop command could
  not run then. The stop command removes the link when that plasmashell ends, however it ends, so
  that a plasmashell started in any other way (from a terminal, with `--replace`, by a Plasma
  that has no systemd) finds stock. One case stays open and is accepted as it is, or not: a
  `plasmashell --replace` started by hand while the unit's plasmashell runs, after an update in
  the same session, loads the copy for as long as that process lives, as the old version's stock
  applet with the shortcut off.
- **The selector** is a shell script of the package. It reads the bar, and when it holds it makes
  the link. It puts a time limit on its own run, 5 seconds against the unit's 40, and at the limit
  it stops with the link removed. A selector stopped by a signal it can catch removes the link,
  at any point of its run. One killed by a signal it cannot catch after it has made the link
  leaves the copy in front for that start of plasmashell: a copy that had just passed the bar.
- `fusion-config.sh` installs four files, made as it makes the login check's, from the user's
  directories: the environment file, the drop-in, the notify unit of the copy (below) and its link
  in `xdg-desktop-autostart.target.wants`. It reloads the user manager when there is one, so the
  commands count from the next start of plasmashell through the unit. The copy is in front from
  the next login, when the environment file is read. `fusion-config.sh` never makes the link.
  Where plasmashell is not started through its unit, the copy is not put in front at all: nothing
  can read the bar before each start there. `fusion-config.sh` removes the link when it finds one
  and starts plasmashell with stock. It makes the directory of the link and checks that it can
  write a file in it and remove it; where it cannot, it installs none of the four files.
- `fusion-restore.sh` treats the four files as it treats the login check's own: they come back
  when the configuration it restores has them, and go otherwise; its reload of the user manager
  covers the notify unit. It removes the link and the selector's state before it starts plasmashell,
  so that a desktop returned to stock does not have the copy in front in the session it is
  returned in, whose plugin path names the directory until it ends.

**What the selector reads, and when.**

- The installed version of `plasma-workspace` comes from the package database. The selector keeps
  it in a file of its own, under `~/.local/state/plasma-fusion/notifications/`, with the stamp of
  the package database it was read with (the rpm database's inode, size and time, as the login
  check stamps its cache), and reads the database again only when the stamp differs. It does not
  depend on the login check's cache, which is filled only while one of its parts is on.
- The load check runs when the stamp differs or no pass is recorded. A pass is recorded with the
  stamp; a failure is not recorded, so it is tried again at the next start. It has a time limit
  of its own inside the selector's.
- It honours the login check's test hook for versions, `PF_GATE_FAKE_VERSIONS`, in the same way:
  a faked version is never cached. A hook of its own names other programs and files in its place,
  as `PF_GATE_RPM` names the rpm program: the check, the record and the plugin.
- When the copy steps aside for the version rule or the load rule, after it was in front at the
  previous start, the selector queues the notification and starts its notify unit with
  `systemctl --user start --no-block`: it never waits
  on systemd, because at a login that wait and plasmashell's wait on the selector could hold each
  other. It keeps a log of one line a run.

**The notification.** The copy has a queue and a unit of its own, made like the login check's:
`~/.local/state/plasma-fusion/notifications/notify`, and
`~/.config/systemd/user/plasma-fusion-notifications-notify.service`, which waits for the
notification service and shows what is queued. The login check's queue is not shared: at a login
both have something to say after a Plasma update, and each is shown once.

That a directory of Fusion's own in `QT_PLUGIN_PATH` is enough was shown on the ThinkPad on
2026-11-27: a plugin directory under the user's home and one environment file put the copy in
front of the stock applet, with no package and no root. The start and stop commands are new and
are shown by the cases below.

## The package

- A subpackage, `plasma-fusion-notifications`, builds the copy from the source the repository
  carries, against the installed Plasma's build requirements. It ships the plugin under the
  directory above, the built-against record, the check and the selector.
- It requires `plasma-fusion` of its own version and release. It pins no Plasma version: a Fedora
  update is never blocked, as for the navigation effect; the selector is what stands between an
  update and a copy that was not built for it.
- **Proposed, the owner's word: in this plan the subpackage stands alone.** No profile requires
  it and no count includes it: the metapackage of the full profile, its release test, the
  installer and the other channels all name six packages, and they change together when the other
  channels get the copy, in the plan that follows this one (decision 9 of the triage's
  specification). A desktop that wants the triage before then installs the subpackage by name.
- **Proposed, the owner's word: this plan changes the Fedora package only.**
- **The ThinkPad's package, the owner's word.** The subpackage requires the base package of its
  own release, and the ThinkPad's base package carries the release tag of the full profile. So the
  copy for the ThinkPad comes from a build of the full project, which is a release's build and is
  asked for first, or from packages built on this machine. The ThinkPad's part of "complete"
  waits for that word.

## System Settings

- With the copy in front, the shortcut page lists "Focus notification banner" among plasmashell's
  shortcuts, unassigned, and the user gives it a key there.
- With the copy stepped aside, the action is not registered and the page does not list it. The
  page shows the actions the shortcut daemon has registered, and the daemon lists only those. The
  key the user gave stays in the daemon's configuration and is theirs again when the copy returns.
  That much was seen on the ThinkPad on 2026-11-27: with stock in front the daemon no longer
  listed the action, while its entry stayed in the configuration. The page itself is shown in a
  session (case 13).

## Where it is shown

- **The unit's commands, in a private user manager inside the private sessions.** Their plasmashell
  is started directly, without a user manager, so nothing there runs a start command or a stop
  command. The harness is to start a user manager of its own in the session, with a stand-in unit
  of the name `plasma-plasmashell.service` whose start command is the harness's own, and to let
  `fusion-config.sh` install the drop-in there. That shows the commands as systemd runs them: the
  `-`, the path, a selector killed at its limit, a restart after a crash, the notify unit. Whether
  this can be had is tried first, as a throwaway; if it cannot, the cases that need it move to the
  ThinkPad, which is the owner's word for each.
- **The selector's decisions, in the private sessions** as they are: the harness runs the two
  start commands in the unit's order and then plasmashell, with the directory in the plugin path.
  On the packages: the subpackage installed in the container and on the stock VM's overlay, and
  the triage's nine modes run with the link made by the selector rather than by a staged plugin.
- **The selector and the scripts, in unit tests with fake tools**, as the login check is tested
  (`gate-unit.sh`, `gate-stub.sh`): fake package databases, a record and a plugin of their own, a
  check made to pass or to fail.
- **The real unit, on the ThinkPad**, when the subpackage is installed there (below): the copy in
  front at a login, and the four files in place. The VM harness logs in over ssh only; a
  throwaway VM with a real login would be a plan of its own.

## What must be shown

In the private sessions, with the start commands run in the unit's order unless a case names the
user manager; in the unit tests; and on the ThinkPad where it says so.

1. **Matching Plasma.** After the two start commands the copy is in front: plasmashell maps the
   link's target and no other notification applet, and the shortcut is listed. The nine modes of
   the triage pass from the package.
2. **Another Plasma version, without a new login.** With the version faked for the selector, at
   the next start in the same session: the link is gone, the stock applet is the one mapped, the
   shortcut is not listed, and one notification is in the copy's queue.
3. **At a login, in the user manager.** After an update, the login check's notification and the
   copy's are both queued, and each is shown once.
4. **A copy that does not load.** With the stamp changed and the check made to fail: stock is in
   front, the notification is queued, no pass is recorded, and at the next start the check runs
   again.
5. **The record or the plugin missing alone.** Stock is in front, and no notification is queued.
6. **A selector that cannot run, or is killed before it has made the link, in the user manager.**
   Stock is in front and plasmashell starts. One stopped by a signal it can catch after it has
   made the link leaves stock in front as well.
7. **A stop of the unit's plasmashell.** In the user manager: the link is gone when it ends by a
   crash and by a stop, and it is made again at the next start when the bar holds.
8. **The device scripts.** After `fusion-config.sh` the four files are in place, and where there
   is a user manager it knows the drop-in. After `fusion-restore.sh` they are gone, or back when
   the restored configuration has them, and the link and the state are removed.
9. **The times.** With nothing changed in the packages the selector finishes in a small fraction
   of a second; after a package change the check's run is measured and is within its limit.
10. **Under another theme.** With the Global Theme set to one that is not Plasma Fusion's, the
    copy is not in front and nothing is queued; with it set back, it is at the next start.
11. **On the ThinkPad.** After the subpackage is installed and `fusion-config.sh` has run, at a
    login: the copy is in front through the real unit's commands, and the shortcut is listed.
12. **Without the unit.** Where `fusion-config.sh` starts plasmashell itself, the copy is not in
    front, and a link found there is removed.
13. **The shortcut page.** With the copy in front it lists the action; with the copy stepped aside
    it does not, and the key is back when the copy returns.
14. **A copy whose QML cannot be built**, if decision 10 is taken: with such a copy put in its
    place by a hook, stock is in front again within the session, plasmashell is restarted once,
    and the copy stays aside until the packages change.
15. **The unit tests.** Each case above that a unit test can hold has a row in the login check's
    own tests (`tools/device/tests/gate-unit.sh`, `gate-stub.sh`) or in the package's tests.

## What this does not cover

- Beyond what the load check shows: it does not build the QML (decision 10).
- A `plasmashell --replace` started by hand while the unit's plasmashell runs, after an update in
  the same session (above).
- The real unit before the ThinkPad, if the private user manager cannot be had: the VM harness has
  no graphical login.
- The other channels, the installer, the profiles and the counts of six packages (above).
- The ThinkPad's trial of 2026-11-27. It is ended by its undo script before the subpackage is
  installed there; that is a change to the device and waits for the owner's word.

## Boundaries and success criteria

- **Build on:** plasmashell's systemd user unit and Fusion's environment files, which
  `fusion-config.sh` and `fusion-restore.sh` already manage; the copy's package and its plugin
  test; the session harness of the triage and the login check's unit tests.
- **Ask first:** a change to the ThinkPad beyond its private sessions; a Plasma or Qt version
  other than 6.8.3; a merge, a release, a build of the full project, a package for another channel;
  a VM with a real login.
- **Never:** replace the stock plugin's file; pin a Plasma version so that an update is blocked;
  keep plasmashell from starting; put a copy in front that was not built for the running Plasma
  or that did not load; weaken a check.

Complete means the cases above pass where each says, the part pages of the login check and of the
copy say what the code does, and the ThinkPad runs the triage from its package with the real unit's
commands in front of it. No claim extends beyond the tested versions.

## Decisions proposed, for the owner

1. **The bar:** the version rule and a load check. Taken on the owner's word to proceed with the
   recommendation.
2. **Under another Global Theme the copy steps aside**, with the other Fusion parts, and without a
   notification.
3. **"Every start" means every start through the unit.** Any other start of plasmashell finds
   stock; the one case that does not, a `--replace` typed by hand while the unit's plasmashell
   runs after an update in the same session, is accepted.
4. **The notification** is for the version rule and the load rule only, from a queue of its own,
   shown in the running session; and its wording.
5. **In this plan the subpackage stands alone:** no profile requires it and no count includes it;
   the profiles, the installer and the other channels change in the plan that follows.
6. **This plan changes the Fedora package only.**
7. **No version pin.**
8. **Where the unit's commands are shown:** in a private user manager in the sessions, tried first
   as a throwaway; where that cannot be had, on the ThinkPad, a case at a time and each with the
   owner's word. No VM with a real login in this plan.
9. **The ThinkPad:** the trial is ended; the subpackage comes from a build of the full project,
   which is the owner's word; it is installed there by name and `fusion-config.sh` is run; the
   owner logs out and in.
10. **A copy whose QML plasmashell cannot build, with the version the same.** The load check does
    not build the QML, so such a copy is put in front, and the session has no notification service
    until plasmashell starts again. The triage's specification asks for stock back within the same
    session in that case. **Proposed, the owner's word:** a watcher of the package, started after
    plasmashell, waits for the notification service; when it does not appear and the copy is in
    front, it removes the link, records the verdict against the stamp of the package database, so
    that the selector keeps stock in front until the packages change, and restarts plasmashell
    once. Taken, it is part of this plan and its case is among those to show. Declined, the case
    is a limitation of this plan.

## Size

A project: a selector, a check, a notify unit and, if decision 10 is taken, a watcher, all of the
package; a subpackage in the Fedora spec file; four files more for `fusion-config.sh` and
`fusion-restore.sh` to manage; a private user manager in the session harness; session cases in
three places; and two part pages.
