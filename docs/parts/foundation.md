# Foundation: colour schemes, fonts, wallpapers, Konsole, Kate/KWrite, GTK

Status 2026-09-29: built, parse-checked, contrast-checked and tested in virtual sessions on the
ThinkPad (dark and light, on its own and inside the whole Plasma Fusion desktop), then reviewed
and fixed in a second pass (see "Review" at the end). Evidence:
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/foundation/` (review: `review-*.png`).

## What this part builds

`tools/build.d/10-foundation.sh` (about 40 s; `PF_WALLPAPER_SIZES=quick` renders only three
sizes for test builds). Output is byte-identical between runs (checked: two builds, 122 files,
same SHA-256).

| Source | Installed at (in the HOME tree) |
|---|---|
| `packages/color-schemes/PlasmaFusionDark.colors`, `PlasmaFusionLight.colors` | `.local/share/color-schemes/` |
| `fonts/manrope/Manrope[wght].ttf`, `fonts/spacegrotesk/SpaceGrotesk[wght].ttf` + both `OFL.txt` | `.local/share/fonts/plasma-fusion/` (`OFL-Manrope.txt`, `OFL-SpaceGrotesk.txt`) |
| `generators/wallpapers/gen_wallpapers.py wallpapers` | `.local/share/wallpapers/PlasmaFusion/` (Dusk Ridge: `contents/images/` light, `contents/images_dark/` dark) and `.local/share/wallpapers/PlasmaFusion-<Name>/` for Aurora, CoralBay, DesertNoon, Ember, Glacier, Lagoon, Meadow, NightGrid, PineFog, PlumHills, SlateRain |
| `generators/wallpapers/gen_wallpapers.py backgrounds` | `.local/share/plasma-fusion/backgrounds/dusk-ridge-dark-{dimmed,blurred,login,splash}.png` |
| `packages/konsole/PlasmaFusionDark.colorscheme`, `PlasmaFusionLight.colorscheme`, `Plasma Fusion.profile` | `.local/share/konsole/` |
| `packages/ktexteditor/Plasma Fusion Dark.theme`, `Plasma Fusion Light.theme` | `.local/share/org.kde.syntax-highlighting/themes/` |
| `packages/gtk/gtk.css`, `packages/gtk/gtk-3.0/plasma-fusion.css`, `packages/gtk/gtk-4.0/plasma-fusion.css` | `.config/gtk-3.0/{gtk.css,plasma-fusion.css}`, `.config/gtk-4.0/{gtk.css,plasma-fusion.css}` |

Other files: `packages/color-schemes/check_contrast.py` (contrast checker, run by the build),
`packages/gtk/check_css.py` (GTK's own CSS parser, run by the build when PyGObject is installed;
it unsets `DISPLAY`/`WAYLAND_DISPLAY` and opens no window), `generators/wallpapers/svg/` (the 39 SVG
sources: every scene at 16:10, 16:9 and portrait; the build fails when they differ from what the
generator writes, `gen_wallpapers.py svg generators/wallpapers/svg` rewrites them) and
`generators/wallpapers/tests/` (virtual-session test tooling, not installed).

Build dependencies: Python 3 with Pillow and PySide6 (QtSvg renders the wallpapers with full
anti-aliasing, offscreen). No network, no absolute paths.

## Applying it

Everything is per user and needs no root. The Global Theme part names these ids in its
`contents/defaults`; the commands below apply them one by one (all verified in virtual sessions).

### Colour schemes

```
plasma-apply-colorscheme PlasmaFusionDark        # or PlasmaFusionLight
```
Global Theme: `[kdeglobals][General] ColorScheme=PlasmaFusionDark` / `PlasmaFusionLight`.
Leave kdeglobals `[General] AccentColor` unset (and `accentColorFromWallpaper=false`): with an
accent Plasma replaces the Selection fill by the accent at 70 % over the view colour and may switch
light-mode selected text to black. The wallpaper package still carries
`X-KDE-PlasmaImageWallpaper-AccentColor {"Light":"#2F6FDF","Dark":"#2F6FDF"}` for people who pick
"From wallpaper".

### Fonts

Install (done by the build into the HOME tree) and refresh fontconfig: `fc-cache -f
~/.local/share/fonts`. fontconfig exposes the named instances of both variable fonts (Manrope
ExtraLight to ExtraBold, Space Grotesk Light to Bold). kdeglobals, Qt 6.11 `QFont::toString` form
(checked with PySide6 6.11.2 `QFont.fromString`/`toString` round trip, and in the Fonts page of
System Settings in the virtual session):

| Group / key | Value | Size |
|---|---|---|
| `[General] font` | `Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0` | 13 px |
| `[General] menuFont` | `Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0` | 13 px |
| `[General] toolBarFont` | `Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0` | 13 px |
| `[General] smallestReadableFont` | `Manrope,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0` | 12 px |
| `[General] fixed` | `Noto Sans Mono,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0` | Fedora default |
| `[WM] activeFont` | `Manrope,10.5,-1,5,800,0,0,0,0,0,0,0,0,0,0,1,,0,0` | 14 px ExtraBold |

Write them with `kwriteconfig6 --notify --file kdeglobals --group General --key font '…'`; with
`--notify` kde-gtk-config also moves GTK to Manrope (`gtk-font-name=Manrope, 10`). The Global Theme
already carries these strings plus the `[kdeglobals][General] activeFont` sentinel that Plasma 6.7.5
needs to detect a font block. Space Grotesk is not a KDE font role: QML sets it where the boards use
it (clock, splash greeting, lock clock, big headings).

Weights. Manrope has named instances for every weight the boards use (200 to 800), so
`font.weight` works for it. Space Grotesk 2.000 has only Light, Regular, Medium and Bold: there is
no SemiBold instance, and the boards' 600 (clocks, weather figure, greeting) cannot come from
`font.weight`. Measured with Qt 6.11.2 (PySide6, fontconfig, the shipped files): `Font.DemiBold`
on Space Grotesk selects the **Bold** instance and draws exactly the same glyphs as 700
(`fc-match "Space Grotesk:weight=180"` also answers Bold). Only the variation axis gives a true 600:

```
font.family: "Space Grotesk"
font.weight: Font.Normal            // keep the weight off the instance choice
font.variableAxes: { "wght": 600 }  // Qt 6.7+; 300 to 700 for Space Grotesk, 200 to 800 for Manrope
```

The same pattern is safe for Manrope (identical output to its named instances), so the shell
parts' `FusionText` helpers that always put the weight on the axis are correct.

Synthetic bold. Qt 6.11.2 adds a synthetic emboldening on top of the named Bold/ExtraBold
instances of these variable fonts for any text of weight 700 or more drawn below 64 px (measured;
the likely cause is that FreeType reports the light default instance's style flags, so Qt sees a
non-bold face). With Manrope that makes every bold label in Qt applications (Dolphin's
breadcrumb, KCM headings, `QFont::setBold`) and the 800 window-title font about a third heavier
than the real Bold/ExtraBold (ink measured at 13-14 px: +38 % for 700, +33 % for 800; identical at
64 px and above). Fedora's variable Noto Sans is affected the same way. Qt's own switch
`QT_NO_SYNTHESIZED_BOLD=1` turns this off; with it the named instances render exactly as the
variation axis does, and bold text in System Settings and Dolphin matches the board's weights
(verified in the review session, `review-bold-synthetic.png`). It has to be in the session
environment before KWin and plasmashell start, i.e. a login script:

```
# ~/.config/plasma-workspace/env/plasma-fusion.sh  (sourced by startplasma at login)
export QT_NO_SYNTHESIZED_BOLD=1
```

This part does not install it (a session-wide file outside the naming table; it must be in the
device script's backup/restore list), see "Needs from other parts". Without it, QML that must show
a true 700/800 below 64 px has to use the axis pattern above (`font.weight: Font.Normal` plus
`font.variableAxes`), as the shell plasmoids already do.

### Wallpapers

```
plasma-apply-wallpaperimage ~/.local/share/wallpapers/PlasmaFusion
```
Global Theme: `[Wallpaper] Image=PlasmaFusion`. With the image unset or set to the package without a
URL fragment the picture follows the Plasma style's darkness (verified: Breeze following Fusion Dark
shows `images_dark/`, Fusion Light shows `images/`). Sizes in every package: 1920x1200, 2560x1600,
3840x2400 (16:10), 1920x1080, 2560x1440, 3840x2160 (16:9) and 1200x1920 (portrait, for the X13 Yoga
in tablet mode); Plasma picks the closest. The ThinkPad panel (1920x1200 physical) gets the exact
board scene.

How the scene is made: `scene_svg()` writes the Main.dc.html SVG (sky #141a2e, bands at y 180/340,
sun r150 at 1010,360 with the r212 orbit ring at 18 %, four ridges) and MainLight.dc.html for the
light variant. Other aspect ratios extend the scene instead of stretching it: 16:9 shows 80 board
units more on each side (ridges continue along their outer slopes, the lower sky band is carried
down behind them); portrait is a 1000-unit crop with the sun at 55 % width and 58 % height, more
sky above and the front ridge filling the lowest 8 %. The palette packages use the thumbnail
palettes of Main.dc.html (background, sun, near ridge, front ridge); the missing sky, bands and
ridges are mixed from them with weights that reproduce the board's own Dusk Ridge scenes from their
palettes to within a few units per channel.

Pixel check against the board renders (1440x900 render vs `desktop-dark-1`/`desktop-light-1`, areas
without windows): mean absolute difference 1.1 to 4.7 per channel (the rest is window shadow in the
render).

Startup backgrounds (1920x1200, `.local/share/plasma-fusion/backgrounds/`), each the board's CSS
reproduced (blur in premultiplied alpha over a transparent surround, `scale(1.08)` about the
centre):

| File | Board | Recipe | Mean diff vs render |
|---|---|---|---|
| `dusk-ridge-dark-dimmed.png` | Lock.dc.html | wallpaper under rgba(8,10,22,.22) | ≤ 2.5 |
| `dusk-ridge-dark-blurred.png` | Login.dc.html without its veil | blur 20 px, scale 1.08, over #0f1428 (no top band, no ring) | — |
| `dusk-ridge-dark-login.png` | Login.dc.html | the blurred one under rgba(8,11,24,.5) | ≤ 0.8 |
| `dusk-ridge-dark-splash.png` | Splash.dc.html | blur 26 px, scale 1.08, 28 % over #0b0e1b (no bands, no ring) | ≤ 1.6 |

### Konsole

```
kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile "Plasma Fusion.profile"
```
The profile uses `PlasmaFusionDark` in both Global Themes, as the Light boards also draw the terminal
dark (OverviewLight, TabsSnap). `PlasmaFusionLight` is there for people who want a light terminal
(`konsole --profile "Plasma Fusion" -p ColorScheme=PlasmaFusionLight` to try it). Font: Noto Sans
Mono 11 pt (Fedora's `fc-match monospace`; Space Grotesk is not monospaced), block cursor, 14 px
margin, 2 px extra line spacing, bold text uses the bright colours.

The board's teal prompt appears with any prompt that uses cyan (ANSI 6 = #3cc4b0); Fedora's default
bash prompt has no colour and this part does not change shell files. A prompt like the board's:
`PS1='\[\e[36m\]\w $\[\e[0m\] '` in `~/.bashrc`.

### Kate and KWrite

```
kwriteconfig6 --file kwriterc --group "KTextEditor Renderer" --key "Auto Color Theme Selection" false
kwriteconfig6 --file kwriterc --group "KTextEditor Renderer" --key "Color Theme" "Plasma Fusion Dark"
# the same two keys in katerc for Kate
```
KTextEditor's automatic choice only knows Breeze Light/Dark, so the theme must be set explicitly.
Recommended: "Plasma Fusion Dark" under both Global Themes, like the dark code window on the Light
boards; "Plasma Fusion Light" is the light alternative.

### GTK

`~/.config/gtk-3.0/gtk.css` and `~/.config/gtk-4.0/gtk.css` contain only

```
@import 'colors.css';
@import 'plasma-fusion.css';
```

How this switches with the colour scheme: kde-gtk-config (kded module `gtkconfig`) rewrites
`colors.css` (named colours such as `@theme_selected_bg_color_breeze`) on every colour-scheme
change, and its `addImportStatementsToGtkCssUserFile()` keeps the existing `gtk.css` untouched as
long as it contains `@import 'colors.css';` (otherwise it appends that line). `plasma-fusion.css`
takes every colour from those named colours (`alpha()`, `mix()`, `shade()` of them), so one file
serves Fusion Dark and Fusion Light and follows a later scheme change. Verified in the virtual
sessions: after `plasma-apply-colorscheme` the file kept both imports and `colors.css` held the
Fusion values.

What the CSS does (design/boards/Controls.dc.html):
- GTK 3 (Breeze GTK theme): 10 px corners on text/image/toggle buttons, combo boxes, entries and
  spin buttons, with the joined edges of linked groups squared again; 6 px check boxes; 8 px
  tooltips; menus and pop-overs 14 px with 6 px padding, 32 px items with 8 px corners and a soft
  accent hover (`#5b9dff` at 16 %, accent-tinted text), separators inset 8 px; solid accent
  (`suggested-action`) and solid #C93A42 (`destructive-action`) buttons with white bold text; white
  switch and slider knobs; switch "on" track, slider fill and progress fill in the solid accent (Breeze GTK
  draws them as a 33-50 % tint of the hover colour, a pale blue, where the board and Breeze for Qt
  use the accent; disabled controls keep Breeze's look); keyboard focus ring 2 px in the focus
  colour with a 2 px gap; focused fields get the focus colour border plus a 3 px soft ring.
- GTK 4 / libadwaita: the libadwaita palette (`accent_bg_color`, `accent_fg_color`,
  `accent_color`, `window_bg_color`, `window_fg_color`, `view_bg_color`, `view_fg_color`,
  `headerbar_*`, `sidebar_*`, `secondary_sidebar_*`, `card_*`, `dialog_*`, `popover_*`,
  `thumbnail_*`, `destructive_*`, `error_*`, `success_color`, `warning_color`) as named colours and
  as the matching `--*-color` variables at user priority, so GNOME apps get the exact #2F6FDF accent
  (not the nearest of libadwaita's nine accents) and the Fusion surfaces; 14 px pop-overs with 8 px
  items and the same soft hover; solid destructive buttons; the focus ring as above; plain GTK 4
  applications drawn with Breeze get the same solid accent switch/slider/progress fills as GTK 3
  (libadwaita already draws them so).

Rules for applying it to an existing HOME: if `gtk.css` exists and has other lines, append
`@import 'plasma-fusion.css';` after its `@import 'colors.css';` instead of replacing the file, and
back the file up first. To switch it off, delete that import line. Flatpak GTK apps only see it with
`flatpak override --user --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro`.

## Colour scheme mapping

Sources: Colors.dc.html (every text/background pair) and Controls.dc.html; derived values are
marked (d). Accent fill #2F6FDF in both.

| Set | Dark: background / alternate / text / secondary | Light: background / alternate / text / secondary |
|---|---|---|
| Window | #1b2031 / #181c2b / #e8ebf4 / #a3abc2 | #ffffff / #f5f6fa / #141827 / #4d546a |
| View | #1f2540 / #232a47 (d, Controls menu) / #e8ebf4 / #a3abc2 | #ffffff / #f5f6fa (d) / #141827 / #4d546a |
| Button | #262d4c / #28395a (d) / #e8ebf4 / #a3abc2 | #eef0f5 / #e6eefb (d) / #141827 / #4d546a |
| Selection | #2f6fdf / #28395a (soft row) / #ffffff / #dbe7ff (d) | #2f6fdf / #e6eefb (soft row) / #ffffff / #dbe7ff (d) |
| Tooltip | #0c0f1c / #141827 (d) / #e8ebf4 / #a3abc2 | #1b2031 / #222840 (d) / #ffffff / #a3abc2 |
| Complementary | #1a1f33 / #141a2e (d) / #e8ebf4 / #a3abc2 | #f7f8fb / #eef0f5 (d) / #141827 / #5b6278 |
| Header (title bar) | #222840 / #1b2031 (d) / #e8ebf4 / #a3abc2 | #eceff6 / #f5f6fa (d) / #141827 / #4d546a |
| Header, inactive | #1f2536 / #1b2031 (d) / #8891aa / #6f7892 (d) | #f1f3f8 / #f5f6fa (d) / #646b80 / #7c8396 (d) |

Shared roles, dark / light: link and active #8ab8ff / #2359c4, visited #c3a6ff / #6b3fb5, negative
#ff8a8f / #b3262e, neutral #f5c08c / #8f4f12, positive #7fd99c / #23703b, DecorationFocus (focus
ring) #8ab8ff / #2f6fdf, DecorationHover #5b9dff in both (the base of every soft accent tint on the
shell boards, and the quick-settings slider fill). The Tooltip set in Light uses the dark palette's
accents (it is a dark surface). Selection keeps white text and pale status tints.

Other keys:
- `[WM]` copies the Header colours (blend = foreground), dark #222840/#e8ebf4 and #1f2536/#8891aa,
  light #eceff6/#141827 and #f1f3f8/#646b80. KWin's decoration palette reads the Header groups.
- `[General] TintFactor=0`: since Plasma 6.7.0 applying a scheme without a TintFactor key writes the
  Window colours into `[Colors:Header][Inactive]`; with the key the scheme's own inactive title-bar
  colours pass through a tint of factor 0. Verified in kdeglobals after `plasma-apply-colorscheme`:
  exactly 31,37,54 / 136,145,170 (dark) and 241,243,248 / 100,107,128 (light).
- `[ColorEffects:Disabled]`: fade the text towards the background (`ContrastAmount` 0.53 dark, 0.59
  light) plus a 10 % darkening in dark, chosen so the disabled text hits the board's contrast
  (3.7:1 dark, 2.6:1 light; estimated `#757986` and `#9fa0a6` with KColorScheme's algorithm).
  `[ColorEffects:Inactive]` as Breeze (disabled). The applicator copies nine keys per group and
  writes an empty value for a missing one; `[ColorEffects:Disabled]` has eight of them plus
  `Enable=true` and, like Breeze, no `ChangeSelectionColor`, which KColorScheme reads only for the
  Inactive group, so the empty value it leaves in kdeglobals has no effect.
- `[KDE] contrast=4`, `frameContrast` 0.13 (dark: mix(window, text) ≈ the board's white 12 % edge) and
  0.14 (light: exactly the board's rgba(20,24,39,.14) border).

## Contrast (WCAG 2), `packages/color-schemes/check_contrast.py --markdown`

The build runs the checker and stops if a board colour is missing from the scheme, a ratio differs
from the board's figure by more than 0.1, or a pair falls below its minimum.

#### PlasmaFusionDark: board pairs

| Role | KDE section | Scheme fg / bg | Ratio | Board | Minimum | Result |
|---|---|---|---:|---:|---:|---|
| Text | Window · ForegroundNormal | `#e8ebf4` / `#1b2031` | 13.6:1 | 13.6:1 | 4.5 | pass |
| Secondary text | Window · ForegroundInactive | `#a3abc2` / `#1b2031` | 7.1:1 | 7.1:1 | 4.5 | pass |
| Disabled text | Window · disabled effect | `#757986` / `#1b2031` | 3.7:1 | 3.7:1 | - | exempt (estimate; board #6f7892 3.7:1) |
| Alternate background | Window · BackgroundAlternate | `#e8ebf4` / `#181c2b` | 14.2:1 | 14.2:1 | 4.5 | pass |
| Fields and lists | View · BackgroundNormal | `#e8ebf4` / `#1f2540` | 12.6:1 | 12.6:1 | 4.5 | pass |
| Link | View · ForegroundLink | `#8ab8ff` / `#1f2540` | 7.4:1 | 7.4:1 | 4.5 | pass |
| Visited link | View · ForegroundVisited | `#c3a6ff` / `#1f2540` | 7.3:1 | 7.3:1 | 4.5 | pass |
| Button | Button · BackgroundNormal | `#e8ebf4` / `#262d4c` | 11.3:1 | 11.3:1 | 4.5 | pass |
| Button, hover | Button · hover fill (style) | `#e8ebf4` / `#2d355a` | 10.0:1 | 10.0:1 | 4.5 | pass |
| Selected, focused | Selection · BackgroundNormal | `#ffffff` / `#2f6fdf` | 4.7:1 | 4.7:1 | 4.5 | pass |
| Selected row, soft | Selection · BackgroundAlternate | `#cfe0ff` / `#28395a` | 8.6:1 | 8.6:1 | 4.5 | pass |
| Focus ring | Button · DecorationFocus | `#8ab8ff` / `#1b2031` | 8.0:1 | 8.0:1 | 3.0 | pass |
| Positive | Window · ForegroundPositive | `#7fd99c` / `#1b2031` | 9.5:1 | 9.5:1 | 4.5 | pass |
| Neutral / warning | Window · ForegroundNeutral | `#f5c08c` / `#1b2031` | 9.9:1 | 9.9:1 | 4.5 | pass |
| Negative | Window · ForegroundNegative | `#ff8a8f` / `#1b2031` | 7.2:1 | 7.2:1 | 4.5 | pass |
| Destructive fill | Button · negative fill (style) | `#ffffff` / `#c93a42` | 5.0:1 | 5.0:1 | 4.5 | pass |
| Title bar, active | Header · BackgroundNormal | `#e8ebf4` / `#222840` | 12.2:1 | 12.2:1 | 4.5 | pass |
| Title bar, inactive | Header · Inactive | `#8891aa` / `#1f2536` | 4.9:1 | 4.9:1 | 4.5 | pass |
| Shell panels | Complementary · BackgroundNormal | `#e8ebf4` / `#1a1f33` | 13.7:1 | 13.7:1 | 4.5 | pass |
| Shell secondary | Complementary · ForegroundInactive | `#a3abc2` / `#1a1f33` | 7.1:1 | 7.1:1 | 4.5 | pass |
| Tooltip | Tooltip · BackgroundNormal | `#e8ebf4` / `#0c0f1c` | 16.0:1 | 16.0:1 | 4.5 | pass |

#### PlasmaFusionDark: every role on its own background

| Set | Background | Fg Normal | Fg Inactive | Fg Active | Fg Link | Fg Visited | Fg Negative | Fg Neutral | Fg Positive | Deco Focus | Deco Hover |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Window | `#1b2031` | 13.6 | 7.1 | 8.0 | 8.0 | 7.9 | 7.2 | 9.9 | 9.5 | 8.0 | 5.9 |
| View | `#1f2540` | 12.6 | 6.6 | 7.4 | 7.4 | 7.3 | 6.6 | 9.2 | 8.8 | 7.4 | 5.5 |
| Button | `#262d4c` | 11.3 | 5.9 | 6.6 | 6.6 | 6.5 | 5.9 | 8.2 | 7.9 | 6.6 | 4.9 |
| Selection | `#2f6fdf` | 4.7 | 3.8 | 4.7 | 4.7 | 4.0 | 3.6 | 4.0 | 4.1 | 2.3 | 1.7 |
| Tooltip | `#0c0f1c` | 16.0 | 8.3 | 9.4 | 9.4 | 9.3 | 8.4 | 11.6 | 11.2 | 9.4 | 7.0 |
| Complementary | `#1a1f33` | 13.7 | 7.1 | 8.1 | 8.1 | 7.9 | 7.2 | 9.9 | 9.6 | 8.1 | 6.0 |
| Header | `#222840` | 12.2 | 6.3 | 7.2 | 7.2 | 7.1 | 6.4 | 8.9 | 8.5 | 7.2 | 5.3 |
| Header Inactive | `#1f2536` | 4.9 | 3.5 | 7.5 | 7.5 | 7.4 | 6.7 | 9.3 | 8.9 | 7.5 | 5.6 |

Soft selection row (board: 20 % #5b9dff accent over the window colour) = `#28395a`; `#cfe0ff` text on it 8.6:1; Window text on it 9.7:1.

#### PlasmaFusionLight: board pairs

| Role | KDE section | Scheme fg / bg | Ratio | Board | Minimum | Result |
|---|---|---|---:|---:|---:|---|
| Text | Window · ForegroundNormal | `#141827` / `#ffffff` | 17.7:1 | 17.7:1 | 4.5 | pass |
| Secondary text | Window · ForegroundInactive | `#4d546a` / `#ffffff` | 7.5:1 | 7.5:1 | 4.5 | pass |
| Disabled text | Window · disabled effect | `#9fa0a6` / `#ffffff` | 2.6:1 | 2.6:1 | - | exempt (estimate; board #9aa0b2 2.6:1) |
| Alternate background | Window · BackgroundAlternate | `#141827` / `#f5f6fa` | 16.3:1 | 16.3:1 | 4.5 | pass |
| Fields and lists | View · BackgroundNormal | `#141827` / `#ffffff` | 17.7:1 | 17.7:1 | 4.5 | pass |
| Link | View · ForegroundLink | `#2359c4` / `#ffffff` | 6.4:1 | 6.4:1 | 4.5 | pass |
| Visited link | View · ForegroundVisited | `#6b3fb5` / `#ffffff` | 7.0:1 | 7.0:1 | 4.5 | pass |
| Button | Button · BackgroundNormal | `#141827` / `#eef0f5` | 15.5:1 | 15.5:1 | 4.5 | pass |
| Button, hover | Button · hover fill (style) | `#141827` / `#e4e7ef` | 14.3:1 | 14.3:1 | 4.5 | pass |
| Selected, focused | Selection · BackgroundNormal | `#ffffff` / `#2f6fdf` | 4.7:1 | 4.7:1 | 4.5 | pass |
| Selected row, soft | Selection · BackgroundAlternate | `#1d4fb0` / `#e6eefb` | 6.4:1 | 6.4:1 | 4.5 | pass |
| Focus ring | Button · DecorationFocus | `#2f6fdf` / `#ffffff` | 4.7:1 | 4.7:1 | 3.0 | pass |
| Positive | Window · ForegroundPositive | `#23703b` / `#ffffff` | 6.1:1 | 6.1:1 | 4.5 | pass |
| Neutral / warning | Window · ForegroundNeutral | `#8f4f12` / `#ffffff` | 6.4:1 | 6.4:1 | 4.5 | pass |
| Negative | Window · ForegroundNegative | `#b3262e` / `#ffffff` | 6.5:1 | 6.5:1 | 4.5 | pass |
| Destructive fill | Button · negative fill (style) | `#ffffff` / `#c93a42` | 5.0:1 | 5.0:1 | 4.5 | pass |
| Title bar, active | Header · BackgroundNormal | `#141827` / `#eceff6` | 15.3:1 | 15.3:1 | 4.5 | pass |
| Title bar, inactive | Header · Inactive | `#646b80` / `#f1f3f8` | 4.8:1 | 4.8:1 | 4.5 | pass |
| Shell panels | Complementary · BackgroundNormal | `#141827` / `#f7f8fb` | 16.6:1 | 16.6:1 | 4.5 | pass |
| Shell secondary | Complementary · ForegroundInactive | `#5b6278` / `#f7f8fb` | 5.7:1 | 5.7:1 | 4.5 | pass |
| Tooltip | Tooltip · BackgroundNormal | `#ffffff` / `#1b2031` | 16.2:1 | 16.2:1 | 4.5 | pass |

#### PlasmaFusionLight: every role on its own background

| Set | Background | Fg Normal | Fg Inactive | Fg Active | Fg Link | Fg Visited | Fg Negative | Fg Neutral | Fg Positive | Deco Focus | Deco Hover |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Window | `#ffffff` | 17.7 | 7.5 | 6.4 | 6.4 | 7.0 | 6.5 | 6.4 | 6.1 | 4.7 | 2.7 |
| View | `#ffffff` | 17.7 | 7.5 | 6.4 | 6.4 | 7.0 | 6.5 | 6.4 | 6.1 | 4.7 | 2.7 |
| Button | `#eef0f5` | 15.5 | 6.6 | 5.6 | 5.6 | 6.1 | 5.7 | 5.6 | 5.3 | 4.1 | 2.4 |
| Selection | `#2f6fdf` | 4.7 | 3.8 | 4.7 | 4.7 | 4.0 | 3.6 | 4.0 | 4.1 | 1.0 | 1.7 |
| Tooltip | `#1b2031` | 16.2 | 7.1 | 8.0 | 8.0 | 7.9 | 7.2 | 9.9 | 9.5 | 8.0 | 5.9 |
| Complementary | `#f7f8fb` | 16.6 | 5.7 | 6.0 | 6.0 | 6.6 | 6.1 | 6.0 | 5.7 | 4.4 | 2.6 |
| Header | `#eceff6` | 15.3 | 6.5 | 5.5 | 5.5 | 6.1 | 5.6 | 5.5 | 5.3 | 4.1 | 2.4 |
| Header Inactive | `#f1f3f8` | 4.8 | 3.4 | 5.7 | 5.7 | 6.3 | 5.9 | 5.7 | 5.5 | 4.2 | 2.5 |

Soft selection row (board: 12 % #2f6fdf accent over the window colour) = `#e6eefb`; `#1d4fb0` text on it 6.4:1; Window text on it 15.1:1.

Minimums used: text roles 4.5:1; the focus colour 3:1; no minimum for the hover colour (a hover cue,
the control is identifiable without it) and for the secondary roles on the accent fill (3.6 to 4.1:1,
pale status tints on #2F6FDF); the inactive title bar's secondary text 3:1 (3.5 dark, 3.4 light).

### Terminal and editor colours

| Konsole Dark on `#0f1320` | normal | ratio | bright | ratio |
|---|---|---:|---|---:|
| foreground | `#cdd3e4` | 12.4 | `#f2f4f8` | 16.8 |
| 0 black | `#262d4c` | 1.4 | `#5d6680` | 3.2 |
| 1 red | `#ec5f67` | 5.6 | `#ff8a8f` | 8.2 |
| 2 green | `#3aa65b` | 6.0 | `#7fd99c` | 10.9 |
| 3 yellow | `#f2a65a` | 9.1 | `#f2c38a` | 11.4 |
| 4 blue | `#5b9dff` | 6.8 | `#8ab8ff` | 9.2 |
| 5 magenta | `#9b7bf0` | 5.7 | `#c3a6ff` | 9.0 |
| 6 cyan | `#3cc4b0` | 8.6 | `#72dcca` | 11.3 |
| 7 white | `#cdd3e4` | 12.4 | `#ffffff` | 18.5 |

Faint text (`\e[2m`, the board's grey progress lines) is `#8f98b3` (6.4:1); faint colours are each
colour 40 % towards the background. Black is the card colour and meant for backgrounds.

| Konsole Light on `#ffffff` | normal | ratio | bright | ratio |
|---|---|---:|---|---:|
| foreground | `#141827` | 17.7 | `#0b0e1b` | 19.2 |
| 0 black | `#141827` | 17.7 | `#4d546a` | 7.5 |
| 1 red | `#b3262e` | 6.5 | `#c93a42` | 5.0 |
| 2 green | `#23703b` | 6.1 | `#27803f` | 4.9 |
| 3 yellow | `#8f4f12` | 6.4 | `#a65e17` | 5.0 |
| 4 blue | `#2359c4` | 6.4 | `#2f6fdf` | 4.7 |
| 5 magenta | `#6b3fb5` | 7.0 | `#7b5cd6` | 4.8 |
| 6 cyan | `#0e7c6f` | 5.1 | `#0f8274` | 4.7 |
| 7 white | `#6f7892` | 4.4 | `#9aa0b2` | 2.6 |

KTextEditor Dark (background `#161a26`, gutter `#121520`, the Overview board's code window):
Normal `#cdd3e4` 11.6; Keyword and ControlFlow (bold) `#9b7bf0` 5.4; Function, DataType, Import,
QML types (Others) `#8ab8ff` 8.6; Attribute and Variable `#3cc4b0` 8.0; String `#f2a65a` 8.6;
numbers and constants `#f07fa8` 6.9; Comment (italic) `#7a84a0` 4.7; Preprocessor `#c3a6ff` 8.4;
Error `#ff8a8f` 7.7; selection #28395a (the soft row), current line #1b2031.

KTextEditor Light (background `#ffffff`): Normal `#141827` 17.7; Keyword `#6b3fb5` 7.0; Function,
DataType, Others `#2359c4` 6.4; Attribute `#0e7c6f` 5.1; String `#a4550a` 5.4; numbers
`#b8336a` 5.6; Comment `#656d85` 5.1; Preprocessor `#7b5cd6` 4.8; Error `#b3262e` 6.5; selection
#d6e3f8, current line #f5f6fa.

## Verification

Offline:
- `python3 packages/color-schemes/check_contrast.py` (every board pair and role, see above);
  `kreadconfig6 --file …/PlasmaFusionDark.colors --group Colors:Header --group Inactive --key
  BackgroundNormal` parses the files.
- `QFont.fromString`/`toString` round trip of every font string (PySide6 6.11.2 = system Qt).
- `XDG_DATA_HOME=… ksyntaxhighlighter6 --list-themes` lists both themes; `-f html --theme …`
  renders with their colours.
- `packages/gtk/check_css.py 3.0|4.0 …` (GTK 3.24.52 and 4.22.5 parsers; a deliberate error is
  reported, the shipped files parse clean).
- Wallpapers: pixel comparison with the board renders (see above); `gen_wallpapers.py check-svg`;
  reproducible build (two runs, identical SHA-256).

Virtual sessions on the ThinkPad (`tools/vsession/remote.sh`, names `fd-1` to `fd-9`; final evidence from `fd-6`/`fd-8` (dark), `fd-7` (light) and `fd-9` (integrated); seed from
`generators/wallpapers/tests/make-seed.sh`):
- `scenario-dark.sh` / `scenario-light.sh`: fonts with `kwriteconfig6 --notify`,
  `plasma-apply-colorscheme`, `plasma-apply-wallpaperimage`, plasmashell restarted with
  `QT_FORCE_STDERR_LOGGING=1`, then System Settings (Colours and Fonts pages), Dolphin on a folder
  of the 12 wallpapers, Konsole with the profile, KWrite with the theme, a GTK 3 and a libadwaita
  test window (buttons, fields, checks, switches, slider, progress, menus, keyboard focus), the
  logout greeter (`--windowed`) and the stock lock screen (`kscreenlocker_greet --testing`).
  Results: header-inactive values as above; `colors.css` written with the Fusion values and
  `gtk.css` kept; `gtk-font-name=Manrope, 10`; fontconfig lists Manrope and Space Grotesk with all
  named instances; no GTK CSS parser warnings; no QML/plasmashell messages from this part (it
  ships no QML; the logs only show the virtual session's missing kdeconnect/PipeWire/a11y bus).
- `scenario-integrated.sh` (seed `make-seed.sh --all`): every part built, applied with
  `tools/device/fusion-config.sh` (dark, then `--light`); the scheme, fonts and wallpaper come in
  through the Global Theme; Konsole opens with the default profile set in konsolerc.

Screenshots (`…/2026-09-29-build/foundation/`): `sbs-desktop-{dark,light}.png` (board Main vs
System Settings on the wallpaper), `sbs-controls-gtk-{dark,light}.png` (Controls board vs GTK 3 and
libadwaita), `sbs-konsole.png`, `sbs-kwrite.png`, `wallpapers-contact-sheet.png` (all packages,
aspect ratios and startup backgrounds), `session-dark/`, `session-light/` (every scenario shot),
`integrated/` (whole desktop), `logs/` (kdeglobals inactive header values, GTK state, fc-list).

## Deviations from the boards

- Board values that are not colour-scheme roles are drawn by the application style, not by this
  part: the button hover/pressed fills (#2d355a/#212846, #e4e7ef/#d9dde8), the soft selected-row
  text (#cfe0ff/#1d4fb0) and the destructive fill #C93A42 (KDE has no role; the GTK CSS hard-codes
  it, Breeze has no destructive button).
- Fusion Light Window is #ffffff (Colors board). The boards draw sidebars in the Window alternate
  colour (#f5f6fa, dark #181c2b); Breeze/Kirigami draw sidebars in the Window or View colour, so they
  are white in Light and #1b2031/#1f2540 in Dark. The Controls board's page colour #f6f7fa is a
  board background, not the scheme's.
- DecorationHover is #5b9dff in both schemes. The Colors board labels its "Button, hover" row
  (#2d355a dark, #e4e7ef light) "Button · DecorationHover", but in KDE that role is not a fill: Breeze
  draws it as the hover outline of buttons, fields, check boxes and tabs, Kirigami as the list hover
  tint, Breeze GTK as the pressed/hover tint, and the quick-settings slider reads it. With #2d355a
  (1.1:1 against the #262d4c button) every hover cue would vanish, so the row's fill is recorded as a
  style value (`check_contrast.py` lists it as "hover fill (style)") and the role keeps the accent
  tint that every shell board uses for hover and soft selection. In Light (research draft: #2f6fdf)
  it is 2.7:1 on white, acceptable for a hover cue. The same holds for the "Selected row, soft" row
  (board label "Selection · tinted"), kept as Selection BackgroundAlternate.
- Complementary follows the board in Light (#f7f8fb, text #141827, secondary #5b6278). Consequences
  (verified): background-less desktop applets get dark text on the wallpaper (right on the light
  Dusk Ridge; custom desktop cards must use `StandardBackground` anyway); the stock lock screen
  (`LockScreenUi.qml`) shows dark text on its wallpaper; the Breeze logout screen, which a Global
  Theme without its own `contents/logout/` falls back to, draws Complementary text on black at 85 %
  and becomes unreadable in Fusion Light (`session-light/light-10-logout.png`). Kicker's dashboard
  and the plasma-login greeter (after "Apply Plasma Settings") also use Complementary. The Global
  Theme part now ships its own `contents/logout/` whose veil takes the Complementary background, so
  the Light log-out screen is readable (review run, `review-light-logout.png`); the lock-screen shell
  sets its own colours.
- Switch/slider/progress geometry in GTK 3 stays Breeze's (16 px slider knob, 4 px trough) where
  the board has a 20 px knob and a 6 px track; only their colours follow the board.
- GTK font size: kde-gtk-config writes whole points, `Manrope, 10` (13.3 px) for the 9.75 pt font.
- GTK geometry stays the toolkit's where overriding is fragile: Breeze GTK 3 keeps its box tabs,
  segmented buttons and switch track shape; libadwaita keeps its filled entries, 9 px buttons and
  flat header bars. Only corners of menus/pop-overs, fields and buttons, the focus ring, the accent
  and destructive fills (buttons, switch track, slider and progress fill), the switch and slider
  knobs and the palette are changed.
- Konsole's teal prompt needs a coloured shell prompt (not set by this part); the ANSI palette maps
  cyan to #3cc4b0 and bold yellow to the board's #f2c38a warning colour.
- KTextEditor has no automatic Fusion theme selection (it only switches between Breeze Light and
  Dark); the theme is set explicitly (see Applying).
- Palette packages other than Dusk Ridge exist in one variant each (the board gives one palette per
  picture); their sky bands and middle ridges are derived colours.

## Needs from other parts

- **Device setup (lead, `tools/device/fusion-config.sh` and `fusion-restore.sh`)** — **open:** write
  `~/.config/plasma-workspace/env/plasma-fusion.sh` with `export QT_NO_SYNTHESIZED_BOLD=1` (see
  Fonts, "Synthetic bold"), back up/restore it like the other files, and tell the user to log out and
  in. Without it every bold Qt label and the 800 window titles are drawn a third heavier than the
  design.
- **Global Theme / device setup (lookandfeel, `tools/device/fusion-config.sh`)** — all done by
  that part as of the review (checked in the integrated review runs `rfd-1`/`rfd-2`):
  - own `contents/logout/` readable in Light (done);
  - `konsolerc [Desktop Entry] DefaultProfile=Plasma Fusion.profile` and `katerc`/`kwriterc`
    `[KTextEditor Renderer] Auto Color Theme Selection=false`, `Color Theme=Plasma Fusion Dark`
    (done; kreadconfig6 in the session);
  - `gtk.css` backed up and merged (the seed's own rule was kept and `@import 'plasma-fusion.css';`
    added; done);
  - kdeglobals `[General] AccentColor` left unset (done);
  - optional: `dusk-ridge-dark-splash.png` is the Splash board background at 1920x1200 if the splash
    wants a ready-made file (not used yet).
- **Lock screen shell (`org.plasmafusion.lockshell`)**: use explicit dark colours from the Lock board
  rather than Kirigami's Complementary set (it is light in Fusion Light; the shell does this);
  `~/.local/share/plasma-fusion/backgrounds/dusk-ridge-dark-dimmed.png` is the Lock board background.
  **Open:** `BigClock.qml` (148 px clock and its suffix), `SmallClock.qml` (28 px time) and
  `UserHeader.qml` (name) set Space Grotesk with `font.weight: Font.DemiBold`; Space Grotesk has no
  SemiBold instance, so Qt draws the Bold (700) instance there (see Fonts;
  `review-space-grotesk-weights.png`). Use `font.weight: Font.Normal` with `font.variableAxes: {"wght": 600}`
  as the shell plasmoids' `FusionText` and the splash already do.
- **Login screen (phase 2, root)**: install the fonts system-wide (`/usr/local/share/fonts/plasma-fusion`
  or an RPM) and use `dusk-ridge-dark-login.png` as the greeter wallpaper (blur and veil included).
- **Plasma style, quick settings**: the values they asked for hold: Tooltip 12,15,28 / 27,32,49 with
  light text, Selection 47,111,223, DecorationFocus 138,184,255 / 47,111,223, DecorationHover
  91,157,255 (now in both schemes).

## Test tooling (not installed)

`generators/wallpapers/tests/`: `make-seed.sh [--all] SEED`, `scenario-dark.sh`,
`scenario-light.sh`, `scenario-common.sh`, `scenario-integrated.sh`, the GTK 3 and libadwaita test
windows (`gtk3-controls.py`, `adw-controls.py`, PyGObject on the ThinkPad), `demo.sh` and
`sample.qml` (Konsole and KWrite content), `sbs.py DARK_OUT LIGHT_OUT EVIDENCE_DIR` and
`sheet.py STAGE OUT.png` for the comparison images.

## Review (2026-09-29, second pass)

An independent review re-read the boards (Colors, Controls, Main/MainLight, Overview, TabsSnap,
Lock/Login/Splash) and the upstream sources the part depends on, rebuilt everything into its own
stage and tested the part inside the whole Plasma Fusion desktop on the ThinkPad (virtual sessions
`rfd-1` dark, `rfd-2` dark then switched to light with `fusion-config.sh --light`). Evidence:
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/foundation/review-*.png`.

What was checked and held:
- Colour schemes: every group and key of `/usr/share/color-schemes/BreezeDark.colors` is present
  (only the translated `Name[..]` keys are absent); every Colors-board pair matches
  (`check_contrast.py`, 21 pairs per scheme). `colorsapplicator.cpp` (plasma-workspace 6.7.5) was
  read to confirm the `TintFactor=0` behaviour (without the key the inactive title-bar colours are
  replaced by the Window colours; with it and no accent they pass through unchanged, and with a user
  accent the factor 0 still keeps them), the `[WM]` fallback and how `[ColorEffects:*]` keys are
  copied. After the Global Theme applied the scheme, kdeglobals held the Fusion values and
  kde-gtk-config's `colors.css` switched from the dark to the light values on `--light`.
- Fonts: both variable fonts install and resolve; the kdeglobals strings parse in Qt 6.11.2; see
  the two font findings below.
- Wallpapers: the 16:10 images are the board SVG itself (the generator's SVG and the board's own
  SVG rendered by QtSvg at 1920x1200 differ by at most 2 per channel), ridge and sun edges are
  anti-aliased, `metadata.json` matches the stock packages and the accent key matches the parser in
  `mediaproxy.cpp`; Plasma's `packagefinder.cpp` distance picks 1920x1200 for the ThinkPad panel and
  1200x1920 in portrait. The integrated desktops match `desktop-{dark,light}-1` within 2-6 per
  channel in window-free areas.
- Build: `tools/build.sh` with every part into the review stage, rc 0; the foundation output is
  byte-identical between two builds (122 files) and the fixes below changed only the two GTK CSS
  files. KTextEditor themes load (`ksyntaxhighlighter6 --list-themes`), the GTK CSS parses with
  GTK 3.24.52 and 4.22.5, the Konsole profile opens as the default profile, KWrite shows the theme,
  the user's own `gtk.css` rule was kept by the merge, and plasmashell/KWin logs show nothing from
  this part.

Fixed in this pass:
- GTK 3 and Breeze-drawn GTK 4: the switch "on" track, slider fill and progress fill were a pale
  33-50 % tint of DecorationHover (Breeze GTK's recipe) instead of the board's solid #2F6FDF (which
  Breeze for Qt also uses); now solid accent, disabled controls keep Breeze's look
  (`review-gtk-accent-fills.png`, `review-sbs-controls-gtk-{dark,light}.png`).
- GTK slider knob: dark #262d4c in Fusion Dark and light grey in libadwaita dark; now white with a
  soft shadow (and a 1 px edge in GTK 4), as in both columns of the Controls board.
- Documentation: the Space Grotesk weight guidance was wrong (`Font.DemiBold` gives Bold, see
  Fonts); the DecorationHover deviation now says that the board maps its hover fill to that role
  and why the role keeps #5b9dff; the ColorEffects note no longer claims nine keys in both groups;
  "Needs from other parts" reflects what the Global Theme part and the device script now do.

Open (outside this part's files):
- `QT_NO_SYNTHESIZED_BOLD=1` in the session environment (lead, device script): measured and
  verified in the session, `review-bold-synthetic.png`.
- Lock-screen shell: Space Grotesk 600 through the variation axis (`review-space-grotesk-weights.png`).
- The virtual session starts kded6 before the Global Theme exists, so kde-gtk-config there does not
  read `~/.config/kdedefaults` and GTK's `settings.ini` keeps Noto Sans and Breeze icons; a real
  login (startplasma sets `XDG_CONFIG_DIRS`) does not have this limit. The first pass verified the
  Manrope GTK font with direct `kwriteconfig6 --notify` writes.
- Unchanged deviations listed above (GTK geometry partial, soft selection is a style matter, one
  variant per palette wallpaper).

Review scratch work ran under `build/rfd/` (git-ignored) because the /tmp quota was full; the
ThinkPad's `/tmp/pfv-rfd-*` were removed afterwards.
