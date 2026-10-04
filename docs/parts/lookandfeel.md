# Global Themes, desktop layout, splash and session configuration

Status: built, reviewed and checked in private virtual sessions on the ThinkPad (1440x900), dark
and light, integrated with every other part as built on 2026-09-29 (see "Review" at the end).
Last edited 2026-09-29.

## What it is

| Id | Name | Contents |
|---|---|---|
| `org.plasmafusion.dark.desktop` | Plasma Fusion Dark | defaults, layout, splash, log-out screen, previews |
| `org.plasmafusion.light.desktop` | Plasma Fusion Light | same; only the defaults and previews differ |

Both are config-only `Plasma/LookAndFeel` packages plus the splash and log-out QML. The desktop
layout, splash and log-out screen are identical in both, so the automatic light/dark switch (which
applies appearance only) never changes the layout. `tools/device/fusion-config.sh` sets everything a Global Theme cannot;
`tools/device/fusion-restore.sh` undoes it.

## Files

| Path | What |
|---|---|
| `packages/look-and-feel/org.plasmafusion.{dark,light}.desktop/metadata.json` | package metadata |
| `packages/look-and-feel/org.plasmafusion.{dark,light}.desktop/contents/defaults` | the values the Global Theme applies |
| `packages/look-and-feel/org.plasmafusion.{dark,light}.desktop/contents/previews/` | `preview.png` 600x375, `fullscreenpreview.jpg` 1440x900, `splash.png` 300x188 (committed; made by `generators/look-and-feel/previews.py` from the review screenshots of the integrated desktop and the splash) |
| `packages/look-and-feel/common/contents/layouts/org.kde.plasma.desktop-layout.js` | top bar, dock, desktop cards (copied into both packages) |
| `packages/look-and-feel/common/contents/layouts/defaults` | title-bar buttons and maximized-window borders (layout defaults) |
| `packages/look-and-feel/common/contents/splash/Splash.qml` | log-in splash (Splash board) |
| `packages/look-and-feel/common/contents/logout/Logout.qml`, `LogoutButton.qml`, `timer.js` | log-out / shut-down screen: Plasma 6.7.5's Breeze files, with the veil in the Complementary background instead of black (readable in Plasma Fusion Light) |
| `generators/look-and-feel/splash_background.py` | renders `splash/images/background.png` (the board's blurred Dusk Ridge layer) at build time |
| `generators/look-and-feel/previews.py` | previews from any 16:10 desktop capture and a splash capture |
| `generators/look-and-feel/tests/` | test tooling only, not installed: `make-seed.sh`, `session-common.sh`, `scenario-full.sh`, `scenario-relogin.sh`, `merge-kdedefaults.py`, `dump-layout.js`, `render-splash.py` |
| `tools/build.d/60-lookandfeel.sh` | writes `$STAGE/.local/share/plasma/look-and-feel/org.plasmafusion.{dark,light}.desktop/` |
| `tools/device/fusion-config.sh` | session configuration (run inside the user session) |
| `tools/device/fusion-restore.sh` | undoes `fusion-config.sh` from its backup |

Build needs Python 3 and Pillow only; two builds give identical files.

## contents/defaults

Written by Plasma into `~/.config/kdedefaults/<file>` (the layer startplasma puts in
`XDG_CONFIG_DIRS`), the user's own key is reverted. Dark / light values:

| File, group | Key | Dark | Light |
|---|---|---|---|
| kdeglobals [KDE] | widgetStyle | Breeze | Breeze |
| kdeglobals [General] | ColorScheme | PlasmaFusionDark | PlasmaFusionLight |
| kdeglobals [Icons] | Theme | PlasmaFusion-Dark | PlasmaFusion |
| plasmarc [Theme] | name | plasma-fusion-dark | plasma-fusion-light |
| kwinrc [org.kde.kdecoration2] | library, theme, NoPlugin | org.kde.kwin.aurorae.v2, `__aurorae__svg__PlasmaFusionDark`, false | …`PlasmaFusionLight` |
| kwinrc [org.kde.kdecoration2] | BorderSize | None (used once `BorderSizeAuto=false`, set by fusion-config.sh) | None |
| kwinrc [WindowSwitcher] | LayoutName | org.plasmafusion.switcher | same |
| kwinrc [Windows] | Placement | Centered (layout setting) | same |
| ksplashrc [KSplash] | Theme | org.plasmafusion.dark.desktop (both variants) | same |
| [Wallpaper] | Image | PlasmaFusion | same |
| [Desktop][org.kde.plasma.desktop] | Containment | org.kde.desktopcontainment (widgets only, no desktop icons) | same |

`contents/layouts/defaults`: kwinrc [org.kde.kdecoration2] ButtonsOnLeft=M, ButtonsOnRight=IAX;
[Windows] BorderlessMaximizedWindows=false (applied only together with the layout).

Fonts and cursor are NOT in the Global Themes (changed 2026-09-30, ADAPTIVE.md fix 1). Every
theme apply, including Plasma's automatic light/dark switch and the quick-settings Dark tile
(AppearanceSettings), writes each value the theme provides to `kdedefaults` and reverts the
user's own key (`KLookAndFeelManager::writeNewDefaults`), so fonts or a cursor in the theme would
undo the user's font size or cursor at every switch. `tools/device/fusion-config.sh` sets them
once instead (section 1b, marker `plasmafusionrc [Setup] FontsAndCursor=done`; `--fonts` sets
them again): kdeglobals [General] font, menuFont, toolBarFont
`Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0` (13 px), smallestReadableFont
`Manrope,9,-1,5,400,…` (12 px), [WM] activeFont `Manrope,10.5,-1,5,800,…` (14 px ExtraBold), and
the cursor theme PlasmaFusion-cursors through `plasma-apply-cursortheme`. Sessions configured by
an earlier version keep Manrope in `kdedefaults` (a theme apply never clears that file), and
KConfig does not write a user key equal to it, so nothing changes for them. The Qt 6.11 font
strings were printed by PySide6 6.11.2 `QFont.toString()` on the build laptop.
A name that is not installed is skipped by Plasma (the old value stays), so the Global Theme can
be applied before every part exists.

## Desktop layout (layout script)

Runs on the first login of a user whose `kdeglobals [KDE] LookAndFeelPackage` is a Fusion theme
and has no `plasma-org.kde.plasma.desktop-appletsrc`, on `plasma-apply-lookandfeel -a <id>
--resetLayout`, and when "Desktop and window layout" is ticked in System Settings. It replaces the
existing panels.

| Piece | Settings | Widgets (fallback when a Fusion widget is not installed) |
|---|---|---|
| Top bar | `location top`, `height 34`, `floating false`, `lengthMode fill`, `hiding none`, `opacity adaptive` (solid next to a maximized window, decision 5) | `org.plasmafusion.appname` (else `org.plasmafusion.launcher` as a 32 px pill, else Kickoff), `org.kde.plasma.appmenu` (`allScreens=false`: the menu of that screen's window), panelspacer, `org.plasmafusion.clockpill` (else pager + digital clock "ddd d MMM" beside the time), panelspacer, `org.kde.plasma.systemtray`, `org.plasmafusion.pen` (when installed), `org.plasmafusion.quicksettings` |
| Top bars on the other screens | as above | app name, appmenu (`allScreens=false`), clock pill; no tray, quick settings or dock (decision 8) |
| Dock | `location bottom`, `height 72` (the dock plate; the Plasma style keeps the 16 px headroom above it in the panel window. 88 with the headroom frame until INT-1), `floating true`, `lengthMode fit`, `alignment center`, `hiding dodgewindows`, `opacity translucent` | `org.plasmafusion.launcher` with `[General] buttonStyle=hidden` when the app-name widget holds the top-left corner (the dock finds it in its own panel for Start; Meta finds it in any panel), then `org.plasmafusion.dock` (else Kickoff when there is no Fusion launcher, and `org.kde.plasma.icontasks`) |
| Desktop | The Plasma Fusion desktop (`org.plasmafusion.desktop`, `docs/parts/desktop.md`: Folder View on the laptop, the home screen in tablet posture; plain `org.kde.plasma.folder` is accepted, BACKLOG M1): `url desktop:/`, `arrangement 1` (columns), `alignment 0` (from the left), `iconSize 2`, `sortMode -1` (free placement), `popups false`, `toolTips false`, `selectionMarkers true`, `useTypeAhead true`, previews for the installed image/SVG/PDF/office/video thumbnailers; `org.kde.image` wallpaper plugin, image left unset (the Global Theme's `PlasmaFusion` default, light/dark by the Plasma style) | the weather, calendar and system cards, see below |

System tray: when the quick-settings widget is installed, `[General] hiddenItems` =
`org.kde.plasma.networkmanagement, org.kde.plasma.volume, org.kde.plasma.battery,
org.kde.plasma.bluetooth, org.kde.plasma.brightness, org.kde.plasma.notifications,
org.kde.plasma.keyboardlayout, org.kde.kdeconnect, org.kde.plasma.clipboard,
org.kde.plasma.mediacontroller` (the ten ids of docs/parts/shell-quicksettings.md: the pill, tiles
and bell replace the first six, the widget draws the EN badge, phone and clipboard buttons and the
media card itself). They stay loaded (notification server and popups, network secrets, battery
warnings, Klipper, KDE Connect) but sit in the tray's hidden section. Five passive items are also
hidden and disabled as status notifiers, so the tray has no expander arrow: `org.kde.plasma.vault`,
`org.kde.plasma.devicenotifier`, `org.kde.kscreen`, `org.kde.plasma.printmanager` and
`org.kde.plasma.manage-inputmethod` (quick settings has its own keyboard button).

Desktop cards: the Plasma Fusion weather, calendar and system cards (`docs/parts/desktop-cards.md`),
each with the stock widget as fallback when the Fusion one is not installed, on the primary screen.
Their places are written for each screen shape (`ItemGeometries-WxH` for the screen's landscape and
portrait sizes and for 1440x900 / 900x1440, plus the `ItemGeometriesHorizontal` / `Vertical`
fallbacks): landscape a right-hand column 16 px under the top bar; portrait the first two side by
side under the bar and the rest below. The column keeps clear of the top bar and the dock's 104 px
area; when it does not fit, the system card goes first. Icons fill from the left, so they never
sit under a card.

## Splash

`contents/splash/Splash.qml`, same file in both packages; ksplashrc points both at the dark
package. Board values: background `#0b0e1b` with the pre-blurred Dusk Ridge layer
(`images/background.png`, 1920x1200, generated from the board geometry: blur 26 px, scale 1.08,
opacity 0.28; pixel check against the render within 1-2 levels), orbit rings r 120 / 190 at white
6 % / 4 %, three dots (10/8/8 px, `#5b9dff`, `#f2a65a`, `#3cc4b0`) that start at the board
positions and travel together along the outer ring (one turn in 16 s, so their spacing stays as
drawn and they never overlap), the three-circle logo (46 px radius, colours as drawn on the board
with its screen blend), "Welcome back, <first word of the real name, else the login name>" in
Space Grotesk 30 px / 600, 260x4 progress bar (`#5b9dff` on white 10 %), a 13 px `#8f98b3` status
line, and the "Plasma Fusion" mark bottom-left (13 px / 700, 40 px, 32 px). Manrope and Space
Grotesk weights go on the `wght` axis with a Normal font weight (Qt otherwise draws a synthetic
bold over the variable fonts' named instances); without the fonts the fallback gets a plain
weight. Content fades in at stage 2. ksplashqml counts six steps (initial and, on Wayland, the
window manager at once, then startplasma, kcminit, ksmserver; the desktop closes it); the bar
shows the finished share, (stage-1)/5 (80 % while the session is restored), and creeps towards
the next step while one takes long. Animations stop when Plasma's animation speed is set to
instant. Imports only QtQuick, Kirigami and org.kde.coreaddons (KUser).

## Log-out screen

Plasma 6.8 no longer reads the Global Theme's `contents/logout/`: the log-out greeter loads the
shell package's `logout/Logout.qml` (plasma-workspace 3729037a). Plasma Fusion therefore carries
the same files in the `org.plasmafusion.lockshell` shell package (staged from
`packages/look-and-feel/common/contents/logout/` by `tools/build.d/90-lockscreen.sh`), and
`lockscreen-enable.sh` writes a per-user D-Bus service override that starts the greeter
(`ksmserver-logout-greeter`, D-Bus name `org.kde.LogoutPrompt`) with
`PLASMA_DEFAULT_SHELL=org.plasmafusion.lockshell`, so Plasma 6.8 shows Plasma Fusion's log-out
screen as well. Plasma 6.7's greeter still reads the Global Theme and is unaffected. The gate
moves the override aside together with the KWin drop-in on untested Plasma series and puts it
back with it.

`contents/logout/` (both packages): Plasma 6.7.5's Breeze `Logout.qml`, `LogoutButton.qml` and
`timer.js` with one change. Breeze draws the Complementary colours on a black 85 % veil; Plasma
Fusion Light has the board's light Complementary set (`#f7f8fb`, text `#141827`), which made the
Breeze screen unreadable (foundation evidence `session-light/light-10-logout.png`). The veil now
takes the Complementary background: dark in Plasma Fusion Dark, light in Plasma Fusion Light. The
greeter contract (context properties, signals, keyboard navigation, count-down) is unchanged;
qmllint reports only the same unqualified context-property accesses as the upstream file. There is
no board for this screen.

## tools/device/fusion-config.sh

Run inside the user's Plasma session: from Konsole, or over SSH with only the session's
`DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus` and `XDG_RUNTIME_DIR=/run/user/<uid>`
(without a display in its environment it takes `WAYLAND_DISPLAY`, `XDG_CONFIG_DIRS` and the other
session variables from the running plasmashell, so `plasma-apply-lookandfeel` works; a
plasmashell it restarts outside systemd gets the old shell's environment).

```
tools/device/fusion-config.sh --install stage/home --dry-run   # print every change, change nothing
tools/device/fusion-config.sh --install stage/home             # back up, install the build, Plasma Fusion Dark
tools/device/fusion-config.sh                # Plasma Fusion Dark (build already installed)
tools/device/fusion-config.sh --light        # Plasma Fusion Light
tools/device/fusion-config.sh --auto         # also switch light/dark with the time of day
tools/device/fusion-config.sh --hot-corner   # top-left corner opens Overview (off by default)
tools/device/fusion-config.sh --reset-layout # always rebuild the panels (default: only when the
                                             # Fusion top bar and dock are not both present)
tools/device/fusion-config.sh --keep-layout  # appearance and settings only
```

`--install DIR` (a `tools/build.sh` HOME tree) replaces the earlier `rsync -a stage/home/ ~/`
step, after the backup: `DIR/.local/` is copied over `~/.local/` (packages, fonts, wallpapers,
themes), then every file under `DIR/.config/` (today the GTK files). A `gtk.css` that holds more
than Plasma's own `@import 'colors.css';` (and comments) is kept and only gets
`@import 'plasma-fusion.css';` after its colors.css import (foundation rule); a plain one is
replaced. Then `fc-cache -f` and `kbuildsycoca6`; a running plasmashell is restarted so updated
widgets load.

Before changing anything it copies to `~/.local/state/plasma-fusion/backup-<UTC stamp>/`:
kdeglobals, kwinrc, kglobalshortcutsrc, plasmarc, plasmanotifyrc, plasmashellrc,
plasma-org.kde.plasma.desktop-appletsrc, ksplashrc, kcminputrc, krunnerrc, kscreenlockerrc,
konsolerc, katerc, kwriterc, gtk-3.0/gtk-4.0 settings.ini, gtk.css and plasma-fusion.css,
xsettingsd/xsettingsd.conf, Trolltech.conf, the lock-screen drop-in
`systemd/user/plasma-kwin_wayland.service.d/plasma-fusion-lockscreen.conf`, every file the build
installs under `.config`, the kdedefaults/ folder and ~/.gtkrc-2.0 (`manifest` records which
existed), plus the workspaces (`desktops.json`, `rows`), the old keys of every shortcut it changes
(`shortcuts`), the workspaces it creates (`created-desktops`) and the previous Global Theme (`info`).

What it sets, in order (all idempotent; a second run reports only the theme re-apply):

1. Global Theme: `plasma-apply-lookandfeel -a <id>`; when the layout is rebuilt: apply, restart
   plasmashell (it reads the Global Theme's desktop type only at start), `plasma-apply-lookandfeel
   -a <id> --resetLayout`, restart plasmashell again (a system monitor created in a running shell
   shows its bars only after a restart, upstream race in its FullRepresentation.qml). plasmashell
   is restarted through `plasma-plasmashell.service` only when that unit is the shell on this
   session bus, otherwise with kquitapp6 + `setsid plasmashell` (output in
   `~/.local/state/plasma-fusion/plasmashell.log`). Without a running plasmashell it removes the
   appletsrc so the next start builds the layout. A panel that came up at another thickness is set
   back to 34 / 72 px (88 until INT-1; this is also what moves a deployed 88 px dock to the
   plain frame's 72 px on the next `fusion-config.sh` run).
   kdeglobals [KDE] `DefaultDarkLookAndFeel=org.plasmafusion.dark.desktop`,
   `DefaultLightLookAndFeel=org.plasmafusion.light.desktop`, `AutomaticLookAndFeel=false` (true
   with `--auto`); keys checked in plasma-workspace 6.7.5
   `kcms/lookandfeel/lookandfeelsettings.kcfg`.
2. Workspaces through `org.kde.KWin /VirtualDesktopManager`: the first four named Work, Design,
   Media, Chat (missing ones created with `createDesktop`, existing extra ones left alone), rows 1.
3. Shortcuts through kglobalaccel `setForeignShortcut` (KWin holds kglobalshortcutsrc, so the file
   is not edited): Meta+1..4 is removed from plasmashell `activate task manager entry 1..4` (their
   other keys stay) and added to kwin `Switch to Desktop 1..4` (next to Ctrl+FN and Meta+FN).
   Alt+Tab and Meta+Tab are left as KWin's defaults (both "Walk Through Windows"): the Fusion
   switcher has its own "This workspace / All workspaces" tabs (see 4).
4. kwinrc: [TabBox] and [TabBoxAlternative] LayoutName=org.plasmafusion.switcher, DesktopMode=0
   (KWin hands the switcher every window; it opens on "This workspace" and filters itself, its "All
   workspaces" tab needs the full list), HighlightWindows=false (no flash of a window the switcher
   skips); [Effect-overview] BorderActivate=9 (7 with `--hot-corner`; 9 = no edge, 7 = top-left,
   KWin globals.h); [Effect-blur] BlurStrength=13, NoiseStrength=0, Saturation=140;
   [org.kde.kdecoration2] BorderSizeAuto=false; [Plugins] plasmafusion-snapEnabled=true and
   plasmafusion-attachEnabled=true (each only when the script is installed; run again after
   installing it), sheetEnabled=true (dialogs slide out of their parent); [Outline]
   QmlPath=kwin/scripts/plasmafusion-snap/contents/outline/outline.qml (the snap script's zone
   preview; KWin src/outline.cpp resolves it in the data directories) when that file is installed.
   Then `reconfigure`, `Scripting.start`, `reconfigureEffect blur/overview`. Tiling: a one-shot
   KWin script sets padding 6 on every screen and workspace root tile and splits the right column
   of the untouched 25/50/25 default top/bottom (the board's custom-zone layout); KWin stores it
   per workspace and screen UUID.
5. plasmarc [PlasmaToolTips] Delay=600; [OSD] Enabled=true, kbdLayoutChangedEnabled=true (plasmarc
   is ShellCorona's config, shellcorona.cpp:108); plasmanotifyrc [Notifications]
   PopupPosition=TopRight, PopupTimeout=5000 (notificationsettings.kcfg), [Jobs] PermanentPopups=false
   (file-copy pop-ups close after the timeout, progress stays in the history; 2026-10-01, research
   D-desktop complaint 15; only where unset, a user's own value is kept); krunnerrc [General]
   FreeFloating=true (KRunner centred, for the dock's Search button). Written with
   `kwriteconfig6 --notify`.
6. Lock screen: `tools/device/lockscreen-enable.sh` (the lock-screen part's drop-in, from the next
   login) when `org.plasmafusion.lockshell` is installed; kscreenlockerrc [Greeter]
   WallpaperPlugin=org.kde.image, [Greeter][Wallpaper][org.kde.image][General]
   Image=file://~/.local/share/wallpapers/PlasmaFusion/ when the wallpaper is installed.
7. Terminal and editor (foundation part): konsolerc [Desktop Entry] DefaultProfile=Plasma
   Fusion.profile; katerc and kwriterc [KTextEditor Renderer] Auto Color Theme Selection=false,
   Color Theme=Plasma Fusion Dark (the boards draw a dark terminal and code window in both
   variants; KTextEditor's automatic choice knows only Breeze).

The hot corner can be switched later without the script:
`kwriteconfig6 --file kwinrc --group Effect-overview --key BorderActivate 7` (9 = off), then
`qdbus-qt6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect overview`.

## tools/device/fusion-restore.sh

```
tools/device/fusion-restore.sh --list        # backups and the Global Theme before each
tools/device/fusion-restore.sh [--dry-run]   # newest backup taken before Plasma Fusion was applied
tools/device/fusion-restore.sh --latest      # undo only the last run
tools/device/fusion-restore.sh BACKUP_DIR
```

Restores the shortcuts (newest change first) through kglobalaccel, removes the workspaces the
run created and renames the rest, stops plasmashell, puts every backed-up file back (removing
files that did not exist, which also removes the lock-screen drop-in and the Plasma Fusion GTK
files), reloads systemd for the drop-in, KWin and effects, sends the palette/style/font change
signals and starts plasmashell (with the old shell's environment when run over SSH). The files
`--install` put under `~/.local` stay installed. Log out and in to finish (tiling padding is
held by the running KWin until then). The whole-profile snapshot tools `backup-profile.sh` /
`restore-profile.sh` remain the full safety net.

## Verification

First build (lf-* sessions), then the review (rlf-* sessions, see "Review"):

- Offline: `qmllint` of Splash.qml clean; Logout.qml / LogoutButton.qml give only the upstream
  file's unqualified context-property warnings; `node` syntax check of the layout script;
  `bash -n` and `shellcheck -S warning` on all scripts; PySide6 offscreen render of the splash
  with the project fonts (`tests/render-splash.py`), weights compared with render startup-2; splash
  background pixels within 1-2 levels of the render.
- Virtual sessions on the ThinkPad with every part built (`tests/make-seed.sh`,
  `tests/scenario-full.sh`, then `tests/scenario-relogin.sh` with seed `-`, the same HOME in a new
  session):
  - `--install --dry-run` changes nothing (no state folder); `--install` keeps a gtk.css with a
    rule of its own and adds the import, replaces a plain one;
  - dark: desktop type `org.kde.desktopcontainment`, top bar 34 px, dock 88 px
    floating/fit/centre/dodgewindows, cards at the rectangles above, tray hiddenItems (10), four
    workspaces, kwinrc keys as listed, lock-screen drop-in written, konsolerc/katerc/kwriterc set;
  - after a plasmashell restart as at login, and in the next session: top bar still 34 px;
  - second run: 1 change (theme re-apply); `--reset-layout` without a display in the environment
    (as over SSH) rebuilds the layout and the restarted shell runs;
  - light: layout kept, 1 change; log-out screen readable in dark and light;
  - `ksplashqml --test org.plasmafusion.dark.desktop`: stage screenshots;
  - fusion-restore.sh (without a display): stock Fedora panel, one "Desktop 1", original
    shortcuts, gtk.css files as before, drop-in removed;
  - plasmashell logs: only the upstream system-monitor TypeError in the shell that builds the
    layout (gone after the restart that follows).
- Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/lookandfeel/`
  (`review-*.png`, `review-logs/`; the earlier files of the first build are kept).

A virtual session is not started by startplasma, so `~/.config/kdedefaults` is not in its
`XDG_CONFIG_DIRS`: `tests/session-common.sh` exports it for everything the scenarios start,
restarts plasmashell with it (as a login would) and copies KWin's keys with
`tests/merge-kdedefaults.py`. The real session needs neither.

## Deviations from the boards

- Desktop cards: the Plasma Fusion cards follow the board (`docs/parts/desktop-cards.md`); only the
  stock fallbacks are larger (416 px wide; the stock calendar needs 21x14 grid units for its
  month view, the stock weather view 10 grid units of height). The column sits 16 px from the
  right edge and the top bar (board 22 px / 56 px from the top).
- The weather card shows "Configure…" until the user sets a location (no automatic location in
  6.7.5); the memory row shows used percent, not "6.1 / 16 GB", and the stock bars face draws
  each bar above its label, not below.
- A CPU/memory card created in a running shell is empty until plasmashell restarts (upstream race:
  FullRepresentation.qml reads `Plasmoid.faceController` before `SystemMonitor::init` creates it,
  "TypeError: Cannot read property 'fullRepresentation' of null"). fusion-config.sh restarts the
  shell; after a Global Theme applied from System Settings with the layout, or on a first login,
  it shows from the next login.
- Splash status line: "Starting Plasma" plus a per-stage note instead of "restoring 4 windows"
  (no API reports restored windows). The greeting uses the first word of the account's real name,
  or the login name as it is written (the ThinkPad's `test` account has no real name). The board
  is a still; the dots' motion (together, one turn in 16 s) is this part's choice.
- The tray shows its expander arrow, because the replaced items are hidden, not removed.
- Alt+Tab and Meta+Tab both open the Fusion switcher on "This workspace"; "All workspaces" is the
  switcher's tab (A key or click). The board shows no Meta+Tab.
- Log-out screen: no board; Breeze layout with the Fusion colours and a Complementary veil.
- Without the clock-pill widget the fallback clock uses the digital clock's automatic font size
  (larger than the board's 13 px).

## Needs from other parts

- Desktop cards: done (`org.plasmafusion.weathercard`, `calendarcard`, `systemcard`,
  `docs/parts/desktop-cards.md`); the `CARDS` table keeps the stock widgets as fallback.
- Window switcher / KWin part: fusion-config.sh sets [TabBox]/[TabBoxAlternative] DesktopMode=0
  and HighlightWindows=false (what `org.plasmafusion.switcher`'s main.qml and its test seed
  expect), [Outline] QmlPath for the snap script's outline and [Plugins] sheetEnabled=true (as in
  the KWin part's test seed). If that part decides otherwise, change the constants at the top of
  the script. The KWin part has no docs/parts/ notes yet.
- Plasma style: keep the unprefixed `widgets/panel-background` tiles small (now 6 px). With them,
  the 34 px top bar survives plasmashell restarts and logins (verified, rlf-4/rlf-6); with the
  earlier 24 px tiles every start clamped it to 48 px.
- Installed names this part refers to: colour schemes `PlasmaFusionDark`/`PlasmaFusionLight`,
  icons `PlasmaFusion-Dark`/`PlasmaFusion`, cursor `PlasmaFusion-cursors`, Aurorae
  `PlasmaFusionDark`/`PlasmaFusionLight`, switcher `org.plasmafusion.switcher`, wallpaper
  `PlasmaFusion`, KWin scripts `plasmafusion-snap`/`plasmafusion-attach` (+ outline QML), widgets
  `org.plasmafusion.{appname,clockpill,quicksettings,launcher,dock}`, lock shell
  `org.plasmafusion.lockshell` with `tools/device/lockscreen-enable.sh`, Konsole profile
  `Plasma Fusion.profile`, KTextEditor theme `Plasma Fusion Dark`, fonts `Manrope` and
  `Space Grotesk` (splash). Anything missing is skipped with a note.
- Not set (optional, for the lead): kxkbrc `[Layout] DisplayNames=en` for the board's `EN` badge
  (it must match the user's LayoutList); the dock's `launchers` list (the dock's own default is
  used).
- Test tooling (lead): `tools/vsession/remote.sh` syncs `out/` with `--delete`, so a second run
  with the same NAME (seed `-`) replaces the first run's local results; copy them first.

## Review (2026-09-29, sessions rlf-1..rlf-6)

What was checked: the boards (Main/MainLight for layout and cards, Splash, render startup-2) value
by value against the files; the 6.7.5 sources for every key the defaults and scripts write
(klookandfeelmanager.cpp packageContents/save, shellcorona.cpp, defaultwallpaper.cpp,
ksplashqml splashapp.cpp, osd.cpp, tooltiparea.cpp, notificationsettings.kcfg, kwin outline.cpp,
Panel.qml/panelview.cpp thickness clamping, systemtray main.qml); the other parts' notes for what
they need from this part; the build into a separate stage (all parts, `tools/build.sh`), qmllint,
shellcheck; and integrated virtual sessions (install, dark, re-login, light, SSH-like run,
restore). Findings and fixes:

- Fixed (high): run over SSH as documented (only the session bus), `plasma-apply-lookandfeel`
  aborted ("could not connect to display", rc 134) and nothing was applied. fusion-config.sh now
  takes the display and XDG variables from the running plasmashell; restarted shells (both
  scripts) get the old shell's environment.
- Fixed (high): log-out screen unreadable in Plasma Fusion Light (Breeze fallback draws the light
  Complementary text on a black veil). Own `contents/logout/`.
- Fixed (medium): the switcher settings were option A (DesktopMode=1 for Alt+Tab), which disables
  the built switcher's "All workspaces" tab; now DesktopMode=0 and HighlightWindows=false, and
  Alt+Tab / Meta+Tab keep KWin's defaults.
- Fixed (medium): the tray hid 6 of the 10 items the quick-settings widget replaces, so the stock
  clipboard, keyboard-layout, KDE Connect and media icons could show next to the widget's own.
- Fixed (medium): the lock screen, the snap outline (`[Outline] QmlPath`), the sheet effect,
  Konsole's default profile and the KTextEditor theme were never configured; now set (and backed
  up / restored).
- Fixed (medium): the documented `rsync -a stage/home/ ~/` overwrote `gtk.css` before any backup;
  `--install` backs up first and merges gtk.css.
- Fixed (medium): the splash's Manrope/Space Grotesk text had a synthetic bold (mark and greeting
  heavier than the board); weights now on the `wght` axis (offscreen and ThinkPad captures match
  the render).
- Fixed (low): splash bar full at stage 5 while the session was still restoring; now
  (stage-1)/5. Dots with different speeds ran into each other; now they travel together.
- Fixed (low): Meta+FN (KWin default) was dropped from "Switch to Desktop N" and every key of
  "activate task manager entry N" removed; now only Meta+N moves.
- Fixed (low): previews were board renders; now made from the integrated desktop and splash.
- Verified, fixed in the Plasma style during the review: the top bar came back at 48 px after every
  plasmashell start (unprefixed 24 px panel tiles); with the style's 6 px tiles it stays 34 px.
- Remains: desktop card sizes (needs custom widgets), weather location, system-monitor first-run
  race, tray expander arrow (upstream), the `--auto` sunset switch itself not exercised (only its
  key), not run on the real ThinkPad session or in portrait/tablet mode. In the virtual sessions
  KWin's title bars showed its default left buttons (menu + on all desktops): that KWin does not
  read `~/.config/kdedefaults`, and the keys copied into kwinrc for the test did not stay there
  (not investigated; the real session reads `ButtonsOnLeft=M` from kdedefaults).

## Polish (2026-09-29)

See `docs/parts/polish.md`.

- Layout script, top-bar section: writes `plasmashellrc [PlasmaViews][Panel <id>]
  floatingApplets=1` through `ConfigFile` right after `new Panel` and before the location is set,
  so the stock pop-ups of the bar float with rounded corners also when the Global Theme is applied
  from System Settings (verified live, no restart).
- `fusion-config.sh`: sets the same key for existing Fusion top bars (older layouts) before its
  last plasmashell restart, restarting once when only this key changed; gives the quick-settings
  widget Meta+N when it has no shortcut and the key is free (recorded for `fusion-restore.sh`);
  still writes nothing to kxkbrc (the badge shows the layout's display name or short name).
  `fusion-restore.sh` puts plasmashellrc back from the backup as a whole; since the polish review
  it also undoes the shortcut and workspace records of every later run (the Meta+N of a newer
  `fusion-config.sh` lands in a later backup than the pre-Fusion one the restore picks).
- Splash: the title and status use the plain CSS weight on the static font files (they were
  drawn regular).

## Login check and "My previous desktop" (2026-09-30)

See `docs/parts/gate.md`. `fusion-config.sh` now also saves the look from before Plasma Fusion as
the Global Theme "My previous desktop" (`org.plasmafusion.previous.desktop`, section 0, once) and
installs the login check (section 8: `~/.config/plasma-workspace/env/plasma-fusion-gate.sh`,
`plasma-fusion-gate-notify.service`), which after a Plasma update falls back to Plasma's own lock
screen and the Aurorae title bars until `fusion-config.sh` records the new versions, and switches
the lock screen, snap/attach scripts, snap outline and Fusion switcher off while another Global
Theme is chosen (automatic light/dark switching with a Plasma Fusion theme as one of the two counts
as Plasma Fusion). `fusion-restore.sh` removes the check; "My previous desktop" stays installed.

## LAYOUT-1 (2026-09-30)

Work package LAYOUT-1 of the one-pass plan (`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-decisions/PLAN.md`),
built by the lead directly. The layout script runs only on a fresh layout or `--reset-layout`; the
live session gets these changes through DEVICE-1's in-place migration.

### Changes

- `contents/defaults` (both themes): `[kwinrc][org.kde.kdecoration2] library=org.plasmafusion.decoration`,
  `theme=` (the compiled title bars; where the plugin is missing the login check picks the matching
  Aurorae theme, `docs/parts/gate.md`), and the desktop containment `org.plasmafusion.desktop`
  (TABLET2 H1; `org.kde.plasma.folder` before).
- Layout script: Folder View desktop with the keys above; a top bar on every screen (decision 8; the
  primary one with tray, pen and quick settings, the others with app name, appmenu and clock pill);
  every appmenu for its own screen; top bars `adaptive`; the five passive tray items hidden (no
  expander arrow); the pen widget between tray and quick settings when installed; card places per
  screen shape (above).
- `contents/layouts/ensure-topbars.js` (new): adds a top bar to any screen without one, never removes
  one, prints `top bars: screens N, added M`; for `fusion-config.sh --screens` and KWIN-2's hot-plug
  handler (`workspace.screensChanged` through `evaluateScript`).
- Two panel templates (`packages/look-and-feel/layout-templates/org.plasmafusion.panel.topbar` and
  `.dock`, `X-Plasma-ContainmentCategories=panel`), installed into
  `~/.local/share/plasma/layout-templates/`: "Add Panel" offers the Fusion top bar and dock.
- Splash (ADAPTIVE 5.11): emblem and greeting `× clamp(min(W/1440, H/900), 0.75, 1.4)`; a portrait
  background (`background-portrait.png`, 1200 x 1920, the sun kept at 68 % of the width) when H > W.

### Verification

Private sessions on the ThinkPad (1920 x 1200 at 4/3 unless noted; scratch `build/ly/`):

- `ly-1` (24/24): Folder View and its keys; three cards; the landscape column and the portrait
  side-by-side geometries (and both fallbacks) clear of the bar and the dock area; one 34 px
  adaptive top bar; the dock translucent, dodgewindows, 88; the tray hides the passive items and
  the replaced ones; appmenu for its own screen; the compiled decoration named and used by KWin;
  `ensure-topbars.js` adds nothing on one screen; with EIS input on 20, 60 and 50 files: the band
  selects, Del trashes, Ctrl+Z restores, F2 renames, Ctrl-click adds one, Shift-click a range, a
  drag moves an icon.
- `ly-2` (19/19, two outputs): a top bar on each screen (the second one with app name, menu and
  clock pill only), dock and cards on the primary; the primary output disabled (lid closed): the
  remaining screen has exactly one top bar with tray and quick settings, the dock and the cards;
  back to two screens with a bar each; M24: font, cursor, buttons and the compiled decoration
  survive Dark, Light, Dark through `plasma-apply-lookandfeel`; plasmafusionrc untouched; panels
  unchanged.
- `ly-3` (6/6): the decoration plugin hidden with bwrap: KWin draws Breeze, then the login check
  picks Aurorae `__aurorae__svg__PlasmaFusionDark` with no notification, and KWin draws it.
- Matrix subset on the same stage: M01, M10, M12, M23 pass. M09 and M14 fail only on the portrait
  top bar (quick settings 16 px past the 900 px edge; 46 px before LAYOUT-1): TOP-2's width
  budget. M18 fails only because the launcher opens on the primary screen: LAUNCH-1.
- Splash rendered offscreen at 1440 x 900, 900 x 1440 (portrait background, emblem 0.75) and
  1366 x 768 (0.85).
- Perf gate (`tools/tests/perf/run.sh`, 3 quiet runs per arm, 1920 x 1200 at 4/3, exclusive host;
  HEAD 024570a's stage against this one; `gate.py --baseline` HEAD's `result.json`): no regression.
  Idle frames 0.07 (0.03..0.17) /s against 0.17 (0.07..0.17), plasmashell idle CPU 0.47 % against
  0.57 % (budget: at most +0.02 frames/s and +0.1 point); plasmashell PSS after settle 200 against
  196 MiB and GEM 138 against 136 MiB with an empty desktop; KWin RSS 278 against 306 MiB. Alt+Tab
  animation done 566 (543..587) against 513 (510..551) ms, within the gate's noise (not a layout
  change; the open Alt+Tab follow-up).
- **Memory with desktop icons (over budget, owner decision)**: plasmashell with 50 files on the
  desktop against the pre-LAYOUT-1 desktop (no icons), two sessions per arm: anonymous memory
  +31 and +67 MiB (PSS +38 / +69), GEM +24 and +15 MiB; the plan's budget is +15 MiB PSS and
  +10 MiB GEM. Folder View with no files costs about +2 MiB; switching previews off does not help
  (+60 / +41). Stock Plasma (no Plasma Fusion) shows the same: 0 to 50 files +49 / +50 MiB
  anonymous, +47 / +36 MiB GEM. The cost is upstream Folder View's per-icon cost, not the layout's;
  the budget cannot be met with Folder View. Options: keep the icons (decision M1), or ship icons
  off by default with KCM-1's "Desktop icons" switch.
