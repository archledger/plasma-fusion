# Plasma Fusion navigation (KWin effect)

Tablet-posture navigation for Plasma Fusion (TABLET2.md 3.1): from the bottom edge, swipe up to go home,
swipe up and hold for the app switcher, swipe sideways for the previous or next app. The app follows the
finger. Active only while KWin reports tablet mode.

## Origin

This package is derived from **Plasma Mobile's task switcher effect**, `kwin/mobiletaskswitcher` in
[plasma-mobile](https://invent.kde.org/plasma/plasma-mobile) tag **v6.7.5** (commit 10773c8), by Devin Lin,
Luis Büchi, Marco Martin, Vlad Zahorodnii and others, GPL-2.0-or-later. Every file keeps its original
copyright lines. Plasma Fusion changes:

- renamed the effect (`plasmafusion_navigation`), the QML module (`org.plasmafusion.navigation.plugin`) and
  the C++ classes (`FusionNavigationState`, `FusionTouchBorder*`, `FusionTask*Model`), so it never clashes
  with Plasma Mobile;
- the gestures follow KWin's tablet mode (`TabletModeManager`) instead of Plasma Mobile's shell settings;
- removed the Plasma Mobile shell dependencies (navigation panel, gesture panel, haptics, shell D-Bus state,
  panel constants);
- the toggle shortcut has no default key;
- a short swipe up (16 px or more, below home) over an app shows the dock; the switcher leaves out
  input-method panels, pop-ups, OSDs, zero-size windows and plasmashell's surfaces;
- gesture numbers (TABLET2 N1, from the research on the share): a fast upward flick from an app goes
  home only past 72 px, a slow drag past min(260 px, 55 % of the height) (Plasma Mobile: any flick,
  and 55 %); the cards pulse (3.5 %, Kirigami durations) where Plasma Mobile vibrates;
- a key press on a hardware keyboard hides the on-screen keyboard (`FusionKeyboardSpy`, a KWin input
  event spy; KWin 6.7.5 keeps it shown).
- Fusion look for the cards: previews with radius 18 and a 1 px edge through the window switcher's
  corner shader (`shaders/thumbnail.frag`, a copy; layers only for cards within two of the current
  one), a bold title, 44 px round close buttons, the boards' dark dim (rgb 6, 8, 18);
- idle under a KWin it was not built for (`KWIN_VERSION_STRING` against the running version).
- gesture lock (TABLET2 G1): with `plasmafusionrc [Tablet] GestureLock=true` (quick settings' tablet row,
  followed live through KConfigWatcher) a swipe from the bottom edge is held back unless it follows a
  held-back one within 1.5 s (iOS's deferred system gestures); a held-back swipe shows Plasma's OSD
  (`org.kde.osdService.showText`).
- the pen like a finger in tablet posture (TABLET2 PEN-2, `FusionPenFilter`; drawing apps exempt;
  `plasmafusionrc [Pen] TabletPen`), and a test-only virtual pen (`FusionTestPen`, only with
  `PLASMA_FUSION_TEST_PEN=1`) for private test sessions.

## Build

`tools/build-rpm.sh` builds it in the Plasma Fusion build container on the test device and fetches a staged
install (`stage/`) and the RPM.

## Home closes a shell sheet (2026-10-01)

Seen on the owner's ThinkPad: with no app open, the launcher sheet open, three swipes up did
nothing, and each logged "TaskSwitcherHelpers.qml:247: TypeError: Cannot read property 'window' of
null". `onGestureInProgressChanged` read `if (taskList.count === 0) { close(); } if (...)` (Plasma
Mobile's code, no `else`), so with no tasks it went on and opened a task that does not exist; it
now returns after closing, and `openApp` skips a missing task. Shell sheets (launcher, Notification
Centre, quick settings) close themselves when they lose the focus; with no app to minimise nothing
took it. A home gesture (and, with no app open, any upward swipe past 16 px) now gives the focus to
the desktop window of that screen when a shell window other than a dock or the desktop is active
(`dismissShellSheet`; the shell's other windows have the class "org.kde.plasmashell"; log "home
closes the shell sheet"). Test (6.7.5 container, hsheet3): launcher opened with no app and over
KWrite, home gesture: the sheet closed both times, no TypeError.
