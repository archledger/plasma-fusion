# Part: centred launcher (`org.plasmafusion.launcher`)

The start menu of the Launcher / LauncherLight boards: a 680 x 700 card centred on the screen
above the dock, with a search field, category chips, pinned apps, recently used files and a
user/session footer. Plasma 6 applet (QML only), GPL-2.0-or-later.

## Files

| Path | What |
|---|---|
| `packages/plasmoids/org.plasmafusion.launcher/metadata.json` | Plasma/Applet metadata, `X-Plasma-Provides: org.kde.plasma.launchermenu` (Meta key) |
| `.../contents/config/main.xml`, `config.qml`, `ui/ConfigGeneral.qml` | settings (see below) and their page |
| `.../contents/ui/main.qml` | applet: Kicker models, default pins, open/close, placement, `expanded` mirroring |
| `.../contents/ui/LauncherButton.qml` | panel button: Fusion logo as 48 px dock tile, 32 x 26 top-bar pill, plain logo, or hidden |
| `.../contents/ui/LauncherWindow.qml` | the card window (`PlasmaCore.Dialog`, applet-popup role, explicit position, style frame with the `launcher` prefix) |
| `.../contents/ui/BackdropWindow.qml` | dim layer behind the card |
| `.../contents/ui/LauncherCard.qml` | card content in board coordinates; views home / category / all apps / recent / search; keyboard map |
| `.../contents/ui/SearchBox.qml`, `Chip.qml`, `PillButton.qml`, `SectionHeader.qml`, `RoundButton.qml`, `FocusRing.qml`, `ThinScrollBar.qml` | controls of the board |
| `.../contents/ui/NavGrid.qml`, `AppGrid.qml`, `AppTile.qml`, `DocGrid.qml`, `DocItem.qml`, `ResultsList.qml` | grids and lists |
| `.../contents/ui/Footer.qml` | avatar or letter, real full name, "Local account" (account menu), Lock / Sleep (Hibernate menu) / Restart / Shut Down |
| `.../contents/ui/ActionMenu.qml` | right-click / Menu-key menu: Pin/Unpin, Keep in Dock (when the Fusion dock is in the panel) plus the model's own actions |
| `.../contents/ui/FusionColors.qml` | dark and light tints of the boards |
| `.../contents/ui/FusionText.qml` | text in CSS px and CSS weight (see "Manrope weights") |
| `.../contents/ui/Glyph.qml`, `FusionLogo.qml`, `code/launcher.js` | the boards' stroke glyphs and logo, category/file-type/design-name tables |
| `.../contents/icons/fusion-logo.svg` | the three-circle logo (24 x 24), usable by other parts |
| `tools/build.d/72-launcher.sh` | copies the package to `$STAGE/.local/share/plasma/plasmoids/org.plasmafusion.launcher` |

## Install and use

- Build: `bash tools/build.sh launcher` (or all parts). Per-user install from the repo:
  `kpackagetool6 -t Plasma/Applet -i packages/plasmoids/org.plasmafusion.launcher`
  (`-u` to upgrade), then restart plasmashell (`systemctl --user restart plasma-plasmashell`).
- The applet must sit in a **panel** so that Meta (plasmashell's "Activate Application Launcher",
  D-Bus `org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu`) finds it;
  the first launcher-providing applet in a panel of the active screen is used. Where it sits does
  not change where the card opens.
- Card placement: 680 px wide, centred on the applet's screen; bottom edge at
  `min(screen bottom - bottomOffset, bottom of the available area - 4)`, height 700 (smaller
  screens: down to 420, pinned rows and "Recommended" shrink first). With the Plasma Fusion dock
  this gives the board's 92..792 at 1440 x 900 (verified).

### Settings (`[General]` of the applet, e.g. via layout script `writeConfig`)

| Key | Default | Meaning |
|---|---|---|
| `buttonStyle` | `auto` | `auto`: tile when the panel is at least 36 px thick, else pill; `icon`; `hidden` (zero size, used next to the Fusion dock which draws Start itself) |
| `favorites` | design list | default pins, used once (first run). Entries are desktop ids or `preferred://browser`; `a|b|c` = first installed alternative. They are inserted/moved to the front one by one (`addFavorite(id, index)` / `moveRow`), not with `portOldFavorites()`, which Fedora's `kicker-extra-favoritesrc` (`IgnoreDefaults=true`) would replace with its own list |
| `favoritesPortedToKAstats` | false | set after the default pins were written |
| `favoritesClientId` | `org.plasmafusion.launcher.favorites` | KActivities client id (pin order); pins themselves are shared with every launcher, Kickoff included |
| `designLabels` | true | short design names (Files, Browser, Terminal...) on the pinned tiles of the default apps; the real name is the tooltip |
| `dimBackground` | true | dim layer rgba(6,8,18,0.4) dark / rgba(221,230,244,0.35) light |
| `bottomOffset` | 108 | 16 px dock gap + 74 px dock + 18 px |
| `showRecommended` | true | recent files section |
| `openRequest` | "" | written by other parts through desktop scripting: `<mode>:<nonce>[:<argument>]`, modes `home`, `search` (argument = query), `apps`, `recent`, `category` (argument = key such as `graphics`) |
| `hiddenApplications` | [] | Kicker's "Hide Application" list |

### API for other parts

- `expanded` of the applet item mirrors the open state. Setting it opens or closes the card
  (this is what the Fusion dock's Start button does). The one automatic `expanded = true` that
  Plasma emits when it first shows an inline applet is ignored.
- Functions on the applet item: `open(mode, argument)` (modes as above; `open("search", "text")`
  pre-fills the search), `close()`, `toggle()`. The dock's Search button can use
  `launcherApplet.open("search")` when it finds the applet, or the D-Bus call above.
- The search field is focused whenever the card opens, so "Start" and "Search" both land in search.

## Behaviour

- Models: `Kicker.RootModel` (flat, all apps + categories), its `KAStatsFavoritesModel`,
  `Kicker.RunnerModel` (merged KRunner results), `Kicker.RecentUsageModel` (documents, recent
  first) - the models Kickoff uses.
- Chips: "All" plus every non-empty XDG menu category, identified by its directory icon
  (locale independent), duplicates and "Lost & Found" dropped, ordered Development, Graphics,
  Internet, Multimedia, Office, System, then Games, Education, Science, Utilities, Settings, Help.
  Chips that do not fit go into a round "..." chip with a menu.
- Pinned: 6 columns, 3 rows visible (scrolls beyond 18). First run pins, per slot, the first
  installed of: Dolphin, default browser, Konsole, KMail, Kate/KDevelop/Code/KWrite, Elisa,
  Gwenview, System Settings, KOrganizer, Marknote/KNotes, KCalc, Discover, Haruna/Dragon/VLC,
  NeoChat, Marble/GNOME Maps, KWeather/GNOME Weather, System Monitor, Spectacle (GNOME apps as last
  fallbacks). On the ThinkPad: 17 of 18 (no Notes app installed).
- Recommended: 4 most recent files, "More" lists all. Subtitle "Folder · age" ("12 min ago",
  "3 hours ago", "Yesterday", "2 days ago", then the date); the age is the file's modification
  time (see deviations).
- Search: typing anywhere in the card goes to the field (Backspace too); results grouped by
  KRunner category; Enter launches the highlighted (top) result, also when pressed before results
  arrive. Enter in the empty field does nothing.
- Hover: a tile, file or result is highlighted and selected only after the pointer moves; items
  that appear or scroll under a resting pointer do not take the selection (so Enter still
  launches the top result, and the hover highlight is never shown twice).
- Footer: face image (`~/.face.icon` via KUser) or the first letter on #7b5cd6, full name
  (login name when the full name is empty), "Local account". The account row opens a menu, as the
  Windows account menu and the stock launcher's leave entries: Account Settings… (Users settings),
  Switch User and Log Out (each where the session allows it; Log Out asks as configured).
  Lock, Sleep, Restart (asks), Shut Down (asks); buttons are disabled when logind forbids them.
  Where the system can hibernate, Sleep's menu (right-click, press and hold or the Menu key) offers Hibernate,
  in the footer and in the tablet sheet.
- Keyboard: Down from search goes to the pinned grid (to results while searching); arrows move
  in grids (the home "Recommended" grid keeps the selection in its four visible files); Up from
  a top row goes back to chips/search; Tab / Shift+Tab walk search, chips,
  header button, grid, "More", recent files, footer; Left/Right switch chips; Enter/Space
  launch; Menu key opens the item menu; Esc clears the search, then returns to Home, then closes
  (from the search field, the chips, a grid or the result list alike).
  Keyboard focus shows the Controls board's 2 px ring.

## Verification

- `qmllint` on every file: only the usual unqualified-`i18n` notes and three type-inference notes.
- `kpackagetool6 -t Plasma/Applet -i` and `--show` in a sandbox HOME: installs and reads the metadata.
- Offscreen harness (PySide6 + the real QML, mock models, board wallpaper; test files in the
  evidence folder): layout against the board, and keyboard sequences with QTest (Down/Right into
  the grid, grid -> recent files, Tab through chips into a category, Up back to search, Esc closes).
- ThinkPad virtual sessions (prefix `ln-`): Meta via `activateLauncherMenu` toggles the card
  open/closed repeatedly; the window becomes active (keyboard focus); `openRequest` modes search
  ("dolphin" -> Dolphin + System Settings results), all apps, category Graphics; dark and light with
  the Fusion colour schemes and Plasma style; standalone dock (launcher tile) and the Plasma Fusion
  Global Theme layout (Fusion dock + top bar). No QML warnings from the launcher in plasmashell's log.
- Pixel checks against the renders (same 1440 x 900 geometry): card at 380,92 680x700; dim, card fill
  under blur and search field within 1-3 RGB units of the board in both variants.
- Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/shell-launcher/`
  (`board-vs-launcher-{dark,light}.png`, `fusion-layout-*`, `standalone-*`,
  `keyboard-navigation-offscreen.png`, `manrope-qt-synthetic-bold-vs-wght-axis.png`, `test/`).

## Deviations from the board

- Shadow: the card uses the Plasma style's dialog shadow (0 18 44 at 0.45) - Plasma shares one
  shadow set for all dialogs; the board's 0 40 110 at 0.55 would need its own window shadow.
- Blur strength and saturation are KWin-global (not 40 px just for the launcher).
- Tile icons come from the icon theme (Breeze in the tests; the Fusion icon theme supplies the
  rounded tiles).
- "12 min ago" is the file modification time: the activity manager's last-use time is not
  exposed to QML and access times change whenever an indexer or thumbnailer reads a file.
- The board's highlighted Browser tile and first recent file are hover/focus states; they appear
  on hover or keyboard focus only.
- Categories that do not fit in the chip row are behind a "..." chip (the board has no overflow).
- Pins are shared by all Plasma launchers; pins that existed before (for example Kickoff's default
  Kontact on a fresh profile) stay after the design's set.
- "Local account" is a fixed label.
- Not implemented: drag-and-drop from tiles to the desktop/panel, reordering pins by drag,
  right-to-left layout review.
- The frame corner radius comes from the style (`launcher-` elements, 26 px); with another
  Plasma style the card uses that style's dialog frame and radius (Breeze: about 6 px) - checked.

## Needs from other parts

- Plasma style: keep the `launcher-*` frame and `mask-launcher-*` elements in
  `dialogs/background` (radius 26, margins 18). The launcher selects them by setting the
  prefix of the dialog's own frame item; without them it falls back to the plain frame.
- Fonts / Global Theme: Qt puts a synthetic bold on top of the variable Manrope's named Bold and
  ExtraBold instances, so 700/800 text renders much heavier than the design (see
  `manrope-qt-synthetic-bold-vs-wght-axis.png`). The launcher avoids it by setting weights on the
  `wght` axis (`FusionText.qml`). Other parts using Manrope at 700+ (window titles at 800, the top
  bar, quick settings) will look too bold unless static instances are shipped or they use the axis.
- Icons: rounded tiles for the pinned apps' Icon= names (dolphin, konsole, kmail, kwrite/kate,
  elisa, gwenview, preferences-system, korganizer, accessories-calculator, plasmadiscover,
  dragonplayer, org.kde.neochat, org.gnome.Maps, org.gnome.Weather, utilities-system-monitor,
  spectacle, browser).
- Layout (look-and-feel): in the test (`plasma-apply-lookandfeel -a org.plasmafusion.<v>.desktop
  --resetLayout` in a virtual session) the Global Theme did not set `plasmarc [Theme] name`
  (Plasma style stayed Breeze until `plasma-apply-desktoptheme`), and the pinned tiles still
  showed Breeze app icons although the staged `PlasmaFusion-Dark` icon theme was present (not
  investigated further; not a launcher setting). When `org.plasmafusion.appname`
  is missing the layout puts the launcher in the top bar; the dock then cannot see it
  (`findLauncherApplet` only looks in its own panel), so its Start button shows no pressed state.
- Dock: bind the Start button's pressed state to the launcher applet's `expanded` (works when
  both are in the dock panel); use `open("search")` for the Search button if a distinct entry is wanted.

## Review (2026-09-29)

Second pass by a reviewer, with real input: key and pointer events were injected into the
private virtual sessions through KWin's EIS interface (`org.kde.KWin.EIS.RemoteDesktop`,
libei via ctypes; the tool is `review-test/pfv-input.py` in the evidence folder). So Meta is the
real modifier-only shortcut, typing goes through the keyboard, and clicks and right-clicks are
real pointer events. Every part was built into one stage (`tools/build.sh` with no arguments) and
applied with the Plasma Fusion Global Theme, Fusion style, colours and icons, dark and light,
with Fedora's `XDG_CONFIG_DIRS` (it includes `/usr/share/kde-settings/kde-profile/default/xdg`).

### Checked

- Board values against `Launcher.dc.html` / `LauncherLight.dc.html`: card 680 x 700 at 380,92
  (radius 26 from the style's `launcher-` frame), dim layer, search field (50 px, radius 25,
  1.5 px accent border, Meta badge), chips (30 px, 14 px padding, 12 px 800/700), section
  headers and pills, 6 x 84 px tiles with 4 px gaps and 52 px icons, 2-column 52 px recent rows,
  62 px footer with 36 px avatar and 38 px round buttons (red power), in both variants. Pixel
  samples at the same coordinates are within 1-4 RGB units of the renders (dim layer, card
  fill, footer band, tile hover, avatar, power button; the 1 px footer and bottom edges fall on
  fractional rows in the render). Side-by-sides: `review-board-vs-build-{dark,light}.png`.
- Behaviour, live: Meta opens/closes, dock Start opens and shows its pressed state, hover,
  search typing, Down into results, Esc in every focus position, grid keyboard ring, Tab into
  chips and Right into a category, All apps, More (12 files), right-click menus on pins and
  files, the "..." category menu and choosing Games from it, click on the dim layer closes,
  Enter launches the highlighted result, the applet's settings dialog.
- Logs: no warning from the launcher's files in `plasmashell` logs in any run.
- `qmllint` (Qt 6.11.2) on all QML files: only unqualified `i18n` notes and 11 type-inference
  notes on dynamic objects (Instantiator delegates, `Dialog.margins`, delegate `model`).
  `metadata.json` and `main.xml` parse; the logo SVG renders in QtSvg; `tools/build.sh launcher`
  output is identical to the package directory.

### Fixed

1. Esc in the result list or a grid typed the ESC control character into the search field
   (the key handlers forwarded any `event.text`), so Esc neither cleared nor closed; the text
   became a query of an invisible character. Only printable text is forwarded now
   (`Launcher.isPrintable`), so Esc reaches the card; Backspace in a list/grid edits the field.
2. Items under a resting pointer took the selection whenever they appeared or scrolled there
   (`onPositionChanged` fires for those too): with the pointer over the card, typing a query
   selected the result under the pointer, and Enter launched that instead of the top result
   (seen live: "dol" + Enter chose Konsole). Hover now selects only after the pointer really
   moves (`NavGrid.pointerMovedTo`, the same in `ResultsList`); reset when the card opens and
   when the query changes.
3. Default pins used `KAStatsFavoritesModel.portOldFavorites()`, which ignores the given list
   when the distribution's `kicker-extra-favoritesrc` has `IgnoreDefaults=true`. Fedora ships
   one (`Prepend=` 7 apps) in `XDG_CONFIG_DIRS` of the real session, so the design's 18 would
   never have been pinned on the ThinkPad (the earlier test session did not have that
   directory). Pins are now inserted or moved to their place one by one; checked live with
   Fedora's directory: 17 design apps in design order, then the pre-existing Kontact.
4. The home "Recommended" grid shows 4 files of a longer list, but Right/Down moved the
   keyboard selection into the hidden rows (invisible focus). Navigation is limited to the
   visible 4 (`NavGrid.limit`); "More" lists all.
5. The applet settings dialog logged 15 "Setting initial properties failed ... cfg_..." lines
   (the dialog passes every key and its `...Default`). The page now declares them and refreshes
   the non-edited keys from the live configuration in `saveConfig()`, so saving cannot write
   back a stale `favoritesPortedToKAstats`/`openRequest`. Only Plasma's own "not placed in the
   graphics scene" line remains (stock Kickoff logs the same plus 21 property errors).
6. Pinned columns were `floor(width / 6)` wide, so the last column ended 4 px short of the
   board's grid; cells are now fractional like the board (icons snapped to whole pixels).
7. The search glyph and text sat 1.5 px left of the board (the border is inside the board's
   box); fixed.
8. Enter in the empty search field launched a grid item still selected from earlier keyboard
   navigation; it now does nothing there.
9. Smaller: recent-file age "2 days ago" as on the board (was the weekday name); the "..."
   category menu showed checkboxes, now a check mark on the current one; `decodeURIComponent`
   on a malformed file URL threw; a reused recent-file row could keep the previous file's age;
   the pinned grid could not scroll when fewer than 3 rows fit.

### Remains / not changed

- Deviations listed above stand (shared dialog shadow, global blur, recency order,
  modification-time ages, "Local account" label, overflow chip, no drag-and-drop).
- One right-click in one light run did not open the menu; five repeats (pins and files) did.
  Treated as test-input timing, not reproduced.
- Real ThinkPad session (touch, tablet mode, 4/3 scale) not tested; everything above ran in
  1440 x 900 virtual sessions.
- The Global Theme still leaves `plasmarc [Theme]` and `kdeglobals [Icons]` unset after
  `plasma-apply-lookandfeel` in the virtual session (look-and-feel part; see above).

### Review evidence

`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/shell-launcher/`:
`review-{dark,light}-01..13-*.png` (home, hover, search with a resting pointer, keyboard into
results, Esc clears, grid keyboard ring, Esc closes, dock Start + category, All apps, More,
context menu, more-categories menu, dim-layer click closes), `review-board-vs-build-*.png`,
`review-dark-recommended-keyboard-limit.png`, `review-dark-more-twelve-files.png`,
`review-config-dialog.png`, and `review-test/` (EIS input tool, scenarios).

## Polish (2026-09-29)

See `docs/parts/polish.md`. `FusionText.qml` uses the CSS weight as the font weight: the static
per-weight Manrope files ignore the `wght` axis the old workaround used, so every launcher label
was drawn regular. Right-click on a pinned tile opened the context menu 3 of 3 times with real
input (the intermittent miss of the review was not reproduced).

## LAUNCH-1 (2026-09-30): drag to the desktop, pins, search, size, cost

Work package LAUNCH-1 of the one-pass plan (BACKLOG M3, M8, S2, S10; ADAPTIVE 5.6 and fix 27; GAPS C7;
EFFECTS 5), built by the lead directly.

### Changes

- **Drag an app to the desktop** (M3): a `DragHandler` on every app tile (mouse, touchpad, pen; a finger
  scrolls the grid) starts Kicker's `DragHelper` with the app's desktop file, a 48 px drag image and an
  extra `application/x-xbel` type. KIO's DropJob treats a drop carrying that type as a bookmark and
  links it without the Move/Copy/Link menu, so Folder View gets a symlink to the system desktop file
  (it starts without a trust prompt) at the drop position. The launcher closes when the drag leaves
  its card (and at the latest when the drag ends); the check runs through `Qt.callLater`, because
  QML timers stand still during the drag's own event loop.
- **Reorder the pins** (GAPS C7): the same drag dropped on the pinned grid moves that pin there
  (`favoritesModel.moveRow`); a card-wide drop area below the grid tells a hand-over inside the card
  from leaving it.
- **Tiles** (fix 27, S2): `FusionIconTile` (the neutral tile for icons outside the Fusion theme) over one
  `RectangularShadow` instead of a `MultiEffect` layer per tile.
- **Built on idle** (S2): the card is an asynchronous `Loader` in the launcher window, built 4 s after
  start or at once when the pointer reaches the Start button; an open request before that waits for it.
- **Size and placement** (ADAPTIVE 5.6): height clamp(0.78 H, 420, 700) scaled with the text, 960 with up
  to five pinned rows in portrait; opens on KWin's active screen when there are several (with the dim
  layer there); an on-screen keyboard pushes the card up (Qt's keyboard rectangle, else the lower 40 %
  while it is shown).
- **Search** (S10, decision 6): the runners are a fixed list without web or network runners (web
  shortcuts, bookmarks, browser history and tabs, dictionary, software centre, contacts, spelling);
  every search key already opens the launcher (DEVICE-1), KRunner keeps no key. The sections still come
  in Kicker's merged order (relevance), not a fixed Top hit / Apps / Settings / Files order.
- **Caret** (EFFECTS 5): blinks for 10 s after the last input or focus change, then stays on, so an open
  and untouched launcher draws no frames.
- **Recent files** (M8): the menu of a recent file says "Hide from Recent Files" and "Clear Recent Files"
  (Kicker's forget actions).
- Test hook: `openRequest` `frames:NONCE` logs the frames drawn since the last request, the geometry,
  pinned rows, columns and the pinned tiles' centres; log lines for the first frame of each open and the
  first search results.

### Verification

- `qmllint` (Qt 6.11): only warnings that HEAD already had (Kicker model roles on QObject, the dialog's
  margins); `a11y-lint` and `motion-lint`: no launcher findings (the dim layer's pointer area marked).
- Private sessions (1920 x 1200 at 4/3; `build/l1/scen-l1a.sh`, `scen-l1c.sh`):
  - M3: a pinned tile dragged to (260, 250) became `~/Desktop/org.kde.dolphin.desktop ->
    /usr/share/applications/org.kde.dolphin.desktop`, shown at the drop cell with the link emblem; no
    menu window; the link existed before the input tool returned (the exact delay to the icon was not
    measured). The launcher closed when the drag left the card in two of three runs, and at the drop in
    the third.
  - C7: pin 0 dropped on pin 2 moved there.
  - "Meta, fir, Enter" typed at once launched Firefox; the first results for "fi" came after 82 ms; no
    KRunner process in the session.
  - 0 frames in 5 s with the launcher open and untouched after the caret's 10 s.
  - M09 (portrait): five pinned rows in a 960 px card.
- `l1d` (two 1024 x 768 outputs at 1): M19 the card inside the screen (680 x 599); M18 with the pointer on
  the second screen the launcher opened there.
- Cost (A/B `l1b`, HEAD's package with the same timing log): first open after login 224 ms against HEAD's
  248 ms, later opens 83 / 42 ms against 81 / 42 ms; plasmashell GEM +71 MiB on the first open against
  +72 MiB. The plan's budgets (50 ms, 30 MiB) are not met; the full-screen dim layer is most of it: with
  `dimBackground=false` the first open is 111 ms, later opens 47 / 16 ms and GEM +28 MiB. Whether to keep
  the dim layer is left to the owner.
- Not in LAUNCH-1: the fixed section order of the search, a finger drag (touch scrolls the grids; the
  tablet sheet is LAUNCH-2).

## LAUNCH-2 (2026-09-30): the launcher sheet in tablet posture

Work package LAUNCH-2 of the one-pass plan (TABLET 4.5), built by the lead directly.

### Changes

- **`SheetWindow.qml`**: a full-screen, frameless normal-layer dialog without the style's background (no
  KWin blur; the top bar and the dock stay above it). It takes the focus (the dim layer's
  `WindowDoesNotAcceptFocus` is not set), does not hide by itself, and the launcher closes it when
  another window becomes active. The sheet inside is an asynchronous `Loader`, built 3 s after tablet
  posture starts or on first use, then kept; the icon delegates exist only while it is shown.
- **`TabletSheet.qml`**: the Tinted backdrop (`FusionBackdrop`, the wallpaper's static blurred copy); a
  search pill (560 x 48, narrower where the session buttons need the room; at the grid's left edge in
  portrait), not focused on open (except for an `openRequest` `search:`, which the home screen's swipe
  down sends: then the field is focused and the keyboard comes up, TABLET2 H2); four 44 px session buttons right-aligned to the grid; the page title;
  pages of 128 x 120 cells with 72 px `FusionIconTile`s and 13 px labels (7 columns, 5 in portrait or on
  a narrow screen, 4 below 700 px; rows from the height above the dock's 128 px reserve, at most 7),
  page 1 the pins, then all apps (one `KSortFilterProxyModel` slice per page); page dots (tappable);
  search results (the card's list, at most 720 wide) that end above the on-screen keyboard (Qt's
  keyboard rectangle, else plasma-keyboard's height rule while KWin shows its keyboard). Typing on a
  keyboard searches without touching the pill.
- **Gestures**: a horizontal swipe changes the page; a swipe down of 96 px or 800 px/s closes (the
  content follows the finger, in a layer above the tiles so taps and flicks still reach them); a tap on
  empty space, Esc, Meta, Start or launching an app closes; a long press on a tile opens its menu.
- **Open and reveal**: `progress` (0 to 1) drives the backdrop's opacity and the content's scale
  (0.96 to 1) and offset (24 px to 0). Opening animates it in `Motion.popupIn` (200 ms; the spec's
  250 ms put open-to-settled over its own 300 ms limit with the window's first frame), closing in
  `Motion.popupOut`. The dock's swipe drives it through `beginReveal()`, `updateReveal(progress)` and
  `endReveal(commit)`.
- `main.qml` routes every open to the sheet in tablet posture (FusionTablet) and to the card otherwise;
  the expanded state now follows both windows (it is read from the windows themselves: inside a
  visibleChanged handler the combined binding was one step behind and every second Meta press did
  nothing).

### Verification

- `qmllint`, `a11y-lint`, `motion-lint`: nothing new.
- Private session `l2a` (1920 x 1200 at 4/3, tablet posture; `build/l1/scen-l2a.sh`), 18 checks PASS:
  - T8: a touch swipe up on the dock opens the sheet (7 x 4 grid, 5 pages); the search field is not
    focused and KWin's keyboard is not shown.
  - T9: a horizontal swipe goes to page 2; a swipe down closes; 0 frames 1 s after closing; a tap on
    empty space closes.
  - Meta opens it (open to settled 272-295 ms, 14 frames; limits 300 ms and 20 frames); the window
    pill ("Desktop") opens it; Esc closes.
  - 0 frames in 5 s while open and untouched.
  - A tap on the pill focuses the field and the keyboard appears; "kons" and Enter start Konsole and
    the sheet closes; the next open has no focus in the field again.
  - Portrait: 5 x 7 grid. Laptop posture: the card.
- plasmashell GPU memory on the first open: +82 to +83 MiB against the 30 MiB budget (BACKLOG S2). A
  full-screen surface at 1920 x 1200 needs about 9 MiB per buffer (swap chain and depth: about 37 MiB)
  before any content; the budget cannot hold for a full-screen sheet. Left to the owner with the
  card's dim-layer question (LAUNCH-1).
- In the private session the backdrop showed only its tint (the wallpaper query gave nothing there);
  the wallpaper copy is part of the INT-1 screenshots in the deployed session.
- Not done: the date on a calendar app's tile (the dock has it), GPU time per animation frame (the INT-1
  perf run measures it).
