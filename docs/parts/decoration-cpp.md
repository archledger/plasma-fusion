# Window decoration (phase 3): C++ KDecoration3 plugin "Plasma Fusion"

Status: **1.0-3** (work package DECO-1, 2026-09-30), built in the Fedora 44 build container on the
ThinkPad (KDecoration 6.7.5, Qt 6.11.2, KF 6.30) as `plasma-fusion-decoration-1.0-3.fc44.x86_64.rpm`.
Not installed: the lead installs it after review (the reviewed 1.0-2 is installed system-wide on the
ThinkPad, not selected; KWin still uses Aurorae). 1.0-3 adds, over the reviewed 1.0-2:

- snap layouts on **hold** by default (owner decision 4); `SnapLayoutsOnHover=true` adds hover;
- **touch title bars in tablet mode** (TABLET.md 4.9): 44 px hit areas or more while KWin's
  TabletModeManager reports tablet mode, read over D-Bus and live on a flip;
- **40 px title bars on screens under 800 px high** (ADAPTIVE.md 5.12);
- the board's tooltip "Maximize · hold for snap layouts".

The 200 % shadow and KWin's memory per window against Aurorae are measured (section "DECO-1
measurements"). Checked offline (the final build: 658 checks, dark and light, scales 1, 1.25, 4/3,
1.325 and 1.5, plus the 200 % shadow) and in 10 private sessions on the ThinkPad (section "DECO-1
verification"; the review fixes below are checked offline). The history of 1.0-1 and 1.0-2 (build,
review) is kept below. Last edited 2026-09-30.

## What it is

| | |
|---|---|
| Plugin id | `org.plasmafusion.decoration` (file `org.plasmafusion.decoration.so`; KWin takes the id from the file name) |
| Name in System Settings | Plasma Fusion |
| Installed at | `/usr/lib64/qt6/plugins/org.kde.kdecoration3/org.plasmafusion.decoration.so` (RPM); metadata (`src/plasmafusion.json`) is embedded in the .so |
| Package | `plasma-fusion-decoration` (x86_64), GPL-2.0-or-later, licence text in `/usr/share/licenses/plasma-fusion-decoration/` |
| kwinrc | `[org.kde.kdecoration2] library=org.plasmafusion.decoration`, `theme=` (empty) |
| Options | `~/.config/plasmafusionrc [Decoration]`: `ButtonStyle`, `SnapLayoutsOnHover` (contract below) |
| Reads (never writes) | KWin's tablet mode (`org.kde.KWin.TabletModeManager.tabletMode` on `org.kde.KWin /org/kde/KWin`), the window's screen height (`window.output.geometry`), `kwinrc [Plugins] plasmafusion-snapEnabled`, `kdeglobals [KDE] AnimationDurationFactor` |

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
| `src/fusionconfig.{h,cpp}` | reads `plasmafusionrc`, `kwinrc [Plugins]`, `kdeglobals [KDE] AnimationDurationFactor`; `snapHold()` / `snapHover()` |
| `src/tabletmode.{h,cpp}` | KWin's tablet mode over D-Bus, never blocking: one watcher per process (asynchronous `Properties.Get` at start, then the `tabletModeChanged` signal) |
| `plasma-fusion-decoration.spec` | RPM spec (`%cmake`, `BUILD_TESTING=OFF`) |
| `LICENSES/GPL-2.0-or-later.txt` | licence text |
| `tools/build-rpm.sh` | laptop side: copies the package to the ThinkPad, builds plugin + tests + RPM in the container, fetches `build/cx/out/{bin,rpm}`; `PF_REMOTE` picks another work tree below the test user's HOME (a reviewer's build does not overwrite the builder's) |
| `tools/container-build.sh` | runs inside `localhost/plasma-fusion-build:f44-6.7.5` (cmake/ninja -j6 under nice 10, rpmbuild) |
| `tools/run-preview.sh` | runs `tests/pfdeco-preview` on the ThinkPad (offscreen, private D-Bus) for dark and light |
| `tools/sheet.py` | title-bar contact sheets (board first) from preview or session screenshots |
| `tests/preview.cpp` | `pfdeco-preview`: loads the real plugin through its factory with a mock KDecoration3 bridge, renders scenes, runs checks (not installed) |
| `tests/vsession/make-seed.sh`, `lib.sh`, `scenario.sh`, `scenario-kcm.sh` | virtual-session seed, shared helpers (`geom` with the title height KWin applied, `flyout`, `setdeco`, `use_decoration`, `kwin_pid`) and the scenario set (not installed) |
| `tests/vsession/scenario-tablet.sh`, `scenario-short.sh`, `scenario-hidpi.sh`, `scenario-mem.sh` | 1.0-3 scenarios: tablet mode, a 1366x768 screen, the 200 % shadow, KWin memory per window |
| `tools/shadow-alpha.py` | the shadow's alpha from two session screenshots (window shown / minimized) against the CSS model, in device pixels |

## Build

```
packages/decoration-cpp/tools/build-rpm.sh            # CLEAN=1 for a from-scratch build
#  -> build/cx/out/bin/org.plasmafusion.decoration.so, build/cx/out/bin/pfdeco-preview
#  -> build/cx/out/rpm/plasma-fusion-decoration-1.0-3.fc44.x86_64.rpm (+ debuginfo, debugsource)
# review build: CLEAN=1 PF_REMOTE=.local/state/plasma-fusion/rcx/decoration-cpp tools/build-rpm.sh build/rcx/out
# DECO-1 build (under the team's build lock):
#   build/lead/vslot.sh --build env CLEAN=1 PF_REMOTE=.local/state/plasma-fusion/o1dc/decoration-cpp \
#     packages/decoration-cpp/tools/build-rpm.sh build/o1dc/out
#   build/lead/vslot.sh env PF_REMOTE=.local/state/plasma-fusion/o1dc/decoration-cpp \
#     packages/decoration-cpp/tools/run-preview.sh build/o1dc/out/preview
```

`PF_SSH_OPTS` (default `-o ConnectTimeout=40`) adds ssh options to both tools; `run-preview.sh` takes
`PF_SCALES` (default `1,1.3333333,1.325`) and runs the tool with `LANG=en_US.UTF-8`. On the ThinkPad
the work tree is `~test/.local/state/plasma-fusion/decoration-cpp/` (`src/`, `build/`, `rpmbuild/`); the container runs `podman run --rm --network=none -v $PWD:/work:Z` under
`nice -n 10` with 6 jobs. A clean build has no compiler warnings (KDE compiler settings: `-Wall
-Wextra -pedantic ...`). Plain CMake anywhere with the -devel packages:
`cmake -S packages/decoration-cpp -B build -G Ninja -DKDE_INSTALL_USE_QT_SYS_PATHS=ON && ninja -C build`.

## Install, apply, roll back (for the reviewer / the real session)

```
sudo dnf install --disablerepo='*' ./plasma-fusion-decoration-1.0-3.fc44.x86_64.rpm   # as root (upgrades 1.0-2)
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
| `SnapLayoutsOnHover` | `false` (default since 1.0-3, owner decision 4 "hold") / `true` | **Hold:** holding the maximize button of the active window pressed for 600 ms (mouse, pen or a finger's long press) invokes the KWin global shortcut `Plasma Fusion: Snap Layouts` (`org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut`, asynchronous, never waited for); after the hold the release does not toggle maximize, and a click maximizes on the first click. **`true` adds hover:** resting 600 ms on maximize opens the snap layouts too (laptop mode only, never in tablet mode; see the deviation on the first click after it) |

Both triggers are active only when `kwinrc [Plugins] plasmafusion-snapEnabled=true` (without the
script there is no flyout, and holding maximize must still maximize) and only for the active,
normal, movable, resizable, maximizable window (the script's own `usable()` test). The hover trigger
fires once per visit of the pointer to the title bar: the shortcut toggles the flyout, so a second
hover would close it. With the script on, hovering maximize shows the board's tooltip "Maximize ·
hold for snap layouts" ("Restore · ..." when maximized) on an English UI; other languages keep
KWin's translated "Maximize" (the plugin has no translations). Unknown `ButtonStyle` values mean
`RightGlyphs`. Up to 1.0-2 the key defaulted to `true` and `false` switched hold off as well; a
settings page that writes `false` for "Hold" now gets hold.

## Tablet mode (TABLET.md 4.9; 1.0-3)

While KWin's TabletModeManager reports tablet mode, every title bar is touch-sized; windows keep
their title bars (the Windowed case: `plasmafusion-tablet` `WindowMode=windowed`, a window made
"Windowed" from its window card, dialogs that stay framed, and every window when KWin runs without
the tablet script). Values in logical px; tablet heights are rounded **up** to the device grid so a
hit area never ends under 44 (at 4/3: 52.5 and 44.25; at 1.325: 52.08 and 44.53).

| Metric | Laptop | Tablet |
|---|---|---|
| Title bar | 50 (maximized 40, tool 32; 40 on short screens) | 52 (maximized, tool windows and short screens 44) |
| Button circles | 28, 6 apart, 10 from the edge; glyph 13 | 36, 8 apart, 8 from the edge; glyph 16 |
| Button hit areas | circle + gap (34) x bar height; app icon 32 | at least 44 wide (circle + gap = 44; the app icon's area is widened to 44) x bar height (44 or more) |
| Close / maximize centre from the right | 24 / 58 | 26 / 70 |
| App icon / title | 26 px / 14 px 800 (`[WM] activeFont`) | 28 px / 15 px 800 (the same font x 15/14) |
| `ShowOnHover` | fades in on hover | buttons always visible |
| `LeftCircles` | 13 px dots, 7 apart, 12 from the left; colours and glyphs on hover | 36 px circles, 8 apart, 8 from the left (maximize centre 114 px from the left); glyphs always, the active window always in colour (close red, the others the accent) |
| Snap trigger on maximize | hold (and hover with `SnapLayoutsOnHover=true`) | hold only (long press) |

How: `TabletMode` (one per process, a child of the application object; KWin never unloads a
decoration plugin) subscribes to `org.kde.KWin.TabletModeManager.tabletModeChanged` on
`/org/kde/KWin` with an empty sender (a named service would make QtDBus look up its owner with a
blocking call) and asks for the initial value with an asynchronous `Properties.Get` to
`org.kde.KWin` (retried 5 times at 1 s if KWin has not registered the object yet; a reply older
than a signal is ignored). The decoration runs inside KWin, so it never makes a synchronous call to
KWin. Kirigami's `TabletModeWatcher` is not used (stale start, TABLET.md F3). On a change every
decoration recomputes its metrics, borders (`setBorders`: KWin sends each window a configure) and
buttons. The settings page's previews (their own process) follow tablet mode the same way.

## Short screens (ADAPTIVE.md 5.12; 1.0-3)

Screens under 800 logical px high get 40 px title bars for normal windows (as maximized ones; tool
windows keep 32; tablet mode 44). The height comes from the window's KWin scripting property
`output` (a `KWin::LogicalOutput`) and its `geometry` (`KWin::Rect`, converted to `QRect` by the
converter KWin's scripting registers at workspace start), followed through `outputChanged` and the
output's `geometryChanged`: rotating a 1366x768 screen to portrait gives 50 again. Buttons keep
their laptop size (28 px circles in a 40 px bar, as when maximized). Outside KWin (settings-page
preview) the height is unknown and the normal values apply.

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
| Tooltip "Maximize · hold for snap layouts" (Windows.dc.html) | shown on hover when the snap script is on, English UI only (1.0-3) |
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
  decoration (parent class, tool / normal, style, snap hold / hover, scale, tablet, screen height,
  title height), every tablet-mode change, and a `layout` line with every button's hit area and
  circle size whenever they change (1.0-3; the session scenarios check hit areas with it).
- The shadow on 200 % screens: KWin 6.7.5 draws a decoration shadow image at one image pixel per
  logical pixel (`Shadow::elementSize` takes the tile sizes from the `DecorationShadow` geometry,
  `NinePatchOpenGL` samples it with `GL_LINEAR`, and there is no device-pixel-ratio path in
  kdecoration's `DecorationShadow`), so neither an @2x image nor a vector shadow can be handed to
  KWin. The shadow is a Gaussian of sigma 45 (30 inactive) logical px, and its frame cut-out lies
  1 px inside the window, under it; measured, the upscaling costs nothing visible (section "DECO-1
  measurements").

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

## DECO-1 verification (1.0-3)

Offline (`tools/run-preview.sh`: scales 1, 4/3 and 1.325, dark and light): 374 PASS, 0 FAIL. New
checks in 1.0-3:

- the contract default (key absent) and `SnapLayoutsOnHover=false`: resting 900 ms on maximize
  opens nothing and shows the tooltip "Maximize · hold for snap layouts"; the first click after the
  rest maximizes; holding 600 ms opens the snap layouts and the release does not maximize; with the
  script off the tooltip is KWin's plain "Maximize" and hold and release maximize;
- tablet mode against a fake `org.kde.KWin.TabletModeManager` on the private bus: read at start
  through the asynchronous Get (50 -> 52 within 400 ms), the signal both ways; 52, 44 maximized, 44
  for tool windows and on a short screen; every hit area at least 44 x 44; close 26 and maximize
  70 px from the right; hover never opens the flyout, even with `SnapLayoutsOnHover=true`; a hold
  (long press) does; a tap maximizes; ShowOnHover visible; LeftCircles hit areas 44; back to laptop
  (50, 34 px hit areas);
- short screens through a fake KWin output: 1366x768 -> 40, rotated to 768x1366 -> 50, 1280x799 ->
  40, 1440x900 -> 50; tool windows keep 32;
- the shadow at 200 % (next section).

Private sessions on the ThinkPad: the whole desktop from a `tools/build.sh` stage of a clean snapshot
of HEAD 3e950d4 with this package copied over it, applied with `fusion-config.sh --install`; the
plugin through `QT_PLUGIN_PATH`. Every run logged the 1.0-3 debug line, so KWin ran this build and
not the installed 1.0-2. Real input with pfinput:

| Run | Setup | Result |
|---|---|---|
| o1dc-s1 | `scenario.sh`, dark, 1440x900 at 1 | default: resting 1.4 s on maximize opens no flyout (`PFCXFLYOUT open=false`) and shows the board's tooltip; the first click maximizes (maximizeMode 3, title 40); hold opens the flyout, window not maximized; the hover option opens it; the rest of the scenario set as for 1.0-2 |
| o1dc-s43 | `scenario.sh`, light, 1920x1200 at 4/3 | the same; titles 50.25, maximized 39.75 (device grid) |
| o1dc-s1325 | `scenario.sh`, dark, 1920x1200 at 1.325 | the same; titles 49.81, maximized 40 |
| o1dc-tab | `scenario-tablet.sh`, dark, 1920x1200 at 4/3, KWin started in tablet mode | all windows 52.5 from their first frame (the first decoration was created before the Get reply and switched in the same millisecond); in 105 `layout` lines every hit area at least 44 x 44.25; pointer probes 20 px right of the maximize centre and 3 px below the bar's top light the button; hover 1.5 s with `SnapLayoutsOnHover=true`: no flyout; touch long press 1.1 s: flyout, not maximized; tap: maximized, 44.25; ShowOnHover visible; LeftCircles; a kdialog at 52.5; four live flips: new layout 11-32 ms after the setting was written (kwriteconfig6's start included), all three windows within 32 ms |
| o1dc-short | `scenario-short.sh`, dark, 1366x768 at 1 | 40 (normal and maximized); rotated to portrait 50; back 40; tablet mode 44; laptop 40 |
| o1dc-hidpi | `scenario-hidpi.sh`, light, 2880x1800 at 2 | shadow against the CSS model (next section) |
| o1dc-mem-cpp, -aur, -brz | `scenario-mem.sh`, dark, 1920x1200 at 4/3 | memory (next section) |
| o1dc-kcm | `scenario-kcm.sh`, dark, 1440x900 | the Window Decorations page lists and draws "Plasma Fusion"; its previews follow a tablet flip and back (their own D-Bus connection); System Settings kept running |

Build: clean container build, 0 compiler warnings (ninja and rpmbuild logs; rpmbuild prints only the
usual Fedora `%cmake` notices). rpmlint output identical to 1.0-2: the known spelling hits (`px`,
`plasmafusionrc`), no URL, no documentation, `incorrect-fsf-address` on the REUSE licence text.
`coredumpctl list --since "2026-09-29 23:15"` on the ThinkPad after all runs: no core dumps. KWin
logs: no warnings from the plugin. The settings page logs "KPluginFactory could not create a
KDecoration3::DecorationThemeProvider", as for 1.0-2 (the plugin has no themes).

## DECO-1 measurements

**KWin memory per window** (BACKLOG C10: at most 5 MiB of anonymous memory per extra window).
Private sessions at 1920x1200 and 4/3 with the whole Fusion desktop; KWrite windows of 800x500,
cascaded; `RssAnon` of the session's KWin from `/proc/<pid>/status` (equal to `Anonymous` in
`smaps_rollup`, read with `sudo -n`); one decoration per fresh session. MiB:

| Decoration | 0 windows | 1 | 5 | 10 | 15 | first window | per extra window, 1 -> 10 | 1 -> 15 |
|---|---|---|---|---|---|---|---|---|
| C++ 1.0-3 | 61.9 | 67.1 | 71.8 | 77.1 | 82.4 | 5.2 | **1.12** | 1.10 |
| Aurorae `PlasmaFusionDark` (today's) | 61.6 | 76.2 | 94.1 | 111.1 | 128.1 | 14.7 | **3.87** | 3.71 |
| Breeze (reference) | 61.8 | 65.5 | 70.3 | 75.0 | 79.6 | 3.7 | 1.05 | 1.00 |

With 10 windows the C++ decoration uses 34 MiB less than the Aurorae themes and 2.1 MiB more than
Breeze; its first window costs 1.5 MiB more than Breeze's (the shared shadow images, fonts and
glyphs). Both Fusion decorations stay under the 5 MiB budget per window.

**The shadow at 200 %** (ADAPTIVE.md 5.12; KWin cannot take an @2x or vector shadow, see "How"):

- offline (`pfdeco-preview`): the plugin's 1x image sampled at 2x as KWin does (`GL_LINEAR` at
  texel centres) against an exact Gaussian rendered at 2x, outside the window: at most 0.0088 alpha
  (dark) and 0.0044 (light). The same comparison at 1x gives 0.0093 and 0.0049: that is the
  three-box approximation of the Gaussian, not the scale. The upscaling alone (an exact 1x image
  sampled at 2x against the exact 2x image) differs by 0.01/255 at most.
- session o1dc-hidpi (light, 2880x1800 at 2): the alpha recovered from a screenshot with the window
  and one with it minimized (`tools/shadow-alpha.py`) against the CSS model in device pixels: at
  most 0.0062 in the column under the window (334 samples) and 0.0086 over the bottom-left corner
  (45 276 px), about one screenshot level (0.007 there). The 1 px edge is KWin's own outline, one
  device pixel wide at 200 %.

**Tablet flip:** 11-32 ms from writing `kwinrc [Input] TabletMode` (kwriteconfig6 `--notify`) to
the decorations' new layout, 4 flips with 3 windows (TABLET.md 9: drawn within 100 ms).

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build2/DECO-1/` (see its
`README.txt`): the RPM and its `.sha256`, build logs, `preview-{dark,light}.log`, offline title-bar
sheets (tablet, short screen, LeftCircles and ShowOnHover in tablet mode), the offline 200 % corner
comparison, the session screenshots and `scenario.log` / `kwin.log` excerpts of every run, `mem.txt`
of the three memory runs, and the 200 % session analysis (`shadow-profile.csv`, corner comparison).

## Deviations (with reasons)

- With `SnapLayoutsOnHover=true` (no longer the default since 1.0-3), a click on maximize while the
  hover-opened flyout is open only closes the flyout; the second click maximizes. KWin's popup input filter swallows any press outside an open popup
  (`PopupInputFilter::pointerButton`) before the decoration sees it. Consequence of the contract's
  default `SnapLayoutsOnHover=true` (the flyout opens after 600 ms of rest on the button); verified
  in the sessions (`dark-05b-click-while-flyout-open.png`). See "Needs from other parts".
- The hover trigger works on the active window only (the script's flyout acts on the active window);
  hovering an inactive window's maximize shows the normal hover and tooltip.
- The board's tooltip "Maximize · hold for snap layouts" shows only on an English UI (1.0-3; up to
  1.0-2 it was never shown): the plugin has no translations, so other languages keep KWin's
  translated "Maximize" / "Restore".
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
- (1.0-3) Shadows are not drawn as vectors or at @2x for 200 % screens (ADAPTIVE.md 5.12 asked for
  one of the two): KWin 6.7.5 has no way to take either from a decoration (see "How"). Measured
  instead: sampling the 1x image as KWin does differs from an exact 2x Gaussian by at most 0.01/255
  of alpha offline, and a 200 % session shows the CSS model within 0.0086 (about one screenshot
  level).
- (1.0-3) Tablet mode: tool windows get 44 px title bars, not TABLET.md 4.9's 40, because a 40 px
  bar cannot hold a 44 px hit area; short screens in tablet mode also get 44 (not 52).
- (1.0-3) Tablet mode, `LeftCircles`: TABLET.md 4.9 names no size for this style; it uses the
  RightGlyphs circle size (36) and shows glyphs always and colours on the active window, since
  nothing may depend on hover (ADAPTIVE.md 7).
- (1.0-3) In tablet mode the settings page's small "Plasma Fusion" preview is too narrow for all
  its sample buttons at 36 px, so they overlap (cosmetic, preview only; real windows narrower than
  about 200 px would show the same, as Breeze does).

## Needs from other parts

- KWin part (plasmafusion-snap, KWIN-2): the flyout anchors on the maximize centre 59 px from the
  right (`SnapFlyout.qml` `anchorRect.width - 59`). Where the centre really is: RightGlyphs /
  ShowOnHover 58 px from the right in laptop mode and **70 px in tablet mode** (1.0-3; the title bar
  is then 52 px, 44 maximized); `LeftCircles` 58.5 px from the LEFT in laptop mode and 114 px from
  the left in tablet mode. The flyout can tell tablet mode from `FusionTablet` (or from the title
  height `clientGeometry.y - frameGeometry.y` >= 44 while not maximized) and the style from
  `plasmafusionrc [Decoration] ButtonStyle`. In tablet mode the flyout currently hangs 11 px right of
  the button (seen in the o1dc-tab run).
- KWin part / lead (UX of the contract): settled by owner decision 4 (hold): 1.0-3 defaults to hold
  only, so a click on maximize is never swallowed by default. With `SnapLayoutsOnHover=true` the
  first click after the hover-opened flyout still only closes it (KWin's popup filter), unless
  KWIN-2's non-grabbing flyout spike lands.
- Settings module (KCM-1): write `library=org.plasmafusion.decoration` and an empty `theme`, then
  reconfigure; fall back to the Aurorae themes when `org.plasmafusion.decoration.so` is not present.
  `ButtonStyle` changes need no kwinrc button-list change for the C++ decoration. The "Snap layouts:
  Hold / Hover" control writes `SnapLayoutsOnHover=false` / `true` and reconfigures; the default
  (key absent) is now hold. Tablet mode needs no setting in the decoration.
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

DECO-1 (1.0-3): work tree `~test/.local/state/plasma-fusion/o1dc/decoration-cpp/` (sources, build,
rpmbuild, preview output, scratch config; `rm -rf ~test/.local/state/plasma-fusion/o1dc` to undo);
private sessions `/var/tmp/pfv-o1dc-*` (removed by remote.sh after each run). No RPM installed, no
system file changed; `sudo -n cat /proc/<session KWin>/smaps_rollup` (read-only) in the memory runs.
The real session untouched.

Earlier (1.0-1, 1.0-2): none outside the test user's home and the (deleted) test sessions: no sudo, no system files, the
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

## Review of 1.0-3 (DECO-1; reviewer `ro1dc`, finished by the lead)

The reviewer's work stopped when the lead took the lane over (2026-09-30 04:31Z); the lead kept its
fixes, re-ran the checks and fixed one more.

- Fixed (reviewer): a press that slid off maximize still opened the snap layouts after the hold
  time (the hold timer only stopped for the hover trigger). Leaving the button now ends either
  trigger, and a hold fires only while the pointer is on the button. Preview check added: a slide
  off opens nothing, the release off the button does not maximize, the next hold still works.
- Fixed (reviewer): in tablet mode the app icon's hit area (widened to 44 px) overlapped its
  neighbour's by 4 px; KDecoration gives a press to the first hovered button, so the wrong button
  could act. A hit area wider than circle + gap now moves its neighbour over; laptop positions are
  unchanged (there every hit area is exactly circle + gap). Preview check added: every KWin
  button next to the app icon, no two hit areas overlap, each at least 44.
- Fixed (lead): at scale 1.5 the 1 px light edge was rounded to 2 device px (an edge a third
  heavier than the shell's hairlines; outline outer radius 14.67 instead of 14; found when the
  review added scales 1.25 and 1.5 to the preview). The outline is now the Plasma Fusion hairline
  (1 device px up to 1.5, 2 from 1.75); unchanged at 1, 1.25, 4/3, 1.325 and 2.
- Final build in the Fedora 44 container: 0 compiler warnings. Preview at scales 1, 1.25, 4/3,
  1.325 and 1.5, dark and light: 658 PASS, 0 FAIL.

Release after review: `plasma-fusion-decoration-1.0-3.fc44.x86_64.rpm`, sha256
`84a04778491ce5962551a4fc2c99817e49a0a5f9bbd127c942e38d7dcf722dc4`
(`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build2/DECO-1/rpm/`; the builder's RPM
from before the review is kept in `rpm/builder-pre-review/`).
