<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Notification applet: private sessions

`scen-notifications.sh` runs Plasma's notification applet in an isolated session (`tools/vsession`)
and checks that the built copy behaves like the installed applet. It is test tooling, never
installed, and must never run against a logged-in desktop.

## Modes

`make-seed.sh` writes the mode into the session's HOME (`pf-notif/mode`):

| Mode | What plasmashell loads |
|---|---|
| `stock` | The installed applet. The seed adds no plugin, so nothing stands in its way. |
| `copy` | The built copy. The seed puts it under `pf-plugins/plasma/applets` and `QT_PLUGIN_PATH` (`home/.config/pfv-env`) puts it in front of the stock plugin. The applet's debug category is switched on. |

Both modes run the same checks, so a difference between them is the copy's doing.

## Build, seed, run

Build the part and install it to a stage first (`docs/parts/notifications-cpp.md`, "Build and
test"). Then, on the test device:

```sh
p=packages/notifications-cpp
for mode in stock copy; do
    bash $p/tests/vsession/make-seed.sh build/notifications-stage "/var/tmp/pfv-notif-$mode-seed" notif "$mode"
done
```

`PFV_BASE` (default `/var/tmp`) must be where the session HOME will live, because `QT_PLUGIN_PATH`
names it literally.

For each mode, copy that seed to the session's HOME and start the session:

```sh
mode=copy
rm -rf "/var/tmp/pfv-notif" && mkdir -p "/var/tmp/pfv-notif"
cp -a "/var/tmp/pfv-notif-$mode-seed/." "/var/tmp/pfv-notif/home/"
bash tools/vsession/vsession.sh notif $p/tests/vsession/scen-notifications.sh 1440x900 120
```

Session names must be unique on the host. For the ThinkPad from the laptop, `tools/vsession/remote.sh`
takes the seed directory instead and fetches the results.

## What it checks

- The notification server on the session bus belongs to plasmashell, and the applet plasmashell
  has mapped is the one the mode asks for (`stock`: the installed one; `copy`: the staged plugin,
  by SHA-256).
- A banner with a two-second timeout tells the application it expired.
- A click on a banner with a default action runs that action once and then closes the notification.
- Closing a notification tells the application.
- The shell log holds no script error.

## Reading a run

The session's `out/` directory holds `checks.txt` (one `PASS` or `FAIL` line per check),
`scenario.log` (`scenario rc=0`), `teardown.log` (`left: none`), `mapped-applet.txt`,
`packages.txt`, `sender.log` with every receipt, and the screenshots. A mode passes only when the
scenario and the session returned zero, teardown left no process, and every line of `checks.txt`
is `PASS`. Keep the `out/` directory with the applet's identity and the package versions as the
record of the run.
