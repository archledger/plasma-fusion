# Desktop containment and tablet home screen (TABLET2 H1)

`packages/plasmoids/org.plasmafusion.desktop`, built by `tools/build.d/76-desktop.sh`, installed
like an applet package at `~/.local/share/plasma/plasmoids/org.plasmafusion.desktop` (RPM:
`/usr/share/plasma/plasmoids/`).

## What it is

A copy of plasma-desktop v6.7.5 `containments/desktop/package` (Folder View, 4,638 lines of QML)
under its own plugin id, with one switch in `contents/ui/main.qml`:

- Laptop posture: upstream Folder View, unchanged (desktop icons from `~/Desktop`, the cards, the
  rubber band, the context menu, Desktop and Wallpaper settings).
- Tablet posture (`FusionTablet`): the Folder View layer is not loaded (no icons, no rubber band:
  the owner's pen "selection box" on the home screen) and `HomeLayer.qml` shows the home screen in
  the desktop window, under the apps.

The fork is a distinct containment, not a replacement of Plasma's files: Plasma lists it as a
desktop layout in Desktop and Wallpaper ("Plasma Fusion Desktop"), and switching to Folder View or
Desktop there works as for any containment. It reads Folder View's configuration keys
(`contents/config/main.xml` is upstream's), so switching between the two keeps icons, icon
positions, cards and wallpaper. Upstream decides "folder" or "desktop" mode by plugin name; the fork
counts as the folder variant (`isFolder` in `main.qml` and `config/config.qml`).

`UPSTREAM-FILES` lists the files kept as upstream; the QML linters skip them
(`tools/checks/qmlscan.py`). Small fixes in them are marked "Plasma Fusion" (accessible names for
the folder-title link, pin and home buttons and the rename field; a Kirigami duration on the two
`SmoothedAnimation`s). `main.qml`, `HomeLayer.qml` and `HomeActionMenu.qml` are Plasma Fusion code
and are linted.

## Home screen (tablet posture)

Owner decision "iPad-style" (TABLET2 section 3.2): pages of apps over the wallpaper.

| Item | Value |
|---|---|
| Home pages | the pinned apps: the launcher's list (KActivities client `org.plasmafusion.launcher.favorites`, so pins in the launcher and on the home screen are one list), page 1 first. Pins that do not fit continue on further home pages (iPadOS adds home pages), before the A-Z pages; before 2026-10-01 they were hidden. How many pins each home page holds is kept in the containment's `homePageSizes` ("7,2"; empty: page 1 fills first), so an app moved to another page does not pull its neighbours across. Layout on read (`layoutPages`): a page holds at most its capacity (page 1: the columns and rows left by the widgets; others the full grid), the rest carries on to the next page, so a rotation or a larger widget area never hides an app and turning back restores the pages; new pins fill the last page's room, then new pages; empty pages after page 1 go |
| Next pages | every app A to Z (Kicker `RootModel` flat, sorted, `KICKER_ALL_MODEL`) |
| Grid | 6 columns x up to 5 rows in landscape, 5 x up to 6 in portrait (TABLET2 decision 1); cells fill the width minus 48 px margins, 120 px or taller |
| Tiles | 72 px icon tiles (`FusionIconTile`, shadow 3/8 px), 13 px demibold white labels with a raised shadow, press scale 0.94 |
| Widgets | the containment's cards stay where they are on page 1; page 1's grid stops before them (a column on the right in landscape, a band at the top in portrait); on the other pages they fade out (`Motion.toggle`) |
| Page dots | 8 px, the current one 20 px wide, 10 px apart, 14 px above the dock's 128 px reserve; a tap goes to that page. Each dot's target is its cell, the pitch wide (dot + 10) and 44 px tall (until 2026-10-01 a containmentMask meant to add 18 px around the dot, which Qt 6.8+ ignores outside an item's bounds, so the target was the 8 px dot) |
| Swipe | horizontal flick, one page per swipe (`SnapOneItem`, `Motion.surface`) |
| Tap | launches the app |
| Long press, right click, pen barrel button | the app's menu: Add to / Remove from Home Screen (the pinned list), then the app's own actions (jump list, Edit Application, Hide Application...) |
| Swipe down (TABLET2 H2) | 96 px or 800 px/s, touch (and a pen, which acts as a finger in tablet posture): the launcher sheet opens with its search field focused, so the on-screen keyboard comes up (iPadOS, Android). The pages follow the finger (half the distance, up to 120 px, fading to 50 %) and spring back. The request is the launcher's `openRequest` `search:<nonce>`, written by desktop scripting over D-Bus (`evaluateScript`). A drag layer above the tiles holds a passive grab until 16 px, so taps, long presses and page flicks still reach the tiles |
| Input passthrough | presses on page 1's cards reach the cards (`containmentMask` of the home layer) |
| Edit mode (TABLET2 H2) | a long press on empty space, or "Edit Home Screen" in an app's menu. Page 1's tiles get a little smaller (0.92; a static cue: an endless jiggle would keep the GPU drawing, and the motion lint forbids it) and carry a 26 px remove badge (44 px target); a tile dragged onto another takes its place (`moveRow` on the pinned list; a ghost follows the finger, the target dips to 0.84); a tile dropped on a home page's dot moves to that page (its last place; on a full page the page's last app moves on to the next one, as on iPadOS; the dot turns blue and larger while the tile is over it; the view goes to that page); the A-Z pages show "+" on apps not on a home page (`addFavorite`; the view stays on the A-Z page). Every change can be undone for 5 s (Undo pill: `addFavorite(id, index)`, `removeFavorite`, `moveRow` back, page sizes restored). Done (56 px, right of the page dots, where nothing else sits on any page), a tap on empty space, Escape or leaving tablet posture ends it. While editing the cards are dimmed to 25 % and take no presses, page flicks pause (the dots still change pages) and the swipe-down search is off. The dots and pills are `AbstractButton`s: they take the press, so the page's empty-space tap (which ends edit mode) does not fire with them |

The pages are rows of a `ListModel` (home pages inserted or removed at their end, A-Z pages at the
end), not an int model, which would reset the view to page 1 whenever the count changes; the sync
runs once per event loop pass (`Qt.callLater`) with settled values, and an A-Z page in view stays in
view. Each page's proxy gets a new `filterRowCallback` when its slice changes (the proxy filters
again only then). Tested 2026-10-01 in the 6.7.5 and 6.7.91 containers at 1280x800 (page 1 holds 8):
overflow page, dot targets 16 px off the dot, a move to page 2 keeping its app, Undo, a reorder on
page 2, an add from A-Z opening a home page, a move to a full page 1, a posture round trip.

The cards' rectangle is read from the containment's applet containers when tablet posture starts
and for 10 s after (the layout manager places them asynchronously), again after a drop and when a
widget is added or removed, and every 0.5 s while a widget edit mode is on (the stock one or the
home screen's) and once it ends, so a moved or resized card stays tappable; there is no timer on an
idle home screen. A reading with no sized containers keeps the last rectangle (edit mode rebuilds
the layout for a moment); only a containment without widgets gets an empty one. The home screen's
edit state reaches the root through the full representation (`fullRepresentationItem.homeLoader`,
a property alias, as `appletsLayout`): until 0.5.0 the root read the loader's id, which is not
visible outside the full representation, so every evaluation logged "ReferenceError: homeLoader is
not defined" and a home screen edit never started the 0.5 s measuring (the stock edit mode did).
`tools/checks/id-scope-lint.py` (build step) reports such reads.

Tablet posture across a plasmashell restart (0.5.0): `tools/tests/shell-vm/tablet_restart.py`, run in
the session, turns tablet mode on, restarts plasmashell in it and goes back to the laptop (auto or
off) 0, 3, 10 and 25 s later, checking each time that KWin shows the top bar and the dock with their
posture's heights, that the desktop shows its posture's layer and that plasmashell logs no
ReferenceError or TypeError from Plasma Fusion. In the test VM (1280 x 800) the previous code passes
everything but the last check (the ReferenceError above, once per start in tablet posture), with and
without a cleared QML cache; with the alias it passes. A report of the top bar and the dock missing
after such a switch until the next plasmashell restart (seen once in another 0.5.0 track's VM) did
not happen in these eight rounds, nor in eleven manual variants (re-login in tablet posture, a
deploy that also reloads KWin's scripts, the switch during the shell's start, with the Notification
Centre, the launcher's sheet, KWin's Overview or the home screen's edit mode open); the scenario
stays as its regression test.

## The free side beside an app (tablet posture, 2026-10-18)

Board `design/boards/TabletSplit.dc.html` (SPLIT.md item 9, the owner's screencast of 2026-10-02):
an app split into one half with nothing beside it left the rest of the screen to the home screen,
where page 1 showed cut off under the app, the cards in the free half. Android and iPadOS offer the
apps there. Now the home screen does:

- **When**: one shown window of this screen, desktop and activity fills the left or the right part
  of the work area top to bottom (within 24 px of its top, bottom and one side edge, not both: a
  maximized window is at both), the part beside it is at least 240 px wide, and no other shown
  window overlaps that part by more than the gaps (`contents/ui/code/home.js`, `freeSide()`). That
  is a split from the dock or an app's menu with nothing else open, the other app of a split closed
  or sent home, or a split at the divider's 1/3 or 2/3 (KWin's quick tiles, so the split divider
  leaves its place: docs/parts/kwin-tablet.md). The windows come from the task manager's model
  (`TaskManager.TasksModel`, filtered by screen, desktop and activity, without minimized and hidden
  windows), with the geometry KWin publishes; the answer is worked out again whenever the model's
  rows or data change (one pass per event loop turn) and logged when it changes: `home: free side:
  right, 723 px from x 717 beside org.kde.kwrite.desktop`, `home: free side: none`.
- **What**: the pages, their dots and the cards step aside (the cards' opacity 0, the input mask
  covers the whole layer, edit mode ends), and the free part shows `FreeSidePicker.qml`: the board's
  tint (rgba(8,11,24,.55); light rgba(250,251,255,.62), the snap script's "Pick a window for this
  side" fill), "Pick an app for this side" (17 px, ExtraBold), the home apps under "Home" (the
  pinned list in the home pages' order) and every app A to Z under "All apps", in 128 x 120 px cells
  40 px from the sides, the list scrolling under a 120 px fade into the tint; the swipe-down search
  is off there. Only apps are offered (a pinned file or link is not). The app on the other side is
  dimmed to 40 % and takes no tap.
- **A tap** opens the app on that side: the home screen's split request (`requestSplit`, the dock's
  `startSplitForApp`), with the app-open zoom growing into the free part (`FusionLaunchZoom.play`'s
  part, docs/parts/shared-blocks.md). The request goes to the dock of the home screen's own screen
  (`splitScript()`: with a dock on every screen each dock used to start the app; with one dock only,
  on another screen, to that one). The dock moves the app in use to the other half first, which is
  where the app beside the free part already is: KWin 6.7.5 and 6.8.0 leave a window quick-tiled
  again to its own side in place on a single screen (`Window::handleQuickTileShortcut`, identical in
  both). With other windows open, "Pick a window for this side" covers the free half right after the
  split (docs/parts/kwin.md); dismissed, this picker is under it.

Tests: `tests/split-request.test.js` (node, in `76-desktop.sh`): the request against a model of
desktop scripting reaches the dock of the home screen's screen only (a dock on every screen), the
one dock when it is on another screen, not a dock of a screen that is gone, once with two docks on
one screen, nothing without a dock, the app id quoted. `tests/freeside.test.js` (node, in
`76-desktop.sh`): the halves with the snap script's gaps, both sides, two apps, nothing shown, a
maximized window, a window not top to bottom or away from the edges, the divider's 2/3 and 1/3, a
sliver too narrow, a window over the free part, a dialog in the app's half, one touching by the gaps
only, a window without a size, a work area not at 0, a portrait screen, the app ids under their
names, unchanged answers. `tests/vsession/scenario-freeside.sh` (private session on the ThinkPad,
1440 x 900, tablet posture, real touch through pfinput; 2026-10-18, fs-3): 12 checks pass - no free
side on the home screen or beside a maximized KWrite; KWrite quick-tiled left: the right part offers
the apps; a tap on Dolphin there puts Dolphin on the right (723, 717 x 836) and KWrite stays on the
left, and the free side goes; Dolphin closed: it comes back; KWrite on the right: the left part;
KWrite maximized: none; Dolphin alone on the left: its own tile asks for nothing, the next (Konsole)
opens beside it; no QML message about these files. With main's stage (e8193ac, fs-r1) the same
scenario fails 6 checks (no free side, no tap opens an app there). The scenario taps 0.6 s after
pfinput starts: the seat gains touch only when pfinput's device appears and plasmashell binds
`wl_touch` a moment later, so an immediate tap lost its down event (WAYLAND_DEBUG: the up and frame
arrived without it); a real touchscreen is always there.
`tests/vsession/scenario-freeside-screens.sh` (two outputs, "Dock on every screen", tablet posture;
fss-2): a dock on each screen; KWrite quick-tiled left on the first; one tap on Konsole in the free
part starts one Konsole, on the right, and one dock acts on the request. With the previous request
(every dock, fss-r1) the same tap started two Konsoles: both docks acted on it (one of their plans
was dropped later, its app not becoming active). Not verified: by a person's finger on the
ThinkPad's own screen, portrait, a real second monitor.

## Saved app pairs on the home screen (2026-10-19)

A favourite whose entry is a pair's (`applications:org.plasmafusion.pair-ID.desktop`) is drawn as
`FusionPairTile` and named after both apps; a tap has this screen's dock open both, held it has the
pair's menu (Open, Swap Sides, Keep in Dock, Remove Pair), and with an app gone a second line says
which and a tap opens the menu. The helper's `pinRequest` (containment configuration) pins a pair it
saved. The whole feature: [`apppairs.md`](apppairs.md).

## Installation and switch-over

- `fusion-config.sh` layout migration (plasmashell stopped): a desktop containment
  `org.kde.desktopcontainment` or `org.kde.plasma.folder` becomes `org.plasmafusion.desktop` when the
  package is installed; a plain Desktop also gets the Fusion Folder View keys (an existing Folder
  View keeps its own). Without the package, Desktop becomes Folder View as before, and a desktop
  naming the missing package becomes Folder View. The layout file is in the backup.
- Both Global Themes' `defaults` name `org.plasmafusion.desktop` for new desktops; the layout script
  accepts it or `org.kde.plasma.folder`.
- The settings module and the test helpers treat both plugin ids as Folder View.
- The login check (`docs/parts/gate.md`, part `desktop`) switches the desktop to stock Folder View
  after a plasma-desktop, plasma-workspace, libplasma or Qt update, with a missing package, or under
  another Global Theme, and back afterwards.

## Tests

`build/home/scen-home.sh` (private session, 1920x1200 at 4/3): the containment switched to the fork,
laptop posture Folder View with cards and no QML errors; tablet posture page 1 with the pinned apps
in 5 columns beside the cards, page 2 after a swipe with apps A to Z in 6 columns, a tap on the first
tile of page 2 started Akregator, laptop posture again Folder View. Evidence:
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-10-01-tablet2/H1/`. `scen-home2.sh`: the installer
built the layout with the fork, long press and right click open the menu (Firefox's jump list
included), the login check's dry run with plasma-desktop 6.8.0 switches the containment and words
the notification. `scen-home3.sh` (H2): a 70 px drag does nothing, a 300 px swipe down opens the
sheet with the search focused and the keyboard visible (KWin `VirtualKeyboard` visible and active),
page flicks and taps unchanged.

## Open (TABLET2 H1/H2 remainder)

- Folders, a widget stack per page; dragging an app across pages.
- App Library page with search at the end.

Edit mode tests (`build/he/scen-he2.sh`, he7; evidence
`artifacts/plasma-fusion/2026-10-01-tablet2/H1/edit`): long press on an empty cell enters it (badges,
cards dimmed, Done); Done leaves it; the Firefox badge removes Firefox and shows Undo; Undo puts it
back in place; the second page dot opens the A-Z page with "+" on unpinned apps; "+" on Akregator adds
it; after Done Akregator is last on page 1. he1: a drag from Discover's tile to Maps' cell moved
Discover there (with Undo). The model's `favorites` list reads empty from QML, so tiles pass their own
`favoriteId`.

## Widgets on the tablet home screen (2026-10-01, owner: "the placement of the widgets needs adjustment, in whatever orientation")

The cards are the containment's applets, placed by Plasma's layout manager and saved per screen
size (`ItemGeometries-WxH`): in tablet posture they stayed where the laptop desktop had them, and in
portrait (900 x 1440) they kept a landscape-shaped place in the top right corner (and the system card
hid itself there). Now the tablet home screen has its own saved layout per size and orientation
(`ItemGeometriesTablet-WxH`; fallback key `ItemGeometriesTablet{Horizontal,Vertical}`), so the
laptop desktop's layout (the same 1440 x 900 key in landscape) is never touched. The first time a
tablet layout is used, the cards are arranged (`arrangeTabletCards`): landscape, a column 24 px from
the right edge (more columns leftwards if they do not fit); portrait, a row across the top from the
grid's 48 px left edge (more rows if they do not fit); 24 px from the top, 16 px apart, the dock's
128 px and the page dots kept clear, each card keeping its size. The containers animate x and y, so
the layout manager assigns the space 500 ms later (`positionItem`, then `save`). The key is then
listed in `tabletCardsArranged`, so moves in edit mode stay the user's. The system card no longer
hides in tablet portrait (it has room in the row); it still gives way where it would reach the dock.
Test (6.7.5 container, cardsP5 1200x1920 and cardsL5 1920x1200 at 4/3): portrait, weather, calendar
and system in a row at the top, the apps below; landscape, the column at the right, 5 app columns;
leaving tablet posture restores the laptop positions exactly (scripting geometry before = after).
