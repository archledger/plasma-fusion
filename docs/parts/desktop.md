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
| Page 1 | the pinned apps: the launcher's list (KActivities client `org.plasmafusion.launcher.favorites`, so pins in the launcher and on the home screen are one list) |
| Next pages | every app A to Z (Kicker `RootModel` flat, sorted, `KICKER_ALL_MODEL`) |
| Grid | 6 columns x up to 5 rows in landscape, 5 x up to 6 in portrait (TABLET2 decision 1); cells fill the width minus 48 px margins, 120 px or taller |
| Tiles | 72 px icon tiles (`FusionIconTile`, shadow 3/8 px), 13 px demibold white labels with a raised shadow, press scale 0.94 |
| Widgets | the containment's cards stay where they are on page 1; page 1's grid stops before them (a column on the right in landscape, a band at the top in portrait); on the other pages they fade out (`Motion.toggle`) |
| Page dots | 8 px, the current one 20 px wide, 10 px apart, 14 px above the dock's 128 px reserve; a tap (18 px margin) goes to that page |
| Swipe | horizontal flick, one page per swipe (`SnapOneItem`, `Motion.surface`) |
| Tap | launches the app |
| Long press, right click, pen barrel button | the app's menu: Add to / Remove from Home Screen (the pinned list), then the app's own actions (jump list, Edit Application, Hide Application...) |
| Swipe down (TABLET2 H2) | 96 px or 800 px/s, touch (and a pen, which acts as a finger in tablet posture): the launcher sheet opens with its search field focused, so the on-screen keyboard comes up (iPadOS, Android). The pages follow the finger (half the distance, up to 120 px, fading to 50 %) and spring back. The request is the launcher's `openRequest` `search:<nonce>`, written by desktop scripting over D-Bus (`evaluateScript`). A drag layer above the tiles holds a passive grab until 16 px, so taps, long presses and page flicks still reach the tiles |
| Input passthrough | presses on page 1's cards reach the cards (`containmentMask` of the home layer) |

The cards' rectangle is read from the containment's applet containers when tablet posture starts
and for 10 s after (the layout manager places them asynchronously); there is no timer on an idle
home screen.

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

- Edit mode (arrange page 1 by drag, jiggle), folders, a widget stack per page.
- App Library page with search at the end.
