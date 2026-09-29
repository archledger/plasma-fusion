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
| kdeglobals [General] | font, menuFont, toolBarFont | `Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0` (13 px) | same |
| kdeglobals [General] | smallestReadableFont | `Manrope,9,-1,5,400,…` (12 px) | same |
| kdeglobals [General] | activeFont | sentinel, same as [WM] activeFont: Plasma 6.7.5 detects fonts by this key but applies [WM] (klookandfeelmanager.cpp:118-120 vs 556-566) | same |
| kdeglobals [WM] | activeFont | `Manrope,10.5,-1,5,800,…` (14 px ExtraBold) | same |
| kdeglobals [Icons] | Theme | PlasmaFusion-Dark | PlasmaFusion |
| plasmarc [Theme] | name | plasma-fusion-dark | plasma-fusion-light |
| kcminputrc [Mouse] | cursorTheme | PlasmaFusion-cursors | PlasmaFusion-cursors |
| kwinrc [org.kde.kdecoration2] | library, theme, NoPlugin | org.kde.kwin.aurorae.v2, `__aurorae__svg__PlasmaFusionDark`, false | …`PlasmaFusionLight` |
| kwinrc [org.kde.kdecoration2] | BorderSize | None (used once `BorderSizeAuto=false`, set by fusion-config.sh) | None |
| kwinrc [WindowSwitcher] | LayoutName | org.plasmafusion.switcher | same |
| kwinrc [Windows] | Placement | Centered (layout setting) | same |
| ksplashrc [KSplash] | Theme | org.plasmafusion.dark.desktop (both variants) | same |
| [Wallpaper] | Image | PlasmaFusion | same |
| [Desktop][org.kde.plasma.desktop] | Containment | org.kde.desktopcontainment (widgets only, no desktop icons) | same |

`contents/layouts/defaults`: kwinrc [org.kde.kdecoration2] ButtonsOnLeft=M, ButtonsOnRight=IAX;
[Windows] BorderlessMaximizedWindows=false (applied only together with the layout).

The Qt 6.11 font strings were printed by PySide6 6.11.2 `QFont.toString()` on the build laptop.
A name that is not installed is skipped by Plasma (the old value stays), so the Global Theme can
be applied before every part exists.

## Desktop layout (layout script)

Runs on the first login of a user whose `kdeglobals [KDE] LookAndFeelPackage` is a Fusion theme
and has no `plasma-org.kde.plasma.desktop-appletsrc`, on `plasma-apply-lookandfeel -a <id>
--resetLayout`, and when "Desktop and window layout" is ticked in System Settings. It replaces the
existing panels.

| Piece | Settings | Widgets (fallback when a Fusion widget is not installed) |
|---|---|---|
| Top bar | `location top`, `height 34`, `floating false`, `lengthMode fill`, `hiding none`, `opacity translucent` | `org.plasmafusion.appname` (else `org.plasmafusion.launcher` as a 32 px pill, else Kickoff), `org.kde.plasma.appmenu`, panelspacer, `org.plasmafusion.clockpill` (else pager + digital clock "ddd d MMM" beside the time), panelspacer, `org.kde.plasma.systemtray`, `org.plasmafusion.quicksettings` |
| Dock | `location bottom`, `height 88` (72 px dock + 16 px headroom, shared contract with the Plasma style), `floating true`, `lengthMode fit`, `alignment center`, `hiding dodgewindows`, `opacity translucent` | `org.plasmafusion.launcher` with `[General] buttonStyle=hidden` when the app-name widget holds the top-left corner (the dock finds it in its own panel for Start; Meta finds it in any panel), then `org.plasmafusion.dock` (else Kickoff when there is no Fusion launcher, and `org.kde.plasma.icontasks`) |
| Desktop | `org.kde.image` wallpaper plugin, image left unset (the Global Theme's `PlasmaFusion` default, light/dark by the Plasma style) | Weather, calendar, CPU/memory cards, see below |

System tray: when the quick-settings widget is installed, `[General] hiddenItems` =
`org.kde.plasma.networkmanagement, org.kde.plasma.volume, org.kde.plasma.battery,
org.kde.plasma.bluetooth, org.kde.plasma.brightness, org.kde.plasma.notifications,
org.kde.plasma.keyboardlayout, org.kde.kdeconnect, org.kde.plasma.clipboard,
org.kde.plasma.mediacontroller` (the ten ids of docs/parts/shell-quicksettings.md: the pill, tiles
and bell replace the first six, the widget draws the EN badge, phone and clipboard buttons and the
media card itself). They stay loaded (notification server and popups, network secrets, battery
warnings, Klipper, KDE Connect) but sit in the tray's hidden section.

Desktop cards, on the primary screen, in the area left free by the top bar, all with
`StandardBackground` (so the Plasma style's `blurred-*` card and the wallpaper blur apply):

| Card | Rect (logical px) | Configuration |
|---|---|---|
| `org.kde.plasma.weather` | 1008,16 416x208 | none (asks for a location) |
| `org.kde.plasma.calendar` | 1008,240 416x288 | none |
| `org.kde.plasma.systemmonitor` | 1008,544 416x144 | face `org.kde.ksysguard.horizontalbars`; sensors `cpu/all/usage` (label CPU, 60,196,176) and `memory/physical/usedPercent` (label Memory, 91,157,255); range 0-100; no title |

Sizes come from the stock widgets' minimums in grid units (18 px for Manrope 13 px) plus the
card padding (14 px), rounded up to the desktop's 16 px cells; x is right-aligned with a 16 px
margin. Verified exactly in the virtual sessions (`dump-layout.js`).

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
   back to 34 / 88 px (safety net; with the current Plasma style it reports "as designed").
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
   PopupPosition=TopRight, PopupTimeout=5000 (notificationsettings.kcfg); krunnerrc [General]
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

- Desktop cards are 416 px wide (board 192) and 208/288/144 px high (board about 120/188/92):
  the stock calendar needs 21x14 grid units for its month view (below that it shows only an
  icon), the stock weather view needs 10 grid units of height (FullRepresentation.qml), and the
  desktop snaps widgets to 16 px cells. The column sits 16 px from the right edge and top bar
  (board 22 px / 56 px from the top). Matching the board needs small custom card widgets (see
  "Needs").
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

- Decision for the lead: board-sized desktop cards need three small widgets (weather, calendar,
  CPU/memory; about 100-150 lines of QML each) with new ids, a new part; the layout script's
  `CARDS` table takes them with a one-line change per card and keeps the stock widgets as
  fallback.
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
