# KWin packages: window switcher, snap layouts, attached dialogs, snap-zone outline

Status: built, checked offline and in private virtual sessions on the ThinkPad (dark and light,
1440x900); reviewed and fixed (see "Review" at the end). KWIN-2 (2026-09-30) changed the switcher's
windows and previews, the flyout's side and layouts, the picker's backdrop, and added the
screen-change and touchpad handling: see "KWIN-2" at the end, which replaces the older text where
they differ. Last edited 2026-09-30.

## What it is

| Id | Type | What |
|---|---|---|
| `org.plasmafusion.switcher` | KWin/WindowSwitcher | Alt+Tab switcher of the AltTab / AltTabLight boards: frosted 1100 px card (radius 26), "This workspace" / "All workspaces" tabs, window count, live previews in a 5-column grid, key-hint bar, dimmed work area behind |
| `plasmafusion-snap` | KWin/Script (declarative) | Meta+Z snap-layouts flyout (QuickSettings board), "Pick a window for this side" after snapping a half (TabsSnap board), 6 px gaps for snapped halves and quarters, pairs that minimise and restore together; "Plasma Fusion: Activate Dock Entry 1..9" (Meta+Alt+1..9 from setup), passed to the dock as its `activateRequest` key, since Plasma 6.8 gives plasmashell's task manager entries to the stock task manager only |
| (in `plasmafusion-snap`) `contents/outline/outline.qml` | KWin outline QML | blue snap-zone preview of the TabsSnap board (drag to an edge, Shift+drag custom zones, Meta+Z zone preview) |
| `plasmafusion-attach` | KWin/Script (JavaScript) | modal dialogs placed centred on their window, just under its title bar, and moving with it (Windows board, "Dialogs · Attached to the parent window") |

No compiled code. Everything uses the KWin 6.7.5 QML/JS script API (verified against the v6.7.5
sources) plus `org.kde.plasma.core` (Dialog), Kirigami (theme colours, icons) and QtQuick.Effects.

## Files

| Path | Purpose |
|---|---|
| `packages/kwin/switcher/org.plasmafusion.switcher/metadata.json` | KPackage metadata (KWin/WindowSwitcher) |
| `.../contents/ui/main.qml` | `KWin.TabBoxSwitcher`: filter state (tabs), selection handling, card window, dim window |
| `.../contents/ui/WindowCard.qml` | one window: preview (cover-fit, rounded), icon, app name, title, ring, close button (hover; in touch mode on the selected card) |
| `.../contents/ui/shaders/thumbnail.frag` (+ compiled `thumbnail.frag.qsb`) | rounds the corners of a preview's layer |
| `.../contents/ui/Hint.qml`, `Kbd.qml` | hint bar items and key caps |
| `.../contents/ui/FusionPalette.qml` | board colours, dark/light |
| `packages/kwin/scripts/plasmafusion-snap/metadata.json` | KPackage metadata (KWin/Script, declarativescript, config KCM) |
| `.../contents/ui/main.qml` | shortcut, quick-tile logic, gaps, picker trigger, pairs |
| `.../contents/ui/SnapFlyout.qml` | Meta+Z flyout |
| `.../contents/ui/DecorationSide.qml` | which side the maximize button is on (reads the decoration settings with `kreadconfig6`) |
| `.../contents/ui/ensureTopBars.js` | generated at build from `packages/look-and-feel/common/contents/layouts/ensure-topbars.js`: the script text the hot-plug handler sends to plasmashell (not in the source tree) |
| `.../contents/ui/FillPicker.qml`, `PickerCard.qml` | "Pick a window for this side" |
| `.../contents/ui/FusionPalette.qml` | colours (created inside each popup, where Kirigami's theme is reliable) |
| `.../contents/config/main.xml`, `contents/ui/config.ui` | settings shown in System Settings > Window Management > KWin Scripts |
| `.../contents/outline/outline.qml` | snap-zone outline |
| `packages/kwin/scripts/plasmafusion-attach/metadata.json` | KPackage metadata (KWin/Script, javascript, config KCM) |
| `.../contents/code/main.js`, `contents/config/main.xml`, `contents/ui/config.ui` | script and settings |
| `tools/build.d/80-kwin.sh` | checks metadata ids/structures and XML, copies the three packages into the stage, generates `ensureTopBars.js`, compiles the preview shader with `qsb` when it is installed (else the committed `.qsb` file is used) |
| `packages/kwin/tests/` | test tooling only, not installed (see Verification) |

## Build and install

```
tools/build.sh kwin     # -> $STAGE/.local/share/kwin/tabbox/org.plasmafusion.switcher
                        #    $STAGE/.local/share/kwin/scripts/plasmafusion-snap   (incl. contents/outline/outline.qml)
                        #    $STAGE/.local/share/kwin/scripts/plasmafusion-attach
```

Per user, from a checkout (equivalent to copying the stage folders into `~/.local/share/kwin/`):

```
kpackagetool6 -t KWin/WindowSwitcher -i packages/kwin/switcher/org.plasmafusion.switcher   # -u to upgrade
kpackagetool6 -t KWin/Script -i packages/kwin/scripts/plasmafusion-snap
kpackagetool6 -t KWin/Script -i packages/kwin/scripts/plasmafusion-attach
```

## Apply (config keys)

All in `~/.config/kwinrc`, then `qdbus6 org.kde.KWin /KWin reconfigure` (or `busctl --user call
org.kde.KWin /KWin org.kde.KWin reconfigure`). Everything else below is optional.

```
[TabBox]
LayoutName=org.plasmafusion.switcher
DesktopMode=0              # every workspace in the list: both tabs work (see "Workspace tabs")
HighlightWindows=false     # the board dims the work area instead of highlighting one window

[TabBoxAlternative]        # Meta+Tab, if it stays bound
LayoutName=org.plasmafusion.switcher
DesktopMode=0
HighlightWindows=false

[Plugins]
plasmafusion-snapEnabled=true
plasmafusion-attachEnabled=true
sheetEnabled=true          # stock "sheet" effect: modal dialogs unfold from the parent's top edge
                           # (dialogparent, on by default, dims the parent: keep it)

[Outline]
QmlPath=kwin/scripts/plasmafusion-snap/contents/outline/outline.qml
```

The Global Themes already carry `[kwinrc][WindowSwitcher] LayoutName=org.plasmafusion.switcher`
(libklookandfeel writes it to `[TabBox] LayoutName` through `~/.config/kdedefaults/kwinrc`). The
other keys cannot come from a Global Theme and belong in `tools/device/fusion-config.sh`.
To undo: delete the keys (or set `plasmafusion-*Enabled=false`, `sheetEnabled=false`, remove
`[Outline] QmlPath`) and reconfigure. Loaded scripts can be stopped at once with
`qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript plasmafusion-snap` (same for
`plasmafusion-attach`); `isScriptLoaded <id>` checks them.

The Meta+Z shortcut is registered by the script under the KWin component with the action name
`Plasma Fusion: Snap Layouts` (visible text the same). It can be invoked from anywhere, e.g. a
decoration's maximize button: `qdbus6 org.kde.kglobalaccel /component/kwin
org.kde.kglobalaccel.Component.invokeShortcut "Plasma Fusion: Snap Layouts"`.

Script settings (System Settings > KWin Scripts > configure, or kwinrc):

| Group / key | Default | Meaning |
|---|---|---|
| `[Script-plasmafusion-snap] Gap` | 6 | px between snapped windows and at the work-area edges (0-48) |
| `[Script-plasmafusion-snap] QuickTileGaps` | true | apply the gap to KWin's quick tiles (edge snapping, Meta+arrow, Meta+Z halves/quarters) |
| `[Script-plasmafusion-snap] FillOtherHalf` | true | offer the other windows after a window is snapped to a half |
| `[Script-plasmafusion-snap] PairWindows` | true | windows placed side by side through the picker minimise/restore/raise together |
| `[Script-plasmafusion-attach] FollowParent` | true | dialogs move with their window |
| `[Script-plasmafusion-attach] DetachOnMove` | true | dragging a dialog yourself detaches it (false: it snaps back) |
| `[Script-plasmafusion-attach] TitleBarGap` | 0 | px between the parent's title bar and the dialog |
| `[Script-plasmafusion-attach] HideDialogTitleBar` | false | board "sheet" look without a dialog title bar (also drops its shadow, see deviations) |

## Behaviour

### Window switcher

- Card: `PlasmaCore.Dialog` (so KWin blurs behind it) whose frame is switched to the Plasma
  style's `launcher` prefix: radius 26, fill rgba(22,27,46,.86) / white .86, 1 px edge .12, exactly
  the board card. With another Plasma style the regular dialog frame is used. Content is laid out
  against the window edges with the board's padding (23/28/21 including the 1 px edge), so it does not depend
  on the frame margins.
- Size and place: 196 px cells, 16 px gaps, up to 5 columns (fewer on narrow screens); the card
  shrinks to the needed columns but never below the hint bar's width; centred horizontally, 24 px
  above the vertical centre (the board's 268 px on a 900 px screen). More windows than fit in
  86 % of the screen height: the grid scrolls and keeps the selected row in view.
- Dim: a separate input-transparent window over the work area (below the top bar, as on the board)
  in rgba(6,8,18,.55) / rgba(221,230,244,.5). The window is transparent and a Rectangle carries the
  tint (KWin composites internal windows as premultiplied; a translucent window clear colour is
  not premultiplied and turned the light tint into opaque white). The card window is created after
  the dim window has drawn a frame, so it is always above it; KWin sends keys to the card (first
  window it finds). Clicking outside the card closes the switcher (KWin's own behaviour).
- Card contents: live `KWin.WindowThumbnail` filling the 118 px box like CSS "cover" (top aligned,
  clipped to radius 10), app icon 24, app name 13/800, window title 11.5 muted. The app name is the
  caption suffix when it matches the window's app ids ("Wallpapers — Dolphin" -> Dolphin /
  Wallpapers), else the desktop-file name. Selected: accent fill .16 + 2 px ring (#5b9dff; derived
  from the accent colour when it is not the Fusion accent). Hover: .05 tint and a close button.
- Keys: Tab / Shift+Tab (KWin), ` for the same app (KWin's mode switch), Q closes the selected
  window, Left/Right/Up/Down move in the grid, Home/End, Enter switches, **A toggles
  This workspace / All workspaces**, Esc cancels (KWin). Mouse: click a card to switch, click a tab,
  middle-click closes, wheel moves the selection (KWin).
- Workspace tabs: KWin has no API to change the list's desktop filter while it is open, so the
  switcher filters itself. With `[TabBox] DesktopMode=0` KWin lists all workspaces; the switcher
  opens on "This workspace" (the board), skips hidden rows while KWin walks the list, and "All
  workspaces" shows everything, with the workspace name added to the title of windows elsewhere.
  If the current workspace has no windows it opens on "All workspaces". With `DesktopMode=1` the
  list only has this workspace and the "All workspaces" tab is shown disabled (45 % opacity).
- Header count: "N windows · <workspace name>" (current workspace of the switcher's screen) or
  "· All workspaces". Zero windows: "No open windows" (KWin's own translated string) or "No windows
  on this workspace".

### Snap layouts (Meta+Z)

- Flyout: `PlasmaCore.Dialog`, 280 px, the Plasma style's `notification` frame (radius 18, fill
  .90, edge .12); a `snaplayouts` prefix is used automatically if the style ever adds one with the
  board's radius 16. Board layout: "Snap layouts" 12/800 + "Meta+Z", 2x2 cards 58 px (radius 9,
  padding 5, fill .06), zones radius 4 / fill .20 / 4 px gaps, the active zone #5b9dff, footer.
- Placement: centred on the maximize button (the decoration's button slot 58 px from the right
  edge), top edge on the title bar's bottom (from the window's client geometry), clamped to the
  work area; for windows without a KWin title bar it hangs 8 px below the top.
- Zones: halves 50/50, 2:1 (2/3 + 1/3), quarters, thirds. Halves, 2:1 and quarters use KWin's quick
  tiles (the 2:1 split is the quick-tile split, so the partner half resizes with it; KWin resets it
  to 50 % when both halves are empty); thirds are plain geometry with 6 px gaps.
- Keys: the first zone is highlighted when it opens (board); arrows/Tab move, 1-4 pick a layout,
  Enter/Space places, Esc closes. Moving with keys or hovering shows the target in the snap-zone
  outline. It is a Qt popup: a click anywhere else or any focus change closes it (KWin's popup
  handling), and it closes itself after 30 s. Meta+Z again closes it.

### Fill the other half

- After a window is snapped to the left or right half (edge drag, Meta+Left/Right, Meta+Z) and the
  other half is empty, a picker covers the other half (220 ms later, when KWin has settled):
  the blurred wallpaper (`KWin.DesktopBackground` + MultiEffect blur) under the board tint
  rgba(8,11,24,.55) (light: rgba(250,251,255,.62)), "Pick a window for this side", and the other
  windows of the workspace (most recent first) as cards: radius 12, padding 8, live preview, icon
  + name + title, selected = accent .22 + 2 px ring. 2 columns up to 4 windows, else 3 if they fit.
- Pick with a click or Enter (arrows/Tab move, hover selects; with more windows than fit, the list
  scrolls to the selection). The window goes into the other quick tile (so both share the split)
  and becomes active. Esc, a click on the tint or anywhere else, any focus change, the snapped
  window changing its tile (leaving its half, or Meta+Left/Right to the other half: the picker then
  comes back for the new empty half) or closing, a workspace switch, or 60 s without input closes
  it. Nothing appears when there are no other windows. Choosing a half in the Meta+Z flyout for a
  window that already sits in that quick tile (e.g. 2:1 then halves) also offers the picker.
- Pairs (windows placed through the picker): minimising one minimises the other, restoring one
  restores the other, activating one raises the other. A pair ends when either leaves its half.
- Gaps: the script sets the quick-tile root's padding to the gap (6 px): 6 px between halves and
  quarters and 6 px from the work-area edges, the same look as the Meta+T custom zones.

### Snap-zone outline

`outline.qml` replaces KWin's outline: rounded rectangle radius 14, fill rgba(91,157,255,.28) with a
2 px #5b9dff edge (light scheme: rgba(47,111,223,.20) / #2f6fdf; other accents follow the accent).
It fades in after 150 ms (TabsSnap "after the pointer rests at the edge for 150 ms") and glides
from the window to the zone. Zones that touch the work-area edge are drawn 6 px inset.

### Attached dialogs

A modal dialog whose parent has a KWin title bar is placed horizontally centred on the parent
and with its top on the parent's title-bar bottom (clamped to the work area). It is re-placed when
the parent moves or resizes and when the dialog changes its own size. Dragging the dialog detaches
it. Client-side-decorated parents (GTK/libadwaita) keep KWin's placement. With `sheetEnabled` the
stock sheet effect animates the dialog out of the parent's top edge and the stock dialogparent
effect dims the parent (Windows board's dimmed parent).

## Verification

Offline (laptop):
- `qmllint` on every QML file (only the expected "org.kde.kwin not found" import notes: KWin
  registers that module at runtime); `node --check` on main.js; XML parse of main.xml/config.ui;
  the build script checks ids and structures. Build is deterministic (plain copies).
- Offscreen renders with a stand-in `org.kde.kwin` module (`packages/kwin/tests/offscreen/`,
  PySide6 + private Xvfb display, private HOME): `run.sh STAGE_HOME switcher-harness.qml OUT.png
  [dark=false count=N otherDesktop=N current=N]`, `snap-harness.qml mode=flyout|picker`. Measured
  against the board render: card 170,268 1100x316 (board 170,268 1100x316), tabs, rows, key caps
  within 1-2 px (`tests/compare.py` for side-by-sides). Edge cases rendered: 30 windows (scrolls to
  the selection), 0 windows, 2 windows, all windows on another workspace.

Virtual sessions on the ThinkPad (`tools/vsession/remote.sh kw-N SCENARIO SEED`, private HOME and
bus, 1440x900). Seeds: `packages/kwin/tests/vsession/make-seed.sh STAGE_HOME SEED dark|light`
(Fusion data from the stage plus the kwinrc keys above and a desktop file that lets
`tests/vsession/fakeinput.py` drive KWin's fake-input protocol, i.e. real Alt+Tab, Meta+Z, keys
and pointer drags inside the private session only).
- `scenario-switcher.sh`: Alt+Tab (4 windows), a window moved to workspace 2, Alt+Tab then A
  (All workspaces, title "Welcome · Design"), Tab Tab Shift+Tab, Q closes the selected window.
- `scenario-snap.sh`: Meta+Z, Right (outline preview of the right half), Enter (window tiled right),
  picker on the left, Right + Enter (filled pair with 6 px gaps), Meta+Z + Esc, a pointer drag of a
  third window to the left edge (outline), a modal Open dialog of KWrite attached under the title
  bar and following its window when it moves.
- `scenario-evidence.sh`: the same on the Plasma Fusion desktop (Global Theme layout script and
  wallpaper), 5 windows, dark and light, plus pair minimise/restore.
- Journal (`journalctl --user`, the private sessions log there): no messages from these packages.
  Libplasma prints "Member visible of the object PlasmaQuick::Dialog overrides a member of the
  base object" once per process that uses PlasmaCore.Dialog (plasmashell, the stock thumbnail_grid
  switcher, and these packages); it is not caused by the QML here.
- Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/kwin/`: `screenshots/dark`,
  `screenshots/light` (evidence runs), `screenshots/switcher-keys/{dark,light}`,
  `screenshots/snap-sequence-dark`, `side-by-side/` (board vs build: switcher full frame and card
  crop, flyout crop, dark and light), `offscreen/` (harness renders incl. edge cases), `logs/`.

Re-run: `STAGE=$S tools/build.sh && packages/kwin/tests/vsession/make-seed.sh $S/home $SEED dark &&
tools/vsession/remote.sh kw-3 packages/kwin/tests/vsession/scenario-evidence.sh $SEED 1440x900 240`.

## Known deviations from the boards

- Card shadow: the Plasma style's dialog shadow (0 18 44 .45), not the board's 0 40 110 .55
  (KWin draws one shadow set for all Plasma dialogs).
- Flyout radius 18 (the style's `notification` frame), board 16; edge .12 instead of .14. A
  `snaplayouts` prefix in the Plasma style would make it exact (requested below).
- Switcher tabs need `DesktopMode=0`; with the current `fusion-config.sh` default (`DesktopMode=1`
  for Alt+Tab, Meta+Tab = all workspaces) Alt+Tab shows "All workspaces" disabled and Meta+Tab opens
  on "This workspace" (the switcher cannot tell which shortcut opened it). Recommended: DesktopMode=0
  for both, or drop the Meta+Tab alternative.
- A key for the tabs is not on the board; A toggles them (the board's hint bar is kept unchanged).
- Close button on hover and middle-click close are additions (not on the static board).
- The blur behind the switcher card is KWin's; behind the picker it is the wallpaper only (the
  picker is a plain window: libplasma's blurred windows either print "This plugin does not support
  setting window masks" on every resize or add a shadow). Windows under the empty half are hidden
  behind the frosted wallpaper, which suits "the empty half".
- Dim layer with `HighlightWindows=true` (KWin default): KWin fades every other window, including
  the dim layer, so the board's even dim needs `HighlightWindows=false`.
- Snapped halves: 6 px gap, but corners stay as the decoration draws them (Aurorae: square client
  corners); the board's "square inner, rounded outer" corners need the compiled decoration.
- The first snap on each workspace/screen shows the gap one step late (the script can only reach
  KWin's quick-tile root through a tiled window, so it sets the padding right after the first snap).
  The padding stays until KWin restarts if the script is disabled.
- 2:1 and quarters are real quick tiles; thirds are plain geometry (KWin's quick tiles have only two
  columns), so thirds do not resize together and do not restore on drag.
- 150 ms zone delay is visual: KWin still snaps a window dropped before the zone has appeared.
- Attached dialogs keep their own title bar and shadow (board: no title bar, radius 0 0 16 16).
  `HideDialogTitleBar` removes it but also the shadow; the board look needs a decoration variant
  for modal windows. Client-side-decorated parents keep KWin's placement.
- Fonts: Manrope is requested by name; without it installed Qt falls back to the default sans.

## Needed from other parts

- `tools/device/fusion-config.sh` (lead): set `[TabBox] DesktopMode=0` (and `[TabBoxAlternative]`
  the same, or unbind Meta+Tab), `HighlightWindows=false` in both groups, `[Outline] QmlPath=
  kwin/scripts/plasmafusion-snap/contents/outline/outline.qml`, `[Plugins] sheetEnabled=true`
  (dialogparent stays on), keep `plasmafusion-snapEnabled` / `plasmafusion-attachEnabled`; the
  restore script should also delete `[Outline] QmlPath` and `sheetEnabled`. (Review: the current
  `fusion-config.sh` sets all of these, DesktopMode 0 for both groups; `fusion-restore.sh` puts
  the backed-up kwinrc back as a whole, which covers the two keys.)
- Plasma style: an optional `snaplayouts` prefix in `dialogs/background` (radius 16, fill .90, edge
  .14, margins 12, with `mask-snaplayouts-*`) for the exact flyout; the `launcher` prefix already
  matches the switcher card exactly, keep it.
- Window decoration (phase 3, compiled): hold-on-maximize calls the shortcut above; a modal-window
  variant without title bar (board sheet) and rounded outer / square inner corners for tiled windows.
- Fonts part: Manrope installed per user (the packages ask for the family by name).

## Test tooling (not installed)

| Path | Use |
|---|---|
| `packages/kwin/tests/offscreen/run.sh`, `render.py`, `switcher-harness.qml`, `snap-harness.qml`, `stubs/org/kde/kwin/`, `session-bus.conf` | offscreen renders with a stand-in KWin module, on a private session bus that activates nothing; `PFK_PACKAGES=DIR` renders the built packages (`DIR/switcher/<id>`, `DIR/scripts/<id>`) |
| `packages/kwin/tests/vsession/scenario-kwin2-a.sh`, `-b.sh`, `-c.sh` | KWIN-2 sessions for `tools/vsession/remote.sh` with a `fusion-config.sh` seed: flyout side, switcher, snap and picker, portrait, tablet (a); hot-plug top bar with two outputs (b); Light (c) |
| `packages/kwin/tests/compare.py` | board-vs-build side-by-sides and crops |
| `packages/kwin/tests/vsession/make-seed.sh`, `fakeinput.py`, `scenario-*.sh` | ThinkPad virtual-session tests |
| `packages/kwin/tests/vsession/manywindows.py` | one PySide6 process with N plain windows (switcher and picker with many windows, long titles) |
| `packages/kwin/tests/vsession/scenario-review.sh` | edge cases: no windows, 16 windows + long workspace name, picker scrolling, 2:1 / quarters / thirds, Meta+Right with the picker open, click outside the flyout; writes KWin's PID to `$OUT/kwin.pid` and geometry lines (`PFKGEOM`) to the journal |

Notes for later test runs: a vsession does not read `~/.config/kdedefaults`, so
`plasma-apply-lookandfeel` inside one appears to reset KWin settings (the evidence scenario runs
only the Global Theme's layout script and sets the wallpaper instead). The laptop's `/tmp` quota
was repeatedly full during this work; test output lived in the git-ignored `build/kw/`.

## Review

Second pass over the part, 2026-09-29: board values re-read (AltTab/AltTabLight,
QuickSettings/QuickSettingsLight, TabsSnap, Windows), the 6.7.5 sources re-checked for every API
the packages use, and every part built together (`STAGE=build/rkw/home tools/build.sh`, all parts
of the tree at that time) and run in private sessions `rkw-1`..`rkw-6` (dark and light).

What was checked:
- Contracts: `TabBoxSwitcher` (model roles, `close`/`activate`, key forwarding: KWin sends keys
  without modifiers to the first `QQuickWindow` under the switcher), KWin's lookup of
  `kwin/tabbox/<id>` after `kwin-wayland/tabbox/`, `ShortcutHandler`, `Tile` (`manage`, `padding`,
  writable `relativeGeometry`), `QuickRootTile` (8 children; its padding is not saved to kwinrc),
  `Workspace` slots (`showOutline`, `slotWindowQuickTile*`, `clientArea`), `WindowThumbnail.client`,
  `DesktopBackground`, the outline loader (`[Outline] QmlPath` resolved in the data dirs, context
  property `outline`, outline windows stacked in the normal layer). Input filter order: global
  shortcuts run before internal windows, so the flyout and picker cannot swallow Alt+Tab, Meta+...
- Metadata ids and structures, `kcm_kwin4_genericscripted` present, `kcfg_` widget names match
  the kcfg entries, `qmllint -I packages/kwin/tests/offscreen/stubs` (no warnings besides
  `WindowModel` missing from the stub and `Dialog.margins` typed as QObject), `node --check`,
  no attribution text.
- Measured against the renders: switcher card 268..583 in both (board 268..584), tab pill rows
  294..319 in both, key caps 541..562 (board 542..563), flyout 769,110 280 wide (board 769,112;
  the 2 px come from the Aurorae title bar height). Snapped geometry from the private KWin:
  2:1 left 6,40 951x854 (split at 960), halves 723,40 711x854, top-right quarter 723,40 711x424,
  right third 962,40 472x854 (6 px gaps).
- Edge cases in `scenario-review.sh`: Alt+Tab with no windows ("No open windows"), 16 windows (the
  grid scrolls, the selection stays in view), a long workspace name, 15 picker candidates with
  keyboard navigation, 2:1 then halves, Meta+Right while the picker is open, quarters and thirds,
  a click outside the flyout (closes it, the click is not passed on).
- Logs: the private KWin's journal lines (`journalctl --user _PID=<kwin pid>`) hold nothing from
  these packages; the only QML line is libplasma's "Member visible of the object
  PlasmaQuick::Dialog overrides..." (printed once by any process that loads PlasmaCore.Dialog).

Fixed:
- **Light switcher washed the screen out to white.** The dim window used a translucent window
  colour; QtQuick clears with it unpremultiplied while KWin composites internal windows as
  premultiplied, so rgba(221,230,244,.5) came out opaque white (the builder's light evidence
  shows it) and the dark dim came out a little too light. The window is now transparent and a
  Rectangle draws the tint: light (100,850) is 156,178,229 (board 155,177,227), dark 44,61,107
  (expected 43,61,105).
- **Picker missing after 2:1 -> halves.** Choosing a half in the Meta+Z flyout for a window that
  was already in that quick tile only moved the split (no `tileChanged`), so the freed side was
  not offered. `placeInZone` now asks for the picker itself.
- **Picker stuck over the window after Meta+Left/Right.** With the picker open, moving the snapped
  window to the other half kept the picker where it was (now on top of the window) and blocked a
  new one. Any tile change of the snapped window closes it; the picker then comes back for the new
  empty half.
- Picker with more windows than fit: keyboard selection now scrolls the list.
- Switcher header: the "N windows · workspace" text is elided before it reaches the tabs and is
  plain text (workspace names are user input).

Remains (not fixed):
- Keys pressed in the first frame of the switcher, before the card window exists (at most 150 ms),
  go to the dim window and are dropped (KWin handles Tab/Shift+Tab/` itself, so only Q, A, arrows
  and Enter are affected).
- Some text widths differ from the board render by 4-5 % (flyout footer at 11.5 px narrower, the
  switcher's 12.5 px count wider) while others match to the pixel ("Snap layouts" 12 px/800,
  "Meta+Z" 11 px, tab labels). Font engine difference (Qt/FreeType vs the browser render), left as is.
- dialogparent dims the whole parent window, the Windows board dims only below its title bar.
- The deviations listed above stay; not tested at the ThinkPad's 4/3 scale, with several screens,
  with Xwayland dialogs or with touch.

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/kwin/review-*.png`
(dark and light evidence runs after the fixes, the edge cases, board side-by-sides). The builder's
`screenshots/light/10-switcher.png` and `11-switcher-all-workspaces.png` show the white-out that
is fixed now.

Re-run: `STAGE=$PWD/build/rkw/home tools/build.sh && packages/kwin/tests/vsession/make-seed.sh
build/rkw/home build/rkw/seed-dark dark && tools/vsession/remote.sh rkw-3
packages/kwin/tests/vsession/scenario-review.sh build/rkw/seed-dark 1440x900 230`, then
`ssh thinkpad-fedora journalctl --user _PID=$(cat vsession-out/rkw-3/kwin.pid) -o cat`.

## Polish (2026-09-29)

See `docs/parts/polish.md`.

- Switcher: keys typed before the card's first frame are no longer lost. KWin sends them to the
  dim layer then; its focus item now takes active focus itself and calls the same `handleKey()` as
  the card. Test: `QT_QPA_PLATFORM=offscreen python3 tests/offscreen/keytest.py` (commit 0918220
  loses the key, this revision handles it). Keys in KWin's own 90 ms show delay still go nowhere.
- Snap flyout: the Plasma style now has the `snaplayouts` prefix, so the flyout is the board's
  (radius 16, edge .14); the deviation "Flyout radius 18" no longer applies.
- Font weights (Font.Bold / Font.ExtraBold) resolve to the static font files; no synthetic bold.

## KWIN-2 (2026-09-30)

PLAN.md "KWIN-2"; BACKLOG S3, S15, E14; ADAPTIVE 5.7, 5.8, fix 24, M09/M13/M14/M23; TABLET 4.10;
owner decisions 4 (snap layouts on hold: no hover flyout, so no spike) and 8 (a top bar on every
screen).

### Window switcher

- Two windows, made once. The dim layer and the card are created the first time the switcher
  opens and then only shown and hidden; the dim is shown first and the card right after it in the
  same turn, so the card is above it and both appear in the same frame. The old gate (card after
  the dim's first frame) and its timer are gone. Keys typed before the card's first frame reach
  it: its focus scope takes active focus when the window is created and each time it is shown
  (`tests/offscreen/keytest.py`: both cases "handled").
- The dim layer is a tooltip-type window. As a normal window it got KWin's scale animation
  (200 ms, full screen), which ended after the card's fade and set the time to a settled
  picture; as a tooltip type KWin fades it like the card.
- Previews: KWin paints the thumbnail (cover size, top aligned) into one layer per card, and one
  small shader (`shaders/thumbnail.frag`) rounds the layer's corners. This replaces the layer +
  MultiEffect + mask layer of before. The plan's single pass (the thumbnail's texture fed
  straight to a shader, no layer) was built and measured and then dropped:
  - KWin's texture holds everything the window draws, the shadow around the frame included, and
    the script API does not tell where the frame is in it (`Window::visibleGeometry` is no
    property). The single pass had to search the texture for the frame's opaque edge; that
    works for the Fusion and Aurorae title bars but not for a translucent window.
  - It was not faster: Alt+Tab settled 408 ms (400..458, 3 runs) against 404 ms (402..405,
    2 runs) with the layer; KWin's render time per frame is the same (about 6 ms) in both.
  The previews stay live (the terminal's clock changes between two screenshots 0.8 s apart).
- Cells `clamp(round(W / 7.35), 160, 260)` wide (196 at 1440), previews 0.6 x the cell, up to 5
  columns (6 on a wide screen); the hint row is a `Flow` that wraps when the card is narrower
  than the hints.
- Pointer: moving it over a card selects that card (a pointer that only rests where a card
  appears does not); a click switches to it. KWin keeps the list's order while the switcher is
  open.
- Touch (tablet posture or a touch-sized screen): the selected card carries the close button
  (28 px, 44 px target).
- Light: the dim is a neutral dark rgba(20,24,39,.22) instead of a light wash.
- Motion tokens for the grid's scroll; `[TabBox] DelayTime` is 120 ms (`fusion-config.sh`).

### Snap layouts

- The flyout hangs under the real maximize button: 59 px from the window's right edge, or 58.5 px
  from the left when the buttons are on the left; a right-to-left layout mirrors the side. The
  side comes from `DecorationSide.qml`, which reads with `kreadconfig6` (through Plasma's
  `executable` data source, so the values are the ones on disk with KDE's defaults):
  `plasmafusionrc [Decoration] ButtonStyle` (LeftCircles) when `kwinrc [org.kde.kdecoration2]
  library` is the Fusion decoration, else a theme name ending in `-Left`, else an "A" in
  `ButtonsOnLeft`. Read when the script starts and at every Meta+Z. The file is loaded on its
  own: without `org.kde.plasma.plasma5support` the script still works, with the flyout on the
  right. (Asking plasmashell for the values did not work: its view of kwinrc is not read again
  after the decoration changes.)
- A work area taller than it is wide gets row layouts: top/bottom halves, 2/3 over 1/3,
  quarters, three rows; the layout cards are 104 px tall and drawn in the area's aspect ratio.
  Top and bottom halves are KWin's quick tiles, so the other half is offered for them too.
- "Pick a window for this side": the backdrop is `FusionBackdrop` (one blurred capture of the
  wallpaper, taken again after the second frame) instead of a live blur. In tablet posture the
  cards are `clamp(W / 5, 220, 300)` wide with 0.6 x previews and 14 px titles.
- After a screen or geometry change (800 ms later) every normal window that is not tiled,
  maximized, full screen or minimized is moved, and if needed shrunk, into its screen's maximize
  area. KWin 6.7.5 already does this for a rotation in both directions (the log line says
  "0 window(s) moved"); the script is the net for what KWin leaves outside.
- Hot-plug: the same handler sends the Global Theme's `ensure-topbars.js` to plasmashell
  (`evaluateScript`), so a screen that appears after login gets its top bar. The text comes from
  `ensureTopBars.js`, which the build generates from the Global Theme's file. (A layout template
  with `loadTemplate()` did not work: plasmashell loads only templates of the panel category,
  which would also put it into "Add Panel".)
- Touchpad, three fingers: up opens Overview, down closes it or shows the desktop
  (`SwipeGestureHandler`, device type touchpad). KWin's own three-finger vertical swipe switches
  between rows of virtual desktops; the Fusion layout has one row. Hand check on the device.
- The outline's durations follow Plasma's animation speed.

### Verification

Offline (laptop), against the built packages (the source tree lacks the shared QML blocks and
`ensureTopBars.js`):

```
S=build/k2/stage; P=build/k2/pkgroot
ROOT=$PWD STAGE=$PWD/$S bash tools/build.d/80-kwin.sh
mkdir -p $P/switcher $P/scripts
ln -sfn $PWD/$S/.local/share/kwin/tabbox/org.plasmafusion.switcher $P/switcher/
ln -sfn $PWD/$S/.local/share/kwin/scripts/plasmafusion-snap $P/scripts/
env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY QT_QPA_PLATFORM=offscreen \
  dbus-run-session --config-file=packages/kwin/tests/offscreen/session-bus.conf -- \
  python3 packages/kwin/tests/offscreen/keytest.py $PWD/$P        # both lines: "handled"
PFK_PACKAGES=$PWD/$P PFK_TMP=$PWD/build/k2 packages/kwin/tests/offscreen/run.sh \
  STAGE_HOME packages/kwin/tests/offscreen/switcher-harness.qml out.png [dark=false]
```

Private sessions on the ThinkPad (seed from `fusion-config.sh --install`):

- `scenario-kwin2-a.sh` (1920x1200 at 4/3), 19 checks PASS:
  - flyout centre against the maximize button: compiled decoration right 1061.5 / 1061.25 and
    left 378.5 / 378.5, Aurorae `-Left` 378.5 / 378.5, Aurorae right 1061.5 / 1061.25;
  - switcher: hover selects, a resting pointer does not, click activates;
  - halves with the 6 px gap and the picker; M09 rows (top half, bottom half offered, bottom
    third 461 px of a 1406 px area); M14 every window inside the work area after rotating and
    back; T18 split in tablet posture (picker, two tiles without title bars, title bars back
    after leaving);
  - no QML warnings from the scripts, no KWin or plasmashell crash.
- `scenario-kwin2-b.sh` (two outputs, the second disabled before the install and enabled after):
  M23 PASS: "top bars: screens 2, added 1", one top bar per screen, none added on a second
  hot-plug.
- `scenario-kwin2-c.sh` (1920x1080 at 1, Light): M13: white under the dim is (203,204,208), the
  top bar is not dimmed; previews, flyout and picker in Light.
- Perf gate (`tools/tests/perf/run.sh`, 1920x1200 at 4/3, 2 quiet runs of this code): Alt+Tab
  Alt to first frame 221 ms (219..222; budget 233, baseline 255), Alt to a settled picture
  404 ms (402..405; budget 420, baseline 489). The first Alt+Tab of a session, which creates
  the two windows, settles at 533-641 ms. No regression against the baseline, no core dumps.
- NOT met: KWin render p95 of 3.5 ms. The 73 frames of six openings take 6.0 ms in the median
  (p95 7.5, at most 9.2) against about 3 ms just before Alt. The full-screen dim layer is most
  of the difference: the same build without it (2 runs, a comparison only) gives 3.7 ms in the
  median (p95 6.0, at most 7.2) and settles as fast. The previews are not the cost (see above).
  Keeping the board's dim or dropping it is the owner's choice.
- Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build2/KWIN-2/`.

### Not done

- The split divider handle (TABLET 4.10, P2): T18's "drag the divider" step has no handle; the
  two tiles still share their edge when one is resized by its border.
- Touchpad swipes cannot be produced in a private session: hand check at DEPLOY-1 (also that
  KWin's own three-finger vertical gesture does nothing visible with one desktop row).
- The 6 px strip between a snapped half and the picker shows the windows under it (as before).

