# Plasma style: plasma-fusion-dark, plasma-fusion-light

Status: built and checked in private virtual sessions on the ThinkPad (1440x900 at scale 1, and
1920x1200 at scale 4/3), dark and light; reviewed and fixed in an integrated session with every
part (see "Review" at the end). Last edited 2026-09-29.

## What it is

Two Plasma styles (desktop themes) generated from the design boards by one Python generator:

| Id | Name | Used by |
|---|---|---|
| `plasma-fusion-dark` | Plasma Fusion Dark | Global Theme `org.plasmafusion.dark.desktop` |
| `plasma-fusion-light` | Plasma Fusion Light | Global Theme `org.plasmafusion.light.desktop` |

Each is a complete `Plasma/Theme` package of plain `.svg` files (no `.svgz`), `metadata.json`
(`X-Plasma-API` 5.0, licence CC-BY-SA-4.0) and `plasmarc`. It has no `colors` file: text and
control colours come from the active Fusion colour scheme, surface fills are fixed per variant.

## Files

| Path | What |
|---|---|
| `generators/plasma-style/gen_plasma_style.py` | tokens (every value names its board) and one builder per SVG file |
| `generators/plasma-style/svgkit.py` | nine-slice frame writer (analytic arcs, clipped corners), hints, masks, pre-rendered CSS box-shadows (Pillow) |
| `tools/build.d/20-plasma-style.sh` | writes `$STAGE/.local/share/plasma/desktoptheme/plasma-fusion-{dark,light}/` |
| `generators/plasma-style/tests/` | test tooling only (not installed): `validate.py`, `coverage.py`, `run-harness.sh` + `harness.qml` (offscreen KSvg/PC3 render), `make-seed.sh` + `vsession-scenario.sh` + `vsession-dock-scenario.sh` + `pstest-plasmoid/` (virtual-session screenshots), `make-integrated-seed.sh` + `vsession-integrated.sh` (all parts with the Global Theme layout), `render-test-wallpapers.py`, `sidebyside.py` |

Generated per variant (36 SVG files):

- Surfaces: `dialogs/background`, `widgets/tooltip`, `widgets/panel-background`, `widgets/background`
  in three selectors: `translucent/` (KWin blur available, design alphas), root (no blur, 0.96-0.97
  alpha), `solid/` (opaque). Plus `widgets/translucentbackground`, `widgets/plasmoidheading`.
- Controls used by Plasma Components 3 and the stock applets: `button`, `lineedit`, `viewitem`,
  `listitem`, `tabbar`, `menubaritem`, `tasks`, `scrollbar`, `slider`, `switch`, `checkmarks`,
  `radiobutton`, `actionbutton`, `frame`, `bar_meter_horizontal`, `bar_meter_vertical`,
  `busywidget`, `line`, `arrows`, `toolbar`, `pager`, and Folder View's `action-overlays`
  (selection markers and the folder pop-up button, STYLE-1).
- Not generated (Breeze fallback, as the research's tier 3): `notes`, `clock`, `timer`,
  `analog_meter`, `calendar` (the calendar applet itself uses `button` and `viewitem`, which are
  ours), `containment-controls`, `margins-highlight`, `configuration-icons`, `dragger`, `glowbar`,
  `media-delegate`, `monitor`, `picker`, `plot-background`, `scrollwidget`, `branding`,
  `weather/wind-arrows`, `dialogs/shutdowndialog`. `icons/` is unused in 6.7.5.

## Build, install, apply

```
tools/build.sh plasma-style          # or STAGE=/some/home tools/build.sh plasma-style
# per user, from the stage:
kpackagetool6 -t Plasma/Theme -i stage/home/.local/share/plasma/desktoptheme/plasma-fusion-dark    # -u to upgrade
kpackagetool6 -t Plasma/Theme -i stage/home/.local/share/plasma/desktoptheme/plasma-fusion-light
plasma-apply-desktoptheme plasma-fusion-dark      # writes ~/.config/plasmarc [Theme] name=plasma-fusion-dark
```

Copying the two folders into `~/.local/share/plasma/desktoptheme/` works as well. The build is
deterministic (two runs give identical checksums) and needs only Python 3 + Pillow. After
regenerating an installed style, restart plasmashell; if pixmaps look stale remove
`~/.cache/plasma_theme_plasma-fusion-*.kcache` and `~/.cache/ksvg-elements*`.

`plasmarc` inside the style: `[ContrastEffect] enabled=false contrast=1 intensity=1 saturation=1`
(KWin 6.7 has no contrast effect; these only feed the wallpaper blur behind desktop widgets, which
the board draws as a plain `blur(24px)`), `[BlurBehindEffect] enabled=true` (the research's name
for the group libplasma reads; "BlurEffect" in the task text means this), `[AdaptiveTransparency]
enabled=true`.

## Surfaces (values from the boards)

| Surface | Dark | Light | Shape |
|---|---|---|---|
| Top bar, `panel-background` prefix `north` | rgba(9,12,24,.58), bottom edge white .06 | rgba(250,251,255,.74), edge rgba(20,24,39,.06) | square, 1 px cells, margins t/b 4, l/r 6 |
| Dock, prefix `south` | rgba(14,18,34,.60), edge white .10 | white .72 (board .70, see STYLE-1), edge ink .10 | radius 24, 16 px transparent headroom (contract below); `--south-frame plain`: a plain bar, headroom above it (STYLE-1) |
| Vertical panels, prefixes `west`, `east` | as dock | as dock | radius 24, no headroom, margins 8 |
| Unprefixed panel frame (a panel before its edge is known, or without an edge) | as dock | as dock | radius 6 in 6 px cells, margins 8 (see the Review section) |
| Pop-ups, `dialogs/background` | rgba(22,27,46,.88), edge white .12 | white .88, edge ink .12 | radius 22, margins 14 |
| Pop-up shadow (KWin tiles) | 0 18 44 rgba(0,0,0,.45) | 0 18 44 rgba(20,24,39,.16) | clipped inside the shape |
| Plasma tooltips, `widgets/tooltip` | rgba(22,27,46,.90), edge white .12 | white .90, edge ink .12 | radius 16, margins 6 (+ DefaultToolTip's 8 = the board's 14), shadow 0 18 44 (Popups rich tooltip) |
| PC3 ToolTip, `solid/widgets/tooltip` | #0c0f1c, edge white .12 | #1b2031, no edge | radius 8, own `shadow` frame |
| Desktop widget cards, `widgets/background` `blurred-*` | rgba(14,18,34,.52), edge white .10 | white .62, edge ink .10 | radius 18, margins 14, `blurred-mask-*` for the wallpaper blur |
| PC3 Menu/Popup, widgets without blur (unprefixed `widgets/background`) | rgba(22,27,46,.96) | white .96 | radius 18 |

("ink" = rgb(20,24,39), the light boards' tint colour.) Blur masks (`mask-*`) follow each shape;
their corner radius is 3 px larger so KWin's 1-bit blur region stays inside the anti-aliased edge
(no blurred staircase outside the corner). `widgets/plasmoidheading` is transparent (one flat
frosted surface, as on the Popups board); the footer keeps a 1 px .08 hairline 16 px in from the
sides. Both headings exist in the same theme as `dialogs/background`, so they are shown.

Extra prefixes in `dialogs/background` for shell pieces that draw their own surface with
`KSvg.FrameSvgItem { imagePath: "dialogs/background"; prefix: "…" }` (each has `mask-<prefix>-*`):

| Prefix | Radius | Fill (translucent) | Margins t,b,l,r | Board |
|---|---|---|---|---|
| `launcher` | 26 | .86 | 18,18,18,18 | Launcher |
| `osd` | 30 | .88 | 14,14,20,20 | Popups OSD pill |
| `notification` | 18 | .90 | 14,14,14,14 | Popups notification card |

## Shared contract with the dock (org.plasmafusion.dock)

Implemented as specified. Panel geometry the layout must use: location bottom, floating, lengthMode
fit, alignment center, thickness (height) 88, hiding dodgewindows, opacity translucent.

- `south` frame, drawn over the full 88 px: rows 0-16 are fully transparent, the frosted dock is
  rows 16-88 (radius 24, 1 px edge). `mask-south-*` (blur/contrast region) has the same transparent
  headroom, so nothing is blurred there (checked: the wallpaper edge stays sharp above the dock).
  The same holds for the non-floating state and for `solid/` (opaque/adaptive).
- `floating-hint-*-margin` top 0, bottom 16, left 8, right 8: the panel window is 88 + 16 px tall
  and the visible dock sits 16 px above the screen edge (as on the board).
- Content margins (`south-hint-*-margin`): top 26 (16 headroom + 10 board padding), bottom 14,
  left/right 8. The panel containment adds 4 px row spacing on the sides, giving the board's 12.
  An applet without `CanFillArea` therefore gets rows 26-74: a 48 px row, the board's buttons.
  An applet with `Plasmoid.constraintHints: Plasmoid.CanFillArea` (the containment then gives it
  no top/bottom margins) gets all 88 rows and can grow icons into the headroom; its visible dock
  starts at y 16 of its own height.
- Dock shadow 0 18 44 at .35 (light rgba(20,24,39,.14)) is a KWin window shadow computed for the
  72 px dock, not for the panel window: `shadow-hint-top-margin` is 21 (37 - 16 headroom).
  PanelShadows is one shadow set for all panels and the full-width top bar only ever receives the
  `shadow-bottom` tile, so that tile is transparent and the dock's bottom shadow is carried by two
  1335 px wide bottom corner tiles that KWin splits in the middle. Result: the dock has its full
  shadow, the top bar has none (as on the board). Limits: a dock wider than about 2560 px shows a
  gap in the middle of its bottom shadow; a panel that is not full width at the top would get the
  dock's corner shadows.
- `south-active-tab` (expanded applet indicator in the dock) is a 4 px accent line with 5 px below
  it, 14 px in from both sides: the running-indicator row of the board.
- Task manager in the dock: stock `icontasks` declares `CanFillArea`, so it gets all 88 rows, and
  its slots are panel height + frame margins wide (`LayoutMetrics.preferredMaxWidth`). The
  `south-` frames of `widgets/tasks` (used only on bottom panels) are therefore dock-aware: margins
  26/14/4/4 put a 48 px icon on the button row (rows 26-74) of a 96 px slot, the hover/active tint
  is the board's 48 px radius-13 square, and the running bar sits 6 px above the dock's bottom edge
  (6 px wide, 16 px and ButtonFocus colour for the active window; attention in NeutralText).
  Checked with Dolphin (active) and Konsole (running), `side-by-side/dock-running.png`. Only the
  pitch differs from the board: 96 px slots instead of 56 (48 + 8 gap); the Fusion dock plasmoid
  sets its own spacing. `north-`, `west-`, `east-` and unprefixed task frames are ordinary
  (4 px margins, bar towards the screen edge). Hovered states `<state>-hover` and
  `launcher-hover` exist so pinned launchers get a tint without a running bar.

## Top bar

Configure: location top, height 34, lengthMode fill, floating false, hiding none, opacity
translucent (adaptive also works: `solid/` north is the opaque bar). The containment caps side
padding at (34 - 22) / 2 = 6 px, so the top-bar plasmoids add 4 px themselves to reach the board's
10. Applets get a 26 px row (margins 4/4). An expanded stock applet shows `north-active-tab`, a
3 px accent line along the bottom edge of the bar.

For pop-ups that float 8 px below the bar with all corners rounded (Main/QuickSettings boards), set
`floatingApplets=1` on the top panel: `plasmashellrc [PlasmaViews][Panel <id>] floatingApplets=1`.
Without it Plasma attaches pop-ups to the bar and squares the touching corners (verified both).

## Controls in pop-ups (Plasma Components 3)

Controls board: 10 px corners, accent fill, 2 px focus ring with a 2 px gap. Colours come from the
colour scheme so accent changes follow: `ColorScheme-Highlight` (accent #2F6FDF), `ColorScheme-
ButtonFocus` (focus ring: #8ab8ff dark, #2f6fdf light), `ColorScheme-Text` at low alpha (neutral
tints, as the Popups board's rgba(255,255,255,.1) buttons), `ColorScheme-HighlightedText` (check).

- Buttons: neutral fill (text .10, both variants: Popups boards rgba(255,255,255,.1) / rgba(20,24,39,.1)), pressed/checked accent .30/.20, hover +.06 and a
  1 px edge, focus ring; flat tool buttons radius 8 (hover .10, checked accent .24/.16).
- Text fields: faint fill, 1 px edge, hover stronger edge, focus 1.5 px accent border + 3 px soft
  accent halo (Controls "Search" field).
- List highlight / current item (`viewitem`): accent .20 / selected .30 / selected+hover .38,
  radius 8 (Controls menu "Copy" row). `listitem`: text-tint hover, accent pressed.
- Switch 40x22 pill, white 18 px knob; slider 6 px groove, white 20 px handle; progress 6 px;
  checkbox accent square with white check; radio 16 px; scrollbar 5 px thumb in 8 px; tabs with a
  3 px accent underline; menubar items radius 6, padding 4/8 (top-bar menu board).

## Verification

- Offline: `tests/validate.py` (XML, QtSvg load, nine cells per prefix with consistent sizes,
  required elements, metadata) passes for both variants; `tests/coverage.py` lists what Breeze has
  beyond ours (only unused hints and Breeze-internal ids remain); `tests/run-harness.sh` renders
  the surfaces and PC3 controls offscreen (`offscreen/harness-{dark,light}.png`).
- Virtual sessions on the ThinkPad (`tools/vsession/remote.sh ps-N …`, private HOME and D-Bus):
  install with kpackagetool6, apply with plasma-apply-colorscheme / plasma-apply-desktoptheme, top
  bar + dock + desktop widgets built by desktop scripting, then the test pop-up, system tray,
  calendar, a notify-send notification, a rich tooltip, a dock tooltip and the volume OSD, in dark
  and light (runs ps-1 … ps-6), at scale 4/3 on a 1920x1200 output (ps-7), and the dock with
  running windows (ps-8).
- Colour check against the boards (same pixel positions): dock light (201,217,253) vs board
  (200,215,250); dock dark (38,62,120) vs (37,58,114); top bar dark (13,18,37) vs (12,17,36), light
  (242,245,254) vs (241,246,252); pop-up dark (22,28,50) vs (21,26,46), light (251,252,255) vs
  (250,251,253). Stock OSD is 60 px tall like the board pill.
- plasmashell log (stderr) with the style: no warnings from the style, only the stock messages that
  a Breeze baseline run (ps-4) prints too. An earlier build without `hint-*-inset` in `dialogs/background` caused
  "PlasmoidHeading: Binding loop detected for property leftInset" in the network and Bluetooth
  pop-ups; fixed (zero insets, as Breeze has).
- Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/plasma-style/`
  (`screenshots/`, `side-by-side/` board vs build, `scale-4-3/`, `offscreen/`, `logs/`).

Re-run: `STAGE=$S tools/build.sh plasma-style && generators/plasma-style/tests/make-seed.sh $S/home
$SEED && tools/vsession/remote.sh ps-9 generators/plasma-style/tests/vsession-scenario.sh $SEED`.

## Known deviations from the boards

- One pop-up radius: every stock shell pop-up (tray panels, calendar, notifications, OSD, KRunner,
  stock Alt+Tab) uses `dialogs/background`, so all get 22 px. Boards: notifications 18, OSD pill 30,
  launcher 26. Custom shell pieces can use the `notification`, `osd`, `launcher` prefixes. A
  PlasmaCore.Dialog with `NoBackground` (needed to draw such a prefix itself) loses KWin blur in
  6.7.5, so a custom launcher either keeps the stock 22 px frame with blur or draws its own frame
  without KWin blur.
- Plasma tooltips (`widgets/tooltip`: ToolTipArea, DefaultToolTip, task-manager tooltips) are the
  Popups board's rich tooltip (radius 16, pop-up fill .90, light in the light variant) also when
  they hold a single line: DefaultToolTip always adds 8 px of its own padding and uses the Window
  colour set (dark text in Fusion Light), so the board's small dark label (radius 9, padding 6/11,
  dark in both variants) cannot be drawn by it. The small label style is used where the Tooltip
  colour set applies (PC3 ToolTip, `solid/widgets/tooltip`); the dock draws its own name pill. Dark variant:
  #0c0f1c with light text everywhere, as on the boards.
- Unchecked PC3 checkbox is round: CheckIndicator draws the button frame at 16x16, so button corner
  cells are 8 px (the 10 px arc is clipped to the cell, invisible on real buttons). Larger cells
  overlap at 16 px and drew a broken cross. PC3 checkboxes are practically unused in shell pop-ups.
- Blur strength and saturation are global KWin settings (see below), not per surface
  (board: top bar 24 px, dock 28, pop-ups 36, launcher 40). The rounded blur region is 1-bit.
- Tooltip, widget and pop-up shadows are close CSS equivalents (pre-rendered Gaussian tiles). The
  pop-up shadow tiles are cleared inside a 26 px corner (the `launcher` prefix, which the Fusion
  launcher and window switcher switch their Dialog frame to), so those corners keep their shadow.
- Panel thickness minimums (the minimum drawing size of the frame PanelView clamps to): bottom
  panels 64 px (16 px headroom + two 24 px corners; the dock is 88), vertical panels 48 px, top
  panels 2 px. A bottom panel thinner than 64 px is raised to 64 on the next plasmashell start.
- Stock icontasks in the 88 px dock: 96 px slot pitch instead of the board's 56 (see the contract).

## Needed from other parts

- Global Themes (look-and-feel) / `tools/device/fusion-config.sh`: `plasmarc [Theme]
  name=plasma-fusion-dark` / `-light`; panels as above (top 34 fill non-floating; dock bottom 88
  floating fit center dodgewindows); `kwinrc [Effect-blur]` (fusion-config.sh sets BlurStrength 13,
  NoiseStrength 0, Saturation 140; the style was tuned at 12) and `plasmarc [PlasmaToolTips]
  Delay=600` are in place. **Still missing (checked 2026-09-29 in the integrated session):** top
  panel `plasmashellrc [PlasmaViews][Panel <top id>] floatingApplets=1`. Desktop scripting has no
  property for it, so fusion-config.sh has to write it with kwriteconfig6 before its plasmashell
  restart. Without it every stock pop-up of the top bar (system tray, its applets) is attached to
  the bar with square top corners instead of floating 8 px below it with 22 px corners
  (`review-tray-floatingapplets.png`).
- Colour schemes: keep `[Colors:Tooltip]` BackgroundNormal 12,15,28 (dark) / 27,32,49 (light) with
  light ForegroundNormal, `[Colors:Selection]` BackgroundNormal 47,111,223 and DecorationFocus
  138,184,255 (dark) / 47,111,223 (light): the style's controls and inverted tooltips rely on them.
  Tests used the research drafts because the colours part was not in the stage yet.
- Dock plasmoid: use `CanFillArea` to own the full 88 px (visible dock = rows 16-88), or rely on the
  26/14 margins for a 48 px row; draw running indicators itself (the board's 5 px / 16 px bars).
- Launcher, quick settings, OSD, notification list: optional prefixes listed above.

## Review (2026-09-29)

An adversarial review of this part: board values re-read (Main, MainLight, Popups, PopupsLight,
QuickSettings, Launcher, Controls), generator and output inspected element by element, and the
style run together with every other part.

### What was checked

- Build: `STAGE=<dir> tools/build.sh` with all parts (the tmpfs scratch quota was full, so the
  stage lived in the git-ignored `build/rps/`); `tools/build.sh plasma-style` twice gives identical
  checksums; `tests/validate.py` (0 errors), `tests/coverage.py`, `tests/run-harness.sh` offscreen
  in both variants; `bash -n` / shellcheck on the scripts; metadata (Id, Name, Authors, License
  CC-BY-SA-4.0, `X-Plasma-API` 5.0) and `plasmarc`.
- Contracts read in the 6.7.5 sources: Panel.qml and PanelView (thickness clamp, floating
  paddings, focus indicator, shadows), panel containment margins, DefaultToolTip, PC3 button /
  checkbox / tooltip, KSvg FrameSvgItem fast path, notification popup, calendar day highlight.
- Integrated virtual sessions on the ThinkPad (`rps-1` … `rps-5`): seed from
  `tests/make-integrated-seed.sh` (all parts), scenario `tests/vsession-integrated.sh`, which runs
  `tools/device/fusion-config.sh` (Global Theme with layout: Fusion top bar plasmoids, dock
  plasmoid, launcher, desktop cards), restarts plasmashell, then opens the system tray, quick
  settings, clock pop-up, a pop-up of PC3 controls, a notification, the volume OSD, KRunner, the
  Fusion launcher and a rich tooltip, in dark and light. Logs: no message from the style in
  plasmashell or KWin (only stock kdeconnect/PipeWire/systemmonitor messages).
- Dock contract re-checked with the real dock plasmoid: 72 px frosted dock under a transparent,
  unblurred 16 px band, board fill within 1-2 levels, shadow and 16 px gap as on the board.

### Fixed

- **Top bar came back 48 px tall after every plasmashell start (high).** PanelView clamps the
  thickness to `minPanelHeight` when the panel QML becomes ready, before Panel.qml has set the
  edge prefix, so the unprefixed frame's corner cells (24 + 24 px) applied to the 34 px top bar
  and the clamped value was saved. After the layout script the bar was 34, after any restart 48
  (`rps-2`: 48 after each of 4 restarts). The unprefixed frame now has 6 px cells (radius 6,
  margins still 8) and vertical panels get their own `west`/`east` frames (the dock look, radius
  24). After the fix: 34 px after 4 restarts (`rps-4`), `review-topbar-thickness.png`.
  `tests/validate.py` now fails if the unprefixed panel frame needs more than 16 px.
- **Plasma tooltips did not follow the board (medium).** `widgets/tooltip` used the small label
  style (radius 8, dark .94 in dark, white .94 in light) although everything drawn through it
  (DefaultToolTip: icon, title, subtitle; task-manager tooltips) is the Popups board's rich
  tooltip. Now: radius 16, pop-up fill .90 (dark rgba(22,27,46,.9) / light white .9), 1 px .12
  edge, margins 6 + DefaultToolTip's 8 = the board's 14 px padding, shadow 0 18 44 (.45 / ink
  .16). The light variant therefore matches the board instead of deviating from it
  (`review-tooltip-sbs.png`). PC3 ToolTip (`solid/widgets/tooltip`) keeps the small label style.
- **Shadow notch at the corners of 26 px frames (low).** The pop-up shadow tiles were cleared
  inside a 22 px corner, so the Fusion launcher and window switcher (both switch their Dialog frame
  to the `launcher` prefix, radius 26) had a thin crescent without shadow at each corner. The
  tiles are now cleared inside a 26 px corner (`svgkit.window_shadow(clear_r=…)`).
- **Light buttons were fainter than the board (low).** Neutral button fill in the light variant
  was ink .08; the PopupsLight buttons are rgba(20,24,39,.10). Now .10 in both variants.
- Test tooling: `validate.py` could report a present element as missing or pass a missing one
  (a stale `ok` flag); fixed. New self-contained integrated seed and scenario.

### Remains (not fixable in the style, or another part's)

- Top-bar pop-ups float only with `floatingApplets=1` on the top panel, which the layout /
  fusion-config.sh do not set yet (see "Needed from other parts"). The final screenshots set it in
  the test scenario to show the intended look; `review-tray-floatingapplets.png` shows both.
- One radius for all stock pop-ups (22), stock OSD not a pill, round unchecked PC3 checkbox,
  global blur strength, 96 px slots for stock icontasks: unchanged, see "Known deviations".
- Bottom panels are at least 64 px and vertical panels at least 48 px with this style (frame
  minimum drawing size; the dock is 88).

### Evidence

`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/plasma-style/`:
`review-dark-sheet.png`, `review-light-sheet.png` (all ten screenshots per variant),
`review-{dark,light}-{01-desktop,02-tray,07-tooltip,10-launcher}.png`, `review-topbar-thickness.png`,
`review-tooltip-sbs.png`, `review-tray-floatingapplets.png`, logs in `logs/review/`.

Re-run from the repository root (results land in the git-ignored `vsession-out/`):
`STAGE=$S tools/build.sh && generators/plasma-style/tests/make-integrated-seed.sh $S $SEED &&
tools/vsession/remote.sh rps-N generators/plasma-style/tests/vsession-integrated.sh $SEED 1440x900 270`;
`touch $SEED/pf-tools/floating-applets` before the run sets `floatingApplets=1`.


## Polish (2026-09-29)

See `docs/parts/polish.md`. Changes in `gen_plasma_style.py`:

- `widgets/menubaritem`: every frame has 4 px of transparent space above and below the pill and
  1 px at each side, margins (4, 4, 9, 9): the stock global menu's pill is 26 px tall in the 34 px
  bar (y 4..29, as on the board) with 2 px between titles. Light variant: hover and open pills are
  the accent (`ColorScheme-Highlight`) darkened with ink .10 / .18, because the appmenu draws the
  title in the Selection foreground (white); white on it is 5.4:1 / 6.0:1 (was 1.3:1 on the grey
  pill). Dark variant unchanged (white on white .10 / .14).
- `dialogs/background`: new prefix `snaplayouts` (radius 16, fill .90, edge .14, margins 12,
  `mask-snaplayouts-*`), the QuickSettings board's Meta+Z flyout; plasmafusion-snap uses it.
- The top bar's `floatingApplets=1` is now written by the layout script and `fusion-config.sh`
  (the "Still missing" note under "Needed from other parts" is resolved).

## STYLE-1 (2026-09-30)

Work package STYLE-1 of the one-pass build plan. Changes in `gen_plasma_style.py`,
`tests/validate.py`, `tools/build.d/20-plasma-style.sh`; new test tooling in `tests/`.

### Panel frame switches (ADAPTIVE fix 12, TABLET corners)

Both switches default to the frames deployed since round 2, so a build without them is the
deployed look (element-identical to HEAD: same ids, sizes and pixels for every element; the only
addition is the `south-hint-*-inset` hints below). The lead flips them in INT-1, in the same commit
as the dock, top-bar and quick-settings padding.

| Build switch (`tools/build.d/20-plasma-style.sh`) | Generator option | Default | Flipped |
|---|---|---|---|
| `PF_SOUTH_FRAME=headroom\|plain` | `--south-frame` | `headroom` | `plain` |
| `PF_NORTH_SIDE_MARGIN=6\|0` | `--north-side-margin` | `6` | `0` |

**`--south-frame plain`.** Today the `south` frame carries the dock contract: 16 px transparent,
unblurred headroom inside an 88 px panel and 26/14 content margins, so every bottom panel gets it: a
44 px bottom panel that a user adds is raised to 64 px on the next shell start (the frame's minimum
drawing size) and its applets get 24 px rows (measured, `o1st-b1`). The plain frame is the dock look
without headroom: radius 24 drawn in 22 px corner cells (minimum drawing size 44 px; the 24 px arc
clipped to a 22 px cell is 0.08 px off the straight edge), content margins 4/4/8/8 (t/b/l/r: a 44 px
panel gives its applets 36 px rows), `south-hint-*-inset` 0, mask and shadow of the frame itself.

The headroom moves out of the frame into the panel window: `floating-hint-top-margin` becomes 16
(bottom 16, left/right 8 unchanged). Panel.qml places a floating panel's frame that far below the
window top, so the dock window stays 16 + 72 + 16 = 104 px tall with the plate in the same place;
the 16 px above the plate are outside the frame's mask, so they are not blurred and, because
PanelView cuts the input region at the mask's top edge, not clickable (both as today). The panel's
thickness is now the plate: the dock panel is 72 px instead of 88. The dock applet (CanFillArea)
gets the plate's 72 rows; magnified icons are drawn above its top edge (negative y) into the window's
top 16 px, which no ancestor clips. KWin's shadow is unchanged (PanelShadows subtracts the floating
padding from the frame's shadow margins: 37 − 16 = 21 px above the window, as the headroom frame's
21). A floating panel on any edge gets the 16 px top margin (a floating top panel sits 16 px below the
screen edge); the Fusion top bar is not floating. Stock task managers on a bottom panel use the
ordinary bottom frames (the dock-aware `south-*` task frames are dropped with the plain frame).

Why not "the dock draws the headroom in QML" with a transparent panel: in 6.7.5 the panel
containment's background cannot be switched off per panel (Panel.qml tests the containment's own
`backgroundHints`, which org.kde.panel does not make configurable), and with no background PanelView
turns KWin blur off for the whole panel (`panelview.cpp:1450`) and the input region covers the whole
window. Switching the dock's frame prefix from QML would work but reaches into Panel.qml's private
items. The floating top margin is a documented theme hint and needs no private access.

**`--north-side-margin 0`.** The panel containment insets its applets by
`min(floor((T − 22) / 2), frame.fixedMargins.left + 4)` at each screen edge
(`containments/panel/main.qml:386-387`; T = bar thickness, 4 = Kirigami smallSpacing). With side
margins 6 that is 6 px at T = 34 and 10 px at T = 44 (tablet); with 0 it is 4 px at any T ≥ 30. The
containment's 4 px row spacing cannot be removed by the style; edge plasmoids reach the screen
corner by extending their hit area 4 px outwards (an item outside its parent's bounds still gets
pointer events when nothing clips). Measured (`o1st-b1`, 1920x1200 at 4/3): the leftmost and
rightmost top-bar content moves 2 px towards the screen edges; nothing else in the bar changes.

### Action overlays (BACKLOG S6)

`widgets/action-overlays` with the nine elements Folder View's `FolderItemActionButton` asks for:
`add`, `remove`, `open` × `normal`, `hover`, `pressed`, each 16 x 16 (drawn at smallMedium, 22 px, for
48 px desktop icons). A 16 px accent disc (`ColorScheme-Highlight`) with a white glyph
(`ColorScheme-HighlightedText`: plus, minus, a chevron) and a 1 px white rim that separates it from
the icon under it; hover lightens the disc with white .18, pressed darkens it with the light boards'
ink .22. The selection markers show on hover when the desktop uses single-click activation; the
`open` button only in Folder View pop-ups (`popups=true`). Screenshots of every state, dark and light,
over the Dusk Ridge wallpapers: `screens/desktop-states-{dark,light}-1to1.png` (1:1 device pixels at
4/3; hover, marker hover, marker pressed, selected+hover with the remove marker, selected,
the link emblem, the drag-selection band and the band's result).

### viewitem review over the wallpapers (BACKLOG S6)

The desktop's hover, selected and selected+hover highlights are the Plasma style's `viewitem`
(accent .20 / .30 / .38, radius 8; Folder View draws it at 60 % while the desktop window is not
active). Reviewed in private sessions over the Dusk Ridge dark and light pictures: every state is
visible and distinct on both; the stock drag-selection band (accent border, 30 % fill, radius 5) and
the moving-card placeholder need nothing from the style. Kept as it is, because the same element
is the list highlight in every pop-up (Controls board "Copy" row).

Not fixable in the style: Folder View draws desktop labels white with a black drop shadow
(`FolderItemDelegate.qml:357-370`, `PlasmaExtras.ShadowedLabel`), whatever the colour scheme. On the
light Dusk Ridge sky the white glyphs have 1.1-1.3:1 against the bare wallpaper; the shadow halo is
what makes them readable (brightest glyph pixel against the darkest 5 % of the label, the shadow
core: 4.5-5.6:1; `tests/label_contrast.py`). On the dark picture white has 15-17:1. The subpixel
colour fringes in the same screenshots go away with DEVICE-1's greyscale antialiasing (D9). A
dark-label-on-light variant needs a Folder View fork or an upstream option.

### Accent colour (decision 3)

Every accent-coloured element of the style takes its colour from the colour scheme
(`ColorScheme-Highlight`, `ColorScheme-ButtonFocus`, and `ColorScheme-HighlightedText` on accent
fills); the generated files contain no fixed accent value outside the `current-color-scheme`
stylesheet (checked with a grep of both packages for #2f6fdf and #8ab8ff).
