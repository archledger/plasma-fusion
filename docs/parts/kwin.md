# KWin packages: window switcher, snap layouts, attached dialogs, window placement memory, dynamic workspaces, snap-zone outline

Status: built, checked offline and in private virtual sessions on the ThinkPad (dark and light,
1440x900); reviewed and fixed (see "Review" at the end). KWIN-2 (2026-09-30) changed the switcher's
windows and previews, the flyout's side and layouts, the picker's backdrop, and added the
screen-change and touchpad handling: see "KWIN-2" at the end, which replaces the older text where
they differ. Last edited 2026-09-30.

## What it is

| Id | Type | What |
|---|---|---|
| `org.plasmafusion.switcher` | KWin/WindowSwitcher | Alt+Tab switcher of the AltTab / AltTabLight boards: frosted 1100 px card (radius 26), "This workspace" / "All workspaces" tabs, window count, live previews in a 5-column grid, key-hint bar, dimmed work area behind |
| `plasmafusion-snap` | KWin/Script (declarative) | Meta+Z snap-layouts flyout (QuickSettings board), "Pick a window for this side" after snapping a half (TabsSnap board), snapped halves and quarters that meet with no gap (a gap can be set), pairs that minimise and restore together; "Plasma Fusion: Activate Dock Entry 1..9" (Meta+Alt+1..9 from setup), passed to the dock as its `activateRequest` key, since Plasma 6.8 gives plasmashell's task manager entries to the stock task manager only |
| (in `plasmafusion-snap`) `contents/outline/outline.qml` | KWin outline QML | blue snap-zone preview of the TabsSnap board (drag to an edge, Shift+drag custom zones, Meta+Z zone preview) |
| `plasmafusion-attach` | KWin/Script (JavaScript) | modal dialogs placed centred on their window, just under its title bar, and moving with it (Windows board, "Dialogs · Attached to the parent window") |
| `plasmafusion-placement` | KWin/Script (declarative) | window placement memory: each app's window is remembered where and as big as it was left and given back on the next open (bug 15329, the most-duplicated open Plasma wish); a spot on a screen that is gone is left to KWin's placement |
| `plasmafusion-workspaces` | KWin/Script (declarative) | dynamic workspaces, **off until the user turns them on** (System Settings > Window Management > KWin Scripts): workspaces come and go as windows need them, as in GNOME - always one empty workspace at the end, an empty one removed once nothing shows it (bug 446448) |

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
| `.../contents/ui/main.qml` | shortcut, quick-tile logic, gaps, picker trigger, filling a layout's zones, snap groups |
| `.../contents/ui/Groups.js` | snap groups' pure rules (join, leave, partners, the zones' fill order, the thirds' zone test); node-tested |
| `.../contents/ui/Gestures.js` | the touchpad gestures you can set: their kwinrc keys and defaults, the actions and how each is run ("Touchpad gestures" below); node-tested |
| `.../contents/ui/SnapFlyout.qml` | Meta+Z flyout |
| `.../contents/ui/DecorationSide.qml` | which side the maximize button is on (reads the decoration settings with `kreadconfig6`) |
| `.../contents/ui/ensureTopBars.js` | generated at build from `packages/look-and-feel/common/contents/layouts/ensure-topbars.js`: the script text the hot-plug handler sends to plasmashell (not in the source tree) |
| `.../contents/ui/FillPicker.qml`, `PickerCard.qml` | "Pick a window for this side" |
| `.../contents/ui/FusionPalette.qml` | colours (created inside each popup, where Kirigami's theme is reliable) |
| `.../contents/config/main.xml`, `contents/ui/config.ui` | settings shown in System Settings > Window Management > KWin Scripts |
| `.../contents/outline/outline.qml` | snap-zone outline |
| `packages/kwin/scripts/plasmafusion-attach/metadata.json` | KPackage metadata (KWin/Script, javascript, config KCM) |
| `.../contents/code/main.js`, `contents/config/main.xml`, `contents/ui/config.ui` | script and settings |
| `packages/kwin/scripts/plasmafusion-placement/metadata.json` | KPackage metadata (KWin/Script, declarativescript, config KCM) |
| `.../contents/ui/main.qml` | the script: window watch, restore and record, the memory file through plasmashell or the fork's native writer facade |
| `.../contents/ui/Placement.js` | the pure rules (identity, file format, on-screen and stack guard, record, the native-writer registration/binding/sequence/reconciliation rules); node-tested |
| `.../contents/config/main.xml`, `contents/ui/config.ui` | `RememberSize` and `IgnoreApps` (System Settings > Window Management > KWin Scripts) |
| `packages/kwin/scripts/plasmafusion-workspaces/metadata.json` | KPackage metadata (KWin/Script, declarativescript, config KCM, `EnabledByDefault: false`) |
| `.../contents/ui/main.qml` | the script: reads the desktops and windows, carries out a pass, watches the windows' desktop moves |
| `.../contents/ui/Workspaces.js` | the pure rules (which windows hold a workspace, the plan, the timing, the numbered names); node-tested |
| `.../contents/config/main.xml`, `contents/ui/config.ui` | `KeepFirst` (System Settings > Window Management > KWin Scripts) |
| `tools/build.d/80-kwin.sh` | checks metadata ids/structures and XML, copies the five packages into the stage, runs the placement rules', snap groups', snap cycle's, `Panels.js`'s, touchpad gestures' and dynamic workspaces' node suites when node is installed, generates `ensureTopBars.js`, compiles the preview shader with `qsb` when it is installed (else the committed `.qsb` file is used) |
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
plasmafusion-placementEnabled=true  # window placement memory
plasmafusion-workspacesEnabled=true # dynamic workspaces: off by default, the setup never sets it
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
`plasmafusion-attach`, `plasmafusion-placement` and `plasmafusion-workspaces`); `isScriptLoaded <id>` checks them.

The Meta+Z shortcut is registered by the script under the KWin component with the action name
`Plasma Fusion: Snap Layouts` (visible text the same). It can be invoked from anywhere, e.g. a
decoration's maximize button: `qdbus6 org.kde.kglobalaccel /component/kwin
org.kde.kglobalaccel.Component.invokeShortcut "Plasma Fusion: Snap Layouts"`.

Script settings (System Settings > KWin Scripts > configure, or kwinrc):

| Group / key | Default | Meaning |
|---|---|---|
| `[Script-plasmafusion-snap] Gap` | 0 | logical px between snapped windows (0-48; none by default, Windows board); no gap at work-area edges |
| `[Script-plasmafusion-snap] QuickTileGaps` | true | apply the gap to KWin's quick tiles (edge snapping, Meta+arrow, Meta+Z halves/quarters) |
| `[Script-plasmafusion-snap] FillOtherHalf` | true | offer the other windows after a window is snapped to a half, and for every empty zone of a layout chosen in the flyout |
| `[Script-plasmafusion-snap] PairWindows` | true | snap groups: windows snapped together through the picker minimise/restore/raise together |
| `[Script-plasmafusion-snap] LegacyWidthCycle` | false | opt in to the former Left/Right half, third, two-thirds cycle instead of directional snapping |
| `[Script-plasmafusion-snap] GestureSwipeUp3`, `GestureSwipeDown3`, `GestureSwipeLeft3`, `GestureSwipeRight3`, `GesturePinchIn4`, `GesturePinchOut4` | `overview`, `desktop`, `none`, `none`, `launcher`, `desktop` | what three fingers up, down, left and right and four fingers pinched in and spread out do: `none`, `overview`, `desktop`, `grid`, `windows`, `launcher`, `quicksettings`, `notifications` or `snaplayouts` (an unknown name is the default). Set on the Plasma Fusion settings page, not in the script's own settings; read at the next reconfigure ("Touchpad gestures") |
| `[Script-plasmafusion-attach] FollowParent` | true | dialogs move with their window |
| `[Script-plasmafusion-attach] DetachOnMove` | true | dragging a dialog yourself detaches it (false: it snaps back) |
| `[Script-plasmafusion-attach] TitleBarGap` | 0 | px between the parent's title bar and the dialog |
| `[Script-plasmafusion-attach] HideDialogTitleBar` | false | board "sheet" look without a dialog title bar (also drops its shadow, see deviations) |
| `[Script-plasmafusion-placement] RememberSize` | true | give the remembered size back too (false: only the position, with the size the window opens with) |
| `[Script-plasmafusion-placement] IgnoreApps` | (empty) | app ids or window classes the memory leaves alone (comma-separated; `konsole` matches `org.kde.konsole`; a window matches by its app id or its class) |
| `[Script-plasmafusion-workspaces] KeepFirst` | 0 | the first N workspaces always stay, even when empty (0-24; for example 4 keeps the setup's Work, Design, Media and Chat); applied at the next reconfigure |

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
  to 50 % when both halves are empty); thirds are plain geometry with the same gap.
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
- Every layout (Windows' Snap Assist after a layout choice): a zone chosen in the Meta+Z flyout
  (or the maximize button's hold/hover) starts a sequence - the picker covers each other zone of
  that layout in turn, in zone order after the chosen one and wrapping (`Groups.fillOrder`), with
  the windows not placed yet. A zone already holding a window is skipped: a quick tile with
  windows, or for thirds (plain geometry, not KWin tiles) a zone any window of the desktop already
  sits in - also one the switcher skips, a minimised one, which comes back there, or one in a
  matching custom tile, but not one of another activity (`Groups.zoneOccupied`/`inZone`: top-left
  within 4 px, no larger than the zone and smaller by at most 32 px - a terminal rounds its size to
  whole cells - so a window merely starting at a zone's corner does not fill it). The picker offers
  the windows of this desktop and the current activity, and a zone that filled while it was open
  (an app or a script put a window there) gets no pick placed over it - the next empty zone is
  offered instead. The empty zones are worked out again before
  every offer: a window picked out of another zone of the layout leaves that zone empty, and it is
  offered in its turn (a zone this sequence filled counts as held while the window placed there is
  still in it - not closed, re-tiled, maximized or moved to another desktop - whatever its geometry
  says while it answers its resize - asked again once 1.5 s have passed since that placement; a
  zone it left is offered again). Esc, a click elsewhere, a workspace switch, the first window
  leaving its zone (another tile, out of its rectangle, maximized or full screen, another desktop,
  screen or activity - with a picker open or in the settle before the next one) or closing, the
  current desktop or activity changing, a screen change (a rotation turns columns into rows), or a pick that cannot be placed (the window closed while the
  picker was open, or KWin refused the tile) end the sequence; what was placed stays. Halves from
  an edge drag or Meta+Left/Right keep the single offer above.
- Snap groups (Windows' snap groups; GNOME Tiling Assistant's tile groups raise together too):
  the first window and every window picked for its layout form one group (two for the halves).
  Minimising one minimises the others, restoring one restores the others, activating one raises
  the others under it - so a member chosen from the dock or Alt+Tab brings its whole arrangement
  back. A window is in one group at most; picking it for another arrangement moves it there (it
  leaves its old group before it is restored, so a minimised group is not brought back with it), and a
  zone chosen for it in the flyout is a new arrangement (it leaves its old group first). A
  member leaves when it leaves its zone (a quick-tile member's tile changes; a thirds member is
  no longer in its rectangle - asked when a move ends, and on any other geometry change once 1.5 s
  have passed since its placement, so an app or a script moving it counts too), goes to another
  desktop, screen or activity, is
  maximized or made full screen, or closes; a
  group left with one window ends. `PairWindows=false` forms no groups. A placement KWin refuses
  puts the picked window's old group back as it was.
- Asked at use: handlers end a sequence early and close its picker, but every decision reads the
  windows as they are then - before each offer and each placement the sequence is checked
  (`Groups.fillValid`: the first window holds its zone, same desktop, activity, work area and
  layout family), and before a group minimises, restores or raises, every member is checked
  (`Groups.holds`). So a change no handler sees (an app or a script moving a window within its
  placement's settle, a switch in the 220 ms between two offers) still counts.
- Gaps: none by default: snapped windows meet (Windows board; the owner's decision of 2026-10-16, up
  to 0.5.0 the default was 6 px). A gap set with `Gap` goes between halves and quarters, with the
  outer edges flush to the work area (panels remain reserved). KWin's scalar tile padding also
  insets screen edges, so the script leaves native quick-tile padding at the configured gap and
  fills only each window's outer edges after KWin settles. Native padding keeps the inner gap and
  pointer compensation during split resizing; the outer-edge correction runs during resizing too.
  Work-area endpoints clamp odd trailing tiles that KWin rounds one pixel too wide or tall. Tile
  membership, shared splits and restoration on drag remain native. The picker uses the same
  inner-gap geometry. Meta+T custom zones retain their own padding.
- Quick tiles (0.5.0, survey B12): KWin keeps one quick-tile root per screen and desktop
  (`QuickRootTile`, `src/tiles/quicktile.cpp`, the same in Plasma 6.7 and 6.8) beside the custom
  root that `Workspace.rootTile()` returns. Scripts reach it only as a tiled window's
  `tile.parent`; Plasma 6.8 registers `Tile` and `CustomTile` as QML types but still not
  `QuickRootTile`, and nothing documents its children. The script used to recognise it by
  exactly eight children and address them by their place. `SnapGeometry.js` now recognises it by
  the class name Qt puts in the object's string (`KWin::QuickRootTile(0x…)`, checked in Plasma
  6.7.91; the custom roots read `KWin::RootTile`, their tiles `KWin::CustomTile`), and, should that
  name change, by its shape: the left and right halves at full height, top and bottom at full
  width and the four quarters, which a custom layout cannot have (its tiles never overlap). Each
  quick tile's role (left, right, top, bottom, the quarters) comes from its shape, not its place
  among the children; the outline uses the same test.

### Directional snapping from the keyboard

The four arrows have one spatial meaning (approved 2026-10-22): Meta+Left/Right/Up/Down places
the active window in the corresponding half. A perpendicular direction combines with the current
side into a quarter, in either order: Left then Up and Up then Left both give top-left. An opposite
direction replaces that axis only: top-left then Right gives top-right; then Down gives bottom-right.
Repeating a direction does nothing: no width cycle, restore, minimize, or monitor jump.

`Directional.js` maps the eight quick-tile roles. `main.qml` reads native requested tile membership,
not the last rendered frame, so rapid key sequences do not wait for a Wayland client to draw. A
direction change uses 50/50 splits; a repeat keeps a manually resized split and snap group intact.
Custom tiles and floating thirds start a new half. A tile refused by KWin is not emulated by changing
frame geometry: native tiling keeps window rules and the floating restore rectangle intact.
For the first quick tile from a custom layout, a native corner request discovers the quick-tile
root without combining a direction with KWin's `Custom` flag; the same action then manages the
requested half. The floating restore rectangle stays native throughout.

Meta+Shift+Arrow moves to an adjacent monitor in that direction, never by connector order. An
adjacent output lies wholly on that side and overlaps on the perpendicular axis; the nearest facing
edge wins, then the closest perpendicular center. No neighbor means no change. KWin transfers the
native tile role and restore rectangle, and the script retains resized proportions by adjusting
the destination's shared split (other windows on that split follow it). Floating windows move
normally. The gap correction uses the requested tile's output even before the client commits the
move; clipping to its old output could otherwise send it back. Meta+PageUp maximizes,
Meta+Backspace restores and Meta+Z keeps the advanced layouts.
Moving does not require a resizable window: normal movable fixed-size windows are supported too.
The existing Left/Right action identities stay; Up/Down and four `Plasma Fusion: Move to Screen ...`
actions are added. Setup waits for all eight actions before assigning keys; upgrade ownership rules
are in `docs/parts/device.md`.

#### Optional legacy width cycle

Enable **Legacy Left/Right width cycling** in System Settings > KWin Scripts > Plasma Fusion Snap
Layouts > Configure (`[Script-plasmafusion-snap] LegacyWidthCycle=true`). This retains the former
keyboard cycle (approved 2026-10-16), rather than making repeated directional keys resize windows.
"Plasma Fusion: Snap Left" and "Snap Right" (`ShortcutHandler`s of the snap script, no key of their
own: the setup moves Meta+Left/Right to them from KWin's `Window Quick Tile Left` / `Right`, as two
actions cannot share a key; docs/parts/device.md) step the active window through 1/2, 1/3 and 2/3 of
that side of the work area, then back to 1/2 (`Cycle.js`):

- where the window is comes from its size: its edge on that side and its top within 8 px of the
  area's, nearly the area's height (90 %), and a width within 3 % of the area's width of a step's
  width as the script places it, gap included (`Cycle.stepWidths()`: so the largest gap, 48 px, on
  a small area still gives known steps); a terminal sizes itself in character cells, hence the
  tolerances; anything else starts at 1/2;
- a client that has not drawn the new size yet still shows the rectangle it had: for a second after
  a request on the same side, while the window still has that rectangle, the step asked counts
  (`Cycle.currentStep()`, `cyclePending` per window with the rectangle it was asked from), so quick
  presses and key repeat go on through the steps; any other rectangle (the step drawn, or a drag or
  resize since) is measured, and a move to another screen drops it;
- 1/2 is KWin's quick tile (`quickTile()`, as the key gave before, so the other half is still
  offered by the picker), 1/3 and 2/3 plain geometry with the gap (`thirdRect()`, `zoneRect()`, as
  the flyout's thirds and 2:1 zone); a step leaves the window's snap group, as a layout choice;
- after 2/3, when a screen lies on that side (`Cycle.neighbourOf()`: the nearest one wholly on that
  side that shares some height), the window goes there, to that screen's facing half
  (`sendClientToScreen`, then the quick tile), as KWin's quick tile did on a second press; on one
  screen it goes back to 1/2. Meta+Shift+Arrow still uses the spatial monitor actions.

An update in a running session (2026-10-17, found on the ThinkPad's live session): the snap script
running then is the older one, without the two actions, and the setup cannot move the keys until
the new one runs. KWin 6.7.5 does not load a script that is loaded already, and a script unloaded
and started again is the older one once more: KWin's QML engine keeps every file it compiled by its
path and does not read it again (Qt 6.11.2 `QQmlTypeLoader::getType` returns the cached type for a
path; the cache is trimmed only from 64 types on, and KWin never clears it). So the setup unloads
it and loads it from a path the engine has not seen: a link to the installed package in
`$XDG_RUNTIME_DIR/plasma-fusion/kwin-scripts/` (a new one each time, gone with the session), with
`Scripting.loadDeclarativeScript` and `start`. At the next login KWin loads it from where it is
installed. KGlobalAccel retains inactive action names after unload, so the pending version upgrade
always reloads the script rather than treating names alone as evidence that the new code runs.
KWin's load/start D-Bus success also does not prove the QML component instantiated. Setup supplies
a fresh `StartupProbe` identifier and waits for a keyless probe action created after root completion;
it then unregisters that temporary action and deletes the config key. Preparation or acknowledgement
failure leaves the shortcut keys and migration marker unchanged.
Without a runtime directory the older script stays, the setup says the new one comes
with the next login, and the run is not marked, so the next update moves the keys. The other
Plasma Fusion KWin scripts run their older code until the next login.

Tests: `tests/snap-directional.test.js` (node, in the build step) checks every role/direction,
repeat and order invariants, and four-direction monitor selection. `tests/offscreen/snaptest.py`
also exercises the real shortcut handlers, rapid chaining before frame commits, opposite directions,
refused tiles, monitor transfer, no-neighbor behavior, fullscreen exclusion and legacy opt-in.
`tests/vsession/scenario-directional.sh` runs actual keys in a private three-output session:
all halves, opposite and repeated directions, both corner orders, original geometry restoration,
spatial monitor moves with resized splits, cold custom-tile bootstrap, a visible picker with two
real windows, and a fixed-size Qt window moving between outputs. It uses the staged build and
`tools/` as the session HOME's `pf-stage` and `pf-tools`; set `PFV_OUTPUTS=3` when running it.
`tests/snap-cycle.test.js` (node, in the build step): the steps from a window's size on
both sides and a second screen, the order, and the neighbouring screen;
`tests/offscreen/snaptest.py` (CI `build`, the real script with stand-in KWin objects): from the left
half, Snap Left gives the third, the two thirds and the half again with the 6 px gap, Snap Right the
right half, third and two thirds, and with a screen to the right the window is sent there; a press
before the client drew the third goes on to the two thirds; with a 48 px gap on a 1024 px area the
half, third and two thirds follow;
`tools/device/tests/shortcut-keys-unit.sh` (CI `build`): the setup's key move (with the
Windows-style set, once on an update while KWin's quick tile holds the key, never after the mark or
from another action the user chose; an update while an older snap script runs unloads it and
loads it from a link in the runtime directory to the installed package, then moves the keys; its
stand-in KWin runs the older code when the script is started again from its own path, so the
reload of 0.5.0's setup, a load from the installed path or a missing link fail it; without a
runtime directory the keys stay and the run is not marked); `tests/vsession/scenario-snapcycle.sh`
(a private session, real keys): Meta+Left four times and Meta+Right twice after the setup;
`tests/vsession/scenario-snapreload.sh` (a private session, the 0.5.0 package's snap script running
from login, the setup installing the new one over it): the setup loads it again, Snap Left has
Meta+Left, and Meta+Left twice gives the left third; with 0.5.0's setup the three checks fail; a
failed check fails the scenario (its status).

### Snap-zone outline

`outline.qml` replaces KWin's outline: rounded rectangle radius 14, fill rgba(91,157,255,.28) with a
2 px #5b9dff edge (light scheme: rgba(47,111,223,.20) / #2f6fdf; other accents follow the accent).
It fades in after 150 ms (TabsSnap "after the pointer rests at the edge for 150 ms") and glides
from the window to the zone. It draws the supplied geometry without an extra edge inset:
Meta+Z supplies its gap-aware target; a native padded quick-tile preview is expanded to the same
filled outer edges. The outline window's bounds include that expanded target. Matching custom
tiles keep their native preview: the outline API exposes geometry, not the tiling mode, so a
custom zone with exactly the same shape as a quick tile is kept native rather than guessed.

The outline needs the snap script's gap settings (`QuickTileGaps`, `Gap`) but runs in KWin's
outline context, which has no `KWin.readConfig`, so it reads them with `kreadconfig6` through
Plasma's executable data engine. It did so each time it showed, starting a shell and two
`kreadconfig6` processes inside KWin on every edge drag (survey B12). It now reads them when it
is created and again when KWin reloads its configuration (`Options.configChanged`, the moment
the snap script's own `KWin.readConfig` sees new values too, so preview and snap agree). Each read
is a new source of the data engine, which otherwise hands a source read moments before its old
result.

### Attached dialogs

A modal dialog whose parent has a KWin title bar is placed horizontally centred on the parent
and with its top on the parent's title-bar bottom (clamped to the work area). It is re-placed when
the parent moves or resizes and when the dialog changes its own size. Dragging the dialog detaches
it. Client-side-decorated parents (GTK/libadwaita) keep KWin's placement. With `sheetEnabled` the
stock sheet effect animates the dialog out of the parent's top edge and the stock dialogparent
effect dims the parent (Windows board's dimmed parent).

### Window placement memory

Each ordinary window is remembered where and as big as it floated last and, when its app opens it
again, set back to that rectangle: KWin's `windowAdded` fires after its own placement (Wayland and
X11), so the assignment wins. The record is per app - its desktop file when it has one (the stable
name across Wayland and X11), else the window class; a window with neither is left alone. A window
is only touched while it floats (not maximized in any way, not full screen or tiled, not a dialog,
transient or modal, not minimized); a window opened maximized keeps its last floating record. A
maximize KWin has asked for counts as maximized until the window has taken it: the commit with which
a Wayland client answers the request updates the frame before the maximize mode (KWin 6.7.5,
`xdgshellwindow.cpp`, `XdgSurfaceWindow::handleCommit`: the window geometry, then the acknowledged
states), so the first frame change after the request already has the maximized frame while
`maximizeMode` still reads 0, and a window maximized and then closed was remembered at its maximized
size (issue #128). The script mirrors the mode KWin asked for from `maximizedAboutToChange` (emitted
with the request, before any geometry change, on Wayland and X11; the same signal in 6.8 and
`master`; its last emission is exactly what KWin keeps as the requested mode, so the mirror is not
reset from the mode taken: with a restore and a maximize both in flight, a client that answers them
one by one takes the restore first, and the maximized frame that follows must still count as
maximized). At `maximizedChanged` a restore that has been taken records the floating frame the
window went back to (on X11 KWin sets the mode before it moves the frame, so the frame change itself
records it there) - also for a window that was mapped maximized and has no restore geometry, where
KWin asks the app for its own size at the work area's corner and that frame becomes the record,
as a close there would have made it. Known limit on a KWin without `requestedGeometry`: a maximize
and a restore in flight together, answered one by one, show the maximized frame while both KWin's
and the script's requested mode already say restored, so that frame is recorded until the restore's
commit records the floating one again; a close in between keeps it. A
window KWin holds in place - a window rule that forces its position (KWin's `moveable` is false
then), or moving switched off - is left to KWin entirely: assigning `frameGeometry` goes straight to
`Window::moveResize` and would bypass the rule. A forced or fixed size keeps the window's own size
on a restore. One second after an open the geometry the window settled at is recorded (the restored
spot unless the app moved itself again), every later floating change updates it, and so does the
close: KWin marks a closing window deleted before `windowRemoved`, and the script reads its frame
geometry and state as they were (a deleted window's tile request is a no-op, so the tile stays). The
quiet second keeps the restore itself and an app's late repositioning out of the record. On a KWin
with `Window.requestedGeometry` (only the optional backport, `packaging/patches/kwin`, has it: KDE
declined the property upstream), a frame that does not yet match the geometry KWin requested is not
recorded: a Wayland client answers a move or resize later, and a frame it commits after an untile
can still have the tile's size (KDE [bug 527821](https://bugs.kde.org/show_bug.cgi?id=527821)). The
record waits for the change that brings the two together, and a window that closes before that keeps
its earlier record. Positions and sizes less than 1 px apart count as equal, as an X11 frame is the
request rounded to native pixels. On a KWin without the property every frame counts, as before.
Windows already open when the script is enabled or reloaded (the Fusion setup enables it in a
running session; a reconfigure can reload it) are watched - their moves and closes are remembered -
but neither moved nor recorded on loading: recording every open window then would replace the
records the user left. A remembered spot is given back only while the centre of the rectangle to
apply still lies on a screen the session has (with `RememberSize` off that is the saved position
with the size the window opens with); when a window of the same app already sits (within 8 px) on
the spot on the same desktop and activity, KWin's own placement takes the new window instead (it
offsets it) and the held record stays - the new window's own geometry changes in its first second
are not recorded either, while the user's later moves are.

The memory file is `~/.config/plasmafusion-placementrc`, one JSON text under `[Windows] windows`
(`{"v":1,"apps":{"<app id>":{"x":…,"y":…,"width":…,"height":…}}}`). On a KWin with the native
placement writer (the fork's `Workspace.transientTiling()` facade, fork PRs #17-#20 — the
writer's own C++ methods are not callable from QML), the script registers as the provider,
binds each watched window to the writer under its app id and submits every record as a typed
native call: the provider incarnation token first, then the revision, the window, an already
rounded rectangle (the writer rejects fractional frames outright), the key's next event
sequence (the writer orders a key's events globally, so all windows of one app share the
counter) and the origin. The writer keeps a key's event watermark across provider incarnations:
a reloaded script (a reconfigure) that answers OutdatedEvent resubmits the same rectangle with
exponentially increasing sequences until it passes the watermark, so the first move after a
reload is not lost. The writer owns the file and its flush discipline, and the script's
in-memory cache is a read-through from the writer's `snapshot()`, re-read for a key before each
restore: a deferred same-key update (an active reservation held the key) only becomes visible
in the snapshot after its barrier ended, later than the cache's own write. A submission the
writer suppresses (a restore watermark) or defers reconciles the cache from the writer's own
entry. An orderly compositor teardown keeps the pending map: the writer persists an accepted
record no flush attempt has covered yet once, best effort, at its own destruction (fork PR #21)
— a flush that already failed is not retried there, and an interrupted compositor (or a file
the teardown write cannot reach) leaves the last flushed state, which the restarted writer
serves while accepting new records normally. Owner state never crosses a restart: the automatic
rectangle never entered the file, and the reservations, watermarks and window bindings die with
the writer, so a newly mapped client starts from the ordinary record alone. The writer binds a window to one key for its whole lifetime: a window that opens before
its identity is usable (no desktop file and no class yet) is bound at its first record, and an
identity that changes after the binding is neither rebound nor recorded natively — those
records live in the session cache only, until the writer grows a re-binding path. A window an
earlier incarnation of the script already bound (a reload) keeps that binding, and the script
asks the writer which key that is (`windowBinding`, fork PR #20): the record files under the
binding's key, never under a key the caller passes, so a refused track settled by assuming the
key would overwrite another app's saved entry when the identity changed across the reload,
where no comparison could detect or undo it. The same key confirms the binding (the reload's
binding is the one to keep writing through); another key retires it — the same
never-rebound policy as an identity that changed after the binding — and an empty answer (the
writer was busy and holds nothing) retries the track on the next record, the session cache
holding the record until then. A facade without the question (an older fork) never assumes
either: those windows keep their records in the session cache. When the
writer refuses the provider registration — or the facade exists but answers nothing — the
memory stays disabled for the session — a native
session must not bypass the sole native writer. The native lane runs only on the fork's KWin;
the session scenarios in CI exercise the stock and backport lanes, which take the legacy
transport, and the node suite drives the registration, identity-binding, refused-binding,
event-sequence and reconciliation rules (`packages/kwin/tests/placement.test.js`). On stock KWin or older forks
without the facade, both directions run through plasmashell's desktop scripting (`ConfigFile`,
the same bridge the tablet script's panel policy uses): the KWin scripting API has `readConfig`
and no file write at all, and plasmashell's `evaluateScript` answers with what the script
printed, which carries the file's text back. Writes are coalesced
(two seconds after the last change, one retry when a change races the write); the file is read
once at start with a few retries while plasmashell comes up - windows opened before that answer
keep KWin's placement - and written once more when the script is disabled or KWin quits (also
when a write is still in flight then: it carries an older snapshot). On that teardown the
script disconnects the geometry handlers it put on the windows: KWin keeps one QML engine for
its scripts and the windows outlive the script, so a handler left connected would call into a
destroyed context, and each disable/enable cycle would add another. A profile snapshot carries
the memory file (`tools/device/backup-profile.sh`, see device.md).
No timer runs while the desktop is idle.

### Dynamic workspaces

Off until the user turns it on (`EnabledByDefault: false`; the setup's `KWIN_SCRIPTS` does not list
it): System Settings > Window Management > KWin Scripts > "Plasma Fusion Dynamic Workspaces". The
reference behaviour is GNOME's (`WorkspaceTracker._checkWorkspaces`, gnome-shell 51.1); the KDE
Store script "KWin dynamic workspaces" (24,284 downloads, BSD-3-Clause) shows the demand and its
issues the traps - nothing is taken from it. The rules are in `Workspaces.js`:

- A workspace holds a window when a window of the user's lists it in `desktops`: a managed window,
  not a special one (panel, notification, OSD, applet popup, tooltip, desktop), not a popup menu,
  not on every desktop (KWin's own internal windows, such as the snap flyout, are) and not kept out
  of the pager. Minimized windows count. Windows of every activity count: KWin's desktops are
  shared by the activities, and removing one would move another activity's windows.
- When the last workspace holds a window, an empty one is added at the end (up to KWin's 25),
  named "Workspace N" for its position (Fusion's word, the `plasmafusion` catalogue).
- Every other empty workspace is removed, except the one right after the last occupied workspace
  (the empty one to move windows to), the one each screen shows (KWin 6.7's per-screen desktops
  give every screen its own; `currentDesktopForScreen`) and the first `KeepFirst`. KWin moves a
  window off a removed desktop rather than losing it, but the script only removes empty ones.
- After removals the script's own "Workspace N" names follow their positions. Ownership is kept by
  desktop id: only a workspace this instance of the script added, and that still carries the name
  it gave, is renamed. Every other name - the setup's Work, Design, Media and Chat, a name the user
  gave (also one like "Workspace 3"), KWin's "Desktop N" - is never touched. KWin scripts cannot
  write a file, so the ownership does not outlive the script: after a KWin restart or a
  disable/enable, the names from before stay as they are, even when a later removal puts them out
  of order.
- Timing: KWin's slide effect ends a desktop switch animation at once when a desktop is added or
  removed (`desktopAdded`/`desktopRemoved` -> `finishedSwitching`; its spring settles in about
  0.7 s at the default speed), so nothing changes until a second after the last switch. Removals
  also wait a second after a window that held its workspace closes (a dialog handing over to its
  app's next window, GNOME's 1000 ms grace) and ten seconds after the script starts: KWin 6.7's
  Wayland session restore puts windows back on their desktops by id, and a desktop removed before
  they come back would scatter them. Moving a window past the end within that second finds no next
  workspace yet. A burst of changes is one pass; the script's own adds and removes only schedule
  another pass, which finds nothing to do (the rules are a fixed point - the node suite checks it).
- A reconfigure (the KWin Scripts page applying `KeepFirst`) runs a pass with the new value
  (`Options.configChanged`).
- The top bar's workspace dots (`org.plasmafusion.clockpill`, `WorkspaceDots.qml`) and the stock
  pager read KWin's desktops through `TaskManager.VirtualDesktopInfo`, so they show the workspaces
  as they come and go without a change of their own.

Around it: the setup (`tools/device/fusion-config.sh`, "Workspaces") names the existing workspaces
but creates none while the script is on - it would remove them again and every run would count
changes; the login check switches the script off with the other Fusion KWin scripts when the
Global Theme is not Plasma Fusion (`docs/parts/gate.md`); a profile restore unloads it before it
puts files back and keeps it from loading again until the next login, because KWin writes its whole
`[Desktops]` group at every change (`docs/parts/device.md`). On teardown the script disconnects the handlers it put on the windows.

Known limits: a workspace that holds another activity's window stays; a window whose session data
names a workspace that was removed (empty) comes back on the shown one, as in GNOME; with several
rows the workspaces are added and removed in KWin's linear order and the grid reflows.

## Dynamic-tiling feasibility (2026-10-23)

The following paragraphs retain development checkpoints on their identified source baselines.
The maintained fork, current milestone boundary and later qualification limits are summarized
in the [status and source snapshot](https://github.com/archledger/plasma-fusion/blob/3e7a775add95c8f6b52dddd6b2956c6dc849b4c5/tasks/todo.md#status-and-source-snapshot).

The isolated native-ownership lane also tests the deprecated `Window.tile` compatibility setter.
A refused manual destination must leave the previous manual assignment and geometry unchanged.
Direct and Qt-property calls are covered with Wayland and X11 clients, alongside successful
cross-desktop and explicit-null controls. The cancellation continuation retains the Window and
guards the destination against destruction, newer cancellation/geometry intent and committed-only
changes. Pending/committed owner tests cover these checks; cancellation does not mean restoration
has completed. Post-management cleanup and broader owned-state validation remain separate NT02.5
leaves; the public state/completion API remains NT04 work.
The previous manual Tile is tracked with a guarded pointer across destination management, so its
destruction prevents a later cleanup call on the freed object. This is lifetime protection only;
it does not establish that a newer assignment may safely be cleared. The private native-operation
receipt and newer-intent-safe cleanup remain planned work.
The internal prerequisites now include an immutable Window-bound assignment fence. It observes
versioned Window state and retains its lifetime, but grants no mutation authority and has no
scripting entry point. Owned native-step receipts are still separate work; the fence is not
connected to the compatibility setter.
The fence also observes a per-window membership revision. Every actual tile membership change of
a window, ordinary or transient, advances it before the corresponding notification, and the
otherwise-valid public membership no-ops (managing an existing member, unmanaging or forgetting a
non-member of an ordinary tile) record the same intent under a conservative same-window rule;
refusals and the internal misses of an evacuation record nothing. Saturation counts as exhausted.
The transient admission snapshots the revision after its membership add and treats a change
across its publication as supersession. Public membership paths keep their bodies; a stale public
continuation resuming after a nested public re-management remains an explicit exclusion until the
guarded ingress.
A guarded maximize normalization serves ordinary assignment: it makes its own recorded writes and
guarded child calls instead of the public unmaximize, refuses without effect where the backend
would refuse (an owner or active request, an unresizable window, a rule-forced maximize, an
interactive or electric-border operation, the recursion guard, missing headroom, a backend
without guarded requests), captures the restore with the exact legacy formula, and returns a
receipt carried as an operation provenance (the requested-mode revision and the frozen size
limits) that every child boundary and later step evaluates; after its mode write every stop is a
supersession. X11 keeps its legacy path.
The public cancellation boundary has a qualified variant for a guarded ingress: its checkpoint is
taken after the cancellation's own callback-free writes (the placement stamp and, for an owner,
the release's transient membership removal and association detachment) and validated once after
the release's notifications and finalization, threaded through the controller's release and the
window's own revoke path without counting increments; exhaustion known before the stamp is
refused, a foreign change or a deleted window makes the continuation stale, and a current
continuation is reported even when the release cannot finalize, leaving the owner for a
consumer's entry refusal. The release and the legacy helper are unchanged.
A guarded requested-association step serves ordinary assignment: a read-only preflight (never a
grant) refuses before any mutation a transient tile, a backend without guarded requests, an owner
or active request, a transient marker no ordinary step may consume, an interactive operation, the
normalization's own refusals when tiling a maximized window, and the whole path's conservative
headroom; an equal association is an operation-owned no-op; otherwise the step takes its own
snapshot, runs the guarded normalization when needed and carries its receipt, captures the restore
through the guarded writer, writes the association under its own checkpoint, requests the geometry
through the guarded request, and discharges the association write's obligation (the backend's
quick-tile protocol state and the notification behind a recheck of the live window, the unchanged
association revision, the destination's identity with its original presence and the marker)
before the result is finalized; callbacks that invalidate the operation make it superseded although
the write stands. The public entry points establish their own operation: the qualified
cancellation is their single stamp, a refusal without effect selects the legacy body after the
cancellation, and a supersession stops; X11, interactive operations and the exhaustion edge stay
on the legacy path.
The Tile membership ingress has guarded steps of the same shape: refusals before any mutation (the
backend first, a transient tile, an unresizable or applet window, a window not on the destination's
desktop, a destination that is not live, the follow-up's read-only preflight, membership headroom),
operation-owned no-ops, the evacuation over a worklist collected without callbacks with the Window
retained and the destination's context frozen and validated after every notification, each
membership write sealed by its own checkpoint with its notifications as that write's obligation,
then the association step chaining the last checkpoint; a refusal after the first mutation is a
supersession and a destroyed destination is never read as explicit null. The public manage,
unmanage and forget establish their own operation after the mutation-free rejections (the qualified
cancellation first, so a valid manual intent revokes automatic ownership before any new membership
is published; a refusal without effect selects the legacy remainder; a supersession stops with
false), misses and deleted members keep the legacy membership-only paths (the workspace's removal
notification relies on the release of a dead member), and the outer quick-tile boundary verifies
its qualified preparation's currentness before the public management runs.
The compatibility setter (the deprecated window.tile property) consumes the guarded ingress with
its own continuation: the destination's context and the original membership captured before the
first callback, the complete path preflighted before any guarded mutation (the original's cleanup
reserved in the ingress's headroom, its null association preflighted), the ingress and the
cleanup of the captured original consumed on currentness with no retry, fallback or refreshed
checkpoint after the ingress applied; legacy only for a backend without guarded requests, at the
exhaustion edge and on an ingress refused without effect.
The X11 backend now takes the guarded paths for windows that need no unmaximize: its guarded
geometry request publishes synchronously as the request's own write (sealed before any callback,
with every X11 notification still announced), its immediate tile commit is the association
write's own publication through a carrier the step passes (a superseded request still publishes
the still-current association without being resurrected), and both committed changes are
budgeted before any mutation; an unmanaged window and blocked geometry updates are refused
before any mutation and keep the legacy remainder.
The X11 backend normalizes a maximized undecorated window for assignment as its own recorded
operation: the mode is written through one saturating writer the legacy maximize uses too, the
receipt pins that revision with the complete geometry constraints by value (the rule-checked
limits, the resize increments, the base size and aspect with their presence, the strict-geometry
rule, the decoration state and policy, the client frame extents and the Xwayland scale), the
restore is captured by the legacy formula through the guarded restore writer, the final rectangle
is requested through the guarded request, and the mode write's publication is its own obligation
gated by the live window and the revision alone, completed before the outcome is decided. A
decorated window and the borderless-maximized policy (the decoration transition writes geometry
through public paths on X11 and is routed through the operation in a later part), a fullscreen
window and an invalid prospective restore rectangle are refused before any mutation and keep the
legacy remainder.
The decoration transition is now the operation's own. A recorder, passed explicitly through
private variants of the policy setter, the decoration update, the creation and the destruction,
records the identified internal reactions instead of writing them (the border hook's workspace
check on a planned rectangle through the read-only decision, the creation's gravitated frame, the
update's own check, the frame-extents update), bound to the decoration incarnation it records for
before that decoration's initial state is applied; the public entry points keep their behaviour,
so a foreign call from a handler still writes and the fence detects it. The owned path takes no
geometry-update block, revalidates after every callback-producing step against the incarnation
and the policy revision it recorded for (the base window's installation reports the installed
incarnation's generation at its commit and withholds its final notification once that incarnation
is gone; each helper's own obligations follow its own write's currentness), bounds the supported
reaction sequences, ends the recorder's scope before the geometry request, validates the
authorized changes after the transition (the decoration
identity, the generation, the policy and its revision) and establishes the receipt against the
post-transition constraints, the border metrics included; the single guarded request commits the
client and buffer rectangles under the new borders, and the frame extents are an obligation of
the incarnation recorded for. A decorated window with a requested quick tile stays refused before
any mutation. The intermediate rectangles the legacy path installed and announced per write are
not installed and not announced; the committed result is announced accurately.
Two prerequisites for routing that decoration transition through the operation are in place.
The workspace-position computation of `checkWorkspacePosition` is a read-only decision (nothing
for a deleted, dock, desktop or unplaceable window; the legacy special-state branch for a
fullscreen, maximized or quick-tiled request with the rectangle it starts from and both screen
areas; otherwise the rectangle after the strut, edge, offscreen, size-constraint and rule checks),
and the wrapper keeps the legacy writes and their order, requesting an ordinary rectangle publicly
even when it equals the current one. A saturating decoration generation versions every
installation, removal and replacement of the decoration, advanced with the new pointer before any
observer runs while the displaced decoration is held; the X11 decoration policy is written through
one saturating writer that versions every change, installed before the decoration update.
A private native commit step validates that checkpoint and the current requested association,
then captures its own result before notifications. Superseded callbacks discard the result
without rollback; ordinary commit paths keep their existing behavior. This covers committed
association state only, not membership, geometry completion or eligibility, and is not yet
connected to the compatibility setter.
Saved restore-geometry field changes also advance the private continuation revision before
notification. The guarded field writer returns a checked checkpoint without cancelling ownership
or requesting geometry. Equal field writes remain no-ops, and empty/invalid restore sentinels
remain supported. The fullscreen restore field has the same guarded, versioned writer, and its
legacy setter advances the same revision on change. This does not yet guard keyboard restore
storage or backend geometry completion.
The private Wayland publication step handles synchronous committed client/frame/buffer/output
updates, not geometry requests or client configure completion. Actual geometry and legacy output
changes advance the continuation revision before callbacks. Interrupted notifications remain
pending for an explicitly invoked guarded drain; a pending-only drain takes a new publication
generation without changing placement. The helper rejects stale callbacks without refreshing
their checkpoint. Full Window/Xdg request orchestration and maximize normalization remain later
work; none of these private helpers enables production tiling.
The private requested-state synchronizer freezes the target output properties and versions
requested rectangle/output, property and pending-synchronization changes before callbacks.
It can finish an interrupted same-output synchronization without allocating a geometry-request
generation or emitting requestedGeometryChanged. Existing transient ownership is refused without
release. Property hooks may schedule configures; backend dispatch and client completion remain
separate from this storage step.
The private backend geometry request builds on that synchronizer. It reserves the request
generation, the exact synchronization writes, one committed-geometry change and one publication
generation before mutating anything, then allocates its generation and only afterwards takes the
checkpoint it validates at every callback boundary. Immediate updates consume the publication
helper's result; a resize that needs the client is staged as a queued configure and reported as
such, and the client's later acknowledgement completes it through the ordinary commit path. A
superseded request keeps the state it already applied and returns no authority. Only xdg toplevels
take these requests; everything else is refused before any effect. Callers pass a complete frame
rectangle with Move, Resize or MoveResize, as the legacy path does; a Move during an unsubmitted
resize is promoted to MoveResize. The step does not route transient-tile requests, normalize
maximize state or admit controller membership.
The private transient request now runs on those guarded steps. Its restore write goes through
the guarded restore writer, the requested association is installed between a validated fence and
an immediate checkpoint, and its geometry goes through an owned form of the guarded geometry
request that takes the exact active request, derives the target from it and always dispatches a
full move-resize; ordinary callers still refuse active ownership and active requests. Each step
result carries the borrowed request, because its external authority can lapse without any Window
counter changing, and the restore writer, the synchronized output-property writes, the Xdg
dispatcher and the Wayland publication helper validate it next to their checkpoint. The carrier
joins the result right after the callback-free rectangle write, since the request's own predicate
cannot hold between generation allocation and that write. Progress becomes Requested at
allocation and stays so. The geometry result's checkpoint then validates the quick-tile update and
the final requested-tile notification, so a handler that changes fenced state with the authority
intact supersedes the attempt as well. Known headroom and a backend without a guarded dispatcher
are rejected in preflight; a restore-writer refusal is rejected without effects, and a later child
refusal supersedes and removes only this attempt's association. The transient commit on client
completion stays gated on the ownership record.
The application of an ownership can now return, alongside that receipt, a qualified continuation
for a caller that goes on after it. The step result the request validated itself against borrows
the request, which the application consumes and destroys, so the continuation is translated while
the request still exists: the same checkpoint, preserved, with an ownership provenance bound to the
generation and, by value, to this attempt's native sequence, progress, request generation and
target, chained with the caller's own admission constraint. It is validated after the request's
destruction and the end of the execution, where current success is exported from only; an
attempt that ended without a current application is concluded, an application that did not start
is refused, and nothing is ever refreshed. The ownership, the receipt, the callers and the release
policy are unchanged by that translation. The controller's admission now consumes the continuation:
it preflights eligibility and headroom for the complete synchronous path, including failure cleanup,
before reserving or publishing membership. An ordinary membership on any desktop or output remains
ineligible, and X11 is refused before reservation. After its callback-free membership writes, the
admission seals a checkpoint with its controller, tree, window, generation, writer/provider and
context validity as provenance. Both membership notifications validate it. Acceptance requires
the native receipt and its current continuation after the request has been destroyed; a later
failure releases only this generation's transient membership and associations. A Requested attempt
keeps its restoration barrier, and loss of the writer leaves the unavailable record rather than
allowing another writer to reuse the window. These are private native paths; production tiling and
the public completion API remain disabled.
The controller-owned release tests observe every notification in both pending and committed
admission: the generation and floating frame are retained, transient membership and matching
associations are already detached, and the writer barrier remains. A current cancellation
continuation does not mean restoration completed. Its checkpoint can retain a logically closed
Window; the reservation and any deferred same-key manual update remain blocked until actual
destruction. Selective Qt-property rows exercise the same cancellation supersession checks as the
direct compatibility setter. These are native tests, not public completion APIs or provider
integration.
The internal placement writer can inspect an exact Restoring reservation by owner UUID and
generation without changing it. This predicate is distinct from its Owned-phase query. It does
not flush the map, consume deferred intent, prove provider freshness or authorize restoration;
native attempt and context validation remain separate.
The private explicit-restore precursor claims one Window-local sequence before release callbacks.
Its external result carries Window identity, ownership generation and the release checkpoint;
the Window record stores no self-retaining fence. A claim that fails after allocation stays
consumed. Accepted manual cancellation/commit intent and effective Window membership/output
changes invalidate it, while native configure commits keep their origin distinction. Stable
attempt validity is separate from the synchronous continuation. The claim itself sends no geometry
and is not connected to public actions; global desktop/activity navigation and later asynchronous
completion are not qualified by it. The explicit untile-or-restore action is now routed through
this machinery (fork PR #10): a record-holding window consumes the action as one qualified
restoration attempt — a five-value consumption separates started, stopped, in-flight and no-start
from not-owned — with the ordinary ladder kept for windows without a record. The action's
duplicate and no-start arms are consumed without legacy fallthrough; the close and newer-intent
arms ride the claim and request contracts.
The separate private restore request consumes that original claim checkpoint once. It uses distinct
restoration provenance, requires ordinary mode and exact feasible A on the recorded output, and
records the allocated native geometry generation before synchronization callbacks. The lower entry
also checks the active wrapper, unused generation, exact target and MoveResize mode. A duplicate
refuses without cancelling the original; a failed consumed request remains superseded with its
reached generation and dispatch evidence. Pending admission geometry is allowed, but pending
gravity is not silently cleared. Queued and Published requests remain distinct, and neither clears
the ownership record or writer barrier. The request and configure-placement protection are
qualified only within the private normal-mode/fixed-context scope. A dispatched restoration now
completes on its own boundary (fork PR #11): the acknowledged configure of the live restoration,
committed by the client, clears the restoring record with its reservation and installs the
writer's restore watermark; a configure-less (published) restoration settles on the client's next
commit; a cancelled attempt, a superseded request or an older configure's late acknowledgement
never completes anything. The read-only state/completion export and the unload/serial-wrap rows
remain later gates.
Configure acknowledgements now select one exact uint32 serial in queue order, preserving later
events across serial wrap. Unknown or ambiguous matches select nothing. The selected prefix is
detached before old configure objects are destroyed, because releasing a decoration can close
the window or reenter commit handling. A per-dispatch generation and consumed ACK prevent the
outer invocation from continuing after that reentry; selected-object tail disposal is guarded
as well.
Each geometry allocation also records a value-only origin, copied into native configures before
it can be confused with later manual intent. During explicit restoration, obsolete or unknown
content is accepted at the current committed position without synchronizing requested A. Current
restoration may place content but cannot replace A with client-selected dimensions; a genuinely
new ordinary request retains ordinary behavior. No-ACK content retains its origin, not old bounds.
A separate pending snapshot carries unfinished decoration, scale and committed-mode work across
nested dispatch. Pending content blocks new admission and supplies fullscreen interpretation for
interactive positioning. Guarded native synchronization preserves newer claims, and association
commit checks preserve newer manual placement. The writer reservation still waits for NT04.
A separate private maximize-capable claim can normalize horizontal, vertical or full maximize,
including a pending committed mode, before requesting the immutable floating frame. It supports
CSD and a surviving same-identity SSD; fullscreen, borderless-maximized policy and returning or
replacement decorations remain refused. Explicit stages prevent geometry dispatch during mode
notifications. Revision-bound backend state prevents later mode/output-intent writes from
reviving an old request. Existing SSD borders are checked exactly after their normal-mode
response, and a failed consumed attempt preserves its mode-publication obligation without
falling back. The normal-only claim and public owned toggles keep their separate behavior.
The returning-decoration work also guards reads of one decoration settings instance. It
snapshots values before notifications, stops after a nested read or destruction, and emits
stable local payloads rather than references to members a callback can replace. An older
read cannot re-enable the application-menu view service or announce completion after a newer
read took over. This does not yet guard the bridge's complete configuration operation,
cross-generation settings, factory lifetime or decoration publication.
Decoration recreation on a plugin or theme change visits a snapshot of guarded windows in
workspace order instead of the live list. A member deleted by an earlier callback is skipped,
the visited window is retained until its callback returns so that closing itself cannot free
it while its decoration is being constructed, and windows mapped by a callback wait for a later
pass. Plugin-creation failures remain unguarded.
A configuration change that a decoration plugin requests while the bridge is loading a
plugin, creating a decoration or recreating decorations no longer runs nested inside that
operation. The bridge counts its nested operations, marks the request and, once the outermost
operation has unwound, applies the newest configuration with one queued pass bound to the
bridge. Several requests during one operation share that pass, and a change made while the
bridge is idle still applies at once. Until the follow-up runs, the bridge keeps reporting the
previous plugin and newly mapped windows still receive it.
The bridge borrows the decoration plugin's factory instead of owning it. The factory is the
plugin library's shared Qt root object, so switching or disabling plugins only drops the
reference and destroying a bridge leaves it alone; loading the same library under another id
returns the object already held. If something else destroys the factory, the bridge reports no
plugin and creates no new decorations until the next reconfiguration loads the configured
plugin again. A factory that is no longer used stays alive until the library is unloaded.
An owned window's ordinary maximize toggle keeps its ownership. The toplevel decides before the
first callback whether it acts as the owner, from a live ownership-validity predicate (same
generation, Owned phase, nothing executing or releasing, valid writer/provider/reservation, live
tile holding the window in a current context, the window's own single desktop and move-resize
output equal to the recorded ones, association unchanged) that is separate from admission
feasibility, and from a mode-aware plan: every axis the toggle releases must be able to return to
the managed extent under the client's size limits. An interactive or electric-border operation, a
caller-supplied restore rectangle, a record whose tile or context is unusable or a managed extent
the client cannot honour selects the legacy path, which releases as before; an owner is never
silently enlarged or recentred. The owned path emits the about-to-change signal, revalidates the
fence, the ownership, that feasibility and a requested-mode revision that every requested-mode
write advances, writes the mode, treats each decoration signal as its own callback boundary
(guarded pointer, scoped recursion flag, revalidation after every emission), and passes the
feasibility to the owned geometry entry as the operation's own constraint, which the
ownership-kind provenance evaluates at every child boundary; it never touches the restore field
or the tile. It requests maximized axes from the maximize area and released axes exactly from the
managed rectangle frozen beforehand through that owned geometry entry keyed by the ownership
generation; the step-result carrier is a tagged provenance validated by every child step.
Publishing the mode to the client is the mode write's own guarded obligation and reports no
success; after supersession nothing falls through to the legacy path. The acknowledgement of the
maximize configure still commits a kept association. X11 remains separate.
An owned window's ordinary fullscreen toggle keeps its ownership as well. The toplevel decides
before the first callback, from the same ownership-validity predicate, whether it acts as the
owner; an interactive operation, a client-requested output other than the one the ownership
lives on, or any lapse of the record selects the legacy path, which moves and releases as before.
The owned path writes the requested state, configures the decoration as a callback boundary
(plugin code creates it), revalidates the fence, the ownership, the separately versioned state and
output intent (a nested output-only request publishes nothing, so it must not suppress the state's
publication), the frozen requested-output identity and the maximize revision. Entering, it stores
the rectangle an owned exit returns to, the managed rectangle or the maximize-area extents on the
maximized axes of a retained requested mode, through the guarded fullscreen-restore writer, and
requests the fullscreen area through the owned geometry entry with the intent and feasibility as
its constraint. Exiting, every non-maximized axis must be able to return to the managed extent
under the client's size limits: the plan checks this with the undecorated conversion, exact when
no server decoration returns and with that decoration's enforced minimum as a necessary condition
otherwise, and the exact check runs once the restored decoration is configured, a prefix the
legacy path shares; an extent the restored decoration cannot return to, with the client's size
hints unchanged, hands the exit to the legacy path (a predictable effect, not a supersession),
while changed hints end the operation where it stands, and a superseded owned operation never
reaches the legacy tail. The exit returns to the frozen rectangle, never to the stored field.
Publishing the state is the state write's own guarded obligation. The explicit untile-or-restore
action releases an owned fullscreen window on its first press: the dispatch routes an owned window
to the owning layer, which leaves a requested fullscreen state, acknowledged or still pending, as
the owner and releases only if that exit completed as the current intent (a nested round trip
ending not fullscreen holds the newer intent and survives; a pending entry's stale configure commits
no association); the window's lifetime is retained, and windows without ownership keep the one-step
semantics. The acknowledgement path is unchanged.
The lane's Memcheck runs use a labelled profile: `QT_HASH_SEED=0` in the Valgrind environment
only. Qt 6.11.2's AES short-string hash deliberately loads 16 bytes for keys shorter than that
and masks the surplus; Memcheck reports it whenever that window leaves the key's heap block, which
made startup results address-dependent without pointing at KWin code. With a zero global seed Qt
uses its non-AES hash, so the profile avoids the path rather than suppressing the function. It
changes the hash algorithm, container iteration order and performance of the test process, so the
ordinary randomized functional runs stay as they are, and a clean Memcheck result under this
profile qualifies neither the AES path nor other Qt startup code. Qt's `QT_NO_CPU_FEATURE` switch
cannot serve instead: from 6.8 to 6.11 its feature-name table carries leading spaces that its
parser does not skip. The two startup initializer defects the lane found (an `Options` boolean
and the test fixture's relative-tablet flag) were first fixed with their regressions on the
private branch `fix/startup-initialization` (`136c04f435704ce5d9d1593ea35913862f2572bb`), separately
from those native checkpoints. The maintained fork now includes that correction as `9c6fb381`;
the source snapshot above distinguishes this from later unresolved startup diagnostics.

Dynamic tiling is not implemented or installed. Its approved plan starts with a native ownership
gate. The test-only `tests/vsession/auto_tiling_probe.py` and `scenario-auto-tiling.sh` characterize
one candidate: temporarily replace the custom tree and rebuild the saved layout when finished.

KWin 6.7.5 and 6.7.91, both with Qt 6.11.2, accepted four native master-stack leaves without stealing
focus. Unmanaging those four windows restored their original floating frames. However, replacing
the tree also changed an existing manual window's tile and saved the replacement to `kwinrc`.
After a deliberate SIGKILL of the private compositor and reopening the same disposable HOME, both
versions loaded the replacement rather than the original layout. Gate A therefore remains blocked.

These results reject that temporary-tree approach; they do not prove that every native solution is
impossible. A separate ownership/recovery design needs review before production work. Restoring a
known fixture normally is not proof of arbitrary-layout or crash-safe restoration. Hotplug, forced
rules, Activity transitions and interaction with all placement scripts remain unqualified for the
proposed feature. The existing directional tests remain the baseline, not tests of a new tiler.

To reproduce in an existing local test image, use fresh names and disposable paths:

```sh
name="tiling-gate-$(date +%Y%m%dT%H%M%S)"
seed="$PWD/build/$name-seed"
persist="$PWD/build/$name-home"
test ! -e "$seed" && test ! -e "$persist"
mkdir -p "$seed/pf-tools" "$persist"
cp -a tools/. "$seed/pf-tools/"
cp packages/kwin/tests/vsession/auto_tiling_probe.py "$seed/auto_tiling_probe.py"
touch "$seed/tiling-gate-crash"
PFV_IMAGE=localhost/plasma-fusion-test:f44-6.7.5 PFV_OUTPUTS=2 PFV_HOME_DIR="$persist" \
  tools/vsession/cvsession.sh "$name-crash" \
  packages/kwin/tests/vsession/scenario-auto-tiling.sh "$seed" 1440x900 150
PFV_IMAGE=localhost/plasma-fusion-test:f44-6.7.5 PFV_OUTPUTS=2 PFV_HOME_DIR="$persist" \
  tools/vsession/cvsession.sh "$name-reopen" \
  packages/kwin/tests/vsession/scenario-auto-tiling.sh "$seed" 1440x900 120
```

Use `localhost/plasma-fusion-test:f44-6.8beta` for the second lane and verify its actual package
versions. Read `vsession-out/NAME/result.json`: `characterizationChecks` tests whether the experiment
ran as intended; `acceptance` and `gatePassed` report preservation separately. The first session
must produce `interruption-sent.json`, confirming the kernel accepted SIGKILL through a pidfd for
the verified private compositor. A missing receipt makes that interruption trial inconclusive;
the wrapper's status line alone is insufficient. The reopen phase records the observed failure
before rebuilding the disposable fixture. The wrapper's final exit code alone is not a verdict.
The probe refuses to run outside a matching private container HOME/runtime and targets only its
same-UID ancestor compositor with the exact private socket. It never signals the logged-in KWin.

## Verification

Offline (laptop):
- `qmllint` on every QML file (only the expected "org.kde.kwin not found" import notes: KWin
  registers that module at runtime); `node --check` on main.js; XML parse of main.xml/config.ui;
  the build script checks ids and structures. Build is deterministic (plain copies).
- `node packages/kwin/tests/placement.test.js` (the build runs it when node is installed): the
  placement rules - identity (desktop file over class, lowered), the file's round trip and broken
  records, the centre test (a between-screens gap, a screen left of the origin), the 8 px stack
  guard, size-only mode, the ignore list (app id and window class), windows held by a rule (forced
  position, forced or fixed size), the teardown write (a change made while a write was in flight),
  the record's rounding, the settled test against `requestedGeometry` (missing property, a
  pending move or resize, an empty requested size, X11 rounding under 1 px, malformed values), and
  the maximize asked for but not yet taken (`maximized`, `requestedMode`: a full or partial
  maximize pending, a restore pending while the frame is still maximized, a signal without a usable
  mode, no tracking at all), and the native-writer rules (a refused registration disables the
  memory, the one-key-per-window identity binding, the per-app event sequence the writer orders
  globally, the cache reconciling from the writer's entry - a deferred update that became visible
  after its barrier ended wins, and the restore reads the refreshed entry - and the rounded,
  representable submission rectangle).
- `node packages/kwin/tests/workspaces.test.js` (the build runs it when node is installed): the
  dynamic workspaces' rules - which windows hold a workspace (every exclusion), the plan (GNOME's
  cases, an empty one in the middle, the shown one, each screen's shown one, `KeepFirst` and its
  bounds, KWin's ceiling with removals making room), 5000 random states (never an occupied, shown,
  kept or the trailing empty workspace removed, one always left, a second pass a no-op), the
  timing gates, the numbered names and their ownership (a user's "Workspace 3", a name changed
  since, another desktop's id).
- `node packages/kwin/tests/snap-groups.test.js` (the build runs it when node is installed): snap
  groups - forming a group from the picks, a window in one group at most (joining another
  arrangement moves it), membership and zones changing together (a window left alone by a transfer
  is forgotten with its zone), leaving and a group of one ending, the checks asked at use
  (`holds`: tile, settled rectangle, place, maximized; `fillValid`: desktop, activity, work area,
  layout family; `sharedActivity`), the zones' fill order (wrapping,
  skipping held zones) and the thirds' zone test (a terminal a few px smaller still counts).
- Offscreen renders with a stand-in `org.kde.kwin` module (`packages/kwin/tests/offscreen/`,
  PySide6 + private Xvfb display, private HOME): `run.sh STAGE_HOME switcher-harness.qml OUT.png
  [dark=false count=N otherDesktop=N current=N]`, `snap-harness.qml mode=flyout|picker`. Measured
  against the board render: card 170,268 1100x316 (board 170,268 1100x316), tabs, rows, key caps
  within 1-2 px (`tests/compare.py` for side-by-sides). Edge cases rendered: 30 windows (scrolls to
  the selection), 0 windows, 2 windows, all windows on another workspace.
- `QT_QPA_PLATFORM=offscreen dbus-run-session
  --config-file=packages/kwin/tests/offscreen/session-bus.conf -- python3
  packages/kwin/tests/offscreen/snaptest.py STAGE_HOME` loads the built snap script and outline
  in Qt. It checks flush outer edges, inner gaps, thirds/portrait rows, offset/odd work areas,
  picker geometry, existing tiled windows, native geometry updates, shared-split resize and
  leaving an interactive move or tile, and the quick-tile root: found by class name and by shape,
  roles from the shape with the children in another order, a ninth child, another desktop's
  custom root with quick-tile-shaped children never taken for it (script and outline; the 0.4
  test of eight children fails 4 of these), and the outline's settings: not read again when it
  shows, read again when KWin reloads its configuration and then back to the default (`Options`
  stub; with the 0.4 outline 6 checks fail: it read the new gap on show, then kept it from the
  data engine's cached result, which the later geometry checks inherit). The geometry checks set a
  6 px gap; the default, none, has its own: the script's, the outline's before and after it reads
  its settings and for a gap that is not a number, and the settings dialog's (`main.xml`,
  `config.ui`); each fails with its old default of 6 (2026-10-16, 65 checks). Build the stage
  with `STAGE=STAGE_HOME tools/build.sh kwin`.
 - `QT_QPA_PLATFORM=offscreen python3
   packages/kwin/tests/offscreen/tiling_lifecycle_test.py [PACKAGES_KWIN_DIR]` (CI `build`, on
   the snap geometry step's stage) loads the real placement `main.qml` in Qt with the stand-in
   `org.kde.kwin` module and a mock of the fork's `TransientTilingApi` facade, then drives the
   tiler's whole native lifecycle through the Tile Workspace shortcut: the tree created and the
   master admitted before any stack geometry write (invariant 8; the mock snapshots the stack at
   `createTile`), the configured `MasterFraction` reaching the native tile, the endpoint-rounded
   column the script writes, a window joining live, the untoggle (floats back, the master's
   `restoreWindow`, `releaseTile` with the admitted generation, and no second teardown when
   the release reports the tree's end), a refused admission (its tree released), a cell
   landing a fraction of a pixel off on a 133% output (still the tiler's own), a facade
   without `restoreWindow` (the tiler off, the memory's transport intact), the native
   `treeChanged`
   teardown (floats back, no release of an ended tree, the next toggle lays out again) and a
   refused tree (no admission, no geometry write); a further run (`scenario: "released"`)
   drives the master a native teardown released without restoring it, against a mock of
   `settleWindow` and `floatingFrame` that answers as the fork does: a master the native
   layer is restoring (left to it), one returned from its fit and settled, one in the user's
   hand (left there, settled when the drag ends, recorded where it was put), one released
   onto another automatic rectangle (returned), one the user was resizing (not moved until
   let go), one held while maximized and settled when it is back, a held record settled by
   the next toggle, the admission's retries (accepted on a later attempt, bounded, dropped
   by a newer press), an unsettled master left out of another session's stack, a second
   window of the master's app (the mock's writer reports the key's second window as the
   fork's does: the master released at once, the tree's end queued; the new window is given
   no cell, keeps its place and records nothing), a float given back while the cell's
   configure is in flight (asked for once more when the cell lands, not a second time, and
   not while KWin still asks for the float), the app's remembered place being another
   window's (the mock's writer admits a window only from the app's entry: the toggle records
   the master's own place first; nothing is recorded beside another window of the app, of a
   window on the tile's rectangle, or in the quiet second), a press with the active window
   on a screen other than KWin's active one (that window's screen is tiled), a master sent
   to another output
   (returned to the float the record carried there), a float on a display that is gone
   (never applied, then applied when the display is back), a released master and a tiled
   master that close and are destroyed (the mock refuses a destroyed window as the
   compositor does) and the script destroyed while a record is held (nothing stays
   connected). Each step waits for the condition it checks, not for a fixed time; after the settling second, the joined
   windows' saved floats - never a cell - are what the memory recorded (invariant 7), and
   the shortcut invoked on another desktop while a session lives tiles the invoked view even
   though the untoggle's activation carried the current desktop back (the stub emulates that
   in its restore hook), an ignored app's live join records nothing, and a reflow-starved
   member's late cell commit is quieted by the float restore. Mutation-checked: skipping
   `admitTile`, skipping the untoggle's `releaseTile` and ignoring the teardown each fail it.

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
- `scenario-snapgroups.sh` (strict mode, verdict at the end, real keys through `pfinput`): Meta+Z
  -> quarters -> Enter, then Enter for each of the other three quarters fills all four; minimising
  one minimises the group, restoring one restores it; activating a member raises the group above a
  covering window; a member moved out of its quarter leaves (the group minimises without it);
  Meta+Z -> thirds fills all three thirds and that group minimises together; a window placed anew
  through the flyout (another third) leaves that group; a window that already holds a quarter can
  be picked for another, and the quarter it leaves is offered in its turn (all four filled); a pick
  of a window that closed while the picker was open ends the sequence (the halves picker still
  works for that window afterwards); the first window moved out of its quarter right after its
  placement ends the sequence (no picker); a window the switcher skips keeps its third (nothing is
  placed over it), and neither does a minimised one; the first window sent to another desktop while
  the picker is open ends the sequence; thirds members sent to another desktop or activity leave
  their group; a window the sequence placed that closes before the layout is full leaves its zone
  to be offered again; a minimised member of another group picked for a new layout is restored
  alone; a thirds member moved by a script leaves its group, also when the move comes within its
  placement's settle (asked at the group's next use); the first window moved by a script while the
  picker is open ends the sequence; a window of another activity does not hold a third; a placed
  window moved out of its third by a script while a later picker is open leaves the third to be
  offered again; a window of another activity is not offered; a window moved into the offered third
  while the picker is open is not covered by the pick; the halves picker
  after Meta+Left still pairs its two windows.
- `scenario-placement.sh` (strict mode; a step that fails is written to the checks; every check
  runs and the scenario's status - "scenario rc" in the session log - is non-zero when any check
  failed, after a verdict line): windows
  opened before the script is enabled are adopted - not moved, nothing recorded on loading (an
  earlier record stays), a move remembered, a close without a move recorded where the window was
  left; a window moved to a distinctive spot and closed comes
  back there on its next open (the memory file carries the entry); a spot moved off every screen
  is not restored (the window lands on-screen by KWin's placement); a second window of the same
  app is not stacked exactly on the held spot, and when it moves itself while it opens the held
  record stays; `IgnoreApps` leaves that app's window alone; a
  window rule that forces the position wins (the window opens at the rule's spot, the record
  stays); a disable/enable cycle with a window open leaves no errors from the unloaded instance and
  the new instance remembers the next move; a window maximized by a script (`setMaximize`) and
  closed keeps its floating place, and the step records what `maximizedAboutToChange` delivers;
  the same for a vertical-only maximize; the same through KWin's own operation
  (`slotWindowMaximize`, the shortcut's and the title bar's path) with a restore in between: the
  restored window floats where it was and that place is recorded again (a second window of the app
  had taken the record meanwhile), a move after the restore is remembered, a close while maximized
  keeps it; an X11 window maximized and closed keeps its place (in a session with Xwayland,
  `PFV_XWAYLAND=1`, which the backport lane sets; a session asked for Xwayland that has none fails
  the step, any other is skipped as INFO). The disable/enable step also maximizes and restores the
  window that lived through the cycle, so a maximize handler the unloaded instance left behind
  would show up as an error.
- `scenario-placement-pending.sh` (strict mode, verdict and "scenario rc" as above): KDE bug
  527821's order with `tools/tests/lib/heldclient.py`, an xdg-shell window whose answers to
  configure events the scenario sends (it needs pywayland: `python3-pywayland` on Fedora, in the
  test image; it refuses to run outside a private session). The window floats at A and is
  remembered there; it is tiled, acknowledges the tile's configure without committing, is untiled,
  then commits the tile-sized frame and closes before answering the untile's configure. On a KWin
  with `requestedGeometry` the memory must keep A; on one without it the outcome is reported as
  INFO (the tile size is recorded). Then a tile and untile with prompt answers: the window floats
  at A again, A is kept, a later move and the close are remembered. Then a maximize and a restore
  requested while the client holds its answers, and the restore answered alone (acknowledging a
  configure supersedes the earlier ones, so KWin never reports a maximize mode change): the window
  floats at A, A is kept and a later move is remembered (the requested mode the script mirrors is
  not left pending). Then the client asks to be maximized itself (`maximize`:
  `xdg_toplevel.set_maximized`), answers at once, asks to be restored (`unmaximize`: back where it
  was, the record kept), asks to be maximized again and closes maximized: the floating place is
  kept. Then, on a maximized window, a restore and a maximize requested before the client answers
  either, answered one by one: the restore is taken first, the maximize's commit then shows the
  maximized frame while the mode still reads restored, and the memory keeps A through it and
  through the close. For the backport's lane,
  `tools/tests/kwin-backport/run.sh --rpms DIR` builds the image with the backport's packages,
  installed with the command in `packaging/patches/kwin/README.md` (the test image has
  `kwin-devel`, so it takes that subpackage too), and runs this scenario and
  `scenario-placement.sh` in both images; the `kwin-backport` workflow runs it nightly without a
  GPU (docs/parts/ci.md). On 2026-10-26 (ThinkPad, `cvsession.sh`), the scripts as they were before
  the maximize steps: 12 of 12 checks with the backport and 11 of 11 in the stock test image (the
  tile size recorded, as INFO, as with the previous script); the previous script with the backport
  failed the check that the memory keeps A; and `scenario-placement.sh` passed 25 of 25 in both
  images. With the maximize steps (issue #128, 2026-10-26, ThinkPad, `cvsession.sh`, images
  `f44-6.7.5-pw` and `-pw-pf1`): `scenario-placement.sh` 51 of 51 on stock and on the backport (with
  Xwayland; 44 of 44 in an earlier form of the steps without the render node too),
  `scenario-placement-pending.sh` 33 of 33 on stock and 34 of 34 on the backport; the same scenarios
  with the previous script failed 9 (placement) and 6 (pending) checks, every one a maximize check
  with the record `0 34 1440 866` (the vertical maximize's `217 34 590 866`); in the Plasma 6.8 beta
  image (KWin 6.7.91, laptop) 51 of 51 and 33 of 33. `maximizedAboutToChange` delivered
  `{"type":"number","mode":3}` to the script on both KWins. On the ThinkPad's logged-in session (4/3
  scale) the fixed script kept the floating place of a KWrite maximized by script, by KWin's
  operation and through Xwayland.
- `scenario-workspaces.sh` (strict mode, verdict and "scenario rc" as above): the setup's four
  named workspaces and a window on Work, then the script on: nothing removed in the first seconds,
  then down to Work and Design; a window moved to the last workspace adds "Workspace 3" at once;
  following it, the empty Work goes a second after the switch and "Workspace 3" becomes
  "Workspace 2"; a move together with a switch adds the next one only after the switch settled; an
  empty workspace stays while shown and goes when left; a window on every desktop, or kept out of
  the pager, holds nothing; a close removes the extra empty one a second later; the setup run again
  creates no workspace; a workspace the user adds empty goes again unless `KeepFirst` keeps it; a
  name the user gives in the script's own form ("Workspace 7" in second place) stays after a pass and
  after a restart; a disable/enable cycle leaves no errors and the new instance works.
  The times come from the script's own log lines.
- Journal (`journalctl --user`, the private sessions log there): no messages from these packages.
  Libplasma prints "Member visible of the object PlasmaQuick::Dialog overrides a member of the
  base object" once per process that uses PlasmaCore.Dialog (plasmashell, the stock thumbnail_grid
  switcher, and these packages); it is not caused by the QML here.
- Evidence: the kwin build run of 2026-09-29 (the maintainer's records): `screenshots/dark`,
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
- Snapped halves: corners stay as the decoration draws them (Aurorae: square client corners); the
  board's "square inner, rounded outer" corners need the compiled decoration.
- With a gap set, the first snap on each workspace/screen shows it one step late (the script can
  only reach KWin's quick-tile root through a tiled window, so it sets the padding right after the
  first snap). The padding stays until KWin restarts if the script is disabled.
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

When KWin advertises integer `plasmaFusionThumbnailSourceLifecycleVersion` 1 or later on
`WindowThumbnail`, the switcher clears its client assignment while the card is filtered out
or the switcher is closed. Missing, zero, negative, non-integer and non-numeric values keep
the baseline client assignment, including while hidden. The switcher remains usable.
The card and thumbnail objects remain reusable; reopening restores the visible assignments.
Version 1 promises bounded cache-cleanup connections per live view/client pair, removal of
the pair's entry and remaining callback when either endpoint is destroyed, and weak ownership
that does not extend either endpoint's lifetime.
It binds the native `client` property, not `wId`: on KWin 6.7.5,
`setClient(null)` disconnects the previous client's geometry signal, whereas clearing `wId`
does not. The client comes from the switcher's existing window lookup. Clearing the assignment
does not establish GPU texture reclamation:
KWin may retain its texture provider and previous paint node.
`packages/kwin/tests/offscreen/thumbnail_lifetime_test.py` checks assignment and object identity
with the staged switcher on a private bus. It runs in the build workflow after the KWin stage
is created; eleven capability cases cover supported/future versions and malformed or absent
values. The test's KWin stub checks assignment and object lifecycle, not real compositor
GPU memory usage. No memory saving is claimed without a native measurement.

The native lifecycle regression lives in `packages/kwin/tests/native-thumbnail`. Build its
test-only QML probe with Qt Core/QML development files, then run it in each existing test image:

```sh
cmake -S packages/kwin/tests/native-thumbnail -B build/thumbnail-probe -G Ninja
cmake --build build/thumbnail-probe
STAGE="$PWD/build/thumbnail-stage" tools/build.sh kwin
python3 packages/kwin/tests/native-thumbnail/run.py \
  build/thumbnail-stage build/thumbnail-probe build/thumbnail-native \
  thumbnail-case "$IMAGE" --runtime-manifest runtime.json
```

The runtime manifest contains the resolved image id in `image`, and a `files` mapping from
`kwin_wayland` and the versioned `libkwin.so` filename to their SHA256 hashes. It must describe
the actual provider build. Use `--retain-hidden` to check the baseline assignment policy on a
compositor without the capability. The runner records seed hashes, checks loaded binary
provenance, and rejects compositor, shell or bus-service crashes. It requires the separate
`dbus.log` alongside the compositor log and quits the private shell before bus teardown.
Use `--filter-target` to place the target on another private workspace and toggle All workspaces
and This workspace during each cycle. Its 48 snapshots must show the target assigned only in
All workspaces when release is supported, or assigned throughout for `--retain-hidden`.
The other fixture window is explicitly focused before measurement: KWin's input method otherwise
adds two unrelated geometry listeners when the measured target regains focus after closing.
After the filtering measurements, the target returns to the current workspace for the resize
check; an off-workspace Qt client can suspend rendering instead of committing a resized buffer.
The runner requires exactly one successful scenario status and actual compositor-session status
in `scenario.log`, plus a successful wrapper status. It rejects inherited `PFV_HOME_DIR` and
`PFV_PRE` overrides so the recorded seed cannot be replaced or modified before startup.

Use a new run name and the matching image for each case. The probe adds instrumentation
only to its copied seed, dumps the test window's native geometry connections through public Qt
APIs, and checks 12 open/close cycles followed by resizing. Connection totals must remain stable
within each state and decrease on close in the release-enabled profile. It counts all geometry
connections, not GPU resources or individual callback invocations. Assignment checks follow the
selected profile: one assigned preview for a shown target, none for a hidden or closed target
when release is supported, and one throughout the retained fallback. Do not run the scenario
against a logged-in compositor.
The parser's offline checks run with `python3 packages/kwin/tests/native-thumbnail/test_check_connections.py`.
The session-status and fresh-seed guards run with
`python3 packages/kwin/tests/native-thumbnail/test_runner.py`.

On unpatched KWin builds, recreating a `WindowThumbnailSource` registers cache-cleanup
callbacks whose connections can outlive that source. Geometry-connection stability alone does
not establish bounded lifetime, which is why the switcher releases its client assignment only
when the compositor advertises the lifecycle capability; every other build keeps the baseline
assignment while hidden.

The maintained provider (`archledger/kwin#5`, runtime `3a4a942`) supplies version 1 and bounds
cleanup connections per live view/client pair, removes the pair and its remaining callback when
either endpoint is destroyed, and keeps weak ownership. Its native suite covers twenty
recreations, independent views and clients, and both destruction orders; restoring the old
cleanup while keeping the capability fails four of its eight results. The switcher's enabled
and fallback native matrix passes enabled release and retained-client behavior over 144
observations. Neither result claims GPU texture or memory reclamation.

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

Evidence: the `review-*.png` files of the kwin build run of 2026-09-29 (the maintainer's records;
dark and light evidence runs after the fixes, the edge cases, board side-by-sides). The builder's
evidence files `screenshots/light/10-switcher.png` and `11-switcher-all-workspaces.png` show the
white-out that is fixed now.

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
  (`evaluateScript`), so a screen that appears after login gets its top bar. Since 2026-10-09 it is
  also sent once 5 s after the script starts (screens attached at login, and bars made before that
  date get their status area), and a "skipped" answer (layout not loaded, panels not on their
  screens yet) or a failed call is retried with a growing delay: every 3 s for the first ten
  tries, then every 6 s, 40 tries in all (about three minutes; a slow start, the parity VM,
  needed more than 15 s). Only the first skip of a burst and the give-up are logged (until
  2026-10-12 every try logged a line: a laptop logged about 20 at every session start). The text
  comes from
  `ensureTopBars.js`, which the build generates from the Global Theme's file. (A layout template
  with `loadTemplate()` did not work: plasmashell loads only templates of the panel category,
  which would also put it into "Add Panel".) When the answer says a bar was added or completed, or
  a dock was made ("Dock on every screen", a screen plugged in; `contents/ui/Panels.js`
  `addedWidgets()`, tested by `packages/kwin/tests/panels.test.js` in the build; a "skipped" of either
  part, the top bars' or the docks', or a dock reported not made, is asked again, `needsRetry()`;
  both can hold at once, a dock
  made while the top bars' part was skipped, and then the tier is asked for before the retry,
  `afterAnswer()`, also checked in the offscreen snap harness), the script asks
  systemd (`ReloadOrTryRestartUnit plasma-fusion-powerfx.service`) to have the power service apply
  its tier to the new widgets; nothing happens when the service is not running
  (docs/parts/powerfx.md).
- Touchpad, three fingers: up opens Overview, down closes it or shows the desktop
  (`SwipeGestureHandler`, device type touchpad). KWin's own three-finger vertical swipe switches
  between rows of virtual desktops; the Fusion layout has one row. Hand check on the device.
  Since 2026-10-16 these are two of the gestures the settings page sets ("Touchpad gestures" at
  the end).
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

- `scenario-kwin2-a.sh` (1920x1200 at 4/3), 19 checks PASS on 2026-10-02, 30 since the T19
  checks (2026-10-13), 31 since a window out of full screen takes a half (2026-10-18,
  docs/parts/kwin-tablet.md):
  - flyout centre against the maximize button: compiled decoration right 1061.5 / 1061.25 and
    left 378.5 / 378.5, Aurorae `-Left` 378.5 / 378.5, Aurorae right 1061.5 / 1061.25;
  - switcher: hover selects, a resting pointer does not, click activates;
  - halves with the 6 px gap and the picker; M09 rows (top half, bottom half offered, bottom
    third 461 px of a 1406 px area); M14 every window inside the work area after rotating and
    back; T18 split in tablet posture (picker, two tiles without title bars, title bars back
    after leaving); T19 a window un-maximized in tablet posture takes a half without a title bar,
    and taken out of it floats without one (and gets it back on leave);
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
- Evidence: the KWIN-2 build run of 2026-09-30 (the maintainer's records).

### Not done

- The split divider handle (TABLET 4.10, P2): T18's "drag the divider" step has no handle; the
  two tiles still share their edge when one is resized by its border.
- Touchpad swipes cannot be produced in a private session: hand check at DEPLOY-1 (also that
  KWin's own three-finger vertical gesture does nothing visible with one desktop row). Since
  2026-10-16 a virtual touchpad on the test laptop's own session plays them ("Touchpad gestures",
  Verification).
- The 6 px strip between a snapped half and the picker shows the windows under it (as before).

## Touchpad gestures (2026-10-16)

The next queue's item 8 (the owner's list and defaults, 2026-10-16; board
`design/boards/Gestures.dc.html`): the snap script listens to six touchpad gestures, and the
Plasma Fusion settings page sets what each does (docs/parts/kcm-cpp.md, "Touchpad gestures").
Before, three fingers up opened Overview and down closed it or showed the desktop, fixed.

What KWin 6.7.5 leaves free (read in its v6.7.5 sources): it takes every touchpad swipe and pinch
with three or more fingers, whether or not a handler matches (`src/input.cpp` 1090-1131), and all
the handlers of a gesture's direction and finger count fire together (`src/gestures.cpp` 117-147).
Its own are four fingers up (Overview) and down (Overview's grid,
`plugins/overview/overvieweffect.cpp` 35-46), three and four fingers left and right (desktops,
`src/virtualdesktops.cpp` 806-809, which move only with more than one column of desktops), three
fingers up and down (the desktop row above or below, 810-821, only with more than one row) and a
three-finger pinch (Zoom, `plugins/zoom/zoom.cpp` 70-75, on by default). No setting turns them off.
So the script takes three fingers up, down, left and right and four fingers pinched in and spread
out; four-finger swipes and the three-finger pinch stay KWin's. Where KWin also uses one of the
six (three fingers sideways with several columns of desktops, up and down with several rows),
both happen: the settings page says so on the row, and its "Keep desktops in one row" leaves up
and down to the script.

- `contents/ui/Gestures.js` (pure, `packages/kwin/tests/gestures.test.js` in the build): each
  gesture's kwinrc key in `[Script-plasmafusion-snap]` (`GestureSwipeUp3`, `GestureSwipeDown3`,
  `GestureSwipeLeft3`, `GestureSwipeRight3`, `GesturePinchIn4`, `GesturePinchOut4`), handler type,
  direction, finger count and default; the nine actions in the settings page's order (`none`,
  `overview`, `desktop`, `grid`, `windows`, `launcher`, `quicksettings`, `notifications`,
  `snaplayouts`); a name it does not know (empty, a later version's, a typo) is the gesture's
  default, as on the page.
- `main.qml`: four `SwipeGestureHandler`s (three fingers, touchpad) and two
  `PinchGestureHandler`s (four fingers, contracting and expanding). A gesture reads its key with
  `KWin.readConfig` when it comes, from KWin's copy of kwinrc (KWin 6.7.5
  `src/scripting/scripting.cpp` 119-122), which a KWin reconfigure reads again
  (`src/workspace.cpp` 1014); the settings page asks for one after it writes the keys. It logs
  `plasmafusion-snap: gesture <key>: <action>` and runs the action:
  - Overview, Grid of desktops, All windows: KWin's shortcuts `Overview`, `Grid View` and
    `Expose` (kglobalaccel `invokeShortcut` on `/component/kwin`), each opening or closing it;
  - Show desktop: closes Overview when it is open, else shows or hides the desktop (as three
    fingers down did);
  - Launcher: plasmashell's `activateLauncherMenu`, as the Meta key;
  - Quick settings, Notifications: quick settings' `openRequest` (`toggle:<nonce>`,
    `notifications:<nonce>`), as its own keys hand it (docs/parts/shell-quicksettings.md); the
    widget on KWin's active screen acts on it;
  - Snap layouts: the Meta+Z flyout for the active window (or closes it).

  Overview, its grid and All windows do not start while another full-screen effect runs (KWin
  6.7.5 `effect/quickeffect.cpp` `QuickSceneEffect::startInternal`), and KWin's desktop switch is
  one (its slide, `plugins/slide/slide.cpp` 460 and 500, or fade). So when KWin also switches
  desktops with the gesture, the shortcut waits until the switch ends: the script asks KWin's
  active effects (`org.kde.kwin.Effects` `activeEffects`) every 100 ms while `slide` or
  `fadedesktop` is among them, 3 s at most (`Gestures.js` `desktopSwitching`). Without it, three
  fingers sideways set to All windows only switched the desktop on the test laptop (four desktops
  in a row, as the setup makes them). There is one wait at a time: a gesture that comes during it
  joins it, and when the switch ends each shortcut is invoked once, in the order the gestures
  came (review of #59: with a wait each, the first answer invoked the second gesture's shortcut,
  and the second answer did it again, toggling it back off, while the first was lost).

### Verification (2026-10-16)

- `packages/kwin/tests/gestures.test.js` (8 tests, in the build): the keys and defaults, the
  actions in the page's order, unknown and empty names, the shortcuts and quick settings' modes,
  the `openRequest` script, the desktop switch seen in a list or its text, main.qml's handlers
  (direction, finger count, key) and its shortcuts going to the wait. Each of six mutations
  (a shortcut, the case of a name, the request's key, a finger count, a handler's key, a default)
  fails it.
- The offscreen snap harness (`tests/offscreen/snap-geometry-harness.qml`, CI `build`; its
  stand-in `org.kde.kwin` has `PinchGestureHandler` and KWin 6.7.5's gesture enums, and its
  `DBusCall` logs each call's arguments): the built script's six handlers; three fingers left
  (All windows) asks KWin's effects and invokes nothing yet; three fingers right (the grid) during
  the wait joins it; while KWin slides nothing is invoked, it asks again 100 ms later, and after
  the switch All windows and then the grid are invoked, each once; a late answer invokes nothing;
  three fingers up (Overview) with no switch is invoked at once. With a wait each (the first
  head of #59) three of the checks fail.
- On the test laptop's own session (Fedora 44, KWin 6.7.5, four desktops in one row), with a
  virtual touchpad made through `/dev/uinput` that libinput 1.31.3 takes as a touchpad (three-
  and four-finger swipes and pinches, as `libinput debug-events` showed): the installed 0.5.0 snap
  script with this change's gesture code (`Gestures.js` and the gesture part of `main.qml`, the
  same text) put in `~/.local/share/kwin-wayland/scripts`, which KWin 6.7.5 reads before
  `kwin/scripts` (`src/scripting/scripting.cpp` 757-760). A changed script needs a path KWin has
  not loaded before: its QML engine keeps a file it compiled (the second and third runs, from the
  same path, ran the first one's code). With the defaults three fingers up opened Overview (no
  wait), down closed it, then showed the desktop and gave it back; four fingers pinched in opened
  and closed the launcher (`activateLauncherMenu`), spread out showed the desktop and gave it
  back. With the keys set as the page writes them: three fingers left (All windows) went to the
  next desktop and then opened All windows, the script having waited one check for KWin's slide;
  right (Grid of desktops) came back and opened the grid, the same; four fingers pinched in sent
  quick settings `toggle:<nonce>` twice, spread out `notifications:<nonce>`; up (Nothing) did
  nothing; down (Snap layouts) found no window to place. The machine was left as found (the
  script's keys deleted, the installed script loaded again, the first desktop current).

## Dynamic tiling (2026-11-12)

The per-workspace master-and-stack tiler (issue #115) lives inside `plasmafusion-placement`:
the writer takes exactly one provider, and the tiler IS that provider's policy consumer —
a separate package would need a fork-side per-window suppression seam the first slice
deliberately defers.

### How it works (Option A, the anchor approach)

- **Toggle on** ("Plasma Fusion: Tile Workspace"): the active window becomes the master, and
  the screen that is tiled is that window's own (`viewOutput`), not KWin's active screen:
  the active screen is where the window stood when it was activated, a window moved to
  another screen since (a script's move, a rule's) leaves it behind, and a tile made there
  admits no window of another screen (on hardware the press did nothing, 7). The master is
  admitted into the transient tile through `Workspace.transientTiling().createTile()` +
  `admitTile()` with the provider token; the workspace's other eligible windows become the
  stack, their pre-tiling floats saved, placed by direct `frameGeometry` writes in the
  endpoint-rounded column (the snap script's discipline: `Tiling.stackRects`). The window
  inside the admission call is already managed for the memory (`tiler.admitting`): the native
  admission can land it on the tile before `admitTile` returns, and a record there would put
  the tile into the memory and move the provider's revision under the admission. An
  admission refused as busy (3) or ineligible (7) may pass: the first is a released master
  whose record is being settled, the second a configure the client has not answered yet
  (an activation right before the shortcut, or the previous session's restore when the
  shortcut moves the tiling to another output). The tiler releases the tree and tries the
  same view again every 50 ms, at most 8 times; every other refusal, and the last attempt's,
  stands. Pressing the shortcut again drops a start that is still being retried. The native
  interface itself retries nothing.
  The native layer admits a window only from the place the memory has for its app
  (`NATIVE-TILING-CONTRACT.md`, the admission's steps 2 and 3), and the two differ whenever
  the app's last record was another window's: on hardware the master's app had opened a
  second window, that window was closed where it stood, and every later toggle on the master
  was refused (8) until the master moved. So the toggle first records the window's own
  floating frame as its app's place (`recordForAdmission`), by the memory's ordinary record
  and under its rules - nothing in the window's quiet second, nothing of a held, ignored or
  unsettled window. Not while another window of the app is open: the native layer refuses a
  key two windows share (8) and the memory stays as it is. And not a window that stands on
  the tile's own rectangle (an earlier release left it there; that is no floating placement).
  A window whose place the memory does not take is refused (8), as before.
  The master's frame is the tile's rectangle where the window reaches it. On a
  fractional-scale output most whole-pixel rectangles are off the pixels a frame can have,
  and the fork gives the window the tile's corner and the largest size it reaches inside the
  tile (`Window::transientTileFrame`); `masterWindowRect()` stays the tile's rectangle, so
  the stack column does not move.
- **Toggle off**: the stack windows return to their saved floats (see "A float given back
  too early" below); the master restores through
  the native explicit restore (the facade's `restoreWindow(master)` — Meta+Backspace's action
  for that window; the scripting `Workspace` has no slot for it, and a first version that
  called one threw on hardware and left the session stuck); the tree releases
  (`releaseTile`, whatever the restore did). The restore comes first because it restores an
  owned window only. The session is ended before the native layer is told, because the
  release reports the tree's end before it returns. The completion is asynchronous: the
  `transientRestorationCompleted` signal marks the boundary.
- **Native teardown**: the facade forwards `treeChanged`; a change with no live tree is
  session-end — the stack floats restore, the session clears. This covers master close,
  output removal, desktop removal, provider retirement, key conflict, a manual quick-tile or
  move of the master, and output transfer — every native path at once, for free. The
  controller keeps a tree whose window has left it; the facade ends that tree, which is what
  turns a release of the master into this signal. A release that is not the explicit restore
  (a removed desktop or output, a second window of the master's app, a move of the master,
  a re-check of the work area) is detach-only (`NT03-RESTORATION-SPEC.md`): the native layer
  leaves the master where the release left it, at the tile's size, and keeps its record, and
  while that record lasts Window Restore is consumed without a restoration and an admission
  of the window answers busy. The tiler ends it (`releaseMaster`, 2026-11-13; on hardware a
  removed desktop had left the master at the tile's size, refused by every later toggle
  until it closed). It asks the native layer to settle the record (`settleWindow(master,
  token)`) and acts on the answer:
  - nothing to settle (1): the explicit restore is returning the master and completes its
    record by itself, or the master closed. The tiler touches nothing.
  - neither on its floating frame nor placed by the user (4): the master goes back to its
    floating frame, as the stack does, by an ordinary request under the `placing` guard and
    the restore's quiet second. The frame is the native record's own
    (`floatingFrame(master)`, which follows the window to another output and off an
    unplugged one, and on an output of another scale has its size on that output's
    pixels), or the frame saved before the admission on a fork build without it;
    never one on a display that is gone (`Tiling.touchesScreen`).
  - not settled (3): the client has not answered a configure, the user is still moving or
    resizing the window, or it is maximized, full screen or quick-tiled. A master that still
    stands on its tile (`Tiling.onMasterTile`: the tile's corner, at the tile's size or the
    fit inside it) is returned at once, unless it is in the user's hand or in one of those
    modes.
  - settled (0): the frame the master stands on is recorded as its floating placement. The
    native layer settles only on the floating frame or where the user's own interactive move
    or resize left the window, so no automatic rectangle can be recorded.
  The question is asked again every 100 ms, at most 30 times. A record that has not settled
  by then is held (a maximized or full-screen master, a client that does not answer): the
  window's next geometry change asks again, and so do the end of a drag and a toggle on the
  window once it is in an ordinary state. Until its record is settled nothing of a released
  master is recorded, and a new session leaves it out of its stack. A released master that
  closes takes its entry along and records nothing (its native record ends with the
  window); the tiler never hands the facade a window that is closing or destroyed
  (`Tiling.alive`: a script's reference to a destroyed window is neither null nor falsy, and
  reads "not deleted"). The placement memory
  counts a window the tiler holds where it floats, not on its tile or cell (`siblings`), so
  a second window of the master's app is not restored onto the spot the master returns to.
  On a fork build without `settleWindow` the tiler leaves the master as before. When the
  script goes (disabled, reloaded) the tiler disconnects from the facade and from every
  released master it still holds: both outlive it.
  The window whose arrival ends the session is no member of it. The native layer has
  released the master by the time the script sees the app's second window, the tree's end
  follows in a queued call, and in between the session still reads active (`vacated`: the
  master has no tile; an owned master keeps its tile through full screen and back). On
  hardware that window was given a stack cell, lost it an instant later, stayed on the cell
  (next item) and was recorded there a second later, which also made every later toggle on
  the master fail. It keeps the place KWin gave it and records nothing when it opens: the
  app's place is the master's.
- **A float given back too early**: KWin applies a request for the size a window already has
  at once and sends no configure. A stack window that gets its float back while its cell's
  configure is still in flight (a second press of the shortcut a few milliseconds after the
  first, a native teardown right after a window joined) therefore has nothing on its way to
  the float: the client's answer to the cell lands afterwards, KWin takes it as the
  window's request, and the window stands on a cell no session owns - on hardware three
  times out of three, 15 ms between the presses. For five seconds after a float restore the
  tiler remembers the cell the window had last been given, and when that cell lands and
  KWin is not still asking for the float it asks for the float once more
  (`returnFromStaleCell`, `Tiling.staleCellLanding`): the sizes differ now, so the client is
  told. Once per window and restore; a window a new session manages, one in the user's hand
  or in a mode of its own is left alone.
- **Live**: new eligible windows on the tiled workspace join the stack (a window with a
  remembered placement keeps it as its saved float: the untoggle returns the app to its
  remembered spot, as the memory would have placed it); a window the stack
  cannot manage - not resizable, or a minimum size above the cell it would get - is handed
  back untouched (its remembered placement applies, and its own moves reach the placement
  memory); closed or minimized windows leave the layout and the column refills, a minimized
  one rejoining on restore with its pre-tiling float kept; a window that joins live keeps
  the settle pass: one second after it opens, the memory records its saved float (never the
  cell it sits at - invariant 7 keeps automatic rectangles out), so its next open has a
  placement even if the user never moves it, and the memory's ignore policy still decides
  whether anything is recorded (an ignored app's joined window records nothing, settle pass
  included); the provider's `record()` skips
  managed windows and the close of a managed window records nothing (invariant 7: automatic
  rectangles never enter placement memory), and the tiler's own float restores quiet the
  window for the restore's settling second, so a client's late commit of a cell cannot
  record as the float. The workspace is the desktop *and* the activity *and* the session's
  output: windows of another activity are not candidates even on a shared desktop, and a
  same-desktop window on another screen is not the session's to place (stacking order top
  first: KWin lists the bottom-most first, and the stack's first cell is the top-most
  window's).
- **Minimized-before members**: the workspace's minimized windows at toggle-on are
  members-to-be, not strangers: their floats are saved and they are watched from the start
  (restoring one during the session emits no `windowAdded` - it was there all along), so a
  restore rejoins the layout instead of floating over it (`Tiling.dormantCandidates`) - but
  a minimized window that is full-screen or manually tiled keeps that state through the
  restore, and a relayout never overwrites it, so those are strangers; the rejoin rechecks
  the eligibility for the same reason. A window that *arrives* already minimized while the
  session is live is the same member-to-be (`Tiling.eligibleDormant`, the one rule both
  paths read): it is watched on arrival - for it too, a later restore emits no
  `windowAdded` - with the remembered placement as its saved float, as for every new member.
- **Leavers stop being managed**: a member that moves to another desktop, activity or output
  during the session is detached (its `desktopsChanged`/`activitiesChanged`/`outputChanged`
  ends it): the session is per-workspace and per-screen, its cell belongs to the view it
  left, and the float is dropped so the untoggle cannot drag it back - the geometry it
  carries over is the user's own. A dormant member-to-be that moves away while minimized
  loses its saved float the same way: it never joined the layout, but the float described a
  view it left, and the untoggle must not drag it back there either.
- **A manual move of a stack window floats it**: the tiler never fights the user for a cell,
  for the memory's ignored apps as much as recorded ones (the tiler's membership decision
  runs before the memory's `IgnoreApps` guard - an ignored member's move by hand leaves the
  session too, or a later relayout would put it back in its cell over the move).
  The tiler's own writes are excluded twice - they run under a `placing` guard, and they land
  on the cell the layout assigned, to the output's pixel (`Tiling.isOwnCell`: the synchronous
  write and the client's late commit of it alike; off a scale of 1 KWin snaps the frame to
  device pixels and gives the client a whole logical size, so a 718 px cell lands as
  717.75 px at 133%; `Tiling.cellSlack` is how far a landed frame may be from its cell, and
  the largest over the outputs applies, since an X11 window lands on Xwayland's scale) -
  so anything else is the user's hand: the member is
  detached, the move is recorded as its floating placement, and the untoggle cannot write the
  saved float over it. The master is exempt (its manual teardown is native, and its maximize
  or full-screen frames are mode changes, not hands - reading them as moves collapsed the
  stack once; `cellRects` holds stack cells only, and the check is stack-members only).
- **One session at a time, on the workspace it was invoked on**: the controller holds one
  tree, the TileManager allows one transient root per desktop - this is the contract, not a
  limitation to hide. A toggle on another workspace ends the session there (its floats
  restore on that workspace) and lays out the current one, so the action never untoggles a
  desktop the user left behind. The workspace is the desktop *and* the activity *and* the
  output (`Tiling.sameView`, the session's one scoping rule): a toggle invoked while another
  screen is the active one tiles that screen - the same desktop on another output is not
  this session's view. The invocation's view is captured before the untoggle: the master's
  native restore raises and focuses the old master, which carries the active window and
  screen over to the old session's view, so `start()` lays out the captured view, not
  whatever the teardown left current, and the focus goes back to the window the shortcut was
  invoked on.
- **The divider follows the master**: the stack column's left edge is the master's placed
  right edge, read from the facade at every relayout (the tile is relative to the output's
  root, so the native layer rescales it when the geometry changes; a screens change also
  forces a relayout). A strut change that does not touch the screens heals at the next
  membership event.
- **Infeasible windows float**: a window whose minimum size exceeds its cell is left
  floating (the defined safe state), not squeezed or dropped - and it stops being managed:
  the tiler never wrote its geometry, its moves are placement memory again, and the untoggle
  does not drag it back to where it floated before the session. Feasibility is judged against
  the cells as they would be for the set being placed: the worst fit leaves first and the rest
  are re-tried in the larger cells (a 300 px column with minimum heights 100, 100 and 200 has
  no three-way cells, but the two that fit place once the tall window floats), and a window
  too wide for the column is never feasible at any count. The same holds when a later
  addition shrinks the column below a placed member's minimum: the member's saved float goes
  back before the detach (`Tiling.floatRestores` - it sat at a cell no untoggle could undo),
  where a window the layout never placed already sits at its own float. That reflow restore
  quiets the window for the restore's settling second, like the untoggle's: a late commit of
  the starved cell arriving after the member left the session must not record the cell as
  its floating placement.
- **Restored floats stay on a live screen**: an output that goes away takes its coordinates
  with it, and KWin has already evacuated such windows - the untoggle and the teardown
  restore a saved float only while it still lands on a screen the session has, so a stale
  absolute rectangle cannot drag a window offscreen over the evacuation.

### Shortcuts (sequence-less; the user assigns them)

| Name | Action |
|---|---|
| Plasma Fusion: Tile Workspace | toggle on/off |
| Plasma Fusion: Tile Focus Master | focus the master |
| Plasma Fusion: Tile Focus Next | next in the cycle (master → stack → master) |
| Plasma Fusion: Tile Focus Previous | previous in the cycle |

### Config (`kwinrc [Script-plasmafusion-placement]`)

The keys are flat (no nested group): `KWin.readConfig` reads the script's own kwinrc group
and nothing below it, so the KConfigXT group in `main.xml` stays empty and the KCM writes
where the script reads.

| Key | Type | Range | Default |
|---|---|---|---|
| `MasterFraction` | Double | 0.25–0.75 | 0.5 |
| `StackGap` | Int | 0–48 | 8 |

### The pure rules (`Tiling.js`)

The layout math lives in a `.pragma library` with node tests (`tiling.test.js`): the fraction
clamp, the endpoint-rounded stack column, the per-window feasibility check, the layout
separation (feasible placed, infeasible floated, the column re-filled between just the
feasible), the session structure, the focus cycle, the float save, the one workspace rule
(`onWorkspace` - the candidates, the managed windows and the leavers read it), the
minimized-before members (`dormantCandidates`, and `eligibleDormant` - the one rule the
toggle-on scan and the live add of an already-minimized window read), the reflow float
restores (`floatRestores`), the toggle's view comparison (`sameView`), the own-cell test
(`isOwnCell`), the released master's tile test (`onMasterTile`, with `tileFitShort` for how
far inside its tile a fit can be), the native answers the tiler asks again about
(`settleAgain`, `admitAgain`) and the screens a returned master may show on
(`touchesScreen`). The eligibility predicates (`eligibleForMaster`, `eligibleForStack`) mirror
the snap script's `usable()` guards and leave out a window that keeps itself off the taskbar
or the window switcher (`userWindow`: the XWayland Video Bridge's invisible window took a
stack cell on hardware). The QML path is covered too:
`tests/offscreen/tiling_lifecycle_test.py` loads this `main.qml` under the stand-in KWin
module with a mock `TransientTilingApi` and drives the native admission, the stack geometry
writes, the untoggle, the native teardown and a refused tree (see the Tests list). The mock
and the stand-in `Workspace` answer only what the compositor answers: a call the mock takes
and KWin does not is a failure only hardware shows.

### What it rides

Every native contract: the transient ownership (the master's floating-A guarantee), the
placement-memory suppression (invariant 7), the explicit restore (NT03.6), the completion
boundary (NT04), the command-intent matrix (NT05), the capture/replay filter (NT06A), the
context-release and transfer rebase (NT06). The tiler is the policy consumer the contract
names — it creates no geometry loops, writes no tree into kwinrc, and defers to native
quick-tile/manual precedence.

### Deliberately deferred

Runtime master-width adjust and full-width-master (the re-admission dance); swap
(release → settle → re-admit); multiple masters; simultaneous per-workspace sessions;
divider dragging; session memory across toggle/restart; X11 (the native layer refuses
admission); settings UI; auto-tiling rules; a separate tiler package.
