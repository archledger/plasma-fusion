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
| `packages/plasmoids/org.plasmafusion.livechips/metadata.json` | Plasma/Applet metadata (no settings) |
| `.../contents/ui/main.qml` | the sources, the chips (compact representation), the panel (full representation), hidden when nothing is in use |
| `.../contents/ui/ChipRow.qml` | the chips in the bar: Keep awake, a recording, the privacy capsule |
| `.../contents/ui/InUsePanel.qml` | the panel: a row for each app or login, its action, Application permissions |
| `.../contents/ui/LineIcon.qml` | the board's 24-unit line glyphs (the pen menu's component) |
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
- `tests/chips_qml_test.py` (offscreen Qt on a private bus, CI `build`, 24 checks):
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

In a test container (`tools/vsession/cvsession.sh`, the depth suite's beta lane) there is no
system bus and so no logind: the first check there is that the widget says it has no logind and
shows no SSH chip, and step 4's capsule and panel come without the login (the scenario knows the
lane from podman's `/run/.containerenv`).

Not verified: the camera in a session (that would turn on the test laptop's own camera; the
monitor is Plasma's own and `pw-dump`'s parsing has its tests), a real portal session and a real
Spectacle recording (stand-ins with the same properties), Plasma 6.8, other text scales.
