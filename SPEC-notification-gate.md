<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Spec: notification applet gate

Status: **Implemented for Fedora; real-device qualification pending.** It is the second plan that
[SPEC-notification-triage.md](SPEC-notification-triage.md) left (its rule 12 and decision 10): the
enforcement point of the version rule and its test, the package that ships the copy, and what
System Settings shows for the shortcut. Baseline: main
`e498f115cf6f697b21143456f10f5f53db5af8b1`, Plasma Workspace 6.8.3.

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
2. **A session-wide path containing a link managed by the user unit.** The original design.
   Rejected after the specification was merged: a directory can become unwritable after setup.
   If cleanup fails, the link is still readable through the session's plugin search path, even
   if the selector rejects the copy. Making cleanup fatal would instead stop the desktop.
3. **At every start through the unit, in that launch's environment** (chosen). The launch
   command opts in only when the selector succeeds. No link or exported session-wide path
   remains when the shell stops. The drop-in wraps the supported vendor command, so changes to
   that command require compatibility checks rather than blindly installing the same override.

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
   cannot build may still pass this rule; that is the case of decision 10.
4. **The theme.** The Global Theme in use is Plasma Fusion Dark or
   Light, read as the login check reads it. Under another theme the copy steps aside with the
   other Fusion parts, and its shortcut with it.

There is no rule of a tested series here. The login check's rule of that name is computed once,
when `fusion-config.sh` deploys, and from KWin's version; it would not be read at a start of
plasmashell. The copy needs none: rule 2 admits exactly the version the copy was built from.

When any rule fails, the stock applet loads and the shortcut does not focus a banner. For the
version rule and the load rule the user is told once, each time the copy steps
aside after it was in front, through a notification of the copy's own (below): "Plasma changed
under Plasma Fusion, or the notification applet could not be loaded. The banner keyboard shortcut
is off until Plasma Fusion is updated." That text holds also when the version could not be read,
which counts as another version. The theme rule is silent, since the user chose the theme, and so
is a missing record or plugin, as a missing decoration plugin is. The wording is the owner's to
change. When the bar holds again at a later start the copy is in front again without a
notification, as the other parts are switched back on.

## How the copy is put in front

The stock plugin's file is never replaced. On Fedora x86-64 the copy stays under
`/usr/lib64/libexec/plasma-fusion/qt6/plugins`, outside Qt's plugin directories.

- **The copy is admitted per launch.** A drop-in for `plasma-plasmashell.service` in
  `~/.config/systemd/user/plasma-plasmashell.service.d/20-plasma-fusion-notifications.conf`
  resets `ExecStart` and installs a launcher for the known Fedora command
  `/usr/bin/plasmashell --no-respawn`. `Type=dbus`, `BusName=org.kde.plasmashell`,
  `Restart=on-failure` and the 40-second timeout stay in the vendor unit. The launcher `exec`s
  that command whether or not Fusion is admitted. It does not replace the vendor unit file.
- **On early failure, start stock.** The launcher takes at most 5 seconds, including terminating
  a timed-out selector. It prepends the private directory to `QT_PLUGIN_PATH` only when the
  selector exits successfully with that exact configured directory as its entire output. It
  preserves unrelated plugin paths and does not set a systemd manager or session variable.
  A missing, failing or killed selector, including one that printed a path before failing, leaves
  the private directory out. A stale link is not consulted. A launch outside this unit, including
  a manual `--replace` from a normal terminal, is not changed by Fusion.
- **Vendor compatibility.** Install the override only where the effective vendor unit matches
  the supported contract. If the vendor unit on disk no longer matches, do not opt in. Remove
  the Fusion override when setup reconciles an unsupported unit. Until that reconciliation, an
  existing override still invokes the previously supported fixed command without the copy.
  The rollback is removing Fusion's drop-in and reloading the user manager; the vendor file
  remains untouched. Test this boundary before qualifying a different vendor unit.
- **Setup and restore.** `fusion-config.sh` manages the drop-in, the copy's notify unit and its
  `xdg-desktop-autostart.target.wants` link, and the recovery unit. No login environment file is
  needed. Reload only the manager belonging to the current session. `fusion-restore.sh` stops
  pending notification and recovery work before restoring/removing these managed files, clears
  the selector's state, and reloads the manager before starting the restored shell. Older
  backups without the managed files must remove them. Profile snapshots must not replay a
  selection verdict.

**What the selector reads, and when.**

- The installed version of `plasma-workspace` comes from the package database. The selector keeps
  it in a file of its own, under `~/.local/state/plasma-fusion/notifications/`, with the stamp of
  the package database it was read with (the rpm database's inode, size and time, as the login
  check stamps its cache), and reads the database again only when the stamp differs. It does not
  depend on the login check's cache, which is filled only while one of its parts is on.
- The load check runs when the stamp or payload differs or when no pass is recorded. Recheck the
  stamp and payload identity after the check and do not use the result if they changed during
  the attempt. Cache passes only. A failed check is tried again on the next start.
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

The ungated ThinkPad trial on 2026-11-27 showed that a private directory in `QT_PLUGIN_PATH`
selects the copy. In a Fedora 44 private user manager, a drop-in changed the path for the stand-in
shell only, preserved the vendor arguments, and used the original path when the helper was absent.
In direct-start Plasma 6.8.3 probes, a valid copy mapped and registered the notification service
under the shell's PID; a copy with an unavailable QML import passed the plugin test and mapped
but did not register the service; a layout with no applet neither mapped it nor registered the
service. These establish the detection rule, not packaged recovery.

## The package

- A subpackage, `plasma-fusion-notifications`, builds the copy from the source the repository
  carries, against the installed Plasma's build requirements. It ships the plugin under the
  directory above, the built-against record, the check and the selector.
- It requires `plasma-fusion` of its own version and release. It pins no Plasma version: a Fedora
  update is never blocked, as for the navigation effect; the selector is what stands between an
  update and a copy that was not built for it.
- **The subpackage stands alone.** No profile requires
  it and no count includes it: the metapackage of the full profile, its release test, the
  installer and the other channels all name six packages, and they change together when the other
  channels get the copy, in the plan that follows this one (decision 9 of the triage's
  specification). A desktop that wants the triage before then installs the subpackage by name.
- **This plan changes the Fedora package only.**
- **The ThinkPad's package, the owner's word.** The subpackage requires the base package of its
  own release, and the ThinkPad's base package carries the release tag of the full profile. So the
  copy for the ThinkPad comes from a build of the full project, which is a release's build and is
  asked for first, or from packages built on this machine. The ThinkPad's part of "complete"
  waits for that word.

## System Settings

- With the copy in front, System Settings lists **Focus notification banner** under **Plasma
  Workspace**. It has no default key.
- Stock does not implement the action. KDE may still show the saved row and key in System
  Settings: the page reads the shortcut daemon's saved entries, not just actions a running
  applet handles. Pressing that key under stock does not focus or dismiss a banner. Fusion
  does not remove or rewrite the saved binding; it works again when the copy returns (case 13).

## Where it is shown

- **The unit's launch, in a private user manager.** The existing session harness starts
  plasmashell directly. Test the drop-in under a disposable manager with a stand-in unit, and
  keep that evidence separate from direct-start runs. Prove the selector's timeout, removal
  and restart behavior without touching the host user manager. Cases that require the real
  ThinkPad unit need authorization for each device change.
- **The selector's decisions, in the private sessions**: run the same launcher logic before
  plasmashell, without claiming that a direct-start session tested systemd ordering.
  On the packages: the subpackage installed in the container and on the stock VM's overlay, and
  the triage's nine modes run against the installed RPM, not a staged plugin.
- **The selector and the scripts, in unit tests with fake tools**, as the login check is tested
  (`gate-unit.sh`, `gate-stub.sh`): fake package databases, a record and a plugin of their own, a
  check made to pass or to fail.
- **The real unit, on the ThinkPad**, when the subpackage is installed there (below): the copy in
  front at a login, and the managed configuration in place. The VM harness logs in over ssh only; a
  throwaway VM with a real login would be a plan of its own.

## What must be shown

In the private sessions with the launcher, in the private user manager where named, in unit
tests, and on the ThinkPad where noted.

1. **Matching Plasma.** Plasmashell maps the installed copy and no other notification applet,
   and the shortcut is listed. The nine modes of
   the triage pass from the package.
2. **Another Plasma version, without a new login.** With the version faked for the selector, at
   the next start in the same session: the private path is not added, stock is the one mapped, the
   saved shortcut does not focus a banner, and one notification is in the copy's queue.
3. **At a login, in the user manager.** After an update, the login check's notification and the
   copy's are both queued, and each is shown once.
4. **A copy that does not load.** With the stamp changed and the check made to fail: stock is in
   front, the notification is queued, no pass is recorded, and at the next start the check runs
   again.
5. **The record or the plugin missing alone.** Stock is in front, and no notification is queued.
6. **A missing, slow or killed selector in the user manager.** Stock is in front and plasmashell
   starts, even if the failed helper produced plausible output.
7. **A stop or crash of the unit's plasmashell.** No plugin path is left in the manager's
   environment. The next managed start checks again.
8. **The device scripts.** After setup the matching user manager knows the drop-in. Restore
   reinstates the backed-up configuration or removes it, and clears pending gate work and state.
9. **The times.** With nothing changed in the packages the selector finishes in a small fraction
   of a second; after a package change the check's run is measured and is within its limit.
10. **Under another theme.** With the Global Theme set to one that is not Plasma Fusion's, the
    copy is not in front and nothing is queued; with it set back, it is at the next start.
11. **On the ThinkPad.** After the subpackage is installed and `fusion-config.sh` has run, at a
    login: the real unit launched the copy, and the shortcut is listed.
12. **Without the unit.** Where `fusion-config.sh` starts plasmashell itself, the copy is not in
    front. An unreadable or non-removable link left outside the private RPM path changes nothing.
13. **The shortcut page and saved key.** In the same session, bind a key with the copy loaded.
    Verify the saved key is visible in KDE's shortcut page with stock loaded but leaves a visible
    banner and the active document alone. Verify the same key is shown and focuses a banner when
    the copy returns, without assigning it again.
14. **A copy whose QML cannot be built.** Install the invalid-QML fixture in the private test.
    Stock comes back within the session, plasmashell restarts once, and the copy stays aside
    until the package or payload identity changes. A layout with no applet does not restart.
15. **The unit tests.** Each case above that a unit test can hold has a row in the login check's
    own tests (`tools/device/tests/gate-unit.sh`, `gate-stub.sh`) or in the package's tests.

## What this does not cover

- Beyond what the load check shows: it does not build the QML (decision 10).
- An independently injected plugin path (a test, a manual launch override or another theme
  package) is not configured or removed by the gate.
- The real unit before the ThinkPad, if the private user manager cannot be had: the VM harness has
  no graphical login.
- The other channels, the installer, the profiles and the counts of six packages (above).
- The ThinkPad's trial of 2026-11-27. It is ended by its undo script before the subpackage is
  installed there; that is a change to the device and waits for the owner's word.

## Boundaries and success criteria

- **Build on:** plasmashell's systemd user unit and the unit-file management in
  `fusion-config.sh` and `fusion-restore.sh`; the copy's package and its plugin
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

## Decisions

1. **The bar:** the version rule and a load check. Taken on the owner's word to proceed with the
   recommendation.
2. **Under another Global Theme the copy steps aside**, with the other Fusion parts, and without a
   notification.
3. **"Every start" means every start through the unit.** The path is set only in the admitted
   launch, not in the session. Other starts are not changed by Fusion.
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
    session in that case. A watcher of the package, started asynchronously after plasmashell,
    checks that this invocation mapped the admitted copy and waits for the notification service
    from that shell. A layout with no mapped notification applet is not a malfunction. A
    different owner of the service is inconclusive: log it and leave that session alone.
    On a confirmed failure the watcher records the verdict against the package stamp and
    payload, then triggers the existing restart-on-failure policy for that process only.
    The selector keeps stock in front until that identity changes. Do not restart if the
    invocation has ended, has been replaced, is stopping, or the verdict cannot be saved.

## Size

A selector, a check, a notify unit and a bounded recovery unit; an optional Fedora subpackage;
setup and restore; private unit and session cases; and the part pages.
