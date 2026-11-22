# Part: top bar plasmoids (`org.plasmafusion.appname`, `org.plasmafusion.clockpill`)

The left and centre of the Plasma Fusion top bar (Main / MainLight boards `<header>`, renders
desktop-dark-1..4 and desktop-light-1..4): the Fusion logo button with the active application's
name, and the centred pill with workspace dots, date and time. The global menu between them is
the stock `org.kde.plasma.appmenu` widget. Plasma 6 applets, QML only, GPL-2.0-or-later.

Status: built, checked offline and in private virtual sessions on the ThinkPad, dark and light.
Last edited 2026-11-21.

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
| `.../org.plasmafusion.clockpill/contents/config/main.xml`, `config.qml`, `ui/ConfigGeneral.qml`, `ui/ConfigCalendar.qml`, `ui/ConfigTimeZones.qml` | settings (below) and their three pages |
| `.../org.plasmafusion.clockpill/contents/ui/main.qml` | the pill, panel centring, workspace switching, calendar pop-up |
| `.../org.plasmafusion.clockpill/contents/ui/WorkspaceDots.qml` | dots / current bar, clicks, keys, tooltips |
| `.../org.plasmafusion.clockpill/contents/ui/WidthBudget.qml` | the top bar's width budget (ADAPTIVE 5.1), run by the clock pill |
| `.../org.plasmafusion.clockpill/contents/ui/CalendarView.qml` | month view of the pop-up |
| `.../org.plasmafusion.clockpill/contents/ui/LayoutState.qml` | the bar's workspace layout state, the clock's side of the layout transport, and the layout menu's action |
| `.../org.plasmafusion.clockpill/contents/ui/LayoutControl.qml` | the workspace layout control in the pill, read only |
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
| `wheelSwitchesWorkspaces` | true | scrolling over the pill switches workspaces (wraps when KWin's navigation wraps); a page scroll still turning as the pointer passes over the pill is ignored (`FusionWheelGuard`, shared-blocks.md) |
| `showLayoutControl` | true | the dynamic tiling control (Floating or Tiled for the current workspace), which appears only once the placement script confirms that tiling is available there; the control itself comes in P4 (`tasks/workspace-layout-control/todo.md`), and the tiling shortcut works either way. Off, the bar's layout state stays idle, with no request and no wake, and its saved request is withdrawn. Settings: "Workspaces: Show the dynamic tiling control" |
| `showDate` | true | date before the time |
| `dateFormat` | `auto` | `auto`: weekday, day, month in the order of the region's long date, without year and commas (en_GB "Mon 28 Sept", en_US "Mon Sep 28", de_DE "Mo. 28. Sept.", es_ES "lun 28 de sept", ja_JP "9月28日 (月)"); `custom` uses `customDateFormat` |
| `customDateFormat` | `ddd d MMM` | QLocale format |
| `use24hFormat` | 1 | 0 = 12-hour, 1 = region setting, 2 = 24-hour (the stock digital clock's key and values). The region's own short time format is kept whenever it has the wanted hour cycle (en_US "2:49 PM", ko_KR "오후 2:49", zh_TW "下午2:49", fr_CA "14 h 49"); forced 24-hour in a 12-hour region gives "09:05", forced 12-hour in a 24-hour region "2:49 PM" (marker first for zh, ja, ko) |
| `showSeconds` | false | opt-in seconds; native Clock tracks seconds only while requested |
| `selectedTimeZones` | `Local` | world clocks in the calendar popup, chosen through the searchable Time zones settings page |
| `firstDayOfWeek` | -1 | calendar week start, -1 = region |
| `enabledCalendarPlugins` | empty | native calendar providers enabled in the Calendar settings page; their own resource pages appear after Apply |
| `centerInPanel` | true | keep the pill on the middle of the panel (horizontal panels only; see Behaviour) |
| `popupGap` | 10 | px between the bar and the calendar card (the quick-settings pop-up uses 10 too) |
| `widthBudget` | true | the top bar's width budget (TOP-2); off: only tablet posture collapses |
| `menuPolicy` | `centre` | when the budget compacts the global menu: `centre` (whenever the pill cannot stay centred with the full menu, ADAPTIVE 5.1) or `overlap` (only when the bar would otherwise overlap; the pill may leave the middle) |
| `menuSearch` | `false` | show the global menu's Search entry. Off because Plasma's applet (6.7.5 and 6.8.3) crashes when you type in it after the active app rebuilt a submenu (Chrome's History does): it keeps pointers to deleted menu items. A KDE bug ([526561](https://bugs.kde.org/show_bug.cgi?id=526561)), reproduced with a stock panel on 6.7.5 and 6.8.3; analysis and the upstream drafts in the appmenu crash record of 2026-10-02 (the maintainer's records). Arrowing right past the last menu skips the hidden entry and wraps to the first menu. The rebuilt plasma-workspace of `packaging/patches/plasma-workspace` (its README) carries the fix and names the action `appmenu-guarded`: the entry is shown there whatever the key says, and hidden again when a Fedora update replaces the rebuild. Settings: "Global menu: Show the Search entry" |
| `menuCompacted` | false | internal: the budget compacted the global menu (and may switch it back) |
| `debugAction` | "" | testing only: `dump-bar:TAG` logs the bar's widgets, the pill's offset and the budget step; `dump-layout:TAG` the bar's workspace layout state |
| `layoutRequest` | "" | internal: the clock's query to the placement script's layout provider ([Workspace layout state](#workspace-layout-state-layoutstateqml)), which the provider reads through desktop scripting |
| `layoutResponse` | "" | internal: the provider's answer, written through desktop scripting; a saved answer alone never counts. Declared, it makes each frame the provider writes cost the shell a save of the widget's configuration ([kwin.md](kwin.md#the-layout-providers-state), what a call costs the shell) |

Formats follow the region settings (`LC_TIME` / KDE Region & Language). The time zone is the
system one.
The panel keeps the system time zone. Add world clocks in the Time zones page without changing it;
the popup shows each selected city's time and date through KDE's native Clock, including DST and
next/previous-day differences. At least one zone stays selected. Optional seconds preserve the
region's AM/PM placement and the chosen 12/24-hour cycle.

## Behaviour

### Calendar agenda and setup

The popup now selects a day by click or with Left/Right/Up/Down; Page Up/Down changes the month
and clamps the selected day, Home returns to today. Event dots and the selected-day agenda use
Plasma's native calendar providers, including KDE PIM's timed, all-day and recurring appointments.
Long content scrolls within the work area. Missing or unselected providers show setup guidance,
distinct from a configured day with no events.

Choose **Calendar settings → Calendar**, enable **Calendar Events** (called PIM Events in some
versions), Apply, then choose the calendars
in the **Calendar Events** resource page. Install the distribution's KDE PIM add-ons if that provider
is absent. KOrganizer or Merkuro manages local calendars, accounts/sync, recurrence and reminders;
Fusion does not store credentials or start a second alarm service. Holidays and other installed
providers can also be enabled in the same page.

**Open calendar** uses KDE's calendar application integration (the calendar application the
system uses); KOrganizer is first sent to the selected day only when it is that application
(`code/calendar.js`, tests/calendar.test.js), so another calendar application opens without
starting KOrganizer. **Add event** is available when
KOrganizer's D-Bus service is installed and opens its native editor. The editor's initial date/time
follows KOrganizer's own current-view defaults and remains editable; Fusion does not save an event
until the user confirms it there. Browsing dates works without a calendar app or provider.

Regression checks (Qt/PySide6, offscreen and a private bus):

```sh
STAGE=build/parity-stage tools/build.sh topbar
QT_QPA_PLATFORM=offscreen dbus-run-session --config-file=packages/kwin/tests/offscreen/session-bus.conf -- \
  python3 packages/plasmoids/org.plasmafusion.clockpill/tests/calendar_backend_test.py
QT_QPA_PLATFORM=offscreen dbus-run-session --config-file=packages/kwin/tests/offscreen/session-bus.conf -- \
  python3 packages/plasmoids/org.plasmafusion.clockpill/tests/calendar_view_test.py build/parity-stage
```

Native adapter checks cover week start, missing providers, year rollover and leap day; view checks
cover click/keyboard selection and touch targets. Real PIM integration was verified in an isolated
Fedora VM with synthetic timed/all-day/recurring events, provider/resource settings and the native
event editor. The backend keeps pending editor calls alive when the popup loses focus. The view
checks also cover the adapter's lifetime: it unloads when the popup closes, stays loaded while a
call it made is running, and unloads with no binding loop.

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
- The workspace layout control between the dots and the date ("Workspace layout control" below).
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
  (region's weekend), today on a 28 px #2f6fdf circle in white 800. Keys: Left/Right selects a day,
  Up/Down moves a week, Page Up/Down changes month, Home returns, Tab reaches the controls, Esc closes. Opens with a
  click or Enter on the date, or the widget's global shortcut; closes on focus loss.
- Context menu: "Adjust Date and Time…" (kcm_clock), "Configure Virtual Desktops…".
- Vertical panels are not designed for (the pill is wider than a vertical panel).

### Workspace layout state (`LayoutState.qml`)

The clock's side of the workspace layout transport, whose other side is the placement script's
layout provider ([kwin.md](kwin.md#the-layout-providers-state)); the pill's layout control shows
it (below). The component's owner passes the saved answer in (`response`), saves each request it
is asked to (`requested`), may shorten the requests' deadline (`deadlineMs`) and may wake the
provider (`wake()`). The clock's `main.qml` owns it:

- It asks for its window's output (`Screen.name`) while the control may show: the user's setting
  on (`showLayoutControl`), and the bar's own layout one that shows it, a horizontal panel outside
  tablet posture (the specification's scope; a clock on the desktop is not the top bar).
  Otherwise the component stays idle, with no request and no wake. The saved request is then
  withdrawn - at start, when the user hides the control, when the bar's layout does and when it has
  no output name (`Screen.name` empty) - and the provider woken (`wake()`): an empty `layoutRequest`
  is no request, so the provider forgets the widget at that read, and no frame, and no save of the
  configuration, keeps following a bar that shows nothing. On a change the withdrawal waits for
  whatever made it (`Qt.callLater`): the settings dialog's Apply writes the setting first, then the
  page's copy of the request, and saves.
- It binds `response` to the configuration's `layoutResponse`, and writes each request to
  `layoutRequest` and saves the configuration (`writeConfig()`) before the component wakes the
  provider: desktop scripting reads the saved configuration, not the property map.
- A request with no answer taken by its deadline is said once in the shell's log, "no layout answer
  was taken in time; the mode is unknown until one is": no placement script, stock KWin, a Kiosk
  policy that refuses the shell's scripting, or an answer whose check failed. A late answer still
  counts. The testing hook `dump-layout:TAG` (`debugAction`) logs the state.

- A request is a version-1 `query` for the bar's output (`outputName`, 1 to 128 characters):
  `{version, intent, consumer, request, outputName}`, or one of the layout action's intents, a
  `prepare` or a `set` ("The layout action" below). The consumer is drawn fresh for each instance
  (an MD5 of a timestamp and random numbers), and requests are numbered from 1. The component asks
  at its start and whenever the output changes - never on a view change, which the provider pushes
  itself - and with no output it asks nothing (`outcome` idle). Each ask retires the request that
  was out, going idle among them, so no answer to it, late or being checked, counts. Once the owner
  has saved the request, it wakes the provider
  (`kglobalaccel /component/kwin invokeShortcut "Plasma Fusion: Refresh Layout Controls"`), which
  reads only when woken.
- An answer counts only as the provider's version-1 frame for this instance's consumer and current
  request, of at most 4096 characters: an epoch of 32 lower-case hex digits, the identity name
  `org.plasmafusion.LayoutProvider.p` and that epoch, a backend owner that is a unique connection
  name, an integer revision up to 2147483646, and online - with `capable`, `tiled`, which needs both
  capability and a view, and a `view` that is null or names the requested output with a desktop of 1
  to 128 characters and an activity of at most 128, possibly empty - or online with a refusal of 1
  to 64 characters, or offline, with nothing capable, no view and nothing tiled. Such a frame is
  then checked on the session bus, one at a time: the owner of `org.kde.KWin` must be the frame's
  backend owner, and for an online frame that connection must also own the identity name. A lookup
  that fails ends the check and confirms nothing, and nothing that comes after the component is
  gone, a reply or a request queued just before, touches it. An offline frame comes as its lifetime
  releases that name, so it counts only from the lifetime the request is bound to, on that
  lifetime's connection. Of the frames that come while one is checked, only the newest of one
  lifetime waits.
- The first answer accepted binds the request to its lifetime. A newer revision from it is taken,
  among them a frame the provider pushes for a view change with no request of its own; an older or
  equal one is not, but for an intent's first frame, which may come at the revision shown ("The
  layout action" below). A frame from another lifetime makes the bar ask again, as revisions do not
  carry over between lifetimes, and so does the bound lifetime's offline frame. A new query starts
  unknown and from no revision, so its answer may come at the revision the last one had. That holds
  for queries only: an intent keeps the answer held until its own first frame or its deadline
  ("The layout action" below).
- A lifetime can also go with no frame, when its script or KWin stops without one. The component
  watches the session bus's `NameOwnerChanged` through the workspace plugin's `SignalWatcher` (the
  same at plasma-workspace 6.7.5 and 6.8.3), with no polling. The bound lifetime's connection holds
  its identity name and `org.kde.KWin`, so once either changes hands - released, or handed straight
  to another connection - the bar is unknown and asks again, and whichever provider comes next reads
  the saved request. A watch of whether a name is held, the plugin's `DBusServiceWatcher`, would
  miss the handover: that is one change, naming both owners. The watch hears every name change on
  the session bus, as the plugin's match names no name, and each costs the component two
  comparisons.
- A check needs one rule of its own. Its lookups share the session connection with the watch, and
  the bus says an owner changed before it answers any lookup made after it, so a change before a
  lookup fails it, and one after the check's answer is taken finds the lifetime bound. But a check
  looks up KWin's owner first and the identity name's last. KWin's name moving from the frame's
  owner between the two would let the check take a lifetime KWin no longer has, so a move of KWin's
  name from the owner of the frame being checked also makes the bar ask again, which retires the
  request the check would answer. A move said just before the check began counts as well, as
  asking again is always safe. Each lookup gives the plugin its signature, so no introspection
  round trip comes first.
- The component reports `outcome` - idle, pending, unconfirmed, answered, or refused with `refusal`
  its reason - apart from the state an answer gives: `capable`, `view`, `tiled`, `epoch` and
  `revision`. `mode` follows the answer held: unknown until an answer is accepted, unavailable when
  the provider cannot tile or KWin has no such output, and otherwise floating or tiled. For a query
  it agrees with `outcome`, as a query drops the answer it replaces. A saved answer alone is never
  state: an earlier instance's answer names that instance's consumer.
- Each request has a deadline, `deadlineMs`: 100 to 10000 ms, and 10000 for any other value,
  which starts as the request is made. A request keeps the deadline it was made with, and a change
  applies from the next request. Past it with no answer, the outcome is unconfirmed and the mode
  is unknown, but the request stays out: nothing is cancelled, renumbered or asked again, and a
  late answer still counts, as in P0's transport (`tasks/workspace-layout-control/g0-receipt.md`,
  item 9). That covers an answer that does not come - a Kiosk policy that refuses the shell's
  scripting, no placement script, stock KWin, a wake that fails - and a check whose lookup fails,
  which leaves the request pending. A new request starts its own deadline, so the one it replaces
  cannot end it, and an answer or going idle ends the wait. The read-only control below shows
  nothing while a query is pending, as the mode it showed no longer applies and nothing is confirmed
  yet; the pending state of the specification's item 7 follows an explicit request, P6's. Once
  unconfirmed the bar shows no control that looks as if it works (item 8), as nothing has been said
  of its view.

Tests: `tests/calendar_backend_test.py`, run as above, also checks the layout state against
stand-ins on its private bus - `org.kde.KWin` and the lifetimes' identity names on its own
connection or a second one, and kglobalaccel's component recording the wakes. It covers the request
and the wake after it, the answer an earlier instance was given, a reply or a queued request after
the component is gone, the malformed forms, the bus checks with KWin's name unowned or moved among
them, revision order and the frames that wait, an output KWin does not have, a refusal, another
lifetime, offline frames from the bound lifetime and from others, a frame checked as its request
moves on, and going idle. It also covers a provider lost with no frame: the bound identity name or
KWin's name released, and KWin's name handed straight to another connection (one change, recorded),
against names that change hands with nothing bound, or nothing of the bound lifetime, and a name
released after the component is gone. For the check's rule, KWin's name is handed on in the same
turn as a frame arrives - before the check's first lookup or between its two, which the test cannot
tell apart - against a move from another owner during a check and one after it. The deadline is
checked with a short one, timed from just before the step that asks: a request with no answer ends
unconfirmed, with nothing asked again; a late answer counts; an answer before the deadline, or going
idle, ends the wait; a new request gets a full deadline of its own, and keeps it when the owner
changes `deadlineMs`; a failed check, or a wake that fails with kglobalaccel gone from the bus,
leaves the request to its deadline, with nothing asked again; a deadline outside 100 to 10000 ms
gives the timer 10 s; and one that would end after the component is gone touches nothing. Its
layout-state checks go on after a failure, so that one run shows them all.
It runs `main.qml`'s wiring - the block between its `BEGIN layout state` and `END layout state`
lines - unchanged in a fixture that supplies the configuration and the screen, as the launcher's
opening test runs `main.qml`'s blocks: the request saved before the wake, the answer through
`layoutResponse`, a hidden control leaving the state idle and withdrawing the saved request with
one save and then a wake, and shown again asking again, another screen asking for its output, the
`dump-layout` hook, and of all the outcomes only a request with no answer taken by its deadline
said, once. Three more fixtures start with a configuration already set: hidden with a request
saved earlier (withdrawn with one save and one wake), hidden with none (nothing saved, no wake),
and shown with one (nothing withdrawn, the clock's own request its one save). A fourth replays the
settings dialog's Apply in one turn - the setting written false, the page's copy of the request
written back, the configuration saved - and the request must still end withdrawn. Three start in
tablet posture, on a vertical panel and outside a panel (nothing asked; a request saved earlier
withdrawn with one save and one wake), and one meets tablet posture coming (idle, withdrawn, then
woken) and going (asking again); one loses its screen and gets it back the same way. The control's
place in the width budget is checked at every step against a stand-in control: its level, and the
width it gives up, none while it shows no mode.
`runDebugAction`, outside the block, is checked as text for its `dump-layout` branch, and the
fixtures must log nothing but the dumps and the one unanswered line. The pill's short date at the
width budget's step 4 runs through `main.qml`'s own binding in eight regions: the day and the
month in the region's order, without the year and what joined it to them.

### The layout action (`LayoutState.qml`)

The layout menu's Floating and Tiled choices (P6 of `tasks/workspace-layout-control/todo.md`)
reach the provider's prepared target and desired mode
([kwin.md](kwin.md#the-layout-providers-state)) through the layout state, which makes every
decision. The menu and the pill's interactive control, which come in P6's later slices, forward the
user's input to it and bind to the action's state; until then nothing calls it, and the bar sends
queries only.

- `open()` freezes the action's context from the answer the bar holds - its lifetime (`epoch`), its
  `view` (`desktopId`, `activityId`) and the output - and sends nothing, so a menu opened and closed
  again holds nothing of the provider's. It returns false and changes nothing unless the action is
  idle with actions available: while a set is awaited, the control's activation is ignored.
  `input()` is the menu's first counted input, a navigation or choosing key or a press on a row: it
  sends the prepare, which takes the provider's one prepared slot - one for all the bars, so that
  while one holds it a prepare from any other is refused `busy` - and an open menu alone never holds
  it. `choose(mode)` is the user's choice, `tiled` or `floating`: queued with a prepare while
  nothing is prepared, sent as a set once prepared. Re-selecting the mode shown sends a set too,
  which the provider makes a no-op: the authority decides, not a mode that may lag it.
  `close(dismissed)` says the menu closed, `dismissed` when the user closed it (Escape, or a press
  on the control).
- `actionsAvailable` holds while a mode shows, tiled or floating, and the answering lifetime has not
  refused the intents (below). `actionOpen` holds from `open()` until the action ends; the menu
  shows only then. `actionState` is `idle` (no action, or one that ended with nothing awaited),
  `open` (nothing in flight: the next input prepares), `preparing` (the prepare is out with no
  frame), `prepared` (the prepare is done and its newest frame says ready), `setting` (the set is
  out, the menu still open) or `awaiting` (the action has ended, its set awaited before its
  deadline). `actionChoice` is the choice queued or sent, kept until the next request so that an
  outcome shown after it is worded for its mode; `actionPending` holds while a choice is queued or
  a set is out. `actionHandle` and `actionTarget` are the done prepare's handle and whether it found
  an app to tile, held only while prepared. `tiledBlocked` holds while prepared with no target on a
  floating view; on a tiled view Tiled needs none. `actionReason` is what the menu's status line or
  the pill presents, or empty: a provider's reason, or the bar's own `unconfirmed` (no answer by the
  deadline), `interrupted` (the menu closed by itself before its set was read) and `malformed` (a
  frame without the intent's fields).
- `actionOutcome(reason, mode)` is emitted whenever a row of the table below presents a reason,
  with the mode it concerns (`actionChoice` at that moment, empty for none), and with an empty
  reason when a done set clears a notice. It comes after every other change of its event, so that
  a handler sees the action as the row leaves it; the clock's handler will be the only one to
  announce it.
- Callers. Each input, frame or deadline decides first and then changes each property at most
  once - the action's properties, `mode` and `outcome` among them - so that a binding never sees a
  value the event does not leave; no property passes through one. Which property changes first is
  not settled, though: inside the change handler of one property the others may not have followed
  yet, so a handler acts on the property whose change it handles, or on `actionOutcome()`, which
  comes last and may read them all. A handler that runs inside the layout state's own change - the
  menu's hide, as `actionOpen` or `actionsAvailable` turns false, or the control's, as the mode
  stops showing - only calls `close(false)`. That call always meets an ended action and changes
  nothing: every event ends the action before the mode or the actions go (a frame whose mode leaves
  nothing to act on, a refusal, a deadline, asking again), and records how the menu closed before
  `actionOpen` changes.
- The intents carry exactly the keys the provider's reader copies: a prepare
  `{version, intent, consumer, request, outputName, epoch, view: {desktopId, activityId}}`, a set
  `{version, intent, consumer, request, outputName, mode, handle}`. They share the queries'
  numbering, deadline and save-then-wake path, and each clears the frame waiting for its check.
- An intent keeps the answer the bar holds, so the mode stays on screen while it is out, until its
  first frame is taken - which may come at the revision shown, as a done prepare moves none, but
  not below it, and is taken once, as every later frame needs a newer revision - or until its
  deadline. Past the deadline with no frame the mode is unknown and the control hides, as for a
  query: an intent the provider never read would otherwise keep a view's mode past a desktop switch
  or a press of the shortcut. The request stays out, and a late frame from the bound lifetime shows
  the mode again. The deadline belongs to the request, not to the action: it drops the kept mode
  whether the action is still waiting, has ended, or has been opened again meanwhile. `outcome`
  keeps its meaning for every request - pending until its first frame, answered or refused then,
  unconfirmed past its deadline with no frame - while `mode` follows the answer held.
- Which frames count. Every frame of the current request gives the mode. Its completion and
  preparation count only on the action's own request while the action waits for them (preparing,
  prepared, setting and awaiting: only the action's requests lead there, and any other request ends
  the action first), and for a set's first completion after its deadline, in idle or in the action
  that sent the set: an action opened after the deadline takes it for the mode only. A completion
  counts once, from the first frame that carries one: every later frame of the request carries it
  again, and each desktop switch publishes the request anew. The one later field that counts is a
  prepared action's `prepared.ready`. On the action's own request the intent's fields must be as
  the provider adds them: a prepare's completion naming the prepare, `result` `done` or `refused`
  with a reason of 1 to 64 characters, a done prepare's handle of at most 128 characters beginning
  with the frame's epoch and a colon, a boolean `target` with a reason when false, and on a done
  prepare's frame `prepared` with that handle, a boolean `ready` and a reason when not ready (on a
  refused prepare's frame, which the provider gives none, a `prepared` is only checked for that
  form); a set's frames carry a completion naming the set only once it is decided, and never
  `prepared`.
- Refused intents. An own frame refused at frame level while the action waits for it (preparing,
  setting, awaiting) ends the action with that reason, and the bar asks again with a query, which
  starts unknown as every query does. `intent`, `version` and `malformed` leave the lifetime without
  actions until another lifetime answers: such a provider would refuse every further choice the same
  way, and a control that kept offering them would look as if it worked. An own frame without the
  intent's fields does the same and presents `malformed`: dropping it would leave the bar to the
  deadline whenever that provider answers so, and taking it as not ready would fail every further
  choice. `output` leaves the actions available, as the query is refused the same way. So a provider
  older than P5 costs one failed try before the control turns read-only. Once the action has ended,
  a frame refused at frame level for its intent - still the current request - asks again in the same
  way and marks the lifetime for the same reasons, but presents nothing, and an action opened since
  then ends, as nothing is left to act on (T16a). So does such a frame for an open action's own
  intent after its decision, so that the bar asks again rather than leave the mode unknown; P5 never
  sends one, as it refuses a request at frame level from the request's content alone, and so from
  its first frame on. In prepared, and for an open action's own set still undecided past its
  deadline, such a frame gives the mode only, and the action ends through T34 with no reason
  presented and no query. Each lifetime left without actions is said once in the shell's log, naming
  the side that failed: "the provider refused the bar's prepare (or set) at frame level with" the
  reason, or "the provider sent a frame for the bar's prepare (or set) that lacked the intent's
  fields", then "the layout actions are off for its lifetime" and its epoch. No intent goes to a
  lifetime so marked, so nothing repeats the line.
- The frame's mode comes first: a frame whose mode leaves nothing to act on ends the action (T34)
  before its completion counts, so no set goes out on a frame that hides the control, and a set
  already out is then awaited, its completion in that frame included. That end is no close by the
  user, whatever an earlier action's close was.

The table: q is the queued choice; an own frame is a frame of the request the action sent last,
while it is the current request. "Ready" means the newest accepted frame of the prepare says
`prepared.ready: true`, and a sendable q is Floating, or Tiled with a target or on a tiled view.
"Presents" sets `actionReason` and emits `actionOutcome()` with it; a row that presents nothing
clears `actionReason` only when it changes the state, and every request sent clears it. A next
state of `idle` or `awaiting` ends the action (`actionOpen` false): every end drops q and records
how the menu closed, once, before the change is notified - the change hides the menu, whose hide
calls `close(false)` at once, possibly from inside the call or the frame that ended the action, and
that call must meet the ended action. Only `close(true)` records the user's close; afterwards only
T22 changes the record, and the move from `awaiting` to `idle` keeps it.

| # | In | Event | Next | Sends | Presents |
|---|---|---|---|---|---|
| T1 | idle | `open()`, actions available | open | nothing | nothing; `open()` is true |
| T2 | any other, or idle without actions | `open()` | unchanged | nothing | nothing; `open()` is false |
| T3 | open | `input()` | preparing | prepare | nothing |
| T4 | open | `choose(m)` | preparing, q = m | prepare | nothing |
| T5 | open | an accepted frame of the current request names a view other than the frozen one: the frame that moved the action into open included, the newest accepted frame on entering open through T31, and the frames T35 and T35a take | idle | nothing | nothing |
| T6 | preparing | `choose(m)` with no q | preparing, q = m | nothing | nothing |
| T7 | preparing | own frame: done and ready, q sendable | setting | set (q) | nothing |
| T8 | preparing | own frame: done and ready, no q | prepared | nothing | the prepare's reason, when Tiled is blocked |
| T9 | preparing | own frame: done and ready, q Tiled, Tiled blocked | prepared, q dropped | nothing | the prepare's reason |
| T10 | preparing | own frame: done, not ready, `focus-changed` or `target-departed` | open, q dropped | nothing | nothing |
| T11 | preparing, prepared | own frame: not ready, `view-changed` or `shell-replaced` | idle | nothing | nothing |
| T12 | preparing | own frame: refused `busy`, `unavailable`, `conflicting-request` or `stale-request` | open, q dropped | nothing | the reason |
| T12a | preparing | own frame: refused for a reason not in T12, T13 or T14 | open, q dropped | nothing | the reason |
| T13 | preparing | own frame: refused `popup-focus-unconfirmed` | open, q dropped | nothing | nothing |
| T14 | preparing | own frame: refused `stale-context` | idle | nothing | the reason |
| T15 | preparing, prepared, setting, awaiting | own frame without the intent's fields as the provider adds them | idle; no actions for the lifetime | query | `malformed` |
| T16 | preparing, setting, awaiting | own frame refused at frame level | idle; `intent`, `version`, `malformed` as T15, `output` not | query | the reason |
| T16a | idle, open | a frame refused at frame level for the current intent, whose action has ended, or for an open action's own intent after its decision (which P5 never sends) | unchanged; `intent`, `version`, `malformed` mark the lifetime as T15, `output` not; an open action then ends through T34 if nothing is left to act on | query | nothing |
| T17 | preparing | the prepare's deadline, no frame, no q | idle; the mode unknown | nothing | `unconfirmed` |
| T17a | preparing | the prepare's deadline, no frame, q queued | idle, q dropped; the mode unknown | nothing | `unconfirmed` |
| T17b | idle, open | the deadline of the current request, an intent with no frame accepted | unchanged; the mode unknown, so open ends through T34 | nothing | nothing |
| T18 | prepared | `choose(m)`, m sendable | setting | set (m) | nothing |
| T19 | prepared | own frame: not ready, `focus-changed` or `target-departed` | open | nothing | nothing |
| T19a | preparing, prepared | own frame: not ready for a reason not in T10, T11 or T19 | open, q dropped | nothing | nothing |
| T20 | open, preparing, prepared | `close(d)` | idle, the close's kind recorded | nothing | nothing |
| T21 | setting | `close(d)` | awaiting, the close's kind recorded | nothing | nothing |
| T22 | awaiting, or idle with the action's set unread, the close recorded not the user's | `close(true)` | unchanged, the close now the user's | nothing | nothing |
| T22a | idle, awaiting | any other `close(d)`, the nested `close(false)` that follows every end of the action among them | unchanged | nothing | nothing |
| T23 | setting, awaiting | own frame without a completion | unchanged; the set read | nothing | nothing |
| T24 | setting, awaiting | own completion `done` | idle | nothing | clears a notice |
| T25 | awaiting | first own frame: refused `stale-context` or `focus-changed` | idle | nothing | nothing after `close(true)`; `interrupted` after `close(false)` |
| T26 | setting | own frame: refused `stale-context`, `focus-changed` or `target-departed` | open | nothing | the reason |
| T27 | setting, awaiting | own frame: refused `view-changed` or `shell-replaced` | idle | nothing | the reason |
| T28 | setting | own frame: refused for any other reason | open | nothing | the reason |
| T29 | awaiting | own frame: refused for a reason not in T25 or T27 | idle | nothing | the reason |
| T30 | setting, awaiting | the set's deadline, no frame | idle; the mode unknown | nothing | `unconfirmed` |
| T31 | setting, awaiting | the set's deadline, frames without a completion | open from setting, idle from awaiting | nothing | `unconfirmed` |
| T32 | idle, or open in the action that sent the set | the first frame carrying the set's completion, after the set's deadline, while the set is the current request | idle on done, else unchanged | nothing | done clears the notice; a refusal its reason, a first frame refused `stale-context` or `focus-changed` as T25 |
| T33 | any but idle | the bar asks again: another lifetime, the bound offline frame, a name or output change, going idle | idle | a query (none going idle) | `unconfirmed` when a set was out |
| T34 | open, preparing, prepared, setting | actions become unavailable | idle, or awaiting from setting with the close recorded not the user's | nothing | nothing |
| T35 | any | a frame of a request the action did not send: a query's, or an earlier action's, including a late completion of a set reaching an action opened after it | unchanged | nothing | nothing; the mode only |
| T35a | any | any other frame of the current request: a later frame once its completion is taken, a frame of an ended action's prepare, an own frame no row above takes | unchanged | nothing | nothing; the mode only |
| T36 | any | `input()` outside open; `choose()` in idle, with q, while setting or awaiting, or for a blocked Tiled | unchanged | nothing | nothing (ignored) |

- Where an action is left. A preparation that ended with `focus-changed`, `target-departed` or
  another reason that does not end the view (T10, T19, T19a), a silent `popup-focus-unconfirmed`
  (T13) and a prepare refused for another reason (T12, T12a) leave it open: the next input prepares
  again, and nothing is retried without one. A done prepare can arrive already not ready, and then a
  queued choice is dropped silently. After the action ends the state is `awaiting` while a set is
  out before its deadline (T21, T34), and `idle` otherwise; a queued choice, Escape and then the
  handle arriving sends nothing (T20, T35a).
- The menu's close before the set is read. The focus change that closes the menu ends the
  preparation and empties the provider's slot, so a set read after it is refused `stale-context`, or
  `focus-changed` when KWin did not announce the change, in its first frame. T25 keys on the close,
  not the reason: after the user's close nothing is presented, after any other "Interrupted, try
  again". With the menu still open, those reasons say that the workspace changed (T26). So the menu
  does not close on a choice: it stays open until the provider has read the set, or until the user
  or KWin closes it, and a done set ends the action (T24), as a done Tiled gives the app focus,
  which hides the menu.
- T5 compares two of the provider's views, the frozen one and the frame's, on every accepted frame
  while the action is open, over T35 and T35a; otherwise the next prepare would be refused
  `stale-context` and a second notice would follow the first. A reason the moving frame's row
  presented stays presented. T31 enters open on a deadline, not a frame, so there T5 checks the
  newest accepted frame.
- A prepare that times out presents `unconfirmed` with or without a choice queued (T17, T17a): the
  menu closes with the unknown mode, so the pill says it is not confirmed if the control shows again
  in time. A late completion is the set's first after its deadline and counts until the bar's next
  request, not after (T32): the provider tells a request no longer read nothing, and the bar takes
  only its current request's frames. A late done clears the notice. A set's frames without a
  completion come while the tiler retries its start; the mode follows them, and the set ends
  unconfirmed at its deadline (T31), after which a new choice is a new intent that prepares again,
  not a retry.
- The mode always comes from the frames' `tiled`, never from a completion.

Tests: `tests/calendar_backend_test.py`, run as above, also runs the action against the real
component on its private bus, each case with a bar of its own answered by one lifetime, with the
fields the provider adds to an intent's frames. It has a case for each outcome of each row of the
table, and one for each outcome where a row has several: T2 in every state of the action and with
the mode unknown or unavailable; T11 and T19a in preparing, on the first frame, and in prepared, on
a later one; T15 for each missing or malformed field in each state it lists, the five kinds of a
set's frame both while setting and while awaited; T16 for each reason, and a prepared action's frame
refused at frame level, which gives the mode only; T16a in idle after Escape, in idle past the
prepare's deadline, with the menu opened again and in an open action after its own prepare's
refusal, each with a reason that marks the lifetime and with `output`, and an open action's own set
still undecided past its deadline, which T16a does not take; T17 and T17a; T20 from open, preparing
and prepared, with nothing sent after; T22 in awaiting and in idle past a set's deadline; T22a in
awaiting and after a done set; T25 for both reasons after both kinds of close; T31 from setting and
from awaiting; T32 done and refused in idle and in open, a late first frame refused `stale-context`
after either kind of close, and in idle once a menu opened since has closed; T33 with a set out,
with none, and going idle; T34 from each state, with the close it records; T35 for a late
completion, done or refused, reaching a menu opened after the set's deadline, which stays open; and
T36 for each call it ignores. Beyond the rows it checks the nested `close(false)` from inside the
user's close, through the change of `actionOpen`, and the closes that the menu's and the control's
hiding will make from inside a done set's end, a frame that takes the actions away from a setting
action with the set refused in it (after an earlier action the user closed), a set's deadline, a
refusal at frame level and another lifetime's frame: the state moves once and the row presents its
own outcome; an open action ended before its actions go, `actionOpen` false already as
`actionsAvailable` turns false, in T15, T16 and T16a (with the menu opened again, and after T12);
the change signals of every action property, `mode` and `outcome`, at most one each, in T3, T4, T7,
T8 with an app to tile and on a frame that turns the view tiled, T18, T15 from prepared with a
reason shown, and a frame and a deadline that each move the action into open and end it (T26 or T31,
then T5); a completion presented once, after T8, T25, T27, T28, T29 and T32; T5 on the frame that
moved the action into open, on the newest frame when a deadline did, and on a query's frame naming
another desktop or activity; the exact keys and numbering of a prepare and a set, each saved before
its wake; the mode kept while an intent waits, its first frame taken at the revision shown, once,
but not below it, and not kept out by a frame of the request it replaced still waiting for its
check; a fresh query's first frame at revision 0 not taken; a prepare sent after a set's deadline,
whose late frame is no late set; actions coming back with another lifetime; the handle emptied on
every way out of prepared; the choice and the reason kept until the next request, a prepare or a
query, which clears them, and the reason cleared by a change of state that presents nothing; the
mode never taken from a completion; and that the cases log exactly one line for each lifetime left
without actions, in the cases that leave one, and nothing else.

### Workspace layout control (`LayoutControl.qml`)

The control that shows the bar's workspace layout state, read only (P4 of
`tasks/workspace-layout-control/todo.md`); the Floating and Tiled choices come in P6. Its owner
passes in the state's `mode`, the window's metrics and the pill's text colour, and sets `level`:

- It shows only a mode an answer confirmed: tiled, a glyph of the window frame and its divider with
  the label "Tiled"; floating, the frame alone with "Floating". Unknown and unavailable show nothing
  and take no room, at every level. A query pending, past its deadline or refused, a provider that
  cannot tile and an output KWin does not have look alike, as nothing that looks as if it worked
  may appear without the placement script's word (the specification's items 7 and 8).
- `level` 0 shows the glyph and its label, 1 the glyph alone, whose accessible name still says the
  mode, and 2 nothing. For the width budget, `fullWidth` and `compactWidth` are the widths at 0 and
  1 whatever the mode and level, and `available` says whether a mode shows. The label's box is as
  wide as the wider of the two labels, so a change of mode never changes the pill's width, as with
  the time's box.
- No board draws it, and its values are the boards': the glyph 14 px (the LiveChips board's glyph
  size) on the 24-unit grid of the boards' line glyphs, stroked 1.8 with round caps and joins as the
  shell boards' line icons; 6 px to the label (a LiveChips chip's own gap after its glyph); the
  label in Manrope 13 px 600 (the pill's text size, and the weight of the TabletSnap board's
  window-card rows); glyph and label in the pill's text colour. The glyphs are the Icons board's
  Snap symbol without its last stroke. Text goes through the metrics' `font()` and sizes through
  `px()`, so large text scales them. The label's alignment is set, so that a mirrored layout keeps
  it against its glyph: one left unset follows the text's own direction. The presentation awaits the
  owner's review of the screenshots at the read-only checkpoint.
- It offers no action yet. It takes no keyboard focus and no click, and a wheel turned over it
  reaches the pill, which switches workspaces. Its accessible role is static text, named "Dynamic
  tiling: Tiled" or "Dynamic tiling: Floating"; its tooltip and accessible description say whether
  the dynamic tiler arranges the workspace's windows. It draws without animation.
- It does not compare an answer's view with the bar's own. The placement script is the only
  authority for the view, and on a desktop switch the bar's own desktop and the provider's frame for
  the new view arrive separately, so a comparison would disagree for a moment on every switch,
  whichever came first, and hide the control. An answer that a failed or malformed publication
  leaves standing stays until a later publication reaches the bar, the limit of P2's fourth item.
- In the pill (`main.qml`) it sits after the workspace dots, or first with one workspace (the
  specification's item 1), one pill padding from its neighbours. The width budget turns it to its
  glyph alone at step 4, with the short date, and hides it at step 7, with the dots, so the steps
  keep their order (`WidthBudget.qml`): it gives up its label's room, then its width and one pill
  padding. Where the bar's own layout hides it - tablet posture, a vertical panel, a clock outside
  a panel - the layout state is idle, so its mode is unknown and it shows nothing. At step 7 the
  state keeps asking: the budget counts the control's room only while it shows a mode, so idling
  the state there would free that room, let the budget step back and show the control again, in a
  loop. A bar that narrow keeps receiving frames. The testing hook `dump-pill:TAG` (`debugAction`)
  logs where the pill's parts sit, the step, the control's level and mode, and its measures. The
  budget evaluates again when one of the clock's savings changes while the pill's width does not:
  at step 7 a control that stops showing a mode lets it step back, and a new query there moves the
  bar down until its answer comes, then back up, as below step 7.

Tests: `tests/calendar_view_test.py`, run on a stage as in the calendar's regression checks above,
loads the staged control beside the shared `FusionMetrics`. It checks both modes' glyph, label,
accessible name and tooltip; unknown and unavailable showing nothing and taking no room; the
compact and hidden levels; the width, which a change of mode keeps; sizes and text through the
metrics, and the label not in the display family; the colour; the layout as drawn in either
direction - the gap between glyph and label, the label's box, the two filling the control, and the
label's alignment toward its glyph; a wheel and a click reaching what is behind it, and nothing of
it handling a click itself; and nothing taking focus. Its control checks go on after a failure, so
that one run shows them all. A stand-in bar around the staged `WidthBudget.qml` checks that the
budget evaluates again when a saving changes while the pill keeps its width: the control showing
no mode at step 7, and a saving that only the steps below give up.

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
- Settings pages (0.5.0): Plasma 6.7's dialog (`AppletConfiguration.qml`) shows one page at a time,
  creates it with every key and its default (`cfg_<key>`, `cfg_<key>Default`) and on Apply writes
  back every `cfg_` property of that page only; it replaces the page after Apply or Discard. Each of
  the three pages (General, Calendar, Time zones) therefore declares all 17 keys and defaults, and
  its `saveConfig()` refreshes the keys it has no control for (the other pages' keys, `widthBudget`,
  `menuPolicy`, `menuCompacted`, `debugAction`) from the live configuration, so Apply on one page
  does not write back a value another page, part or script changed while it was open.
  `packages/common/tests/config_page_keys_test.py` checks both rules on every page of
  `config.qml` and runs in the build step (`tools/build.d/70-topbar.sh`); on the previous pages it
  reports 76 problems (each page lacked the other pages' keys and the widget's own). In the test VM
  (Plasma 6.7.5) opening the settings and going General, Calendar, Time zones, General logged 88
  "Setting initial properties failed" lines before and none after; a time zone written by desktop
  scripting while General was open survived Apply there. The Kirigami notice "Created graphical
  object was not placed in the graphics scene" stays (see Remains). The calendar providers' own
  pages (KDE's) are not checked.
- Settings pages and the layout control's keys (P3): `tests/calendar_config_test.py` opens and
  applies each of the three pages as the dialog does at plasma-desktop v6.7.5 and v6.8.3 alike:
  `open()` passes every key of the configuration as `cfg_<key>`, KConfig's map listing each default
  as `<key>Default` (KConfig 6.32, `KConfigPropertyMap`), and Apply calls the page's `saveConfig()`,
  then copies back every `cfg_` property the page declares. A stand-in for `org.kde.plasma.plasmoid`
  hands the pages the configuration. Each page takes all 20 keys and defaults and writes nothing as
  it opens; while it is open the clock's request, the provider's answer and, where the page does not
  edit it, `showLayoutControl` change, and Apply leaves each as it now is. On the General page the
  checkbox shows the saved choice, Apply writes the user's, and with the workspace dots off it stays
  enabled and shown. It runs as the specification's command (`QT_QPA_PLATFORM=offscreen
  dbus-run-session --config-file=packages/kwin/tests/offscreen/session-bus.conf -- python3
  packages/plasmoids/org.plasmafusion.clockpill/tests/calendar_config_test.py`), the Calendar page's
  provider checks after these. A field written while a page is open, as `menuCompacted` already
  can be, leaves the dialog's change check (`isConfigurationChanged()`) seeing a difference once
  anything on the page changes, so Apply can stay enabled after an edit is undone; Apply then
  writes the values as they are. A page that cannot load fails the run, as the dialog opens each
  of them: a module it imports missing or misspelled alike.
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
- Evidence: the shell-topbar build run of 2026-09-29 (the maintainer's records):
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
- Calendar has no week numbers (events and holidays come from the calendar plugins, see above).
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

Evidence: the shell-topbar build run of 2026-09-29 (the maintainer's records), its files
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
  (the dots hide; Overview still switches workspaces). Since P4 also `layoutLevel` and
  `layoutSaving` ("Workspace layout control" above). The short date is the region's short date
  without the year and what joined it to the day or the month (en_US "11/21", en_GB "21/11"), but
  a dot right after either stays (de_DE "21.11.", ko_KR "11. 21."), also where the region writes
  none (ru_RU "21.11."): the short format does not tell the two apart. A custom date format sets
  only the full date.
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
    Since 2026-10-18 the window takes the free half instead (docs/parts/kwin-tablet.md, "Full screen
    off takes a half"), unless it is wider than a half.
  - Split: the card activates the window, waits until KWin reports it active, then invokes "Window
    Quick Tile Left/Right" (component `kwin`); the tile loses its title bar as before (KWIN-1).
- **Width budget** (`WidthBudget.qml` in the clock pill, which sits between the bar's two expanding
  spacers): the pill stays on the middle while each side fits within W/2 − pill/2 − 24; otherwise the
  steps of ADAPTIVE 5.1 apply in order: 1 the global menu compact (and the optional system meters'
  network meter out, 0.5.0: `docs/parts/shell-meters.md`), 2 phone and clipboard into quick
  settings (QS-1 adds its hook; the system meters leave the bar), 3 the app name hidden, 4 the short date, 5 the time only, 6 no
  battery % (QS-1), 7 no workspace dots. Tablet posture starts at step 2, portrait or a narrow screen
  at step 5 (TABLET 4.3); the clock pill has no dots in tablet posture and uses 14 px 800 text with
  16 px padding. The step is computed in one go from the widgets' level-0 widths: each Fusion widget
  of the bar has `budgetLevel` and `budgetSaving(level)`; the stock menu's full width is measured from
  its menu model (titles in the panel font plus the `menubaritem` margins; measured exactly equal to
  the full view for Konsole, Dolphin and Kate). Nothing is laid out to be judged, so nothing flickers.
  Since P4, step 4 also turns the workspace layout control to its glyph alone, and step 7 hides it
  ("Workspace layout control" above).
- **Global menu crash (Plasma 6.7.5)**: the stock appmenu crashes plasmashell when it goes from its
  compact view back to its full view after its menu changed (libplasma
  `AppletQuickItemPrivate::compactRepresentationCheck` reads the full view's size hint). Cause, in
  Qt 6.11's `QQuickGridLayoutBase` (qtdeclarative v6.11.2, src/quicklayouts): a removed child stays in
  the layout engine until the layout's next polish (`ensureLayoutItemsUpdated`), and `sizeHint()`
  reads the engine without rebuilding it. A full view that is compact (unparented) or hidden (the
  active window has no menu) is not polished, so the next size read after a change reads a deleted
  item. Found in private sessions t2m (E1-E6: compact and back without a change is safe, after an
  app switch it crashes every time; `destroy()` is refused, adding a child does not rebuild) and ov2
  (tablet, portrait, no menu, then a new window's menu and the compact switch at once, back to
  landscape; the deployed 0efb34f crashed in 2 of 4 runs of that sequence, oA2 twice, once in
  libplasma's preload of a compact applet a few seconds after a start).
  **Fix (2026-09-30):** the budget rebuilds the full view's layout itself with `ensurePolished()`
  (QQuickItem, Qt 6.3) right before it switches the menu either way, and at once after a menu change
  while the full view is not shown (for the preload). Proof with the width budget off (ov6a/b): a
  change while compact, the rebuild, then full: 8 of 8 without a crash; the same without the rebuild
  crashed both times. With the budget (ov3 x3, ov4, a start with the menu compact, a start in
  tablet portrait with changes inside the preload time x3, 15 rotations with app switches): no
  crash, and the menu goes back to full every time (it no longer stays compact until plasmashell
  starts again; an interim version, cc1bce8, did that). Evidence: the menu-fix deploy2 run of
  2026-09-30 (the maintainer's records). `menuPolicy=overlap` compacts the menu only
  when the bar would otherwise overlap (the pill then leaves the middle), which keeps full menus far
  more often. The earlier plan to switch it from the tablet script's panel script was dropped when
  the crash was found; with the rebuild it would be possible again.
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

## TABLET2 S1 (2026-10-01): clock pill pull-down in tablet posture

In tablet posture a pull-down on the clock pill opens the Notification Centre when the quick settings
widget in the same bar keeps notifications apart (`openNotificationCentre()` on it returns true;
docs/parts/shell-quicksettings.md, TABLET2 S1); otherwise, and on the laptop, it opens the calendar as
before. A tap opens the calendar in every posture.

## Hidden automatically (2026-10-17)

The settings page's "Hide the top bar automatically" (off by default; docs/parts/kcm-cpp.md) sets
the bar's panel to Plasma's auto-hide: a maximized window takes the whole screen, and the pointer
at the top of the screen brings the bar back over it; it stays while the pointer is on it or one of
its menus or panels is open (plasma-workspace 6.7.5 `PanelView::restoreAutoHide`; the bar's widgets
ask for attention only while their pop-ups are open, so nothing keeps it shown). In tablet posture
it always shows (docs/parts/kwin-tablet.md). While it is hidden, the island at the top centre shows
what the live chips would (board Island.dc.html, docs/parts/shell-livechips.md, "The island").

## The pill's drag (tablet posture, 2026-10-18)

Board `design/boards/TabletSnap.dc.html` ("A place for every window"): iPadOS 26 tiles a window
flicked by its top to an edge, ChromeOS and Windows 11 snap a window dragged to an edge; in tablet
posture Plasma Fusion's windows have no title bar, and the window pill is their chrome. Research:
the tablet auto-snap research of 2026-10-18 (the maintainer's records).

- **Hold and drag**: in tablet posture, the pill of an app held for 300 ms without moving 10 px
  (the dock's lift for its split drag) arms the drag: the pill takes its open look and grows to
  1.04. Dragged down from there (the 24 px drag layer, which otherwise opens the card), the app's
  icon follows the finger over `WindowDropOverlay.qml` (layer shell, "on-screen-display", no input,
  as the dock's `SplitDropOverlay.qml`): the two halves at accent 8 %, the target at 28 % with a
  full edge, both lit as "Full screen" over the middle third, a "Home" pill above the bottom, and
  the hint "A side splits · the middle is full screen · the bottom goes home" in the island's
  black. The release decides (`contents/code/drop.js`, `target()`): back in the top bar nothing,
  the bottom 96 px of the work area home (minimized), the outer thirds that half (the card's Split
  left or right: KWin's quick tile, so the other half offers what fills it), the middle full screen
  (maximized, also out of a tile; nothing for a window already maximized).
- **Flick**: without the hold, the pill moved sideways at 800 px/s or faster, more sideways than
  down (`flick()`), puts the app in that half at once. A slower sideways move does nothing.
- The drop acts on the window the drag started with (its windows and icon kept at the lift), even
  when the focus moves meanwhile (an app's dialog, a notification); a flick acts on the active
  window. Only the bar of the window's own screen drags or flicks it (`drop.js` `sameScreen()`:
  the app-name model is not filtered by screen, so with a second screen a bar can show the other
  screen's window, whose halves are not the ones its overlay would show); elsewhere the hold is a
  pull-down as before.
- A tap and the 24 px pull-down still open the window card (a pull-down now has to be more down
  than sideways). Laptop posture is unchanged: no lift and no flick there. The log:
  `appname: pill drag starts`, `appname: pill drag to left`, `appname: pill flick to right`,
  `appname: pill drag to nowhere (back in the top bar)`.

Tests: `tests/drop.test.js` (node, in `70-topbar.sh`): the top bar, the thirds and their edges, the
bottom 96 px on every side, a portrait screen, flicks at and under 800 px/s and mostly downward,
the same screen and others. `tests/vsession/scenario-pilldrag.sh` (private session on the ThinkPad,
1440 x 900, tablet posture, real touch through pfinput; 2026-10-18, pd-5): all 10 checks pass -
KWrite opens full screen; held 0.45 s and dragged to the left third, KWrite takes the left half
(0, 717); to the middle, full screen again; a flick to the right, the right half (723, 717); a slow
sideways move does nothing; dragged within the top bar, nothing; the pull-down still opens the
window card; dragged to the bottom, KWrite is minimized; the focus moved to Konsole during a drag
of KWrite's pill, KWrite takes the left half and Konsole stays; no QML message about the pill's
files. `tests/vsession/scenario-pilldrag-screens.sh` (two outputs, a top bar on each; pds-2): all 4
pass - the second screen's pill does not drag the first screen's KWrite, the first screen's does.
With main's pill (pd-r1) 6 checks fail: no drag, no flick (the held drags open the window card, and
the card they leave open keeps the later pull-down from opening it again); with the first version
of this change (6c5f570) the focus case fails (Konsole was tiled, pd-r2) and so does the second
screen (KWrite moved from the second screen's bar, pds-r1). Not verified: by a person's finger on
the ThinkPad's own screen, portrait, a real second monitor.
