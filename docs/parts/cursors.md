# Part: cursor themes

Two cursor themes drawn from `design/boards/Pointers.dc.html` (render `theme-parts-5`):

| Directory (id) | Name in settings | Look | Inherits |
|---|---|---|---|
| `PlasmaFusion-cursors` | Plasma Fusion | `#1b2031` fill, white 1.6 outline (board default) | `breeze_cursors` |
| `PlasmaFusion-Light-cursors` | Plasma Fusion Light | white fill, `#1b2031` outline (board "Light variant") | `Breeze_Light` |

Both are installed per user in `~/.local/share/icons/`. Each theme holds

- `cursors_scalable/<shape>/` KWin SVG cursors: `<shape>.svg` (or `<shape>-01..12.svg` for the
  animated ones) and `metadata.json` (`filename`, `hotspot_x`, `hotspot_y`, `nominal_size` 32,
  `delay`; the hotspot includes the 4-unit shadow margin, see Design values). KWin 6.7 prefers this directory, so everything that asks KWin for a cursor
  (Qt 6 and GTK 4 through cursor-shape-v1, KWin's own window edges, move and drag cursors) gets
  the SVG pointer rendered at the exact size and output scale.
- `cursors/<shape>` Xcursor files for everything that loads cursor files itself: GTK 3 apps
  (Firefox, via wayland-cursor), XWayland apps (libXcursor) and the cursor settings page (its
  previews and its size list come from `cursors/left_ptr`).
- 112 alias names as relative symlinks in both directories (same-directory links, which is what
  KWin's alias detection requires), so every name has a Fusion pointer: 37 drawings, 149 names.
- `index.theme` `[Icon Theme]` Name, Comment, `Example=default`, Inherits.

## Files (owned by this part)

| Path | Purpose |
|---|---|
| `generators/cursors/shapes.py` | the drawings (board path data + derived shapes), hotspots, animation, alias table, theme colours |
| `generators/cursors/gen_cursors.py` | writes both themes: SVG + metadata, Xcursor files rendered with QtSvg, index.theme, aliases; reads everything back (`verify`) |
| `generators/cursors/xcursor.py` | Xcursor binary writer and reader (standard library) |
| `generators/cursors/sheet.py` | contact sheets and board comparisons (verification only) |
| `generators/cursors/tests/test_cursors.py` | reproducibility, SVG/metadata, libXcursor and name-coverage checks |
| `generators/cursors/vsession/` | virtual-session test: `scenario-qt.sh`, `scenario-gtk.sh`, `scenario-kcm.sh`, `scenario-review.sh` (all parts, both Global Themes, window edges), `scenario-scaled.sh` (output scale 4/3), `eipointer.py` (pointer via KWin's EIS interface + libei), `qtcursors.py`, `gtkcursors.py`, `edgewin.py` + `place.js` (decorated test window at a fixed geometry), `shots_sheet.py` |
| `tools/build.d/40-cursors.sh` | build step: `$STAGE/.local/share/icons/PlasmaFusion{,-Light}-cursors` |

Build dependencies: python3 and PySide6 (`python3-pyside6`, for QtSvg, the renderer KWin itself
uses). No network, no xcursorgen, no kcursorgen. The output is byte-for-byte reproducible
(checked by the test). Size: 14 MB per theme (13 MB Xcursor, 0.8 MB SVG).

## Design values used

- Canvas: the drawings use the board's 32-unit canvas and `nominal_size` 32. KWin scales by
  `cursorSize / nominal_size`, so at size 24 the 32 units are 24 px, exactly the board's
  "Sizes 24 · 32 · 48 · 64 px" ramp (the arrow is then about 19 px tall, Breeze's is about
  20 px). The image adds a 4-unit margin on every side for the shadow: SVG
  `viewBox="-4 -4 40 40"`, `width`/`height` 40, hotspots in metadata.json shifted by +4, Xcursor
  images 1.25 x the nominal size (30 px for size 24). Breeze does the same (32 px images for
  nominal 24). 4 units = 3 px at size 24, so the drawing keeps its pixel grid at every size.
- Filled shapes: board fill + `stroke-width 1.6`, round joins. Line shapes (text, crosshair,
  not-allowed): 4.4 outline stroke under a 2.0 stroke, round caps (board `line`/`lc`/`lcl`).
- Colours: fill/outline `#1b2031`/`#ffffff` (light: swapped), spinner `#5b9dff`, `#f2a65a`,
  `#3cc4b0`, copy badge `#3aa65b`, not-allowed `#e5484d` (both themes, as `lcl` on the board),
  crosshair centre `#5b9dff`. The copy badge ring is white in the dark theme and `#1b2031` in
  the light theme (board `a1l`).
- Shadow: the board's "Sizes" panel, which shows the pointer at its real sizes:
  `drop-shadow(0 2px 3px rgba(0,0,0,.35))`. Designed at size 24 (the size the themes are applied
  with): 2 px = 2.667 units down, blur radius 3 px = Gaussian sigma 1.5 px = 2 units, opacity
  0.35; a black silhouette of the whole pointer under `feGaussianBlur` (QtSvg renders it). At
  other sizes it scales with the pointer.
- Hotspots = the board's amber rings (board units): default/progress/copy (6,3), pointer
  (14,3), all centred shapes (16,16); written as +4 in metadata.json and scaled per Xcursor
  size.
- Busy animation (wait, progress): the board's 4 key frames (0/30/60/90 degrees about 16,16.6 for
  wait and 25,25 for the progress badge, 800 ms loop, one loop = 120 degrees because the dots
  are three-fold symmetric) plus two in-betweens per key frame: 12 frames, 10 degrees apart,
  delays 67/67/66 ms = 800 ms. Frames 1, 4, 7 and 10 are the board's key frames.
- Xcursor sizes: 24, 32, 48, 64 (board) + 96, 128 (GTK 3 on a scaled output asks for
  size x ceil(scale): 24 at 4/3 -> 48, 48 at 2x -> 96, 64 at 2x -> 128). The settings page offers
  exactly these six sizes. Hotspot per size = the pixel containing the scaled hotspot
  (`floor((h + 4) * size / 32)`).

### Drawings (37) and aliases

Board pointers (board path data verbatim): `default`, `pointer`, `text`, `wait` (12 frames),
`progress` (12 frames), `move` (4-way arrow), `ew-resize`, `ns-resize`, `nwse-resize`,
`nesw-resize` (mirror of nwse), `crosshair`, `not-allowed`, `copy`.

Derived in the same style (arrow + the board's 6.4-unit badge at 25,25, or the hand, or the
fill/outline/line rules):

| Drawing | How | Aliases |
|---|---|---|
| `alias` | arrow + neutral badge with a curved link arrow | link, dnd-link, 3 hashes |
| `help` | arrow + accent (`#2f6fdf`) badge with "?" | whats_this, left_ptr_help, question_arrow, 2 hashes |
| `context-menu` | arrow + rounded menu badge with three lines | dnd-ask |
| `no-drop` | arrow + red badge with a white slash | — |
| `grab` | open hand (from the board hand) | openhand, 1 hash |
| `grabbing` | closed hand | closedhand, dnd-move, dnd-none, 5 hashes |
| `dnd-no-drop` | closed hand + red badge | — |
| `cell` | thick plus | plus |
| `all-scroll` | four triangles around a centre dot with the crosshair's blue | all_scroll |
| `vertical-text` | the text I-beam turned 90 degrees | — |
| `zoom-in`, `zoom-out` | lens (fill + outline) with +/− and a handle, hotspot at the lens centre | — |
| `col-resize`, `row-resize` | bar with two arrows | split_h / split_v + hashes |
| `up-arrow`, `down-arrow`, `left-arrow`, `right-arrow` | single arrow, hotspot at the tip | up_arrow, sb_up_arrow, based_arrow_up, ... |
| `center_ptr`, `right_ptr` | symmetric up pointer; mirrored arrow | centre_ptr |
| `color-picker`, `pencil` | eyedropper and pencil at 45 degrees, hotspot at the tip | draft, draft_large, draft_small |
| `x-cursor`, `pirate` | thick X; the same X in red (KWin's "kill window" cursor is `pirate`) | X_cursor |

The board drawings carry these aliases: `default` left_ptr, arrow, top_left_arrow,
wayland-cursor; `pointer` hand, hand1, hand2, pointing_hand + 2 hashes; `text` xterm, ibeam;
`wait` watch, clock; `progress` left_ptr_watch, half-busy + 3 hashes; `move` fleur, size_all,
all-resize; `ew-resize` e-/w-resize, size_hor, size-hor, h_double_arrow, sb_h_double_arrow,
left_side, right_side + hash; `ns-resize` n-/s-resize, size_ver, size-ver, v_double_arrow,
sb_v_double_arrow, double_arrow, top_side, bottom_side + hash; `nwse-resize` nw-/se-resize,
size_fdiag, size-fdiag, bd_double_arrow, top_left_corner, bottom_right_corner + hash;
`nesw-resize` ne-/sw-resize, size_bdiag, size-bdiag, fd_double_arrow, top_right_corner,
bottom_left_corner + hash; `crosshair` cross, tcross, cross_reverse, cross-reverse,
diamond_cross, diamond-cross; `not-allowed` circle, crossed_circle, forbidden + hash; `copy`
dnd-copy + 3 hashes. The full table is `ALIASES` in `shapes.py`.

Coverage: every name of `breeze_cursors` (115) and of `Adwaita` (63), every CSS /
cursor-shape-v1 name, every name in KWin 6.7.5's `CursorShape::alternatives` table (except the
misspelled `base_arrow_*`/`op_left_arrow` entries there) and the legacy Qt/KDE Xcursor hashes, so
nothing falls through to Breeze. Inherits still names Breeze for anything unforeseen.

## Build, install, apply

```sh
tools/build.sh cursors                      # or all parts; writes stage/home/.local/share/icons/PlasmaFusion{,-Light}-cursors
STAGE=/some/dir bash tools/build.sh cursors  # into another HOME tree
QT_QPA_PLATFORM=offscreen python3 generators/cursors/tests/test_cursors.py --work build/cr   # checks (about 4 s)
```

Install for a user: copy both directories with their symlinks (`rsync -a` or `cp -a`) to
`~/.local/share/icons/`. Apply in a running session:

```sh
plasma-apply-cursortheme PlasmaFusion-cursors --size 24        # or PlasmaFusion-Light-cursors
```

It writes `~/.config/kcminputrc` `[Mouse] cursorTheme=PlasmaFusion-cursors`, `cursorSize=24`,
signals KWin (KGlobalSettings notifyChange 5, KWin reloads at once) and Plasma's GTK settings
sync writes `gtk-cursor-theme-name`/`-size` into `~/.config/gtk-3.0/settings.ini`,
`gtk-4.0/settings.ini`, xsettingsd and GSettings (verified in the virtual session). The Global
Themes already set `[kcminputrc][Mouse] cursorTheme=PlasmaFusion-cursors` in `contents/defaults`
(look-and-feel part): applying either one writes it as a new default to
`~/.config/kdedefaults/kcminputrc` (verified in the review session rcr-3), which a real session
reads through `XDG_CONFIG_DIRS` (startplasma puts `~/.config/kdedefaults` first). No cursor size
is set there, so KWin uses its default 24. Manual equivalent: `kwriteconfig6 --file kcminputrc --group Mouse --key
cursorTheme PlasmaFusion-cursors` and `--key cursorSize 24`, then log out and in. KWin ignores
kcminputrc only when both `XCURSOR_THEME` and `XCURSOR_SIZE` are set in its environment.

Rollback: `plasma-apply-cursortheme breeze_cursors --size 24`, then remove the two directories.

## Verification done (2026-09-29)

Offline (laptop, same Plasma 6.7.5 / Qt 6.11.2):
- `gen_cursors.py` reads back every theme after writing it: every name exists in both
  directories, every alias is a same-directory link, every SVG loads in `QSvgRenderer` with a
  40x40 default size (32 + margin), every Xcursor file parses with the expected sizes, image
  sizes (1.25 x nominal) and frame counts.
- `tests/test_cursors.py`: two builds identical (716 paths); 496 SVG documents parse with
  ElementTree and their metadata matches KWin's parser rules, animations total 800 ms; the system
  libXcursor (`XcursorLibraryLoadImages` with `XCURSOR_PATH` = the build) finds all 149 names in
  both themes at 24 and 48 px (596 lookups) with the right frame count, size and hotspot, and
  the pixels come from the drawing the alias names; all 115 Breeze and 63 Adwaita names exist.
- `sheet.py`: `board-compare.png` puts the board render above the same panels rebuilt from the
  build (12 cards at 72 px, light variant at 48 px, the size ramp from the Xcursor files, the busy
  key frames) — they match to anti-aliasing; `contact-*.png` show every drawing read back from
  the Xcursor files at 24/32/48 px with the hotspot pixel marked, plus the SVG.

Virtual sessions on the ThinkPad (`tools/vsession/remote.sh`, names cr-1, cr-2, cr-3; seed = all
parts built into `build/cr/home` + `.config/kcminputrc` + the test tools):
- The virtual backend has no pointer, so KWin hides the cursor. `eipointer.py` gets an emulated
  absolute pointer from KWin's `org.kde.KWin.EIS.RemoteDesktop.connectToEIS` (libei via ctypes),
  moves it and takes `spectacle -b -n -f -p` screenshots (with pointer).
- cr-1: KWin `supportInformation` reports `themeName: PlasmaFusion-cursors`, `themeSize: 24`.
  A full-screen Qt window with one cell per `Qt::CursorShape` (21 shapes, cursor-shape-v1): KWin
  drew the Fusion SVG pointer for every one, hotspots on the pointer position, wait/progress
  caught on different frames. `plasma-apply-cursortheme --list-themes` lists both themes;
  switching to `PlasmaFusion-Light-cursors --size 24` changed kcminputrc, KWin reported the new
  theme and drew the light pointers live. No cursor warnings in kwin.log.
- cr-2: a GTK 3 window with 28 CSS cursor names (GTK 3 loads the Xcursor files itself): all 28
  drawn from our Xcursor files with the right hotspots.
- cr-3: `kcmshell6 kcm_cursortheme` lists "Plasma Fusion" (current, size 24) and "Plasma Fusion
  Light" with previews from the Xcursor files.

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/cursors/`. The files
without the `review-` prefix were made before the review changed the shadow and canvas (see
Review); the `review-*` files show the current build. Builder's files: (`board-compare.png`, `session-vs-board.png` = board cards above the pointers KWin drew at size
24 zoomed 3x, `contact-PlasmaFusion-cursors.png`, `contact-PlasmaFusion-Light-cursors.png`,
`session-kwin-qt-shapes.png`, `session-kwin-light-switch.png`, `session-gtk3-xcursor.png`,
`session-kcm-cursortheme.png`, `session-fullscreen-qt-help.png`, `session-checks.txt`).

Reproduce the session tests (from a directory on a disk with space, results land in
`./vsession-out/NAME/`):

```sh
STAGE=$PWD/home bash tools/build.sh
cp -al home seed && mkdir -p seed/pfv-cursor-test
printf '[Mouse]\ncursorTheme=PlasmaFusion-cursors\ncursorSize=24\n' > seed/.config/kcminputrc
cp generators/cursors/vsession/*.py seed/pfv-cursor-test/
tools/vsession/remote.sh cr-1 generators/cursors/vsession/scenario-qt.sh seed
tools/vsession/remote.sh cr-2 generators/cursors/vsession/scenario-gtk.sh seed
python3 generators/cursors/vsession/shots_sheet.py vsession-out/cr-1 qt shots-qt.png
QT_QPA_PLATFORM=offscreen python3 generators/cursors/sheet.py --icons home/.local/share/icons \
  --out sheets --board <renders>/theme-parts-5.png --session vsession-out/cr-1
```

## Deviations from the board, and why

- Busy animation has 12 frames instead of 4: the board's 4 key frames are kept (frames 1, 4, 7,
  10) with the same 800 ms loop and direction; the in-betweens make the spinner turn smoothly
  instead of jumping 30 degrees every 200 ms.
- Shadow: the board draws it with CSS, so it stays 2 px down / 3 px blur at every size. The
  cursor's shadow is part of the SVG and is designed at size 24 (matches the board's Sizes panel
  at 24); it scales with the pointer, so at 48 and 64 it is 2x and 2.7x the board's, and on the
  72 px cards (an illustration, not a cursor size) it is larger than the cards' CSS shadow.
  One shadow for all sizes keeps Wayland apps (SVG through KWin) and GTK 3 / XWayland apps
  (Xcursor) identical at every size.
- `move` is the board's 4-way arrow, which is also what KWin shows for Qt's DragMoveCursor during
  a drag-and-drop move (Breeze shows a closed hand there). KWin itself uses `grabbing` for
  interactive window moves and `all-scroll` for Qt's SizeAllCursor, which get their own drawings.
- Resize sides and corners (`top_side`, `top_left_corner`, `n-resize`, ...) reuse the board's
  double arrows instead of Breeze's single arrows with an edge bar.
- Only 6 light pointers are on the board; the other 31 light drawings are the same shapes with
  fill and outline swapped (coloured badges, red and the spinner keep their colours).

## Not verified / limits

- XWayland apps were not started (the virtual session runs KWin without Xwayland). They read the
  same Xcursor files through libXcursor, which the test checks directly.
- Cursor shapes are not recoloured by the accent colour (KWin does not support that).
- The login greeter (plasma-login-manager runs as user `plasmalogin`) cannot read themes in the
  user's HOME: phase 2 must copy both theme directories (with their symlinks) to
  `/usr/share/icons/` and set the greeter's `kcminputrc [Mouse] cursorTheme` (login-screen part).
  The lock screen runs in the user session and already uses the session cursor.

## Needs from other parts

- look-and-feel: already sets `cursorTheme=PlasmaFusion-cursors` for both Global Themes; nothing
  else needed. Optionally `cursorSize=24` if the Global Theme should also fix the size.
- device apply scripts (`tools/device/`): `fusion-config.sh` installs with `rsync -a` (symlinks
  kept) and applies the Global Theme, which selects `PlasmaFusion-cursors`; nothing else needed.
  `plasma-apply-cursortheme PlasmaFusion-cursors --size 24` only if the size must be forced.
- `tools/vsession/vsession.sh` (lead): the test session starts KWin with `env -i` and no
  `XDG_CONFIG_DIRS`, so settings a Global Theme writes to `~/.config/kdedefaults/` never reach
  KWin or the apps there (the cursor stayed `default`, the decoration stayed Breeze). Adding
  `XDG_CONFIG_DIRS="$PFV/home/.config/kdedefaults:/etc/xdg"` to the `env -i` line would match
  startplasma; until then `scenario-review.sh` copies the cursor and decoration keys itself.
- Phase 2 system-wide package: install both directories under `/usr/share/icons/` for the
  greeter; symlinks must survive packaging.

## Review (2026-09-29)

An independent review of this part: board values, build, formats, KWin/GTK/libXcursor contracts,
and integrated virtual sessions with every other part.

### What was checked

- Board (`Pointers.dc.html`, render `theme-parts-5`): the 12 card drawings use the board's path
  data verbatim; fills, 1.6 outlines, 4.4/2.0 line pairs, badge ring/disc radii (6.4/5.0),
  colours (`#1b2031`, `#5b9dff`, `#f2a65a`, `#3cc4b0`, `#3aa65b`, `#e5484d`), light-variant
  swaps (`lcl`, `a1l`), hotspots (the amber rings), busy key frames (rotation about 16,16.6 and
  25,25, clockwise, 800 ms). The cards at 72 px and the light panel at 48 px match the board to
  anti-aliasing (`review-board-compare.png`).
- The size ramp at real sizes (24/32/48/64 px) against the board's "Sizes" panel: this is where
  the part was wrong (below).
- KWin 6.7.5 source: `SvgCursorReader` (metadata keys, `defaultSize() * size / nominal_size`,
  hotspot scaling), `CursorTheme` discovery (`cursors_scalable` preferred, same-directory
  symlink aliases, `Inherits`), `CursorShape::name()`/alternatives, the drag cursors
  (`move`/`copy`/`grabbing`/`not-allowed`) and the reload on `notifyChange(5)`.
  plasma-workspace: `kcm_cursortheme` (sizes from `cursors/left_ptr`, `Example`),
  `plasma-apply-cursortheme --size` (size must be in that list), `KLookAndFeelManager`
  (a Global Theme writes the cursor theme to `kdedefaults/kcminputrc`).
- Names: every alias target compared with how Breeze and Adwaita group the same names; the only
  differences are deliberate (`move` = board 4-way arrow; Breeze maps `size-hor`/`size-ver`/...
  to the plain arrow, here they get resize arrows; `forbidden` = not-allowed).
- Build: `tools/build.sh` with all parts into `build/rcr/home` (all 12 steps pass); the cursor
  step writes only its two directories; `tests/test_cursors.py` passes (reproducible, 716 paths;
  596 libXcursor lookups; all Breeze and Adwaita names).
- All 37 drawings at the real size 24 px (Xcursor, zoomed 4x, hotspot pixel marked) on light and
  dark backgrounds, both themes (`review-all-24-dark.png`, `review-all-24-light.png`).
- Virtual sessions on the ThinkPad (prefix `rcr-`):
  - rcr-3, `scenario-review.sh`: full build, seed without kcminputrc. Applying
    `org.plasmafusion.dark.desktop` and `org.plasmafusion.light.desktop` each wrote
    `kdedefaults/kcminputrc [Mouse] cursorTheme=PlasmaFusion-cursors`; with that value in effect
    KWin reports `themeName: PlasmaFusion-cursors`. Pointer shot over the desktop, top bar, dock,
    title bar, a text field (I-beam) and the Aurorae window edges and corners (ew/ns/nwse resize
    shapes) in both Global Themes, then with `plasma-apply-cursortheme PlasmaFusion-Light-cursors
    --size 24` (`review-session-integrated.png`, full screens `review-session-dark-textfield.png`,
    `review-session-light-corner.png`, `review-session-lightptr-title.png`).
    plasmashell.log empty; no cursor or SVG lines in kwin.log.
  - rcr-4, `scenario-scaled.sh`: output scale 4/3 (the device setting, logical 1080x675). All 21
    Qt shapes (KWin SVG at device pixel ratio 4/3) and 28 GTK 3 names (Xcursor size 48 at
    buffer scale 2): same pointer size in both paths; hotspots measured from the screenshots
    (the arrow's outline starts on the pointer pixel)
    (`review-session-scale43-qt.png`, `review-session-scale43-gtk.png`).
  - rcr-5, `scenario-kcm.sh`: the cursor settings page lists both themes with previews from the
    new, larger Xcursor images and "Size: 24" (`review-session-kcm.png`).
  Log summary: `review-session-checks.txt`.

### What was fixed

- Shadow too weak at the real sizes (medium). The builder converted the 72 px cards' CSS shadow
  into canvas units, so at size 24 it was 0.67 px down with a 0.5 px blur: almost invisible, and on
  light windows the white outline merged with the background. The board's Sizes panel shows the
  pointer at 24 px with a clear 2 px / 3 px shadow. Now the shadow is designed at size 24
  (2.667 units down, sigma 2 units, opacity .35 = the Sizes panel) and matches the board at 24 and
  32 px (`review-size-ramp.png`: board / before / after).
- No room for the shadow (part of the fix above). The 32-unit canvas left 2.2 units beyond the
  arrow tips of ew/ns/move, so a board-sized shadow would have been cut off. The SVGs now have a
  4-unit margin (`viewBox -4 -4 40 40`, hotspots +4, Xcursor images 1.25 x nominal, e.g. 30 px at
  size 24), like Breeze's 32 px images for size 24. 4 units = 3 px at size 24, so edges stay on
  the pixel grid. Themes grew from 8.9 to 14 MB each.
- Verification tools updated for the new geometry: `gen_cursors.verify` checks the 40-unit SVG
  size and the Xcursor image sizes; `tests/test_cursors.py` checks canvas, `nominal_size`,
  image sizes and the shifted hotspots through libXcursor; `sheet.py` places the larger images by
  the margin.
- New session tests: `scenario-review.sh` (integrated, both Global Themes, window edges;
  with `edgewin.py` and `place.js`) and `scenario-scaled.sh` (scale 4/3).

### What remains

- The larger shadow scales with the pointer, so at 48/64 px it is heavier than the board's fixed
  CSS shadow (documented under Deviations).
- Virtual sessions do not read `kdedefaults` (see Needs, `tools/vsession/vsession.sh`), so a
  Global Theme alone does not change the cursor there; the real session is not affected.
- During a drag-and-drop move KWin asks for `move`, which is the board's 4-way arrow (Breeze and
  Adwaita show a hand or the arrow). Kept, because the board defines `move`.
- Qt's `UpArrowCursor` shows the ns double arrow on Wayland: QtWayland sends `n-resize`
  (cursor-shape-v1 has no up arrow). Breeze behaves the same; not fixable in a theme.
- XWayland apps and the login greeter were not exercised (unchanged from the builder's notes).

Reproduce the review sessions (from a directory on a local disk; `seed` = the full build plus
`pfv-cursor-test/` holding `generators/cursors/vsession/*.py` and `place.js`, without
`.config/kcminputrc` for rcr-3, with `[Mouse] cursorTheme=PlasmaFusion-cursors`,
`cursorSize=24` for rcr-4 and rcr-5):

```sh
tools/vsession/remote.sh rcr-3 generators/cursors/vsession/scenario-review.sh seed
tools/vsession/remote.sh rcr-4 generators/cursors/vsession/scenario-scaled.sh seed-with-kcminputrc
tools/vsession/remote.sh rcr-5 generators/cursors/vsession/scenario-kcm.sh seed-with-kcminputrc
```
