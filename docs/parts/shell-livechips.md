# Part: live chips (`org.plasmafusion.livechips`)

<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

At the start of the top bar's right cluster (LiveChips board, number 26): what uses the
microphone, the camera or the screen, who controls this computer or has signed in to it over SSH,
and what runs on its own (a screen recording, a timed Keep awake). With nothing in use the widget
is hidden and the bar is as without it. Queue item 6 of the 2026-10-14 feature report; the owner
chose the board's proposal on 2026-10-16 (glyphs in a capsule, app names in the panel only, the
start of the right cluster, recording and Keep awake chips). Plasma 6 applet, QML only,
GPL-2.0-or-later.

Status: new in the release after 0.5.0. Last edited 2026-10-16.

## Files

| Path | What |
|---|---|
| `packages/plasmoids/org.plasmafusion.livechips/metadata.json` | Plasma/Applet metadata (no settings page) |
| `.../contents/ui/main.qml` | the sources, the chips (compact representation), the panel (full representation), hidden when nothing is in use |
| `.../contents/ui/ChipRow.qml` | the chips in the bar: Keep awake, a recording, the privacy capsule |
| `.../contents/ui/InUsePanel.qml` | the panel: a row for each app or login, its action, Application permissions |
| `.../contents/ui/LineIcon.qml` | the board's 24-unit line glyphs (the pen menu's component) |
| `.../contents/ui/Island.qml` | the island (board Island.dc.html): its window, its black shape and bubble, compact, opened and full-screen |
| `.../contents/ui/IslandPart.qml` | the island's compact parts: leading (the app, the red dot, the cup, the cover) and trailing (the dots, the times, the levels) |
| `.../contents/ui/IslandOpened.qml` | the opened island: the apps with Mute, Stop sharing or End; a recording with Stop; the music with its controls |
| `.../contents/ui/sources/Media.qml` | the music playing: the MPRIS multiplexer quick settings follows (a Loader: optional) |
| `.../contents/ui/sources/FullScreen.qml` | whether the screen's active window is full screen (libtaskmanager's IsFullScreen) |
| `.../contents/config/main.xml` | `barHidden` (written by the tablet KWin script) and the test hook `islandRequest` |
| `.../contents/ui/sources/Microphone.qml` | plasma-pa's recording streams (loaded with a Loader: optional) |
| `.../contents/ui/sources/Camera.qml` | kpipewire's camera monitor, and `pw-dump` for the apps (a Loader: optional) |
| `.../contents/ui/sources/StatusItems.qml` | the portal's and Spectacle's status items over D-Bus, their End and Activate |
| `.../contents/ui/sources/RemoteLogins.qml` | systemd-logind's remote sessions (system bus) |
| `.../contents/ui/sources/KeepAwake.qml` | quick settings' timed Keep awake, read from its widget in the same bar |
| `.../contents/ui/sources/Exec.qml` | runs `pw-dump` (the executable engine; quick settings' Exec) |
| `.../contents/code/chips.js` | what the chips show from what the sources report (no QML; node tests) |
| `.../tests/chips.test.js` | the code's tests (CI `build`) |
| `.../tests/chips_qml_test.py` | the QML's offscreen tests (CI `build`) |
| `.../tests/fake_status_items.py` | stand-ins for the portal's and Spectacle's status items (session tests) |
| `.../tests/fake_watcher.py` | a stand-in status notifier watcher and its items, for the QML tests (a private bus) |
| `.../tests/vsession/scenario-livechips.sh` | the session test |
| `tools/build.d/76-livechips.sh` | stages the package with the shared QML blocks it uses; checks that it logs through its category |

## What it shows

| Chip | Source | Glyph colour | Action |
|---|---|---|---|
| Microphone | plasma-pa's `SourceOutputModel`: every stream that is not virtual, while a microphone exists (plasma-pa's MicrophoneIndicator rule); the app is the stream's client name, else its name | ForegroundNeutral | the panel's **Mute** / **Unmute**: the app's own stream (other apps keep the microphone) |
| Camera | kpipewire's `MediaMonitor` (role Camera; the same as Plasma's camera indicator) for "in use" and the camera's name; `pw-dump` gives the video streams linked from a camera and their apps, when a camera starts, 1.5 s later and every 10 s while one runs (an app that starts or stops reading a running camera changes no node's state) | ForegroundPositive | none |
| Screen sharing | xdg-desktop-portal-kde's "Screen casting" status item (icon `media-record`, id `xdg-desktop-portal-kde`); the app from its tooltip, a window or the screen from its overlay icon | ForegroundVisited | **Stop sharing**: the item's menu action End (`Session::close`) |
| Remote control | the portal's "Remote Control" item (icon `krfb`); the app from the tooltip's first line, the pointer and keys or the screen from its lines | ForegroundNegative | **End**, as above |
| SSH | systemd-logind: sessions with `Remote=yes` (any user) that are not closing; `sshd` and `tailscaled` read as SSH, others as a remote login | ForegroundLink | none |
| Recording | Spectacle's recording item, known by its tooltip title ("Spectacle is Recording", or "Spectacle is Recording with Sound" when Spectacle 6.8 records sound; its id is Spectacle's translated name); the time is Spectacle's own (`KFormat`, `0:42`); while it renders, no chip | ForegroundNegative on its tint | the round button: Activate (Spectacle's `finishRecording`) |
| Keep awake | quick settings in the same bar: its widget's `keepAwakeUntil` (a timed Keep awake's end, else 0); "until turned off" has no chip (the status pill shows its cup) | text colour | a click opens quick settings on its Keep awake page (`openRequest` `keepawake`, with that widget's output) |

A status item is read again on each of its signals (Spectacle's tooltip changes every second). A
reply that comes after its item unregistered is dropped (`chips.js` `readStarted()`: a token per
registration), so an item gone while it was read leaves no chip.

Names that come from other apps and from logins (an app's name, a user, a host) and Spectacle's
time are shown as plain text, never read as markup.

The apps' messages are translated, so every message the chips read is matched against the same
message from the sending app's own catalogue (`i18ndc` with `xdg-desktop-portal-kde` or
`spectacle`) with a marker in place of its argument (`chips.js` `argument()`): any language works
as long as both use the same translation.

The privacy kinds share one capsule, left to right remote control, screen sharing, camera,
microphone, SSH (the most serious first); one kind tints the capsule with its badge tint, several
share a neutral one. Then the recording chip and, leftmost, Keep awake. Sizes (board): chips 22 px
high, radius 11, 6 px apart, glyphs 14 px, figures in Space Grotesk 600 12 px; the panel is the
Popups board's (360 px with its frame, rows 48 px, radius 12, 30 px badges, 28 px buttons). Every
size that holds text goes through FusionMetrics (the user's text scale). The badge tints are the
Colors board's; the glyphs take the colour scheme's semantic colours (the light scheme's
ForegroundLink, #2359c4, is a little darker than the board's #2f6fdf: the scheme decides).

The panel opens from the capsule (a click, or the widget's shortcut if the user gives it one) and
closes when nothing is left in it; on hover it shows as the capsule's interactive tooltip. From the
keyboard, Tab reaches the Keep awake chip, the recording's stop button and the capsule, and Space or
Return runs each, as the panel's buttons. Application permissions (System Settings, `kcm_app-permissions`)
shows only where flatpak-kcm installed it.

Hover and click share the same 328 px content width (the board's 360 px including its frame,
scaled with the text). The panel is an Item with an explicit implicit width and the layout's
implicit height: Plasma's tooltip reads these sizes, not the Layout attached hints used by the
clicked representation. Using a bare ColumnLayout let the tooltip shrink to its narrowest controls,
hiding most of the application name and resource. Long names and resource descriptions wrap; rows
keep their 48 px minimum but grow for the text. The two views still use the same live sources and
actions, including changes while the tooltip is open.

## In the bar

The layout script puts the widget right before the tray in every top bar it makes, and the tray
hides the items it replaces (`TRAY_ITEMS_REPLACED_BY_CHIPS`: `plasmashell_microphone`,
`org.kde.plasma.cameraindicator`, `xdg-desktop-portal-kde`, `Spectacle`) in `hiddenItems` and
`disabledStatusNotifiers`, as with the items quick settings replaces. They stay loaded: the volume
applet still makes the microphone item, and the camera indicator still runs; only the tray shows
them nowhere. `ensure-topbars.js` and the "Add Panel" top bar do the same, also in a tray they
copy from another bar (one the user shows again there is hidden next to the new bar's chips), and
the build checks that the three lists agree. The package jobs' import check (`tools/tests/packages/qml-imports.sh`)
counts the microphone and camera sources as optional, as they are loaded with a Loader: without
plasma-pa or kpipewire those chips are simply missing. An existing layout gets the widget from the setup once
(`fusion-config.sh` migration step 7, recorded in `plasmafusionrc [Setup] LiveChips`; device.md).

A status item's id is its program's display name: plasmashell's has none, so plasma-pa's item is
`plasmashell_microphone`; the portal's is `xdg-desktop-portal-kde`; Spectacle's display name is
translated, so in a language that translates it the tray keeps showing Spectacle's item next to
the chip (the chip finds Spectacle's item by its tooltip, not its id).

## Debug output

`QT_LOGGING_RULES="org.plasmafusion.livechips.debug=true"` makes the widget log what the chips
show (`livechips: state`), where they are when a chip comes or goes (`chips at`), the panel's rows
and buttons, the status items and the other sources. The session test reads these lines (its seed
sets the rule). By default the widget logs only failures (warnings), so a recording's every second
reaches no journal.

## Tests

- `tests/chips.test.js` (node, CI `build`): the capsule's order and tint, the board's glyphs and
  tints, the argument of a translated message (Spectacle's two lines, a pattern with text after
  the argument, a message of another shape), the portal's two kinds, logind's sessions (remote,
  not closing, oldest first; Tailscale SSH is SSH), the apps reading a camera from a `pw-dump`
  graph (a screen-cast source and an audio stream are not the camera), Keep awake's time left.
- `tests/chips_qml_test.py` (offscreen Qt on a private bus, CI `build`, 66 checks):
  - the camera source with a stand-in camera monitor and `Exec`: no `pw-dump` without a running
    camera; its reader; an app that starts or stops reading the running camera seen at the next
    look; none once it stops;
  - the chips from the keyboard: Tab and Space or Return on the Keep awake chip, the stop button
    and the capsule;
  - names with markup in the panel (an app, a login) and in Spectacle's time, shown as plain text;
  - the status items, with Plasma's D-Bus module and `fake_watcher.py`:
    - an item that unregisters while its properties are read is not shown when the reply comes
      after, while one that stays is shown and goes when it unregisters;
    - a recording's time runs on with nothing logged;
    - a recording with sound (Spectacle 6.8's title) shows its time too;
    - with the widget's debug output on, the lines the session test reads are there.
- `tests/privacy_hover_test.py` (offscreen Qt with the real Plasma tooltip, CI `build`): hover and
  click have equal content width; Sound Recorder and Microphone are readable without clicking;
  long names wrap as plain text; mute state, newly active resources and stopped resources update
  both views while shown. CI also runs with a 15.6 pt UI font (the supported 1.6 text scale).
- `tests/vsession/scenario-privacy-hover.sh`: real hover and click screenshots in an isolated
  Plasma session, with a private PipeWire/Pulse server and only a virtual microphone. The hover
  card's Mute/Unmute must change that stream, and stopping it must remove the indicator. No
  hardware microphone or camera is opened.
- `tools/build.d/76-livechips.sh`: the widget logs only through its category (`console.debug(log,
  ...)` and `console.warn(log, ...)`).
- `packages/look-and-feel/tests/layout.test.js` (node, run by the look-and-feel build): the chips
  right before the tray in every new bar, their items hidden; nothing without the widget;
  `ensure-topbars.js` with the main bar's chips (a new bar, an older bar with its own tray: at the
  tray's place, that tray hiding their items; the tray copied from the main bar hiding them too),
  without them (the copy as the main tray), a first bar, and two screens with no bar (both bars
  get them); the "Add Panel" top bar that copies
  another bar's tray hides their items too, and copies it as it is without the widget.
- `tools/device/tests/layout-migration-unit.sh` (CI `build`): step 7 adds the chips before the tray
  of every top bar with distinct ids and hides their items there, once; a bar that has them before
  its tray is left; a widget that a stopped run left out of the bar's order is put before the tray
  (not added again); nothing without the widget; the setup's list is the layout script's; a real run writes
  them; in one run with steps 4 and 6 it keeps what they queued (the pen menu in the bar's order,
  the other hidden items); the once-only marks are not written after a migration that stopped.
- Session test (`tests/vsession/scenario-livechips.sh`; 2026-10-16, private sessions on the Fedora
  44 test laptop, Plasma 6.7.5, 1440x900; quick settings' stand-in PowerDevil, a private PipeWire
  with a virtual source; the widget's debug output on): **15 checks pass**:
  - the setup puts the chips right before the tray;
  - the harness's own SSH login shows the SSH chip, tinted;
  - a timed Keep awake shows "25 min", and a click opens quick settings' Keep awake page;
  - Spectacle's recording (stand-in) shows its running time, and the chip's button finishes it;
    while the time runs on (3.5 s), the state is logged each second and the chips' places are
     not logged again;
  - screen sharing and remote control (stand-ins) give the neutral capsule; hover shows the panel
    as a tooltip and a click opens it; Stop sharing and End end them (the item's menu End);
  - `parecord` as "Zoom" shows the microphone, the panel's Mute mutes its stream, and the chip goes
    when it stops. Meanwhile the watcher lists plasma-pa's item with the id
    `plasmashell_microphone`, the one the tray hides, and the screenshot shows no microphone item
    in the tray (an observation, not a check).

  The earlier runs of the scenario were red where the widget was wrong: a property named `left` (an
  anchor line in Qt 6.11) kept the widget from loading, and Stop sharing and End failed until the
  menu event's data was a plain string (the D-Bus module marshals no wrapped `int32` in a variant).
  The hover check failed now and then (2026-10-17, one run in three) where the test was wrong:
  step 3's click left the pointer on the bar, the capsule came up under it, and Qt Quick opened
  the tooltip before the step's mark (Qt 6.11 `QQuickDeliveryAgent` hovers at the last pointer
  position each frame items change), so the log after the mark had no new hover line. The pointer
  now leaves the bar before the mark.

In a test container (`tools/vsession/cvsession.sh`, the depth suite's beta lane) there is no
system bus and so no logind: the first check there is that the widget says it has no logind and
shows no SSH chip, and step 4's capsule and panel come without the login (the scenario knows the
lane from podman's `/run/.containerenv`).

Not verified: the camera in a session (that would turn on the test laptop's own camera; the
monitor is Plasma's own and `pw-dump`'s parsing has its tests), a real portal session and a real
Spectacle recording (stand-ins with the same properties), Plasma 6.8, other text scales.

## The island (2026-10-17)

The owner's request of 2026-10-17: with the top bar hidden (the settings page's "Hide the top bar
automatically", docs/parts/kcm-cpp.md), a "dynamic island" in the middle for the privacy
indicators, after Apple's design (board `design/boards/Island.dc.html`; the owner approved its mock
on 2026-10-17). Apple's Human Interface Guidelines (Live Activities) give its grammar: one thing
shows compact, a leading part that names it and a trailing part with its state, read as one;
several show minimal, the second detached in a bubble; touching it opens it in place, an enlarged
version that keeps the parts where they were; opaque black in light and dark, bold colours, a key
line over dark content. iPhone shows the camera's and microphone's dots inside it.

- **When.** While the tablet KWin script reports the bar of this screen hidden (`[General]
  barHidden`, docs/parts/kwin-tablet.md, "The top bar for the island") and something is going on.
  The bar coming back (the pointer at the top of the screen) fades it out; it comes back when the
  bar hides. Off, in tablet posture (the bar always shows) and with nothing going on: no island.
  Its own sources (the music, the full-screen window) load only while the bar is hidden, so nothing
  runs for them with the switch off (the default).
- **What** (`Chips.island()`): the privacy kinds always first, then a screen recording, a Keep awake
  timer and the music playing; the first two show, the second in the bubble. In a full-screen window
  (`sources/FullScreen.qml`) only the privacy kinds, as 6 px dots in a 14 px capsule; the pointer on
  them shows the compact island (until the pointer leaves or full screen ends). A screen is full
  screen while its last activated window that is not minimized is (`Chips.fullScreenOf()`, the task
  manager sorted by activation), also with another screen's window focused. Notifications, the
  clock and file copies are not in it.
- **Plasma's notices** (2026-10-17, the owner's option B; the board's "volume, brightness and
  Plasma's notices"): while the bar is hidden, what Plasma's own pop-up would show (the volume, the
  microphone, a player's volume, the screen and keyboard brightness, the keyboard layout, the
  touchpad, the power mode and the rest) shows in the island, and Plasma's pop-up does not. Plasma's
  pop-up is compiled into plasma-workspace (6.7.5 loads it from the QML module
  `org.kde.plasma.workspace.osd`), so a theme cannot change it; but every notice goes through
  plasmashell's Osd object, which also sends it on D-Bus (`/org/kde/osdService`:
  `osdProgress(icon, percent, maximum, text)`, `osdText(icon, text)`, shell/osd.cpp), and its
  window is a new KWin window each time it shows. `sources/Osd.qml` (loaded while the bar is hidden)
  listens to the two signals; the tablet KWin script, when that window comes up on a screen whose
  island is there, makes it transparent and asks that screen's island to show the notice
  (`[General] noticeRequest`, docs/parts/kwin-tablet.md): the one that just came (Plasma sends it
  before it shows its window), and the ones that follow while it shows, for Plasma's own 1.8 s
  (`OsdItem.qml` timeout) after the last. `Chips.notice()` makes the view: the board's glyph for
  Plasma's icon name (`Chips.NOTICE_GLYPHS`; the speaker, crossed out for `audio-volume-muted`; the
  microphone; the sun; the keyboard light; and the board's "other notices", each its glyph crossed
  out when off: the keyboard for the layout, the touchpad, the gauge for the three power modes, Do
  Not Disturb's bell, Night Light's moon (KWin 6.7.5 sends `redshift-status-day` when it resumes by
  day), the on-screen keyboard, Keep awake's cup for sleep and screen locking blocked, the clock for
  the time zone; plasma-pa's `-symbolic` and `-rtl` forms of a name, which its notice for a new
  output device uses (`audioicon.cpp`), are the same icon), else Plasma's icon itself (a player's;
  an output device's kind, push to talk, notification history cleared); a level fills the 96 px bar
  to Plasma's maximum (150 % for the volume past 100) with a tick at 100 % past it, in white to 100,
  the warning colour to 125 and danger past it (osd.cpp's steps), with Plasma's label for it before
  the bar in the island's second colour (one screen of several, whose name Plasma gives; a player);
  a text is Plasma's, its lines in one with " · ". A notice takes the island while it shows
  (`Chips.island()`), also over a full-screen window, then it shows what it did; an island opened by
  a click stays as it is (the notice is not shown); a click on a notice opens nothing, and a screen
  reader reads it as what it says ("Volume 60%", static text, not the island's button); no key line.
  With the bar shown, on a screen without an island, with the tablet script off, and with Plasma's
  pop-up turned off (plasmarc `[OSD] Enabled`: it sends nothing then), Plasma's pop-up as before.
  Plasma 6.7.5 never shows a Wi-Fi, Bluetooth or mobile-internet notice (nothing calls those), so
  the island has none.
- **Compact** (`IslandPart.qml`): 32 px high, radius 16, at least 132 px wide, 6 px margins; the
  privacy kinds: the first app's icon (its name as an icon name, `Chips.iconGuess()`; the kind's
  glyph when the theme has none: Kirigami 6.31's `Icon.valid` only says a source is set, so its
  `status` says whether the theme has it, and the icon stays shown, only transparent, until then,
  as Kirigami loads an icon only once it is shown; on the ThinkPad's session a login and an app
  without an icon showed Kirigami's "unknown" icon before, 2026-10-17) and an 8 px dot for each
  kind; a
  recording: the red dot in its
  tint and its time; Keep awake: the cup and the time left; the music: its cover (radius 6) and
  four level bars in the cover's orange (still: the motion lint allows no endless animation).
- **Opened** (`IslandOpened.qml`, a click on the island or the bubble; Keep awake opens quick
  settings' page instead): 400 px wide (at most the screen's width less 8 px on each side), radius
  28, 14 px margins, on the screen (4 px from its top and 24 px above its bottom at most: the rows
  scroll beyond that). A row for each app or login (`Chips.islandRows()`: an app's kinds in one row,
  the most serious first) with its icon, the dots and what it uses, and the action of its most
  serious kind: End, Stop sharing, Mute or Unmute (the panel's own actions; an app's microphone
  streams together: Mute while any of them records, for all of them). A recording: its time and
  Stop. The music: cover, title, artist and player, where it is (read again every second while
  opened) and previous, play or pause, next; paused there, the music stays while its view is open
  and its player is there, so Play is there. It takes the keyboard focus while opened (Esc closes
  it), and a click outside it or on its free part closes it.
- **Colours** (`Chips.ISLAND_COLOURS`): the island is black in both schemes, so its glyphs and dots
  take the dark scheme's semantic colours (PlasmaFusionDark.colors: ForegroundPositive for the
  camera, -Neutral the microphone, -Visited the screen, -Negative remote control and a recording,
  -Link SSH), white text, and over a dark theme a 1 px key line in the leading part's colour.
- **The window.** A Plasma Dialog of type CriticalNotification, 4 px from the top of its screen
  and centred on it (the bubble's room on both sides keeps it centred). KWin keeps the place it
  asks for and stacks it above full-screen windows; an OnScreenDisplay window would not do: KWin
  6.7.5 places those itself, two thirds down the screen (`Placement::placeOnScreenDisplay`). It
  takes no focus until opened (its flags; libplasma 6.7.5 passes them on to KWin as the surface's
  takes-focus). The black shape morphs between its sizes inside the window (the Motion tokens'
  surface duration), and the window keeps the larger size until a morph has ended, so it is not
  resized on every frame. The frame's size and the window's place are bound again whenever the
  focus changes: the Dialog sizes its main item to the window when the window is resized from
  outside (a change of flags can give it the platform's last size back), which in Qt 6 ends the
  main item's size bindings (a CI run of the QML test caught it).
- **Test hooks.** Debug output `livechips: island compact privacy at X,Y WxH; bubble ...` (or
  `none`; a notice: `compact notice (speaker 60 plain) at ...`) once a morph has ended;
  `[General] islandRequest` "open:NONCE" or "close:NONCE".
- **Tests.** `tests/chips.test.js`: the island's content (nothing, a call, a call and music, four
  things, without a privacy kind, music alone, full screen with and without one), its colours, the
  opened rows (one row for Firefox's screen, camera and microphone with Stop sharing, remote control
  first with End, a muted app with Unmute, a login without action, a camera known by its name only)
  and the icon names; Plasma's notices: the glyph for each of Plasma's icon names (the volume, the
  microphone, the brightness, the keyboard layout, the touchpad, the power modes, Do Not Disturb,
  Night Light by night and by day, the on-screen keyboard, sleep blocked, the time zone), crossed
  out in each of plasma-pa's forms of a muted name, Plasma's own icon for a name without a glyph
  (and for one an object has of its own, `toString`), every notice's glyph as the Island board
  draws it (one state of each, the other with its crossing line or without), the bar's fill
  and the tick for 60 of 100 and 115 of 150, white, warning and danger at 100, 101, 125, 126 and
  150, the bar never more than full nor less than empty, a level keeping Plasma's label, Audio Muted
  and several screens' brightness in one line, and the notice taking the island during a call, over
  a full-screen window and with nothing else. `tests/chips_qml_test.py`: the island's QML in its own
  window, offscreen at 1440 x 900: shown while the bar is hidden and gone when it shows, 4 px from
  the top, 32 px high and at least 132 wide (at the test's text scale), centred; an app with an icon
  in the theme (KWin, from hicolor) leads with it, one without with the camera's glyph (the test
  gives Qt the system's icon themes: offscreen it looks only in `:/icons`); the bubble 6 px beside
  it with the island still centred and both inside its window; opened 400 px wide and centred, where
  a real click on Mute asks the app's microphone to mute and Esc closes it; the window resized from
  outside while it opens and once it has opened, it still opens to its size and centred; five apps
  at once give five rows, twelve on a screen 400 px high stay on it and scroll; the full-screen dots
  14 px high, the pointer on them shows the island and full screen coming back shows the dots again;
  Plasma's notices: a volume level compact and centred with the speaker, the bar 60 % full and 60 in
  white, no key line, read as "Volume 60%" and not as a button, 115 of 150 with the tick and the
  warning colour, 130 in danger, one screen of several with its name before the level, Audio Muted
  without a bar, Do Not Disturb with the island's crossed-out bell and not Plasma's icon, a click
  opening nothing, the notice during a call and the call back after it (a
  button again); and `sources/Osd.qml` on the private bus, the test being plasmashell sending its
  Osd's signals: a notice before KWin asks is not shown, after the request it is, the next one takes
  its place, a text arrives as its words, the same one again keeps it 1.8 s from then and it goes
  after, a request with no recent notice shows nothing old and one just after it shows. Mutations of
  each (8 px from the top, no room for the bubble, shown with the bar, 300 px opened, no Esc, Mute
  doing nothing, no binding again after the focus, the peek kept, the icon chosen by `valid`, the
  glyph always; a notice shown unasked, kept for good, or an old one shown; the notice not taking
  the island, one tone for all; step one's glyphs alone, a name's `-symbolic` or `-rtl` kept, a
  lookup that takes an object's own names, Night Light by day without its moon, sleep unblocked
  not crossed out, a glyph not the board's) fail it or `chips.test.js`.
- **Session** (`packages/kcm-cpp/tests/scenario-island.sh`; 2026-10-17, a private session on the
  Fedora 44 test laptop, Plasma 6.7.5, 1440 x 900, the stage, module and kcmctl of this change;
  stand-in status items): **31 checks pass**. The switch on: the bar's panel hides, KWin hides its
  window and the tablet script sets the chips' `barHidden`; the harness's own SSH login is in the
  island; screen sharing: compact, 4 px from the top and centred (654,4 132x32); opened in place and
  centred (520,4 400x148, the window KWin configured the same); closed; a recording too: the bubble
  6 px beside it, the island still centred; Plasma's notices through plasmashell's real osdService
  (`volumeChanged`, `showText`, as the volume keys reach it): the volume's level in the island,
  centred (629,4 182x32), Plasma's pop-up window there with opacity 0, Audio Muted, Do Not Disturb
  (`showText` with its icon) with the crossed-out bell (639,4 163x32) and the touchpad turned off
  (`touchpadEnabledChanged`) with the crossed-out touchpad, and 1.8 s after them the call and the
  recording again (a red run with the tablet script not hiding the window
  fails the opacity check); the pointer pushed against the top: the bar shows and the island goes,
  and Plasma's pop-up shows as it is (opacity 1); the pointer down through the bar and away: the bar
  hides and the island is back; the tablet KWin script turned off: no island left (a red run
  without its last call keeps the island), Plasma's pop-up as it is, on again: back; tablet
  posture: the bar shows, no island; laptop again: hidden, the island back; off: the bar shows, no
  island. The screenshots match the board (compact with the app and its dots, the opened rows, the
  bubble, the volume's level, Audio Muted and Notifications Off, taken with the notice sent again
  every 0.4 s, as a key held down: a screenshot takes longer than 1.8 s).
- **Found in the session** (each fixed): with `Qt.WindowStaysOnTopHint` libplasma 6.7.5 makes a
  Dialog a Dock (`DialogPrivate::applyType`: a panel whose windows go below, under full-screen
  windows), so the island has no such flag. Taking the focus at once when it opened kept the
  compact size: KWin activates the window and configures it with the size it has then, and Qt
  takes that size; the island takes the focus once its window has the opened size. Pushing the
  pointer against the edge needs a second push 75 to 350 ms after the first (KWin's
  ElectricBorderDelay and ElectricBorderCooldown), as a person's pointer does.

Not verified: a real camera or microphone in the session (stand-ins; the chips' own session test
covers the microphone), the music (no MPRIS player in the session; `sources/Media.qml` is quick
settings' source), a full-screen window in the session (`FullScreen.qml` reads libtaskmanager's
role; the dots are in the QML test), Plasma 6.8, other text scales.
