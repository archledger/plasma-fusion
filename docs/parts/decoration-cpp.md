# Window decoration (phase 3): C++ KDecoration3 plugin "Plasma Fusion"

Status: built in the Fedora 44 build container on the ThinkPad (KDecoration 6.7.5, Qt 6.11.2, KF 6.30),
packaged as `plasma-fusion-decoration-1.0-2.fc44.x86_64.rpm` (1.0-2 = after review), checked offline
(mock-bridge renderer, 120 checks, dark and light, scale 1 and 4/3) and in private virtual sessions on
the ThinkPad with the whole Plasma Fusion desktop applied (dark, light, 1920x1200 at 4/3, Xwayland,
the Window Decorations settings page). Reviewed (see "Review"): passes. Not installed system-wide yet
(the review's install step was not permitted in that session; commands below) and not applied to the
real session. Last edited 2026-09-29.

## What it is

| | |
|---|---|
| Plugin id | `org.plasmafusion.decoration` (file `org.plasmafusion.decoration.so`; KWin takes the id from the file name) |
| Name in System Settings | Plasma Fusion |
| Installed at | `/usr/lib64/qt6/plugins/org.kde.kdecoration3/org.plasmafusion.decoration.so` (RPM); metadata (`src/plasmafusion.json`) is embedded in the .so |
| Package | `plasma-fusion-decoration` (x86_64), GPL-2.0-or-later, licence text in `/usr/share/licenses/plasma-fusion-decoration/` |
| kwinrc | `[org.kde.kdecoration2] library=org.plasmafusion.decoration`, `theme=` (empty) |
| Options | `~/.config/plasmafusionrc [Decoration]`: `ButtonStyle`, `SnapLayoutsOnHover` (contract below) |

It replaces the phase 1 Aurorae themes where the board needs code: 14 px corners on all four sides
with the window content clipped, square inner corners for tiled windows, a shadow that follows every
resize, animated states, the icon fade, 32 px tool-window bars, the show-on-hover mode, the
snap-layouts trigger on the maximize button and clean title elision. The look otherwise matches
the reviewed Aurorae part (docs/parts/decoration.md), value for value.

## Files (all in `packages/decoration-cpp/`)

| Path | What |
|---|---|
| `CMakeLists.txt` | project (ECM, C++20 because the KDecoration 6.7 headers need it); `BUILD_TESTING=ON` also builds `tests/` |
| `src/plasmafusion.json` | plugin metadata (`org.kde.kdecoration3`: `blur false`, `recommendedBorderSize None`); licence in `src/plasmafusion.json.license` (REUSE) |
| `src/decoration.{h,cpp}` | `PlasmaFusion::Decoration`: metrics, borders, radius, outline, shadow, button layout, caption, hover tracking, state handling |
| `src/button.{h,cpp}` | `PlasmaFusion::Button`: circles / dots / app icon, hover and press animations, the snap-layouts trigger |
| `src/colors.{h,cpp}` | colours from the window's colour scheme plus the board constants |
| `src/shadow.{h,cpp}` | CSS box-shadow renderer (three box blurs = Gaussian), shared `DecorationShadow` cache |
| `src/glyphs.{h,cpp}` | the board's symbolic glyphs (24-unit SVG paths, small SVG path parser) |
| `src/fusionconfig.{h,cpp}` | reads `plasmafusionrc`, `kwinrc [Plugins]`, `kdeglobals [KDE] AnimationDurationFactor` |
| `plasma-fusion-decoration.spec` | RPM spec (`%cmake`, `BUILD_TESTING=OFF`) |
| `LICENSES/GPL-2.0-or-later.txt` | licence text |
| `tools/build-rpm.sh` | laptop side: copies the package to the ThinkPad, builds plugin + tests + RPM in the container, fetches `build/cx/out/{bin,rpm}`; `PF_REMOTE` picks another work tree below the test user's HOME (a reviewer's build does not overwrite the builder's) |
| `tools/container-build.sh` | runs inside `localhost/plasma-fusion-build:f44-6.7.5` (cmake/ninja -j6 under nice 10, rpmbuild) |
| `tools/run-preview.sh` | runs `tests/pfdeco-preview` on the ThinkPad (offscreen, private D-Bus) for dark and light |
| `tools/sheet.py` | title-bar contact sheets (board first) from preview or session screenshots |
| `tests/preview.cpp` | `pfdeco-preview`: loads the real plugin through its factory with a mock KDecoration3 bridge, renders scenes, runs checks (not installed) |
| `tests/vsession/make-seed.sh`, `scenario.sh`, `scenario-kcm.sh` | virtual-session seed and scenarios (not installed) |

## Build

```
packages/decoration-cpp/tools/build-rpm.sh            # CLEAN=1 for a from-scratch build
#  -> build/cx/out/bin/org.plasmafusion.decoration.so, build/cx/out/bin/pfdeco-preview
#  -> build/cx/out/rpm/plasma-fusion-decoration-1.0-2.fc44.x86_64.rpm (+ debuginfo, debugsource)
# review build: CLEAN=1 PF_REMOTE=.local/state/plasma-fusion/rcx/decoration-cpp tools/build-rpm.sh build/rcx/out
```

On the ThinkPad the work tree is `~test/.local/state/plasma-fusion/decoration-cpp/` (`src/`,
`build/`, `rpmbuild/`); the container runs `podman run --rm --network=none -v $PWD:/work:Z` under
`nice -n 10` with 6 jobs. A clean build has no compiler warnings (KDE compiler settings: `-Wall
-Wextra -pedantic ...`). Plain CMake anywhere with the -devel packages:
`cmake -S packages/decoration-cpp -B build -G Ninja -DKDE_INSTALL_USE_QT_SYS_PATHS=ON && ninja -C build`.

## Install, apply, roll back (for the reviewer / the real session)

```
sudo dnf install --disablerepo='*' ./plasma-fusion-decoration-1.0-2.fc44.x86_64.rpm   # as root
rpm -V plasma-fusion-decoration                                             # no output = clean
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.plasmafusion.decoration
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme ""
qdbus6 org.kde.KWin /KWin reconfigure
```

(or System Settings > Colors & Themes > Window Decorations > "Plasma Fusion"). Keep
`BorderSize=None` / `BorderSizeAuto=false` as fusion-config.sh already writes; the plugin draws no
side borders whatever they say. Rollback: set `library=org.kde.kwin.aurorae.v2` and
`theme=__aurorae__svg__PlasmaFusionDark` (or `...Light`, `...-Left` with `ButtonsOnLeft=XIA`,
`ButtonsOnRight=_`), reconfigure, then `sudo dnf remove plasma-fusion-decoration`. Removing the
package while it is selected makes KWin fall back to its default decoration (seen in a test session:
"Could not locate decoration plugin" and Aurorae/Breeze title bars, no crash).

## Contract with the settings module

`~/.config/plasmafusionrc`, group `[Decoration]`, re-read on every KWin reconfigure
(`qdbus6 org.kde.KWin /KWin reconfigure`; also when System Settings changes KWin settings):

| Key | Values | Effect |
|---|---|---|
| `ButtonStyle` | `RightGlyphs` (default) | app icon left, title left, 28 px circles with glyphs on the right; KWin's button lists (`ButtonsOnLeft` / `ButtonsOnRight`) are honoured |
| | `LeftCircles` | close, minimize, maximize as 13 px circles on the left (fixed order, KWin's lists ignored, no app icon), title centred |
| | `ShowOnHover` | as RightGlyphs, buttons fade in while the pointer is over the title bar |
| `SnapLayoutsOnHover` | `true` (default) / `false` | hovering the maximize button of the active window for 600 ms, or holding it pressed for 600 ms, invokes the KWin global shortcut `Plasma Fusion: Snap Layouts` (`org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut`, asynchronous, never waited for); after a hold the release does not toggle maximize |

The trigger is active only when `kwinrc [Plugins] plasmafusion-snapEnabled=true` (without the script
there is no flyout, and holding maximize must still maximize) and only for the active, normal,
movable, resizable, maximizable window (the script's own `usable()` test). The hover trigger fires
once per visit of the pointer to the title bar: the shortcut toggles the flyout, so a second hover
would close it. Unknown `ButtonStyle` values mean `RightGlyphs`.

## Look (board values; everything in logical px, snapped to the device grid at 4/3)

| Board (Windows.dc.html unless named) | Implementation |
|---|---|
| Title bar 50 px, 40 maximized, 32 tool windows (spec 7) | `setBorders(0, 50/40/32, 0, 0)`; tool = KWin window property `utility` or `toolbar` (see "How") |
| Title bar colour (Colors.dc.html #222840 / #1f2536, light #eceff6 / #f1f3f8) | the window's colour scheme, Header group background (active / inactive), cross-faded in 150 ms on activation |
| Top corners 14 px outside the edge (spec 4) | frame radius 13 px + 1 px KWin outline = 14 px outer; title bar painted round at the top |
| Bottom corners 14 px with content clipped | `setBorderRadius(0, 0, 13, 13)`: KWin clips title bar and client (SDF, anti-aliased) |
| Maximized: square, no shadow, no edge | radius 0, no outline, `setShadow(nullptr)`, decoration opaque |
| Tiled: outer corners round, inner square ("Maximized and tiled", border-radius 0 0 0 6px / 0 0 6px 0) | top corners square; a bottom corner stays round only where its two sides lie on the work-area border (left half: bottom-left) |
| 1 px edge, white 14 % / 8 % (spec 5; light rgba(20,24,39,.14/.08)) | KWin border outline outside the frame, opaque colour = edge over the scheme's Window background (#3b3f4e active dark), like the Aurorae part |
| Shadow active 0 34 90 px 55 % black, inactive 0 24 60 px 35 % (spec 6; light MainLight rgba(20,24,39,.22/.14)) | Gaussian sigma = blur/2 of the window shape (frame + outline), reach 3 sigma, measured within 0.0074 alpha of the analytic CSS profile (preview check) |
| App icon 26 px, 16 px from the left; 60 % on inactive windows (spec 1, :95) | the window icon, snapped to device pixels, opacity 0.6 + 0.4 x active |
| Title 14 px ExtraBold, left, 10 px after the icon (spec 2) | `settings()->font()` = kdeglobals `[WM] activeFont` (Manrope 10.5 pt 800 = 14 px); colour = Header foreground active / inactive (#e8ebf4 / #8891aa), cross-faded; elided at the end with the title font |
| Buttons: 28 px circles 6 apart, 10 px from the right (spec 3), centred on y 24.5 (the board's 49 px row) | hit areas 34 px wide (circle + half gaps) and full bar height; the first/last one reaches the screen edge when maximized |
| Rest fills white 10 % / 7 % (ink on light), glyph #e8ebf4 / #a3abc2 (Main.dc.html:94-96, 145-147) | same; close #D9434B with white glyph on the active window only |
| Hover: accent fill, white glyph, 3 px ring rgba(91,157,255,.3) (:108); close red | accent = the window palette's Highlight (Selection background); ring = the scheme's DecorationHover (#5b9dff) at 30 %, red at 30 % for close; 150 ms ease |
| Pressed | hover look under 20 % black, 80 ms |
| Glyphs: 13 px, stroke 1.8 in the 24 grid, round caps | the board paths; centred on a device-pixel centre so the minimize dash is one crisp row |
| Buttons on the left (:116-125): 13 px circles 7 apart 12 px from the left, #8891aa, title centred | same; light #9aa0b2; inactive 40 % / 45 %; hovering any circle colours all three (close red, others accent) with 9 px white glyphs |
| Resize area: invisible 8 px band, 16 px corners (spec 7) | `setResizeOnlyBorders(8)` on every free side (none when maximized in that direction); KDecoration makes the corner zones 2 x largeSpacing (~20 px) |
| Extra buttons KWin may request | keep above/below, on all desktops, shade, context help, application menu, exclude from capture, spacer: same circle style with their own glyphs; toggled-on buttons keep the pressed accent look |

## How (KDecoration3 / KWin 6.7.5 details that matter)

- Outline and clipping are KWin's own (`setBorderOutline`, `setBorderRadius`), as in Breeze 6.7; the
  outline colour changes only on activation (each state change is a configure round-trip for Wayland
  clients, so it is not animated). Radius and outline thickness are snapped to the next scale's pixel
  grid, so at 4/3 the corner is 17 device px inside + 1 px outline.
- Window type and tiles: KDecoration3 has neither. KWin creates the decoration with the
  `KWin::Window` as its QObject parent; the plugin reads that window's scripting properties by name
  (`utility`, `toolbar`, `normalWindow`, `specialWindow`, `tile` and the tile's `relativeGeometry`,
  converted to QRectF through KWin's registered converter). Elsewhere (settings page preview) the
  properties are simply invalid and the defaults apply. The tile path is needed because KWin reports
  no adjacent screen edges for tiles with padding (`Tile::anchors()` returns nothing when padding
  > 0, and Plasma Fusion uses 6 px gaps); tile changes arrive as `adjacentScreenEdgesChanged`.
- Shadows are rendered once per parameter set (colour, opacity, blur, offset, radius, corner shape)
  and shared by every window (KWin also shares the nine-patch texture per shadow object); the cache
  is dropped with the last decoration. Rebuilt on activation, maximize, tile and palette changes;
  KWin stretches the tiles on resize, so there is no stale edge (the Aurorae limitation).
- Palette changes (per-window colour schemes, the global Dark/Light switch) re-read the colours; a
  check switches a window from one scheme to the other and reads the new title colour.
- Reconfigure re-reads the options once per event-loop pass for all decorations and rebuilds the
  buttons when the style changes (hiding a tooltip of a hovered button that goes away).
- Debug output: `QT_LOGGING_RULES=org.plasmafusion.decoration.debug=true` prints one line per
  decoration (parent class, tool / normal, style, snap trigger, scale, title height).

## Verification

Offline: `tools/run-preview.sh` (after `tools/build-rpm.sh`) runs `pfdeco-preview` on the ThinkPad
under `dbus-run-session`, offscreen, with scratch config under
`~test/.local/state/plasma-fusion/decoration-cpp/preview-config-*` (the user's own config is never
read or written). It loads the real plugin, draws 22 scenes per scheme and scale over the Main /
MainLight board renders at the board's Appearance-window frame (549,263 650x504), and checks:
title bar 50 / 40 / 32 px, circle positions (close 24 px, maximize 58 px from the right: the snap
flyout's assumption), icon at 16, no side borders, clip radius, outline outer radius 14 (13.5 at
4/3), resize band, shadow profile against the CSS Gaussian, maximized (no shadow/outline, square),
a left tile with gaps (only its outer bottom corner round), state churn (maximize / tile / shade /
width 40 px / palette / reconfigure) without a crash, the palette switch, and the snap trigger
against a fake kglobalaccel service: nothing before 600 ms, hover fires once per visit and again
after leaving, hold fires and the release does not maximize, a quick click maximizes without the
flyout, inactive windows and `SnapLayoutsOnHover=false` or a disabled script do nothing special,
and a live `ButtonStyle` switch. Result: 120 PASS, 0 FAIL (dark and light, scales 1 and 4/3).

Virtual sessions on the ThinkPad (whole desktop from `tools/build.sh`, applied with
`fusion-config.sh --install`, then `library=org.plasmafusion.decoration`), real pointer input with
pfinput:

```
W=build/cx; STAGE=$PWD/$W/home tools/build.sh
packages/decoration-cpp/tests/vsession/make-seed.sh $W/home $W/out/bin/org.plasmafusion.decoration.so $W/seed cx-15 dark [1.3333333]
(cd $W && ../../tools/vsession/remote.sh cx-15 ../../packages/decoration-cpp/tests/vsession/scenario.sh seed 1440x900 420)
# scale run: same with SCALE 1.3333333 and 1920x1200; settings page: scenario-kcm.sh
```

`scenario.sh` places System Settings (active, the board's Appearance frame), Dolphin (inactive, the
board's Files window) and Konsole, then: hover maximize / close, press minimize and release
outside (not minimized), hover maximize 1.4 s with the trigger on (flyout opens under the button),
click maximize while that flyout is open (see deviations), hover the inactive Dolphin's maximize (no
flyout), hold maximize (flyout; after the release the window is not maximized), quick click
(maximized, 40 px bar, square), quick tile left and right (6 px gaps, corners as on the board),
LeftCircles rest / hover, ShowOnHover away / over, then 4 more windows and a modal kdialog through
two rounds of maximize-all, fullscreen, keep above, on all desktops, 160 x 90 px geometry,
minimize/restore. Final runs: cx-15 dark, cx-14 light, cx-16 1920x1200 at 4/3, cx-17 dark with the
final binary, cx-18 the Window Decorations page ("Plasma Fusion" listed, previews and button
previews drawn). supportInformation: `Plugin: org.plasmafusion.decoration`, title font
`Manrope,10.5,...,800`. KWin logs: no warnings from the plugin. `coredumpctl` since the start of
this work: no core dumps from these sessions (the ones listed belong to other agents' sessions:
kdialog run as plasmalogin by greeter-apply.sh, perf-pilot KWin sessions, kscreen-doctor/spectacle
called without a display).

Board comparison (pixels at the board positions, dark / light): title bar 34,40,64 vs board 33,39,63
and 236,239,246 vs 235,238,245; neutral button 57,62,83 vs 56,61,81 and 214,217,225 vs 213,216,225;
close 217,67,75 vs 216,66,75; inactive title bar 31,37,54 vs 31,36,55; circle and glyph rows and
title text rows identical (283-295) at scale 1; icon 0.5 px lower (snapped to whole pixels). The
board render sits about 0.6 px right/down of its CSS geometry and blends its edge row with the
backdrop, so its edge reads darker (49,47,66) than the spec value we draw (59,63,78), as the Aurorae
review found.

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/decoration-cpp/`:
`sbs-{dark,light}-titlebars-2x.png` (board row first, then rest, hover maximize, hover close,
pressed minimize, hold on maximize, left circles rest / hover, show on hover away / over, maximized),
`sbs-{dark,light}-inactive-2x.png`, `sbs-dark-titlebars-scale-4-3.png`, `tiled-corners-6x.png`,
`dark-*.png` / `light-*.png` / `dark-scale-4-3-*.png` (full session screenshots: desktop, snap flyout
on hover and on hold, click while the flyout is open, inactive hover, maximized, tiled halves,
LeftCircles, ShowOnHover, many small windows), `kcm-window-decorations.png`,
`offline-{dark,light}-scenes-s{1,4-3}.png` (all preview scenes incl. tool window, extra buttons, long
title, disabled buttons, shaded), `preview-{dark,light}.log`, the RPM and its `.sha256`.

## Deviations (with reasons)

- A click on maximize while the hover-opened flyout is open only closes the flyout; the second
  click maximizes. KWin's popup input filter swallows any press outside an open popup
  (`PopupInputFilter::pointerButton`) before the decoration sees it. Consequence of the contract's
  default `SnapLayoutsOnHover=true` (the flyout opens after 600 ms of rest on the button); verified
  in the sessions (`dark-05b-click-while-flyout-open.png`). See "Needs from other parts".
- The hover trigger works on the active window only (the script's flyout acts on the active window);
  hovering an inactive window's maximize shows the normal hover and tooltip.
- The tooltip stays KWin's translated "Maximize" / "Restore" instead of the board's "Maximize · hold
  for snap layouts" (the plugin has no translations; with the trigger on, the flyout opens before a
  first tooltip would appear).
- LeftCircles always shows close, minimize, maximize (no app icon, no other buttons); RightGlyphs
  and ShowOnHover follow KWin's button lists.
- Border size settings (System Settings "Window border size") are ignored: the design has no side
  borders; the invisible 8 px resize band replaces them.
- Tool-window bars (32 px, 20 px circles) apply to X11 utility/toolbar windows; native Wayland
  clients have no window type (KWin reports them as normal), so they get the 50 px bar. Checked
  offline and, in the review, with an Xwayland test session (a Qt::Tool X11 window: frame 192 =
  client 160 + 32 px).
- KWin 6.7.5 has no window shading at all: `DecoratedWindowImpl::isShaded()` and `isShadeable()`
  always return false (src/decorations/decoratedwindow.cpp), for X11 and Wayland windows alike. A
  Shade button in KWin's button list is drawn disabled; the shaded look (title bar with four round
  corners) exists only for the offline preview.
- Modal dialogs keep a normal 50 px title bar; the board's attached sheet without a title bar stays
  with the plasmafusion-attach script (`HideDialogTitleBar`).
- No separator line under the title bar, as in the Aurorae part (Breeze's tool area continues the
  title bar colour and draws its own separator).
- Tabs in the title bar (TabsSnap board) remain an accepted platform deviation (PLAN.md).
- The settings-page preview is narrow: with all its sample buttons the caption shrinks to "…".
- Tiles resized by dragging the split keep the corner shape of their original anchors until the
  next tile change (no signal for a tile's geometry; the shape only changes if a split reaches the
  screen border).

## Needs from other parts

- KWin part (plasmafusion-snap): with `ButtonStyle=LeftCircles` the maximize circle's centre is
  58.5 px from the LEFT edge (12 + 13 + 7 + 13 + 7 + 6.5), not 58 px from the right; the flyout
  should read `plasmafusionrc [Decoration] ButtonStyle` for its placement. For RightGlyphs /
  ShowOnHover the centre is 58 px from the right (checked by the preview).
- KWin part / lead (UX of the contract): the hover trigger plus KWin's popup filter means the first
  click on maximize after resting 600 ms on it is swallowed. Options: keep hover off by default
  (hold only), or have the flyout close itself and maximize when it sees the press (not possible from
  a Qt popup today), or accept it as on Windows 11 (where the click still maximizes).
- Settings module: write `library=org.plasmafusion.decoration` and an empty `theme`, then
  reconfigure; fall back to the Aurorae themes when `org.plasmafusion.decoration.so` is not present.
  `ButtonStyle` changes need no kwinrc button-list change for the C++ decoration.
- Lead / test tooling: `tools/vsession` now keeps sessions in `/var/tmp/pfv-NAME`; seeds that set
  `QT_PLUGIN_PATH` in `.config/pfv-env` must use that path literally (our make-seed.sh does,
  `PFV_BASE` overrides). A session whose plugin path is wrong silently shows the Aurorae fallback,
  which looks almost identical: scenario.sh now logs an ERROR when supportInformation does not name
  `org.plasmafusion.decoration`.
- Lead / look-and-feel (observation): applying the Global Theme inside a running session
  (fusion-config.sh in a test session) sometimes left KWin's title font at Noto Sans (6 of 13
  runs, e.g. KWin started with Manrope pre-seeded and fell back to Noto Sans after the apply;
  the value lives only in `~/.config/kdedefaults/kdeglobals`). A real login reads it at start-up, but
  the same may happen when the theme is re-applied in the real session. scenario.sh works around it
  by writing `[WM] activeFont` into `~/.config/kdeglobals` (with `env -u XDG_CONFIG_DIRS`) and
  sending `org.kde.KDEPlatformTheme.refreshFonts`.

## ThinkPad changes made by this part

None outside the test user's home and the (deleted) test sessions: no sudo, no system files, the
RPM is not installed, the real session untouched. Work tree
`~test/.local/state/plasma-fusion/decoration-cpp/` (58 MB: sources, build, rpmbuild, preview output
and scratch config; delete it to undo). Virtual sessions `/tmp/pfv-cx-1..13` (removed) and
`/var/tmp/pfv-cx-14..18` (removed by remote.sh).

## Review (2026-09-29, reviewer session prefix rcx-)

Verdict: passes. No functional defect was found in the plugin; the fixes below are small
correctness, packaging, documentation and tooling items. One contract-level UX issue (the hover
trigger's swallowed click) is confirmed and stays with the lead and the KWin part.

How it was checked:

- Clean container build of the reviewed sources (`CLEAN=1`, 6 jobs, nice 10): 0 compiler warnings;
  `rpmbuild` only prints the usual Fedora `%cmake` notices. RPM contents: the plugin and the licence.
- Offline `pfdeco-preview` against the rebuilt plugin: 120 PASS, 0 FAIL (dark and light, scales 1
  and 4/3), before and after the fixes.
- KWin 6.7.5 sources for every assumption the plugin makes: the decoration's QObject parent is the
  `KWin::Window` (`DecorationBridge::createDecoration`); `window.tile` is `requestedTile`, updated
  before `requestedTileChanged`, which KWin forwards as `adjacentScreenEdgesChanged`;
  `Tile::anchors()` is empty with padding, so the tile path is needed; KWin's Scripting registers the
  `KWin::RectF` -> `QRectF` converter at workspace start; `DecorationSettings::reconfigured` fires on
  every KWin reconfigure; title and text colours come from the scheme's Header group
  (`DecorationPalette`); KWin's `PopupInputFilter` eats the first press outside an open popup.
- Integrated virtual sessions from a fresh `tools/build.sh` stage of the current repository (all
  parts applied with `fusion-config.sh --install`), plugin via `QT_PLUGIN_PATH`, real pointer input:
  - rcx-1 (dark, 1440x900, with Xwayland): board comparison, hover / press states, hold on
    maximize (flyout; after the release the button shows the hover look, not a stuck pressed look,
    and the window is not maximized), live colour-scheme switch dark -> light -> dark with windows
    open, switching the decoration to Aurorae and back at run time (with the flyout open), 12 rapid
    `ButtonStyle` reconfigures while the pointer moves over the buttons, 16 Konsole windows opened,
    maximized and closed, an X11 normal and an X11 utility window (32 px bar: frame 192 = client
    160 + 32), quick tiles left / right (top and inner corners square, outer bottom corners round),
    untiling (all corners round again), double-click maximize (40 px bar).
  - rcx-2 (light, 1920x1200 at scale 4/3): hover / close / press-released-outside (not minimized),
    the hover flyout dismissed with Esc while the pointer rests on maximize for 2.5 s (it does not
    reopen), a click on maximize while the hover flyout is open (closes the flyout, window not
    maximized, no reopen; the second click maximizes), pointer wiggle on maximize while the flyout is
    open (stays open), LeftCircles group hover, ShowOnHover, maximized.
  - rcx-3 (dark, 1920x1200 at 4/3, final build): the evidence set below.
- Board comparison at scale 1 (desktop-dark-1 positions): title bar 34,40,64 vs 33,39,63; neutral
  button 57,62,83 vs 56,61,81; close 217,67,75 vs 216,66,75; inactive title bar 31,37,54 vs
  31,36,55; inactive buttons 47,52,68 vs 45,51,67; title text rows and weight identical. The edge
  is the CSS value (59,63,78 dark); at 4/3 it is exactly one device pixel, light 222,223,225 active
  and 236,237,238 inactive (the CSS values over white).
- KWin logs of all review sessions: no warnings from the plugin. `coredumpctl` on the ThinkPad since
  the review started (18:52): no core dumps.

Findings:

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | medium | With `SnapLayoutsOnHover=true` (contract default) a user who rests 600 ms on maximize and then clicks it gets no maximize: KWin's `PopupInputFilter` closes the Qt.Popup flyout and eats the press; the second click maximizes. Confirmed at 4/3. There is no reopen loop (Esc or the click close it for good while the pointer rests). The decoration never sees that press. | Not fixable here: plasmafusion-snap could use a non-grabbing flyout, or the lead makes the default hold-only |
| 2 | low | `AnimationDurationFactor` was read from `~/.config/kdeglobals` only (`KConfig::SimpleConfig`), unlike KWin, which reads the cascade (kdedefaults, /etc/xdg). | Fixed (`CascadeConfig`) |
| 3 | low | The doc said shading is X11-only; KWin 6.7.5 has no shading at all (`isShaded()` / `isShadeable()` always false). | Fixed (doc) |
| 4 | low | Tool-window bars were verified offline only. | Verified in an Xwayland session (32 px) |
| 5 | low | Sources did not follow KDE's clang-format (ECM `.clang-format`, 160 columns). | Fixed (formatting only) |
| 6 | low | rpmlint: `%description` lines over 79 columns. Remaining rpmlint output: a false spelling hit (`plasmafusionrc`), no URL / no documentation warnings, and `incorrect-fsf-address` on the REUSE GPL text (identical to Breeze's). | Fixed (wrapped) |
| 7 | low | Spec comment said the plugin API is private to the KDecoration minor release while `Requires` allows any >= 6.7; the plugin links only the public `libkdecorations3.so.6`. | Fixed (comment; rebuild after each Plasma feature release) |
| 8 | low | `build-rpm.sh` / `run-preview.sh` always used the builder's work tree on the ThinkPad, so another build overwrote it. | Fixed (`PF_REMOTE`) |
| 9 | low | `pfdeco-preview` printed an empty plugin id (the explicit Id was removed from the metadata). | Fixed (prints `KPluginMetaData::pluginId()`: `org.plasmafusion.decoration (Plasma Fusion)`) |
| 10 | low | `src/plasmafusion.json` had no licence information (REUSE). | Fixed (`plasmafusion.json.license`) |
| 11 | medium | Review step "install the RPM system-wide, `rpm -V`, load the system copy in a session" could not be run: the session's permission system denied the `sudo dnf install`. | Open: commands below for the lead |

Release after review: `plasma-fusion-decoration-1.0-2.fc44.x86_64.rpm`, sha256
`16c6ac060b22a0ff267c2fab0bc068b0950e8fd9cfc6e4335d4d1edb7a42f69d`, on the share next to the
builder's 1.0-1 (superseded) and on the ThinkPad in
`~test/.local/state/plasma-fusion/rcx/decoration-cpp/rpmbuild/RPMS/x86_64/`. To install and check
(ThinkPad, as root; does not switch any session):

```
sudo dnf install --disablerepo='*' ~test/.local/state/plasma-fusion/rcx/decoration-cpp/rpmbuild/RPMS/x86_64/plasma-fusion-decoration-1.0-2.fc44.x86_64.rpm
rpm -V plasma-fusion-decoration && echo clean
# then a virtual session without QT_PLUGIN_PATH: make-seed.sh, delete the QT_PLUGIN_PATH line from
# SEED/.config/pfv-env, run scenario.sh; it logs ERROR if KWin did not load org.plasmafusion.decoration
# rollback: sudo dnf remove plasma-fusion-decoration   (with the real session still on Aurorae)
```

Test-tool note: `pfinput 'down'` without an `'up'` in the same call releases the button when
pfinput exits, at the current position (a press on minimize held across two pfinput calls minimizes).

Evidence (`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/decoration-cpp/`):
`review-final-dark-4-3-*.png` (rcx-3, final build, dark at 4/3: desktop, hover maximize / close,
snap flyout on hover, hover after an accent change to #E0457B, tiled halves, maximized, LeftCircles
hover, ShowOnHover away / over, live switch to the light scheme, the Window Decorations settings
page listing "Plasma Fusion"); `review-dark-s1-*` (scale 1: desktop and board-above / session-below
crops of the active title bar, the buttons and the inactive title bar); `review-light-4-3-*`
(desktop, button hover and LeftCircles hover zoomed 3x in device pixels, the flyout closed with Esc
and not reopening, the click swallowed while the flyout is open, the second click maximizing);
`review-hold-release-not-maximized.png`, `review-live-scheme-dark-to-light.png`,
`review-aurorae-and-back.png`, `review-after-reconfigure-churn.png` (the flyout visible in both
was opened by the hover trigger: the pointer rested on maximize for more than 600 ms while a
screenshot was taken earlier in the run, and nothing closed the popup since),
`review-xwayland-normal-and-tool-32px.png`, `review-tiled.png`, `review-untiled.png`,
`review-tile-corners-8x.png`, `review-preview-{dark,light}.log` (offline checks of the final build),
and the reviewed RPM `plasma-fusion-decoration-1.0-2.fc44.x86_64.rpm` with its `.sha256`.

ThinkPad changes by the review: work tree `~test/.local/state/plasma-fusion/rcx/` (58 MB: sources,
build, rpmbuild, preview output and scratch config; `rm -rf` it to undo); virtual sessions
`/var/tmp/pfv-rcx-1..3` (removed by remote.sh after each run); rcx-1 ran KWin with `--xwayland`
(its `/tmp/.X11-unix/X1` socket and lock were removed by KWin at exit, checked). No sudo, no system
files, no RPM installed, the real session untouched.
