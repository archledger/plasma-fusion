# Architecture

How Plasma Fusion is put together: where each part comes from, how it is built and installed, what
runs where, and where it keeps its state. Each part has its own page in [`parts/`](parts/); this
page links them. The names and install paths of every part are in the naming table of
[`PLAN.md`](PLAN.md).

Plasma Fusion is not a program of its own. It is a set of KDE Plasma 6 add-ons (themes, widgets,
KWin scripts, a lock screen, a few small services and three compiled plugins) that Plasma, KWin,
System Settings, the screen locker and Plymouth load in their usual places. It changes the look
and the shell; it does not replace Plasma.

## Layers

```
design/boards/*.dc.html          the design boards: every colour, size and drawing
        |
        v
generators/<part>/  (Python)     draw what can be drawn: icons, cursors, wallpapers, Plasma style
packages/<part>/   (hand-written) QML widgets, KWin scripts, lock shell, colour schemes, helpers
packages/common/   (shared QML)  one copy of each shared block, copied into each package at build
        |
        v
tools/build.sh -> tools/build.d/NN-<part>.sh
        |              (QML lints first; each part writes only below the stage)
        v
stage/home/                      a HOME tree: .local/share, .local/libexec, .config
        |
        +--> per user:   tools/device/fusion-config.sh --install stage/home
        |                (backup, copy into ~/.local, configure the session, login check)
        +--> system:     packaging/build-rpm.sh -> plasma-fusion RPM (/usr/share, /usr/libexec)
                         then each user runs fusion-config.sh from /usr/share/plasma-fusion/tools

packages/{decoration,kcm,navigation}-cpp/  (C++, CMake)  -> their own RPMs, against KDE's libraries
tools/system/  (run as root)   login greeter styling, boot splash install
```

### Design boards

The 25 boards in [`design/`](../design/README.md) are HTML canvases. Generators and hand-written
code take their numbers from them; the board decides when the two disagree.

### Generators

`generators/<part>/` are Python programs (standard library and Pillow; PySide6 where Qt's own SVG
renderer must check the result; NumPy for the boot splash). They write SVG, PNG, Xcursor and font
files: icon themes ([`parts/icons.md`](parts/icons.md)), cursor themes
([`parts/cursors.md`](parts/cursors.md)), wallpapers and fonts
([`parts/foundation.md`](parts/foundation.md)), the Plasma style
([`parts/plasma-style.md`](parts/plasma-style.md)), the Aurorae window decoration
([`parts/decoration.md`](parts/decoration.md)), Global Theme previews and the splash background
([`parts/lookandfeel.md`](parts/lookandfeel.md)), and the boot splash
([`parts/plymouth.md`](parts/plymouth.md)).

### Hand-written packages

| Kind | Where | Loaded by | Page |
|---|---|---|---|
| Colour schemes, Konsole and Kate themes, GTK colours | `packages/color-schemes`, `konsole`, `ktexteditor`, `gtk` | Plasma, the apps | [`foundation.md`](parts/foundation.md) |
| Global Themes (dark, light), desktop layout script, splash, layout templates | `packages/look-and-feel` | Plasma's Global Theme machinery, plasmashell | [`lookandfeel.md`](parts/lookandfeel.md) |
| Shell widgets (plasmoids): top bar, quick settings, launcher, dock, desktop cards, pen menu, desktop and tablet home screen | `packages/plasmoids/org.plasmafusion.*` | plasmashell | [`shell-topbar.md`](parts/shell-topbar.md), [`shell-quicksettings.md`](parts/shell-quicksettings.md), [`shell-launcher.md`](parts/shell-launcher.md), [`shell-dock.md`](parts/shell-dock.md), [`desktop-cards.md`](parts/desktop-cards.md), [`pen.md`](parts/pen.md), [`desktop.md`](parts/desktop.md) |
| Shared QML blocks (text scale, motion, tablet posture, glass, accent, icon tile, shadow, app-open zoom) | `packages/common` | copied into each package by `tools/build-lib/shared-qml.sh` | [`shared-blocks.md`](parts/shared-blocks.md), [`text-scale.md`](parts/text-scale.md) |
| KWin window switcher, snap layouts, attached dialogs, snap outline, tablet window policy | `packages/kwin` | KWin | [`kwin.md`](parts/kwin.md), [`kwin-tablet.md`](parts/kwin-tablet.md) |
| Lock screen shell | `packages/lockscreen` | kscreenlocker's greeter | [`lockscreen.md`](parts/lockscreen.md) |
| Boot splash script | `packages/plymouth` | Plymouth (in the initramfs) | [`plymouth.md`](parts/plymouth.md) |
| Power tiers service | `packages/powerfx` | systemd user manager | [`powerfx.md`](parts/powerfx.md) |
| Familiar app icons service | `packages/appicons` | systemd user manager | [`app-icons.md`](parts/app-icons.md) |
| Charge-limit helper and polkit action | `packages/power/charge-limit` | pkexec, from quick settings | [`charge-limit.md`](parts/charge-limit.md) |
| On-screen keyboard keys, per-app fixes | `packages/keyboard`, `packages/compat` | fusion-config.sh, the apps | [`keyboard.md`](parts/keyboard.md), [`compat.md`](parts/compat.md) |

### Compiled parts

Three C++ plugins, each with a CMake project and a spec file, built in a Fedora 44 container
(`tools/container/`) or by the `compiled` workflow ([`parts/ci.md`](parts/ci.md)). The decoration
and the settings module have test tools in their `tests/` directories (an offline renderer, scripted
private sessions):

| Part | Loaded by | Bound to | Page |
|---|---|---|---|
| `packages/decoration-cpp`: KDecoration3 window decoration "Plasma Fusion" | KWin | KDecoration3 6.7 | [`decoration-cpp.md`](parts/decoration-cpp.md) |
| `packages/kcm-cpp`: settings module `kcm_plasmafusion` | System Settings | KDE Frameworks | [`kcm-cpp.md`](parts/kcm-cpp.md) |
| `packages/navigation-cpp`: tablet gestures, a KWin effect derived from Plasma Mobile's task switcher | KWin | KWin's internal library, exact version | [`packages/navigation-cpp/README.md`](../packages/navigation-cpp/README.md) |

The navigation effect stays idle when the running KWin is not the one it was built against
(`packages/navigation-cpp/src/plugin/fusionnavigation.cpp`, the version check at start).

### Build

`tools/build.sh` runs the QML lints (`tools/checks/motion-lint.sh`, `tools/checks/a11y-lint.py`),
then every `tools/build.d/NN-<part>.sh` in order. Each part script runs its generator or copies its
package, runs its own checks (contrast, package structure, unit tests, shellcheck where installed)
and writes only below `$STAGE` (default `stage/home`), in the paths the naming table gives it
([`PLAN.md`](PLAN.md), "Repository layout"). Testing is described in
[`parts/testing.md`](parts/testing.md) and [`parts/containers.md`](parts/containers.md); CI in
[`parts/ci.md`](parts/ci.md).

### Install

- **Per user, no root:** `tools/device/fusion-config.sh --install stage/home` copies the stage into
  the HOME, after a backup of every file it may touch, then configures the running session (Global
  Theme, panels, shortcuts, fonts, KWin scripts, user services, the login check). It records a
  configuration version and only changes keys the user has not changed since
  ([`parts/device.md`](parts/device.md)). `tools/device/fusion-restore.sh` puts a backup back.
- **System package:** `packaging/build-rpm.sh` runs the same build inside `rpmbuild` and installs
  the stage under `/usr/share` and `/usr/libexec/plasma-fusion`, with the polkit action. Each user
  still runs `fusion-config.sh` once ([`parts/system.md`](parts/system.md)).
- **Compiled parts:** their own RPMs (`plasma-fusion-decoration`, `plasma-fusion-settings`,
  `plasma-fusion-navigation`), installed into Qt's plugin directories.
- **As root, optional:** `tools/system/greeter-apply.sh` styles the plasma-login-manager greeter
  ([`parts/system.md`](parts/system.md)); `tools/system/plymouth-install.sh` installs and selects the
  boot splash ([`parts/plymouth.md`](parts/plymouth.md)). Each has an undo script next to it.

## What runs where

| Process | Plasma Fusion code in it | Privileges |
|---|---|---|
| `plasmashell` | the widgets, the Global Theme's layout script | the user |
| `kwin_wayland` | KWin scripts, the switcher, the decoration (Aurorae or C++), the navigation effect | the user (the compositor: it sees all input) |
| `systemsettings` | the settings module | the user |
| `kscreenlocker_greet` | the lock screen QML | the user; PAM checks the password, not this code |
| `plasma-fusion-powerfx`, `plasma-fusion-app-icons` | user services | the user, `NoNewPrivileges=yes` |
| the login check | `plasma-fusion-gate.sh`, before KWin starts | the user, 4 s time limit |
| `plasma-fusion-fieldlog` (optional) | the field log: crashes, restarts and Plasma Fusion errors in daily use | the user, `NoNewPrivileges=yes`, 96 MiB, no swap ([`parts/fieldlog.md`](parts/fieldlog.md)) |
| `plasma-fusion-charge-limit` | the charge-limit helper | root, through pkexec and polkit |
| Plymouth | the boot splash script | boot and shutdown, before any user logs in |
| plasma-login-manager's greeter | styling only (colours, fonts, wallpaper); its QML is KDE's | the `plasmalogin` user |

## Data and control flows

- **Settings.** Plasma Fusion's own options live in `~/.config/plasmafusionrc`. The settings
  module writes it; the widgets, KWin scripts and services read it. KDE's own keys (`kdeglobals`,
  `kwinrc`, `plasmashellrc`, the applet configuration) are written with KDE's tools
  (`kwriteconfig6`, KConfig) and the change is announced so running programs reload.
- **Shell to system.** Widgets run short commands through Plasma's executable data engine:
  KDE tools such as `kwriteconfig6`, `kscreen-doctor`, `plasma-apply-lookandfeel`, and `pkexec`
  for the charge-limit helper. Values from outside the widget are quoted or checked against an
  allowlist first ([`SECURITY-ASSURANCE.md`](SECURITY-ASSURANCE.md), section 6).
- **Login check.** At every login startplasma sources
  `~/.config/plasma-workspace/env/plasma-fusion-gate.sh`, which runs the check as its own process
  with a time limit. The check compares the installed Plasma, KWin, kscreenlocker, libplasma,
  KDecoration and Qt versions (read from rpm, pacman, dpkg or Nix) with the ones recorded
  as tested; after an update it switches the version-bound parts off (lock screen, compiled
  decoration, navigation effect, desktop containment) and queues a notification, which
  `plasma-fusion-gate-notify.service` shows once the desktop is up. `fusion-config.sh` records
  the new versions and turns the parts back on ([`parts/gate.md`](parts/gate.md)).
- **Power tiers.** `plasma-fusion-powerfx` listens to UPower and power-profiles-daemon on D-Bus and
  makes the desktop lighter at low battery; it gives every value back when the battery recovers or
  the service stops ([`parts/powerfx.md`](parts/powerfx.md)).
- **App icons.** `plasma-fusion-app-icons` watches the application directories and draws a tile for
  each installed app's own icon into the user's copy of the icon theme
  ([`parts/app-icons.md`](parts/app-icons.md)).
- **Charge limit.** The quick settings tile reads the battery's thresholds through the helper and
  sets them with `pkexec` ([`parts/charge-limit.md`](parts/charge-limit.md)).
- **Lock screen.** `lockscreen-enable.sh` sets `PLASMA_DEFAULT_SHELL` for KWin only, so
  kscreenlocker's greeter loads the Plasma Fusion lock shell; authentication stays with
  kscreenlocker and PAM ([`parts/lockscreen.md`](parts/lockscreen.md), "Authentication contract").

## Where state lives

| Path | What | Written by |
|---|---|---|
| `~/.config/plasmafusionrc` | Plasma Fusion options | settings module, widgets, `fusion-config.sh` |
| `~/.config/` KDE files (`kdeglobals`, `kwinrc`, `plasmashellrc`, ...) | KDE settings Plasma Fusion sets | `fusion-config.sh`, settings module, widgets, the login check |
| `~/.config/plasma-workspace/env/plasma-fusion-{gate,session}.sh` | login check stub, session variables | `fusion-config.sh` |
| `~/.config/systemd/user/` | the user units and their links, the lock screen drop-in | `fusion-config.sh`, `lockscreen-enable.sh` |
| `~/.local/share/` | the per-user copy of every package | `fusion-config.sh --install`, the app icons service (icon theme) |
| `~/.local/libexec/plasma-fusion/` | per-user copies of the helper programs | `fusion-config.sh --install` |
| `~/.local/state/plasma-fusion/` | backups (`backup-<time>/`), the login check's state and log (`gate/`, `gate.log`), `config-changes`, the app icons record and backup | `fusion-config.sh`, the login check, the app icons service |
| `~/.local/state/plasma-fusion/fieldlog/` | the field log's events, saved crash reports and daily digests (only where it is installed) | `plasma-fusion-fieldlog` |
| `/usr/share/`, `/usr/libexec/plasma-fusion/`, `/usr/share/polkit-1/actions/` | the system package | the RPM |
| `/usr/share/plymouth/themes/plasma-fusion/`, `/var/lib/plasma-fusion/plymouth/` | installed boot splash, its saved previous theme and settings | `plymouth-install.sh` |
| `/var/lib/plasmalogin/.config/`, `/etc/plasmalogin.conf`, `/var/lib/plasma-fusion/greeter-backup-<time>/` | greeter styling and its backup | `greeter-apply.sh` |
| `/sys/class/power_supply/BAT*/charge_control_*_threshold` | the battery's charge limit (kernel, not a file of Plasma Fusion) | the charge-limit helper |
