# Plasma test containers (PLASMA-68, 2026-10-01)

Private test sessions (`tools/vsession`) normally run on the ThinkPad. These containers run the same
sessions on the laptop, against any Plasma release Fedora packages: the device's Plasma 6.7.5, or a
pre-release from the Fedora KDE SIG's `@kdesig/kde-beta` COPR. Same scenarios, same helpers, so a
scenario can run on two Plasma versions side by side and the results compared line by line.

## Images

| Image | Recipe | Holds |
|---|---|---|
| `localhost/plasma-fusion-build:f44-6.7.5` | `tools/container/Containerfile` | build tools + Plasma 6.7.5 devel (also used for the RPMs) |
| `localhost/plasma-fusion-build:f44-6.8beta` | `tools/container/beta/Containerfile` | the same against the COPR's Plasma (6.7.91 on 2026-10-01) |
| `localhost/plasma-fusion-test:<tag>` | `tools/container/test/build.sh BASE TAG` | the BASE image's Plasma desktop, apps the scenarios use, Mesa, and Plasma Fusion's compiled parts (decoration, settings module, navigation effect) built and installed against it |

## Runs

`tools/vsession/cvsession.sh NAME SCENARIO SEED [WxH] [TIMEOUT]` instead of `remote.sh`; seeds as
usual (`make_seed`). Options: `PFV_IMAGE` (default the 6.7.5 test image), all `PFV_*` of
`remote.sh`, `PFV_HOME_DIR` (a persistent HOME on the laptop, for upgrade tests across two images)
and `PFV_PRE` (a command run in that HOME before the session: the login check, as startplasma does).
Container-owned files are removed with `podman unshare rm -rf`.

Needed: `--device /dev/dri` (without a GPU KWin paints in software and its screenshot plugin
crashes), `--cap-add SYS_NICE` (kwin_wayland carries cap_sys_nice; a rootless container cannot exec
it otherwise). Not in the images: KDE Connect and Milou (their QML modules show as missing), a web
browser (`preferred://browser` pins nothing), PAM for unlocking (lock tests stop at the prompt).

`PFV_DRI=0` runs without the render node, as on a machine without a GPU (GitHub's runners: the
`kwin-backport` workflow, docs/parts/ci.md). KWin then composites with QPainter. On 6.7.5
(2026-10-26) a screenshot did not crash but never returned: Spectacle waited until the session's
time limit. So these sessions take no screenshots: `shot` only lists the name in
`shots-skipped.log` (`PFV_NO_SHOTS=1`, which `cvsession.sh` sets). Only scenarios that use
screenshots for review alone fit this mode.

`PFV_XWAYLAND=1` also creates `/tmp/.X11-unix` in the container (mode 1777): the test image has
no X11 socket directory, and without it KWin logs `kwin_xwl: Failed to establish X11 socket` and
runs without Xwayland, so `DISPLAY` stays empty for the scenario (found 2026-10-26).

The results belong to the user who ran `cvsession.sh`: the container hands them back to the
owner of the output directory after copying them out. Before 2026-10-26 they kept the session
user's subordinate ids, which only `podman unshare` could move or remove.

## PLASMA-68 results (6.7.5 vs 6.7.91, 2026-10-01)

Fixed (all also right on 6.7.5): fe4a0f8 KWin 6.8's QML `Window` (its window class, uncreatable)
shadowed QtQuick's in the tablet, snap and outline scripts, which failed to load; ceb1014 Kicker 6.8
names apps `applications:<id>`, which broke the launcher's first-run pins and short names;
a697493 Plasma 6.8 removed `VirtualKeyboardLoader`, so the lock shell fell back to the built-in
locker (now `KeyboardShift.qml`); 183a760 the installer left the navigation effect unloaded after the
login check had switched it off (upgrade test 6.7.5 -> 6.8); f77f10e Plasma Mobile 6.8's velocity
filter fix (25 gestures classified the same as before).

Same on both: compiled parts build without warnings; panels 34/72 laptop and 45/81/21 tablet,
portrait, runtime scales; gestures (home, previous app, switcher, dock flick); Notification Centre,
search, launcher, settings module, decoration, Alt+Tab card, desktop cards; pen tap, no shell
gesture from the pen, pen press and hold in Dolphin; lock shell idle and prompt with the keyboard;
the login check switches the four version-bound parts off after the update and the installer turns
them back on.

Seen only with 6.7.91 in the container: plasmashell crashing in Mesa's texture upload (render
thread) at its very first start, 2 of about 10 runs, before Plasma Fusion is installed; a hidden
(dodging) dock takes a new thickness only when shown. Both on 6.7.5: the Alt+Tab card's `info`
binding loop, and a pen press and hold on a home-screen tile opens no menu.
