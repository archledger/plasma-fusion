# Part: system meters in the top bar (`org.plasmafusion.meters`)

Optional compact meters for the processor load, the memory in use, the download and upload rates
and the processor temperature, in one pill drawn like the quick settings status pill (Main /
MainLight boards `<header>`), with a small pop-up for a few more values and System Monitor. The
0.5.0 answer to the survey's F2 (`artifacts/plasma-fusion/2026-10-11-improvement-survey-3`,
sources C-macos.md and D-windows-gnome.md: Stats is the most-installed Mac utility, 143k Homebrew
installs a year; GNOME's Vitals, system-monitor, Freon and NetSpeed have over 6M downloads).
Plasma 6 applet, QML only, GPL-2.0-or-later.

Status: built, tested offline (node, PySide6 on libksysguard) and in a Fedora 44 / Plasma 6.7.5
test VM, dark and light. Last edited 2026-10-11.

## Files

| Path | What |
|---|---|
| `packages/plasmoids/org.plasmafusion.meters/metadata.json` | Plasma/Applet metadata (horizontal, vertical, desktop), "Plasma Fusion System Meters" in Add Widgets |
| `.../contents/config/main.xml`, `config.qml`, `ui/ConfigGeneral.qml` | settings (below) and their page |
| `.../contents/ui/main.qml` | the pill, the meters, when the sensors run, the width budget hooks, the pop-up window, the test hooks |
| `.../contents/ui/Readings.qml` | the sensors (`org.kde.ksysguard.sensors`), each subscribed only while it is needed |
| `.../contents/ui/MetersPopup.qml` | the pop-up's content |
| `.../contents/ui/LineIcon.qml`, `FusionText.qml` | line glyphs on the 24 grid and board text (copies of quick settings' and the clock pill's) |
| `.../contents/code/meters.js` | formats, limits, the update interval (no Qt; node tests) |
| `.../contents/code/glyphs.js` | the meters' line glyphs |
| `.../contents/code/memory.js` | the pop-up's memory figures in binary units (the same file as the system card's) |
| `.../tests/meters.test.js` | node tests of `meters.js` (not installed) |
| `.../tests/memory.test.js` | node tests of `memory.js`, and that the system card's copy is the same (not installed) |
| `.../tests/readings_test.py`, `tests/mock_ksystemstats.py` | PySide6 test of `Readings.qml` on the real sensor module against a stand-in ksystemstats on a private bus (not installed) |
| `.../tests/vm_meters.py` | test tool for a real session: add or remove the widget, write keys, dump, measure plasmashell's CPU, busy loops, light/dark |
| `tools/build.d/77-meters.sh` | checks the metadata, the config XML and the settings page's keys, runs the node tests when node is installed, stages the package with the shared QML blocks it uses (FusionMetrics, Motion, FusionTablet, FusionAccent) |

## Turning it on

Nothing changes for current users: the widget is in no layout, and the layout scripts never add
it. Two ways to put it in the top bar:

- **Plasma Fusion settings** (System Settings > Plasma Fusion): "System meters in the top bar".
  Apply adds the widget right before quick settings in every top bar (and removes it when the
  switch is turned off); see `docs/parts/kcm-cpp.md`.
- **Add Widgets** (right-click the top bar > Add Widgets, "Plasma Fusion System Meters"), then
  drag it where it should go.

Added, it shows the processor and the memory; the network and temperature meters are turned on in
its settings (right-click > Configure System Meters).

### Settings (`[General]`)

| Key | Default | Meaning |
|---|---|---|
| `showCpu` | true | processor load in percent (`cpu/all/usage`) |
| `showMemory` | true | memory in use in percent (`memory/physical/used` of `memory/physical/total`) |
| `showNetwork` | false | download and upload rates of all network devices (`network/all/download`, `network/all/upload`) |
| `showTemperature` | false | the hottest core (`cpu/all/maximumTemperature`); the meter appears once a reading came, so it never shows where the machine has no CPU sensor (ksystemstats reads 0 there: virtual machines, some ARM boards) |
| `updateInterval` | 2000 | ms between two values, 1-10 s (settings list 1, 2, 3, 5, 10 s) |
| `popupGap` | 10 | px between the bar and the pop-up (no control; the clock pill's and quick settings' value) |
| `powerTier` | 0 | hidden, written by the power service (`docs/parts/powerfx.md`): the interval x 1 (full), x 2 (power saver), x 4 (critical battery), as the system card |
| `debugAction` | "" | testing only, cleared after use: `dump:TAG` logs a JSON line (`meters: dump TAG {...}`: sampling, subscribed sensors, texts, accessible names, the pill's place), `open` and `close` the pop-up |

No GPU meter: ksystemstats 6.7's GPU usage is not generic. It reads AMD cards from sysfs, NVIDIA
cards by running `nvidia-smi`, and Intel graphics through a helper that needs extra privileges
(`plugins/gpu`, `LinuxBackend.cpp`, `IntelHelper.cpp`); on Intel without it the value stays 0
(minihost's Alder Lake-N: `gpu/all/usage` 0 under load). System Monitor shows the GPU where it can.

## Behaviour

### In the bar

- One pill, 26 px tall (never taller than the bar's row), radius 13, ink .08 (white / #141827),
  .12 on hover, .16 pressed; while the pop-up is open the accent at 35 % with a 1 px accent edge at
  50 % (the open status pill of the QuickSettings boards and the clock pill). Padding 12, 10 px
  between meters; everything scaled with the text size (`FusionMetrics.px`).
- Each meter: a 16 px line glyph (chip, memory module, thermometer; arrows for the network) and
  its figure in Manrope 12 px 700 with tabular figures (the status pill's battery percentage),
  5 px apart. CPU and memory "23%", temperature "52°" (Fahrenheit where the region uses US units),
  network "↓ 1.2 MB ↑ 12 kB" (decimal units, at most three figures; the bar leaves "/s" out, the
  pop-up and the accessible names have it).
- **Steady width:** every figure sits in a box as wide as its widest value ("100%", "188°", the
  widest rate of every unit, with the font's widest digit), so a new value never changes the
  widget's width and the bar is never laid out again for it. The widths are worked out from the
  font, not from laid-out items, so they are known while the meters are hidden too.
- **Warning colours:** CPU and memory at 90 % or more, temperature at 85 °C or more in the colour
  scheme's warning text (Neutral: #f5c08c dark, #8f4f12 light), temperature at 95 °C in its error
  text (Negative); a level ends only 5 points under its limit, so a value at the limit does not
  flash. The colours come from the colour scheme, so the High Contrast scheme's apply; the level is
  also in the accessible name ("CPU 100%, high"), not in the colour only.
- Each meter is a button (Tab focus, a 2 px ring in the accent around its part of the pill; Return,
  Enter or Space) that opens the pop-up; a click toggles it. Its accessible name has the value
  ("CPU 23%", "Memory 52% used", "Network: download 2.1 MB/s, upload 313 kB/s", "CPU temperature
  52 °C"), its role is a drop-down button. Tooltips name the meter and repeat the value (not in
  tablet posture). With every meter turned off the pill shows the quick settings' gauge glyph,
  which still opens the pop-up.
- Context menu: Open System Monitor (`kstart --application org.kde.plasma-systemmonitor`, as the
  system card).
- Vertical panels and the desktop: not designed for; the pill is shown as it is.

### Pop-up

An own `PlasmaCore.AppletPopup` under the pill (10 px gap, all corners rounded, the Plasma style's
frosted dialog), 260 px content in the desktop system card's style: "System" (15 px 800); CPU
with its 5 px teal bar (#3cc4b0) and the core count; memory "1.5 / 2.8 GiB" (binary units as
System Monitor and the system card show it, `contents/code/memory.js`) with
its blue bar (#5b9dff) and "51% in use"; download and upload rates; the CPU temperature ("Hottest
core") where there is a reading; a full-width "Open System Monitor" button (32 px, ink .08, the
keyboard focus when the pop-up opens). Bars at a warning level take the warning colour. It shows
every value, whichever meters are in the bar, and its rows never change its height (a value not
there yet keeps its row). Esc closes it, as does a click outside. Built on its first open. It
opens only under a pill shown in a window on a screen (`meters.js` `popupOpens`): the widget's
shortcut while the width budget or tablet posture took the meters out of the bar does nothing,
rather than leave an "open" state that nothing shows and that keeps every sensor subscribed.

### When the sensors run

Values come from ksystemstats through `org.kde.ksysguard.sensors`, as the system card's and the
stock System Monitor widgets'. Nothing polls: ksystemstats sends a value when it reads one (every
500 ms) and libksysguard's `updateRateLimit` drops what comes sooner than the interval. A sensor is
subscribed only while its meter is in the bar (or the pop-up is open) and the meters can be seen;
libksysguard unsubscribes a disabled sensor and ksystemstats then stops reading it. The meters
cannot be seen, and subscribe nothing, while:

- an active full-screen window covers the bar (a `TasksModel` of the bar's screen, current virtual
  desktop and activity, as the system card's, and `meters.js` `coveringWindows`). KWin raises a
  full-screen window above the panels only while it is the active window, or while the active
  window is on another screen (kwin 6.7 `Window::belongsToLayer()`, `isActiveFullScreen()`); an
  inactive one is drawn under the bar, which then keeps sampling. A maximized window leaves the bar
  visible. When a pop-up or a panel of another screen has the focus, or a dialog of the full-screen
  window, the meters sample although KWin keeps the window above the bar: those are not tasks, or
  not the full-screen task, in the model, and sampling is the safe side (the values stay current);
- the session is locked (`org.freedesktop.ScreenSaver` `ActiveChanged`, as the system card);
- the width budget took the meters out (below), the pill is not in a visible window, or its bar
  has no screen (a bar left over from a screen that is gone; its pop-up does not open either). Plasma
  6.7 gives such a bar the screen -1, Plasma 6.8 keeps the index of the screen it was on, so a bar
  counts as on a screen only while that index is below the number of screens (`meters.js`
  `barOnScreen`; before, a 6.8 bar of an unplugged monitor kept its sensors subscribed);
- every meter is turned off.

After a pause (and when the pop-up opens) every tick is taken for 1.5 s, because ksystemstats'
first answer is the value from before the pause; then one value per interval.

### Width budget (`WidthBudget.qml` in the clock pill)

The widget has `budgetLevel` and `budgetSaving(level)`, like quick settings: at step 1 (with the
global menu's compact view) the network meter, the widest, leaves the bar; at step 2 (with phone
and clipboard) the whole pill. Tablet posture starts at step 2, so the meters are not in the
tablet bar. At 1280 x 800 with all four meters the bar goes to step 1 (the network meter leaves),
at 1440 x 900 it stays at step 0 (measured in the VM, below).

### Power tiers

`plasma-fusion-powerfx` writes the hidden `powerTier` of every meters widget as it does the system
card's (`packages/powerfx/tests/widgets.test.js`, "the top bar's system meters slow down with the
tiers"): 2 s, 4 s and 8 s at the default interval. The user's keys are never written.

## Tests

- `node packages/plasmoids/org.plasmafusion.meters/tests/meters.test.js` (also in `tools/build.sh
  meters` and CI): percent, rate (unit boundaries, rounding up into the next unit, at most three
  figures over 15 decades), memory fraction, temperature (0 is no reading, Fahrenheit), the limits
  with the 5 point fall-back, the interval with the power tiers, the meters' order, which
  full-screen windows cover the bar (active, active window on another screen, none active), and
  when the pop-up may open.
- `node packages/plasmoids/org.plasmafusion.meters/tests/memory.test.js` (also in `tools/build.sh
  meters` and CI): the memory figures in binary units as KFormat and System Monitor print them
  (15.3 GiB, 4.1 GiB, MiB under 1 GiB), a full memory, and the system card's copy of `memory.js`.
- `readings_test.py` (CI, build.yml; `QT_QPA_PLATFORM=offscreen dbus-run-session
  --config-file=packages/kwin/tests/offscreen/session-bus.conf -- python3 <it>`): `Readings.qml` on Plasma's sensor module against a stand-in ksystemstats that
  counts subscriptions: nothing subscribed while every meter is off or the meters cannot be seen,
  only the turned-on meters' sensors, the pop-up's extra ones while it is open, everything
  unsubscribed when the meters are not seen, a 0 °C reading is no reading, and with a 1 s rate
  limit 15 values in 1.5 s reach the meter once or twice (every one without a limit). 14 checks.
  Under the pf-ci container the private bus needs root (`docker exec` without `-u`): dbus-daemon
  cannot look up the uid 1000 there, for the existing D-Bus tests too.
- `node packages/powerfx/tests/widgets.test.js`: the power tiers reach the meters.
- VM (Fedora 44, Plasma 6.7.5, 2 CPUs, 1280 x 800 and 1440 x 900): `tests/vm_meters.py` with two
  busy loops and network traffic through QEMU's user network; see "Verification".

## Verification (2026-10-11, test VM 6)

Fedora 44, Plasma 6.7.5, 2 CPUs, 3 GiB, virtio-vga (software rendering), the worktree's build
laid over the user's `~/.local`; `tests/vm_meters.py` in the session, two busy loops (`busy 30 2`)
and a host-side traffic source through QEMU's user network (about 2 MB/s down, 300 kB/s up).
Screenshots and logs: `artifacts/plasma-fusion/2026-10-11-release-0.5.0/tracks/meters-shots/`.

- **Added** with desktop scripting (`vm_meters.py add`, where Add Widgets would place it) and from
  the settings page (`kcmctl`, and a real pointer click on the switch, then Apply): `... systemtray |
  pen | meters | quicksettings`; off again removes it; the settings page reads it back as on.
- **Values:** idle "3% 53% 0 B / 0 B"; under load "100%" in the warning colour with the name "CPU
  100%, high", network "2.1 MB / 330 kB" and "Network: download 2.1 MB/s, upload 330 kB/s"
  (ksystemstats' rates matched the traffic source); 5 s after the load "2%" and the warning gone.
  Temperature: no CPU sensor in the VM, so the meter stays out of the bar and the pop-up (as
  designed); its sensor was subscribed to find out.
- **Sensors subscribed:** default meters `cpu/all/usage`, `memory/physical/used`,
  `memory/physical/total`; all on adds the two network rates and the temperature; the pop-up open
  adds the core count (and the network rates when the bar has no network meter); a full-screen
  Konsole over the bar, and the locked session (`loginctl lock-session`), subscribe nothing
  (`sampling false`, `subscribed []`), and both resume afterwards.
- **Width budget:** at 1280 x 800 with all meters the bar went to step 1 and the network meter left
  (pill 203 px instead of 341); at 1440 x 900 step 0, pill 282 px with CPU, memory and network.
  Nothing overlapped, the clock pill stayed centred.
- **Pop-up:** opens on a real click, under the pill 10 px below the bar, 296 x 274; Esc closes it,
  a second click closes it; Return on its focused button started plasma-systemmonitor and closed
  it. Tooltip on hover: "Processor load", "CPU 1%"; hover tint .12 measured (40,42,52) against
  (29,31,43) at rest.
- **Dark, light and High Contrast** screenshots of the bar and the pop-up under load: the figures
  and glyphs in the scheme's text colour, the warning in its Neutral text (#f5c08c dark, #8f4f12
  light, #ffd08a High Contrast).
- **Not driven:** keyboard focus inside the panel (`cycle-panels` gave the top bar the focus once,
  but neither libei nor QEMU key presses moved it on in this VM); the meters are Templates buttons
  with `focusPolicy: Qt.TabFocus`, Return/Enter/Space and a focus ring, as the other bar widgets.

**plasmashell CPU** (`vm_meters.py cpu`: user + system time of plasmashell, percent of one core,
idle desktop at 1440 x 900 with the desktop cards; the meters widget out of the bar, with its
default CPU and memory, and with CPU, memory and network (no temperature sensor); arms
interleaved, 3 rounds of 60 s and 3 of 120 s):

| Arm | 60 s rounds | 120 s rounds | Median of six |
|---|---|---|---|
| no meters | 0.97, 0.77, 0.53 | 1.25, 0.82, 0.53 | 0.79 % |
| CPU and memory | 1.02, 0.88, 1.27 | 0.95, 0.90, 1.20 | 0.98 % |
| CPU, memory, network | 1.53, 0.75, 1.62 | 1.26, 1.29, 1.18 | 1.27 % |

About 0.2 points of a core for the default meters and 0.5 for three, in a VM whose panel is drawn
in software (llvmpipe): each new figure redraws the bar, once per 2 s per meter at most. The rest
of the shell varies by as much between rounds. On a GPU-drawn desktop the redraw costs less.

## Design decisions

- **A new widget, not a part of quick settings.** Off means not there: no sensor object, no
  window model, nothing in the shell while a user does not want meters, which a part of the
  always-loaded quick settings could only approach. Users find it in Add Widgets and can place it
  in any panel; quick settings (752 + 589 lines in main.qml and TopBar.qml) stays as it is, and the
  width budget treats the meters as one more widget with its own steps.
- **Percent in the bar, details in the pop-up**: the board's status pill has one figure per item
  (the battery's 82%); "6.1 / 16 GB" and rates with "/s" would make the pill twice as wide.
- **Steady widths** over tight ones: a 2 s value that changed the widget's width would make the
  panel lay out and the width budget run again at every update.
- **Colours from the colour scheme** for the figures and warnings (text, Neutral, Negative), so the
  High Contrast scheme stays high contrast; the card's teal and blue only for the pop-up's bars.
