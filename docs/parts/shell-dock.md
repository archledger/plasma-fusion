# Part: shell dock (`org.plasmafusion.dock`)

The whole content of the Plasma Fusion dock as one QML plasmoid, built from the dock on the Main,
MainLight, Launcher, Overview and QuickSettings boards (`<nav aria-label="Dock">`, renders
desktop-dark-1..4 and desktop-light-1..4).

Left to right: **Start** (Fusion logo) · **Search** · **Overview** · separator · pinned apps ·
separator · running apps that are not pinned · **Downloads** stack · **Trash**.

## Files

| File | Purpose |
|---|---|
| `packages/plasmoids/org.plasmafusion.dock/metadata.json` | Plasma/Applet package, provides `org.kde.plasma.multitasking` (Meta+1..9 reach it) |
| `.../contents/config/main.xml` | settings (below) |
| `.../contents/config/config.qml`, `ui/ConfigGeneral.qml` | settings page: "Magnify icons on hover", magnified size, name pill, colours, Search action, filters, click-to-minimize |
| `.../contents/ui/main.qml` | task model, layout and magnification engine, actions, menus, Downloads and Trash logic |
| `.../contents/ui/TaskItem.qml` | one app: theme icon with the board's drop shadow, running dot or active pill, pointer/keyboard handling |
| `.../contents/ui/DockButton.qml` | the 48 px fixed buttons (fill, hover, pressed, "aria-pressed" accent state, indicator, focus ring) |
| `.../contents/ui/NamePill.qml` | the name pill above the hovered item (a separate tooltip window) |
| `.../contents/ui/DockMenu.qml` | script-filled context menu (PlasmaExtras.Menu) |
| `.../contents/ui/DockPalette.qml` | every colour of the dark and light boards |
| `.../contents/ui/Glyph.qml`, `FusionLogo.qml`, `DownloadsStack.qml` | board line icons (1.8 stroke), the three-circle mark, the fanned download cards |
| `tools/build.d/73-dock.sh` | copies the package to `$STAGE/.local/share/plasma/plasmoids/org.plasmafusion.dock/` after checking metadata.json and main.xml |

No compiled code, no private QML modules: it uses `org.kde.taskmanager` (TasksModel), `org.kde.plasma.core/extras/plasmoid`,
`org.kde.plasma.workspace.dbus`, `org.kde.plasma.plasma5support` (executable engine), `QtQuick.Effects`,
`QtQuick.Shapes`, `Qt.labs.folderlistmodel` and `QtCore` — all verified installed on the ThinkPad.

## Install and apply

```
STAGE=... bash tools/build.sh dock          # -> $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.dock
# or on a machine directly:
kpackagetool6 -t Plasma/Applet -i packages/plasmoids/org.plasmafusion.dock   # -u to upgrade
```

The dock panel (what the Global Theme layout script already creates):

```js
var dock = new Panel;
dock.location = "bottom"; dock.height = 72; dock.floating = true; dock.lengthMode = "fit";   // 88 with the headroom frame
dock.alignment = "center"; dock.hiding = "dodgewindows"; dock.opacity = "translucent";
var l = dock.addWidget("org.plasmafusion.launcher");            // optional, see "Launcher" below
l.currentConfigGroup = ["General"]; l.writeConfig("buttonStyle", "hidden");
dock.addWidget("org.plasmafusion.dock");
```

### Settings (`[Containments][N][Applets][M][Configuration][General]`)

| Key | Default | Meaning |
|---|---|---|
| `launchers` | `applications:org.kde.dolphin.desktop, preferred://browser, applications:org.kde.konsole.desktop, applications:org.kde.kmail2.desktop, applications:org.kde.kate.desktop, applications:org.kde.elisa.desktop, applications:org.kde.gwenview.desktop, applications:org.kde.korganizer.desktop, applications:systemsettings.desktop` | pinned apps = the board's Files, Browser, Terminal, Mail, Code, Music, Photos, Calendar, Settings. `preferred://browser` resolves to the default browser (Google Chrome on the ThinkPad's real account, Firefox in a fresh HOME). A layout script may write its own list. |
| `launcherFallbacks` | `kate=kwrite`, `kmail2=kontact`, `korganizer=merkuro.calendar` (full `applications:` URLs) | once per start, a pinned app that is not installed is replaced by its fallback (Kate is missing on the ThinkPad, so Code becomes KWrite; verified). Pinned apps that are still missing are hidden. |
| `magnify` | `true` | "Magnify icons on hover" |
| `magnifiedSize` | `62` | size of the icon under the pointer (48–72; neighbours follow the falloff) |
| `showTooltips` | `true` | name pill above the hovered item |
| `colorVariant` | `0` | 0 follow the Plasma style (brightness of the theme background), 1 dark, 2 light |
| `searchAction` | `0` | 0 KRunner, 1 the application launcher |
| `showOnlyCurrentDesktop` / `showOnlyCurrentActivity` / `showOnlyCurrentScreen` | true / true / false | task filters, as in the stock task manager |
| `minimizeActiveTaskOnClick` | `true` | clicking the active app minimizes it |
| `downloadsFolder` | empty (XDG download dir) | folder of the Downloads stack |
| `debugHoverIndex`, `debugPointerX`, `debugAction` | off | testing only (not in the settings page): force the hovered task, pretend the pointer rests at a screen x, or run one action (`start`, `search`, `overview`, `downloads-menu`, `trash-menu`, `close-menu`, `configure` (opens the settings dialog), `menu:ROW`, `activate:ROW`, `new:ROW`). Used by the virtual-session scenarios because no pointer can be injected there. |

## Behaviour

- **Geometry (board values):** 48 px tiles 8 px apart, 1×36 separators with 4 px margins, 12 px from the dock
  edge to the first/last button, icons 14 px above the dock's bottom edge, running dot 5×4 (60 % ink), active
  pill 16×4 (#8ab8ff / #2f6fdf) 5 px under the icon. The applet asks for the full panel thickness
  (`Plasmoid.CanFillArea`), measures the containment's own side margins and compensates, so the row starts
  exactly 12 px from the visible edge on both sides (measured: dock 305–1135 px vs board 305–1136 px).
- **Magnification:** parabolic falloff `size = 48 + 14·zoom·max(0, 1 − (d/74)²)`, d = pointer distance
  from the icon centre in rest coordinates; gives exactly 62/54/48 at icon centres, ~60/60 between two
  icons. `zoom` animates 0→1 (Kirigami longDuration, OutCubic) when the pointer enters the task list and back
  when it leaves. Only app icons magnify. The dock widens with the icons (fit-content panel); the pointer is
  tracked in screen coordinates and the row is centred on the dock centre, which does not move when the
  panel grows, so the icon under the pointer stays under it (verified in the session with `debugPointerX`).
  Magnified icons grow into the 16 px transparent headroom. Setting `magnify=false` keeps 48 px icons.
- **Many apps:** when the resting dock would be wider than the screen (minus the 8 px floating margins
  and room for the magnified icons), the app icons shrink evenly (down to 24 px) so Start, Search,
  Overview, Downloads and Trash always stay on screen; magnification then adds the same 14 px to the
  smaller icons. The fixed buttons stay 48 px.
- **Name pill:** separate tooltip window (PlasmaCore.Dialog, type Tooltip, no focus, no input), 12 px bold
  Manrope, padding 5/10, radius 8, rgba(12,15,28,.92), 1 px edge; its bottom edge sits 12 px above the hovered
  icon (measured: bottom row 795, icon top 808, board 795/808). Shown for app icons and the fixed buttons
  (Start, Search, Overview, Downloads, Trash). The 1 px edge is drawn over the fill, as CSS draws a
  border over its background; names longer than 320 px are elided.
- **Icons:** the icon theme's app icons (`decoration` of TasksModel) with the board's
  `drop-shadow(0 3px 6px rgba(0,0,0,.35))` (light: rgba(20,24,39,.14)) as a MultiEffect. The blur was
  calibrated against the rendered board: darkening below a tile matches the board within 1–2 % row by row.
- **Tasks:** TasksModel with GroupApplications, SortManual, separateLaunchers, launchInPlace,
  hideActivatedLaunchers (as the stock Icons-only Task Manager). A running pinned app takes its launcher's
  slot; running apps that are not pinned follow the second separator (QuickSettings board). Click:
  launch / activate / minimize the active one / cycle a group's windows (stock rules); Shift+click and
  middle-click: new instance; right-click: menu with window list, New Window or Open, Minimize/Restore,
  **Keep in Dock** (pin/unpin), Close / Close All; drag sideways to reorder within pinned or running; drop
  `.desktop` files to pin, other files on an app to open them with it; Meta+1..9 through
  `activateTaskAtIndex`; startup feedback pulses the icon; an app demanding attention gets an orange dot;
  minimize animation targets are published.
- **Start:** if a launcher applet (org.plasmafusion.launcher, Kickoff, Kicker) sits in the dock's own
  panel, Start opens/closes it (the Fusion launcher's `open()`/`close()`/`recentlyOpen()`, else
  `expanded`) and shows the board's pressed state (accent fill, inner ring, 16×4 pill) while its menu is
  open (`menuOpen`, else `expanded`). Otherwise it calls `org.kde.PlasmaShell.activateLauncherMenu` over D-Bus.
- **Search:** `org.kde.krunner /App toggleDisplay` (or the launcher, `searchAction=1`).
- **Overview:** kglobalaccel `invokeShortcut("Overview")` on component `kwin` (verified toggles Overview).
- **Downloads:** click opens the folder; right-click lists the 10 newest files (FolderListModel sorted by time)
  plus "Open Downloads Folder". Art: three 22×28 cards (#f2a65a −10°, #5b9dff +6°, front card with a
  download arrow), as on the board.
- **Trash:** click opens `trash:/`; right-click: Open Trash, Empty Trash… (asks in a second menu, then
  `ktrash6 --empty`); drop files to move them to the trash (`kioclient move … trash:/`). The trash
  folder is watched; when it holds items a 7 px #f2a65a dot appears (the board's badge dot).
- **Keyboard:** every item takes Tab focus (2 px #2f6fdf ring with a 2 px gap), Enter/Space activate, Menu
  key opens the context menu; accessible names and roles are set.
- **Colours:** follow the Plasma style automatically; all values from the boards' dark and light variants.

## Verification

- `qmllint` on every file: clean except i18n unqualified-access notes and two linter false positives
  (`onDataChanged` with the `roles` argument; `Qt.styleHints.startDragDistance`), no runtime warnings.
- `qmltestrunner` (offscreen, Qt 6.11.2): a HoverHandler on the dock item still tracks the pointer while
  hover-enabled child MouseAreas get hover — the assumption the magnification relies on.
- Virtual sessions on the ThinkPad (`tools/vsession/remote.sh dk-1 … dk-8`, stage built with all parts;
  plasmashell restarted with `QT_FORCE_STDERR_LOGGING=1` because the stock log went to the journal):
  dark and light, the board's wallpaper, the design's app tiles as a test-only icon theme (the icon part was
  not built yet), Dolphin/Konsole/System Settings/Ark running. Checked: rest layout, magnification by task
  index and by screen x (pointer mapping across the panel resize), name pill, running dot / active pill,
  unpinned app after the second separator, Kate→KWrite fallback and hiding of missing apps, trash dot
  after `kioclient move`, click on the active app minimizes and restores, KRunner opens, Overview toggles,
  Start opens the Fusion launcher placed in the same panel and shows the pressed state only while it is
  open, magnification off, dodge-windows hides the dock, stock Breeze Plasma style fallback (dock background
  then fills all 88 px, content still correct). No QML errors or binding loops from the dock in
  plasmashell's log.
- Measured against the renders: horizontal extent within 1 px, icon row and indicators at the board's
  positions relative to the frame, pill within 1 px, shadow profile within 1–2 %.

- A last run with the real `PlasmaFusion-Dark` / `PlasmaFusion` icon themes from `tools/build.d/30-icons.sh`
  (instead of the test-only theme) gave the same layout in both variants (`screens-real-icons/`).

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/shell-dock/`
(`cmp-*.png` board vs session side by side; `screens/*.png` full 1440×900 screenshots with the test icon
theme; `screens-real-icons/*.png` and `real-icons-dock-strip.png` with the built Plasma Fusion icon themes;
`pointer-mapping-sequence.png`).

## Deviations from the board, with reasons

1. **The dock does not grow taller while magnifying.** In the board's CSS the hovered 62 px icon makes the
   nav 88 px tall; by the shared contract the Plasma style draws a fixed 72 px dock (including its 1 px edge,
   so the resting frame is 812–884 px instead of the board's 810–884 px) and the magnified icon rises into
   the transparent headroom, 4 px above the frame. The pill position relative to the icon matches.
2. **Overview button highlight:** not implemented. KWin draws panels only as fading thumbnails during
   Overview (accepted platform deviation), so the dock is not visible then; KWin also exposes no
   "Overview active" state to QML.
3. **Start highlight** works only when the launcher applet is in the dock's own panel (the Global Theme
   layout puts it there). Applets in other panels cannot be observed from QML.
4. **Recent documents in the context menu:** not offered; they need the task manager's compiled private
   backend, which cannot be imported by another package.
5. **Context menus** are PlasmaExtras.Menu (QMenu), so they keep Breeze's radius (accepted deviation).
   They could not be screenshotted in the virtual session: Wayland refuses grabbing popups before the panel
   has received real input. The menus are built without errors (log checked).
6. **Hover and drag-to-reorder with a real pointer** were not exercised live (no input injection on the
   ThinkPad); hover delivery was verified with qmltestrunner and the pointer mapping with `debugPointerX`.
7. **Names in the pill** are the real app names (e.g. "Firefox", "KWrite"), not the board's generic
   "Browser"/"Code".
8. The dock is laid out for a horizontal bottom panel only (its only intended use).

## Needs from other parts

- **Global Theme layout (`common/contents/layouts/org.kde.plasma.desktop-layout.js`):** when it adds
  `org.plasmafusion.launcher` to the dock panel next to `org.plasmafusion.dock`, it must set the launcher's
  `[General] buttonStyle=hidden`; with the default `auto` the launcher draws its own 48 px Start tile and
  the dock shows two Start buttons. Suggested: `krunnerrc [General] FreeFloating=true` so Search opens
  KRunner centred instead of at the top edge. Optionally write the dock's `launchers` with
  `applicationExists()` checks (e.g. Chrome else Firefox; the default `preferred://browser` already follows
  the default browser).
- **Launcher (`org.plasmafusion.launcher`):** keep `open(mode, argument)`, `close()`, `recentlyOpen()` and
  `menuOpen` on its PlasmoidItem; the dock drives it through them. Its hidden button currently takes no
  space in the dock panel (verified). Its `PFDEBUG` console traces were still printing during these tests.
- **Plasma style:** keep the south panel contract as built now (verified): 16 px transparent, unblurred
  headroom, the frosted dock in the lower 72 px, the mask excluding the headroom (the input region then
  starts at the dock's top edge, so the headroom does not swallow clicks), south left/right margin hints 8.
- **Icon theme:** app icons under the Icon= names of the pinned apps: `org.kde.dolphin`, `google-chrome`,
  `firefox`, `utilities-terminal`, `kmail`, `kwrite` (and `kate`), `elisa`, `gwenview`, `korganizer`,
  `preferences-system` — all present in the current build. On the ThinkPad KWrite fills the board's Code
  slot, but the theme draws `kwrite` with the yellow Notes tile; the board's Code slot is the purple `</>`
  tile (the icon part decides). `ark` has no Fusion tile yet (Breeze fallback).
- **tools/vsession/vsession.sh (lead):** add `QT_FORCE_STDERR_LOGGING=1` to the session environment; without
  it plasmashell.log stays empty and QML warnings go to the ThinkPad's journal.

## Review (2026-09-29, second pass)

What was checked:

- Board values against the source (`Main`, `MainLight`, `Launcher`, `LauncherLight`, `Overview`,
  `OverviewLight`, `QuickSettings` `<nav aria-label="Dock">`) and the renders desktop-dark/light-1, -2, -4:
  tile, gap, separator, paddings, radii, fills, pressed state, indicators, pill, drop shadow, glyph
  strokes (1.8, round caps), Downloads cards, logo. Pixel scans of the session screenshots against the
  renders: button and icon columns within 1 px, button rows 822-870 and dock bottom 884 as on the board,
  running dot / active pill rows 875-879, pill 769-794.
- Integrated build: `STAGE=<scratch>/home bash tools/build.sh` (all parts, no errors), then virtual sessions
  rdk-1 … rdk-4 on the ThinkPad that apply the real Global Theme with `tools/device/fusion-config.sh
  --reset-layout` (dark) and `--light --keep-layout`, so the dock runs in the layout's own panel next to
  the hidden Fusion launcher, with the Fusion Plasma style, colours and icon themes. Dolphin, Konsole,
  System Settings and Ark running; rest, pointer (`debugPointerX`), Start pressed, unpinned app, nothing
  pinned, no apps running, 25 pinned apps, settings dialog, in dark and light.
- `qmllint` (Qt 6.11.2): only i18n notes and the two known false positives remain. metadata.json and
  main.xml parse; the build script copies only the package.
- plasmashell logs (QT_FORCE_STDERR_LOGGING=1): nothing from the dock during normal use.

Fixed:

1. **Too many apps pushed Downloads and Trash off the screen** (25 pinned apps: panel length 1674 px on a
   1440 px screen, the end of the dock cut off). App icons now shrink evenly to fit (see "Many apps"),
   keeping room for the magnified icons; checked rest and magnified at both ends (`review-many-apps.png`).
2. **The settings dialog logged 21 warnings** ("Setting initial properties failed: ConfigGeneral does not
   have a property called cfg_launchers", `cfg_…Default`, …) because the dialog passes every key and its
   default to the page. The page now declares them; `saveConfig()` refreshes the keys it has no control for
   right before Apply writes them back, so pinning an app while the dialog is open is not undone. Only the
   generic Kirigami notice "Created graphical object was not placed in the graphics scene" remains; it is
   printed for any page pushed on a Kirigami PageRow (reproduced offscreen with a plain Kirigami.Page).
3. **Name pill edge** was drawn beside the fill (QML border) and showed the wallpaper lightened by 12 %; the
   board's CSS border lies over the background, giving a dark grey edge. The edge is now a separate
   rectangle over the fill (`review-pill-and-ring-fix.png`).
4. **Start pressed ring**: drawn beside the fill instead of over it (CSS inset box-shadow), and in light it
   used OverviewLight's darker rgba(47,111,223,.5) instead of LauncherLight's rgba(138,184,255,.5). Both
   fixed; the ring now matches the Launcher boards in both variants.
5. Very long names are elided at 320 px so the pill cannot run off the screen.
6. metadata.json licence `GPL-2.0+` changed to `GPL-2.0-or-later` like every other package.
7. Test hook `debugAction=configure` (opens the settings dialog) for the virtual sessions.

Still open / not changed:

- The pill text is rendered with the session's subpixel antialiasing (colour fringes, slightly heavier
  than the board's greyscale browser text). That follows the system font settings, like all Plasma text.
- Hover, drag-to-reorder, right-click menus and file drops still need a check with a real pointer on the
  ThinkPad (no input injection in the virtual session). Magnification makes the fit-content panel resize
  on every animation frame; smoothness can only be judged on the real session.
- With nothing pinned, running apps follow the first separator and Downloads follows them without a
  separator (as on the QuickSettings board, where Downloads follows the unpinned app directly).
- Status of the builder's "Needs from other parts": the Global Theme layout writes the launcher's
  `buttonStyle=hidden` and fusion-config.sh writes `krunnerrc FreeFloating=true` (both seen in rdk-1 …
  rdk-4); the launcher's PFDEBUG traces are gone; the Plasma style contract holds. Still open:
  `QT_FORCE_STDERR_LOGGING=1` in tools/vsession/vsession.sh (the scenarios export it themselves) and the
  Breeze fallback icon for Ark (icon part).

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/shell-dock/review-*.png`
(board above, session below: `review-dark-hover`, `review-light-hover`, `review-dark-launcher`,
`review-light-launcher`, `review-dark-unpinned`, `review-light-unpinned`; `review-many-apps` before and
after; `review-nothing-pinned`; `review-pill-and-ring-fix`; `review-dark-config`, `review-light-config`;
full screenshots `review-*-full.png`).

## Magnification rework (2026-09-30)

Spec: EFFECTS.md section 4 (`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-tablet/`), ADAPTIVE fix 7,
BACKLOG M4.

- **The panel never changes size while the pointer moves.** `relayout()` computes only the rest layout (slots,
  rest x, widths, centres) and runs only when the tasks, pins, screen, insets or tile size change. The
  applet's width follows the rest width.
- **Magnification is arithmetic plus transforms.** For the pointer x in row coordinates, each task grows by
  `(Z - T) * zoom * max(0, 1 - ((c - x) / R)^2)` (62 / 54 / 48 at T 48, gap 8). Every slot is shifted by the
  growth to its left minus a share of the total growth proportional to its distance from Start, so Start and
  Trash stay where they are and every gap gives up the same share, never below 3 px. Task items scale around
  the icon's bottom centre and translate; buttons and separators only translate.
- **Icons stay crisp and are rasterised once.** A task shows a plain icon at rest size, and while magnified a
  second icon rendered at the magnified size (loaded after the first hover). The drop shadow (MultiEffect)
  keeps its size, so it is rendered once and only transformed afterwards.
- **One hover source.** The dock's HoverHandler knows the pointer position; the item under it (task or
  button, in the magnified geometry, from 10 px above the icon) is computed with the magnification. Items no
  longer track hover themselves: their state could stay behind when the pointer jumped off the panel, and
  per-item hover gaps between magnified neighbours unmapped and remapped the name pill window many times a
  second.
- **The name pill** is placed when the hovered item changes (at its magnified position at that moment) and
  stays mapped for 150 ms when the pointer moves between two items.
- **Nothing runs at rest.** One update per event-loop pass while the pointer moves (Qt.callLater); a
  FrameAnimation made the window render every frame while it ran, even with nothing changed.
- **Touch and pen.** A touchscreen press turns magnification and the pill off until a mouse, touchpad or pen
  hovers again; a pen that stops reporting for 600 ms counts as gone (Qt keeps a stylus hover after the pen
  leaves range). The launcher or a menu opening clears the hover.
- The start-up pulse runs at most three times and not at all with animations off.

Measured in private sessions at 1920x1200, scale 4/3, a 10 s pointer sweep over the dock at 125 Hz, same
stage apart from the dock (laptop `build/lead/dk/out/perf-dk-*`, script `dock-analyze.py`):

| | old dock (n=4) | new dock |
|---|---|---|
| dock window resizes during the sweep | 288-313 | 0 |
| plasmashell CPU, magnification on | 41.5 % (34.5-46.2) | 32.7-36.3 % |
| plasmashell CPU, magnification off | (research: about 10-15 %) | 22.9 % |
| KWin CPU | 19.0 % | 15.6-16.1 % |
| plasmashell GPU | 4.7 % | 3.3-3.7 % |
| frames after the pointer left | only the zoom-out and the system card's own bars | same |

A perf profile of plasmashell during the sweep guided the fixes (name-pill window churn, then the
FrameAnimation). The remaining cost is spread over Qt's per-event and per-frame work; the target in
EFFECTS.md 4.6 (about 10 %) is not reached. Next candidates: the per-event cost with magnification off
(22.9 %), and moving the per-frame work off the pointer-event path.

Functional check (`build/lead/dk/scen-func.sh`, real EIS input): hover pill and magnification, the launcher
and running-app menus, drag to reorder (the launcher order is saved), hover and pill on the fixed buttons,
pill cleared on a slow exit and on a jump off the panel, magnification off, and a click launching the app.

## DOCK-2 (2026-09-30)

Work package DOCK-2 of the one-pass plan (TABLET 4.4 and 5, BACKLOG M3, GAPS G17/G26, ADAPTIVE 27),
built by the lead directly.

### Changes

- **Tablet posture** (`FusionTablet`, KWin's own state): 56 px tiles (`tabletTile`), 12 px gaps, 40 px
  separators with 6 px margins, a 6 x 4 dot / 18 x 4 pill 4 px under the icon, 12 px bottom padding;
  magnification by mouse and pen only, 56 to 70; Search leaves the dock (it is in the launcher
  sheet), and in portrait only Start and Overview stay (`tabletShowDownloadsTrash` for landscape);
  never below 44 px when crowded. A tap on the active app does not minimize it (apps are full
  screen there). The panel's thickness (96) comes from KWIN-1's panel script.
- **Touch**: a top layer above the icons sees a touch first (an item's own handlers come after its
  children's, so handlers on the dock root never saw touches over the icons): it turns
  magnification off (`touchSuppress`) and holds the swipe. A swipe up of 24 px on the dock opens
  the launcher at once; a launcher with `beginReveal` / `updateReveal(progress)` / `endReveal(open)`
  (LAUNCH-2's sheet) follows the finger (progress = dy / 240; opens at 0.3 or 800 px/s). A long
  press of 500 ms opens the icon's menu (`pressAndHoldInterval`); press feedback 0.94 and 80 %.
  Reorder by touch stays the sideways drag (the menu cannot hand a moving finger back to the icon).
- **Bottom strip and home indicator** (`BottomStrip.qml`, TABLET2 N1; replaces TABLET P2's floating
  `HomeIndicator.qml`): in tablet posture a 20 px layer-shell band along the bottom edge of the dock's
  screen (scope `dock`, bottom layer, exclusive zone 20, no input or focus). KWin ends maximized apps
  above it (work area 1440 x 836 instead of 856 at 1440 x 900 with the 44 px top bar), so no app control
  sits in the 20 px touch zone of the navigation gestures, where KWin keeps every touch (before, the
  pill crossed LibreOffice's status bar and its taps there were lost, private session hd2t). Over a
  maximized app (not full screen) it takes the top bar's solid fill (#090c18 dark, #fafbff light)
  with the 120 x 5 pill 8 px above the bottom; otherwise it is transparent (the dock covers it). It
  exists for the whole tablet posture, so the work area does not change while apps open and close.
  The settings module's home indicator switch (dock config `homeIndicator`, now declared and read; it
  had no effect before) hides the pill; the strip stays. Private sessions st2/st3: tablet 836 px,
  laptop back to 866, strip a `Dock` window, pill on/off.
- **First tablet use** (`GestureCard.qml`, TABLET 5): a centred card with the three gestures and a 44 px
  "Got it"; dismissing it writes `plasmafusionrc [Tablet] GestureCardShown=true` (read once at start).
  TABLET2 (2026-10-01): five rows for today's gestures (swipe up = home, pause halfway = app
  switcher; a short swipe shows the dock over an app; along the bottom edge = previous app; pull down
  at the clock = notifications, at the battery = controls; swipe down on the home screen = search),
  without the three-finger Overview (off in tablet posture since G1). The card has a version
  (`gestureCardVersion` 2): it shows while `GestureCardVersion` is lower, so everyone who dismissed
  the first card sees the new gestures once; dismissing writes both keys. Tests suppress it with
  `GestureCardVersion 99`.
- **Desktop shortcuts** (BACKLOG M3): "Add to Desktop" in the icon's menu makes a symlink in
  `~/Desktop` (trusted: no "untrusted program" prompt); a pinned icon dragged 48 px upwards (mouse,
  touchpad or pen; a vertical `DragHandler` inside the icon's mouse area) starts a real drag of its
  launcher through Kicker's drag helper. Over the desktop, KIO's drop menu then offers "Link Here"
  (its only action). A QML `Drag` offering only a link, Kickoff's way, was tried and did not drop
  (action 0) in private sessions; the menu item links without asking.
- **Tiles** (ADAPTIVE 27): every icon is a `FusionIconTile` (the neutral Fusion tile behind icons the
  Plasma Fusion theme does not draw) over one `RectangularShadow` of the tile shape (0 3 6, .35):
  no per-icon `layer` + `MultiEffect` any more. Calendar apps (KOrganizer, Merkuro, GNOME Calendar)
  show today's month and day over the tile's fixed "SEP 28"; one timer to the next midnight.
  `AppId`s that carry ".desktop" are stripped before they are used as icon names.
- **Attention** (G26): one short bounce when an app asks for attention (besides the orange dot).
- **Unread counts and progress** (G17): `TaskItem` draws the Controls board's badge (20 px, accent,
  11 px 800, tabular) and a 3 px progress ring on a 20 px disc. **No live source yet**: apps send
  `com.canonical.Unity.LauncherEntry.Update` as broadcasts from any object path, and the QML D-Bus
  watcher of plasma-workspace 6.7.5 needs a fixed sender and path (`DBusSignalWatcher::isValid()`;
  the stock task manager's SmartLauncher is compiled into its own applet). A small compiled helper
  is needed; until then only the test hook `debugAction badge:ROW:COUNT[:PROGRESS]` sets them.
- **Motion and accent**: every duration from `Motion` (zoom `popupIn`, press `pressScale`, hover
  colours `hover`, pulse `pulse` with `loops()`, indicator `toggle`); the active fill, ring, pill and
  focus ring follow the user's accent (`FusionAccent`, the board's blues otherwise). The start-up
  pulse runs 3 / 1 / 0 cycles by `powerTier` (written by plasma-fusion-powerfx). The pen watchdog is
  1000 ms and also restarted by `Airbrush` events (PEN.md 3.8).
- **Plain south frame** (STYLE-1): the dock reads its headroom from its height (72 px plate: 16 px
  above it; 88 px: inside), so magnification keeps its full size with either frame.
- Test hooks: `debugAction` `dump-targets` (one log line with every target's rectangle, badges and
  the calendar day; TABLET T6), `add-desktop:ROW`, `badge:ROW:COUNT:PROGRESS`. Log lines use
  `console.info` (Fedora's Qt logging rules drop `console.log`).

### Verification

Private session `dk-1` (1920 x 1200 at 4/3, `build/dk/scen-dk1.sh`, EIS pointer, keyboard and touch;
the tablet script's window policy switched on for the virtual output): 20/20.

- Laptop: 48 px tiles, Search and Downloads shown, the calendar tile shows today's day (30), panel
  88.
- Tablet: 56 px tiles, no Search, Trash kept in landscape, every target at least 44 px (smallest 56;
  T6), panel 96; the gesture card appears the first time and "Got it" records it.
- T7: a touch held 2 s on an icon leaves the dock's geometry unchanged (no magnification) and opens
  the menu; a tap launches Konsole.
- Home indicator over the maximized Konsole (pill 150 against 22 above it).
- T8 (partly): a touch swipe up on the dock opens the launcher (the laptop card until LAUNCH-2).
- Portrait tablet: Start and Overview only.
- Badge 3 and progress 0.4 drawn (test hook).
- M3: "Add to Desktop" makes `~/Desktop/org.kde.konsole.desktop` → `/usr/share/applications/…`; a drag
  from the dock to the desktop gets KIO's "Link Here", which makes the Dolphin link.
- No QML warnings from the dock, no core dumps.

Touch in private sessions: a touch tap shorter than about 0.3 s, or sent right after the EIS client
connects, was often lost (the long presses arrived); the scenario waits 0.8 s and taps for 0.3 s.

Not covered here: M16/M17 (INT-1 matrix), the side-by-side against the dock board and light
screenshots (INT-1), pen hover (hand check V7).
