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
dock.location = "bottom"; dock.height = 88; dock.floating = true; dock.lengthMode = "fit";
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
