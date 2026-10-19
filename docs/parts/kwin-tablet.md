# Part: tablet-mode window and panel policy (`plasmafusion-tablet`, KWIN-1)

Status: built and tested in private sessions on the ThinkPad (see "Verification"); not deployed. The
lead built it directly (work package KWIN-1 of the 2026-09-30 one-pass plan). Last edited 2026-10-13.

Spec: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-tablet/TABLET.md` sections 3.1-3.6 and
4.2 with the review corrections, owner decision 2 (apps full screen without title bars, large dialogs
too; the dock hides over apps). The single owner of window policy and panel geometry in tablet
mode; plasmoids switch their own layouts from `FusionTablet`.

## Files

| File | What it is |
|---|---|
| `packages/kwin/scripts/plasmafusion-tablet/metadata.json` | KWin/Script, declarative, Id `plasmafusion-tablet`, not enabled by default |
| `packages/kwin/scripts/plasmafusion-tablet/contents/ui/main.qml` | the script |
| `packages/kwin/scripts/plasmafusion-tablet/contents/ui/Panels.js` | the panel script it runs in plasmashell, and when it asks again (tested by `packages/kwin/tests/tablet-panels.test.js` against a model of desktop scripting) |
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
| `EdgeLeft`, `EdgeRight` | `false` | in tablet mode a swipe in from the left edge opens the launcher (`activateLauncherMenu`), from the right edge quick settings (its `openRequest` = `sheet:<ms>:<output>`, the output being the built-in screen, which is the touch screen, else KWin's active one: `contents/ui/Requests.js`, tested by `packages/kwin/tests/tablet-requests.test.js`; before 0.5.0 without the output, so the widget on the screen of the pointer or focus opened, and every one when KWin did not answer) |
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
- **Panels, at once on every change**: one `evaluateScript` call in plasmashell (TABLET 3.6): the
  top bar `round(44 x text scale)` (the layout script's `textScale()`), the dock 80 (96 with the
  headroom frame until INT-1) and `DockHiding` (not the stock appmenu's `compactView`: see
  Verification). The laptop height and hiding are saved once per panel in its `[PlasmaFusion]`
  config (`laptopHeight`, `laptopHiding`, `tabletApplied`) and given back on leave (for the dock the
  plate of its size, the dock's `dockSize`: 60, 72 or 78 px, 72 when not set, since 2026-10-16; a
  saved 88 or 96 from the headroom frame counts as that plate). The settings page's Dock size sets
  `laptopHeight` while the posture holds (docs/parts/kcm-cpp.md, "Dock size and window grouping");
  `tests/tablet-panels.test.js` covers both. A dock on the left or right (the settings page's Dock
  position, board DockPosition.dc.html) is at the bottom in tablet posture, as on the Tablet board:
  its side is saved as `laptopLocation` with the height and given back on leave (2026-10-16; the
  test covers a dock on the left, one at the bottom and one without a saved side). A top bar that
  hides (the settings page's "Hide the top bar automatically", board Island.dc.html) always shows in
  tablet posture: its `laptopHiding`, saved with the height, is given back on leave (2026-10-17; the
  test covers a bar that hides, one that shows and one set to hide while the posture held). In
  laptop posture a top bar takes the settings page's choice, plasmafusionrc `[TopBar] AutoHide`
  (true: `autohide`, false: `none`; not set: left as it is), so a bar whose screen was not connected
  when the choice changed gets it when its window appears (the test: a returned screen's bar, tablet
  posture, off, not set). A top bar is a panel with the app name, the clock pill or quick settings,
  the settings page's test (a bar with the app name alone too, since 2026-10-17). Panels the user
  added are never touched. When plasmashell's panel windows appear (a restart, a late start), the
  call is made again after 500 ms (one call for several panels). A Fusion panel whose screen is gone
  (the top bar of a monitor that was unplugged) is skipped, see "Panels without a screen" below.
  When plasmashell is not on the bus, or answers "not ready" (no panels, desktops or screens yet),
  the call is made again after 1, 2, 4, 8, 16 and 32 s.
- **Window policy, after 300 ms of stable posture** (flip bouncing), only with `WindowMode=fullscreen`
  and a built-in screen as the only screen: placement "Maximizing" and borderless maximized windows;
  every eligible window (normal, maximizable, not full screen, minimized, skip-taskbar, transient or
  modal, on the built-in screen) is maximized; tiled windows keep their tile and lose their title bar,
  and keep following `tileChanged`: a new tile loses the title bar, and an untiled window floats
  without one (recorded like a window the user un-maximized, so leave() gives the bar back). A title
  bar the user removed themselves (a no-titlebar rule) is never claimed: `enter()` snapshots each
  window's state before the policy runs (a window opened later is snapshotted when it appears) and
  leave() restores only bars the policy took. KWin does not expose window rules to scripts
  (`Window`'s scriptable properties have `noBorder`, not the rules), so a window that appears while
  maximized without a title bar is taken at its word, the user's: an ordinary app opened that way
  and un-maximized in tablet posture keeps no title bar after leave() until its next maximize. New
  windows
  open maximized by placement; resizable dialogs and transients too (owner decision 2), fixed-size
  dialogs stay centred and framed. Placement skips a window that comes with its own position (an X11
  app with position hints, such as Chrome restoring its last window): 200 ms after it appears, an
  eligible window that is neither maximized nor tiled and can grow to the work area is maximized like
  the windows at enter ("maximized on open" in the log) and gets its own geometry back on leave
  (ThinkPad private session 2026-10-02: xmessage -geometry 600x400+0+0 maximized, 600x450 in
  laptop posture, maximized again; KWrite still maximized by placement alone).
- **Leave**: first, while borderless is still on, the windows this script maximized are
  un-maximized (KWin puts back their laptop geometry); windows first opened in tablet mode, dialogs
  included, get `setMaximize(false, false, rect)` with 70 % of the work area, centred (on the parent
  for dialogs); tiles get their title bar back; then the options are restored, and windows still
  maximized get their title bar back as `Workspace::slotReconfigure` does. A window the user
  un-maximized in tablet mode keeps its size and place and gets its title bar back too (the script
  removed it in tablet posture). Focus, stacking, desktop, activity and minimized state never change.
- **Windowed by the user** (TOP-2, LEAD-1 resolution 11; no title bar since 2026-10-13): the script
  follows `maximizedChanged` of the windows it follows. When the user un-maximizes one in tablet mode
  (the window card's Full screen switch, a shortcut), one event-loop turn later (a quick tile
  un-maximizes first and has its tile by then) the window leaves the script's lists, so leaving
  tablet mode does not touch its size or place; a window first opened in tablet mode is placed at
  70 % of the work area (it has no laptop geometry). It keeps no title bar: in tablet posture the
  appname pill is the window's title bar and menu (owner decision 2026-10-13, KWIN-2 T19), so
  `settleUnmaximized` removes the frame KWin gave back on the un-maximize (remembered in
  `borderlessFloating`) and the leave step gives it back with the tiles'. The next fold maximizes it
  again like any other window. Since 2026-10-18 such a window takes a half instead (below, "Full
  screen off takes a half"); it floats like this only when it is wider than a half at its minimum
  size, or when it leaves its tile.
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
- T19 (2026-10-13): a maximized window the user un-maximizes in tablet posture (the window card's
  Full screen switch) keeps no title bar; on leave it gets it back. `scenario-kwin2-a.sh`
  un-maximizes a maximized window in tablet posture and checks `noBorder` stays set, and the T18
  leave check covers the way back; the previous script fails the check (the window has its frame
  again).
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

## Split divider: swap, and showing up after a split (2026-10-01, SPLIT.md item 3)

- **Double tap swaps the two apps** (Android, One UI): `swap()` moves each window into the other's
  quick tile (`Tile.manage`); the split stays where it is (moved to the middle first when an app
  would not fit its new side, `minSize`); the app that comes to the left is activated. Log "split
  divider: swapped, <left> left, <right> right".
- **The handle appears as soon as the split exists.** `refresh()` ran on window activation, but every
  split path activates the window first and tiles it a moment later (the window card, the dock's split
  drag, the quick-tile keys), so the handle came only at the next focus change. It now also refreshes
  when the active window's tile changes.
- Test (6.7.5 and 6.7.91 containers, swap6/swap68; `InternalOutputs=eDP,LVDS,DSI,Virtual` so the
  virtual output counts as built in): KWrite quick-tiled left, Konsole right -> handle shown; double
  tap on it -> Konsole 6+711 (left), KWrite 723+711 (right).

## A split pair in the app switcher (2026-10-02, SPLIT.md item 4)

The navigation effect (`packages/navigation-cpp`, 0.1-7; details in its README) shows the two apps
of a split as one card, as Android's Overview does. Its sides are this script's test
(`splitside.cpp` is the C++ copy of `isLeft`/`isRight`); the pairs are the apps seen side by side,
layer by layer (every split on the screen, also one under another app), and among minimized apps
only the pairs the switcher minimized as one card (minimized apps keep their tiles). The card
shows both in their split ratio; picking it, a sideways swipe to it and a gesture that returns to
it bring both back into their tiles, so this script's handle comes back with them; closing it
closes both. After the home gesture, activating either app again in tablet posture (the dock, a
notification) restores the other into its half, unless another app is shown there (the dock's
split drag). An app alone in a tile picked from its own card fills the screen. Test: 6.7.5
container, sessions pair5 and lone2, and the review fixes' fx-* sessions (evidence
`artifacts/plasma-fusion/2026-10-01-tablet2/split-pair/`).

## Keeping the dock over apps (SPLIT.md item 6)

The option is the settings module's "Dock in tablet mode: Hide over apps / Always show"
(`DockHiding` above; `docs/parts/kcm-cpp.md`), default "Hide over apps". Test (6.7.5 container,
session dock1, the keys written as the settings module writes them, then the shortcut): KWrite
full screen 45+834 with the dock hidden; "Always show": the dock shown and KWrite 45+753, still
shown after a tap in the app and after a short swipe up; KWrite and Konsole split above it
(742 px tall); "Hide over apps" again: the dock hidden, the tiles 822 px tall.

## Panels without a screen (0.5.0)

Found on Plasma 6.7.91 (6.8 beta, VM 7, 2026-10-11): plasmashell crashed at every session start,
three times or more until systemd gave up (SIGSEGV in `KConfigGroup::config` <-
`KConfigGroup::readEntry<int>` <- `WorkspaceScripting::Panel::height` <-
`ShellCorona::evaluateScript`), with "plasmafusion-tablet: panels: plasmashell did not run the panel
script" in the journal. The layout had a Plasma Fusion top bar of a second screen that was no longer
connected. A scripting `Panel` reads its sizes from the panel's window, or without one from
`PanelView::panelConfig()` / `panelConfigDefaults()` for its screen; for a screen that is not in
the screen pool these return an invalid `KConfigGroup`, and reading it dereferences a null pointer
(`Panel::panelConfig` checks `screenOrder().size() < screenNum` where `<=` was meant, and never
checks the screen). Plasma 6.8 keeps a panel on its last screen (libplasma: `Containment::screen()`
is the last screen, unsigned), so `p.screen` is 1 with one screen; Plasma 6.7 reports such a panel
on screen -1 and the scripting falls back to screen 0, which is why 6.7.5 never crashed. Every
Plasma Fusion release with this panel script (0.4.0 included) crashes this way on 6.8 once a
second screen with a top bar was unplugged: the script runs when the shell's panel windows appear.

The panel script now reads and writes a panel's height and hiding only while
`p.screen >= 0 && p.screen < screenCount`; other panels are counted ("1 without a screen skipped")
and get their posture when their screen comes back (their window appears and the script runs
again). The other scripts that read panel sizes get the same rule: the settings module's state
read and look change (`p.opacity`), and `fusion-config.sh`'s layout check, top-bar ids and bar
thickness (`lengthMode`, `floating`, `height`; on 6.8 the crash made the layout check answer "no",
and an automatic setup would then have reset the layout). The panel script also waits for the
shell: no panels, desktops or screens yet is "not ready", and that answer or a failed call is
retried with a growing delay (`Panels.retryDelay`).

Tests: `packages/kwin/tests/tablet-panels.test.js` (in `81-kwin-tablet.sh`) runs the panel script
against a model of desktop scripting with 6.8's and 6.7's behaviour, a model panel crashing on
the reads plasmashell crashes on; the panel script of 8cf0b3d fails it ("plasmashell crashed: panel
3 height on missing screen 1"). `tools/tests/shell-vm/shell_starts.py` (run inside the session)
adds such a bar when there is none, restarts plasmashell six times in laptop and tablet posture,
triggering the script while the shell starts, and checks for core dumps, the script's answer and
the bars' heights: on VM 7 with 8cf0b3d 8 checks failed in 4 rounds (12 plasmashell cores), with
this change all 19 passed; five log-out and automatic log-in cycles gave 0 cores (the log shows
the retries: "did not run the panel script (not running?), again in 1 s", "has not loaded its
panels yet, again in 2 s", then "top 34, dock 72 dodgewindows, 1 without a screen skipped"). On
VM 5 (Plasma 6.7.5) 8cf0b3d did not crash (the bar is on screen -1 there) but gave the bar without
a screen the tablet height too; with this change all 19 checks passed. A new script reaches a
running KWin only with a new session: KWin keeps the compiled QML of a script it unloads and
loads again from the same path.

## The top bar for the island (2026-10-17)

Board `design/boards/Island.dc.html`: while a top bar is hidden, the live chips of its screen show
the island (docs/parts/shell-livechips.md, "The island"). Plasma hides an auto-hide panel through
KWin: plasmashell asks for an auto-hide screen edge and KWin hides the panel's window until the
pointer touches the edge (KWin 6.7.5 `LayerShellV1Window::reserveScreenEdge`, `Window::setHidden`).
Plasmashell tells its widgets nothing about it (plasma-workspace 6.7.5 `PanelView` has no such
property), but KWin's scripts see the window's `hidden`.

- `contents/ui/TopBar.js`: `isTopBar()` (a plasmashell panel window along the whole top of its
  output; the dock and the island are not) and `barScript()`, the plasmashell script that writes the
  live chips' `[General] barHidden` for every panel on a screen: true while the bar of its screen
  (matched by the screen's corner, `screenGeometry()`) is hidden and the chips' own panel hides.
  KWin sees no widgets, so another full-width top panel on the screen is a bar too: a screen's bar
  is hidden while any of its top panel windows is (`barState()`), and a panel that does not hide is
  never hidden. It writes only what changes and skips panels of a screen that is gone.
- `main.qml` follows plasmashell's panel windows (at start, and as they appear), their `hidden`,
  geometry and output; which of them are top bars is decided by their geometry each time
  (`TopBar.barsOf()`: a panel moved to another edge or made narrower is no bar any more); the state
  goes to plasmashell when it changes (one call for changes in the same turn of the event loop) and
  again when its panels appear (a shell restart). When the script is turned off (the kill switch),
  it sends that no bar is hidden as it goes, so no island is left (the chips keep `barHidden` in
  their config). The log: `plasmafusion-tablet: top bars [{"x":0,"y":0,"hidden":true}]: island: 1
  widgets, 1 changed, islands at 0,0` (the screens whose island is there: a hidden bar with the
  live chips).
- Plasma's own pop-up (the volume, the brightness and the rest; docs/parts/shell-livechips.md,
  "Plasma's notices"): plasmashell's on-screen-display window (`TopBar.isPlasmaOsd()`: the
  `onScreenDisplay` window of plasmashell, the onscreendisplay role of plasma-workspace 6.7.5
  shell/osdwindow.cpp) is a new window each time it shows, on the screen KWin puts it on (its active
  output, `Placement::placeOnScreenDisplay`). When it comes up on a screen whose island is there,
  the script makes it transparent (`opacity` 0) and asks that screen's live chips to show the notice
  (`TopBar.noticeScript()`: `[General] noticeRequest` with a new value, for the chips of that
  screen only); elsewhere it stays as it is (`TopBar.osdOpacity()`). A pop-up already up when a bar
  starts hiding (or the script starts) keeps showing until Plasma closes it, as its notice is not
  the island's to show; one on a screen whose bar shows again gets its opacity back, and turned
  off, the script gives every pop-up it knows its opacity back. KWin's scripts have no
  signal for the active output (6.7.5 `WorkspaceWrapper`), and none is needed: the window says where
  the notice is. The line for each (`Plasma's pop-up on 0,0: in the island`) is debug output (the
  qml category), as it comes with every key press.
- `tests/tablet-topbar.test.js` (in the build): which windows are top bars (the dock, a dock on the
  left, a window at the top, another output's bar, another app's are not), the state in a fixed
  order, and the script against a model of desktop scripting: the laptop's bar hidden and the
  monitor's shown, nothing written again, both changed, every island gone when no bar window is
  known, a value written as text, a panel of a screen that is gone skipped; the screens whose island
  is there (none for a hidden bar without the live chips), a screen's corner, Plasma's pop-up told
  from the island and other windows, what becomes of a pop-up that comes up, one already up and one
  elsewhere, and the notice request reaching only the chips of its screen. Reversing the hidden
  value, dropping the screen check, writing on every call, not listing the islands or asking every
  screen's chips fails it.

## Full screen off takes a half (2026-10-18)

Board `design/boards/TabletSnap.dc.html` ("A place for every window"), owner decision 2026-10-18:
in tablet posture an app is full screen or in a half, never left floating where a finger cannot
move it (a window without a title bar there has nothing to hold; the window card's buttons were the
only way to move it). The tablets of 2025-2026 snap a window as the result of a gesture and then
offer what fills the rest (research: `artifacts/plasma-fusion/2026-10-18-tablet-autosnap/`).

- With apps full screen (`WindowMode` fullscreen, the window policy applied), a window the user
  un-maximizes (the window card's Full screen switch, a shortcut) takes a side in
  `settleUnmaximized`, through KWin's quick tile (`Workspace.slotWindowQuickTileLeft/Right`, the
  window made active first). `contents/ui/Snap.js` decides: `occupiedTiles()` takes the quick
  tiles of the other windows shown with it (its screen, the current desktop and activity; an empty
  activity list is every activity, as in the snap script; not minimized), and `placeFor()` the
  free side (the split divider's test of a left or right tile), the right one when both are free
  or both taken, with the share of the work area that side has now: what the other window leaves
  (the divider's 1/3 or 2/3 included), the right tile's when both are taken. With nothing else
  shown the window takes the right half and the split goes back to the middle (`centreSplit()`,
  by the left half's edge as the divider moves it): KWin keeps a split moved earlier while a
  minimized window holds the other tile. The split, its divider and the other side's pickers (the
  home screen's apps, "Pick a window for this side") then work as for any split, and
  `tileChanged()` takes the title bar as for every tile. The log: `windowed by the user:
  org.kde.dolphin, to the right (50 %, the split in the middle)`, `... to the right (33 %)`.
- A window wider than its side at its minimum size (`minSize.width` over the side's width less
  8 px) floats as before (`windowed by the user: ... (wider than its side)`). In the windowed mode
  the policy is off and windows float; the window pill's drag moves them
  (docs/parts/shell-topbar.md).
- A window maximized again forgets the tile record as it forgets the floating one, so leaving
  tablet posture does not give a maximized window a title bar under the laptop's borderless
  setting (found by T19's maximized-again case once the un-maximized window took a half).

Tests: `packages/kwin/tests/tablet-snap.test.js` (node, in `81-kwin-tablet.sh`): `placeFor()` with
nothing tiled, the other side free on either side, the divider's 1/3 and 2/3 on either side (the
share that side has), both taken, tiles that are not a side (a top half, a quarter), minimum
widths over and at a half, a third and two thirds; `occupiedTiles()` with the window itself,
another activity, screen or desktop, a minimized, a non-normal, a closing and an untiled window
(none count), a window on every desktop, on this activity among others or on every activity (they
count), and the case of a right tile here and a left one on another activity (the left side is
free). `tests/vsession/scenario-fullscreen-off.sh` (private session on the ThinkPad, 1440 x 900,
the window card's switch tapped with pfinput; 2026-10-18, fo-5): all 13 checks pass - Dolphin
alone takes the right half (723, 717) without a title bar and the home screen offers the apps in
the left half; beside KWrite on the left it takes the right half, beside KWrite on the right the
left; beside KWrite in the left two thirds the right third (963, 477; its minimum width 173 fits);
with KWrite sent home (its tile and the split kept), the right half with the split in the middle;
in laptop posture an un-maximized Dolphin is not tiled. With main's script (fo-r1) the snap checks
fail: Dolphin floats at 216, 1008 px wide (70 %); with the first version of this change (6c5f570,
fo-r3) the last case fails: Dolphin got the third the split left (963, 477). `scenario-kwin2-a.sh`
(1920 x 1200 at 4/3, k2a-2): 31 checks pass, T19 now checking that the un-maximized window takes a
half without a title bar, then that it floats without one once taken out of its half; on the first
run with the snap (k2a-1) the maximized-again case failed (a title bar on a maximized window after
leave), fixed as above.

## Windows opened in tablet posture get their title bar back (2026-10-18)

A window opened in tablet posture appears maximized (placement "Maximizing"), and KWin makes a
maximized window borderless while the policy's option is on (`borderlessMaximizedWindows`: KWin
6.7.5 `XdgToplevelWindow::maximize` sets `noBorder` with the maximize, and clears it on the
un-maximize). `follow()`'s decoration handler recorded that first borderless state as the user's,
as KWin gives scripts no window rules to tell a no-titlebar rule from the option, so once such a
window was un-maximized or tiled in tablet posture, `leave()` never gave its title bar back: after
tablet posture it had none (found with the snap above; main did the same, fo-r1, "tiles with
title bar 0, floated with title bar 0").

The script now notes the windows that appear while the policy runs (`appearedInTablet`). When KWin
shows such a window's title bar again (the un-maximize under the option, a quick tile out of
maximized: `barShownAgain()` in `settleUnmaximized()` and `tileChanged()`), nothing forces it
borderless, so the bar is the policy's: taken while the posture holds and given back by
`leave()`. Windows open before tablet posture keep their snapshot from `enter()`.

Leaving tablet posture un-maximizes the windows the policy maximized and those opened in it while
the option is still on, and KWin gives every one its title bar on that un-maximize (6.7.5 and
6.8.0 `XdgToplevelWindow::maximize`: `setNoBorder(false)`). `leave()` makes a window whose missing
bar is the user's borderless again: one borderless before tablet posture (the snapshot of
`enter()`), or one opened in it that the user's rules keep without a bar (below). Before, a window
left maximized until tablet posture ended got a title bar against its rule or the user's choice.
The last step of `leave()`, which gives the windows still maximized their title bar when the
laptop's option is off, skips these. A window's `maximizeMode` is the mode its client has taken,
so a window just un-maximized still reads 3 until the client answers; the first version of this
gave the bar back there (tb-7: "kept without title bar 2", then both with one).

A no-titlebar rule that acts only when the window appears ("apply initially") does not stop KWin
from showing the bar on that un-maximize, so the user's rules are read too, and a window one of
them keeps without a title bar stays the user's (`Rules.js`):

- **Where:** `kwinrulesrc` as KWin's KConfig reads it (`RuleBookSettings`): the user's file, then
  those of the XDG config directories (`~/.config/kdedefaults`, `/etc/xdg`), a key in an earlier
  file hiding the same key in the later ones. One QtCore `Settings` per file
  (`StandardPaths.standardLocations`), read again at each decision, and only read: the objects
  declare no properties, since `Settings` stores every property declared on it in its file (the
  first version of this, an `Instantiator` delegate's `modelData`, wrote
  `modelData=@Variant(...)` into the user's rules and created the file in `~/.config/kdedefaults`;
  KConfig then warned "Invalid escape sequence").
- **Locks:** QtCore `Settings` drops KConfig's marks of an immutable file or group (`[$i]`), with
  which an administrator's rule wins over the user's file (it keeps a locked key's mark in the
  key's name, `noborder[$i]`, which is read too). So the rules of each system file also count on
  their own: a locked rule is never missed, and a user's own change to a system rule may be (the
  window then keeps no title bar after tablet posture, as before this change).
- **Which rules:** those that are on (`Enabled`, default true: `Rules::match()` skips the others),
  in KWin's precedence (`WindowRules::checkNoBorder` and `checkDecorationPolicy`, `CHECK_RULE` in
  6.7.5 and 6.8.0): of the rules that match the window, in their order, the first that names the
  title bar decides, also one that leaves it alone ("don't affect" stops the walk too). It keeps
  the window without a title bar when it sets `noborder` with a rule type that sets it, 2 to 6 (a
  KConfig Bool: anything but false, no, off or 0), or, without `noborder`, one of 6.8's decoration
  policies without a title bar, `none` and `shadow` ("Only shadow"; KConfig's enum takes the value
  in any case or the number, 0 and 3; 6.8 migrates `noborder` over the policy). A rule this
  cannot be sure of decides only when it removes the bar, and one that keeps the bar is passed
  over in case it does not apply: a rule with conditions other than the class (window types, role,
  title, machine, tag, having a parent), a pattern the matcher cannot read, or only 6.8's policy
  (which 6.7.5 does not read).
- **Which windows:** the class matched as KWin's `Rules::matchWMClass` does (6.7.5 and 6.8.0:
  exact and substring matching too are case-sensitive). A regular expression is matched by
  QRegularExpression, as KWin matches it (`RuleRegex.qml`). Qt 6.11's JavaScript reads some PCRE
  without an error but differently: `\A` as `A`, `[[:alpha:]]` as a class and a `]`, `x{,3}` as
  text where PCRE2 10.43 reads a quantifier, `\w` and `\s` beyond ASCII. But a `RegExp` handed to a
  `RegularExpressionValidator` becomes a QRegularExpression with its source unchanged (and its `i`
  and `m` flags as options; a leading `(?i)` or `(?m)` becomes one). A pattern Qt's JavaScript
  cannot read at all (lookbehind, possessive quantifiers, other inline options, parentheses that
  do not pair up on their own) is taken as applying, to every window: with such a rule the policy
  claims no title bar and leaves the windows as before this change. The rules' other conditions
  are not checked: such a rule counts when it removes the bar and is passed over when it keeps it
  (above), so the user's bar is never claimed by mistake.

A window under an apply-initially "Only shadow" rule keeps no title bar, but not its shadow-only
style, until it opens again: KWin's borderless maximize already replaced its policy with none
(6.8.0 `Window::setNoBorder`), and a script can set only `noBorder` (none, or the client's
preference).

Tests:

- `packages/kwin/tests/tablet-rules.test.js` (node, in `81-kwin-tablet.sh`):
  - the rules file as QtCore `Settings` reads it (the `[General]` keys at the top level, a comma
    list as a list or as one string): an apply-initially substring rule, a forced exact one, a rule
    that only sets the opacity, an empty file;
  - KConfig's cascade: a system-wide rule, a user's key hiding the system's, a system group the
    user's list names, a user's list without it; a locked key's name; a system rule the user's
    file turns off still counting on its own;
  - the rule types that set the property and those that do not; rules that are off; KConfig's
    Bool; 6.8's decoration policies by value and by number;
  - KWin's precedence: the first matching rule that names the title bar decides (also "don't
    affect"), in the list's order; a rule with other conditions, an unread pattern or only the
    policy passed over when it keeps the bar;
  - class matching: unimportant, exact and substring (case-sensitive), the complete class; a
    regular expression handed to the matcher with the class, its true and false kept, undefined
    and no matcher taken as applying; leading `(?i)` and `(?m)` as flags.
- `packages/kwin/tests/tablet_regex_test.py` (PySide6, offscreen; CI `build`): `RuleRegex.qml`
  against QRegularExpression. PCRE syntax JavaScript reads otherwise gets KWin's answer; patterns
  it cannot read come back undefined; 6000 random patterns over 11 classes (a fixed seed) never get
  an answer that differs from KWin's (31 checks; 36 685 answers on Qt 6.11.2).
- `tests/vsession/scenario-tablet-titlebars.sh` (private session on the ThinkPad, 1440 x 900, KWin
  6.7.5; 2026-10-19, tb-9: all 19 checks pass, scenario rc 0):
  - **On the laptop** (check 0), KWin applies the rules as the policy must read them. KCalc and
    Ark open without a title bar: KCalc under a system-wide apply-initially rule in
    `~/.config/kdedefaults`, its group locked (`[$i]`) against the user's file turning it off; Ark
    under a regular expression with PCRE's `\A` and `\z`; Gwenview under an apply-initially rule.
    Konsole, under a rule that is off, opens with one, and Filelight, under two apply-initially
    rules of which the first keeps its title bar.
  - **In tablet posture,** windows open: Dolphin taken out of full screen, KWrite quick-tiled from
    it, and Konsole tiled and untiled have their title bars after tablet posture. KCalc, Ark and
    KCharSelect (the user's forced rule), quick-tiled from full screen and untiled, keep none.
  - **Left maximized until tablet posture ends:** Okular, made borderless by the user before it, and
    Gwenview, opened in it under its rule, keep no title bar after `leave()` un-maximizes them;
    Filelight has its title bar (its first rule).
  - **Files:** the script, loaded again once the rules exist, leaves both rules files as they were.
- **Red runs:**
  - main's script (c947218): the three title bars are missing (tb-r2, "tiles with title bar 0,
    floated with title bar 0");
  - the first rules check, which read only the user's file (40cf2e7): KCalc gets a title bar
    after leave (tb-r3, scenario rc 1);
  - the second (3ffa019): Konsole keeps none, KCalc and Ark get one, and `modelData` is written
    into both rules files (tb-r5, 4 failures);
  - the third (402e2bb), and the first `leave()` fix (tb-7): Okular and Gwenview get a title bar
    when tablet posture ends (tb-r7);
  - the fourth (ec24884), which took any matching rule that removes the bar: Filelight keeps none
    after tablet posture (tb-r9);
  - without any rules check, `scenario-kwin2-a.sh`'s T19 failed on its apply-initially KCalc (k2a-3:
    a title bar after leave).
- **Regression:** `scenario-kwin2-a.sh` passes all 31 checks (k2a-4, and k2a-11 with this version)
  and `scenario-fullscreen-off.sh` all 13 (fo-7, fo-10).

Not tested in a session: 6.8's decoration policies (the ThinkPad runs 6.7.5; node only).

## Split at a third, a half, two thirds (2026-10-19)

Three KWin actions without a key, "Plasma Fusion: Split One Third", "Split Half" and "Split Two
Thirds" (`ShortcutHandler`s; text "Plasma Fusion: Split the Screen at …"): the active window's
quick-tile split moves so that the left part is that share of the work area (`splitAt()`, from
`centreSplit()`, which is now `splitAt(w, 0.5)`). The dock invokes one when it opens a saved app
pair ([`apppairs.md`](apppairs.md)); they also show in System Settings' shortcuts. Log "split at one
third: CLASS", or "no split here" when the active window has no quick tile beside another.
