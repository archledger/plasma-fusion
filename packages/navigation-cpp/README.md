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
- a split pair (two apps side by side) is one card, and comes back as a pair (below).

## Build

`tools/build-remote.sh` builds it in the Plasma Fusion build container on the test device and fetches a staged
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

## Split pairs in the app switcher (2026-10-02, SPLIT.md item 4)

As in Android's Overview, two apps side by side (quick-tiled left and right: the window card's
Split left / Split right, the dock's split drag, the quick-tile keys) are one card:

- `FusionTaskFilterModel` finds the pairs when the switcher opens, before it minimizes the apps.
  First the apps shown, layer by layer: the topmost app and the app seen in the other half of its
  split (tiled on the other side and not covered by an app above it: `fusionVisiblePartner` in
  `splitside.cpp`, with the tablet script's split divider test for the sides), then the same
  under them, so an older split under a newer one is a second pair card. Then the pairs
  `FusionTaskModel` remembers, when both apps are shown or both minimized: the split seen when an
  app was activated or tiled (a split with an app opened between its halves), and the pairs the
  switcher minimized as one card. Minimized apps keep their tiles, so tiles alone would pair apps
  that were never side by side; a remembered pair ends when one app closes or leaves its side,
  or when the switcher shows them on cards of their own. The more recently used app stands for
  the pair in the list (the higher one when both came up at once); the other is left out and
  given to the card as the `partner` role.
- The card (`Task.qml`) shows both previews in their split ratio with a gap for the divider, each
  app's icon and name above its half, and one close button. Picking it, a sideways swipe to it, or
  a gesture that returns to it brings up both apps in their tiles (`raiseApp`), the card's app on
  top with the focus; swiping it up or its close button closes both (`closeTask`). In scrub mode
  the pair's other app is a small badge on the card's icon.
- Picking the card of an app alone maximizes it, also an app left alone in a tile (Android: an
  app outside a pair fills the screen), once the app is shown again (maximized while still
  minimized, a tiled app made KWin's maximize effect throw a TypeError). 0.1-6 kept such an app
  in its half; its partner lookup skipped minimized windows, so the other half never came back
  from the switcher.
- Going home and back, in tablet posture: the pairs the switcher minimized are remembered
  (`rememberPair`); when one of the two is activated again from anywhere (the dock, a
  notification, Alt+Tab), the other is restored into its half under it 300 ms later, while both
  are still that pair, side by side, and no other app is shown in that half (log "split pair
  back"; "split pair not back" when an app holds the half). The wait lets the dock's split drag,
  which activates the app and then tiles it, land first: KWrite of a pair that went home, dragged
  next to Dolphin, stays next to Dolphin. Each pair is used once; leaving tablet posture drops
  them.
- An app of the pair that quits while the switcher is open: the other one gets its own card. When
  the pair's card is closed and the app it left out stays open (it asks to save its work), that
  app gets its own card after 3 s, as a card whose app does not close comes back.
- The switcher minimizes the apps oldest first. Minimizing the active app first made KWin
  activate the app behind it, which then counted as the last used one, so after going home the
  switcher led with the app that had been behind.

Test (6.7.5 container, 1440 x 900 logical; sessions pair5, lone2, evidence
`artifacts/plasma-fusion/2026-10-01-tablet2/split-pair/`): Dolphin maximized, KWrite tiled left,
Konsole right. Switcher: 2 cards, the pair as one (screenshot P9-switcher). Picked: both back in
their tiles, Konsole active. Home, then KWrite activated (as the dock does) and, again, KWrite
tapped in the dock: Konsole back in its half both times. Sideways to Dolphin and back: the pair
again. A short swipe up: the pair again. Pair card swiped up: both closed, Dolphin left. Konsole
quitting with the switcher open: KWrite on its own card. KWrite alone in its tile, picked:
maximized. No QML errors from the effect. Builds without warnings against KWin 6.7.5 and 6.7.91.

Review fixes (6.7.5 container, 14 sessions fx-*, evidence `split-pair/review-fix/` next to the
above; the switcher opened by its shortcut, as the hold gesture was unreliable on the loaded
laptop): KWrite|Konsole gone home, Dolphin alone in the left half: cards Dolphin and
KWrite+Konsole, Dolphin picked fills the screen (fx-phantom). Two splits, on top of each other or
one gone home first: two pair cards, the older one picked comes back in its tiles (fx-twopairs,
fx-twopairs2). Dolphin opened over a split and Konsole raised over it: still one pair card; then
Gwenview tiled left over it all next to the visible Konsole: Gwenview+Konsole, KWrite alone
(fx-covered). The dock's split steps after going home put KWrite next to Dolphin and Konsole stays
minimized (fx-dockover); KWrite activated and tiled right at once: Konsole stays minimized
(fx-fromhome); home, Dolphin opened, KWrite activated: Konsole back over Dolphin, and the pair is
one card again from home (fx-back). Laptop posture: KWrite activated, Konsole stays minimized
(fx-laptop). Pair card closed with unsaved text in the app it left out: that KWrite gets its own
card again after 3 s (fx-refuse-hidden; fx-refuse-shown unchanged). fx-pair, fx-lone,
fx-hiddenquits and fx-single as before; KWin's maximize TypeError is gone (0 in all 14 logs).
