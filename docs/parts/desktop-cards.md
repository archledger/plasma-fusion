# Part: desktop cards (`org.plasmafusion.weathercard`, `org.plasmafusion.calendarcard`, `org.plasmafusion.systemcard`)

The three desktop widgets of the Main / MainLight boards (`<!-- Plasma desktop widgets -->`,
renders desktop-dark-1 and desktop-light-1): the weather card ("Local weather", condition glyph,
temperature in Space Grotesk 42 px, "Partly cloudy · 21° / 12°"), the calendar card (month title
with < > arrows, narrow weekday initials, today on an accent circle) and the CPU / memory card
(labels, values, 5 px bars in #3cc4b0 and #5b9dff). Plasma 6 applets, QML only, GPL-2.0-or-later.
They replace the stock weather, calendar and system monitor widgets of the phase-1 layout, which
were 416 px wide (their minimum sizes) instead of the board's 192 px.

This part also owns, in the Global Theme layout script, the desktop `CARDS` table (and its
placement loop) and the system-tray item configuration.

Status: built, checked offline and in private virtual sessions on the ThinkPad (cd-1..cd-6),
integrated with every part as built on 2026-09-29, dark and light, en_GB and en_US, with real
pointer and keyboard input; reviewed and fixed afterwards (rcd-1..rcd-4, see "Review"). Not
deployed to the real session (the lead deploys). Last edited 2026-09-29.

## Files

| Path | What |
|---|---|
| `packages/plasmoids/org.plasmafusion.weathercard/metadata.json` | Plasma/Applet metadata (form factor desktop) |
| `.../weathercard/contents/ui/main.qml` | the card, weather engine connection, refresh, context actions |
| `.../weathercard/contents/ui/WeatherGlyph.qml` | condition glyphs in the board's line style (cloud is the board's path) |
| `.../weathercard/contents/ui/SetupButton.qml` | "Set location" pill of the card without a location |
| `.../weathercard/contents/ui/ConfigLocation.qml` | settings page: location search over every weather provider |
| `.../weathercard/contents/ui/ConfigAppearance.qml` | settings page: title, temperature unit, update interval |
| `.../weathercard/contents/code/weather.js` | engine source names, safety check, units, forecast parsing, glyph map |
| `.../weathercard/contents/config/main.xml`, `config.qml` | settings (below) and their pages |
| `.../weathercard/tests/weather.test.js` | tests of weather.js (`node`), not installed |
| `packages/plasmoids/org.plasmafusion.calendarcard/...` | `metadata.json`, `ui/main.qml` (the card), `ui/ConfigGeneral.qml`, `config/main.xml`, `config/config.qml` |
| `packages/plasmoids/org.plasmafusion.systemcard/...` | `metadata.json`, `ui/main.qml` (the card), `ui/ConfigGeneral.qml`, `config/main.xml`, `config/config.qml` |
| `.../contents/ui/CardPalette.qml`, `CardText.qml`, `LineGlyph.qml` | shared colours and fonts, board type scale, 24-box line icons; the same file in all three packages |
| `tools/build.d/74-desktopcards.sh` | checks metadata ids, config XML, that the three copies of the shared files are identical, runs the weather.js tests when `node` exists; copies the packages to `$STAGE/.local/share/plasma/plasmoids/` |
| `packages/look-and-feel/common/contents/layouts/org.kde.plasma.desktop-layout.js` | only the `CARDS` table with its placement loop, and the tray block (`TRAY_ITEMS_REPLACED`, `TRAY_ITEMS_UNLOADED`, `readList`) |

Build: `bash tools/build.sh desktopcards` (with `STAGE=...` for another HOME tree). Two builds give
identical files. Install per user as any Plasma/Applet package
(`kpackagetool6 -t Plasma/Applet -i packages/plasmoids/org.plasmafusion.weathercard`, `-u` to
upgrade), or through `tools/device/fusion-config.sh --install <stage>`.

## Board values and what the cards draw

| | Board (Main / MainLight) | Cards |
|---|---|---|
| Column | x 1226, y 56, width 192, gap 12 | x 1232 (16 px from the right edge), y 50 (16 px under the 34 px top bar), gap 16 |
| Card surface | radius 18, rgba(14,18,34,.52) / white .62, 1 px edge white .10 / ink .10, blur 24 | the Plasma style's `widgets/background` `blurred-*` frame (same values, radius 18, margins 14) with BasicAppletContainer's wallpaper blur (`StandardBackground`) |
| Weather | 192 x 122; padding 14/16; "Local weather" 12 px 700 #a3abc2 / #5b6278; cloud 22 px #f2c38a / #c77a1e; 42 px Space Grotesk 600, line height 1; body 12 px #cdd3e4 / #3a4157; gaps 6 | 192 x 128, content 158 px wide 17 px from the card side, centred vertically |
| Calendar | 192 x 188; padding 14/14/12; title 13 px 800; arrows 16 px #a3abc2 / #5b6278; weekday 10.5 px 700 #8f98b3 / #6b7288; days 11.5 px 500 #dfe3ee / #2a3044, weekend #8f98b3 / #6b7288; today #2f6fdf, white 800; 7 columns, gap 2; rows 21 px, gap 2; section gaps 8 | 192 x 192, content 162 px wide 15 px from the side; months with 6 rows use 18 px rows with 1 px gaps so the card never changes size |
| System | 192 x 92; padding 14/16; labels 12 px 700 #a3abc2 / #5b6278; values 12 px 700; bars 5 px radius 3, track white / ink .10, #3cc4b0 and #5b9dff; gaps 5 and 10 | 192 x 96, content 158 px wide, centred vertically |

Text uses Manrope (UI) and Space Grotesk (temperature) at the board's pixel sizes (converted to
points at 96 dpi, so 10.5 and 11.5 px work) and the board's CSS weights through `font.weight`: the
build installs one static file per weight, so no synthetic bold. Without the fonts the Plasma UI
font is used. The dark or light text set follows the colour scheme's Window background (the set
BasicAppletContainer gives cards with a standard background); the today circle takes the scheme's
Selection colour (#2f6fdf in both Fusion schemes), so a user accent colour still applies.

Measured in the virtual sessions against the renders at 1:1 (`compare-board-dark.png`,
`compare-board-light.png`): text sizes, weights, colours, the calendar grid pitch (23 px) and the
bars match; every card is 6 px right of and 0-6 px higher than the board card, and the calendar
content 1-2 px lower (vertical centring in the taller card).

## Weather card

Data: the Plasma5Support `weather` data engine (plasma5support 6.7.5 ships it with the BBC,
DWD, Environment Canada, NOAA and wetter.com providers). The 6.7.5 stock widget's own classes (ForecastControl, LocationsControl) and its location
page are compiled into its plugin (`plasma.applet.org.kde.plasma.weather`) and cannot be imported
by another applet, and `org.kde.plasma.private.weather` no longer exists; so the location search is
the card's own page, built on the same engine.

- Sources: `ions` (providers), `<ion>|validate|<text>` (search), `<ion>|weather|<place>[|<id>]`.
  The providers split these names on `|` and index the fields without checks: a BBC weather
  source without its station id crashes the process (reproduced on the laptop:
  `UKMETIon::updateIonSource`, SIGSEGV). Every weather source is therefore built only from a
  validate reply and connected only after `weather.js isSafeSource()` accepted it (3 or 4 fields,
  non-empty place, station id required for bbcukmet, dwd and wettercom, `code;name` for wettercom).
  A hand-edited `source` key that fails the check is never connected.
- Delivery: the DataSource uses `interval: 0`. With a polling interval the engine's SignalRelay can
  pass on an early empty reply and then hold back the real one until the next poll
  (plasma5support `datacontainer_p.cpp` checkQueueing); a newly chosen place then stayed on
  "Updating…" for the whole interval (seen in cd-2/cd-3). Updates come from a timer that
  disconnects and, 250 ms later (after the engine dropped the unused source), reconnects the
  source, which makes the provider fetch again. The last reply with weather in it is kept, so a
  refresh or a network drop never blanks the card.
- Without a location: "Local weather", the cloud, a "Set location" button (keyboard reachable) and
  "No location yet". The button opens the settings on the Location page.
- With data: the current temperature (observation; providers without one, like wetter.com, give
  the day's forecast high), the condition in sentence case for English ("Partly cloudy"; other
  languages keep the provider's text), and today's high / low ("21° / 12°"; "Low 18°" at night
  when the provider only gives tonight's low; NOAA's day and night entries of the same date are
  combined). The glyph follows the condition icon: cloud (board path; also the providers'
  "partly cloudy" `weather-clouds`), sun, moon, sun or moon with cloud (few clouds), rain, snow,
  storm, fog.
- No reply 45 s after connecting: "Weather unavailable" (shown only while there is no earlier
  data).
- Units: temperature in °F where the region uses US units (`Locale.ImperialUSSystem`), °C
  everywhere else. The stock widget takes °F for every non-metric region, which includes the
  United Kingdom (Qt's ImperialUKSystem); UK weather reports use °C. Settings override it.
- Context menu: Refresh; Open Forecast Website (the provider's http/https page only).

Location page: a search field (focused when the page opens; the search runs 0.9 s after typing
stops or at once on Enter, from 2 characters), every provider asked in parallel, results listed
with their provider: places named exactly as typed first, then names starting with it; within
each group the region's own weather service first (`weather.js regionalIon`: US NOAA, GB BBC,
CA Environment Canada, DE DWD; "London" in en_GB lists the BBC's London before NOAA's London,
Kentucky). A click selects, Apply/OK saves. Keyboard: Down moves from the field to the first
result (focus frame), Up/Down move, Enter or Space picks the place, Enter on the place already
picked is left to the dialog (OK), Up from the first result goes back to the field; so "London,
Enter, Down, Enter, Enter" sets London and closes the settings. The search field and the list
take their Enter themselves: the settings dialog closes on any Return that reaches it
(`AppletConfiguration.qml` `Keys.onReturnPressed: acceptAction.trigger()`), and a text field
passes Return on. "Clear" forgets the location. The line above names the current place and its
provider.

Settings (`[General]`, `contents/config/main.xml`):

| Key | Default | Meaning |
|---|---|---|
| `source` | "" | engine source of the location (empty: no location) |
| `placeDisplayName`, `providerName` | "" | shown in the settings and the tooltip |
| `updateInterval` | 30 | minutes between updates (10-180) |
| `temperatureUnit` | 0 | 0 region, 1 °C, 2 °F |
| `titleMode` | 0 | 0 "Local weather" (board), 1 the place name |

## Calendar card

- Week start from the region (`Qt.locale().firstDayOfWeek`; en_US Sunday, en_GB Monday) or the
  setting `firstDayOfWeek` (-1 region, 0 Sunday … 6 Saturday); weekends from the region's working
  days; narrow weekday initials and the month name from the region.
- Month navigation: the < > arrows (16 px glyphs, 22 px hover tint, tooltips), a click on the
  month title when another month is shown goes back to today. Blank cells before the 1st and after
  the last day, as on the board.
- Today moves at midnight (checked every 30 s, also after a resume). A new day also brings the
  card back to today's month unless it was browsed in the last minute, so a month browsed to
  and left there does not stay on the desktop for good.
- A click on a day opens KOrganizer on that date when KOrganizer's D-Bus service is installed
  (`ListActivatableNames` has `org.kde.korganizer`): `org.freedesktop.Application.Activate` on
  `/org/kde/korganizer` (starts or raises it) and `org.kde.Korganizer.Calendar.goDate(QString)` on
  `/Calendar` with the date in the region's long format, which KOrganizer parses with the same
  format (`actionmanager.cpp`, 26.08). Days show a hover circle only then. Context menu: Open
  KOrganizer. Checked with a stub service on the private bus (`logs/korganizer-dbus-stub.log`:
  "Tuesday, 15 September 2026"), so no Akonadi was started in the test sessions.
- Keyboard: a click anywhere on the card (a day, an arrow, the title or the space between) or
  Tab gives the month grid the keyboard; after a click on a day the cursor starts on that day.
  Left/Right/Up/Down move a day cursor (a focus ring; it crosses into the next or previous
  month), Page Up/Page Down change the month, Home goes back to today, Enter/Space open the
  cursor day in KOrganizer. The ring shows after Tab or a key press, not after a click, and
  keeps that state when the desktop gets the keyboard back (a closed pop-up, a window switch).
  Tab order: grid, previous, next; the arrows take Enter/Space. Right-to-left layouts mirror.
- Day names for tooltips, screen readers and KOrganizer are the region's long date without the
  time ("Tuesday, 15 September 2026").

## CPU and memory card

- `cpu/all/usage`, `memory/physical/used` and `memory/physical/total` from ksystemstats through
  `org.kde.ksysguard.sensors` (the stock system monitor's source), every 3 s (setting
  `updateInterval`, 1-10 s; x 2 or x 4 in the power tiers), paused while nobody can see the card
  (see "CARD-1" below).
- "23%" and "6.1 / 16 GB": used memory with one decimal, the total rounded up to whole GB (the
  kernel reports a little less than the installed memory, e.g. 15.3 GiB for 16 GB). GiB values
  labelled "GB" as on the board.
- Bars step to each value in whole pixels (one frame); only a change of 10 points or more glides
  (one Kirigami longDuration, 200 ms at normal speed, OutCubic), and nothing glides when
  animations are off. Every animation frame redraws the whole desktop window (wallpaper and the
  blurred cards): measured in the first review, the original 600 ms glide every 2 s kept
  plasmashell at 1200-1570 ms CPU per 30 s (4-5 % of a core), a 200 ms glide for changes of 3 px
  or more at 470-650 ms (1.6-2.2 %), no animation at 190-300 ms, no system card at about 100 ms.
  CARD-1 below replaced that glide rule.
- Context menu: Open System Monitor (`kstart --application org.kde.plasma-systemmonitor`, so
  nothing stays a child of the shell).

The card sizes are fixed through the widgets' minimum sizes (164 x 94, 164 x 160, 164 x 64 inside
the frame); users can make them larger in edit mode. The widgets always show the card itself:
`switchWidth`/`switchHeight` are not used, because libplasma shows the icon unless the widget is
strictly larger than them (`appletShouldBeExpanded`), which a card of exactly the board size is not.

## CARD-1: idle cost of the system card

Work package CARD-1 of the 2026-09-30 build plan (EFFECTS.md section 5, E6 and the X3 idle rows;
BACKLOG M5). It replaces the update interval and the glide rule of "CPU and memory card" above;
the look, the text scale (FusionMetrics) and keyboard access are unchanged. Built and measured
2026-09-30 (builder `cd1`, finished by the lead) on HEAD d4afee8 plus this package. Not deployed.

Why: every change on the card redraws the whole desktop window (wallpaper and the blurred cards)
and makes KWin composite a frame. The committed card updated every 2 s and glided (200 ms, about
15 frames) whenever a bar moved 3 px or more, which idle jitter does on most updates, and it kept
doing so under maximized windows and behind the lock screen.

| | Before (d4afee8) | Now |
|---|---|---|
| Interval | `updateInterval` default 2000 ms | default **3000 ms** (settings list 1, 2, 3, 5, 10 s) |
| Power tier | none | hidden key `powerTier` (Int 0-2, default 0): effective interval = `updateInterval` x 1 (full), x 2 (saver), x 4 (critical), so 3 / 6 / 12 s at the default |
| Bars | glide when the bar moves 3 px or more | **step** (one frame); glide only when the value moved 10 points or more since the bar last moved (CPU 4 % -> 14 %), only while the card samples, not in the first 1.5 s after a pause, and not at Plasma's animation speed "Instant" |
| Sensors | always subscribed | `enabled: false` (libksysguard unsubscribes; ksystemstats then stops reading CPU and memory) while the card cannot be seen, see below |
| After a pause | - | for 1.5 s every ksystemstats tick is taken, then one value per interval |

When the sensors are off:
- **Covered:** a maximized or full-screen window on the card's screen, on that screen's current
  virtual desktop and the current activity. The windows come from a `TaskManager.TasksModel`
  filtered as the stock panel's `touchingWindow` model (plasma-desktop `Panel.qml`: current
  virtual desktop per screen, activity, not minimized, not hidden, no grouping) plus
  `filterByScreen` with the containment's `screenGeometry`; an `Instantiator` counts rows whose
  `IsMaximized` or `IsFullScreen` is true. "Show Desktop" (`KWindowSystem.showingDesktop`)
  uncovers. TasksModel 6.7.5 has no `filterSkipTaskbar` property and always drops skip-taskbar
  windows, so a maximized skip-taskbar window does not pause the card (the stock panel ignores
  them too).
- **Not shown:** the card's item or its window is not visible (the desktop hides the containment
  of another activity: libplasma `ContainmentView::setContainment`).
- **Locked:** `org.kde.plasma.workspace.dbus` (plasma-workspace 6.7.5): a `DBusServiceWatcher` on
  `org.freedesktop.ScreenSaver`, `GetActive` on `/ScreenSaver` while that name has an owner (so the
  call never activates a service), and a `SignalWatcher` for `ActiveChanged(bool)` (kscreenlocker
  `interface.cpp` emits it on lock and unlock). While locked KWin draws no desktop anyway
  (EFFECTS E3), so this saves the sensor work only.

Fresh values after a pause: libksysguard asks for the current value when a sensor is enabled
again, but ksystemstats has not read CPU and memory while nobody subscribed, so that reply is the
value from before the pause, and its first CPU tick is the average over the pause; ticks come
every 500 ms. With the rate limit lifted for 1.5 s the card shows a current 0.5 s sample about
0.6 s after it can be seen again (measured below), then one value per interval.

The power service (EFFECTS 8.3) writes only `powerTier` (`evaluateScript`,
`writeConfig("powerTier", n)`); the user's `updateInterval` is never rewritten and its kcfg `<max>`
10000 stays. The settings page declares `cfg_powerTier` (so the dialog passes no unknown initial
property) and, on Apply/OK, hands back the tier the card has at that moment, so an open settings
dialog never restores an older tier.

Debug output for tests: `QT_LOGGING_RULES="org.plasmafusion.systemcard.debug=true"` makes the card
log sensor state changes, each CPU value and each bar step or glide with the epoch time in ms
(off by default).

### Measurements (private sessions on the ThinkPad, 1920 x 1200 at 4/3)

Method: `build/lead/dk/perf-remote.sh` (KWin's `KWIN_LOG_PERFORMANCE_DATA` frame log, `pfstat.py`
snapshots, `analyze_ab.py` helpers). Old = a clean `git archive` of d4afee8 built with
`tools/build.sh`; new = the same stage with this package. Installed with `fusion-config.sh
--install`, plasmashell restarted, pointer parked at 720,450, 20 s settle. Runs interleaved:
new1 old1 new2 old2 new3 old3. new1, old1, new2 and old2 ran on a quiet host (system CPU
0.38-0.44 % in the visible window, load 0.22-0.65); new3 and old3 overlapped other lanes' private
sessions (system CPU up to 16 %), where CPU really moved by 10 points or more and new3 glided four
times (1.70 frames/s visible). Table: quiet runs, mean (min..max), n = 2 per arm.

| 30 s window | frames/s old | frames/s new | bursts > 2 frames old / new | plasmashell CPU % old / new | KWin CPU % old / new |
|---|---|---|---|---|---|
| card visible, idle | 0.87 (0.60..1.13) | **0.17 (0.17..0.17)** | 1.5 / 0 | 0.78 / 0.60 | 0.27 / 0.08 |
| Konsole maximized over the card | 0.93 (0.27..1.60) | **0.02 (0..0.03)** | 1.5 / 0 | 0.70 / 0.33 | 0.25 / 0.00 |
| Konsole maximized on desktop 2 (12 s) | 1.00 (0.42..1.58) | 0.29 (0.17..0.42) | 0.5 / 0 | 0.87 / 0.46 | 0.25 / 0.13 |
| stub locker "locked" (14 s) | 1.14 (0.14..2.14) | **0.07 (0.07..0.07)** | 1 / 0 | 0.85 / 0.36 | 0.32 / 0.00 |
| power tier 2, card visible (40 s) | 0.66 (0.55..0.77) | 0.04 (0..0.08) | 1.5 / 0 | 0.70 / 0.44 | 0.21 / 0.03 |

plasmashell GPU (% busy) visible 0.11 -> 0.02, covered 0.12 -> 0.00. The only frames in the new
covered and locked windows are the clock's minute tick (at hh:mm:00.0); the visible window holds
four card frames (a value whose rounded text or whole-pixel bar changed) plus that tick. EFFECTS X3
acceptance: covered 0.02 <= 0.1, visible 0.17 <= 0.45, no burst longer than 2 frames without a
10-point change. The old card kept compositing under an opaque maximized window (up to 1.6
frames/s, glide bursts of 14 frames).

Functional checks (debug log and frame log):
- Un-maximize: sampling again after 0.07-0.08 s; values at +0.07 s (the pre-pause reply), +0.10-0.13
  s (pause average), **+0.60-0.63 s (current)**, +1.1 s, then +4.6 s and every 3 s (3 runs).
- Maximized Konsole on the second virtual desktop: no pause (4 values in 12 s, 3 runs).
- Show Desktop over a maximized Konsole: sampling resumed 20 ms after `showDesktop(true)` and paused
  again when KWin left the mode (KWin ended it by itself after about 20 ms in these sessions).
- Stub locker (a D-Bus service owning `org.freedesktop.ScreenSaver` on the private bus, as KWin's
  locker does): paused at `ActiveChanged(true)`, no values while locked, values 0.24-0.30 s after
  `ActiveChanged(false)` and current by +0.74-0.80 s.
- Power tier 2: values 12.0 and 12.5 s apart; `updateInterval` stayed unset (default) in the
  config.
- CPU jump of about 17 points (two busy loops): one glide up and one down (14-15 frames each);
  at `AnimationDurationFactor` 0 the same jump steps (single frames; the old card still ran a
  1 ms "glide" of 2-3 frames because Kirigami's longDuration is 1, not 0, at factor 0).
- Activity switch (1920 x 1200 at 1.325, `cd1-func-new`): paused 11 ms after
  `SetCurrentActivity` (the card's containment is hidden), resumed 11 ms after switching back, no
  values while away.
- KWin's real screen locker (a `PFV_LOCK=1` session, `pfv_lock`; never unlocked, no password
  typed): paused 0.32 s after the `Lock` call, no values afterwards.
- Glide rule, from the debug logs of every new run: 12 glides, each after a change of 10 points or
  more; 18 changes of 1-9 points and 14 under 1 point stepped; 6 steps of 10 points or more, all at
  factor 0.
- Settings dialog (`cd1-cfg-new1`, 1920 x 1200 at 1.325; opened from the card's context menu,
  because the scripting `showConfigurationInterface()` is a no-op in 6.7.5): a `powerTier` of 1
  written while the dialog was open survived OK, and `updateInterval` stayed unset. The dialog
  showed "Update every: 1 second" although the card used 3 s. `currentIndex` was bound to
  `ComboBox.indexOfValue()`, which answers -1 until the combo has read its model, so the binding
  stayed on the first entry; HEAD had the same binding (it showed 1 s for its 2 s default). The
  page now looks the value up in its own list (`findIndex`). Re-run `cd1-cfg-new2`: the dialog shows "3 seconds";
  the tier written while it was open survived OK. HEAD's card (`cd1-cfg-old`) shows "1 second" for its
  2 s default, so the fault predates this work.
- +3 pt text (fonts, `KGlobalSettings` notify, shell restart): the card draws the larger text and
  still fits; after the restart it sampled at the tier-1 interval (6 s).

Lint: `qmllint` (Qt 6.11.2) old vs new: the same warnings (unqualified `i18n*` only) plus one for the
new "3 seconds" list entry. Core dumps on the ThinkPad since the first run (`coredumpctl list
--since "2026-09-29 23:08:48"`): none.

Not covered: resuming after the real locker's `ActiveChanged(false)` (a private session is never
unlocked; the stub covers that path); the power service itself (EFFECTS 8.3, POWER-1).

Two readers of the same sensor in one plasmashell (a second card, or a stock system monitor
widget): ksystemstats 6.7.5 (`Client::subscribeSensors`) adds one D-Bus connection per subscribe
call and `unsubscribeSensors` removes one, so the other reader keeps its values while this card
pauses; after the card resumes, each value reaches the process twice (harmless: the same value).
From the sources; not tested.

Perf gate (`tools/tests/perf/run.sh`, 3 runs, all quiet, 1920 x 1200 at 4/3; stage = d4afee8 plus
this package; run by the lead 2026-09-30 00:08-00:21 EDT): no regression against the 282b1a5
baseline. Idle rows, median of this build vs the baseline: composited frames 0.30 vs 1.23 per s,
plasmashell CPU 0.63 vs 1.00 % (better), KWin CPU 0.13 vs 0.40 %, whole session 1.36 vs 1.96 %
(better), plasmashell GPU 0.04 vs 0.16 %. The idle budget rows (EFFECTS 9.1) still fail: the
remaining frames come from the clock and other widgets, not from this card. Not caused by this
package, seen in the same run: Alt+Tab to its first frame took 313 ms (312-314) against the
baseline's 255 ms (248-279); the gate's noise rule calls it the same, but every run was slower
than the slowest baseline run (d4afee8 changes against 282b1a5, for the lead to follow up).
Results: `build/cd1/gate/results/` (table.md, result.json).

### CARD-1 review (lead)

The workflow's reviewer stage was replaced by a lead review when the lead took the lane over
(2026-09-30 04:04Z).
- The code matches the spec. The covered model uses the same filters as plasma-desktop 6.7.5
  `Panel.qml` plus the screen filter, so a minimized, a partly covering or another desktop's
  maximized window does not pause the card.
- The settings dialog (plasma-desktop `AppletConfiguration.qml`) calls the page's `saveConfig()`
  before it copies the `cfg_` values, so OK or Apply writes back the live tier.
- Low, not fixed: suppose the tier changes while the dialog is open, and the user then edits a
  setting and reverts it. Apply then stays enabled (`isConfigurationChanged` sees the tier), so
  closing asks to apply or discard. Either answer keeps the live tier.

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/card1/` (runs, analysis,
scenarios, crops); laptop scratch `build/cd1/`.

## Layout script: cards

`CARDS` lists, per card, the Fusion widget and the stock fallback with their sizes. The first
installed one is placed right-aligned with a 16 px margin, the column starting 16 px under the top
bar:

| Card | Fusion widget | Rect (logical px, under the top bar) | Fallback |
|---|---|---|---|
| weather | `org.plasmafusion.weathercard` | 1232,16 192x128 | `org.kde.plasma.weather` 1008,16 416x208 |
| calendar | `org.plasmafusion.calendarcard` | 1232,160 192x192 | `org.kde.plasma.calendar` 416x288 |
| CPU/memory | `org.plasmafusion.systemcard` | 1232,368 192x96 | `org.kde.plasma.systemmonitor` 416x144 (+ the bars configuration) |

Each card gets `userBackgroundHints = StandardBackground`. A mix works (each card is right-aligned
at its own width and the column stacks). Checked with a mock of the scripting API
(`logs/layout-script-mock.txt`: all Fusion, all stock, only the calendar) and in the sessions
(`ItemGeometries-1440x900 = Applet-51:1232,16,192,128;Applet-52:1232,160,192,192;Applet-53:1232,368,192,96`).

## Layout script: system tray

Checked in plasma-workspace, plasma-pa, powerdevil, plasma-nm and bluedevil 6.7.5 which replaced
items still have a duty of their own:

| Item | Background duty in 6.7.5 | Where it really lives |
|---|---|---|
| `org.kde.plasma.volume` | none | volume keys, OSD and the feedback sound are the kded module `audioshortcutsservice` (plasma-pa `src/kded`) |
| `org.kde.plasma.notifications` | **yes**: notification server, pop-ups, Do Not Disturb (the quick-settings tile calls its `toggle do not disturb` shortcut) | the applet (`global/Globals.qml`) |
| `org.kde.plasma.clipboard` | **yes**: hosts Klipper (history, Meta+V; the quick-settings clipboard button calls it) | the applet |
| `org.kde.plasma.battery`, `org.kde.plasma.brightness` | none | battery warnings, brightness keys and their OSD are PowerDevil's |
| `org.kde.plasma.networkmanagement` | none | secret agent, password prompts and notifications are the plasma-nm kded module (`kded/secretagent`, `passworddialog`) |
| `org.kde.plasma.bluetooth` | none (its only notification is for a connect started from its own list) | the pairing agent is bluedevil's kded module (`src/kded/bluezagent`) |
| `org.kde.plasma.keyboardlayout` | none | switching shortcuts are KWin's, the layout OSD is plasmashell's (`plasmarc [OSD]`) |
| `org.kde.kdeconnect` | none | kdeconnectd |
| `org.kde.plasma.mediacontroller` | none | media keys are the kded module `mprisservice` (libkmpris) |

All ten stay loaded (the quick-settings part asks for that: docs/parts/shell-quicksettings.md).
Keys written to the tray (`[Containments][<panel>][Applets][<tray>][Configuration][General]`) when
the quick-settings widget is in the bar:

| Key | Value | Effect |
|---|---|---|
| `disabledStatusNotifiers` | the ten ids above | `calculateEffectiveStatus` (systemtraymodel.cpp) applies this list to every item id, plasmoids included: they get HiddenStatus, so they are neither in the bar nor in the pop-up and do not bring up the expander arrow |
| `hiddenItems` | the same ten ids | fallback: a tray that ignored the first key would only move them into its pop-up |
| `knownItems` | + `org.kde.plasma.weather` | the tray never enables its own weather report again (`PlasmoidRegistry::registerPlugin`) |
| `extraItems` | − `org.kde.plasma.weather` (when present) | the tray's weather report is not loaded: it repeats the desktop card, has no duty and, being passive until it has a location, sat behind the arrow |

`shownItems` and `showAllItems` are left alone (either would force the items back into view).
Application status icons (StatusNotifierItems) keep the stock behaviour: active ones in the bar,
passive ones in the pop-up.

Result (cd-6, `screens/08-dark-tray-popup.png`): none of the ten is shown anywhere. The expander
arrow remains only because three other default items are passive: Vaults, Disks & Devices and
Display Configuration. They become active, and appear in the bar, exactly when they matter (an
open vault, a removable drive, a second display); there is no tray key for "hide while passive",
and listing them in `disabledStatusNotifiers` would also hide them when active. Left as is; to
drop the arrow at that cost, add `org.kde.plasma.vault`, `org.kde.plasma.devicenotifier` and
`org.kde.kscreen` (and `org.kde.plasma.printmanager` where print-manager is installed) to
`TRAY_ITEMS_REPLACED`'s `disabledStatusNotifiers` write.

In the tray's own settings the ten show as "Show only in popup" (the page reads `hiddenItems`
first); choosing another visibility there removes the id from all lists, which brings the item
back. A replaced applet opened by its own global shortcut, if a user sets one, does not show its
pop-up (the tray only follows expansion of items in the bar or in its pop-up).

## Existing sessions (the real ThinkPad session has the phase-1 stock cards)

The layout script runs only on a layout reset (`tools/device/fusion-config.sh --reset-layout`, or
the Global Theme with "Desktop and window layout"). To switch an existing session without
touching its panels, install the cards and run this script twice in the session (it only
replaces stock weather/calendar/system monitor widgets in the right-hand card column whose Fusion
card is installed, and only configures a tray that sits next to the quick-settings widget):

```
js=$(cat desktop-cards-migrate.js); q=org.kde.PlasmaShell.evaluateScript
qdbus-qt6 org.kde.plasmashell /PlasmaShell $q "var PHASE = 'remove'; $js"; sleep 3
qdbus-qt6 org.kde.plasmashell /PlasmaShell $q "var PHASE = 'add'; $js"
```

Two phases because cards added in the same run as the removal are pushed aside (to x 840 in
cd-5): the removed widgets still hold their grid cells until the shell has processed the removal.
Checked in cd-5 from the phase-1 layout (stock cards at 1008,16 416x208 / 1008,240 416x288 /
1008,544 416x144): result 1232,16 / 1232,160 / 1232,368, tray keys as above, and after a
plasmashell restart (`migration-stock-to-fusion.png`, `logs/migrate.txt`). Rollback: the
profile backup of `fusion-config.sh` (`plasma-org.kde.plasma.desktop-appletsrc`), or put the
stock widgets back by hand.

```js
// Plasma Fusion desktop cards: in an existing layout, replace the stock weather, calendar and
// system monitor cards of the right-hand card column with the Plasma Fusion cards, and give the
// system tray next to the quick-settings widget the Plasma Fusion tray keys.
// Run in the user's session, twice: PHASE "remove" takes the stock cards out (and configures the
// tray); PHASE "add" puts the Plasma Fusion cards in once the shell has freed their grid cells
// (a card added in the same run is pushed aside by the cards being removed):
//   js=$(cat this.js); q=org.kde.PlasmaShell.evaluateScript
//   qdbus-qt6 org.kde.plasmashell /PlasmaShell $q "var PHASE = 'remove'; $js"; sleep 3
//   qdbus-qt6 org.kde.plasmashell /PlasmaShell $q "var PHASE = 'add'; $js"
if (typeof PHASE === "undefined") { var PHASE = "remove"; }
var CELL = 16;
var CARDS = [
    ["org.kde.plasma.weather", "org.plasmafusion.weathercard", 192, 128],
    ["org.kde.plasma.calendar", "org.plasmafusion.calendarcard", 192, 192],
    ["org.kde.plasma.systemmonitor", "org.plasmafusion.systemcard", 192, 96]
];
var TRAY_ITEMS_REPLACED = ["org.kde.plasma.networkmanagement", "org.kde.plasma.volume",
    "org.kde.plasma.battery", "org.kde.plasma.bluetooth", "org.kde.plasma.brightness",
    "org.kde.plasma.notifications", "org.kde.plasma.keyboardlayout", "org.kde.kdeconnect",
    "org.kde.plasma.clipboard", "org.kde.plasma.mediacontroller"];
var TRAY_ITEMS_UNLOADED = ["org.kde.plasma.weather"];
var report = [];

function readList(applet, key) {
    var value = applet.readConfig(key, []);
    if (value === undefined || value === null || value === "") return [];
    if (typeof value === "string") return value.split(",");
    var list = [];
    for (var i = 0; i < value.length; ++i) list.push(String(value[i]));
    return list;
}

var ds = desktops();
for (var d = 0; d < ds.length; ++d) {
    var desktop = ds[d];
    if (desktop.screen < 0) continue;
    var width = screenGeometry(desktop.screen).width;
    var widgets = desktop.widgets();
    if (PHASE === "remove") {
        for (var w = 0; w < widgets.length; ++w) {
            for (var c = 0; c < CARDS.length; ++c) {
                // Only cards of the right-hand column (the phase-1 layout's stock cards are 416 px wide).
                // A stock card stays when its Plasma Fusion card is not installed.
                if (widgets[w].type === CARDS[c][0] && widgets[w].geometry.x >= width - 3 * CELL - 416
                        && knownWidgetTypes.indexOf(CARDS[c][1]) !== -1) {
                    report.push("removed " + widgets[w].type + " " + widgets[w].id);
                    widgets[w].remove();
                }
            }
        }
        continue;
    }
    // PHASE "add": only on the screen-0 desktop, and only when it has no Plasma Fusion card yet.
    if (desktop.screen !== 0) continue;
    var hasCards = false;
    for (var h = 0; h < widgets.length; ++h) {
        for (var c2 = 0; c2 < CARDS.length; ++c2) {
            if (widgets[h].type === CARDS[c2][1]) hasCards = true;
        }
    }
    if (hasCards) {
        report.push("desktop " + desktop.id + " already has Plasma Fusion cards");
        continue;
    }
    var y = CELL;
    for (var k = 0; k < CARDS.length; ++k) {
        if (knownWidgetTypes.indexOf(CARDS[k][1]) === -1) {
            report.push(CARDS[k][1] + " is not installed");
            continue;
        }
        var x = Math.floor((width - CELL - CARDS[k][2]) / CELL) * CELL;
        var card = desktop.addWidget(CARDS[k][1], x, y, CARDS[k][2], CARDS[k][3]);
        card.userBackgroundHints = "StandardBackground";
        report.push("added " + CARDS[k][1] + " at " + x + "," + y);
        y += CARDS[k][3] + CELL;
    }
}

var ps = PHASE === "remove" ? panels() : [];
for (var p = 0; p < ps.length; ++p) {
    var tray = null, quickSettings = false;
    var pw = ps[p].widgets();
    for (var i = 0; i < pw.length; ++i) {
        if (pw[i].type === "org.kde.plasma.systemtray") tray = pw[i];
        if (pw[i].type === "org.plasmafusion.quicksettings") quickSettings = true;
    }
    if (!tray || !quickSettings) continue;
    tray.currentConfigGroup = ["General"];
    tray.writeConfig("disabledStatusNotifiers", TRAY_ITEMS_REPLACED);
    tray.writeConfig("hiddenItems", TRAY_ITEMS_REPLACED);
    var known = readList(tray, "knownItems");
    var extra = readList(tray, "extraItems");
    for (var u = 0; u < TRAY_ITEMS_UNLOADED.length; ++u) {
        if (known.indexOf(TRAY_ITEMS_UNLOADED[u]) === -1) known.push(TRAY_ITEMS_UNLOADED[u]);
        var at = extra.indexOf(TRAY_ITEMS_UNLOADED[u]);
        if (at !== -1) extra.splice(at, 1);
    }
    tray.writeConfig("knownItems", known);
    tray.writeConfig("extraItems", extra);
    tray.currentConfigGroup = [];
    report.push("tray " + tray.id + " configured");
}
print(report.join("\n") + "\n");
```

## Verification

- Offline: `qmllint` of every QML file (only the usual unqualified `i18n*` warnings), `node
  tests/weather.test.js` (source safety, validate parsing incl. the BBC reply format, units,
  NOAA day/night and BBC night high/low, glyph map), `node --check` and a scripting-API mock of the
  layout script, `bash -n` and `shellcheck -S warning` of the build script. Weather engine replies
  recorded on the laptop from BBC, NOAA, Environment Canada and wetter.com.
- Virtual sessions on the ThinkPad (`tools/vsession/remote.sh`, prefix cd-, all parts built into
  `build/cd/home`, installed with `fusion-config.sh --install`):
  - cd-1: layout (cards at the rects above, tray keys); found the icon-instead-of-card switch and a
    polish loop in the weekday row (both fixed).
  - cd-2 (en_US): calendar arrows with the real pointer (next, next, previous x3, title back to
    today; August 2026 with 6 rows), tray pop-up, "Set location" click, location search typed
    with real keys, place picked, OK.
  - cd-3/cd-4 (en_GB): board comparisons dark and light; weather via the settings dialog (fresh
    shell and live change, BBC, NOAA, wetter.com, Environment Canada), Clear, context menu;
    hover and click on days and keyboard (cursor, Enter, Tab order, Page Down, Home) against a
    KOrganizer D-Bus stub.
  - cd-5: migration from the phase-1 stock layout.
  - cd-6: final run with every part: set-up state, search dialog, BBC London, arrows, keyboard,
    tray pop-up, light, then en_US (Sunday first, °F) light and dark.
  - plasmashell logs: no warning from the cards except Kirigami's generic "Created graphical object
    was not placed in the graphics scene" when a settings page opens (also seen with the dock's
    page).
  - No core dump from the cd- sessions (`coredumpctl list --since "2026-09-29 17:41:45"`: the
    entries in that window are uid 981 kdialog, perf-pilot-* sessions and `kscreen-doctor -o` run
    over SSH by other agents).
- Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/desktop-cards/`
  (`compare-board-{dark,light}.png` board | session | blend at 2x, `states-strip.png`,
  `pointer-calendar-arrows.png`, `keyboard-*.png`, `location-search-dialog.png`,
  `migration-stock-to-fusion.png`, `tray-popup-after-layout.png`, `screens/` full 1440x900
  captures, `logs/`, `test-tooling/` with the scenarios, the extended input tool (letters, digits,
  `type TEXT`), the KOrganizer stub and the comparison script).

## Deviations from the boards

- Card sizes and positions follow the desktop's 16 px grid (plasma-workspace
  `gridlayoutmanager.cpp` rounds every position and size to cells): 192 x 128 / 192 / 96 instead of
  122 / 188 / 92, 16 px gaps instead of 12, x 1232 instead of 1226, y 50 instead of 56. The
  content keeps the board's side padding and is centred vertically in the taller card.
- Weather texts come from the provider: "Light rain · Low 20°" at night (only tonight's low),
  wetter.com has no current observation (the day's high is shown), non-English condition texts
  are not re-cased.
- The calendar highlights today on the region's calendar; the board's fixed "28" is the design
  date. Weekday initials follow the region (en_US starts on Sunday).
- Memory values are GiB labelled "GB" (as on the board); the total is rounded up to whole GB.
- No board exists for the "Set location" state, the settings pages, hover and focus states; they
  use the card's type scale, tints of the board's ink and the boards' focus-ring colour.
- Portrait (the X13 Yoga turned, 900 x 1440 logical at scale 4/3): Plasma moves the column
  inside the narrower screen itself, 4 px from the right edge instead of 16 (review rcd-2,
  `review-portrait-after-rotation.png`); turned back, the cards return to x 1232.

## Needs from other parts

- Look-and-feel (docs/parts/lookandfeel.md, not this part's file): its "Desktop layout" section
  and card table still describe the stock cards (1008,16 416x208 …) and `hiddenItems` only; please
  point to this document for the cards and the tray keys. Its test tooling
  (`generators/look-and-feel/tests/`) may expect the old rectangles.
- Lead / device deploy: the real ThinkPad session still has the phase-1 stock cards; switch with
  `fusion-config.sh --install <stage> --reset-layout` or the two-phase migration script above.
  `fusion-config.sh` could run the migration itself when it keeps the layout (tools/device is not
  this part's).
- System-wide package: the ThinkPad now has `plasma-fusion-0.1.0-7.git380cc97.dirty202609292222.fc44`
  (rpm -V clean), whose copies of the three cards under `/usr/share/plasma/plasmoids/` predate the
  review fixes (location keyboard, calendar focus and dates, system card animation, weekday row).
  Rebuild it from the reviewed tree. Per-user copies in `~/.local/share/plasma/plasmoids` take
  precedence, so the virtual sessions and a `--install` test the current code.
- Optional (tray, lead decision): hide Vaults, Disks & Devices and Display Configuration too to
  drop the expander arrow at the cost of their indicators (see above).

## Review

Adversarial review of this part on 2026-09-29 (18:25-19:25 EDT): code read against the 6.7.5
sources (plasma5support weather engine and ions, systemtray, notifications `Globals.qml`,
plasma-pa kded, `AppletConfiguration.qml`, `BasicAppletContainer.qml`), the build and linters run
again, and four integrated virtual sessions on the ThinkPad, every part built from the current
tree into `build/rcd/home` and installed with `fusion-config.sh --install`: rcd-1 (1920 x 1200 at
scale 4/3 = the real device, en_US, dark then light), rcd-2 and rcd-3 (1440 x 900, en_GB, dark
and light, final board comparison), rcd-4 (scale 4/3, en_US, focus and robustness). Real pointer
and keyboard through KWin EIS; KOrganizer replaced by the D-Bus stub.

Findings and what was done:

| # | Severity | Finding | Fixed |
|---|---|---|---|
| 1 | medium | Location page, keyboard: Enter in the search field (documented as "search now") also closed the settings dialog, because the text field passes Return on and the dialog's root accepts on any Return; Down then Enter closed the dialog without picking anything (Down only moved focus, no current item). Seen in rcd-1 (`07-keyboard-select`: dialog gone, `source` empty). | yes: the field and the list take Enter; Down selects the first result with a focus frame; Enter/Space pick, Enter on the picked place goes on to OK; Up from the top returns to the field (rcd-2/rcd-3) |
| 2 | medium | System card: the 600 ms glide every 2 s redraws the whole desktop window about 36 times per update, also under windows: plasmashell 950-1570 ms CPU per 30 s (3-5 % of a core) against 180-300 ms without animation and about 100 ms without the card (rcd-1 at scale 4/3, rcd-2 at 1440 x 900; a full-screen window on top still 530 ms). | yes: one Kirigami longDuration (200 ms), whole-pixel widths, changes under 3 px step: 470-650 ms per 30 s at 1440 x 900 (old 1200-1510 ms in the same session) |
| 3 | low | Calendar: a click on a day, an arrow or the title did not give the grid the keyboard (the card's TapHandler never sees clicks that MouseAreas take), so arrow keys did nothing after clicking a day (rcd-1 `15-kbd-cursor`, no second goDate). | yes: every click on the card focuses the grid; the cursor starts on a clicked day (rcd-2: click 9, Right Right Down, Enter -> goDate "Friday, 18 September 2026") |
| 4 | low | Calendar: after a click on the card, any return of the keyboard to the desktop (a closed pop-up, a window switch) drew the focus ring on a day (rcd-3 `08-notification`). | yes: the ring state is kept when the grid gets the keyboard back unchanged (rcd-4 `review-calendar-focus.png`) |
| 5 | low | Calendar: day names for screen readers and the tooltip used `Locale.toString(date, LongFormat)`, which adds time and time zone ("Tuesday, September 15, 2026 12:00:00 AM Eastern Daylight Time"; checked with Qt 6.11). | yes: long date format only |
| 6 | low | Calendar: a month browsed to and left there stayed on the desktop indefinitely (the midnight check only followed the month when today's month was shown). | yes: a new day returns to today's month unless browsed in the last minute |
| 7 | low | Calendar: Qt's line box for the 10.5 px weekday row is 16 px (CSS 14.3), which put the day rows about 3 px lower than the board relative to the card. | yes: 14 px row; now +1/+2 px, the expected half of the 4 px taller card |
| 8 | low | Location search: "London" in en_GB listed NOAA's London, Kentucky first and the BBC's London below the fold (results only grouped by name match). | yes: the region's own provider first within each group (`regionalIon`, with tests) |
| 9 | low | Tray expander arrow still shown (passive Vaults, Disks & Devices, Display Configuration). | no: lead decision, as documented above |

Checked and found correct: ids and paths against the naming table; `bash tools/build.sh` (all 13
parts) and two identical `desktopcards` builds; qmllint (only the unqualified `i18n*` warnings),
`node tests/weather.test.js`, `node --check` of the layout script, shellcheck; layout rects
1232,16/160/368 (`ItemGeometries-1440x900`, also at scale 4/3) with StandardBackground; board
comparison at 1:1 dark and light (`review-compare-{dark,light}.png`: sizes, weights, colours,
radius, fills, bars match; offsets only from the 16 px grid); en_US Sunday-first weeks and °F
(NOAA Boston: "64°", "Cloudy · 66° / 57°"), en_GB Monday-first and °C (BBC London); tray keys
written, none of the ten replaced items in the bar or the pop-up; a `notify-send` pop-up still
shows (the notifications applet places pop-ups by the tray's own item, `systemTrayRepresentation`);
kded6 in the session has `audioshortcutsservice`, `mprisservice`, `networkmanagement` and
`bluedevil` loaded (volume/media keys and network/Bluetooth agents do not depend on the tray
items); weather robustness: a BBC source without station id is never connected (card shows "Set
location"), an unknown NOAA station shows "Updating…" then "Weather unavailable" after 45 s;
context menus; "Open System Monitor" starts plasma-systemmonitor detached (parent pid 1);
ksystemstats killed: libksysguard restarts it and the card carries on; rotation to portrait and
back; plasmashell logs: only Kirigami's generic "Created graphical object was not placed in the
graphics scene" for the location page. Builder's ThinkPad claims: no system change found (the
cards under `/usr/share/plasma/plasmoids` belong to the RPM, `rpm -V plasma-fusion` clean; no
per-user copies in the real HOME; no `/tmp/pfv-cd-*` left).

Core dumps (`coredumpctl list --since "2026-09-29 18:25"`): none from the rcd- sessions. One
`kstart --help` (SIGABRT, 18:31:31) is the reviewer's: a read-only probe over plain SSH without a
display, not a test session; the kscreen-doctor/spectacle aborts in the window are other agents'
plain-SSH calls (sessions 3514, 3729 and 3463, "could not connect to display").

Still open: the tray arrow (lead decision); the migration of the real session (lead deploys); the
system-wide RPM predates these fixes; RTL layouts and a missing ksystemstats service ("–" with
empty bars) are covered by code reading only. The system card still costs about 1-1.5 % of a core
more than a static one; a static card needs `Kirigami.Units.longDuration` 0 (global animation
speed "instant"), which also turns the glide off.

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/desktop-cards/review-*.png`
(board comparisons, final dark and light captures at 1440 x 900 en_GB, dark at scale 4/3 en_US
and light at scale 4/3 from before the fixes, location keyboard flow, calendar focus, tray and notification, robustness, portrait) and
`review-logs/` (CPU measurements, KOrganizer stub calls, layout dumps, kded modules, the scenario
and helper scripts).

