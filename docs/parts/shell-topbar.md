# Part: top bar plasmoids (`org.plasmafusion.appname`, `org.plasmafusion.clockpill`)

The left and centre of the Plasma Fusion top bar (Main / MainLight boards `<header>`, renders
desktop-dark-1..4 and desktop-light-1..4): the Fusion logo button with the active application's
name, and the centred pill with workspace dots, date and time. The global menu between them is
the stock `org.kde.plasma.appmenu` widget. Plasma 6 applets, QML only, GPL-2.0-or-later.

Status: built, checked offline and in private virtual sessions on the ThinkPad, dark and light.
Last edited 2026-09-29.

## Files

| Path | What |
|---|---|
| `packages/plasmoids/org.plasmafusion.appname/metadata.json` | Plasma/Applet metadata |
| `.../org.plasmafusion.appname/contents/config/main.xml` | `startPadding`, `endPadding`, `maximumNameWidth` (no settings page) |
| `.../org.plasmafusion.appname/contents/ui/main.qml` | logo button, active application name (TasksModel), launcher activation; tablet window pill, width-budget hook |
| `.../org.plasmafusion.appname/contents/ui/WindowCard.qml` | the tablet window card (Full screen, Split left/right, Minimize, Close) |
| `.../org.plasmafusion.appname/contents/ui/LineIcon.qml` | the card's line glyphs (24-unit SVG paths) |
| `.../org.plasmafusion.appname/contents/ui/FusionLogo.qml` | the three-circle mark |
| `.../org.plasmafusion.appname/contents/ui/FusionText.qml` | text in board px and CSS weight (variable-font `wght` axis) |
| `packages/plasmoids/org.plasmafusion.clockpill/metadata.json` | Plasma/Applet metadata |
| `.../org.plasmafusion.clockpill/contents/config/main.xml`, `config.qml`, `ui/ConfigGeneral.qml` | settings (below) and their page |
| `.../org.plasmafusion.clockpill/contents/ui/main.qml` | the pill, panel centring, workspace switching, calendar pop-up |
| `.../org.plasmafusion.clockpill/contents/ui/WorkspaceDots.qml` | dots / current bar, clicks, keys, tooltips |
| `.../org.plasmafusion.clockpill/contents/ui/WidthBudget.qml` | the top bar's width budget (ADAPTIVE 5.1), run by the clock pill |
| `.../org.plasmafusion.clockpill/contents/ui/CalendarView.qml` | month view of the pop-up |
| `.../org.plasmafusion.clockpill/contents/ui/Chevron.qml`, `FusionText.qml` | 16 px stroke chevron, text helper |
| `.../org.plasmafusion.clockpill/contents/code/formats.js` | locale-aware date and time formats |
| `tools/build.d/70-topbar.sh` | checks the metadata and config XML, copies both packages to `$STAGE/.local/share/plasma/plasmoids/` |

## Install and apply

```
tools/build.sh topbar                      # or STAGE=/some/home tools/build.sh topbar
# per user, from the repository (or copy the two staged folders to ~/.local/share/plasma/plasmoids/):
kpackagetool6 -t Plasma/Applet -i packages/plasmoids/org.plasmafusion.appname     # -u to upgrade
kpackagetool6 -t Plasma/Applet -i packages/plasmoids/org.plasmafusion.clockpill
systemctl --user restart plasma-plasmashell   # after an upgrade
```

The Global Theme layout (`packages/look-and-feel/common/contents/layouts/org.kde.plasma.desktop-layout.js`)
already places them: top panel 34 px, fill, not floating, translucent:
`org.plasmafusion.appname | org.kde.plasma.appmenu | panelspacer | org.plasmafusion.clockpill | panelspacer | systemtray | org.plasmafusion.quicksettings`.
No configuration is needed; the defaults are the board values.

### Settings

`org.plasmafusion.appname`, `[General]` (layout script `writeConfig`; no settings page):

| Key | Default | Meaning |
|---|---|---|
| `startPadding` | 4 | px before the logo button behind a 6 px panel margin, so the button lands at x = 10 as on the board. The padding follows the margin the panel really has (TOP-2): 6 px with the north frame's side margins at 0 (4 px margin), none in the 44 px tablet bar (10 px margin) |
| `endPadding` | 7 | px after the name. With the panel's applet spacing this gives the board's 22 px from the name to the first menu title (measured) |
| `maximumNameWidth` | 220 | longer names are elided; 140 on a narrow screen (`compactWidth`) |

`org.plasmafusion.clockpill`, `[General]` (settings page "General"):

| Key | Default | Meaning |
|---|---|---|
| `showWorkspaces` | true | dots; hidden anyway while there is only one workspace |
| `wheelSwitchesWorkspaces` | true | scrolling over the pill switches workspaces (wraps when KWin's navigation wraps) |
| `showDate` | true | date before the time |
| `dateFormat` | `auto` | `auto`: weekday, day, month in the order of the region's long date, without year and commas (en_GB "Mon 28 Sept", en_US "Mon Sep 28", de_DE "Mo. 28. Sept.", es_ES "lun 28 de sept", ja_JP "9月28日 (月)"); `custom` uses `customDateFormat` |
| `customDateFormat` | `ddd d MMM` | QLocale format |
| `use24hFormat` | 1 | 0 = 12-hour, 1 = region setting, 2 = 24-hour (the stock digital clock's key and values). The region's own short time format is kept whenever it has the wanted hour cycle (en_US "2:49 PM", ko_KR "오후 2:49", zh_TW "下午2:49", fr_CA "14 h 49"); forced 24-hour in a 12-hour region gives "09:05", forced 12-hour in a 24-hour region "2:49 PM" (marker first for zh, ja, ko) |
| `firstDayOfWeek` | -1 | calendar week start, -1 = region |
| `centerInPanel` | true | keep the pill on the middle of the panel (horizontal panels only; see Behaviour) |
| `popupGap` | 10 | px between the bar and the calendar card (the quick-settings pop-up uses 10 too) |
| `widthBudget` | true | the top bar's width budget (TOP-2); off: only tablet posture collapses |
| `menuPolicy` | `centre` | when the budget compacts the global menu: `centre` (whenever the pill cannot stay centred with the full menu, ADAPTIVE 5.1) or `overlap` (only when the bar would otherwise overlap; the pill may leave the middle) |
| `menuCompacted` | false | internal: the budget compacted the global menu (and may switch it back) |
| `debugAction` | "" | testing only: `dump-bar:TAG` logs the bar's widgets, the pill's offset and the budget step |

Formats follow the region settings (`LC_TIME` / KDE Region & Language). The time zone is the
system one.

## Behaviour

### `org.plasmafusion.appname`

- 32 x 26 button, radius 8, 18 px logo (#5b9dff .9, #f2a65a .9, #3cc4b0 .85); hover ink .10,
  pressed / launcher open ink .16 (white on dark, #141827 on light: Launcher boards'
  `aria-pressed` value); 2 px focus ring 2 px outside (#8ab8ff / #2f6fdf). It takes keyboard focus
  (panel focus shortcut, Tab), Enter, Space and Select activate it, and so does the widget's own
  global shortcut.
- Click: D-Bus `org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu`, the
  method KWin calls for the Meta key. It toggles the first `org.kde.plasma.launchermenu` provider in a
  panel of the active screen: the Plasma Fusion launcher (which the layout puts in the dock with
  `buttonStyle=hidden`), otherwise Kickoff. The button grabs the press, so the panel does not send
  a focus-out to the open launcher and a second click closes it.
- The pressed look while the launcher is open (Launcher boards' `aria-pressed`): the launcher
  lives in another panel (the dock), so its state cannot be read from the top bar; it is followed
  through window focus. A toggle request (this button, its shortcut, or the shell's "Activate
  Application Launcher" action, reached through `Plasmoid.containment.corona.action(...)`, which
  fires on Alt+F1) flips the state and expects one focus change as its result. Any later focus
  change means the launcher closed by itself: Esc, Meta, a click on the backdrop or outside, an
  application started, also when the focus goes back to the desktop window and no application
  window becomes active. `TasksModel.activeTaskChanged` is emitted for activation changes of every
  window, the shell's own included (it listens on the unfiltered window model), so this works
  although the active task stays invalid. Signals are folded into bursts (200 ms); a burst with a
  single signal is a shell window going away (a tooltip, a notification) and is ignored. Verified
  with real pointer and key input in the review (see Review). Limit: the Meta key reaches the shell
  through KWin's modifier-only shortcut (a direct D-Bus call), so a launcher opened with Meta does
  not light the button, and closing that launcher with the button leaves it lit until the next
  focus change (one open/close cycle).
- Name: `TasksModel.activeTask` from `org.kde.taskmanager` (no grouping, sorting or filtering),
  role `AppName`, then `GenericName`, then the window title. "Desktop" (translatable) when no
  window is active, which includes while the launcher or another shell pop-up has focus (board
  desktop-dark-2 shows "Desktop" with the launcher open). While the panel itself has keyboard
  focus the last name is kept, as the global menu does. The name is read in a function called on
  `activeTaskChanged`, `dataChanged` (folded with `Qt.callLater`) and `countChanged`; there is no
  binding into the model, so no binding loop is possible.
- Manrope 13 px at `wght` 800 (Qt's named ExtraBold instance adds a synthetic bold, see the
  launcher notes); falls back to the Plasma UI font when Manrope is missing. Colour: the colour
  scheme's text (#e8ebf4 / #141827, the board values).
- Vertical panels: only the button.

### `org.plasmafusion.clockpill`

- Pill 24 px tall, radius 12, padding 0 12, gap 12; ink .08 (white / #141827), hover over the date
  .12, pressed .16; while the calendar is open rgba(91,157,255,.35) with a 1 px rgba(138,184,255,.5)
  edge (the open status pill of the QuickSettings boards).
- Dots: `VirtualDesktopInfo` (current desktop of this screen via `currentDesktopByScreenGeometry`,
  so per-output workspaces work). Current = 18 x 6 bar radius 3 in the text colour, others 6 x 6 at
  .4 (.7 on hover), 4 px apart; the width animates (Kirigami long duration, OutCubic). Each dot has
  a 10 px wide, 24 px tall hit cell and a tooltip (workspace name, "Workspace N of M"). Click a
  dot: `org.kde.KWin /KWin setCurrentDesktop(N)`; click the current one or Enter: Overview
  (`kglobalaccel /component/kwin invokeShortcut Overview`). Keyboard: Tab to the dots, Left/Right,
  Home/End.
- Date Manrope 13 px `wght` 700, time Space Grotesk 13 px `wght` 600 (no SemiBold instance in the
  font; the axis gives the real 600). Missing fonts fall back to the Plasma UI font.
- Centring (horizontal panels only; on the desktop or in a vertical panel the pill stays in its
  own cell): two expanding spacers put the widget near the middle, but they add up the neighbours'
  size hints and the stock global menu is wider than its hint, so with Dolphin's menu the pill
  sat 8 px right of centre (measured, tb-1..2). The widget therefore asks for 48 px of room on each
  side and moves the pill itself to the middle of the panel window, re-placed when its cell moves
  or the window resizes (assigning `pill.x` only, nothing feeds back into a size hint). Measured:
  pill 618..821, centre 719.5, both with and without a menu shown.
- Calendar pop-up (no board; Popups board surface and Main board calendar card styling): an own
  `PlasmaCore.AppletPopup` under the pill, 10 px gap, all corners rounded (style `dialogs/background`,
  radius 22, blur), 280 px content. Header: weekday (12 px 700, secondary) over the long date without
  weekday (Space Grotesk 24 px 600); hairline; month title 13 px 800 with "Today" (only when another
  month is shown) and 26 px chevron buttons; narrow weekday initials 10.5 px 700 tertiary; six weeks
  always (the pop-up never changes size), adjacent days at 35 %, weekends in the tertiary colour
  (region's weekend), today on a 28 px #2f6fdf circle in white 800. Keys: Left/Right and Page
  Up/Down change month, Home returns, Tab reaches Today and the chevrons, Esc closes. Opens with a
  click or Enter on the date, or the widget's global shortcut; closes on focus loss.
- Context menu: "Adjust Date and Time…" (kcm_clock), "Configure Virtual Desktops…".
- Vertical panels are not designed for (the pill is wider than a vertical panel).

## Global menu (stock `org.kde.plasma.appmenu`)

The layout places it right after the app name with its defaults (`compactView=false`,
`allScreens=true`). It cannot be restyled from QML (the applet is compiled into
`/usr/lib64/qt6/plugins/plasma/applets/org.kde.plasma.appmenu.so`); its titles are
`MenuDelegate.qml` buttons (plasma-workspace v6.7.5 `applets/appmenu/qml/MenuDelegate.qml`):

- Background: Plasma style `widgets/menubaritem`, prefixes `normal` / `hover` / `pressed`; the
  frame margins are the padding. The Plasma Fusion style ships margins 4 / 8, radius 6, hover ink
  .10 (dark) / .08 (light), pressed +.04. But each title fills the panel's height
  (`Layout.fillHeight: !root.vertical` in the applet's `main.qml`), so the hover pill is 34 px
  tall, touching the bar's top and bottom (measured with a real hover, review run rtb-d1), where
  the board's pill is 26 px (y 4 to 29: 13 px text plus 4 + 4 padding). The style can fix it by
  drawing the `hover` and `pressed` frames with 4 px of transparent space at the top and bottom
  of their border elements (the frame's margins stay the padding).
- Spacing: the titles sit in a GridLayout with `columnSpacing: 0`; the board has 2 px between
  titles. Not styleable (1-2 px difference per title, measured 19 vs 20 px gaps).
- Text colour: `Kirigami.Theme.textColor` at rest (#e8ebf4 / #141827; the board's #cdd3e4 /
  #3a4157 is not reachable without a Plasma style `colors` file), and
  `Kirigami.Theme.highlightedTextColor` when hovered or open, which is the colour scheme's
  Selection foreground, white. Dark: white on the hover tint, as on the board. **Light: white on a
  light grey pill, contrast 1.3:1 (unreadable)**; confirmed with a real pointer hover in the
  review (`review-appmenu-light-hover.png`; the builder's `appmenu-light-hover-contrast.png` was
  computed).
  Options for the Plasma-style part: accent fill for the light `menubaritem` hover/pressed
  (white text 4.7:1), or a `colors` file in `plasma-fusion-light` whose Selection foreground is
  dark (check every other highlighted state first).
- The menu itself is the application's QMenu (application style, Breeze with Fusion colours).
- GTK/libadwaita apps show no menu (no appmenu-gtk module on Fedora 44); the name still shows.

## Verification

- `qmllint` (`/usr/lib64/qt6/bin/qmllint -I /usr/lib64/qt6/qml`) on every QML file: no warnings
  apart from the usual unqualified `i18n*` notes.
- Build: `STAGE=<scratch>/home tools/build.sh topbar` (metadata and XML checks pass).
  `kpackagetool6 -t Plasma/Applet -i` and `--show` for both packages in a sandbox HOME: installed, metadata read.
- Offscreen harness on the laptop (system PySide6 6.11.2 = Plasma's Qt, real QML, `QTest` keys and
  clicks), `test/harness.py dark|light`: 27 checks pass in both variants: date formats for en_GB,
  en_US, de_DE, es_ES, ru_RU, ja_JP; 12/24 h; header date; grid starts Monday 31 Aug 2026; Right,
  Page Up, Home, Left across the year, Tab to "Today" + Space, Esc; dots Right/End/Home/Return;
  click on a dot and on the current bar. Renders: `offscreen/`.
- D-Bus messages (`test/dbuscalls.py` under `dbus-run-session`, stand-in services on a private bus):
  `setCurrentDesktop(int32 3)`, `invokeShortcut("Overview")`, `activateLauncherMenu()` arrive as sent.
- `test/configpage.py`: the settings page loads offscreen without QML errors and takes the `cfg_` values.
- `test/hovertest.py`: a hover-enabled MouseArea loses hover to a ToolTipArea child on top; both
  widgets therefore put the tooltip area outside the mouse areas (proven Plasma pattern).
- ThinkPad virtual sessions (prefix `tb-`, 1440 x 900, private HOME and D-Bus; scenarios in
  `test/`): four workspaces created through `/VirtualDesktopManager` (Work, Design, Media, Chat),
  top bar as in the Global Theme, Dolphin for the name and global menu, calendar, workspace 3,
  launcher toggle, panel keyboard focus, dark and light (tb-1..3, tb-5); the Global Theme layout
  script itself with the Fusion launcher, dock and quick settings, System Settings active,
  launcher open/closed through the logo button, en_US 12-hour (tb-4; tb-6 with the final code). plasmashell's log has
  no message from either widget.
- Board comparison at the same pixels (tb-5 vs desktop-dark-1 / desktop-light-1): logo ink x 19-29
  (board 20-29); name starts x 51 (51); name end to first menu title 22 px (22); pill top y 5 (5),
  bar at pill x + 12 (same), pill fill (32,36,54) vs (32,35,52) dark; bar fill (13,18,37) vs
  (12,17,36); pill centre 719.5 (721 on the board with its narrower date). Text caps start on the
  same row; Qt draws the 13 px glyphs 1 px shorter than the Chrome render.
- Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/shell-topbar/`:
  `sbs-topbar-{dark,light}.png` (board rows vs build rows), `sbs-topbar-{dark,light}-zoom.png` (3x),
  `calendar-popup-{dark,light}.png`, `appmenu-light-hover-contrast.png`, `offscreen/`,
  `offscreen-{dark,light}.txt`, `dbuscalls.txt`, `vsession/tb-4`, `tb-5`, `tb-6` (full screenshots and logs),
  `test/` (harness, scenarios).

## Deviations from the boards

- "Overview · Workspace 1 · Work" in the bar during Overview (Overview board) is not implemented:
  KWin's Overview draws panels only as fading thumbnails (accepted deviation in PLAN.md), and KWin
  exposes no Overview state signal over D-Bus (`/Effects activeEffects` has no change signal).
- The name is the application's real name ("System Settings", "Dolphin"); the board uses design
  names ("Settings").
- Date text follows CLDR: en_GB abbreviates September as "Sept" (board "Sep").
- Global menu: rest colour #e8ebf4 instead of #cdd3e4, no 2 px gap between titles, and the light
  hover text problem above (stock widget).
- Launcher-open look follows the launcher through window focus (see Behaviour); a launcher opened
  with the Meta key does not light the button, and closing that one with the button leaves the
  button lit until the next focus change.
- Calendar has no events, holidays or week numbers (the stock calendar plugins are not used; the
  stock digital clock is the fallback when they are wanted).
- The pill width changes with the time's digits (proportional figures as on the board); the pill
  stays centred.

## Needs from other parts

- Plasma style + look-and-feel (top bar thickness): **resolved by the current style** (review,
  2026-09-29: after `fusion-config.sh --install` and a login-style plasmashell restart,
  `plasmashellrc [PlasmaViews][Panel 26][Defaults] thickness=34` in dark and light, runs rtb-d1,
  rtb-fd, rtb-fl). The builder's report, kept for reference: with `plasma-fusion-dark/-light`
  active, plasmashell saved the top panel as 48 px instead of 34 px: `PanelView` clamps the
  thickness to `Panel.qml`'s `minPanelHeight` (`translucentItem.minimumDrawingHeight`) before the
  panel's `north` prefix is applied, while the frame still uses the unprefixed (and, for a new
  panel, `south`) `widgets/panel-background` elements, whose rounded 24 px corners give a
  minimum of 48; the clamped value is written back to `plasmashellrc [PlasmaViews][Panel N][Defaults]
  thickness`. Reproduced: tb-3 and tb-5 (`thickness=34` before, `48` after one plasmashell
  restart with the style active; `vsession/tb-5/scenario.log`, `vsession/tb-4/light-L5-en_US.png`),
  and a new panel made while the style is active gets 48 at once (tb-1, tb-2). A login starts
  plasmashell the same way, so the real session is expected to get it too.
  A fix in the style: keep the unprefixed `panel-background` frame's top + bottom border cells at
  most 34 px in total (give vertical panels their own `west-`/`east-` prefixes for the rounded
  shape). A workaround in the layout/config script only lasts until the next start.
  Also seen with the style: "Panel.qml: Binding loop detected for property minPanelHeight".
- **Plasma style (light, still open):** `menubaritem` hover/pressed must be readable with white
  text (see Global menu; verified with a real hover in the review).
- **Plasma style (both variants):** `menubaritem` `hover`/`pressed` frames with 4 px transparent
  insets at top and bottom, so the stock global menu's hover pill is 26 px tall as on the board,
  not the full 34 px bar.
- Look-and-feel: nothing else; the ids and order in the layout match. `appname`'s `startPadding`
  default assumes the 34 px bar (at 48 px the panel margin grows to 10 px).
- Launcher: nothing required. If it ever publishes its open state somewhere another panel's
  widget can read (it cannot over D-Bus from QML), the logo button could mirror Meta-opened
  launchers too.
- Lead (observation, no owner found): during panel keyboard navigation the shell draws a 2 px
  accent line under the focused panel item (also under the stock tray's arrow); the top bar
  widgets draw their own 2 px focus ring as well, so the focused item shows both.

## Review (2026-09-29)

Adversarial review of the part, integrated with every other part as they stand today.

### What was checked

- Board values re-read: Main / MainLight `<header>` (button 32 x 26 r 8, 18 px logo, name 13 px
  800 with padding 0 10 0 6, pill 24 px r 12 ink .08, padding 0 12, gap 12, bar 18 x 6 r 3, dots
  6 x 6 at .4, gap 4, date 700, time Space Grotesk 600), Launcher / LauncherLight (logo
  `aria-pressed` ink .16, name "Desktop", no menu), Overview / OverviewLight, QuickSettings /
  QuickSettingsLight (expanded status pill rgba(91,157,255,.35) + 1 px rgba(138,184,255,.5), pop-up
  top 44 px).
- Build: all parts into a private stage (`STAGE=build/rtb/home tools/build.sh`, rc 0; the
  scratch /tmp was at its quota because of another session, so the git-ignored `build/rtb/` was
  used). Metadata ids match the naming table; the build script's checks pass; no stray files.
- `qmllint` on every QML file: only the unqualified `i18nc` notes.
- ThinkPad sessions `rtb-d1`, `rtb-d2`, `rtb-l2`, `rtb-fd`, `rtb-fl`, `rtb-c1` (1440 x 900):
  the whole desktop set up by `tools/device/fusion-config.sh --install` (Global Theme layout with
  the Fusion launcher, dock and quick settings, four workspaces), then plasmashell restarted as a
  login starts it. **Real pointer and keyboard input** through KWin's EIS D-Bus interface
  (`org.kde.KWin.EIS.RemoteDesktop.connectToEIS`) and libei via Python ctypes
  (`review-test/pfinput.py`, test tooling): hover on the logo, dots, date and menu titles; clicks
  on the logo, a dot (workspace 3), the current bar (Overview opens), the date (calendar
  opens/closes, click-click toggles), right-click (context menu), wheel (workspace 4 and back);
  Esc, Tab, Page Down in the calendar; the settings page opened from the context menu with keys.
- Pixels against the boards, dark and light: bar background, pill fill ((225,228,237) vs board
  (223,227,236) light), pill rows y 5-28, bar colour ((20,24,39) vs (20,23,38)), logo and name
  x positions, calendar card top y 44 (= QuickSettings board pop-up). Evidence:
  `review-topbar-{dark,light}.png`.
- Locale formats offscreen: 22 locales x 3 hour modes (`review-test/locale-formats-test.qml`).
- plasmashell logs of every run: nothing from either widget apart from the settings page note
  below.

### Fixed

- **Logo button stuck pressed / inverted (appname).** On an empty desktop (after login, all
  windows closed) the launcher's focus goes back to the desktop window, a shell window, so
  neither "an application window became active" nor "plasmashell lost focus" happened: after Esc
  or a click on the backdrop the button stayed pressed, and the next open showed it unpressed
  (measured: button (51,56,72) with the launcher closed, rtb-d1 `dark-04-after-esc.png`). Now the
  state follows window focus bursts (see Behaviour); verified for click/Esc/click-close/backdrop,
  over an application window, and with bar tooltips shown while the launcher is open
  (`review-launcher-state-sequence.png`).
- **Alt+F1 (the shell's launcher action) now lights the button** through the corona's shared
  `activate application launcher` action.
- **Time format (clockpill).** The region's own short format is kept whenever it has the wanted
  hour cycle: Korean showed "2:49 오후" (region "오후 2:49") and Taiwanese "2:49 下午" (region
  "下午2:49"); forced 24-hour in a 12-hour region dropped the leading zero ("9:05", now "09:05").
- **U+202F in the time (clockpill).** CLDR's en_US time has a narrow no-break space before PM;
  Space Grotesk has no glyph for it, so Qt would draw that one character with a fallback font
  (different line metrics). Shown as a thin space (U+2009), which the font has.
- **Settings page warnings (clockpill).** Plasma 6.7.5 hands every key's default to the page
  (`cfg_<key>Default`; KF6's config map lists them); the page lacked them, 9 "Setting initial
  properties failed" lines per opening. Declared.
- **Pill self-centring outside a horizontal panel (clockpill).** On the desktop the pill was
  pushed towards the screen centre inside its own widget; now only in horizontal panels.

### Remains

- Meta-opened launcher does not light the logo button (KWin calls the shell over D-Bus
  directly; not observable from a widget); mixing Meta and the button can leave one wrong
  open/close cycle. Documented in Behaviour.
- Stock global menu (plasma-style part): light hover text unreadable (white on light grey),
  hover pill 34 px instead of 26, rest colour, no 2 px gap. See Global menu and Needs.
- Opening the clock pill's settings logs "Created graphical object was not placed in the
  graphics scene" once; the stock system tray's settings page logs the same (from the shell's
  configuration dialog), so it is not this part.
- Panel keyboard navigation shows the shell's accent underline and the widgets' own focus ring
  together.
- The builder's offscreen harness (`test/harness.py`) now reports 26 of 27: its "en_US time,
  region" check expects "2:49 PM" with a plain space; the region format gives U+202F, shown as a
  thin space. The expectation is outdated, not the widget.
- "Overview · Workspace N · Name" title during Overview: not implemented (accepted deviation).

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/shell-topbar/`
`review-topbar-{dark,light}.png`, `review-states-{dark,light}.png`,
`review-launcher-state-sequence.png`, `review-appmenu-light-hover.png`, `review-settings-dark.png`,
`review-full-{dark,light}-{dolphin,calendar}.png`, `review-test/` (scenarios, `pfinput.py`,
`locate.py`, `session-common.sh`, locale test, per-run logs).

## Polish (2026-09-29)

See `docs/parts/polish.md`.

- `FusionText.qml` (both widgets): Plasma Fusion now installs static per-weight font files, which
  ignore the `wght` axis, so the old `font.weight: Normal` + `variableAxes` workaround drew the
  name, date and time in regular weight. The CSS weight is now the font weight (name 800, date
  700, time Space Grotesk 600), measured equal to the board.
- Global menu (plasma-style): light hover / open title readable (accent pill, 4.9-5.5:1 measured),
  pill 26 px tall with 2 px gaps in both variants. The remaining global-menu deviations are the rest
  colour and the light pill colour (accent instead of grey).
- Logo button: a launcher opened with Meta now shows the pressed state and the Meta / logo / Esc
  sequences keep it right (real input, polish run po-8), so the "Meta-opened launcher" limit is
  no longer observed with Plasma 6.7.5.
- The double focus indicator during panel keyboard navigation is kept (the shell's underline is
  the only indicator of the stock tray icons).

## TOP-1 (2026-09-30): clock pill and calendar

Work package TOP-1 of the one-pass plan (BACKLOG M8 and S2, ADAPTIVE 5.1/5.2, TABLET 4.1 and 4.7), built by
the lead directly.

### Changes (`org.plasmafusion.clockpill`)

- **Steady width** (M8): the time sits in a box as wide as the widest of the current time, 10:58
  and 22:58 in the same format (two-digit hours, AM and PM) with every digit the widest one; the
  time and date also ask for tabular figures (`font.features: tnum`). The pill's width never changes
  from minute to minute.
- **Calendar on demand** (S2): the calendar is a `Loader` (asynchronous) that starts building when
  the pointer enters the pill, anything presses it, or a pull-down begins; nothing is built at login.
  The pop-up shows once the calendar is ready. One log line per open gives the time from the request
  to the pop-up's first frame.
- **Touch** (ADAPTIVE 5.1/5.2, TABLET 4.7): in touch mode (`FusionMetrics.touch`: tablet posture from
  `FusionTablet`, or a recent touch) the calendar is 308 px wide with 44 x 44 day cells, 44 px
  navigation buttons, a 17 px month title and a 36 px today disc; the workspace dots get cells of at
  least 24 px. The pill is 32 px tall in tablet posture (24 otherwise) and its hit area is the whole
  bar's height. A **pull-down of 24 px** (TouchScreen only; a layer above the pill's mouse areas that
  holds a passive grab until then) opens the calendar; the travel is taken from the press position,
  because `translation` is still 0 when the handler turns active.
- `Plasmoid.CanFillArea`.
- **Width budget hooks** for TOP-2: `compactLevel` (1: the short date, 2: the time only) and `hideDots`
  (the dots hide; Overview still switches workspaces).
- **Accent and Motion**: the open pill (accent at 35 %, 1 px edge), today's disc (`accent.fill` with its
  text colour) and the focus rings follow the user's accent; the pill's colour, the dots' width and
  colour animate with `Motion` tokens.
- Settings page: the three combo boxes take their index from the model itself (`indexOfValue()` is -1
  until the model is read, which left them on their first entry); the combo, text field and spin box
  have accessible names.

### Verification

- Offscreen (`build/tp/mw/minutes.qml`, the repository's Space Grotesk SemiBold, 13 px at 4/3): every
  minute from 00:00 to 23:59 gives one box width: 47 px for `HH:mm`, 77 px for `h:mm AP` (the text
  alone varies over 3 widths in 12-hour time).
- Private session `tp-1` (1920 x 1200 at 4/3, `build/tp/scen-tp1.sh`, five workspaces): no calendar before
  the first open; the first open's first frame 61 ms after the click (53-91 ms over the runs: the
  pop-up's window is created on its first show, which Plasma offers no way to do earlier without
  showing it; later opens 4-18 ms), so the 50 ms budget is met from the second open on; tablet
  posture: pill 32 px, dot cells 24 px; a 16 px pull-down does not open the calendar and a 30 px one
  does (T10); the touch calendar at 308 px with 44 px cells; text at 12.75 pt: nothing clipped (M12);
  no QML warnings, no core dumps.
- T6 (touch dump) and M18 are part of the INT-1 matrix; every screen has its own pill, so the calendar
  opens on the screen it was asked on.

## TOP-2 (2026-09-30): window pill and card, width budget

Work package TOP-2 of the one-pass plan (TABLET 4.3 and 4.9, ADAPTIVE 5.1 fix 4, LEAD-1 resolution 11),
built by the lead directly.

### Changes

- **Window pill** (`org.plasmafusion.appname`, tablet posture): the logo button and the name become one
  pill, 32 px tall, radius 16, padding 0 14, the app's icon (20 px, `FusionIconTile`) and its name
  (14 px 800, at most 220·ts). In portrait or on a narrow screen only the icon shows (a target of at
  least 44 x 44). The hit area is the whole bar's height and reaches the screen corner (measured:
  x 0-122, 44 tall in landscape). A tap or a 24 px pull-down (TouchScreen) opens the window card;
  with no active window the pill shows the Fusion mark and "Desktop" and opens the launcher.
  `Plasmoid.CanFillArea`, `Motion` tokens for the press scale and colours, `FusionAccent` for the open
  state and the focus ring. On the laptop the button and the name stay as they were; their click area
  now also covers the bar's height and the corner.
- **Window card** (`WindowCard.qml`, built on first open in an asynchronous `Loader`): 320 px, a 56 px
  header (icon 32, app name 15 px 800, window title 12.5 px at 75 %), 52 px rows (glyph 20, label 15 px
  600): **Full screen** with a switch, **Split left**, **Split right**, **Minimize**, **Close** (#D9434B).
  Keyboard: the switch has the focus, Up/Down move, Return/Space act, Escape closes. The card acts on
  the window that was active when it opened (looked up by its window id when an action runs).
  - Full screen off (LEAD-1 resolution 11): `TasksModel.requestToggleMaximized` for that window only.
    KWin gives the title bar back on un-maximize (the borderless-maximized option). The tablet script
    (`plasmafusion-tablet`) now follows maximize changes: a window the user un-maximizes leaves its
    lists, so it is not touched when tablet mode ends; one that first opened in tablet mode gets 70 % of
    the work area. The next fold maximizes it again. The global switch stays QS-1's "Full-screen apps".
  - Split: the card activates the window, waits until KWin reports it active, then invokes "Window
    Quick Tile Left/Right" (component `kwin`); the tile loses its title bar as before (KWIN-1).
- **Width budget** (`WidthBudget.qml` in the clock pill, which sits between the bar's two expanding
  spacers): the pill stays on the middle while each side fits within W/2 − pill/2 − 24; otherwise the
  steps of ADAPTIVE 5.1 apply in order: 1 the global menu compact, 2 phone and clipboard into quick
  settings (QS-1 adds its hook), 3 the app name hidden, 4 the short date, 5 the time only, 6 no
  battery % (QS-1), 7 no workspace dots. Tablet posture starts at step 2, portrait or a narrow screen
  at step 5 (TABLET 4.3); the clock pill has no dots in tablet posture and uses 14 px 800 text with
  16 px padding. The step is computed in one go from the widgets' level-0 widths: each Fusion widget
  of the bar has `budgetLevel` and `budgetSaving(level)`; the stock menu's full width is measured from
  its menu model (titles in the panel font plus the `menubaritem` margins; measured exactly equal to
  the full view for Konsole, Dolphin and Kate). Nothing is laid out to be judged, so nothing flickers.
- **Global menu crash (Plasma 6.7.5)**: the stock appmenu crashes plasmashell when it goes from its
  compact view back to its full view after its menu changed (the full view is kept unparented and
  its layout keeps a deleted item; libplasma `AppletQuickItemPrivate::compactRepresentationCheck`).
  Private sessions t2m, E1-E6: compact and back without a menu change is safe; after an app switch
  it crashes every time; `destroy()` on the cached view is refused and a forced layout rebuild does
  not help; a menu that loaded compact (no full view built yet) switches back safely. A hidden
  layout does not lay out, so a change while the applet hides its full view (the active window has
  no menu) counts too: private session ov2 (tablet, portrait, no menu, then Konsole's menu and the
  compact switch in the same moment, back to landscape) crashed; after the fix below, ov3 and
  oB1-oB3 did not (the deployed 0efb34f crashed in oA2 as well, 2 of 4 runs). So the budget counts
  a menu as seen only after two frames were drawn while the full view showed it
  (`fullSeenGeneration`), and switches the menu back only when the full view was never built or has
  seen the current menu; otherwise it stays compact until plasmashell starts again (one log line
  says so; the compact line prints both counts). Control runs: compact and back without a change
  still goes back (ov4); a change while hidden, then shown for a few seconds, then compact and back
  is safe with the stock menu (ov5 T1), a change while compact crashes (ov5 T2). Left open: libplasma
  preloads a compact applet's full view once, 1-5 s after plasmashell starts, when it loaded
  compact; if the budget compacts the menu again inside that time and the menu then changes, the
  preload reads the stale layout and crashes (seen once, oA2, right after a KCrash restart in
  tablet posture). A start in laptop posture with the menu left compact is safe (sA1-2, sB1-2: the
  full menu comes back and stays). `menuPolicy=overlap` compacts it only when the bar would
  otherwise overlap (the pill then leaves the middle), which keeps full menus far more often. The
  earlier plan to switch it from the tablet script's panel script is dropped for the same reason.
- **Left edge**: the app-name widget reads its own x in the panel window and pads to the board's
  10 px from whatever margin the panel has (the north frame's side margins 6 or 0, the tablet bar's
  larger margin); its click area reaches the screen corner.
- **Alt underlines (ADAPTIVE 26)**: the stock appmenu shows accelerator underlines while Alt is held
  (`Kirigami.MnemonicData.active: altState.pressed` in its `main.qml`), so holding Alt for Alt+Tab shows
  them. The applet has no option for it: accepted, as the plan allows.
- Not in TOP-2: the keyboard button (quick settings, QS-1); the Chrome stretch (BACKLOG C2, app-name
  button actions for apps without a global menu) is left for later.

### Verification

- `qmllint` (Qt 6.11) on the changed files: only the unqualified `i18n*` notes (the clock pill's two
  calendar-loader casts fixed on the way); `a11y-lint` and `motion-lint`: nothing new.
- Private session `t2a` (1920 x 1200 at 4/3; `build/t2/scen-t2a.sh`): with Konsole and Dolphin
  maximized in tablet posture, a tap on the pill opens the card (first frame 52-70 ms after the tap,
  the pop-up window's creation, as the calendar's); Full screen off: Konsole un-maximized with its
  title bar (1048 x 740), Dolphin still full screen and borderless; Split left from the card: Dolphin
  in the left tile (711 px with the tile gaps, no title bar, T18); a pull-down on the pill opens the
  card; after the next fold Konsole is full screen again. Portrait (rotated): the pill shows the icon
  only (51 px), the clock the time only.
- Width budget, judged by `build/t2/check-bars.py` from the clock pill's `dump-bar` lines (no two widgets
  overlap, quick settings inside the window, pill offset): `t2a` (1440 x 900 and its portrait 900 x 1440,
  laptop and tablet, Konsole, Dolphin, Kate), `t2m19` (1024 x 768 at 1, M19) and `t2m12` (12.75 pt, M12):
  every one of the 27 bars has the pill within 0.5 px of the middle, no overlap, the bell and the
  battery fully visible. Konsole and Dolphin keep their full menus at 1440 x 900; Kate, portrait, M19
  and M12 compact it.
- No plasmashell crash in the final runs (the probe runs' seven core dumps were removed); no QML
  warnings from the two widgets.

