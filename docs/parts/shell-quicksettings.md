# Part: quick settings (`org.plasmafusion.quicksettings`)

The right side of the top bar and its pop-up, built from the Quick Settings boards
(`QuickSettings.dc.html`, `QuickSettingsLight.dc.html`, renders `desktop-dark-4` / `desktop-light-4`),
the top bar of `Main.dc.html` / `MainLight.dc.html` and the Wi-Fi tray panel of
`Popups.dc.html` / `PopupsLight.dc.html`. QML only, no compiled code.

## What it is

**In the top bar** (one widget, right to left as on the board, 6 px apart):

| Item | Board value | Source | Shown when |
|---|---|---|---|
| Notification bell, amber (#F2A65A) 7 px unread dot | 30 × 26, radius 13 | `org.kde.notificationmanager` history, `unreadNotificationsCount` | always (option); slashed bell while Do Not Disturb is on |
| System status pill: Wi-Fi, volume, battery icon + `NN%` | 26 px, radius 13, padding 12, gap 10, fill 8 % overlay; accent tint `rgba(91,157,255,.35)` + 1 px `rgba(138,184,255,.5)` while the pop-up is open | plasma-nm `ConnectionIcon`, plasma-pa `PreferredDevice.sink`, `BatteryControlModel` | each icon only when its service has data; a gear icon when none has |
| Clipboard | 28 × 26, 16 px icon | Klipper D-Bus `showKlipperPopupMenu` | option |
| Phone | 28 × 26, 16 px icon | `org.kde.kdeconnect` `DevicesModel` (paired + reachable) | a device is connected |
| `EN` keyboard layout badge | 22 px, padding 7, radius 6, 1 px border 18 % | `org.kde.plasma.workspace.keyboardlayout` (KWin) | layout info exists (option: only with 2+ layouts); click = next layout |

The pill also takes the mouse wheel (volume ±5 %) and middle click (mute). Icons are the boards'
line icons (24 px grid, 1.8 stroke) drawn with QtQuick Shapes, with the FileIcons board's level
states (Wi-Fi bars, volume waves, battery fill, charging bolt, 30 % / 10 % warning colours).

**The pop-up** (356 px wide, 10 px under the bar, 16 px from the screen edge, frame = the Plasma
style's `dialogs/background`, so radius, 88 % fill, edge, shadow and blur come from the Plasma style):

* battery chip (`82%`, 34 px, radius 17) and four 34 px round buttons: screenshot (Spectacle's
  rectangular-region shortcut), System Settings, lock, leave (logout / restart / shut down prompt);
* volume slider with mute button and chevron to the output chooser; brightness slider
  (8 px track, 20 px white knob with shadow, `#5B9DFF` fill = colour scheme DecorationHover);
* six 60 px tiles, radius 16, accent fill when on:
  Wi-Fi (SSID; body toggles Wi-Fi, chevron opens the network list),
  Bluetooth (`N connected` / device name; body toggles, chevron opens the device list),
  Night light (`From sunset`, `Until sunrise`, `From 19:00`, `Paused`, `Off`; toggles KWin's
  Night Light inhibition, turns Night Light on when it is off),
  Do not disturb (`Off`, `On`, `Until 18:00`; same code path as Plasma's own shortcut, with OSD),
  Power mode (`Power saver` / `Balanced` / `Performance`, click cycles; through PowerDevil, which
  uses tuned-ppd on the ThinkPad),
  Dark style (switches between the two Plasma Fusion Global Themes, see below);
* media card (64 px, radius 16): album art or player icon, title, `Paused` / artist, previous,
  play/pause (36 px filled), next; shown only while a player exists. The player icon is the
  application icon; when libkmpris cannot read the player's desktop file (it then reports the
  generic `emblem-music-symbolic`), the desktop entry name is used as the icon name;
* `Notifications` header with `Clear all`, then the notification cards (app icon + name, time,
  summary, body, job progress with Cancel, action buttons; the first action is the accent button
  for critical or persistent notifications, as the board's calendar reminder). Close button on hover.
  Clicking a card runs its default action.

**Drill-down pages** replace the quick settings in the same card (back button, title, switch):
Wi-Fi (Popups board tray panel: connected network card with band, security and live speed,
`OTHER NETWORKS` list with signal levels and locks, inline password field for new WPA/WPA2/WPA3
networks, `Hidden network…` and `Network settings`), Bluetooth (paired devices, connect /
disconnect, `Pair a new device…`, `Bluetooth settings`), Sound output (choose the default sink).

Keyboard: every control is reachable with Tab and has the design's focus ring (2 px, 2 px gap);
Space/Return activate, Right/Left moves between a tile and its chevron, Escape goes back a page or
closes the pop-up. The widget's global shortcut (Plasmoid shortcut) opens and closes the pop-up.
A notification's close button is in the tab chain (shown while focused or hovered), and the list
scrolls to the card that has keyboard focus. Opening or leaving a drill-down page moves the focus
with it; the ring is shown only when that was done from the keyboard.

Colours: the boards' dark and light values (text `#E8EBF4` / `#141827`, secondary `#A3ABC2` /
`#5B6278`, overlays white / `#141827` at the board's alphas). Dark or light is chosen from the
background of the current colour set (panel for the bar, pop-up window for the card); accent,
slider fill, focus ring and link colours come from the colour scheme, so a user accent still applies.
Text uses the system UI font (Manrope under Plasma Fusion) at the boards' pixel sizes and weights.

## Files

```
packages/plasmoids/org.plasmafusion.quicksettings/
  metadata.json                     Plasma/Applet, id org.plasmafusion.quicksettings, GPL-2.0-or-later
  contents/config/main.xml          widget options (below)
  contents/config/config.qml        settings page list
  contents/ui/main.qml              PlasmoidItem: bar in the panel, own AppletPopup (margin 10)
  contents/ui/Backend.qml           null-safe facade over all services, palette, actions
  contents/ui/TopBar.qml            EN, phone, clipboard, status pill, bell
  contents/ui/PopupContent.qml      page stack + notification list, frame-padding compensation
  contents/ui/QuickSettingsMain.qml header row, sliders, tiles, media card
  contents/ui/WifiPage.qml          Wi-Fi drill-down
  contents/ui/BluetoothPage.qml     Bluetooth drill-down
  contents/ui/AudioPage.qml         output device chooser
  contents/ui/NotificationCard.qml  one notification
  contents/ui/ConfigGeneral.qml     settings page
  contents/ui/components/           palette, line icons (Icons.js, LineIcon, Network/Volume/BatteryGlyph),
                                    Tile, FusionSlider, FusionSwitch, IconButton, TextButton, ListRow,
                                    PageHeader, FocusRing, FText
  contents/ui/services/             one file per data source, each loaded by a Loader:
                                    Network (plasma-nm), Audio (plasma-pa), Battery, PowerProfiles,
                                    Display (brightness, Night Light, light/dark pairing), Media (MPRIS),
                                    Notifications, Keyboard, KdeConnect, Bluetooth (BluezQt), Session, Exec
tools/build.d/71-quicksettings.sh   copies the package to $STAGE/.local/share/plasma/plasmoids/
```

## Build, install, apply

```
tools/build.sh quicksettings        # -> stage/home/.local/share/plasma/plasmoids/org.plasmafusion.quicksettings
# or for one user without the build tree:
kpackagetool6 -t Plasma/Applet -i packages/plasmoids/org.plasmafusion.quicksettings   # -u to upgrade
```

Placing it (Global Theme layout script or `org.kde.PlasmaShell.evaluateScript`), at the right end
of the 34 px top bar, after the system tray:

```js
var tray = topBar.addWidget("org.kde.plasma.systemtray");
var qs = topBar.addWidget("org.plasmafusion.quicksettings");
tray.currentConfigGroup = ["General"];
tray.writeConfig("hiddenItems", [
    "org.kde.plasma.networkmanagement", "org.kde.plasma.volume", "org.kde.plasma.battery",
    "org.kde.plasma.bluetooth", "org.kde.plasma.brightness", "org.kde.plasma.notifications",
    "org.kde.plasma.keyboardlayout", "org.kde.kdeconnect", "org.kde.plasma.clipboard",
    "org.kde.plasma.mediacontroller"]);
// optional: a key for the pop-up, e.g. qs.globalShortcut = "Meta+Alt+S";
```

System tray keys (containment config of the tray, group `[General]`):

* `hiddenItems` = the ten ids above. The first six are what the pill, the tiles and the bell
  replace; the next three are drawn by this widget (EN, phone, clipboard), so they must not show
  twice; `org.kde.plasma.mediacontroller` is replaced by the media card.
* Do **not** remove them from the tray (`extraItems`) or disable them: hidden items stay loaded, and
  this widget needs them loaded. The Notifications applet owns the notification pop-ups and the
  Do Not Disturb bookkeeping (the tile triggers its `toggle do not disturb` shortcut); the Clipboard
  applet hosts Klipper, which the clipboard button calls over D-Bus; Battery/Brightness/Networks keep
  their warnings and password prompts.
* `shownItems` must not list any of them.
* Note: the tray shows its expander arrow while any hidden item is active. That arrow is the stock
  tray's and is not on the board.

Widget options (`[General]` of the widget, `contents/config/main.xml`, also in its settings page):

| Key | Default | Meaning |
|---|---|---|
| `showKeyboardLayout` | true | EN badge |
| `keyboardLayoutAlways` | true | badge also with a single layout (the board shows it) |
| `showKdeConnect` | true | phone button while a device is connected |
| `showClipboard` | true | clipboard button |
| `showBatteryPercent` | true | `NN%` in the pill |
| `showNotifications` | true | bell and notification list |
| `popupGap` | 10 | px between the bar and the pop-up |
| `popupScreenMargin` | 16 | px between the pop-up and the screen edge |
| `startPage` | main | page shown on open: `main`, `wifi`, `bluetooth`, `audio` (settings page: "Page shown when opened") |
| `lightLookAndFeel` / `darkLookAndFeel` | `org.plasmafusion.light.desktop` / `org.plasmafusion.dark.desktop` | Dark style fallback targets |

Dark style: when kdeglobals `[KDE] DefaultLightLookAndFeel` / `DefaultDarkLookAndFeel` pair the two
Plasma Fusion themes (or the user is on a non-Fusion theme), the tile uses Plasma's own
`DarkModeControl` (same as the Brightness applet: sets `LookAndFeelPackage` and runs
`plasma-apply-lookandfeel -a`). When a Plasma Fusion theme is active but not paired, it runs
`plasma-apply-lookandfeel -a <the other Fusion theme>` if that package is installed. The tile state
follows the actual colours (dark background = On).

Night light when it is off in KWin: the tile runs
`kwriteconfig6 --notify --file kwinrc --group NightColor --key Active true`. `--notify` is required:
KWin's Night Light reloads its settings only through KConfigWatcher (a plain write, or KWin's
`reconfigure()`, leaves it off). Without the helper the tile opens the Night Light settings.

## Verification

* `qmllint` (Qt 6.11.2) over all 37 QML files of the package: no errors; the remaining warnings are static-analysis
  limits (types and singletons that plasma-pa registers from C++, `ListView.currentItem` methods,
  attached `KRoleNames` on a model held in a `var`). `metadata.json` parses, `main.xml` is well formed.
* Offline preview on the laptop (no windows on the user's display): PySide6 6.11 `QQuickView`,
  `QT_QPA_PLATFORM=offscreen`, fonts through a private fontconfig file, a mock backend with the
  boards' data, rendered over the board renders at the board positions, plus keyboard focus
  walks with `QTest.keyClick(Tab)` (focus rings on sliders, tiles, chevrons, buttons) and mouse
  runs with `QTest.mouseClick` / drags: every tile body and chevron, the four header buttons, mute,
  both sliders (dragged: 0.65 → 0.24, 0.83 → 0.33), media buttons, `Clear all`, notification
  actions, and the Wi-Fi page (switch, `Disconnect`, open network row) reach the right backend call.
* Private virtual sessions on the ThinkPad (`tools/vsession/remote.sh qs-1 … qs-4`, prefix `qs-`):
  all parts built into `scratchpad/build-qs/home`, prototype colour schemes and the fonts added to
  the test HOME only, top panel created with `evaluateScript`, pop-up opened through the widget's
  global shortcut (`kglobalaccel invokeShortcut "activate widget <id>"`), notifications sent with
  `notify-send -A …` (during Do Not Disturb, so they stay live with their actions), a small MPRIS
  player for the media card. Run qs-3/qs-4 also started a private PipeWire + pipewire-pulse with two
  null sinks and a stand-in for PowerDevil's brightness and power-profile D-Bus objects (so nothing
  touched the real backlight or the real tuned profile), then stopped them at run time.
  Wi-Fi, Bluetooth, battery and keyboard layout were the real, read-only system services.
  Nothing on the ThinkPad was toggled.
* plasmashell was restarted inside the session with `QT_FORCE_STDERR_LOGGING=1`: no warning or
  error from this widget in any run (other lines come from stock applets and the missing session
  services of the virtual session).
* Screenshots and board side-by-sides: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/shell-quicksettings/`
  (`side-by-side-dark.png`, `side-by-side-light.png`, `side-by-side-wifi-{dark,light}.png`,
  `side-by-side-topbar.png`, `side-by-side-preview-{dark,light}.png`, `session-*.png`,
  `preview-keyboard-focus.png`; nearby Wi-Fi names are pixelated). The scenario, seed script,
  stand-ins and the preview harness are in `test-tooling/` there.
* Graceful degradation seen in the sessions: no audio server → no volume icon, slider or output
  page entries; no PowerDevil → no brightness row, Power mode `Unavailable` (dimmed); no KDE Connect
  device → no phone; no player → no media card; no notifications → no list (bell opens an empty
  state); services stopping while running → rows disappear without errors.

## Deviations from the boards

* **Notifications are inside the quick-settings card**, below the quick settings, as inset cards
  (6 % overlay, 1 px edge, radius 18). The board draws them as separate frosted cards on the
  wallpaper. Separate cards need either several pop-up windows or a transparent window, which has
  no KWin blur; one pop-up keeps the Plasma style's blur and one focus scope. The list scrolls when
  it would not fit on the screen.
* **Own pop-up window instead of the stock applet pop-up.** The stock pop-up of a non-floating
  panel is glued to the bar and the screen edge (square corners there). The widget therefore has
  no `fullRepresentation`; it opens a `PlasmaCore.AppletPopup` with a 10 px margin itself, placed so
  the card ends 16 px from the screen edge. Side effect: `plasmoid.expanded` is not used (the
  global shortcut, clicks and Escape work; scripts cannot expand it).
* **Time labels** are relative to now (`now`, `12 min ago`, `1 h ago`); the board's `in 10 min` is a
  calendar event time that notifications do not carry.
* **Night light semantics**: the tile is on while the screen is warm (night, or constant mode),
  as the board shows it off at 14:49 with `From sunset`. Clicking during the day pauses the coming
  evening (`Paused`), clicking again resumes; Plasma has no "turn on now until sunrise" without
  changing the user's Night Light mode.
* **Power mode** cycles through the profiles on click (the board shows no chooser).
* **Drill-down pages** also exist for Bluetooth and sound output (the board draws only the Wi-Fi
  panel); they use the same layout.
* Wi-Fi speeds are shown only once NetworkManager reports traffic counters (hidden in the virtual
  session, where the statistics refresh request is not authorised).
* `Hidden network…` opens the network settings module (Plasma has no QML hidden-network dialog).

## Needs from other parts

* **Plasma style** (`plasma-fusion-dark` / `-light`): `dialogs/background` with the 22 px radius,
  88 % fill, 1 px 12 % edge, shadow and blur hint; the widget compensates any frame padding so the
  content keeps its 16 px inset. Tooltips use `widgets/tooltip`.
* **Colour schemes**: Selection background `#2F6FDF` (tile and button accent), DecorationHover
  `#5B9DFF` (slider fill), DecorationFocus `#8AB8FF` / `#2F6FDF` (focus ring), link colours.
* **Global Theme / device setup**: set kdeglobals `[KDE] DefaultLightLookAndFeel=org.plasmafusion.light.desktop`
  and `DefaultDarkLookAndFeel=org.plasmafusion.dark.desktop` (Plasma's own dark-mode switch and
  automatic day/night switching use them; the tile falls back without them). Place the widget after
  the system tray with the tray keys above (the current layout script hides the first six; add
  `org.kde.plasma.keyboardlayout`, `org.kde.kdeconnect`, `org.kde.plasma.clipboard` and
  `org.kde.plasma.mediacontroller` to avoid duplicates). For the `EN` label set kxkbrc
  `[Layout] DisplayNames=en` (otherwise the badge shows the layout short name, `US`).
* **Fonts**: Manrope installed where fontconfig sees it. Qt only gets the separate weights of the
  variable `Manrope[wght].ttf` through fontconfig's named instances (checked on the laptop: with
  `QFontDatabase::addApplicationFont` Qt sees one instance and draws 400–600 alike and 700–800
  alike). Installing it to `~/.local/share/fonts/plasma-fusion/` works in plasmashell.
* **Icon theme**: app icons for the media card and notification cards come from the icon theme
  (the board's tiles need the PlasmaFusion theme).
* **Test tooling (lead)**: `tools/vsession/vsession.sh` starts plasmashell without
  `QT_FORCE_STDERR_LOGGING=1`, so Qt sends its log to the user journal and `plasmashell.log` stays
  empty; restart plasmashell in the scenario as done here, or add the variable to the script.
  In the virtual sessions a 34 px top panel came out 48 px tall (`panel.height = 34` is not kept);
  this is for the layout / Plasma style parts.

## Not verified

* Wi-Fi connect / disconnect, joining a network with a password, Bluetooth connect and turning
  radios off were not triggered on the ThinkPad: they go to the real system NetworkManager and
  BlueZ and would change the device's state.
* Lock and Leave buttons were not pressed in a virtual session: Leave opens the logout prompt,
  whose confirmation would reach the real machine's power management.
* KDE Connect phone button (no paired phone), vertical panels, touch mode.

(Mouse and keyboard interaction in a real session, the pill/bell open-close logic, Dark style,
Night light, Do not disturb and power profile switching were verified in the review, see below.)

## Review (2026-09-29)

An independent review of the part, integrated with every other part that exists today.

### What was checked

* Board values against the source of `QuickSettings.dc.html`, `QuickSettingsLight.dc.html`,
  `Main.dc.html` / `MainLight.dc.html` (top-bar right side) and `Popups.dc.html` (tray panel):
  pop-up 356 px, 16 px padding, 14 px gaps; header chip and 34 px buttons (fill 0.07, 17 px icons);
  sliders (8 px track, 20 px knob, shadow 0 2 6 at .35 / .14); tiles (60 px, radius 16, padding
  14 / 10 with chevron, 20 px icon, 13 px 800 title, 11.5 px subtitle at .85 / .9 white on accent);
  media card (64 px, 44 px icon, 36 px play button #e8ebf4 / #141827); notification cards (padding
  14, radius 18, 22 px icon, 11.5 / 13.5 / 12.5 px, 32 px radius-10 actions, first action accent
  for critical or persistent); top bar (EN 22 px radius 6 border .18 11 px 800, 28x26 icon buttons,
  pill 26 px radius 13 padding 12 gap 10, open tint rgba(91,157,255,.35) + 1 px .5 edge, bell
  30x26 with the 7 px #f2a65a dot at right 6 / top 4). All match; zoomed side-by-sides are in
  the evidence folder. Naming-table id, metadata (Authors, GPL-2.0-or-later) and the build script
  (`STAGE=… tools/build.sh quicksettings`, stage identical to the source) are correct.
* `qmllint` (Qt 6.11.2) over all 37 QML files: no errors; the warnings are `i18n*` calls
  (injected by Plasma), plasma-pa singletons and `ListView.currentItem` methods (static-analysis
  limits only).
* Integrated test: all parts built into a private stage, the Global Theme applied inside virtual
  sessions `rqs-1` … `rqs-6` on the ThinkPad with `plasma-apply-lookandfeel -a
  org.plasmafusion.dark.desktop --resetLayout` (its layout script places this widget after the
  system tray), plasmashell restarted with `XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:/etc/xdg` (as
  `startplasma` does; without it the Global Theme's Plasma style in `kdedefaults/plasmarc` is not
  read, see "Needs" below) and `QT_FORCE_STDERR_LOGGING=1`. Private PipeWire null sinks, a PowerDevil
  stand-in (brightness and profiles, now answering `setProfile` / `SetBrightness`) and an MPRIS
  stand-in; NetworkManager, BlueZ, UPower and the keyboard layout were the real read-only services.
* Real pointer and keyboard input in the virtual session through KWin's EIS interface
  (`org.kde.KWin.EIS.RemoteDesktop.connectToEIS` + libei, a small ctypes tool): pill and bell
  open / close / reopen, click outside closes, every drill-down page by its chevron, Escape back
  and close, Tab / Shift+Tab / Right focus walks, volume drag (pipewire sink went to 39 %), mute,
  brightness drag (stand-in received 74 … 25), Do not disturb on / off (tile and slashed bell),
  Power mode cycle (stand-in switched to `performance`), Night light enable and pause, Dark style
  off and on again (the whole desktop switched between the two Global Themes through the
  kdeglobals pairing and the tile followed), a notification action (`notify-send -A` printed
  `join`), close by mouse and by keyboard, Clear all, the empty bell state, nine long
  notifications (elided app name, two-line summary, four-line rich body with link, list scrolls
  and stops 16 px above the screen edge), clipboard button (Klipper pop-up), screenshot button
  (Spectacle launched), System Settings button (window opened, pop-up closed).
* Logs: no line from this widget in plasmashell's stderr in any run (the remaining lines are
  stock: kdeconnectd cannot start in a virtual session, PowerDevil keyboard brightness, kpipewire).

### What was fixed

* **Night light could not be turned on** (high): the tile wrote `kwinrc [NightColor] Active=true`
  without `--notify` and then called `org.kde.KWin.reconfigure`, which the Night Light plugin does
  not listen to; KWin stayed `enabled: false` (run rqs-3). Now `kwriteconfig6 --notify …`; KWin
  reports `enabled: true, running: true` after one click (rqs-4).
* **Settings dialog warning** (medium): `ConfigGeneral.qml` had no `cfg_startPage`, so opening the
  widget's settings printed "Setting initial properties failed: … does not have a property called
  cfg_startPage" (reproduced offscreen with the same initial properties Plasma passes). Added the
  property and a "Page shown when opened" combo box.
* **Notification close button not reachable from the keyboard** (medium): it was `visible` only on
  hover, so it never entered the tab chain. It now stays in the chain (transparent until focused or
  hovered, the time label shows otherwise) and the list scrolls to the card that has focus.
* **Media card showed a generic note instead of the player's app icon** (low): libkmpris reports
  `emblem-music-symbolic` when it cannot read the player's desktop file, so the desktop-entry
  fallback never ran. The generic name is now treated as "unknown", and `Kirigami.Icon` falls back
  to it when a theme lacks the app icon. With PlasmaFusion the card shows the board's Music tile.
* **Pop-up could end 12 px (not 16 px) above the screen edge** (low): the height limit was measured
  from the widget, but a non-floating panel's pop-up is placed against the panel window's edge.
  It is now measured from the panel window (checked: bottom edge at 884 on a 900 px screen).
* **Focus ring after a mouse click** (low): opening or leaving a drill-down page always used
  `Qt.TabFocusReason`, so a click on a chevron showed a focus ring on the Back button (and back on
  the chevron). The reason now follows how the page was opened / closed.
* **kdeconnectd activation with the phone button switched off** (low): the KDE Connect model is
  now loaded only when `showKdeConnect` is on (the model D-Bus-activates kdeconnectd).

### What remains (not fixed here)

* Notifications live inside the one frosted pop-up (builder's documented deviation). Separate
  frosted cards would need one window per card (or a transparent window, which gets no KWin blur
  in 6.7.5) and would split keyboard focus; the review agrees with keeping one pop-up.
* In the integrated session the top bar is 48 px, not 34 (known Plasma style issue, see
  `docs/parts/shell-topbar.md`); this widget follows it (pop-up 10 px below the bar either way).
* The stock tray next to this widget still shows the media controller and the expander arrow,
  because the Global Theme layout hides only six items (see "Needs from other parts").

### Needs from other parts (added by the review)

* **Look-and-feel layout**: add `org.kde.plasma.mediacontroller`, `org.kde.plasma.keyboardlayout`,
  `org.kde.kdeconnect` and `org.kde.plasma.clipboard` to the tray's `hiddenItems`
  (`TRAY_ITEMS_REPLACED`); in the integrated session the tray showed a second play/pause icon and
  the expander arrow left of `EN`. Optionally set a global shortcut for this widget
  (`quickSettings.globalShortcut = "Meta+Alt+S"`), since the layout gives it none.
* **Lead / vsession tooling**: `vsession.sh` starts KWin and plasmashell without
  `XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:/etc/xdg`. Plasma writes Global Theme values into
  `~/.config/kdedefaults/`, so `plasma-apply-lookandfeel` inside a virtual session does not change
  the Plasma style (no `plasmarc` in HOME) until plasmashell is restarted with that variable.
* **Lead / test tooling**: the EIS input tool (`pfinput.py`: `click X Y`, `drag`, `scroll`,
  `key tab|shift+tab|escape|…`) makes real clicks and key presses possible in the virtual sessions;
  it is in the evidence folder under `review-tooling/`.

### Evidence

`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/shell-quicksettings/review-*.png`
(network names pixelated): `review-side-by-side-{dark,light,topbar}.png` (board next to the
session), `review-{dark,light}-{bar,popup,wifi}.png`, `review-dark-{bluetooth,audio}.png`,
`review-{dark,light}-keyboard-tile.png`, `review-dark-keyboard-chevron.png`,
`review-dark-keyboard-close-notification.png`, `review-dark-many-notifications.png`,
`review-dark-many-keyboard-scroll.png`, `review-dark-cleared.png`,
`review-dark-nightlight-{enabled-fix,on,paused}.png`, `review-dark-clipboard-menu.png`,
`review-light-screenshot-button.png`. Scenarios, stand-ins and the input tool:
`review-tooling/`.

## Polish (2026-09-29)

See `docs/parts/polish.md`.

- Keyboard badge (decision): the current layout's `kxkbrc [Layout] DisplayNames` entry if the user
  set one, else its short name in capitals ("US" on the ThinkPad), also with a single layout;
  hidden only when KWin reports no layout. Nothing writes kxkbrc.
- `fusion-config.sh` gives the widget Meta+N (only when it has no shortcut and the key is free;
  undone by `fusion-restore.sh`). Meta+Alt+S is Plasma's screen-reader toggle. A layout rebuilt
  from System Settings (or `--reset-layout`) creates a new widget without the key; the next
  `fusion-config.sh` run gives it Meta+N again after removing the dropped widget's dead entry.
- Text weights (Font.Bold / Font.ExtraBold) resolve to the static font files: tile titles measured
  within 10 % of the board's ink, no synthetic bold.
- Tray items: the media controller and the other replaced items are hidden by the layout script;
  the expander arrow is with the desktop-cards part.
