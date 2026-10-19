<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Saved app pairs

Status: new in the release after 0.6.0 (ROADMAP item 2's last part, SPLIT.md item 5; owner decision
2026-10-19: saved from the app switcher, the icon "two tiles on a plate", the details below). Board
`design/boards/TabletPairs.dc.html` (34). Keep in Dock came a pull request later (2026-10-19).
Last edited 2026-10-19.

## What it is

Two apps used together, saved as one icon: a tap opens both side by side, each in its half, as
Android's app pairs (Pixel Tablet, Android 15: two apps in split screen, Overview, "Save app pair";
the pair goes on the Home screen and can be added to the taskbar).

- **Saving:** with two apps side by side, the app switcher (the navigation effect) shows them as one
  card. "Save pair" under that card, beside the switcher's Close All (a button of the same kind:
  Close All sits centred under the cards), saves them, the app on the left first, with the split as
  it is (1/3, 1/2 or 2/3, the divider's snaps). The pair goes on the home screen after its apps. The
  same two apps in the same order are saved once (the split is updated); the button then says
  "Saved". An app whose desktop entry is not installed (KWin's desktop file name finds none in the
  applications directories) cannot be part of a pair: the button is not shown. The switcher works
  on the laptop too, where the home screen's layer is not loaded: the pin request waits in the
  containment's configuration and is taken when tablet posture loads the home screen; a request is
  cleared once taken, so a pair removed since is not pinned again.
- **Opening:** a tap on the pair's tile has this screen's dock open both: the first app to the
  left half, then the second to the right one, each the split request's way (activated if it runs,
  else started, then quick-tiled once it is the active window); the app in use stays where it is,
  behind the pair. An app already open on another screen comes to this one first: with a dock on
  every screen each dock lists only its own screen's windows, so the dock looks among every
  screen's windows, activates that one and moves it with KWin's "Window to Next Screen" (a screen
  at a time) instead of starting a second one. Then the split is set as saved. On the laptop the
  same, as the left and right snap halves.
- **Changing:** held, the pair's menu: Open, Swap Sides, Keep in Dock, Remove Pair (and Edit Home
  Screen).
  Swap Sides keeps the split's place: the app now on the left takes the left part's size. Remove
  Pair unpins the pair, from the docks too, and deletes it at once (no undo: the entry is gone
  with it); in edit mode the tile's remove button does the same. Keep in Dock pins the pair in
  this screen's dock, where it is drawn the same way, named the same, and a tap (or a middle click)
  opens it as on the home screen; held there, its menu has Open and Keep in Dock (unchecking it
  unpins). Its name is both apps' names, "Dolphin · Firefox", in the apps' own language.
- **An app gone:** when one of the two apps is uninstalled, its tile shows faded and grey, a second
  line says which ("Firefox is not installed"), and a tap opens the menu (Remove Pair only) instead
  of opening half of the pair.

## How a pair is kept

A pair is an application entry of its own, so the home screen holds it as it holds an app (its
pinned list is KDE's activity-statistics favourites, which take application entries):

    ~/.local/share/applications/org.plasmafusion.pair-ID.desktop

    [Desktop Entry]
    Type=Application
    Name=Dolphin · Firefox
    Comment=App pair: opens both apps side by side
    Icon=view-split-left-right
    Exec="…/plasma-fusion-app-pair" open %k
    NoDisplay=true
    StartupNotify=false
    X-PlasmaFusion-PairLeft=org.kde.dolphin.desktop
    X-PlasmaFusion-PairRight=firefox.desktop
    X-PlasmaFusion-PairShare=0.3333

`NoDisplay` keeps it out of the app lists (Kicker's all-apps model leaves those out; a favourite is
an application entry whatever `NoDisplay` says: plasma-workspace 6.7.5 `AppEntry` validates the
service only). `Exec` opens it from anywhere else that starts applications; it names the helper as
it was called, with its links kept (on NixOS `/run/current-system/sw/libexec/...`, which outlives
the store generation behind it).

The dock's `pairRequest` and `keepRequest` and the home screen's `pinRequest` are one-time requests:
a dock copied for another screen (`ensure-topbars.js`), an exported layout (`export-layout.js`) and
the settings file's layout (`settingsfile.cpp`) leave them out, as they leave out `splitRequest`.

A pair is the user's data, like a pinned app: `fusion-restore.sh` keeps it (it restores the setup's
configuration). Without Plasma Fusion's home screen nothing shows it, as it is hidden from the app
lists.

## Parts

| Part | Where | What it does |
|---|---|---|
| The helper | `packages/apppairs/plasma-fusion-app-pair` (libexec, `tools/build.d/83-apppairs.sh`) | `save LEFT RIGHT SHARE`: writes the entry (the apps' desktop file ids, the split snapped to 1/3, 1/2 or 2/3; both apps' names from their entries, the user's first), rebuilds KDE's application cache (`kbuildsycoca6`), then asks the home screen to pin it (desktop scripting: the `org.plasmafusion.desktop` containments' `pinRequest`, "nonce:applications:ID"); prints the pair's id. `swap PAIR`, `remove PAIR` (the user's entries only; first out of every dock's pins, desktop scripting), `open PAIR` (the first screen's dock's `pairRequest`). |
| Save pair | `packages/navigation-cpp` (`TaskSwitcher.qml`, `FusionNavigationState::appEntryId()` and `saveAppPair()`) | The button beside Close All while the current card is a pair (`taskList.getTaskAt(currentTaskIndex)`); starts the helper's `save` from the helper directories in the setup's order (`HELPER_DIRS`). Logs "plasmafusion-navigation: Save pair for LEFT \| RIGHT at X,Y" when shown and "save app pair LEFT \| RIGHT, split S". |
| The pair's tile and menu | `org.plasmafusion.desktop` (`HomeLayer.qml`, `HomeActionMenu.qml`, `FusionPairs.js`) | A favourite `applications:org.plasmafusion.pair-ID.desktop` is a pair: its entry and each app's are read with QtCore `Settings` (read only, no declared properties); the apps' names and icons come from the all-apps model, else their desktop files in the data directories (an app the menus hide), else the app is gone. A tap writes this screen's dock's `pairRequest`; Swap Sides and Remove Pair run the helper (Plasma 5 Support's executable engine). `pinRequest` pins a pair's entry only. Keep in Dock writes this screen's dock's `keepRequest`. Logs "home: pair tile: ID at X,Y", "home: pair: …". |
| Kept in the dock | `org.plasmafusion.dock` (`main.qml`: `keepRequest`, `pairFor()`; `TaskItem.qml`) | `keepRequest` "nonce:applications:ID" pins a pair's entry (`setAppPinned`, a pair's only) once the request's script has returned, so that the pin is saved ([`shell-dock.md`](shell-dock.md)). A row whose app id is a pair's entry is drawn with `FusionPairTile` (the entry and the apps' desktop files read with property-less `Settings`; no magnified tile) and named after its apps (the label, not the entry's `Name`). Every way the dock starts a launcher (a tap, a middle click, Shift, Meta+Alt+N, the menu's Open) opens the pair here (`openPair()` → `startPair()`), never the entry's `Exec`; its menu is Open and Keep in Dock only, and no file drop, split drag or desktop drag takes it. With an app gone, a tap opens that menu without Open. An app installed or removed meanwhile is seen at once (libtaskmanager re-sends every launcher's `AppId` on KSycoca's `databaseChanged`). Logs "dock: pair tile: ID at X,Y", "dock: pair menu ID "NAME": ENTRIES". |
| The pair logic | `packages/common/FusionPairs.js` | A shared library (`tools/build-lib/shared-qml.sh` copies a `packages/common/*.js` into the packages that name it, as it copies the QML blocks): pair ids, the entry's and the apps' keys as `Settings` reads them, the label, the dock's `pairRequest` and `keepRequest` scripts, the helper's command. |
| The icon | `packages/common/FusionPairTile.qml` | Two `FusionIconTile`s at 40 % of the size, 5 % apart, on a plate (radius 19/72, white 16 % with a 22 % edge on the dark scheme, ink 10 % with 12 % on the light one); an app gone at 35 % opacity and grey. |
| Opening | `org.plasmafusion.dock` (`main.qml`: `startPair()`, `bringToSide()`, `pairTasks`) | `pairRequest` "nonce:LEFT:RIGHT:SHARE": each app the split request's way (`splitPlan` with a `then`), without moving the app in use, looked up among every screen's windows (`pairTasks`, the dock's filters but the screen's) and moved to this screen when it is on another; 300 ms after the last tile, KWin's "Plasma Fusion: Split One Third / Half / Two Thirds". Logs "dock: pair: …". |
| The split | `plasmafusion-tablet` (`main.qml`: `splitAt()`) | Three KWin actions without a key: the active window's quick-tile split where the left part is that share of the work area (`centreSplit()` is `splitAt(w, 0.5)`). Also in System Settings' shortcuts. |

## Tests

- `packages/apppairs/tests/helper-unit.sh` (CI `build`): the helper against stand-ins for busctl and
  kbuildsycoca6, 39 checks: the entry, the split snapped, both names, the cache rebuilt before the
  pin request, the same pair saved twice, a reversed one, the `Exec` of a helper called through a
  link, swap, open, remove (its script run against a model of desktop scripting: out of every dock
  that keeps it, the other pins kept), and what it refuses.
- `packages/look-and-feel/tests/layout.test.js`: a dock copied for another screen gets no
  `pairRequest` or `keepRequest`.
- `tools/build.d/73-dock.sh` and `76-desktop.sh`: both packages hold `FusionPairs.js` (an import a
  QML engine only fails on at run time).
- `packages/common/tests/pairs.test.js` (node, in `76-desktop.sh`): a
  favourite's pair id, the pair and its apps as QtCore Settings reads their desktop files (localised
  names, commas), the label, the dock's `pairRequest` and `keepRequest` against a model of desktop
  scripting, the helper's command.
- `packages/apppairs/tests/vsession/scenario-apppairs.sh` with `make-seed.sh` (private session on
  the ThinkPad, the navigation effect built against its KWin) and `scenario-apppairs-screens.sh`
  (two screens, a dock on each): see "Verification".

## Verification

2026-10-19, the ThinkPad (KWin 6.7.5, Qt 6.11.2), private session at 1440 x 900 in tablet posture,
the navigation effect built against the same packages (`make-seed.sh`):

- **ap-4, all 14 checks pass, scenario rc 0** (ap-3 the same without step 0, 13):
  - A pair saved on the laptop (the helper's `save` before tablet posture, the home screen's layer
    not loaded) was pinned once tablet posture loaded it.
  - Dolphin quick-tiled left and KWrite right, "Plasma Fusion: Split One Third" put the split at
    477 of 1440 px.
  - The switcher logged "Save pair for org.kde.dolphin.desktop | org.kde.kwrite.desktop" under the
    pair's card, beside Close All; a tap saved the entry (Dolphin left, KWrite right, 0.3333) and
    the home screen pinned it.
  - With the split moved to half (717 px) and both apps minimized, a tap on the pair's tile opened
    Dolphin on the left and KWrite on the right at a third again (the dock's "dock: pair: …").
  - Swapped (the helper's `swap`) and the split at half again, the tile opened KWrite on the left
    and Dolphin on the right at a third.
  - A pair with an app that is not installed showed its tile (that app faded and grey, "… is not
    installed"), and a tap opened nothing; no QML errors from the switcher, the home screen, its
    pairs or the dock.
- **aps-1** (`scenario-apppairs-screens.sh`, two screens, a dock on each listing only its own
  screen's windows; all 5 checks pass): KWrite open on the second screen and Dolphin not running,
  the first screen's dock's `pairRequest` started Dolphin on the left half of the first screen and
  brought KWrite over from the second screen to its right half.
- **dk-5, Keep in Dock, all 27 checks pass, scenario rc 0** (the scenario above with steps 6 and 7;
  dk-3 the same with step 6 only, 20):
  - the dock's `keepRequest`, written through desktop scripting as the menu writes it, pinned the
    pair ("dock: pin applications:…") and the pin was in the saved configuration three seconds
    later;
  - with the split moved to half and both apps minimized, the dock drew the pair's tile at 992,844
    and a tap on it opened KWrite on the left and Dolphin on the right, at a third;
  - the pair with an app that is not installed, kept too, was drawn (that app grey) and a tap
    opened its menu, not the pair;
  - the dock's menus (its test hook): "KWrite · Dolphin": Open, Keep in Dock; the pair with an app
    gone: Keep in Dock only;
  - with the split at half again, a middle click (the hook's `new`, the same function) opened KWrite
    and Dolphin at a third from this dock: the stored `pairRequest` stayed as it was, so the entry's
    `Exec` did not run;
  - with the entry's `Name` rewritten (as if saved in another language) and the cache rebuilt, the
    dock still named the pair "KWrite · Dolphin";
  - the missing app's entry installed while plasmashell ran (a stand-in): that pair's menu had Open
    again, "Stand-in · Dolphin";
  - the helper's `remove` took the pair out of the dock's saved `launchers`; no QML errors from the
    dock or `FusionPairs.js`.
- **Red for Keep in Dock:** on main (1d736c0, dk-r1) nothing was pinned, no tile, nothing opened.
  dk-2, with the pin made while the request's script still ran, pinned and drew the pair but
  never saved it: the stored `launchers` stayed as before, also after plasmashell quit. Logging in
  the dock (dg-3) showed the new list assigned to `Plasmoid.configuration.launchers`; the scripting
  wrapper's reload at the script's end (`KConfigLoader::load`) dropped it before Plasma saved. On
  the first version of this change (72cae63, dk-r2, with dk-4's scenario) every check added after
  it failed: no pair menu (the generic one, in steps 6 and 7), a middle click ran the entry's
  `Exec` (a new `pairRequest` was stored), and the pin stayed after Remove Pair. (dk-4, on the
  fixed code, failed only on its own step 7 setup, both apps still minimized; fixed for dk-5.)
- **Red, on the first pull request's first version (eab4d41):** the pair saved on the laptop was
  never pinned (ap-r2); with two screens Dolphin and KWrite stayed on the second screen, untiled
  (aps-r1).
- **ap-1** (an earlier version) found two faults, both fixed before ap-2 and ap-3:
  - the pinned apps model gives a favourite's storage id without "applications:", so a pair showed
    as a plain tile named after its entry;
  - "Save pair" under the card sat on the switcher's Close All, so it moved beside it.

Not verified: Remove Pair, Swap Sides and Keep in Dock from the menu by touch (the test sessions'
menus take no synthetic input; the helper's `swap` and `remove` and the request Keep in Dock writes
are tested); a real middle click, Shift or Meta+Alt+N on a kept pair (they reach the same functions
as the hook's `new` and a tap); a real second
monitor (two virtual outputs are tested); Plasma 6.8 (the dock and the home screen use nothing that
changed; the navigation effect is built per KWin version).