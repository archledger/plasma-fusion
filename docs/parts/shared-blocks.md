# Shared QML blocks and QML checks (BASE-1)

Work package BASE-1 of the one-pass build plan
(`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-decisions/PLAN.md`, section 5). Every lane builds
its QML on the same blocks for text scale, motion, tablet posture, glass, accent colour and foreign
app icons, and the build checks durations and accessible names.

| File | What it is | Spec |
|---|---|---|
| `packages/common/FusionMetrics.qml` | text scale and pixel grid (see `text-scale.md`); gains `tablet`, and `dpr` now comes from the window | ADAPTIVE 3.1, TABLET 4.1 |
| `packages/common/Motion.qml` | motion tokens from `Kirigami.Units` | EFFECTS 6.1, 7 |
| `packages/common/FusionTablet.qml` | tablet posture from KWin's own D-Bus state | TABLET 3.1 |
| `packages/common/FusionAccent.qml` | accent colours from the colour scheme | decision 3 |
| `packages/common/FusionBackdrop.qml` | the "Tinted" glass material: a cached, blurred wallpaper plus a tint | EFFECTS 3.1, TABLET 4.1 |
| `packages/common/FusionIconTile.qml` | an app icon with a neutral Fusion tile behind icons that have no Fusion tile | ADAPTIVE 5.4, fix 27 |
| `packages/common/FusionShadow.qml` (+ `shaders/fusionshadow.frag`) | the soft drop shadow of a rounded box, one small shader; replaces QtQuick.Effects RectangularShadow | STRESS-1, 2026-10-01 |
| `tools/build-lib/shared-qml.sh` | copies the blocks a package uses into it at build time | |
| `tools/checks/motion-lint.sh` | literal durations, endless loops, animations without a duration | EFFECTS 6.2 |
| `tools/checks/a11y-lint.py` | interactive items without an accessible name | GAPS G25 |
| `tools/checks/qmlscan.py` | the small QML scanner both checks use | |
| `tools/checks/tests/` | fixtures and `run.sh`, the checks' self-test | |
| `packages/common/tests/` | `Probe.qml` and `offscreen.sh`, the blocks' offscreen test | |

## How a package gets the blocks

A package never carries its own copy of a block. Its `tools/build.d` script calls

```
bash "$ROOT/tools/build-lib/shared-qml.sh" check   SRC LABEL     # fails if SRC has a file named like a block
bash "$ROOT/tools/build-lib/shared-qml.sh" install SRC DEST      # copies the blocks SRC uses into DEST
```

`install` always copies `FusionMetrics.qml` (as the scripts did before) and every other block that a
`.qml` or `.js` file under SRC uses: an object declaration (`Motion {`), a typed property (`property
FusionTablet tabletState`), a cast (`as FusionAccent`) or the file name in a string
(`"FusionBackdrop.qml"`). Comments and other strings do not count. Blocks that blocks use are added
too. With `FusionIconTile.qml` it also writes `FusionIconNames.js` (below); with `FusionShadow.qml` it
adds `shaders/fusionshadow.frag.qsb` (compiled with qsb when installed, else the repository's copy). `shared-qml.sh list SRC`
prints what a package gets. `check` stops the build when a package has its own file named like a
block (a lane that wants a variant names it differently), and a failed scan stops `install`. The destination is one QML folder of the staged package, the same one as
before: `contents/ui` (top bar, launcher, dock, cards, switcher, snap script), `contents/ui/components`
(quick settings), `contents/lockscreen`, `contents/splash`. A folder that needs the blocks but is not
that folder (for example the snap script's `contents/outline/`) needs a second `install` call in the
owning build script.

`tools/build.d/{60,70,71,72,73,74,80,90}-*.sh` call it (the one-time BASE-1 edit); the new `75-pen.sh`
and `81-kwin-tablet.sh` call it from the start. At HEAD no package uses the new blocks yet, so the
staged tree is byte-identical to the one before, except `FusionMetrics.qml` itself.

## Motion

```
Motion { id: motion }
Behavior on color { enabled: motion.animate; ColorAnimation { duration: motion.hover } }
NumberAnimation { duration: motion.popupIn; easing.type: Easing.Bezier; easing.bezierCurve: motion.decelerate }
NumberAnimation { duration: motion.popupOut; easing.type: motion.exitEasing }
SequentialAnimation { loops: motion.loops(3); NumberAnimation { duration: motion.pulse } ... }
```

| Token | At factor 1 | Definition | Easing |
|---|---|---|---|
| `press` | 0 | state change in the same frame | |
| `pressScale` | 80 | `shortDuration × 0.8` | `standardEasing` (OutCubic) |
| `hover` | 100 | `shortDuration` | `standardEasing` |
| `toggle` | 150 | `shortDuration × 1.5` | `standardEasing` |
| `popupIn` | 200 | `longDuration` | `Easing.Bezier` with `decelerate` = [0, 0, 0, 1, 1, 1] |
| `popupOut` | 150 | `longDuration × 0.75` | `exitEasing` (InCubic) |
| `surface` | 250 | `longDuration × 1.25` (lock prompt: `scaled(surface, 1.2)` = 300) | `standardEasing` |
| `pulse` | 500 | `longDuration × 2.5`, one half of the dock's startup pulse | |
| `max` | 400 | `veryLongDuration`, the upper bound for anything user-triggered | |

`unit` is `Kirigami.Units.longDuration` (200 ms × the user's `AnimationDurationFactor`, at least 1);
`reduced` is `unit <= 1` (exactly factor 0, "Instant"), `animate` is its opposite. When `reduced`, every
token is 0 and `loops(n)` is 0 (the animation does not run); otherwise `loops(n)` is at most 3.
`scaled(token, ratio)` never exceeds `max`. The tokens follow a factor written with `--notify` at once.
Qt's animators (`OpacityAnimator` and the like) do not fire reliably at duration 0 (libplasma
`units.cpp`, QTBUG-39766): gate them with `enabled: motion.animate`, or use `NumberAnimation`.
`Motion` is a `QtObject`; one per component is enough.

## FusionTablet

```
FusionTablet { id: tabletState }                         // one per applet root, KWin script or lock screen
FusionMetrics { id: m; tablet: tabletState.tablet }      // m.touch then follows KWin as well
```

`tablet`, `available` and `fromKWin`. At creation it sends one asynchronous
`org.freedesktop.DBus.Properties.GetAll("org.kde.KWin.TabletModeManager")` to `org.kde.KWin
/org/kde/KWin`, then follows `tabletModeChanged` and `tabletModeAvailableChanged` through a
`SignalWatcher`. Until KWin answers, or without KWin on the bus (offscreen tests, the lock-screen
harness), it follows `Kirigami.Settings`, so `KDE_KIRIGAMI_TABLET_MODE=1` still works. No timer, no
polling. Touch behaviour is still decided per event (`eventPoint.device.type`), never from `tablet`.

Measured (private sessions `ldb-final-43`, `ldb-final-1325`, KWin started with `[Input] TabletMode=on`):
in plasmashell the KWin value arrived 77-98 ms after the widget was created; in a KWin script 8 ms,
while `Kirigami.Settings.tabletMode` there stayed `false` until the third flip (TABLET F3 reproduced).
Three flips (`off`, `on`, `off` with `kwriteconfig6 --notify`) reached plasmashell 12-28 ms after each
write (three runs).

## FusionAccent

```
FusionAccent { id: tint }               // or FusionAccent { id: tint; dark: palette.dark }
color: tint.accent
color: tint.soft(0.28)
```

| Member | Dark scheme default | Light scheme default | Source |
|---|---|---|---|
| `accent` | #5b9dff | #2f6fdf | DecorationHover (dark) / DecorationFocus (light), decision 3 |
| `accentText` | #141827 | #ffffff | white if it reaches 4.5:1 on `accent`, else the better of white and #141827 |
| `fill`, `fillText` | #2f6fdf, #ffffff | #2f6fdf, #ffffff | Selection background and text |
| `hoverAccent` | #5b9dff | #5b9dff | DecorationHover |
| `focusRing` | #8ab8ff | #2f6fdf | DecorationFocus |
| `soft(a)` | `accent` at alpha a | | |
| `schemeAccent` | true while no user accent is set | | |
| `dark` | from the colour set's background; bind it for widgets with their own Dark/Light option | | |

Plasma writes a user accent into DecorationFocus and DecorationHover of every colour group (and a
matching Selection fill), so everything follows. The colours are read from the parent's
`Kirigami.Theme` (`colorSource`, default `parent`): an invisible item's own Kirigami theme is never
filled in when it is the first theme in its branch (libplasma `plasmatheme.cpp` and qqc2-desktop-style
`plasmadesktoptheme.cpp` skip items that are not visible). Measured offscreen before this rule: all
colours black.

Measured live in plasmashell (`ldb-final-43`, `ldb-final-1325`, `ldb-accent-1325`): teal, orange,
back to the scheme's blue, and a switch to Plasma Fusion Light all reached the widget (accent, fill,
ring, text). One Plasma caveat: `plasma-apply-colorscheme --accent-color` (6.7.5) sends Plasma's
"palette changed" signal before it writes kdeglobals, so plasmashell reloads the old colours and shows
the new accent only at the next palette signal (`ldb-accent-1325`: no change for 3.5 s, then within
0.6 s of `dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange
int32:0 int32:0`). System Settings' Colours page saves first and is not affected. The Fusion settings
module runs that tool, so it needs to send the signal again after the tool exits (handed to KCM-1).

## FusionBackdrop

```
FusionBackdrop {                        // the tablet launcher sheet
    anchors.fill: parent
    followWallpaper: true
    screenNumber: Plasmoid.containment.screen
    dark: tint.dark
    glass: Plasmoid.configuration.glass // "full" | "reduced" | "solid"
}
FusionBackdrop { anchors.fill: parent; sourceItem: wallpaper }   // lock screen, KWin's DesktopBackground
```

The wallpaper at 1/8 of the item's size, blurred once by one `MultiEffect` (`blurEnabled: true`,
`blur: 1.0`, `blurMax` 32, `autoPaddingEnabled: false`) inside a small layer (60 x 45 logical px for a
480 x 360 item; 180 x 113 for 1440 x 900), shown scaled up with linear filtering, plus the tint (dark
rgba(12,15,28,.55), light rgba(236,240,248,.60)). With Glass = Solid, or until a picture has loaded,
only the tint is drawn, at 0.94, and nothing is loaded. Per frame: one textured quad and one
rectangle. The layer is rebuilt only when the picture, the variant or the size changes; never animate
the item's size.

Sources: `sourceItem` (captured once by a `ShaderEffectSource { live: false }`; call `recapture()`
after the picture changes), `followWallpaper` (plasmashell's `org.kde.PlasmaShell.wallpaper(screen)`,
image plugin key `Image`), or `source` (a file, or a wallpaper package folder: `contents/images_dark/`
in the dark variant when present, else `contents/images/`, and the `WIDTHxHEIGHT` file closest to the
item in device pixels, aspect ratio first). The package folder is listed by a `FolderListModel` that
exists only while it lists (a folder model keeps an inotify instance); a folder model given a folder
that does not exist lists the parent folder (Qt 6.11, measured), so only files inside the asked folder
count.

`wallpaperChanged(uint)` is emitted only by `PlasmaShell.setWallpaper` (System Settings' Wallpaper
page); a desktop script (`plasma-apply-wallpaperimage`, `evaluateScript`) changes the wallpaper without
it. The backdrop therefore also asks again each time it is shown; an unchanged answer reloads nothing.
The D-Bus QML module hands numbers over as typed values (`UINT32` with a `value`), not JavaScript
numbers; compare them through `Number(String(x))`.

Measured (`ldb-final-43`, `ldb-final-1325`): the package lookup picked `images_dark/1280x800.png` for a
480 x 360 widget, `images/…` after the switch to the light scheme; a script change of the wallpaper was
taken at the next show, a `setWallpaper` change at once. Screenshots in the evidence folder. Offscreen
(software renderer) the `MultiEffect` is not drawn at all, so the offscreen test checks the logic and
the private sessions check the picture.

## FusionIconTile

```
FusionIconTile { size: 48; source: model.decoration; iconName: model.iconName }
```

A drop-in for `Kirigami.Icon` in the dock and the launcher. `foreign` (default: the icon name is not a
Fusion app tile) draws the neutral tile, and the icon inside at 42 of 64 units, centred on the 60-unit
base; otherwise the icon is drawn as it is (the Fusion tile is the icon). The tile follows the
AppIcon board's anatomy (64-unit tile, radius 15, 4-unit lip, 9 % sheen on the top 28 units, 1-unit
14 % white edge) with the light board neutral in both variants (base #f4f5f9, lip #d5d9e3, like the
Calendar tile), so full-colour icons keep their contrast; DOCK-2's side-by-side check against the
board decides whether the dark variant wants a darker neutral. No shadow (the dock and launcher put
their shared `RectangularShadow` under it), no layer, no effect: four rectangles, drawn only when
`foreign`.

`FusionIconNames.js` is generated by `shared-qml.sh` from `generators/icons/names.py` (`APPS`, 245
names at HEAD; STYLE-1's coverage work adds more) with the icon loader's dash fallback
(`google-chrome-canary` finds the `google-chrome` tile). Bind `foreign: false` while another icon theme
is active. An icon given as a file path or a `QIcon` without `iconName` counts as foreign.

## FusionShadow (STRESS-1, 2026-10-01)

The soft drop shadow under tiles, knobs and dock icons: an Item that fills the shadowed item, with
`offset`, `blur` (falloff width outside the box, px), `spread` (grows the box, px) and `radius`
(corner radius), drawn by one `ShaderEffect` (`shaders/fusionshadow.frag`: the rounded-box signed
distance, alpha 1 inside and `(1 - smoothstep(0, blur, d))^2` outside). Used by the launcher's
AppTile and TabletSheet tiles, the tablet home screen's tiles, the dock's TaskItem and the quick
settings' FusionSlider knob, in place of QtQuick.Effects' `RectangularShadow`.

Why: Qt 6.11.2's `RectangularShadow` keeps about 6 KiB for every destroyed instance. A plain Qt
window that creates and destroys 200 of them 300 times grew from 168 to 335 MiB, while Rectangle,
ShaderEffect and MultiEffect stayed flat (evidence and a draft Qt report:
`artifacts/plasma-fusion/2026-10-01-tablet2/STRESS-1/qt-rectangularshadow/`). The tablet home
screen rebuilds its pages on every rotation, so plasmashell grew 0.4 MiB per rotation (300
rotations: 357 -> 494 MiB) and per posture flip. With FusionShadow the same runs stay flat after the
first rotations' warm-up; screenshots of the home screen, launcher, dock and controls match the old
ones (mean difference below 1.2 of 255 per channel).

## FusionLaunchZoom (TABLET2 M1, 2026-10-01)

The app-open zoom in tablet posture: `play(iconItem, source, iconName)` takes the tapped
`FusionIconTile`'s global rectangle and screen, then a card in the tile's board neutral (#1b2031 dark,
#f4f6fb light) with the app's icon grows from the tile to the whole screen (Motion `surface` x 1.2,
decelerating; the icon grows to 128 px). The card's window is a normal-layer, frameless, non-focus
`PlasmaCore.Dialog` without background, so the panels stay above it and the app's window, which KWin
opens on top, covers it: no "app is ready" signal is needed. It fades out (`popupOut`) and unloads
after 4 s or on a tap; a full-screen window costs about 37 MiB of GPU memory only while it exists.
Reduced motion: nothing is shown. Used by the home screen (tiles), the dock (starting a pinned app in
tablet posture) and the launcher sheet (tiles). Each play logs `launch zoom: <icon> from x,y size`.

Test (private session, `build/m1/scen-m1z.sh`, m1x/m1y; evidence `artifacts/plasma-fusion/2026-10-01-tablet2/M1/zoom`):
Discover tapped on the home screen: the splash with its icon fills the screen under the top bar, then
Discover's window opens over it; KCalc and Konsole (fast starts) appear at once over it; the splash
window is not in the dock's task list.

## FusionMetrics changes

- `property bool tablet: Kirigami.Settings.tabletMode`, and `touch` is now `tablet ||
  hasTransientTouchInput`. Unbound it is exactly the old value; bind it to `FusionTablet.tablet`.
- **`dpr` comes from the window** (`Window.window.devicePixelRatio`, Qt 6.11), falling back to
  `Screen.devicePixelRatio`. In plasmashell on Wayland, `Screen.devicePixelRatio` is the output's whole
  buffer scale, 2 at 4/3, 1.325 and 1.5 (measured, `ldb-dpr-*`), so since 560a7de `snap()` and `px()`
  snapped to half logical pixels, `hairline` was 1 logical px (1.33 device px at 4/3) and `step` was 1.
  With the fix (`ldb-dpr2-*`): 4/3 → dpr 1.3333, hairline 0.75 (one device px), step 3; 1.325 → step 1;
  1.5 → hairline 0.667, step 2; 1 → unchanged. This is what `text-scale.md` describes; sizes that go
  through `px()` move by at most half a logical pixel, and 1 px edges become one device pixel. INT-1's
  side-by-side screenshots cover it. The switcher keeps setting `screenScale` itself.

## Checks

`tools/build.sh` runs both checks over `packages/` before the parts. `PF_LINTS=fail` (default since
INT-1) stops on a finding (both checks run first), `warn` lists the findings and builds anyway, `off`
skips them. Both print `FILE:LINE: RULE message | source line` and a count on stderr, exit 1 on a
finding, 0 with `--warn`.

**motion-lint.sh** (EFFECTS 6.2): `literal-duration` (a number in a `duration:` binding, including
`cond ? 600 : 0` and `anim.duration = 300`; a token times a ratio such as `motion.surface * 1.2` is
fine), `over-max` (a Kirigami unit scaled past 400 ms at factor 1, such as `veryLongDuration * 2`),
`infinite-loop` (`loops: Animation.Infinite` or -1), `no-duration` (a Qt Quick animation or animator
with no `duration`, which runs Qt's 250 ms and ignores the speed setting; `SpringAnimation` always).
Allowed: `packages/look-and-feel/common/contents/splash/Splash.qml` (runs only while logging in).
Not checked: Timer intervals, group animations, `FrameAnimation`, custom animation components at
their uses. At HEAD 1f9f576 it lists 24 findings in 13 files: exactly the rows of EFFECTS 6.3 (line
numbers moved since e55a551; the dock's startup pulse is now `loops: 3` with two 500 ms literals, so it
shows as literals, not as an endless loop).

**a11y-lint.py** (GAPS G25): `control-name` (a Qt Quick Controls, Plasma or Kirigami control with no
`Accessible.name` and no text that Qt Quick Controls turn into the name: `text` on buttons, check
boxes and delegates, `placeholderText` on text fields, or a Kirigami form label), `pointer-name` (a
`MouseArea` or `TapHandler` where neither it nor its parent or grandparent names itself),
`focus-name` (`activeFocusOnTab: true` without a name), `component-name` (a use of a package's own
control, for example `IconButton { }`, that sets neither `Accessible.name` nor the property the
control's file names itself from). Skipped: `Accessible.ignored: true` on the item or an ancestor,
`acceptedButtons: Qt.NoButton` areas, `enabled: false`, read-only text, a file's root (checked at its
uses). A dismiss area (click outside to close) is not a control: mark it `Accessible.ignored: true`.
At HEAD: 16 findings in 12 files (4 control, 10 pointer, 2 focus), for example the battery chip and a
notification's default action in quick settings.

Self-test: `tools/checks/tests/run.sh` (each fixture marks the lines a check must report).

## Tests

- `packages/common/tests/offscreen.sh OUTDIR`: stages `Probe.qml` with the blocks through
  `shared-qml.sh` and runs it with Qt's offscreen platform on a private D-Bus bus at scales 1, 1.25,
  4/3, 1.325 and 1.5 (factor 1 and 0), at factors 0.5 and 2, in both schemes and with teal and amber
  accents, with `KDE_KIRIGAMI_TABLET_MODE=1`. It checks every token, the Kirigami fallback of
  FusionTablet, the accent colours, the tile decisions and glyph sizes, the package lookup and the
  tints, and that no block prints a QML message. Needs qml, Kirigami, qqc2-desktop-style,
  plasma-workspace's QML modules and Pillow; about 15 s.
- Private-session scenario (laptop scratch `build/ldb/vs/`, copied to the evidence folder): a test
  widget and a test KWin script built with `shared-qml.sh`, a session with `PFV_TABLET=on`, three
  flips, factor 0 and back, a teal accent and back, a script wallpaper change, a hide and show, a
  `setWallpaper` change and the light scheme.

## Verification (2026-09-30, builder `ldb`)

- Offscreen: 16 runs, all checks passed (scales 1, 1.25, 4/3, 1.325, 1.5).
- Private sessions at 1920x1200, 4/3 (`ldb-final-43`, `ldb-final2-43`) and 1.325 (`ldb-final-1325`),
  `PFV_TABLET=on`: FusionTablet true from KWin within 100 ms and followed 3 flips; with
  `AnimationDurationFactor=0` every token 0 (plasmashell and KWin), all back at factor 1; FusionAccent
  followed teal, the scheme accent and the light scheme; FusionBackdrop drew the blurred wallpaper and
  followed both kinds of wallpaper change. No core dumps (`coredumpctl` since 2026-09-29 23:15).
- Staged tree from a clean HEAD snapshot with these files over it vs HEAD: identical except the 14
  copies of `FusionMetrics.qml`; qmllint signatures of every staged QML file identical (94 lines both);
  the new blocks lint clean.
- Motion lint = EFFECTS 6.3; both checks' self-tests pass; `bash -n` and `shellcheck -S warning` clean.
- `ldb-final2-43` was run by the lead after taking the lane over (2026-09-30 04:4xZ): tablet true/false
  from KWin, motion unit 1 at factor 0 and 200 after, teal accent and back, wallpaper B then A, light
  scheme; `Screen.devicePixelRatio` 2 against the window's 4/3, hairline 0.75. The whole working tree
  (all lanes) also builds with `tools/build.sh` (1 min; lints in warn mode: 24 motion, 16 a11y
  findings in existing packages, for their lanes).

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build2/BASE-1/`.
