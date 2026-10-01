# Device scripts: configure, upgrade and undo the real session (DEVICE-1)

Status: built and tested in private sessions on the ThinkPad against stand-ins for the parts other
lanes are still building (see Verification; one open item, Meta+N); not run in the real session
(the lead deploys).
Last edited 2026-09-30.

Covers PLAN.md (2026-09-30-decisions) DEVICE-1: owner decisions 5, 6 and 8 as they reach an
existing desktop, GAPS D9, D10, D17, G11, G12, G14, G15, ADAPTIVE fixes 9, 10 and 20, BACKLOG M1
(in place), M8 (tooltips), S10 (shortcuts), S11 (versioned upgrades), TABLET T6 and 3.5, PEN 2 and 3.2,
EFFECTS 8.3 (install side). The login check itself is described in `gate.md`; this part adds to it.

## What changed

| Script | Change |
|---|---|
| `tools/device/fusion-config.sh` | in-place layout migration; the Windows-style shortcut set; `--pen`, `--pen-garage`, `--screens`, `--shortcuts`, `--keep-shortcuts`; text rendering; GTK file dialogs; the power service; `[TabBox] DelayTime`; the tablet KWin script; the on-screen keyboard key; tooltip delay 300 ms; `FusionConfigVersion` with the upgrade rule and a change list |
| `tools/device/fusion-restore.sh` | undoes all of the above (pen, services, keyboard key, shortcuts, files below `~/.local`, blur) |
| `tools/device/gate/plasma-fusion-gate.sh` | four more Fusion-only parts: `tablet`, `inputmethod`, `powerfx`, `pengarage` |
| `tools/device/backup-profile.sh` | never starts a Qt program without the session's display; more files |
| `tools/device/restore-profile.sh` | knows the new Plasma Fusion paths |
| `tools/device/tests/gate-unit.sh` | cases `t`, `t3`, `t4`, `t5` for the new gate parts |

## fusion-config.sh

```
fusion-config.sh [--install DIR] [--dry-run] [--light|--auto] [--reset-layout|--keep-layout]
                 [--hot-corner] [--fonts] [--pen [--pen-garage]] [--screens]
                 [--shortcuts|--keep-shortcuts]
```

The order of a run: backup, "My previous desktop", install, Global Theme, **layout migration**
(inside the plasmashell restart the run needs anyway), fonts and cursor (first run only), workspaces,
**shortcuts**, KWin, shell, lock screen, terminal and editor, **text rendering**, **GTK file
dialogs**, **power tiers**, **pen**, **screens**, login check, **configuration version**.

### Configuration version and the upgrade rule (BACKLOG S11)

`plasmafusionrc [Config] FusionConfigVersion` is `2` after this run. A HOME without the key is
version 1 when an earlier Plasma Fusion configured it (the Global Theme is `org.plasmafusion.*` or
`[Setup] FontsAndCursor=done`), else 0 (first run).

Every setting the script owns goes through `managed_key FILE GROUP KEY VALUE PREVIOUS...`:

- version 0 (first run): set;
- otherwise set only while the key is unset or still holds a value an earlier release wrote
  (`PREVIOUS`); a value the user chose is kept and reported.

So a rerun no longer resets a setting the user changed (before, every run wrote every key again).
The tooltip delay moves from 600 to 300 ms only where it still reads 600.

On an upgrade (version 1 to 2) the changed and the kept settings are written to
`~/.local/state/plasma-fusion/config-changes`, for the settings module's "What changed" page:

```
# Plasma Fusion configuration upgrade 1 -> 2, 2026-09-30T04:02:11Z, backup /home/test/.local/state/plasma-fusion/backup-...
changed	plasmarc	PlasmaToolTips	Delay	600	300
kept	plasmanotifyrc	Notifications	PopupTimeout	8000	5000
changed	kwinrc	TabBox	DelayTime	__plasma_fusion_unset__	120
```

Tab-separated: status, file, group (nested groups joined by `/`), key, old value, new value;
`__plasma_fusion_unset__` means "not set". Reverting a line: write the old value back (or delete the
key for the unset marker) with `kwriteconfig6 --notify`.

Settings under the rule: `[TabBox]` and `[TabBoxAlternative]` switcher keys, `[TabBox] DelayTime`
(new, 120), blur strength/noise/saturation, `BorderSizeAuto`, `[Plugins]` script keys (snap,
attach, tablet, sheet), `[Outline] QmlPath`, `[Wayland] InputMethod`, tooltip delay, OSD,
notification position and timeout, `krunnerrc FreeFloating`, lock-screen wallpaper, Konsole profile,
Kate/KWrite colour theme, the three `Xft*` keys. Options the user passes each time (`--light`,
`--auto`, `--hot-corner`) and the Global Theme defaults stay plain writes.

### Layout migration (an existing Plasma Fusion layout)

A fresh layout comes from the Global Theme's layout script (LAYOUT-1). An existing one (the real
session since round 2) is migrated in place, so panels, pins, cards and their positions stay. It
runs only in the default layout mode, when the layout is a Plasma Fusion one and a change is due;
plasmashell is stopped (it writes the layout file when it quits), the files are edited with
`kwriteconfig6`, and it starts again: one restart for the whole run.

| Change | Only when |
|---|---|
| desktop containment `org.kde.desktopcontainment` or `org.kde.plasma.folder` becomes `org.plasmafusion.desktop` (Folder View with the tablet home screen, TABLET2 H1, `docs/parts/desktop.md`; Folder View's keys, so applets and their `ItemGeometries*` keys stay); without that package `org.kde.desktopcontainment` becomes `org.kde.plasma.folder` (desktop icons, BACKLOG M1), and a desktop naming the missing package becomes `org.kde.plasma.folder` | the plugin is another of the three |
| the `[General]` keys below | the plugin was `org.kde.desktopcontainment` (a Folder View keeps its own) |
| `[General]` `url=desktop:/ sortMode=-1 arrangement=1 alignment=0 iconSize=2 popups=false toolTips=false selectionMarkers=true useTypeAhead=true previewPlugins=` (the installed ones of imagethumbnail, jpegthumbnail, svgthumbnail, gsthumbnail, opendocumentthumbnail, ffmpegthumbs) | per key, when the key is not set |
| portrait card positions `ItemGeometries-<H>x<W>` and `ItemGeometriesVertical`: the first two cards side by side under the bar, right-aligned on the 16 px grid, the rest under the right one (the CPU/memory card hides itself in portrait, CARD-2) | neither key exists; sizes from the landscape positions; screen size from the shell |
| top bar `plasmashellrc [PlasmaViews][Panel <id>] panelOpacity` 2 (translucent) becomes 0 (adaptive: solid next to maximized windows, decision 5) | it is still 2 |
| tray: `org.kde.plasma.vault`, `org.kde.plasma.devicenotifier`, `org.kde.kscreen`, `org.kde.plasma.printmanager`, `org.kde.plasma.manage-inputmethod` added to `hiddenItems` and `disabledStatusNotifiers` (no expander arrow; quick settings has its own keyboard button) | missing from the list |
| every app menu `[Configuration][Appearance] allScreens=false` (decision 8) | the key is not set |
| pen widget `org.plasmafusion.pen` added to the top bar between the tray and quick settings (next free applet id, `AppletOrder`) | the widget is installed and not in the bar |

The landscape card positions are not touched. After the 4/3 scale change the shell reads
`ItemGeometries-1440x900`, which does not exist, and falls back to `ItemGeometriesHorizontal`
(`x=1232`, 16 px from the right edge at 1440 px). LAYOUT-1 owns card geometry for fresh layouts;
if its portrait rule differs, the migration follows it (see Needs).

### Shortcuts (owner decision 6)

Applied once per configuration version (`--shortcuts` again, `--keep-shortcuts` never). Every other
action holding one of these keys loses it; each change is recorded in the backup's `shortcuts`
file, so `fusion-restore.sh` gives every key back.

| Key | Target (kglobalaccel component / action) |
|---|---|
| Meta+Space, Meta+S, Alt+Space, Alt+F2, Search (KRunner's own `_launch` keys) | `plasmashell` / `activate application launcher`: the shell activates the launcher on the active screen, exactly as for Meta |
| (KRunner) | `org.kde.krunner.desktop` `_launch` and `RunClipboard` keep no key, so nothing starts KRunner |
| Meta+A | the quick-settings widget's own "activate widget <id>" (widget API, as before) |
| Meta+N | `org.plasmafusion.notifications.desktop` / `_launch`: a desktop file in `~/.local/share/kglobalaccel/` (how System Settings adds a command shortcut) that writes the quick-settings widget's `[General] openRequest = "notifications:<ms>"` through `evaluateScript` (`busctl`) |
| Meta+Up / Meta+Down | `kwin` / `Window Maximize` (a toggle in KWin 6.7.5) / `Window Restore` (Meta+PgUp and Meta+Backspace stay) |
| Meta+Alt+Up / Meta+Alt+Down | `kwin` / `Window Quick Tile Top` / `Bottom` (`Switch Window Up/Down` lose them) |
| Meta+Tab | `kwin` / `Overview` (Meta+W stays; `Walk Through Windows` keeps Alt+Tab) |
| Meta+Alt+1..9 | `plasmashell` / `activate task manager entry 1..9` (the dock's `activateTaskAtIndex`); Meta+5..9 lose them |
| Meta+1..4 | `kwin` / `Switch to Desktop 1..4` (unchanged) |
| Meta+Shift+W (with `--pen`) | the pen widget's "activate widget <id>", only when free |

Widget keys (quick settings, pen) are also set on later runs when the widget has none (a layout
rebuild drops them; a dead entry of a dropped widget is cleared first), but then only when the key is
free. With `--keep-shortcuts` quick settings keeps Meta+N, as before.

### Other settings

- **Text rendering** (GAPS D9, fix 20): `~/.config/fontconfig/fonts.conf` gets KXftConfig's four
  `<match target="font">` assign edits (rgba `none`, hintstyle `hintslight`, hinting `true`,
  antialias `true`), other rules in the file kept; `kdeglobals [General] XftAntialias=true`,
  `XftHintStyle=hintslight`, `XftSubPixel=none`; `refreshFonts`. This is what System Settings >
  Fonts writes (plasma-workspace `kcms/fonts`). Fedora's
  `/etc/fonts/conf.d/10-sub-pixel-rgb-for-kde.conf` turns subpixel colours on; the user file is read
  later (`50-user.conf`) and wins, for Qt and GTK alike (both use fontconfig; kde-gtk-config 6.7.5
  does not handle these keys). Programs started afterwards use it; plasmashell after its restart.
  Qt Quick text drawn with distance fields (plain `Text`, the shell's labels) does not go through
  fontconfig: on desktop GL it uses subpixel antialiasing by default (qtdeclarative
  `qsgdefaultcontext.cpp`), which gave the top bar's colour fringes. The session env file (below)
  sets `QSG_DISTANCEFIELD_ANTIALIASING=gray` from the next login.
- **Session environment** (G12, fix 20): `~/.config/plasma-workspace/env/plasma-fusion-session.sh`
  (startplasma sources it at login and passes it to systemd and D-Bus activation; it only sets
  variables) exports `GTK_USE_PORTAL=1` and `QSG_DISTANCEFIELD_ANTIALIASING=gray`. GTK programs
  that use GTK's native file chooser (`GtkFileChooserNative`) then open the KDE file dialog through
  the portal; a program that builds its own `GtkFileChooserDialog` keeps GTK's dialog (Xournal++
  1.3.7's Open dialog does).
- **Window switcher**: `kwinrc [TabBox] DelayTime=120` (KWin's default 90).
- **Tablet KWin script**: `[Plugins] plasmafusion-tabletEnabled=true` when installed.
- **Tablet navigation effect** (TABLET2 N1): `[Plugins] plasmafusion_navigationEnabled=true` when the
  plasma-fusion-navigation package is installed, then loaded through `org.kde.kwin.Effects.loadEffect`
  (KWin's reconfigure does not load a newly enabled effect; private session `n5`: unset -> true, loaded).
- **On-screen keyboard** (T6): in laptop posture `kwinrc [Wayland] InputMethod=` (empty) unless the
  user chose another input method; in tablet posture left alone. Quick settings switches it with the
  posture afterwards. `plasmakeyboardrc [General] diacriticsPopupEnabled=false` (TABLET2 P0):
  plasma-keyboard 6.7 shows an accent pop-up when a physical key is held 600 ms while it runs,
  which broke password entry for users (Fedora discussion 194845); the on-screen keys keep their
  long-press accents. The file is in the backup (`fusion-restore.sh` removes it if it was absent;
  private session `cfg1`: set, unchanged on a second run, removed by restore).
- **Tooltips** (M8): `plasmarc [PlasmaToolTips] Delay=300`.
- **Title bars**: every run applies the Global Theme (`plasma-apply-lookandfeel -a`), which removes
  the user's own `kwinrc [org.kde.kdecoration2] library` and `theme`, so the theme's Aurorae value
  comes back. When the compiled decoration was chosen (DEPLOY-1 step 7) and is installed, the script
  chooses it again after the apply (review finding; before, the next run after DEPLOY-1 would have
  switched the title bars back to Aurorae).
- **Panel thickness check** now uses the layout script's text scale (it forced 34 px before) and
  leaves the panels alone in tablet posture (the tablet script owns them there).

### Power tiers (POWER-1's service)

`install_user_service plasma-fusion-powerfx.service powerfx`: the unit is looked for as
`plasma-fusion/powerfx/plasma-fusion-powerfx.service` in the data directories (the build or the
system package), else `packages/powerfx/` next to the tools. It is copied to
`~/.config/systemd/user/`; when its `ExecStart` names `%h/.local/libexec/plasma-fusion/<program>`,
that program is copied there from the unit's directory (mode 0755). The `graphical-session.target.wants`
link is written as `systemctl --user enable` writes it; then `daemon-reload` and `restart` only in
this session's own systemd manager (its environment names this session bus), so a private test
session never touches the logged-in user's manager. The unit is recorded in the backup's `services`.

### Pen (`--pen`, `--pen-garage`)

`tools/pen/pen-defaults.sh --no-install` (nothing installed from here; Xournal++ is recommended by
the package); its backup directory is recorded in the backup (`pen-backup`). Then Meta+Shift+W for
the pen widget. `--pen-garage` (only after hand check V2 showed the garage events) installs
`plasma-fusion-pen-garage.service` the same way as the power service (from `plasma-fusion/pen/`) and
sets `plasmafusionrc [Pen] GarageService=true`.

### Screens (`--screens`)

Runs `contents/layouts/ensure-topbars.js` of the chosen Global Theme in plasmashell (a top bar on
every screen, decision 8) and prints what it prints.

### Decision 7

No code: the owner named no apps, so KMail, KOrganizer and Akonadi stay. When apps are named, the
pins go into the dock's `launchers` and `~/.config/autostart/org.kde.kalendarac.desktop` gets
`Hidden=true` (with a backup entry), both in this script.

## fusion-restore.sh

In addition to what `gate.md` describes, for the chosen backup and every later run, newest first:

1. shortcuts through kglobalaccel (the Windows-style set included); the Meta+N component is
   unregistered when the restored state has no desktop file for it;
2. pen defaults: `pen-defaults.sh --restore <pen backup>` (KWin reads them at once);
3. user services: stopped in this session's own manager (`plasma-fusion-powerfx` gives the
   power-tier values back in `ExecStopPost=... --apply full`); without a manager its program runs
   `--apply full` itself;
4. the backup's `[Wayland] InputMethod` told to KWin with `kwriteconfig6 --notify` (a restored file
   alone does not start or stop the keyboard);
5. files: `~/.config` as listed in the manifest (layout, plasmashellrc, kwinrc, fonts.conf, the
   portal env file, units and their links) and the new `present-file`/`absent-file` entries below
   `$HOME` (`~/.local/share/kglobalaccel/org.plasmafusion.notifications.desktop`,
   `~/.local/libexec/plasma-fusion`);
6. `daemon-reload`, KWin reconfigure, blur loaded again unless the restored kwinrc turns it off,
   `fc-cache`, plasmashell started.

## Login check additions (gate.md)

| Part | "On" when | Switched off (Fusion not the Global Theme) |
|---|---|---|
| `tablet` | `kwinrc [Plugins] plasmafusion-tabletEnabled=true` | written `false` (not removed: the script's EnabledByDefault is not the check's to know) |
| `navigation` | `kwinrc [Plugins] plasmafusion_navigationEnabled=true` | written `false`; also after a KWin or Qt update (version-checked like the compiled decoration) |
| `inputmethod` | user `kwinrc [Wayland] InputMethod` is empty or `/usr/share/applications/org.kde.plasma.keyboard.desktop` (the values the Fusion policy writes) | the user key removed, so Fedora's default keyboard returns; another input method is never touched |
| `powerfx`, `pengarage` | `~/.config/systemd/user/graphical-session.target.wants/plasma-fusion-{powerfx,pen-garage}.service` exists | the link moved to `~/.local/state/plasma-fusion/gate/saved/` (no systemd call at login: startplasma reloads the manager after the check, so the service does not start at this login) |

They follow the existing theme-part rules: recorded first, switched off once (a part the user turns
on again stays on), turned back on at the next Fusion login or by `fusion-config.sh` (`deploy`),
and only while the value is still the one written. A link comes back only when the unit file is
still installed. Link records are checked against the one allowed path, so a hand-edited record
cannot move another file.

## backup-profile.sh

It started `kscreen-doctor -j` and `plasmashell --version` unconditionally; over SSH without
`WAYLAND_DISPLAY` both aborted (2026-09-30 02:56Z, `kscreen.json` empty). Now:

- the display comes from the plasmashell on this user's own session bus (`/run/user/UID/bus`
  unless `DBUS_SESSION_BUS_ADDRESS` names another), as `fusion-config.sh` does; `kscreen-doctor -j`
  runs only when that Wayland socket exists (15 s limit), else `kscreen.json` holds an error note
  (`~/.config/kwinoutputconfig.json`, which has the scale, is always in the tarball);
- the Plasma version comes from `rpm -q plasma-workspace` (fallback `plasmashell --version` with
  `QT_QPA_PLATFORM=offscreen`);
- more paths: `plasmafusionrc`, `krunnerrc`, the Plasma Fusion user units and their wants links,
  `libwacom`, `~/.local/share/kglobalaccel`, `~/.local/libexec/plasma-fusion`;
- its work directory is below the destination, not in `/tmp`.

## Commands for DEPLOY-1

```
# step 2 (over SSH is fine now)
~test/.local/state/plasma-fusion/deploy-<rev>/tools/device/backup-profile.sh
# step 4, decision 1 (exactly 4/3), in the real session's environment (from plasmashell's environ)
kscreen-doctor output.eDP-1.scale.1.3333333
# step 6
deploy-<rev>/tools/device/fusion-config.sh --install deploy-<rev>/home --pen [--screens]
# undo step 6
deploy-<rev>/tools/device/fusion-restore.sh <the backup it printed>
```

## Verification

Private sessions on the ThinkPad (1920 x 1200 at 4/3 unless noted), `build/o1dv/`; builder `o1dv`
until 04:19Z, then the lead (review notes `build/o1dv/REVIEW.md`). Seeds: a clean HEAD stage, stand-ins
for the parts other lanes are still building (tablet script, powerfx, pen widget and garage,
ensure-topbars.js), the deployed d4afee8 tools (upgrade path) and these tools.

- Laptop: `tests/gate-unit.sh` 117/117, `tests/gate-stub.sh` 13/13 (both now accept a relative
  scratch path); `bash -n` and `shellcheck -S warning` clean.
- Upgrade from the deployed d4afee8 configuration (`o1dv-up`, `o1dv-up3`): dry run without changes
  and without a second backup; 81 changes in 12-13 s; the panels, pins and cards kept, the desktop a
  Folder View with the icons in the left column, the pen widget added between the tray and quick
  settings, portrait card positions written, the top bar adaptive; a user-changed value kept and
  listed in `config-changes`; FusionConfigVersion 2; every decision-6 key bound exactly once in
  `kglobalshortcutsrc`; a second run changes 3 things and neither re-applies the key set nor
  migrates again; `fusion-restore.sh` gives the shortcuts and the layout back.
- Keys (screenshots and window probes): Meta+Space, Meta+S, Alt+Space and Alt+F2 open the launcher
  (KRunner never starts), Meta+A quick settings, Meta+Up maximizes, Meta+Down restores,
  Meta+Alt+Up tiles to the top half (with KWin's 6 px tile gap), Meta+Tab Overview, Meta+Alt+1 the
  first dock app, Meta+1 workspace 1, Meta+Shift+W the pen widget. Meta+N: see the open items.
- Text: with the session environment, the top bar's clock text has no colour fringes (0 strongly
  coloured pixels in the clock box against 475 before, `o1dv-up` run 2, landscape; portrait not
  measured). A GTK 3 `GtkFileChooserNative` opens the KDE file dialog
  (`org.freedesktop.impl.portal.desktop.kde`); Xournal++'s Open dialog stays GTK's own (above).
- Upgrade from a phase-1 (0918220) configuration with one user-changed key (`o1dv-u0`): the user's
  tooltip delay 800 kept, an unchanged Fusion value stays, the new keys added, the desktop migrated,
  quick settings on Meta+A. M24: fonts, cursor and button side survive Light and Dark;
  plasmafusionrc untouched by the theme switches.
- Fresh HOME configured from outside the session, as over SSH (`o1dv-fr`, `o1dv-fr2`): the session
  environment taken from plasmashell; the garage unit with `--pen-garage`; a matching login changes
  nothing and the login environment has `GTK_USE_PORTAL=1`; M27 (faked KWin and kscreenlocker
  versions): the stock lock screen, the Aurorae title bars, one notification, none at the second
  login, and the next matching login gives both back ("lockscreen back on; decoration back on",
  after the title-bar fix above); Breeze chosen: powerfx and the garage are not started at the next
  login, the tablet script off, the keyboard key removed; Plasma Fusion again: all back on; the
  restore gives the shortcuts, the layout and the pre-Fusion files back, powerfx and the gate stub
  gone. Remaining differences after the restore are Plasma's own GTK colour files
  (`gtk-3.0/colors.css`, `window_decorations.css`, `assets`, written by Plasma's GTK integration
  on every colour change).
- No core dumps from these sessions.

Open items:
- Meta+N (the notification list): the component's desktop file is now installed executable (KDE
  refused to run it without the bit), but in a private session neither the key nor
  `invokeShortcut` launches it, while its command run directly works. Private sessions have no
  systemd user manager on their bus, the likely difference. To check by hand in the real session at
  DEPLOY-1; if it fails there, a KWin script shortcut that calls `evaluateScript` replaces it.
- Portrait fringe measurement and the real GTK apps the owner uses (hand checks).

## Needs from other parts

(See the report; kept in sync.)

## Measuring the glass's battery cost (tools/device/power-ab.sh, 2026-10-01)

Research D-desktop found no data on the battery cost of blur; E-phone ranks battery life first. In the
Plasma session, on battery, run `tools/device/power-ab.sh [MINUTES=10] [BLOCKS=8]` and leave the
machine alone: KWin's blur effect alternates on and off per block (nothing else changes), sleep and
screen-off are inhibited (kde-inhibit), battery power is sampled every 10 s (power_now, or current x
voltage), and the effect is restored at the end. `summary.txt`: mean watts with and without blur
(each block's first minute skipped) and the difference. Plugging in stops the run. Test mode:
`PF_POWER_AB_FAKE=DIR` (a fake power_supply tree; the effect is not touched).
