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

## Build

`tools/build-rpm.sh` builds it in the Plasma Fusion build container on the test device and fetches a staged
install (`stage/`) and the RPM.
