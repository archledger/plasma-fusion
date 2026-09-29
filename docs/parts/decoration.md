# Window decoration: Aurorae v2 themes PlasmaFusionDark / Light (+ -Left)

Status: built and checked in private virtual sessions on the ThinkPad (1440x900 at scale 1, and
1920x1200 at scale 4/3), dark and light, with Dolphin, System Settings and a kdialog; reviewed and
re-checked integrated with every other part and the Global Theme applied (see "Review" at the
end). Phase 1 (no compiled code). Last edited 2026-09-29.

## What it is

Four Aurorae SVG themes, served by KWin 6.7's C++ Aurorae renderer (`org.kde.kwin.aurorae.v2`):

| Theme directory | Name in System Settings | Layout |
|---|---|---|
| `PlasmaFusionDark` | Plasma Fusion Dark | app icon left, title left, 28 px round buttons right |
| `PlasmaFusionLight` | Plasma Fusion Light | same, light colours |
| `PlasmaFusionDark-Left` | Plasma Fusion Dark (buttons on the left) | 13 px circles left, title centred |
| `PlasmaFusionLight-Left` | Plasma Fusion Light (buttons on the left) | same, light colours |

Each directory holds `metadata.desktop`, `<Theme>rc`, `decoration.svg` and the button SVGs
`minimize`, `maximize`, `restore`, `close`, `keepabove`, `keepbelow`, `alldesktops`, `shade`,
`help`, `appmenu`. There is deliberately no `menu.svg`: Aurorae then paints the window's own icon
in the menu slot, which is the board's "App icon". Licence CC-BY-SA-4.0 (artwork); the generator
is GPL-2.0-or-later.

## Files

| Path | What |
|---|---|
| `generators/decoration/gen_aurorae.py` | the generator (stdlib + Pillow); every token names its board line |
| `tools/build.d/50-decoration.sh` | writes `$STAGE/.local/share/aurorae/themes/PlasmaFusion{Dark,Light}{,-Left}/` |
| `generators/decoration/tests/` | test tooling only, not installed (see Verification and Review): `check_aurorae.py`, `preview.py`, `make-seed.sh` + `scenario.sh` / `scenario-edge.sh` (+ `steps.qml.in`, `pointer.py`), `make-review-seed.sh` + `scenario-review.sh` (integrated, all parts) |

Two builds give byte-identical files (checked with `diff -r`).

## How it is drawn (and why it looks like the board)

Aurorae v2 resizes the `decoration` frame to the window size plus `[Layout] Padding*`, paints it
at -padding, shows the part inside the window's border rect as the decoration and turns the part
outside into the window shadow (KDecoration3 `DecorationShadow`). The generated frame therefore
contains everything the board's CSS draws around a window:

- Shadow: pre-rendered PNG slices (Pillow Gaussian blur, sigma = CSS blur / 2) of the window shape.
  Active `0 34px 90px` at 55 % black, inactive `0 24px 60px` at 35 % (Windows.dc.html spec 6); light:
  `rgba(20,24,39,0.22)` / `0.14` (MainLight.dc.html:138 / :76). Padding 90 / 56 / 90 / 124 px
  (left, top, right, bottom). Measured against the board render below a window: within 1-3 % alpha.
- 1 px edge just outside the window: the board's border colour over the window background, so it
  is opaque like the CSS border: dark `rgba(255,255,255,0.14)` over `#1b2031` (active) and 0.08
  over `#1a1f2e` (inactive); light `rgba(20,24,39,0.14)` / `0.08` over `#ffffff`.
- Title bar 50 px (`TitleEdgeTop 8` + 34 + `TitleEdgeBottom 8`), 40 px maximized (3 + 34 + 3).
  Colours from Colors.dc.html: dark `#222840` active / `#1f2536` inactive, light `#eceff6` /
  `#f1f3f8`. Top corners 14 px outside the edge (13 px inside it); maximized: square, no edge, no
  shadow (Aurorae drops both). Title text colour: dark `#e8ebf4` / `#8891aa`, light `#141827` /
  `#646b80` (`ActiveTextColor`, `InactiveTextColor`).
- Buttons (right layout): 34 px boxes that touch (`ButtonSpacing 0`), each holding the 28 px circle
  and room for the 3 px hover ring, so circles are 6 px apart and 10 px from the right edge
  (`TitleEdgeRight 7`). App icon 26 px at 16 px (`TitleEdgeLeft 16`, `ButtonWidthMenu 26`), title
  10 px after it (`TitleBorderLeft 10`). Glyphs are the board's symbolic paths (13 px, stroke 1.8
  in the 24 grid), with their top-left corner at (11, 10) in the 34 px box: the glyph centre sits
  at title-bar y 24.5 like the board raster, so the minimize dash is one crisp pixel row at scale 1
  (it was spread over two half-bright rows before the review). States (element prefixes):
  `active` white 10 % / ink 10 % with the text-colour
  glyph, close `#d9434b` with a white glyph; `inactive` 7 % with a muted glyph (`#a3abc2` /
  `#5b6278`), close neutral too; `hover` accent disc + white glyph + 3 px accent ring (close: red
  disc + red ring); `pressed` the hover look darkened by 20 % black; `deactivated` 5 % / 4 % with a
  30 % glyph. `hover-inactive` / `pressed-inactive` equal hover / pressed.
- Accent: hover fill and ring use `class="ColorScheme-Highlight"` with a `current-color-scheme`
  stylesheet (default `#2f6fdf`). KSvg replaces it with the colour scheme's Selection background,
  so the hover follows the accent colour. Verified live: after changing `[Colors:Selection]
  BackgroundNormal` to teal and sending `KGlobalSettings.notifyChange` + KWin reconfigure, the hover
  turned teal. The ring is white 8 % under the accent at 35 % (dark) / accent 25 % (light), which
  reproduces the board's `rgba(91,157,255,0.3)` within a few levels.
- Left layout (Windows.dc.html:116-125): 20 px boxes 8 px from the left put 13 px circles at 12,
  32 and 52 px (7 px apart), centred at title-bar y 24.5 on whole pixels (`ButtonMarginTop 7`,
  circle centre 10.5, 9.5 in the box; 9 px glyph at 6, 5). Plain dots at rest (`#8891aa`
  dark as on the board, `#9aa0b2` light, 40-45 % on inactive windows); `ButtonGroupHover=true`, so
  hovering any dot shows all three in colour with glyphs (close red, the others accent), like
  traffic lights. Title centred (`TitleAlignment=Center`); `ExplicitButtonSpacer=60` lets
  `ButtonsOnRight=_` balance the left group so the title is centred on the whole window.
- Extra buttons (keep above/below, on all desktops, shade, help, application menu) exist in the
  same style so a user-chosen button layout keeps working; KDecoration3 hides the ones that do not
  apply (for example "on all desktops" with one desktop, help without context help).

## Installing and applying

Built into the staged HOME by `tools/build.sh` (part `decoration`); per user it lands in
`~/.local/share/aurorae/themes/`. No package tool is needed (Aurorae scans that folder; each theme
needs its `metadata.desktop`).

kwinrc `[org.kde.kdecoration2]`:

| Key | Right layout (default) | Left layout ("Left · circles") |
|---|---|---|
| `library` | `org.kde.kwin.aurorae.v2` | same |
| `theme` | `__aurorae__svg__PlasmaFusionDark` (or `...Light`) | `__aurorae__svg__PlasmaFusionDark-Left` (or `...Light-Left`) |
| `BorderSize` | `None` | `None` |
| `BorderSizeAuto` | `false` (required, see below) | `false` |
| `ButtonsOnLeft` | `M` | `XIA` |
| `ButtonsOnRight` | `IAX` | `_` |

Then `qdbus6 org.kde.KWin /KWin reconfigure` (or `/usr/libexec/kwin-applywindowdecoration
__aurorae__svg__PlasmaFusionDark`). The Global Themes (lookandfeel part) already name the theme,
`BorderSize=None` and M / IAX; `tools/device/fusion-config.sh` sets `BorderSizeAuto=false`.
KWin also rewrites `library=org.kde.kwin.aurorae` to `.v2` for `__aurorae__svg__` themes.

The title font is the system window-title font, kdeglobals `[WM] activeFont` =
`Manrope,10.5,-1,5,800,0,0,0,0,0,0,0,0,0,0,1,,0,0` (14 px ExtraBold at 96 dpi), set by the Global
Themes; Manrope must be installed.

## Verification

- Offline: `python3 generators/decoration/tests/check_aurorae.py <themes dir>` (PySide6 QtSvg):
  every SVG loads, every frame / button element Aurorae v2 looks up exists, slice sizes agree,
  button states equal the button box, 50 / 40 px title bars. Result: 4 themes, 0 errors.
  `tests/preview.py` re-implements the FrameSvg nine-slice and draws the Anatomy window next to
  the board render (`offline-anatomy-sbs-dark.png`).
- Virtual sessions on the ThinkPad (prefix dc-, all with the Plasma style, icons and the draft
  Fusion colour schemes; logs free of Aurorae / KSvg warnings):

  ```
  W=<work dir>   # results land in $W/vsession-out/
  generators/decoration/tests/make-seed.sh $W/seed-dark dark [COLORS_DIR]
  (cd $W && tools/vsession/remote.sh dc-10 generators/decoration/tests/scenario.sh $W/seed-dark 1440x900 240)
  SCALE=1.3333333 generators/decoration/tests/make-seed.sh $W/seed-dark-s dark [COLORS_DIR]
  (cd $W && tools/vsession/remote.sh dc-9 generators/decoration/tests/scenario.sh $W/seed-dark-s 1920x1200 240)
  (cd $W && tools/vsession/remote.sh dc-8 generators/decoration/tests/scenario-edge.sh $W/seed-dark 1440x900 150)
  ```

  `scenario.sh` places Dolphin and System Settings at the Main board positions with a
  declarative KWin script (`steps.qml.in`, advanced by a script shortcut through kglobalaccel),
  moves and clicks the pointer with `pointer.py` (KWin's `org.kde.KWin.EIS.RemoteDesktop.connectToEIS`
  + libei; the pointer of a virtual session does not move otherwise), and shoots: two windows,
  maximize hovered, close hovered, minimize pressed, maximized, inactive, the -Left theme plain /
  hovered / maximized, and the hover after an accent change. `scenario-edge.sh`: small dialog,
  a 140x110 window, `BorderSizeAuto=true`.
- Board comparison (pixels at the board positions): title-bar colours, button fills and close red
  within 1-2 levels of `desktop-dark-1` / `desktop-light-1`; icon, title, circle positions within
  1 px (the board render has half-pixel offsets).

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/decoration/`
(`sbs-{dark,light}-desktop.png`, `sbs-{dark,light}-titlebars-2x.png` board above / ours below,
`states-3x-dark-left-light-right.png`, `{dark,light}-*.png` full screenshots,
`dark-desktop-scale-4-3-1920x1200.png`, `dark-edge-*.png`, `offline-anatomy-*.png`).

## Deviations from the board (with reasons)

- Bottom corners are square and the client is not clipped: Aurorae v2 never calls
  `setBorderRadius`, so KWin does not round the window. The 14 px bottom radius needs the phase 3
  C++ decoration.
- No transitions: Aurorae v2 swaps hover / press frames instantly (`Animation` is ignored).
- The app icon does not fade to 60 % on inactive windows (Aurorae paints the icon as is). The
  title uses the Colors board's inactive colour (`#8891aa` / `#646b80`).
- No 32 px tool-window bar: KDecoration3 does not expose the window type.
- No separator line under the title bar in the decoration: Breeze draws the app's tool area in the
  Header colour and the separator below it (and a top separator in dialogs), so title bar and
  toolbar read as one block with the line under the block, which is closer to the Main board's
  unified header than a line between title bar and toolbar. Maximized title bars could not draw
  one anyway (Aurorae stretches one element over the whole maximized window).
- "Maximize · hold for snap layouts" tooltip and the hover-hold trigger: KWin shows its own
  "Maximize" tooltip; hover-hold needs the C++ decoration (Meta+Z stays the trigger).
- Resize area: KWin/Aurorae use `largeSpacing` of the title font (about 10-12 px) on all sides
  instead of 8 px, and KDecoration's own corner size.
- "Show on hover" button mode is not possible in Aurorae.
- Windows smaller than 140 x 150 px: the frame corners overlap and the top edge / shadow near the
  corners is slightly off (tested with a 140x110 window: readable, minor edge artefact).
- With `BorderSizeAuto=true` (KWin's default) Aurorae gives 4 px side and bottom borders; they are
  drawn in the title colour (tested), so the window gets a thin frame. Set `BorderSizeAuto=false`.
- Hover colours follow the accent only after KSvg reloads the colour scheme: the Colours page sends
  the needed notification; a hand edit of kdeglobals needs `KGlobalSettings.notifyChange` and a
  KWin reconfigure.
- Title-bar colours are fixed per theme (they do not follow "Apply accent colour to title bar").
- Tiled windows keep both top corners rounded and their shadow (the board squares the inner
  corners of tiled halves): Aurorae v2 only distinguishes maximized windows. Phase 3.
- Stale shadow after a resize without a focus change (upstream Aurorae v2, KWin 6.7.5): Aurorae
  rebuilds the `DecorationShadow` image only on activation and maximize changes
  (`Decoration::updateShadow`, not called from `onWindowSizeChanged`), and KWin stretches the old
  image's side tiles over the new size. The 1 px edge, which lives in the shadow outside the
  window, then starts 2-3 px early (window shrunk: a short spur beside the corner arc) or late
  (window grown: a gap) at the two top corners; the soft shadow ramps stretch too (not visible).
  It heals at the next focus change. Measured in the review: at most about 20 levels on a few
  pixels (`review-stale-shadow-corner-10x.png`). Upstream fix: call `updateShadow()` in
  `onWindowSizeChanged()`.
- Long titles are cut at the end of the caption area instead of getting a clean ellipsis
  (upstream Aurorae v2): `Decoration::paint` elides with `painter->fontMetrics()` before it sets
  the title font, so the elision is measured in the general font (Manrope 13 px regular) and the
  wider 14 px ExtraBold text is clipped at the caption rect. The text never runs under the
  buttons (`review-long-title-2x.png`). Upstream fix: set the font before `elidedText`.

## Needs from other parts

- Colour schemes: `[Colors:Header] BackgroundNormal` must equal the title colours (dark
  `34,40,64`, `[Colors:Header][Inactive] BackgroundNormal 31,37,54`; light `236,239,246` /
  `241,243,248`) so Breeze's tool area continues the title bar; `[Colors:Selection]
  BackgroundNormal 47,111,223` is the hover accent. (The research drafts already match.)
- Fonts: Manrope installed for KWin (`~/.local/share/fonts/plasma-fusion/`, or system-wide for the
  login screen); no part installs it yet, the test seeds copy `fonts/`.
- Global Theme / fusion-config: `BorderSizeAuto=false` and `BorderSize=None` (present); for the
  Appearance "Left · circles" choice write the -Left theme plus `ButtonsOnLeft=XIA`,
  `ButtonsOnRight=_` in one go, and back to the plain theme plus `M` / `IAX`.
- Phase 3 C++ decoration: rounded bottom corners with clipping, native outline, animations, icon
  fade, show-on-hover buttons, the maximize hover-hold trigger, square inner corners when tiled,
  a shadow that follows resizes, and correct title elision.
- Test tooling of the look-and-feel and plasma-style parts (`generators/look-and-feel/tests/
  session-common.sh`, `generators/plasma-style/tests/vsession-integrated.sh`): they export
  `XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:...` and then run `merge-kdedefaults.py`; with the
  kdedefaults layer in the cascade, kwriteconfig6 does not write a value equal to it, so nothing
  reaches `~/.config/kwinrc` / `kdeglobals` and KWin (started without that layer) keeps Breeze and
  Noto Sans title bars. Seen in the review's first run (rdc-1: "Plugin: org.kde.breeze", title font
  Noto Sans). Run the merge with `env -u XDG_CONFIG_DIRS` (as `scenario-review.sh` does). Real
  logins are not affected (startplasma puts kdedefaults in KWin's cascade).

## Review (2026-09-29)

An adversarial review of the part as built, with fixes, re-checked in private virtual sessions
(prefix rdc-) with every part built together.

What was checked:

- Board values against the code, element by element (Windows.dc.html, Main.dc.html,
  MainLight.dc.html, Colors.dc.html): 50 / 40 px bars, 14 / 13 px top corners, edge colours
  (spec value, opaque over the window background; the board render blurs its edge rows over the
  backdrop because of its half-pixel resampling), shadows, title colours, icon 26 px at 16,
  title 10 px after it, 28 px circles 6 apart and 10 from the right, active / inactive / hover /
  pressed fills, close red only when active, the left layout. All match; see the pixel
  comparisons in the evidence.
- Against the upstream sources (Aurorae v2 and KWin 6.7.5, KDecoration3): rc keys and their
  defaults, `borders()` with `BorderSize=None` and `BorderSizeAuto`, button state selection
  (checked toggles use the pressed frame), group hover, how the frame becomes the
  `DecorationShadow` and how KWin nine-slices it (this found the stale-shadow limit), caption
  painting (this found the elision limit).
- Build: `STAGE=<dir>/home tools/build.sh` (all parts, no errors); two decoration builds are
  byte-identical (`diff -r`); `tests/check_aurorae.py`: 4 themes, 0 errors; `xmllint` on all 44
  SVGs: 0 errors; naming-table ids (`PlasmaFusionDark`, `PlasmaFusionLight`, `-Left`, library
  `org.kde.kwin.aurorae.v2`, `__aurorae__svg__...`) as in docs/PLAN.md; no attribution text.
- Integrated sessions: `tests/make-review-seed.sh` + `tests/scenario-review.sh` apply the real
  Global Theme with `tools/device/fusion-config.sh --reset-layout` (top bar, dock, cards,
  colour schemes, fonts, icons, cursors) and then drive real Dolphin, System Settings and a
  kdialog: rdc-2 dark and rdc-3 light at 1440x900, rdc-4 dark at 1920x1200 scale 4/3.
  supportInformation: `Plugin: org.kde.kwin.aurorae.v2`, `Theme: __aurorae__svg__PlasmaFusion
  {Dark,Light}`, title font `Manrope,10.5,...,800`. KWin's warnings (in the ThinkPad user
  journal, `journalctl --user`) have no Aurorae / KSvg / decoration entries for these sessions.

  ```
  W=<work dir>
  STAGE=$W/home tools/build.sh
  generators/decoration/tests/make-review-seed.sh $W/home $W/seed-dark dark
  (cd $W && tools/vsession/remote.sh rdc-2 generators/decoration/tests/scenario-review.sh $W/seed-dark 1440x900 270)
  generators/decoration/tests/make-review-seed.sh $W/home $W/seed-light light      # rdc-3
  SCALE=1.3333333 generators/decoration/tests/make-review-seed.sh $W/home $W/seed-dark-s dark
  (cd $W && tools/vsession/remote.sh rdc-4 generators/decoration/tests/scenario-review.sh $W/seed-dark-s 1920x1200 270)
  ```

Fixed:

- Glyph placement (medium): the 13 px glyphs were centred at a half pixel, so at scale 1 the
  minimize dash was two half-bright rows (luminance 150 instead of the board's 226) and the
  maximize square looked like a small ring; the glyphs also sat 0.5 px below the board's. Glyphs
  now have an explicit origin (right layout 11, 10; left layout 6, 5, with the 13 px circle
  centred at 10.5, 9.5 so it lands on whole pixels): the dash is one row at 233, the square's
  strokes fall on the same rows as the board raster (`review-glyphs-board-before-after-8x.png`).
- Test tooling (low): new integrated seed and scenario; the kdedefaults merge runs without the
  kdedefaults layer in `XDG_CONFIG_DIRS`, otherwise kwriteconfig6 drops every merged key and KWin
  stays on Breeze (first run rdc-1). Optional `SCALE` for the 4/3 check.

Not fixable in an Aurorae theme (documented under deviations, phase 3 or upstream): the stale
shadow after a resize without a focus change, the long-title clipping, square inner corners for
tiled windows. Remaining from the build: bottom corners, animations, icon fade, 32 px tool
windows, hover-hold, show-on-hover, resize band.

Evidence (`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/decoration/`):
`review-{dark,light}-desktop.png` (integrated, Global Theme applied), `review-sbs-{dark,light}-
titlebars-2x.png` (board row first, then rest, hover maximize, hover close, pressed minimize,
left rest, left hover), `review-sbs-{dark,light}-inactive-2x.png`, `review-glyphs-board-before-
after-8x.png`, `review-stale-shadow-corner-10x.png`, `review-long-title-2x.png`,
`review-{dark,light}-{02..10}-*.png` (full screenshots of every step),
`review-dark-scale-4-3-1920x1200.png`, `review-dark-left-hover-scale-4-3-1920x1200.png`.
