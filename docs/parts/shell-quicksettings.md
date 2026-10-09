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
| `EN` keyboard layout badge | 22 px, padding 7, radius 6, 1 px border 18 % | `org.kde.plasma.workspace.keyboardlayout` (KWin) | layout info exists (option: only with 2+ layouts); click = next layout, wheel = next/previous, right-click or press and hold = menu of the layouts (as the stock Keyboard Layout widget) |

The pill also takes the mouse wheel (volume ±5 %) and middle click (mute). Icons are the boards'
line icons (24 px grid, 1.8 stroke) drawn with QtQuick Shapes, with the FileIcons board's level
states (Wi-Fi bars, volume waves, battery fill, charging bolt, 30 % / 10 % warning colours).

**The pop-up** (356 px wide, 10 px under the bar, 16 px from the screen edge, frame = the Plasma
style's `dialogs/background`, so radius, 88 % fill, edge, shadow and blur come from the Plasma style):

* battery chip (`82%`, 34 px, radius 17) and four 34 px round buttons: screenshot (Spectacle's
  rectangular-region shortcut), System Settings, lock, leave (logout / restart / shut down prompt);
* volume slider with mute button and chevron to the output chooser (up to 100 %, or 150 % with
  Plasma's "Raise maximum volume", `plasmaparc` read through plasma-pa's `GlobalConfig`; a volume
  set above the limit elsewhere is kept by a step up, and every wheel or key step counts from the
  real volume, not the slider's clamped value: 140 % steps down to 135 %, ten quick steps to 90 %);
  brightness slider
  (8 px track, 20 px white knob with shadow, `#5B9DFF` fill = colour scheme DecorationHover) of the
  first display (internal panels first), with a chevron when there is more to set: the
  **Brightness** page (`DisplayPage.qml`) has a slider for every display PowerDevil can dim and the
  keyboard backlight (`KeyboardBrightnessControl`, stepping through its levels), as the stock
  Brightness widget; the sliders' wheel, arrow keys and Page Up/Down move at least one step (Left
  and Right follow a mirrored, right-to-left layout), and count as a drag until the input pauses
  (600 ms), so each slider follows its value again after it. With a keyboard
  light and no display to dim (a monitor without DDC/CI), the keyboard backlight's slider takes the
  brightness slider's place;
* microphone/input volume and mute when a recording input exists; its chevron opens the input
  chooser. Sound has Output, Input and Applications tabs. Applications lists active playback and
  recording streams with independent volume, mute and device routing, using the native plasma-pa
  models; it updates when streams start/stop. Virtual microphones such as noise-suppression inputs
  are supported. The existing output controls remain independent;
* six 60 px tiles, radius 16, accent fill when on:
  Wi-Fi (SSID; body toggles Wi-Fi, chevron opens the network list),
  Bluetooth (`N connected` / device name; body toggles, chevron opens the device list),
  Night light (`From sunset`, `Until sunrise`, `From 19:00`, `Paused`, `Off`; toggles KWin's
  Night Light inhibition, turns Night Light on when it is off),
  Do not disturb (`Off`, `On`, `Until 18:00`; same code path as Plasma's own shortcut, with OSD),
  Power mode (`Power saver` / `Balanced` / `Performance`, click cycles; through PowerDevil, which
  uses tuned-ppd on the ThinkPad; `contents/code/power.js`, tested by `tests/power.test.js`). As the
  stock Power and Battery widget: Performance is skipped while the daemon inhibits it, and the
  tooltip says why (on a lap, too hot) and when it may be slower; it names applications holding a
  profile; a refused switch reads `Couldn't switch to …` for 5 s. tuned-ppd 2.28 refuses
  `HoldProfile` ("Invalid bus name"), so holds come from power-profiles-daemon systems),
  Dark style (switches between the two Plasma Fusion Global Themes, see below);
* **Keep awake** (`Off` / `On`): manually blocks sleep, display power saving and automatic screen
  locking until turned off in this session. An accent coffee-cup icon stays in the status pill
  while it is on, including tablet posture; the pill's tooltip explains the active inhibition.
  The tile uses Plasma's native `InhibitionControl`, so the hidden stock battery applet and all
  Fusion controls in the same plasmashell process agree on the manual state. Other applications'
  inhibitors are separate; turning this off leaves those in place. The popup can be closed without
  releasing the inhibition. Manual Lock still works. Normal timeout settings are never rewritten,
  and exiting the session releases the native requests. Missing PowerDevil or ScreenSaver service
  shows `Unavailable` with a disabled tile. Its chevron opens **Sleep blockers**: the applications currently
  requesting to block sleep or idle screen locking, with their reasons, each with an `Allow this
  application's request` box (PowerDevil's `SetInhibitionAllowed`, as in the stock battery applet);
* **Wi‑Fi hotspot** (`Off`, `Starting…`, `On`; otherwise the reason: `Wi‑Fi in use`, `Wi‑Fi is off`,
  `Airplane mode`, `No Wi‑Fi radio`, `Unavailable`, `Failed to start`): plasma-nm's own hotspot
  (`Handler.createHotspot`, the stock Networks applet's code path and its settings in
  `~/.config/plasma-nm`): a WPA2 access point sharing IPv4, as a volatile profile that
  NetworkManager removes when it stops. plasma-nm offers it only on a free radio or while the
  connection runs over something else, so a single radio that carries the connection reads
  `Wi‑Fi in use`; the dimmed tile then opens the Wi‑Fi page, which explains it. A start that
  NetworkManager drops within 20 s reads `Failed to start`. The chevron opens the Wi‑Fi page,
  which also has the **Airplane mode** switch (with a Wi‑Fi radio or a modem): plasma-nm's
  `enableAirplaneMode` and setting, as the stock Networks widget (Wi‑Fi, mobile data and
  Bluetooth off, and back on: the radios that were on are kept for every screen's widget in
  `Instances`, since each plasma-nm handler keeps its own copy, and in each widget's settings
  (`airplaneRestore`) across a plasmashell restart, taken back only while airplane mode is still
  on, else dropped as stale; with no record, airplane mode having started elsewhere, all come back
  on), and the **VPN** connections (plugin VPNs and WireGuard: type `Vpn`
  or plasma-nm's `network-vpn` icon, as WireGuard has no type of its own in plasma-nm's Enums); a
  click connects one, or disconnects the active one (one shutting down shows `Disconnecting…` and
  waits, so a click cannot connect it again). Without a Wi‑Fi radio the tile's chevron
  (`Show VPN connections`, or `Show network options` with a modem alone) opens the page as
  `Network`: the VPN list and the airplane mode switch;
* **Disks & Devices** (device name, or `N devices`; accent while one is mounted), shown while a
  removable device is connected, with a USB-drive icon in the status pill: the stock Disks &
  Devices, which is not loaded where this widget is in the bar (desktop layout and
  `fusion-config.sh`). The data comes from Plasma's `hotplug`, `soliddevice` and
  `devicenotifications` engines (plasma5support, as Plasma 5's Disks & Devices used them; they push
  every change). Listed like the stock default filter: a device whose drive is removable or
  hot-pluggable, a camera or a media player (`contents/code/devices.js`). The page shows each with
  its state (`Not mounted`, `Mounting…`, `X free of Y` with a usage bar, `Removing…`); the row opens
  it (the file manager for a volume, which Solid mounts first, or the device's own action), the
  trailing button mounts it or safely removes it (Solid teardown; a disc is ejected), and the
  engine's own message shows under it (why removing failed and which applications hold the
  device, or that it can now be safely removed). A device plugged in while the session runs opens
  the sheet on this page (`popupOnNewDevice`, as the stock item does); the footer opens the
  Removable Storage settings. The `devicenotifications` engine logs an upstream deprecation notice
  in Plasma 6.7.5 (it still works there);
* media card (64 px, radius 16): album art or player icon, title, `Paused` / artist, previous,
  play/pause (36 px filled), next; shown only while a player exists. The player icon is the
  application icon; when libkmpris cannot read the player's desktop file (it then reports the
  generic `emblem-music-symbolic`), the desktop entry name is used as the icon name. As the stock
  Media Player widget: a seek slider with the elapsed and total time when the player can seek (the
  position is asked for when the sheet opens, when playback starts or stops, when the player or
  track changes, and every second while it plays with the sheet open; the player seeks when the slider is
  let go or the wheel or keys pause, so always on the track playing then; a drag let go on
  another player, title or length is dropped), and,
  with two or more players, a row of their icons to choose one (the first, a star, chooses
  automatically; `Mpris2Model.currentIndex`); a stopped player chosen there keeps the card while
  it can play, so it can be played or another chosen;
* `Notifications` header with `Clear all`, then the notification cards (app icon + name, time,
  summary, body, job progress with Cancel, action buttons; the first action is the accent button
  for critical or persistent notifications, as the board's calendar reminder). Close button on hover.
  Clicking a card runs its default action.

**Drill-down pages** replace the quick settings in the same card (back button, title, switch):
Wi-Fi (Popups board tray panel: connected network card with band, security and live speed,
`OTHER NETWORKS` list with signal levels and locks, inline password field for new WPA/WPA2/WPA3
networks, a `Wi‑Fi hotspot` section with Start/Stop and the reason when the radio can't run one,
the network name and the masked password with Show/Hide while it is on, and `Change name and
password…` (an empty password keeps the saved one, which plasma-nm generates on first use; it is
not read before that), `Hidden network…` and `Network settings`), Bluetooth (paired devices, connect /
disconnect, `Pair a new device…`, `Bluetooth settings`), Sound output (choose the default sink).
A device row's "⋯" button (or right-click, press and hold, the Menu key) opens plasma-pa's own
device menu (`ListItemMenu` with the cards' `CardModel`, as the stock Audio Volume widget): its
ports (speakers, headphones) and the card's profiles (HDMI, analog, Pro Audio, off), shown only
when there is a choice. The Sound page also selects the default input and exposes per-application playback/recording
controls. Empty inputs or streams have explicit placeholders and a Sound settings link.

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
  contents/ui/AudioPage.qml         output and input device chooser, each device's ports and profiles menu
  contents/ui/DisplayPage.qml       brightness of every display and the keyboard backlight
  contents/ui/NotificationCard.qml  one notification
  contents/ui/ConfigGeneral.qml     settings page
  contents/ui/components/           palette, line icons (Icons.js, LineIcon, Network/Volume/BatteryGlyph),
                                    Tile, FusionSlider, FusionSwitch, IconButton, TextButton, ListRow,
                                    PageHeader, FocusRing, FText
  contents/ui/services/             one file per data source, each loaded by a Loader:
                                    Network (plasma-nm), Audio (plasma-pa), Battery, PowerProfiles,
                                    KeepAwake (PowerDevil manual sleep/ScreenSaver inhibition),
                                    Display (brightness, Night Light, light/dark pairing), Media (MPRIS),
                                    Notifications, Keyboard, KdeConnect, Bluetooth (BluezQt), Session, Exec,
                                    TabletPolicy (keyboard policy, on-screen keyboard, rotation lock,
                                    tablet-mode setting, full-screen apps; QS-1; posture
                                    settings: power button, touch edge, TABLET2 P0/N1)
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
* Note: the tray shows its expander arrow while a passive application status icon exists (for
  example the XWayland video bridge, which registers a while after login). The stock items Fusion
  hides are disabled as status notifiers, so they never bring it up, and Disks & Devices is not
  loaded at all. That arrow is the stock tray's and is not on the board.

Widget options (`[General]` of the widget, `contents/config/main.xml`, also in its settings page):

| Key | Default | Meaning |
|---|---|---|
| `showKeyboardLayout` | true | EN badge |
| `keyboardLayoutAlways` | true | badge also with a single layout (the board shows it) |
| `showKdeConnect` | true | phone button while a device is connected |
| `showClipboard` | true | clipboard button |
| `showBatteryPercent` | true | `NN%` in the pill |
| `showNotifications` | true | bell and notification list |
| `popupOnNewDevice` | true | open the sheet on Disks & Devices when a removable device is plugged in |
| `popupGap` | 10 | px between the bar and the pop-up |
| `popupScreenMargin` | 16 | px between the pop-up and the screen edge |
| `startPage` | main | page shown on open: `main`, `wifi`, `bluetooth`, `audio` (settings page: "Page shown when opened") |
| `keyboardPolicy` | tablet | on-screen keyboard (kwinrc `[Wayland] InputMethod`): `tablet` (tablet posture only; the process stops on the laptop), `touch` (always, KWin shows it on a touch), `never` (settings page: "On-screen keyboard") |
| `openRequest` | "" | written by other shell parts: `MODE:NONCE[:OUTPUT]` with `sheet`, `notifications`, `toggle`, `close`; without OUTPUT only the widget on KWin's active screen acts (`MODE NONCE` accepted too) |
| `debugAction` | "" | testing only: `dump:TAG` logs the sheet geometry and scrolling, every visible target with its centre and size, and the tablet policy state |
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

* Manual inhibition regression test (real Qt QML and Plasma's native plugin against private-bus
  endpoints; no live desktop changes):

  ```sh
  QT_QPA_PLATFORM=offscreen dbus-run-session \
    --config-file=packages/kwin/tests/offscreen/session-bus.conf -- \
    python3 packages/plasmoids/org.plasmafusion.quicksettings/tests/keepawake_test.py
  ```

  Needs PySide6, python3-dbus, python3-gobject and PowerDevil's QML module. Checks default-off,
  both inhibitor endpoints, shared native state, preservation of another application's inhibition,
  service disappearance/return and complete release after repeated use.

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

## QS-1 (2026-09-30): tablet sheet, keyboard policy, touch sizes

Work package QS-1 of the one-pass plan (TABLET 4.3 and 4.6, ADAPTIVE 5.3, BACKLOG S2, G18), built by
the lead directly.

### Changes

- **Tablet bar** (TopBar.qml, tablet posture): the status pill 32 px (padding 16, gap 12, icons 18,
  battery % 14 px 800, tabular figures), the bell 44 x 44 (32 drawn, 8 px unread dot), a keyboard
  button (44 x 44, 32 drawn; shown while KWin's on-screen keyboard is available; shows or hides it),
  no EN badge, phone or clipboard (phone and clipboard become 52 px rows in the sheet), Wi-Fi and
  battery only in portrait. Every target covers the bar's whole height (`CanFillArea`); the last
  target keeps the board's 6 px from the screen edge (12 in tablet posture) whatever margin the panel
  has. A 24 px pull-down (TouchScreen) on the pill or the bell opens the sheet.
- **Width budget hooks** (with TOP-2): step 2 moves phone and clipboard into the sheet, step 6 hides
  the battery % (`budgetLevel`, `budgetSaving()`).
- **Sheet** (tablet posture): 400 px wide, 8 px under the bar, 12 px from the edge; in portrait
  min(W − 32, 560), centred (measured: 561 px on the 4/3 grid, centred). Header 44 px (chip radius 22,
  four 44 px buttons 12 apart); a **tablet row** of four 44 px toggles: rotation lock (a lock badge while
  locked), keyboard (show now), full-screen apps (the tablet script's `WindowMode`, applied through its
  shortcut), pen (opens the pen widget's menu; shown while a pen is connected, read from the pen widget
  in the same bar); sliders as 44 px fill bars with relative drag (a tap does not jump); tiles 64 px,
  radius 18, 12 apart; a **Tablet mode** tile (Automatic / On / Off, kwinrc `[Input] TabletMode`) where
  the posture can change by itself or the setting is not automatic; media card 72 px.
- **Touch sizes** (ADAPTIVE 5.3, touch mode = tablet posture or a recent touch): every icon button's
  target at least 44 x 44 (drawn size unchanged), tile chevrons 44 wide, switch 48 x 28, slider knob
  28, notification actions 44 tall (radius 12), the notification close button always shown (32 drawn,
  44 target) beside the time, and a horizontal swipe dismisses a card (40 % of its width or 800 px/s;
  the card follows the finger). A long press on an icon button shows its label.
- **One Flickable** (ADAPTIVE 5.3): the page and the notification list scroll together when they are
  taller than the screen allows; the maximum height comes from the available area (the dock's reserve
  excluded). Before, only the list shrank and the rest was cut off.
- **Keyboard policy** (`services/TabletPolicy.qml`, TABLET 3.3): kwinrc `[Wayland] InputMethod` per
  posture, written with `--notify` only when it differs and only once KWin has reported the posture;
  `VirtualKeyboardMode` is never written. The value is plasma-keyboard's desktop file, looked up once
  at start in the system data directories (`XDG_DATA_DIRS`; `/usr/share/applications` on Fedora, the
  system profile on NixOS; 2026-10-02), with the Fedora path when none has it.
- **Rotation lock** (F14, T19): lock = one `kscreen-doctor output.<o>.rotation.<current>
  output.<o>.autoRotatePolicy.never`; unlock = `autoRotatePolicy.inTabletMode rotation.normal`; leaving
  tablet mode while locked turns the screen back to normal and keeps the lock (plasmafusionrc
  `[Tablet] RotationLocked`); the lock is read back from `kscreen-doctor -j` when the sheet opens in
  tablet posture (outputs with the auto-rotation capability report it).
- **Do Not Disturb for a while** (G18): the tile's chevron offers "For 1 hour", "Until tomorrow" (06:00)
  and "Until turned off"; the time is kept in the notification settings, a timer releases it.
- **Built on demand** (S2): the sheet's content is a `Loader` built 4 s after start, or at once when the
  pointer reaches the bar or anything opens it; the Bluetooth device model exists only while the
  Bluetooth page is shown (the tile keeps using BluezQt's manager).
- **Entry points**: `openRequest` = `MODE:NONCE[:OUTPUT]` (the tablet script's right edge writes
  `sheet:`, Meta+N now writes `notifications:`; fusion-config.sh changed); without an output only the
  widget on KWin's active screen (`activeOutputName`) opens. Meta+A stays the widget's own shortcut.
- **Motion and accessibility**: every animation takes a `Motion` token (the palette carries one; the
  motion lint has no quick-settings findings left); accessible names for the battery chip, album art,
  the Wi-Fi list, notification cards; the settings page's combo boxes take their index from the model.
- **KWin exit crash** (found here, in the KWIN-1 tablet script): the script's destruction handler ran its
  leave step while KWin was quitting, after the workspace was gone (SIGSEGV in
  `WorkspaceWrapper::qt_static_metacall` from `Component.onDestruction`, a private session that ended in
  tablet mode). The script now notes `aboutToQuit` and restores nothing when KWin itself quits; disabling
  the script still restores the windows. Probe `q1p` ended in tablet mode without a core dump.

### Verification

- `qmllint` (Qt 6.11) on the changed files: only the unqualified `i18n*` notes; `a11y-lint` and
  `motion-lint`: no quick-settings findings (five a11y and eleven motion findings fixed).
- Private session `q1a` (1920 x 1200 at 4/3, `build/q1/scen-q1a.sh`), all PASS:
  - T11, three rounds: plasma-keyboard starts 198-206 ms after tablet mode turns on and is gone 41-57 ms
    after it turns off (limits 1 s and 2.5 s); with the default policy the laptop posture empties
    `InputMethod` at start.
  - T6: no target of the bar or the sheet under 44 x 44 in tablet posture (dump of every visible button,
    slider and mouse area).
  - T10: a 16 px pull-down on the status pill does not open the sheet, a 30 px one does.
  - Full-screen apps writes `WindowMode=windowed` and back; Do Not Disturb for 1 hour shows "Until
    <time>" and `plasmanotifyrc [DoNotDisturb] Until`; no Bluetooth device model while its page is hidden,
    one while it is shown, none after closing.
  - T12: portrait sheet 561 px wide (min(W − 32, 560) on the 4/3 pixel grid), centred.
  - T19 (virtual output): the lock runs `rotation.left` + `autoRotatePolicy.never` (exit 0) and the
    rotation stays left; leaving tablet mode turns it normal; unlocking runs `inTabletMode` +
    `rotation.normal`. A virtual output stores neither the rotation nor `autoRotation` in
    `kwinoutputconfig.json` (probe `q1p`), so the stored policy is part of hand check H3.
  - Tablet mode tile: On -> Off -> Automatic -> On with the matching kwinrc values.
- `q1c2` (960 x 600 logical, 12.75 pt, M12): the sheet stays inside the screen (436 px, its maximum) and a
  swipe scrolls page and list together to the end.
- First frame of the sheet (A/B `q1b`, the same timing log in HEAD's package, click on the pill): first
  open 96, 111, 103 ms with QS-1 against 85, 94 ms with HEAD (the pop-up window is created on its first
  show; the settings re-read was moved after the first frame); later opens 5-6 ms in both. The first open
  is about 12 ms slower in these few runs.
- No plasmashell crash; no QML warnings from the widget; the one KWin core dump of a run before the exit
  fix was removed.
- Not in QS-1: a swipe up on the sheet to close it (Esc, a tap outside and the pill close it), the icon
  inside the slider bars (the icons stay beside them), the stretch QS-2.

## Power button in tablet posture (TABLET2 P0, 2026-09-30)

In tablet posture there is no lid, and the X13 Yoga's power button opened Plasma's logout prompt.
Phones and tablets turn the screen off and lock it (research B, item 14: convention, no complaint
data); PowerDevil 6.7.5 ships the same pair as its defaults for touch devices, but picks them only
from the posture at its start (`ProfileDefaults::defaultPowerButtonAction(isMobile)`).
`TabletPolicy.applyPostureSettings()` follows the posture instead:

- Tablet posture: for each PowerDevil profile (AC, Battery, LowBattery) where the user has no value,
  `powerdevilrc [<profile>][SuspendAndShutdown] PowerButtonAction=128` (toggle the screen on and off)
  and `[<profile>][Display] LockBeforeTurnOffDisplay=true`; what was written is recorded in
  `plasmafusionrc [Tablet] PostureWritten`.
- Laptop posture: the recorded keys are removed where they still hold those values (Plasma's
  logout prompt is back); a value the user set meanwhile stays.
- One `bash -c` run per posture change under a `flock`, then PowerDevil's `refreshStatus`.
  fusion-config backs up `powerdevilrc` (rollback).
- The same run sets the bottom touch zone (TABLET2 N1): `kwinrc [ScreenEdges] TouchTarget=20` in
  tablet posture (KWin's 8 px is 1.6 mm on the ThinkPad; iOS about 19, GNOME 20, Android 26 px),
  removed in laptop posture. KWin keeps every touch that starts in a touch edge, and in laptop
  posture an auto-hidden dock reserves the bottom edge too, so laptop taps keep KWin's 8 px.
  KWin applies the value live (`KConfigWatcher`, `recreateEdges()`); only the navigation effect's
  bottom edge takes touch in tablet posture (all `[TouchEdges]` actions are None). Private sessions
  `e8`/`e20` (navigation effect, Konsole, tablet): a swipe up starting 15 px above the bottom does
  nothing with 8 px and goes home with 20 px; `pb3`: the key follows the posture with the power
  button keys. Evidence: `.../2026-10-01-tablet2/N1/touch-zone/`.

Private session `pb1` (PowerDevil not running there; keys only): tablet writes 5 keys and keeps the
user's `Battery` value 1 (sleep); laptop removes them; fold, unfold, fold 1 s apart ends in the
tablet state; a user's `AC` 8 set in tablet posture survives the return to laptop. The press itself
(screen off and locked, a second press wakes to the lock screen) is a hand check on the ThinkPad.
Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-10-01-tablet2/P0/power-button/`.

## Gesture lock and Overview in tablet posture (TABLET2 G1, 2026-10-01)

- **Gesture lock** tile in the tablet row (`tabletRow-gestures`, swipe-up icon with the lock badge while
  on): `TabletPolicy.setGestureLocked()` writes `plasmafusionrc [Tablet] GestureLock` with `--notify`;
  the navigation effect follows it live and holds back a swipe from the bottom edge unless it follows a
  held-back one within 1.5 s, with Plasma's OSD "Gestures are locked: swipe again to go on". The research
  asked for it (8+ iPad threads: the dock swipe cannot be turned off for games and drawing); the second
  swipe keeps a way out without opening quick settings.
- **Overview**: KWin's Overview has a built-in three-finger touchscreen swipe, a second app switcher next
  to the navigation effect's. `applyOverview()` unloads it in tablet posture when the navigation effect is
  loaded and loads it again on the laptop unless `kwinrc [Plugins] overviewEnabled=false`. The dock's
  Overview button opens the tablet app switcher in tablet posture (the effect's "Plasma Fusion App
  Switcher" action), KWin's Overview otherwise.
- Private session g1b: Overview unloaded in tablet posture and back on the laptop; lock on: first swipe
  held back (app stays, OSD), second swipe within 1.5 s goes home, a lone swipe 2 s later is held back;
  lock off: home; the dock button activates `plasmafusion_navigation`.

## TABLET2 S1 (2026-10-01): Notification Centre in tablet posture

Research round 2 (E-phone 4.2/4.3, A-ipad section 5) and the owner's iPad-style decision: in tablet
posture the notifications get their own sheet, apart from the controls, with a setting to keep them
together (the forced split is itself a known complaint).

- **Routing** (tablet posture, `tabletNotifications` = `apart`, the default): the bell (tap or pull-down),
  a pull-down on the clock pill (the clock pill calls `openNotificationCentre()` on the quick settings
  widget in the same bar; a tap still opens the calendar) and `openRequest notifications:` (Meta+N) open
  the **Notification Centre**; the status pill opens the controls sheet without the notification list
  (`Backend.notificationsApart`). `together`: everything as on the laptop. Setting page: "Notifications
  in tablet mode: Own sheet / With the quick settings". The laptop is unchanged.
- **Window** (`NotificationCentre.qml`): full screen, frameless, normal layer, no style background (the
  launcher sheet's pattern), so the top bar stays above it and works; built on first use, then kept.
  It closes itself when another window becomes active, but not while its own card menu is open (it
  takes the activation back when the menu closes).
- **Content** (`NotificationCentreContent.qml`): the Tinted backdrop; landscape = the clock (64 px
  light), the date and a Do Not Disturb chip (tap: off) in a column on the left (28 %, at most 400 px),
  the list on the right (at most 760 px) — never a narrow centred column (A-ipad, MacRumors 2023);
  portrait = one column with the clock above. A **Notifications | Controls** segment (44 px) at the top.
  Cards are the quick settings' `NotificationCard` on a **solid** surface (#1b2031 / #ffffff; E-phone
  4.2 MUST), newest first, with their actions. **Clear all** (44 px pill in the list's corner) hides
  the list for 5 s with **Notifications cleared · Undo**; the clear happens then or when the sheet
  closes. An app with **4 or more** notifications shows as one stack (its newest card, two edges
  behind it, "N more from App"); a tap opens the stack until the sheet closes. **Long press** on a card:
  "No Pop-ups from App" (writes Plasma's own `plasmanotifyrc [Applications][<desktop entry>]
  ShowPopups=false --notify`, the key the notification settings page writes) and "Notification
  Settings…". A sideways swipe on a card dismisses it (the card's own handler). On the zones outside
  the list (clock column, the strip above the list, the right margin) a swipe up (96 px or 800 px/s)
  closes and a sideways swipe (96 px, 2:1) switches to the controls; a tap on empty space or Escape
  closes; invoking a notification closes. Buttons are `AbstractButton`s, which take the press, so the
  backdrop's tap-to-close never fires with them (stacked TapHandlers all fire in Qt).
- **Switching to the controls** waits until the centre's window is gone and 200 ms more: opened at
  once, the controls sheet lost its activation as KWin activated the next window and closed, or drew
  its first frame about 5 s late (sessions s1d-s1h).
- **Top bar**: no tooltips in tablet posture (touch synthesises hover; the bell's tooltip covered the
  sheet).
- **NotificationCard**: `surface`/`edge` colours (translucent in the frosted sheet, solid in the
  centre); every model read goes through `entry?.` — a removed row's card read a null model while it
  was torn down (10 TypeErrors per dismissed notification, also in the laptop sheet's hidden list).

Tests (private sessions, 1920x1200 at 4/3, `build/s1/scen-s1b.sh`, `scen-s1h.sh`; evidence
`artifacts/plasma-fusion/2026-10-01-tablet2/S1/`): bell opens the centre (first frame 68 ms; later
16-50 ms); the Konsole stack of 4 opens on "3 more"; long press shows the menu and the centre stays
when it closes; a sideways swipe dismisses the Dolphin card; Clear all → undo bar → Undo brings the
list back; Clear all → after 5 s "No notifications"; swipe up on the clock column closes; the clock
pill's pull-down opens the centre; the Controls segment, the status pill while the centre is open and a
sideways swipe on the clock column each open the controls (first frame 84 ms, then 5-11 ms); the
status pill's sheet has no notification list; portrait one column; laptop posture: the bell opens the
combined sheet as before; no QML errors.

Not done (queued): pull zones of 56 px at the top corners (the 44 px bar is the pull zone; the bar's
empty spacers have no pull), burst cooldown for repeated pop-ups (Plasma's notification server),
the clipboard tile, the position of Plasma's own notification pop-ups in tablet posture (one appeared
beside the dock in s1j).

## Charge limit tile (2026-10-01)

See `docs/parts/charge-limit.md`: a "Charge limit" tile (limit on/off; chevron: 80 %, 90 %, charge to
100 % once, no limit, Battery settings), `services/ChargeLimit.qml`, set through `pkexec` and the
`org.plasmafusion.charge-limit` polkit action; hidden without the system helper or a battery stop
threshold.

## Notification control and the sheet switch (2026-10-01)

Research E-phone 4.2/4.3. A long press on a card in the Notification Centre reads the app's own
settings (plasmanotifyrc [Applications][<desktop entry>] ShowPopups and ShowInHistory, the keys of
System Settings > Notifications) and offers "No Pop-ups from X" / "Show Pop-ups from X" and "Don't
Keep Notifications from X" / "Keep Notifications from X" (turning one back on removes the key:
Plasma's default), plus "Notification Settings…". `components/SheetSwitch.qml` is the
"Notifications | Controls" switch: on top of the Notification Centre (as before) and now also on top
of the controls sheet in tablet posture while notifications have their own sheet (main page only),
so either sheet reaches the other without closing (backend signal notificationCentreRequested).
Tested in the 6.7.5 container (nc1-nc3): menu read and toggle (key false, label flips), switch both
ways.

## The bell as a corner target (2026-10-01)

Research E-phone 4.2 (edge accuracy 11-12 mm: targets at screen edges at least 56 px). In tablet
posture the bell button also covers the row spacing and the board's end padding after it
(`bellButton.corner`, drawn part `bellButton.core`, `rightPadding: corner`), so its tap and pull-down
target is 60 px wide and runs on to the screen's top right corner (the panel containment keeps its own
last 4 px). Nothing moves on screen. A containmentMask cannot do this: since Qt 6.8, delivery skips an
item whose children stay inside its bounds before asking its mask (`effectivelyClipsEventHandlingChildren`),
so a mask can only shrink a target. Tested in the 6.7.5 and 6.7.91 containers (cor3, cor68): taps at
x 1397/1430/1435 and y 2/22/40 and a pull from the corner open the Notification Centre; the bar is
pixel-identical in both postures. "Clear all" (about 90 x 44) and the home screen's "Done" (96 x 56)
already met the target; a card's close button (44 x 44) is not at a screen edge.

## One quick settings per top bar (owner decision 2026-10-09)

Every screen's top bar has the status icons, the bell and quick settings (the owner chose this over
decision 8's main-screen-only status area: macOS shows its menu bar, with its icons and Control
Center, on every display). Each bar's widget is a separate applet; they know each other through
`ui/global/Instances.qml`, a QML singleton that plasmashell shares between them (it loads all
applets into one QML engine, which the stock notifications applet's Globals relies on too).
- **Leader:** the widget on the lowest screen number (the primary screen is 0), else the first. It
  runs the session-wide jobs: the tablet posture's settings and keyboard (`TabletPolicy.leader`;
  the posture script was already locked and idempotent, so a takeover rewrites the same values) and
  the new-device sheet. When tablet mode ends it reads the rotation lock from KWin's auto-rotate
  policy (another screen's widget may have set it) to turn the built-in display back to normal.
- **The screen in use:** Meta+A belongs to one widget (the main bar's); it asks KWin for its active
  output (`activeOutputName`) and opens the widget on that screen. fusion-config.sh gives the key to the
  main bar's widget only (lowest screen), and the settings module's removal of the other bars moves a
  key held there to it. A widget names its screen from its bar's screen geometry (the window's Screen
  named the first screen for a while in a new bar on another screen). A new device's sheet opens there
  the same way. `openRequest` already acted only on the active screen's widget.
- **One set of settings:** the user settings (`sharedKeys` in main.qml: what the pill shows, the
  pop-up gap, the new-device pop-up, the keyboard policy, the tablet notifications, the light and
  dark themes) are copied from a widget whose settings change to the others; a new widget takes the
  settings of the leader there before it (also when it leads at once, as the primary screen's
  bar made again does), and pushes nothing before that (while it loads its settings change too, and
  pushing those defaults reset the others: found by the two-screen test). A value equal to the
  default is not stored, so a script reads it as empty.
- Disks & Devices reads the engine's devices once when it is created (`Devices.qml`): a widget made
  after the engine knew its devices (the second bar's) listed none before.
- Notifications pop up once: the stock Notifications applet in every tray shares its Globals (one
  pop-up manager).
- Test (archhost parity VM with a second virtio GPU, two outputs; `two_screens_test.py`,
  `devices_route.sh`): 20 checks and 4 routing checks: a bar per screen with tray and quick settings, the
  pen only in the main bar, the tray's item lists copied, the shared singleton and the primary
  screen's leader, idempotent re-runs, a removed tray stays removed, a new screen's bar complete,
  the settings page's removal keeps the main bar, `EveryScreen=false` adds nothing, settings synced
  both ways and adopted by a new widget, posture settings written once per change, Meta+A and a USB
  stick open the sheet on the screen with the pointer only (both screens), bars made before the
  change completed at login (two reboots), no QML warnings, no crashes.
