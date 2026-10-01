# Part: tablet-mode window and panel policy (`plasmafusion-tablet`, KWIN-1)

Status: built and tested in private sessions on the ThinkPad (see "Verification"); not deployed. The
lead built it directly (work package KWIN-1 of the 2026-09-30 one-pass plan). Last edited 2026-09-30.

Spec: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-tablet/TABLET.md` sections 3.1-3.6 and
4.2 with the review corrections, owner decision 2 (apps full screen without title bars, large dialogs
too; the dock hides over apps). The single owner of window policy and panel geometry in tablet
mode; plasmoids switch their own layouts from `FusionTablet`.

## Files

| File | What it is |
|---|---|
| `packages/kwin/scripts/plasmafusion-tablet/metadata.json` | KWin/Script, declarative, Id `plasmafusion-tablet`, not enabled by default |
| `packages/kwin/scripts/plasmafusion-tablet/contents/ui/main.qml` | the script |
| `packages/kwin/scripts/plasmafusion-tablet/contents/config/main.xml`, `contents/ui/config.ui` | settings (below) and their form in System Settings > Window Management > KWin Scripts |
| `tools/build.d/81-kwin-tablet.sh` | installs it into the stage with a copy of `FusionTablet.qml` (`tools/build-lib/shared-qml.sh`) |

`tools/device/fusion-config.sh` enables it (`kwinrc [Plugins] plasmafusion-tabletEnabled=true`, when the
package is installed); the login gate switches it off while another Global Theme is in use;
`fusion-restore.sh` gives the backed-up value back (DEVICE-1).

## Settings (`kwinrc [Script-plasmafusion-tablet]`)

| Key | Default | Meaning |
|---|---|---|
| `WindowMode` | `fullscreen` | `fullscreen`: apps maximized without title bars in tablet mode; `windowed`: windows left as they are (the compiled decoration gives touch-sized title bars) |
| `DockHiding` | `dodgewindows` | the dock in tablet mode: `dodgewindows` (hides over apps) or `none` (always visible) |
| `EdgeLeft`, `EdgeRight` | `false` | in tablet mode a swipe in from the left edge opens the launcher (`activateLauncherMenu`), from the right edge quick settings (its `openRequest` = `sheet:<ms>`) |
| `DisableWindowMove` | `false` | windows cannot be dragged in tablet mode |
| `InternalOutputs` | `eDP,LVDS,DSI` | name prefixes of built-in screens; window policy only while one of them is the only screen. Tests add `Virtual` (private sessions have virtual outputs only) |

Quick settings and the settings module write `WindowMode` / `DockHiding` with `kwriteconfig6 --notify`
and then invoke the shortcut "Plasma Fusion: Tablet Window Mode" (`org.kde.kglobalaccel
/component/kwin invokeShortcut`), which re-reads them and applies them. No KWin reconfigure is
needed.

## Behaviour

- **Posture**: `FusionTablet` (BASE-1) asks KWin's `org.kde.KWin.TabletModeManager` once and follows
  its signals. The script does nothing until KWin has answered, so the Kirigami value (which can start
  stale inside KWin, TABLET F3) never moves windows.
- **Panels, at once on every change**: one `evaluateScript` call in plasmashell (TABLET 3.6): the top bar
  `round(44 x text scale)` (the layout script's `textScale()`), the dock 80 (96 with the headroom frame until INT-1) and `DockHiding` (not the stock
  appmenu's `compactView`: see Verification). The laptop height and hiding are saved once per panel in
  its `[PlasmaFusion]` config (`laptopHeight`, `laptopHiding`, `tabletApplied`) and given back on leave
  (72 for the dock; a saved 88 or 96 from the headroom frame counts as 72).
  Panels the user added are never touched. When plasmashell's panel windows appear (a restart, a late
  start), the call is made again after 500 ms (one call for several panels).
- **Window policy, after 300 ms of stable posture** (flip bouncing), only with `WindowMode=fullscreen`
  and a built-in screen as the only screen: placement "Maximizing" and borderless maximized windows;
  every eligible window (normal, maximizable, not full screen, minimized, skip-taskbar, transient or
  modal, on the built-in screen) is maximized; tiled windows keep their tile and lose their title bar,
  and keep following `tileChanged` (a new tile: no title bar; untiled: the title bar back). New windows
  open maximized by placement; resizable dialogs and transients too (owner decision 2), fixed-size
  dialogs stay centred and framed.
- **Leave**: first, while borderless is still on, the windows this script maximized are
  un-maximized (KWin puts back their laptop geometry); windows first opened in tablet mode, dialogs
  included, get `setMaximize(false, false, rect)` with 70 % of the work area, centred (on the parent
  for dialogs); tiles get their title bar back; then the options are restored, and windows still
  maximized get their title bar back as `Workspace::slotReconfigure` does. Windows the user
  un-maximized in tablet mode are not touched. Focus, stacking, desktop, activity and minimized state
  never change.
- **Windowed by the user** (TOP-2, LEAD-1 resolution 11): the script follows `maximizedChanged` of the
  windows it follows. When the user un-maximizes one in tablet mode (the window card's Full screen
  switch, a shortcut), one event-loop turn later (a quick tile un-maximizes first and has its tile by
  then) the window leaves the script's lists, so leaving tablet mode does not touch it; a window first
  opened in tablet mode is placed at 70 % of the work area (it has no laptop geometry). KWin gives the
  title bar back itself. The next fold maximizes it again like any other window.
- **KWin reconfigure** reloads the options from kwinrc (also once about 0.2 s after every session
  start): the script sets them again inside the change handler (synchronously, so KWin does not give
  every maximized window its frame back); the reloaded values become the laptop values.
- **External monitor**: `screensChanged` re-runs the policy check, so window policy leaves when a
  second screen appears and comes back when it goes.
- **Kill switch**: disabling the script (`kwriteconfig6 --file kwinrc --group Plugins --key
  plasmafusion-tabletEnabled false`, then `qdbus6 org.kde.KWin /KWin reconfigure`) runs its leave step
  first, so the windows and options come back. When KWin itself quits (logout, `--replace`) nothing is
  restored: the scripts are destroyed after the workspace, and a leave step there crashed KWin at exit
  (found in QS-1's private sessions that ended in tablet mode; the script notes `aboutToQuit`).
- **Idle**: no timers except the 300 ms debounce and the 500 ms panel coalescing, both single-shot.

## Verification

Private sessions on the ThinkPad (1920 x 1200 at 4/3), `build/kt/` (scenarios `scen-kt1.sh`,
`scen-kt2.sh`, helper `pf-kt/kt.py`), the stage of HEAD plus this package installed with
`fusion-config.sh --install`; `InternalOutputs` includes `Virtual` there. Final runs `kt-1` and
`kt-2` (evidence `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build2/KWIN-1/`):

- T1: three windows at known geometries; tablet: all maximized without title bar, placement 9,
  borderless on, stacking and focus unchanged; leave: every frame geometry exactly as before (0 px),
  none without title bar or maximized, placement and borderless back, stacking and focus unchanged.
- T14: panels 44/96 drawn 34-39 ms after the switch, 34/88 31-46 ms after leaving (budget 100 ms);
  window policy follows after the 300 ms debounce, with KWin's 250 ms maximize animation.
- T4: a KWin reconfigure in tablet mode keeps placement 9, borderless and the windows' state.
- T3: plasmashell restarted in tablet mode: panels 44/96 within 5 ms of its name appearing (614 ms
  after the start); in laptop mode 34/88; `tabletApplied` consistent.
- T2: a window opened in tablet mode opens maximized without title bar; on leave it gets 70 % of the
  work area, centred, with its title bar.
- T17: KWrite's Open dialog (resizable) opens full screen without frame; after leave no window is
  without title bar or maximized.
- T18: two windows split left and right keep their tiles without title bars; on leave both get them
  back.
- Rotation in tablet mode (part of T19): maximized windows follow the portrait work area (within
  the device grid's 0.25 px). The rotation lock itself belongs to quick settings (QS-1) and the hand
  check H3.
- 20 fold/unfold cycles with 5 windows: 0 px drift, focus and stacking unchanged, no window without
  title bar; KWin's memory did not grow over 40 cycles (-76 kB over the second 20).
- Script load: KWin VmRSS +4 kB with the script loaded (budget 4 MiB).
- Kill switch in tablet mode: disabling the script gives the windows (title bars, not maximized),
  placement and borderless back.
- T16 (`kt-2`: the session starts with `[Input] TabletMode=on`, two windows open, then Plasma
  Fusion is installed, which enables the script): panels 44/96 within a few ms of the install
  finishing, both windows maximized without title bar, placement 9; after `TabletMode=off` the
  panels 34/88 and no window without title bar. The windows came back within 1.25 px of their
  frames from before the install (the install also changed the title bars from Breeze to Aurorae,
  which moves a frame onto the device grid differently).
- No core dumps with the final script. An earlier version switched the stock appmenu's
  `compactView` in the panel script, as TABLET 3.6 said: that crashed plasmashell twice in these
  sessions (SIGSEGV inside the scripting `writeConfig`, while the applet changed its representation
  during a layout update; stacks in the evidence), and after the crash restart the saved laptop
  height was the tablet one, so the top bar stayed 44 px in laptop mode. The panel script no longer
  touches the appmenu, and it never saves the tablet height as the laptop height (checked with mock
  panels, including a corrupted saved value).

Not covered in private sessions (hand checks): the real hinge switch and accelerometer, touch
gestures that need a physical screen size and the rotation lock (QS-1). The window card's Full screen
switch was tested with TOP-2 (`docs/parts/shell-topbar.md`, private session t2a: Konsole windowed with
its title bar, Dolphin still full screen, Konsole full screen again after the next fold).

## Needs from other parts

- QS-1 (done): quick settings accepts `openRequest` = `<mode>:<nonce>[:<output>]` with mode `sheet`
  (right edge) and `notifications` (Meta+N now writes `notifications:<ms>`); without an output only
  the widget on KWin's active screen opens. Its "Full-screen apps" toggle writes `WindowMode` and
  invokes the shortcut.
- The quick-settings keyboard policy (TABLET 3.3, `services/TabletPolicy.qml`) is QS-1's; the script does
  not start or stop the on-screen keyboard.
- DOCK-2: the tablet dock content fits the tablet panel (80 px plate; the script sets the thickness).
- TOP-1/TOP-2: a compact global menu in tablet mode (TABLET 4.3) comes from the top bar's width budget
  (the clock pill), which switches the stock appmenu only where Plasma 6.7.5 does not crash
  (`docs/parts/shell-topbar.md`, TOP-2).

## Split view divider (TABLET2 M1, 2026-10-01)

`contents/ui/SplitDivider.qml`. Two apps side by side (the window card's Split left / Split right, or
KWin's quick tiles) get a handle on the split, as on iPadOS:

- Shown while the window policy is applied (tablet posture, built-in screen only) and the active
  window is quick-tiled left or right with another visible window tiled on the other side (the
  topmost one in the stacking order, same output and desktop).
- A 48 x 128 px touch target centred on the split (the left tile's right edge) and on the work
  area's height, drawing a 6 x 64 px white pill (8 x 80 while dragged). It is an internal KWin window
  (KWin's internal-window filter gives it touch), created by an `Instantiator` (with an Item as visual
  parent the script's windows are never shown), titled `plasmafusion-split-divider` and marked
  skip-taskbar, -switcher and -pager when KWin adds it (KWin lists it as a normal window otherwise).
- Dragging resizes live, at most every 50 ms, within 20-80 %: `Tile.resizeByPixels` on the left
  quick tile; KWin's quick-tile root moves the shared split, so the right window follows.
- On release it snaps to 1/3, 1/2 or 2/3 of the work area (portrait: 1/2), skipping a split that
  would make either window narrower than its minimum size (`Window.minSize`). Released in the outer
  12 % it ends the split: the window on that side is minimized (not closed) and the other maximized.

Test (private session, 1920x1200 at 4/3, `build/m1/scen-m1a.sh`, m1f; evidence
`artifacts/plasma-fusion/2026-10-01-tablet2/M1/`): Konsole tiled left and Dolphin right (711 | 711 px);
a drag to 69 % snaps to 2/3 (951 | 471), to 28 % to 1/3 (471 | 951), to 97 % minimizes Dolphin and
maximizes Konsole (1440 x 836); the handle window is skip-taskbar and skip-switcher.

## Tent posture keeps the dock visible (TABLET2 N2/N9, 2026-10-01)

In tent posture the display is upside down and its logical bottom edge rests on the table, so no
bottom swipe can bring the dock. Scripts cannot see an output's rotation, plasmashell can: the dock
(`tentPosture`: tablet posture and `Screen.orientation` inverted landscape) writes the runtime key
`kwinrc [Script-plasmafusion-tablet] TentPosture` after the rotation has been stable for 1 s, and
invokes "Plasma Fusion: Tablet Window Mode"; while it is true `dockHiding()` returns `none` (the dock
stays visible and reserves its space, maximized apps end above it). The first decision after
plasmashell starts is always written, so a value left by a session that ended in tent posture is
cleared. Test (`build/n9/scen-n9.sh`, n9a): Konsole maximized 836 px tall; screen inverted:
TentPosture true, dock `none`, Konsole 756 px; normal again: false, `dodgewindows`, 836 px.

## Pixel grid for the tablet panels (2026-10-01)

Research H-hidpi 3.6 (shell sizes on whole device pixels), owner OK. The panel script snaps the tablet
heights to the smallest value at or above them that is a whole number of device pixels at the
built-in screen's scale (`internalScale()`, KWin's `devicePixelRatio`): top bar 44 -> 45 (60 px at
4/3), dock 80 -> 81 (108 px), and the dock's bottom strip 20 -> 21 (28 px), handed to the dock as its
config `tabletStripHeight` because plasmashell's QML only sees Wayland's rounded integer scale (2).
At 1.25, 1.5 and 2 the sizes stay; laptop sizes are unchanged. Result at 4/3 (session grid1): top 45,
strip 879+21, a maximized app 45+834 = 1112 device px (was 44 + 836 = 58.67 and 1114.67); laptop
34/72 restored. The drawn 1 px edge line of the bar was already crisp before (Qt snaps it); the change
removes the fractional panel slot and puts the app area on whole pixels.

Scale changes at run time (Display Configuration, `kscreen-doctor ... scale`) keep the screen list, so
`onScreensChanged` does not run: each screen's `scaleChanged` (an `Instantiator` over
`Workspace.screens`) restarts a 400 ms timer that applies the panels again. Found by STRESS-1
(2026-10-01): before, a scale change in tablet posture left 45/81/21 at every scale (the dock at
112.8 logical px at 1.25/1.5/1.75); now 44/80/20 at 1, 1.25, 1.5, 1.75 and 2, 45/81/21 at 4/3,
laptop 34/72 unchanged (session st-fix).
