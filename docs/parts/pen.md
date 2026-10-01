# Pen (stylus) support

Spec: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-tablet/PEN.md` (defaults in section 2,
Pen menu in section 3, hand checks V1-V6 in section 6.2). Device: ThinkPad X13 Yoga Gen 4, Wacom
WACF2200 `056a:534d`, libinput devices "Wacom HID 534D Pen" and "Wacom HID 534D Finger".

## Defaults (`tools/pen/pen-defaults.sh`)

Per user, run inside the session (or over SSH with the session bus). Every setting takes effect at
once; `--dry-run` prints the changes, `--restore <backup>` undoes them, `--no-install` skips the
package.

| Setting | Value | Where |
|---|---|---|
| Click button (BTN_STYLUS, 331) | right click | `kcminputrc [ButtonRebinds][TabletTool][Wacom HID 534D Pen] 331=MouseButton,273` |
| One pointer for pen, touchpad and TrackPoint | on | `kcminputrc [Tablet] SyncWithMouse=true` |
| Pen screen | built-in panel (`eDP-1`) | KWin D-Bus `outputName`; KWin writes `OutputUuid` |
| Notes and whiteboard app | Xournal++ | `dnf install --setopt=install_weak_deps=False xournalpp` (3 packages, about 8 MB; with weak dependencies its optional LaTeX tool pulls in about 260 MB of TeX Live) |
| Device description (X13 Yoga Gen 4 digitizer only) | `~/.config/libwacom/lenovo-x13-yoga-gen4-534d.tablet` | per user (libwacom reads `$XDG_CONFIG_HOME/libwacom` first); names the device, `Reversible=false` removes the left-handed option that mirrors a display pen; libinput reads it when KWin adds the device, i.e. from the next login. No `Styli` line until hand check V1 (every `isdv4-aes` stylus has one button) |

The internal output is found through sysfs (`/sys/class/drm/card*-eDP-*`), so no Qt tool runs. The
backup (`~/.local/state/plasma-fusion/pen-backup-<UTC>/`) holds a copy of `kcminputrc`, the old value
of each key the script set (`keys`) and the pen's previous output (`pen-output`).

The backup also holds the pen's screen mapping (`pen-map`) and pressure curve (`pen-pressure`), which
the pen menu's settings page can change; `--restore` sets them back over D-Bus (a backup from before
they were recorded gets `mapToWorkspace false` and the linear curve). The click-button mapping
assumes the button that sends 331 is the one a user expects to right-click with (hand check V1).

## Live device

2026-09-30 01:17Z: applied to the ThinkPad's real session (backup `pen-backup-20260930T011729Z`);
01:41Z the libwacom description (backup `pen-backup-20260930T014140Z`; `libwacom-list-local-devices`
lists the pen as 'Lenovo ThinkPad X13 Yoga Gen 4 Pen', General Pen + Eraser, 2 buttons).
Undo: `~/.local/state/plasma-fusion/tools-pen/pen-defaults.sh --restore
~/.local/state/plasma-fusion/pen-backup-20260930T011729Z`; `sudo dnf remove xournalpp` for the app.

## Pen menu (`org.plasmafusion.pen`, PEN-1, 2026-09-30)

Work package PEN-1 of the one-pass plan (PEN.md 3 and 5 with the review corrections and the
PLAN.md alignment), built by the lead directly.

### Files

| Path | Purpose |
|---|---|
| `packages/plasmoids/org.plasmafusion.pen/metadata.json`, `contents/config/main.xml` | Plasma/Applet; settings `showButton` (`tablet`, `always`, `never`), `actions` (tile order), `garageAction`, `openRequest`, `forcePen` (test sessions only) |
| `contents/ui/main.qml` | visibility, the pop-up and its placement, open requests, the actions |
| `contents/ui/PenButton.qml` | the top-bar button |
| `contents/ui/PenMenu.qml`, `PenTile.qml` | the card: header and action tiles |
| `contents/ui/PenSettings.qml`, `SettingRow.qml` | the settings page inside the card |
| `contents/ui/services/PenDevice.qml` | the pen as KWin knows it (D-Bus), and the device writes |
| `contents/ui/services/Exec.qml`, `LineIcon.qml`, `Icons.js` | helper commands, line icons |
| `tools/build.d/75-pen.sh` | installs the package with the shared blocks (`FusionMetrics`, `FusionAccent`, `FusionTablet`) and writes the Xournal++ templates `Note.xopp` (A4 portrait, ruled) and `Whiteboard.xopp` (A4 landscape, plain) to `~/.local/share/plasma-fusion/pen/templates/` (same bytes on every build) |

The layout script puts the widget between the tray and quick settings when it is installed
(LAYOUT-1); `fusion-config.sh --pen` adds it to an existing top bar and sets Meta+Shift+W on it
(DEVICE-1).

### Behaviour

- **Button**: shown only while a pen exists and, with the default `showButton=tablet`, in tablet
  posture (`FusionTablet`, KWin's own state); `always` shows it whenever a pen exists, `never`
  hides it (the card still opens from the shortcut). A 32 px round fill in tablet posture (26 px in
  the laptop bar) inside a 44 px hit area in touch mode, 18 px pen glyph; while the card is open it
  takes the quick-settings pill's open look (accent at 35 %, 1 px edge).
- **A pen exists**: `PenDevice` reads `devicesSysNames` from `org.kde.KWin /org/kde/KWin/InputDevice`
  once and each device until one has `tabletTool=true`, and reads again on `deviceAdded` /
  `deviceRemoved`. No polling. Without the object (virtual sessions) there is no pen.
- **Opening**: the button, the widget's global shortcut (Meta+Shift+W), and `openRequest` written
  through desktop scripting, `"<mode>:<nonce>"` (the launcher's form; `"<mode> <nonce>"` also
  works) with `open`, `close` (never opens a closed card), `toggle`, `newnote` and `settings`.
- **Card**: 404 px (scaled with the text, at most the screen less 32 px, on the device grid: 405 at
  4/3), 16 px padding including the dialog frame's own; placed from the screen alone: right edge 16 px from the screen edge (12 in
  tablet posture), 10 px under the bar (8 in tablet posture), centred in portrait. Never from the
  widget, which a hidden widget has at the panel's start (PEN.md 3.1). Built on the first open
  (`Loader`, asynchronous), the settings page only while it is shown; a closed card gives its
  window's graphics resources back (`releaseResources()`). At idle only the button, `PenDevice`
  and its signal watcher exist.
- **Header**: 44 px icon well with the pen glyph, "Pen" and the pen's name ("Lenovo Integrated Pen"
  for the X13 Yoga's digitizer), gear button (settings).
- **Tiles** (3 columns, 10 px apart, `(372 - 20) / 3` = 117.33 x 96 at the default size), in the
  order of `actions`:
  - New note (primary, accent fill): copies `Note.xopp` (found with `StandardPaths.locate`, so an
    RPM install's `/usr/share` copy works too) to `~/Documents/Notes/Note YYYY-MM-DD HHMM.xopp`
    (` (2)`, ` (3)` … when the name exists) and starts Xournal++ with
    `kstart --application com.github.xournalpp.xournalpp --url <file>`, in its own scope, not as a
    plasmashell child. Without Xournal++ (`StandardPaths.findExecutable`, checked on every open)
    the tile reads "Install Xournal++" and opens Discover's page.
  - Snip: `spectacle -b -r -k -c -n` 250 ms after the card closed (drag, lift, the picture is on
    the clipboard).
  - Mark up: kglobalaccel `invokeShortcut RectangularRegionScreenShot` on Spectacle's component,
    250 ms after the card closed.
  - Whiteboard: as New note with `Whiteboard.xopp`; left out without Xournal++.
  - Draw on screen: `kstart wayscriber`; left out unless wayscriber is installed (the default).
  - Pen settings: the settings page.
- **Settings page**: Click button (Right click / Open pen menu, only while the widget has a
  shortcut / Middle click / Let apps decide: `kcminputrc [ButtonRebinds][TabletTool][<pen>] 331` =
  `MouseButton,273` / `Key,<shortcut>` / `MouseButton,274` / deleted, with `--notify`); Eraser
  (information); Pressure Soft / Linear / Firm (device `pressureCurve` `0,0.4;0.6,1;`, `0,0;1,1;`,
  `0.4,0;1,0.6;`); Pen works on Built-in screen (`mapToWorkspace false` + `outputName` of the
  first `eDP`/`LVDS`/`DSI` screen) / Follow the active screen (`mapToWorkspace false` +
  `outputName ""` + `OutputUuid` deleted from the device's `[Libinput][vendor][product][name]`
  group) / All screens (`mapToWorkspace true`); One pointer for pen and mouse (`[Tablet]
  SyncWithMouse`); Show pen button; Test your pen and Advanced (System Settings > Drawing Tablet,
  `KCMLauncher`). Values are read when the page opens. Each row with choices opens them below
  itself (44 px rows, the current one checked).
- **Not built** (by the plan's conditions): the battery chip (after hand check V3), the garage
  service, its footer row and subtitle (after V2), and "Touch while the pen is near" (after V4).
- One log line per user action (`pen: card open at …` with the card's and controls' global
  positions, 200 ms after it settles; `pen: card closed`, `pen: run …`, `pen: button shown at …`),
  for the tests and bug reports. They use `console.info`: Fedora's Qt logging rules drop
  `console.log` (debug).
- `tools/pen/pen-defaults.sh --restore` (called by `fusion-restore.sh`) also puts the click button
  (331) and `SyncWithMouse` back to the backup's `kcminputrc` values (deleted where it had none,
  with `--notify`), since the settings page can change them after the defaults step, and it works
  without a pen for those keys (the pen's screen and pressure need the device).

### Verification

Private sessions on the ThinkPad (1920 x 1200 at 4/3, `build/pen/`: `scen-pen1.sh`, `scen-pen2.sh`,
`scen-pen3.sh`; seed = the LAYOUT-1 stage plus this package, a Xournal++ stub first on `PATH` and as
the `com.github.xournalpp.xournalpp` desktop file; the widget's `forcePen` on, because a virtual
session has no tablet device). Final run `pen-1`: 37/37 checks.

- PT5: no pen: nothing shown; forced pen in laptop posture: hidden; tablet posture: shown, hidden
  again in laptop posture.
- PT1: the button's hit area 44 x 44 in tablet posture; a tap opens the card; tiles New note, Snip,
  Mark up, Whiteboard, Pen settings (no wayscriber on the host), each 118 x 96 on a 405 px card
  ((405 - 32 - 20) / 3; 117.33 at 404); card 12 px from the screen edge under the 44 px tablet bar.
- PT3: New note copied the template to `~/Documents/Notes/Note 2026-09-30 HHMM.xopp` and started the
  stub through `kstart --application` with that file. The app's own `app-*.scope` cannot be seen in
  a private session (no systemd user manager: the stub ran in the SSH session's scope, as a child of
  `kstart`, not of plasmashell); hand check in the real session. The "no Xournal++" tile could not
  be tested: Xournal++ is installed on the ThinkPad.
- PT4: Snip logs the card closing, then `spectacle -b -r -k -c -n` (Escape then cancels the region
  selection); Mark up logs the card closing, then the Spectacle shortcut call.
- PT2: through real clicks on the settings page: Middle click, Right click, Open pen menu
  (`Key,Meta+Shift+W`; the choice appears because the widget has the shortcut) and Let apps decide
  write `331` exactly (read back with `kreadconfig6`); One pointer Off/On write `SyncWithMouse`;
  Show pen button Always writes the widget's `showButton`; Pressure and Pen works on without a
  device log "no tablet device, … not written".
- PT7: in laptop posture with the button hidden, Meta+Shift+W, `invokeShortcut "activate widget <id>"`
  and `openRequest` `open:<n>` open the card at the top right, 16 px from the screen edge (never at
  the bar's left end); `close:<n>` closes it; `close:<n>` on a closed card does not open it.
- PT9: after the settings page's kind of changes (331 and `SyncWithMouse` set live), the real
  `fusion-restore.sh` removes both and the widget's Meta+Shift+W entry reads `none`. The device part
  (`outputName ""`, `mapToWorkspace false`) needs a pen: hand check.
- PT6: no core dumps; no QML warnings from the widget (only Plasma's own two `propertyCache` lines).
- PT8 (plasmashell, medians of 3 snapshots): the hidden widget +1.1 MiB PSS, +0.9 MiB anonymous and
  -0.4 MiB GEM against the same install without it (budget +2 MiB PSS). The first open: +10.7 MiB PSS
  and +12.8 MiB GEM when the card is the session's first Plasma pop-up (budget +8 / +6); with quick
  settings opened before it, the card adds +7.8 MiB PSS and +2.8 MiB GEM (inside the budget) while
  quick settings itself took +8.6 / +12.9: about 10 MiB of GEM is the cost of a session's first
  pop-up window, whichever it is. Without `releaseResources()` and with the settings page built at
  once the first open cost +21 / +23. Idle frames after closing and the first-frame latency were not
  measured (the closed card has no timers or animations).
- Lint: `a11y-lint` and `motion-lint` 0 findings; `qmllint` only the unqualified-access notes of
  plasmoid files; `shellcheck` clean.

Hand checks for DEPLOY-1 (PEN.md 6.2): V1-V7 with a real pen, the widget on the real digitizer
(`PenDevice` finds it, the settings page's device writes), the app scope of a note, and the card's
first-frame time.

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build2/PEN-1/`.

## Pen like a finger in tablet posture (TABLET2 PEN-2, 2026-10-01)

The owner found pen drags in tablet posture turning into invisible selection boxes or text
selection. Research round 2 (F-pen, section 0, from source code) explains it: on Linux a pen tip is a
left mouse button for every app that does not take tablet input (Qt turns unhandled tablet events
into mouse events), so a drag selects text or starts a rubber band; Qt Quick's ScrollView ignores
pen drags and Kirigami makes scroll bars non-interactive in tablet mode, so many pages cannot be
scrolled by pen at all. iPadOS, Android and Windows (since 1709) make the pen scroll like a finger
outside drawing surfaces.

- `FusionPenFilter` (navigation effect, `penfilter.cpp`): a KWin input filter ordered after the lock
  screen. In tablet posture, while the pen tip is down, it feeds KWin's own touch path
  (`TouchInputRedirection::processDown/Motion/Up`) instead of tablet events, so focus, activation,
  popups and each app's touch scrolling work as for a finger, and the on-screen keyboard follows as
  for touch.
- Exempt (the pen stays a pen): drawing apps (window class or desktop file name in
  `plasmafusionrc [Pen] DrawingApps`; default Xournal++, Rnote, Krita, Inkscape, GIMP, MyPaint,
  KolourPaint), presses in the bottom 24 px (the pen never starts a shell gesture), laptop posture,
  and `plasmafusionrc [Pen] TabletPen=pen`.
- Setting: the pen settings page, "In tablet posture: Like a finger: drags scroll / Like a mouse:
  drags select"; the effect follows it live.
- Test tooling: with `PLASMA_FUSION_TEST_PEN=1` in KWin's environment (private test sessions only)
  the plugin adds a virtual pen (`testpen.cpp`, an `InputDevice` whose events take the libinput
  pen's path through KWin) driven from D-Bus (`org.kde.KWin /org/plasmafusion/TestPen`
  `proximity/tip/move`).
- Private session pen9 (Dolphin with 300 files): laptop posture, a pen drag on a file starts a drag
  and drop (mouse); tablet posture, the same drag scrolls the view (top row file-000 -> file-036
  after the fling); a pen tap opens a file like a finger tap; a pen stroke from the bottom zone
  leaves the app in place; "like a mouse" switches back live.
- Not done yet (research SHOULD): press-and-hold right-click for the pen in tablet posture, a hover
  dot, a pen tap on the home handle revealing the dock. Hand checks with the owner's pen: F1-F8 of the
  research (scroll in Dolphin, System Settings, Firefox, Chrome; drawing apps keep pressure; taps
  without rubber bands; barrel button = context menu; palm rejection; after suspend).

## Press and hold = right click (TABLET2 PEN-2 follow-up, 2026-10-01)

With the pen acting as a finger in tablet posture, QtWidgets and XWayland apps had no context menus
by pen (a finger's long press opens none there). As with Windows Ink: when the tip rests 500 ms within
10 px (research: 500-600 ms, 10 px), `FusionPenFilter` cancels the emulated touch (no tap, no drag),
swallows the rest of the stroke and, when the pen lifts, sends a right click at the press point:
pointer motion, button press, each with a `wl_pointer.frame`, and the release 80 ms later (Qt opens a
context menu on the press and grabs the pop-up with it; a release sent together made KWin dismiss the
menu). Drawing apps, the bottom gesture zone and laptop posture are unaffected. Setting: pen settings
page "Press and hold: Right click (menu) / Nothing" (shown while the pen acts as a finger),
`plasmafusionrc [Pen] TabletPenHold` (default true), read live. Each hold logs
`plasmafusion-navigation: pen press and hold: right click at x,y`.

Test (`build/penhold/scen-hold.sh`, ph1; evidence `artifacts/plasma-fusion/2026-10-01-tablet2/PEN-2/hold`):
a hold on Dolphin's file view opens its context menu on lift, a hold drifting 40 px opens none, a quick
tap opens the file, a hold in Konsole opens Konsole's menu, with the setting off nothing happens. The
private session has a pointer device only while the test input client is connected, and without one
the seat offers no pointer, so the scenario keeps one connected (as the hardware's touchpad and
TrackPoint always are).

## Press and hold over the Plasma shell (2026-10-01)

Over plasmashell's windows (home screen, dock, launcher, top bar, widgets) the pen's press and hold
does not turn into a right click: those surfaces open their menus on a touch long press, so the pen
stays a finger for the whole hold (`FusionPenFilter::shellLongPress`). The right click, injected after
the touch had been cancelled, opened nothing there (a pen hold on a home-screen tile showed no menu
while a finger hold did; found in the PLASMA-68 container runs, same on Plasma 6.7.5 and 6.8). Apps
keep the right click (Dolphin's menu opens as before).

## Pen tap on the home handle (2026-10-01)

Research F-pen 4.14: the pen never makes a navigation gesture (strokes on the bottom 24 px reach the
app or the bottom strip unchanged), but pen-only use must be able to leave an app. A quick pen tap on
the bottom zone (under 400 ms, within 10 px) now shows the dock, as a short finger flick does
(`FusionPenFilter::setBottomTapHandler` -> `FusionNavigationState::revealDock`; log "pen tap on the
home handle: dock"). From the dock, the home and app buttons work with the pen. Tested with the test
pen in the 6.7.5 and 6.7.91 containers (pt675, pt68): the stroke from the bottom edge changes nothing,
the tap shows the hidden dock over a maximized app.
