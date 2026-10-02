# Part: icons

Two freedesktop icon themes built from the design boards (Icons.dc.html, FileIcons.dc.html,
AppIcon.dc.html and the line icons used on the other boards):

| Theme | For | Inherits |
|---|---|---|
| `PlasmaFusion` ("Plasma Fusion") | light colour schemes | `breeze,hicolor` |
| `PlasmaFusion-Dark` ("Plasma Fusion Dark") | dark colour schemes | `breeze-dark,hicolor` |

Coloured art is identical in both themes. Symbolic art differs only in the default colours
written into the SVGs (what GTK and other non-KDE code sees); KDE recolours it from the
active colour scheme (`FollowsColorScheme=true`).

## What is in the themes

| Family | Drawings | Names per theme | Source |
|---|---|---|---|
| App tiles | 18 tiles + Fusion logo tile + logo mark, and 3 derived tiles (Archive, Document Viewer, Camera; STYLE-1) | 844 (with the per-app tiles) + 289 `-symbolic` twins | AppIcon.dc.html `renderVals()` ported 1:1; `-symbolic` twins use the one-colour app symbols of the Launcher/Main boards' icon table |
| Per-app tiles | 397 tiles, one per app, in the board's tile construction (2026-10-02 redesign and its round 3, "Per-app tiles" below) | 702 of the 844 | `apptiles/` |
| Places | 27 folders (the board's 10 + 17 derived symbols), 10 colour tints, 2 trash cans | 67 (coloured, 16 px, 22 px, `-symbolic`) | FileIcons.dc.html `folder()` |
| Devices | 12 board devices + 8 derived (laptop, speaker, microphone, webcam, gamepad, touchpad, tablet, scanner) | 59 (+ 64 `-symbolic`) | FileIcons.dc.html `devices[]` |
| File types | 820 pages: page + coloured extension tag, one per (kind, extension) | 1358 MIME icon names + 18 `-symbolic` | FileIcons.dc.html `file()` |
| Status | battery (every level, charging, power profile), Wi-Fi, wired, VPN, flight mode, volume, microphone, Bluetooth, notifications, night light, brightness, camera, weather, media player state, software updates, Vaults | 602 | FileIcons.dc.html status groups |
| Actions | the 24 symbolic icons of Icons.dc.html + the line icons of the other boards + a few derived | 324 | Icons.dc.html, Main, Launcher, QuickSettings, Popups, Controls, Login, Boot |
| Categories | menu categories (applications-*) | 26 | derived line icons |
| Emblems | the link badge `emblem-symbolic-link` at 16 and 22 px (pixel grid) and scalable (STYLE-1) | 1 (in `emblems/16`, `emblems/22`, `emblems/scalable`, and `@2x`/`@3x`) | derived |

In total 1301 coloured and 308 symbolic drawings answer 3973 icon names per theme; 578 further
names are handed back to Breeze and 150 to apps' own icons (147 hicolor, 3 Flatpak; see "Lookup
rules" below). About 3.8 MB per theme (apparent size; the per-app tiles are 0.73 MB of it); each theme holds its own copy of the coloured art, so either
one works without the other.

Tiles follow the board exactly: 64 x 64 tile, radius 15, 4-unit lip, 9 % sheen, 1-unit
14 % white edge, glyph layers g1/g2/s1/g3. Text (the calendar's `SEP` / `28`, file-type tags,
`SD`, `Aa`) is drawn as outlines of Manrope ExtraBold and Space Grotesk Bold, placed like the
board's CSS (flex centring, line-height 1, letter-spacing after every glyph).

## Files

```
generators/icons/
  gen_icons.py        builds both themes (Python standard library only); used by the build
  names.py            which drawing answers which icon name (apps, places, devices, actions, categories)
  art_tiles.py        app tiles and logo (AppIcon board)
  apptiles/           per-app tiles: kit.py (tile drawing), b_*.py (the design batches), apps.json
                      (the apps and their icon names)
  art_files.py        file types, folders, trash, devices (FileIcons board)
  art_symbolic.py     24-grid symbolic glyphs, status families, colour roles and default palettes
  svgkit.py           path helpers (rr/ci/el/gear ported from the boards), SVG writer
  textoutline.py      composes text from glyph outlines
  glyphs.json         glyph outlines, advances, kerning, metrics   <- make_textpaths.py (PySide6)
  mimetable.json      MIME icon name -> kind and tag label          <- make_mimetable.py
  outlines.json       filled outlines of every stroked glyph         <- make_outlines.py (PySide6)
  capture.json        Breeze names handed back to Breeze             <- make_capture.py
  validate.py         QtSvg checks and contact sheets (PySide6)
  compare_boards.py   renders board icons and diffs them against the board renders (PySide6, Pillow)
  coverage_report.py  installed apps and dock pins against the Fusion tiles (BACKLOG C8; informational)
  vsession-check.sh        private-session scenario: lookups, Dolphin, launcher, tray, System Settings, Nautilus
  vsession-globaltheme.sh  private-session scenario: the Global Theme applied, icons in context
  vsession-review.sh       private-session scenario: every part, dark or light, tray popup and file types
tools/build.d/30-icons.sh
```

The build reads only the repository (the four committed JSON tables); it needs Python 3 and no
PySide6, fonts or network. Output is byte-for-byte reproducible (checked by building twice).

## Build, install, apply

Build (writes only `$STAGE/.local/share/icons/PlasmaFusion` and `.../PlasmaFusion-Dark`):

```
bash tools/build.sh icons                     # -> stage/home/.local/share/icons/
STAGE=/some/home bash tools/build.sh icons
python3 generators/icons/gen_icons.py --out DIR [--copies]   # direct; --copies = no symlinks
```

Install per user: copy both directories to `~/.local/share/icons/` **with symlinks preserved**
(`rsync -a` or `cp -a`). Every lookup name is a relative link inside its own theme (into `art/` or
`glyphs/`); the `breeze/` hand-back links are absolute links into `/usr/share/icons/breeze` or
`breeze-dark`, the `hicolor/` ones into `/usr/share/icons/hicolor` (they dangle while their app is
not installed). The themes do not depend on each other. The SMB share cannot hold symlinks:
`--copies` exists only for transport, because it leaves out the Breeze hand-back links (System
Settings would then show the Settings tile for its `preferences-system-*` pages); install a build
made without `--copies`.

Apply:

* Global Theme (already in `packages/look-and-feel/*/contents/defaults`):
  `[kdeglobals][Icons] Theme=PlasmaFusion-Dark` (dark) / `Theme=PlasmaFusion` (light).
* By hand: `/usr/libexec/plasma-changeicons PlasmaFusion-Dark`, or
  `kwriteconfig6 --file kdeglobals --group Icons --key Theme PlasmaFusion-Dark` and restart apps
  (KIconLoader caches pixmaps per process).
* GTK apps follow through kde-gtk-config (`gtk-icon-theme-name` in `~/.config/gtk-{3,4}.0/settings.ini`).
* System-wide (phase 2, greeter): copy both directories to `/usr/share/icons/` with `cp -a`.
* Rollback: `/usr/libexec/plasma-changeicons breeze-dark` (or `breeze`), then remove the two directories.

No icon cache is shipped (GTK scans the directories; KDE does not use caches for user themes).

## Lookup rules and decisions

**Sizes.** Places and devices have fixed 16 and 22 px directories (plus `@2x`/`@3x` links, as
Breeze) holding monochrome line icons, and a scalable coloured directory from 24 px up. The
design's Files window (Main board) shows line icons in the sidebar at 16 px; the FileIcons board
shows the coloured folders. Dolphin's Places panel therefore shows the board's line icons, the
file view shows coloured folders. Verified at the ThinkPad's 4/3 scale: the 16/22 px requests hit
the `@2x` directories exactly and stay crisp.

**Symbolic art = filled outlines.** GTK 4 recolours `-symbolic` icons by forcing `fill` on every
path and ignores strokes, so stroked line art rendered as black blobs in Nautilus. Every 1.75 stroke
(round caps and joins) is converted to its filled outline with Qt's `QPainterPathStroker` (the
code QtSvg uses to draw strokes), so KDE and GTK render the same shapes. Colour roles use
`class="ColorScheme-Text"` etc. (KIconLoader) plus GTK's `warning`/`error`/`success` classes.
Dimmed segments (Wi-Fi arcs, volume waves) use `opacity=".28"` as on the board.

**Default colours** (from Colors.dc.html): light theme Text `#141827`, Neutral `#8f4f12`,
Negative `#b3262e`, Positive `#23703b`; dark theme Text `#e8ebf4`, Neutral `#f5c08c`, Negative
`#ff8a8f`, Positive `#7fd99c`. Fixed accents: charging bolt `#f7c948` (dark) / `#e0a008` (light),
unread-notification dot `#f2a65a` (both, as on MainLight).

**Dash fallback.** KIconLoader (kiconthemes 6.30 `findMatchingIcon`) runs the whole fallback chain
inside our theme before asking Breeze (`a-b-c` -> `a-b` -> `a`, `x-symbolic` -> `x`, MIME names ->
`<media>-x-generic`). Consequences handled here:

* every coloured name has a `-symbolic` twin with a line icon;
* families are shipped in full (battery levels x charging x power profile, Wi-Fi levels x
  locked/limited, volume and microphone states, weather);
* `make_capture.py` simulates the chain for every Breeze and hicolor name (laptop and ThinkPad
  inventories) and hands back the names our prefixes would swallow, e.g. all
  `preferences-system-*` settings icons (because `preferences-system` is the Settings tile),
  `image-missing`, `audio-on`, `input-touchpad-on/off`, `printer-error`, `document-edit-*`,
  `zoom-in-*`. They appear in `breeze/<dir>/` as exact-name links into `/usr/share/icons/breeze`
  (`breeze-dark` for the dark theme), with Breeze's own size metadata, so System Settings and
  the OSDs keep Breeze's icons. Names that only apps install (tray states such as
  `qbittorrent-tray`, an app's toolbar or `-symbolic` icons) appear in `hicolor/<dir>/` as links to
  the files the apps install in `/usr/share/icons/hicolor`; while an app is not installed its links
  dangle, and the icon loader skips a dangling link (checked with `kiconfinder6`), so the name
  falls back as before and nothing asks for it. System-wide Flatpak apps get the same in
  `flatpak/<dir>/`, absolute links into `/var/lib/flatpak/exports/share/icons/hicolor` (LocalSend's
  tray icon, Whatsie's `-symbolic`). 211 captured names deliberately keep our drawing
  (folder-*, drive-*, weather-*, unknown MIME types, ...).
* `org.gnome.Settings` is not mapped (it only runs under GNOME and its panel icons would fall back
  to our tile).

**File types.** Every MIME type in shared-mime-info on Fedora 44 (plus aliases and a few legacy
Breeze names) gets the board's page with a coloured tag showing its main extension (condensed when
long); the 12 board icons (DOC, XLS, PPT, PDF, PNG, MP3, MP4, ZIP, JS, TXT, TTF, ISO) come out of
the same table. Unknown types fall back to our generic pages (blank page, TXT, IMG, ...).

**Apps.** Text editors (KWrite, GNOME Text Editor, Kate, ...) share the Code tile: on the ThinkPad
KWrite fills the dock's Code slot. Notes apps (Marknote, KNotes, KJots, GNOME Notes) use the Notes
tile. Kontact shares the Mail tile. Apps without a designed tile (Okular, Ark, KDE Connect, GNOME
extras, Chrome web apps, ...) inherit Breeze/hicolor, as the task allows.

**Light backgrounds.** The board's file pages (`#f6f7fb`) and trash cans (`#e8ebf4`) have no
outline, so on the light scheme's white views (`[Colors:View] BackgroundNormal=255,255,255`) they
disappeared and only the coloured tag was left. Pages and trash cans carry a 1-unit rim of
`#1b2031` at 20 % opacity (the same in both themes); on the boards' dark backgrounds it is barely
visible (board difference for file types 4.0 -> 5.0).

**Tray and popups.** Names requested by the parts of the stock tray that stay visible in the Fusion
top bar, and by the popups next to it, are drawn in the board style: `media-playback-playing`,
`-paused`, `-stopped` (media controller), `update-none`, `update-low`, `update-medium`,
`update-high`, `update-busy` (Discover notifier), `plasmavault`, `plasmavault-error` (Vaults),
`media-playlist-shuffle`, `media-playlist-repeat`, `media-playlist-repeat-song`, `window-unpin`,
`edit-clear-locationbar-ltr/-rtl` (search field clear button), `folder-add`. `edit-copy` is two
pages; the board's Clipboard symbol answers `edit-paste` and `klipper-symbolic`.

**Launcher logo.** `start-here-kde-symbolic` (the launcher's `Plasmoid.icon`, also stock Kickoff)
and `plasmafusion-logo` give the logo mark from the Main board top bar and dock: three translucent
discs without the tile. `start-here-kde`, `start-here-kde-plasma` and `start-here` give the full
Fusion tile (Welcome Center).

## Names other parts can rely on

Standard names (use these first): app ids above, `user-home`, `folder-*`, `user-trash(-full)`,
`drive-*`, battery/Wi-Fi/volume families, `notification-active/inactive`, `notifications-disabled`,
`klipper-symbolic`, `kdeconnect-tray-symbolic`, `device-notifier-symbolic`, `system-search`,
`window-duplicate`, `go-home`, `download`, `edit-delete`, `system-lock-screen`, `system-shutdown`,
`system-reboot`, `system-suspend`, `system-log-out`, `configure`, `edit-copy`, `edit-paste`,
`view-split-left-right`, `window-minimize/maximize/restore/close`, `go-previous/next/up/down`,
`view-list-icons/details/tree`, `application-menu`, `media-playback-*`, `media-skip-*`,
`weather-*` (all with `-symbolic`).

Plasma Fusion names for glyphs that have no standard name: `plasmafusion-logo`,
`plasmafusion-overview`, `plasmafusion-search`, `plasmafusion-snap`, `plasmafusion-screenshot`,
`plasmafusion-phone`, `plasmafusion-clipboard`, `plasmafusion-settings`,
`plasmafusion-network-settings`, `plasmafusion-dark-style`, `plasmafusion-night-light`,
`plasmafusion-dnd`, `plasmafusion-power-mode`, `plasmafusion-appearance`, `plasmafusion-dock`,
`plasmafusion-topbar`, `plasmafusion-windows`, `plasmafusion-displays`, `plasmafusion-keyboard`,
`plasmafusion-accessibility`, `plasmafusion-weather`, `plasmafusion-discover`,
`plasmafusion-installed`, `plasmafusion-3d`, `plasmafusion-photography`, `plasmafusion-meta`,
`plasmafusion-grid`, `plasmafusion-list`, `plasmafusion-submit`, `plasmafusion-upload`
(each also as `-symbolic`). `gen_icons.py --out DIR --list-names` prints every shipped name.

## Maintainer tools (rerun when...)

| Tool | Rerun when | Needs |
|---|---|---|
| `make_textpaths.py` | fonts or the character set change | PySide6, `fonts/` |
| `make_mimetable.py` | shared-mime-info changes (Fedora update) | `/usr/share/mime/packages` |
| `make_outlines.py` | any symbolic glyph changes (the build stops with "run make_outlines.py" otherwise) | PySide6 |
| `make_capture.py [--extra names.txt] [--hicolor-files paths.txt]` | names change, breeze-icon-theme updates (built from 6.30.0), or new hicolor apps appear | installed Breeze/hicolor; `--extra` takes a name list from the device, `--hicolor-files` the hicolor paths of apps not installed here (`dnf repoquery -l` of their packages, `find /usr/share/icons/hicolor` on the device) |

`validate.py ICONS [--sheets DIR]` and `compare_boards.py ICONS RENDERS OUT` are the checks below.

## Verification

* `validate.py` on the stage: 2414 drawings (both themes, each with its own art) accepted by `QSvgRenderer`, rendered at
  16/24/32/48/128 px through `QImageReader` (KIconLoader's path) with no Qt warnings; every symbolic
  drawing passes a KIconLoader-style stylesheet replacement and all opaque pixels take the injected
  colours; no `<text>`, filters or external references; every lookup directory is listed in
  `index.theme`; no dangling links (also checked on the ThinkPad: 0).
* `compare_boards.py` against `icons-1.png`/`icons-2.png` (mean absolute colour difference over the
  icon, 0-255, after sub-pixel alignment): app tiles 2.0 (max 4.0), logo 1.4, places 1.7,
  devices 2.0, file types 4.0, status 4.0, symbolic 6.1 (thin 24 px lines; differences are
  anti-aliasing). Side-by-side sheets: `board-*.png`.
* `kiconfinder6` with private XDG dirs on the laptop and inside the ThinkPad sessions: tiles,
  folders, MIME pages and status icons resolve to our files; `preferences-system-windows`,
  `image-missing`, `input-touchpad-on` resolve to Breeze through `breeze/`
  (`thinkpad-session-kiconfinder.txt`).
* Private ThinkPad sessions (vsession names ic-1 to ic-5, Plasma 6.7.5, breeze-icon-theme 6.30.0;
  scenarios `generators/icons/vsession-check.sh` and `vsession-globaltheme.sh`, usage in their headers):
  dark (Fusion dark colours draft) and light: Dolphin home and a folder with 28 file types (icon and
  details views), stock Kickoff, system tray popup, System Settings (KCM icons stay Breeze),
  Nautilus (GTK 4: sidebar, header bar and window buttons use our symbolic set); dark at the
  ThinkPad's 4/3 scale (1920x1200 physical); and the Plasma Fusion Dark Global Theme with the other
  parts' dock, launcher and widgets (the dock shows the board's tile sequence). No icon or SVG
  warnings in plasmashell, KWin, Dolphin, System Settings or Nautilus logs.
* Two builds are byte-identical (files and link targets).

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/icons/`
(`board-*.png` + `board-scores.txt`, `sheet-*.png` contact sheets, `status-strip-both-variants.png`,
`weather-sheet.png`, `side-by-side-*.png`, `session-dark-*`, `session-light-*`,
`session-dark-scale4of3-*`, `session-integrated-dark-*`, `capture-report.txt`).

## Deviations from the boards

* Places and devices are monochrome at 16 and 22 px (the Files window board's sidebar), coloured
  from 24 px (the FileIcons board).
* Symbolic icons are filled outlines of the board's strokes (GTK 4, see above); the shapes are the same.
* The calendar tile shows the board's fixed `SEP 28`; an icon theme cannot show today's date.
* Folders keep the board's fixed blue instead of following the accent colour; Dolphin's
  "Assign folder color" gets tinted variants (red ... black) in the same construction.
* The Icons board's symbolic "Battery" (three bars) is not used; all battery names use the status
  board's fill-level battery (the top bar mock-up uses the fill level too).
* The board's warning and critical colours (`#f2c38a`, `#ff8a8f`) are applied through the colour
  scheme's Neutral/Negative roles, so Plasma shows the active scheme's values (`#f5c08c` in the
  dark scheme).
* Not on the boards, derived in the same style: 17 folder symbols, 8 devices, power-profile badges,
  VPN lock and "limited" badges, wired/VPN/flight-mode/hotspot, camera indicator, weather set,
  menu category icons, media player states, software updates, Vaults, and about 50 further
  actions (media, playlist modes, undo/redo, copy, cut, save, print, zoom, eye/eye-off, unpin, ...).
* File pages and trash cans have a faint 1-unit rim that the boards do not draw (see "Light
  backgrounds"); without it they vanish on white views.
* RTL-specific names (`*-rtl`) of our actions come from Breeze.

## Needs from other parts

* **vsession tool (lead):** `vsession.sh` does not put `~/.config/kdedefaults` in `XDG_CONFIG_DIRS`
  as `startplasma` does. `plasma-apply-lookandfeel` writes Global Theme values there (Plasma 6.7.5
  `KLookAndFeelManager::writeNewDefaults`; seen in the ic-5 run: `[Icons] Theme=PlasmaFusion-Dark`
  landed in `kdedefaults/kdeglobals`), so in a vsession the icon theme, fonts and other defaults of
  a Global Theme stay invisible. The integrated test restarted plasmashell with
  `XDG_CONFIG_DIRS="$HOME/.config/kdedefaults:/etc/xdg"`; exporting that in `inner.sh` before
  kded6/plasmashell start would fix it for every part.
* **Device apply script:** copy `~/.local/share/icons/PlasmaFusion*` with links preserved, and
  both themes together.
* **Global Theme:** already names `PlasmaFusion-Dark` / `PlasmaFusion`; nothing more needed.
* **Colour schemes:** status colours come from `ForegroundNeutral/Negative/Positive`; the board
  values are expected there.
* After a breeze-icon-theme update on Fedora, rerun `make_capture.py` so the hand-back links match
  the new Breeze file set (a stale link only means that one name falls back to our drawing).
* **Launcher:** Kontact shares the Mail tile (as the task's name map asks), so pinning both KMail and
  Kontact shows two identical Mail tiles (seen in the ric-dark launcher screenshot); pin one of them.
* **vsession tool (lead):** besides the kdedefaults point above, KWin in a vsession keeps looking up
  window icons (title bar, switcher) in hicolor/Breeze after `plasma-apply-lookandfeel` (seen in
  ric-dark, ric-dark2 with `plasma-changeicons`, and ric-light with a seeded kdeglobals), while the
  same session's plasmashell, Dolphin and `kiconfinder6` use Plasma Fusion. With a kdeglobals seeded
  before the session and no Global Theme applied (builder run ic-2) KWin shows the tiles. Check the
  title bar and Alt+Tab icons once in the real session after the device apply script runs.

## Review (2026-09-29, second pass)

**Checked.** Board sources and renders (AppIcon, Icons, FileIcons, and the icon tables of Main,
Launcher, QuickSettings, Popups) against the generator; the build into a private stage (icons alone
and all twelve parts); `validate.py` (QtSvg, 16-128 px, recolouring, index, links); `compare_boards.py`;
determinism (two builds identical, links included); `--copies`; every icon name requested by the
Plasma 6.7.5 sources (plasma-workspace, plasma-desktop, kdeplasma-addons, plasma-nm, plasma-pa,
bluedevil, powerdevil, kwin, libplasma), including the names built at run time (battery levels with
profiles, Wi-Fi strength with `-locked`/`-limited`, volume and microphone levels, media player
state), resolved through the real KIconLoader (`kiconfinder6` with private XDG dirs) and classified
as ours, handed back, Breeze, or captured by our dash fallback; the icon names the other parts'
QML uses; the Icon= names of every application on the laptop and the ThinkPad; tray and file icons
at 16/22/24/32/48 px on the dark and the light (white) view backgrounds; private ThinkPad sessions
with every part and the Global Theme applied, dark (ric-dark, ric-dark2) and light (ric-light):
desktop, launcher, tray popup, Dolphin home and file types in icon and details views. No icon or
SVG warnings in plasmashell, KWin or Dolphin logs; no dangling links on the ThinkPad.

**Fixed.**

* File pages and trash cans were invisible on the light scheme's white views (only the tag showed;
  an unknown file showed nothing). Added a faint rim (see "Light backgrounds").
* `PlasmaFusion-Dark/art` was a link into the light theme: removing "Plasma Fusion" in the icons
  settings page (allowed for user themes) or installing only the dark theme left every coloured
  icon of the dark theme dangling. Each theme now holds its own art.
* Tray items that stay visible in the Fusion top bar and the popups beside it used Breeze glyphs
  next to ours: media controller state, Discover's update states, Vaults, the media popup's shuffle
  and repeat buttons, the launcher's unpin action, the search-field clear button. Drawn in the
  board style (list under "Tray and popups").
* The app `-symbolic` twins used derived glyphs although the Launcher/Main boards define one-colour
  app symbols (globe with one latitude, `>_` terminal, code with slash, 2-radius mail and calendar,
  bag, speech bubble, map pin, cpu, crop). They now use the board's glyphs (`text-html`,
  `x-office-calendar`, `text-x-script` and `applications-development` follow).
* `edit-copy` showed a clipboard (every "Copy" menu entry) and `edit-paste` a clipboard with lines;
  `edit-copy` is now two pages and `edit-paste` the board's Clipboard.
* `battery-ups` fell back to our full battery (a UPS always shown full); handed back to Breeze.
  `folder-add` fell back to a plain folder; it now shows the new-folder glyph.
* `--copies` silently dropped the Breeze hand-back links; it now warns, and the install notes say
  to install a build with links.

**Remains.** Dialog and emblem icons (`dialog-*`, `emblem-*`), `preferences-*` settings icons,
`network-mobile-*` and the Display Configuration applet keep Breeze by design. The "Display
Configuration" entry of the tray popup therefore shows Breeze's glyph. Battery icons of mouse,
keyboard and phone come from Breeze while headphones, headset and gamepad use ours (Breeze has
the specific names only for the former). The integrated screenshots were taken before the
`edit-copy`/`edit-paste` change (not visible in them). KWin's own icon lookups in vsessions: see
"Needs from other parts".

Evidence: `review-*.png` in the evidence folder: `review-{dark,light}-0{1..6}-*.png` (sessions),
`review-light-pages-before-after.png`, `review-pages-trash-and-new-glyphs-on-white-and-dark.png`,
`review-new-tray-and-action-glyphs.png`, `review-app-symbolic-board-glyphs.png`,
`review-board-files.png`, `review-board-places.png`, `review-board-scores.txt` (apps 2.0, logo 1.4,
places 1.9, devices 2.0, file types 5.0, status 4.0, symbolic 6.1), `review-capture-report.txt`,
`review-thinkpad-kiconfinder-{dark,light}.txt`, `review-plasma-name-resolution-before.tsv`.


## STYLE-1 (2026-09-30)

### Link emblem (BACKLOG M3, S6)

`emblem-symbolic-link`, drawn by `art_files.emblem_link_svg()`: a white rounded badge (radius 4 at
16 px, 5.5 at 22 px) with a faint ink edge (rgba(20,24,39,.22)) and a curved "shortcut" arrow in
`ColorScheme-Highlight` (so KIconLoader recolours it with the accent colour; default #2f6fdf).
Pixel-grid drawings at 16 and 22 px, the 16 px drawing also as `emblems/scalable` (8-256), and the
`@2x`/`@3x` directories as links like `places/16`. Dolphin and Folder View draw it on the bottom-left
corner of every symlink, so desktop shortcuts made by "Add to Desktop" (a symlink, BACKLOG M3) carry
the Fusion badge instead of Breeze's grey chain. No board draws an emblem; the badge follows the
tile rules (rounded white plate, accent glyph). Checked in a private session: Konsole's symlinked
`.desktop` file and a link to a text file on the desktop show it (`o1st-a3`, evidence below).

### Coverage report and new tiles (BACKLOG C8)

`coverage_report.py APPS.json` lists every app the launcher shows (Type=Application, not
NoDisplay/Hidden, shown in KDE) and the dock pins (the dock's default `launchers`, with its
`launcherFallbacks`), and says how each icon is drawn: Fusion tile, Breeze, the app's own hicolor
icon, or missing. APPS.json is collected on the device, read-only:

```
ssh thinkpad-fedora 'python3 - <<"PY"
import configparser, glob, json, os
out = []
for d in ["/usr/share/applications", os.path.expanduser("~/.local/share/applications"),
          "/var/lib/flatpak/exports/share/applications"]:
    for f in sorted(glob.glob(d + "/*.desktop")):
        cp = configparser.RawConfigParser(strict=False, interpolation=None); cp.optionxform = str
        try: cp.read(f, encoding="utf-8"); e = cp["Desktop Entry"]
        except Exception: continue
        out.append({"file": f, "name": e.get("Name", ""), "icon": e.get("Icon", ""), "type": e.get("Type", ""),
                    "nodisplay": e.get("NoDisplay", "false").lower() == "true",
                    "hidden": e.get("Hidden", "false").lower() == "true",
                    "onlyshowin": e.get("OnlyShowIn", ""), "notshowin": e.get("NotShowIn", ""),
                    "categories": e.get("Categories", "")})
print(json.dumps(out))
PY' > apps.json
```

The report runs best on the device itself (its Breeze and hicolor directories). ThinkPad,
2026-09-30: 96 apps in the launcher; before this pass 34 had a Fusion tile, 32 used Breeze and
30 their own hicolor icon; all nine dock pins have Fusion tiles. The full table is in the evidence.

Added from it, in the board's tile construction (derived; `art_tiles.TILES`, `names.APPS`):

| Tile | Names | Look |
|---|---|---|
| `archive` | ark, org.kde.ark, utilities-file-archiver, file-roller, org.gnome.FileRoller, engrampa, xarchiver | amber tile, white lid over a cream box, slot |
| `reader` | okular, org.kde.okular, org.gnome.Papers, org.gnome.Evince, evince, atril, org.pwmt.zathura | red tile, white page with a folded corner and lines |
| `camera` | kamoso, org.kde.kamoso, org.gnome.Snapshot, org.gnome.Cheese, cheese | slate tile, light camera body, dark lens with a blue ring, amber flash dot |
| `notes` (existing) | + com.github.xournalpp.xournalpp, xournalpp, com.github.flxzt.rnote | the pen menu's note app |

`make_capture.py` was rerun after adding the names: `capture.json` is unchanged (no Breeze name is
swallowed by the new ones). Remaining apps without a Fusion tile keep their own Breeze or hicolor
icon (never a grey plate); the dock and the launcher draw those on the neutral Fusion tile
(`FusionIconTile`, BASE-1). The next candidates by visibility: LibreOffice (5 apps, own icons),
KDE Connect, Filelight / Disk Usage Analyzer, Help Center, Info Center, KolourPaint, Kleopatra.

Checks: `validate.py` passes (2424 drawings, both themes); two builds are byte-identical.

## Familiar app icons (2026-10-01)

The owner chose to keep every app's own icon, blended with Plasma Fusion, over the designed tiles
(design canvas and comparison: ICONS-BLEND.md on the shared project memory). The designed tiles
stay in the themes; `plasma-fusion-app-icons` (docs/parts/app-icons.md) draws each installed app's
own icon onto a Fusion tile in `~/.local/share/icons/PlasmaFusion{,-Dark}/apps/scalable`, which the
icon loader finds first. `plasmafusionrc [Icons] AppIcons=designs` brings the designed tiles back.
Since the per-app tiles (below), the tool leaves the apps that have one alone: familiar icons
remain only for apps without a design of their own.

## Per-app tiles (2026-10-02)

The owner preferred the design board's tiles (`design/previews/Main.webp`) to the familiar icons,
provided people still recognise their apps, and approved a per-app redesign: every app in Fedora
44's KDE catalogue (237: the apps.kde.org apps packaged for Fedora plus the installed core apps)
and 99 of the most common Linux apps (browsers, office, chat, media, games, development, system
tools), 336 apps in all. Design material on the shared project memory:
`artifacts/plasma-fusion/2026-10-02-icons/` (style guide, per-batch sheets with each original next
to its tile, review notes).

**Style.** The board's tile construction, unchanged: 64 units, radius 15, 4-unit lip, 9 % sheen on
the top 28 units, 1-unit 14 % white edge, glyph layers `g1` (fill), `g2` (even-odd fill), `s1`
(stroke), `g3` (even-odd fill) and `x` (small details drawn last). Per app:

* the base is the app's identity colour mapped to the board palette (saturated mid tones, the lip
  about 25 % darker; a light base only for marks that are several colours on white, like Chrome);
* the glyph keeps the silhouette and the signature colours of the app's own mark, simplified to
  1-3 shapes, white first, light tints of the base second, accents from the board's palette only,
  strokes at least 2.4 units, no detail under about 3 units (legible at 32 px), flat, no text
  except a mark that is a letter;
* apps whose own icon is a generic Breeze glyph get the board's category language plus the app's
  distinctive element, so no two apps look the same; families (LibreOffice, KDE PIM, the games)
  share a motif and keep their own colours;
* where a board tile already is the app's icon, the app uses it (Konsole: terminal, KCalc:
  calculator, Discover: software, NeoChat: chat, Spectacle: screenshot, System Monitor:
  monitor, KOrganizer: calendar, Plasma Camera: camera, KWeather: weather).

Third-party marks are drawn as flat, simplified versions of the brand marks so users find their
apps; the marks remain the trademarks of their owners, and no wordmarks are drawn.

**Sheen seam.** A glyph layer in the base colour (a cut-out that "erases" part of the glyph) used
to cover the sheen above it, leaving a visible step at unit 28. `apptiles/kit.py` paints such
layers with a gradient that carries the sheen (`url(#pf-sheen)`), so cut-outs match the tile at
every height (114 tiles).

**Names.** `apps.json` lists each app's id and the `Icon=` names that lead to it (its desktop
entries in Fedora 44, Flathub ids, common distribution names). `names.py` then:

* gives each per-app tile its key `app-<tile>` in `APPS`; the `-symbolic` twin is the category's
  line icon when one of the app's names was in a category before (Chrome: the browser globe),
  otherwise there is none;
* moves other names of the same app out of the category lists (dash variants such as
  `google-chrome-stable`, a plain name that ends an app's reverse-DNS id such as `vivaldi`, and a
  short alias list: `org.kde.kmail`, `net.thunderbird.Thunderbird`, `rhythmbox`, `vscode`,
  `visual-studio-code`, `code-oss`, `vscodium`), so the exact name the loader finds first is the
  app's own tile (`names.ALIAS_MOVES`, 15 names);
* keeps generic names that a few apps use as their `Icon=` with their own meaning:
  `camera-photo`, `system-search`, `applications-development`, `debug-run`,
  `preferences-desktop-theme`, `start-here-kde-plasma` (Kickoff's own icon); those apps' ids still
  get their tiles;
* `kontact` is claimed by Kontact and PIM Data Exporter; Kontact keeps it.

The names were checked against the `Icon=` names apps really use: the desktop entries on the
laptop and the ThinkPad, and the app icons each app's Fedora package installs in hicolor
(`dnf repoquery -l`). 59 KDE apps gained the short name their desktop entry uses (`krita`, `kmines`,
`plasmadiscover`, `kdeconnect`, `heaptrack`, ...), `kmail` went from the Account Wizard (which
borrows it) to KMail, and 13 common apps gained their native package names (`bitwarden`,
`proton-vpn-logo`, `ardour8`, `lmms`, `pinta`, `Nextcloud`, ...). Icons a package installs among
its app icons for its own use (`labplot-*`, `parley-*`, `akregator_empty`, `skrooge-black`) are not
app names. `keepassxc` stays out: KeePassXC's tray icons (`keepassxc-locked`,
`keepassxc-monochrome-*`) would fall back to the tile; the Flatpak id has it.

`names.DESIGNED` (722 names since round 3: the per-app names and the board-mapped apps' names) is written into
each theme as `designed-apps.txt` and into `FusionIconNames.js` as `designed()`: familiar app
icons skip these names, and `FusionIconTile.familiar` is false for them (so the dock's date stays on
KOrganizer's calendar tile with familiar icons on).

**Capture.** `make_capture.py` was rerun with the ThinkPad's icon inventory and the hicolor paths
of the apps' Fedora packages and of the ThinkPad: 205 more Breeze names (496 links, one per size
directory) are handed back, all app-specific action icons that the new short app names would
otherwise answer by the dash fallback (`labplot-*` 102, `kdenlive-*` 38, VS Code's `code` against
Breeze's `code-block`, `code-class`, ... 12, `kruler-*` 9, `minuet-*`, `virtualbox-*`, `kmouth-*` 8
each), and 87 names only apps install are handed back to their hicolor icons (new, see "Lookup
rules"): tray states (`qbittorrent-tray*`, `kasts-tray-*`, `org.kde.CrowTranslate-tray-*`,
Evolution's alarm notifier), Remmina's 40 toolbar icons, `-symbolic` icons (LibreOffice, Inkscape,
Meld, Blender, Flatseal, Bottles, ...), `labplot-*` and `parley-*` extras.
No captured name is left without a file.

Checks: `validate.py` passes (3076 drawings, both themes); two builds are byte-identical; a sample
of 40 names rendered from the built theme at 128 and 32 px (Chrome and its dash variants, Firefox
and `firefox-esr`, KMail, Thunderbird, VS Code, VSCodium, Vivaldi, Steam, Discord, Telegram,
Kdenlive, Krita, the board-mapped apps, LibreOffice, Rhythmbox, KPatience) shows each app's tile;
`kiconfinder6` on the built theme finds `kmail`, `org.kde.kmail2`, `krita`, `firefox` and
`google-chrome-stable` as tiles, `libreoffice-calc-symbolic` as LibreOffice's own icon, `debug-run`
and `code-block` in Breeze.

### Round 3 (2026-10-02)

After the redesign the owner asked for every app on both machines to have a designed tile, so that
familiar icons only cover apps installed later. 71 more apps, approved by the owner as designed
(canvas boards "Round 3: ..." in the icon canvas; material and review in `build/icons3` on the
laptop: STYLE.md with the round-3 rules, REVIEW.md, batches):

* the visible apps without a design on the laptop and the ThinkPad (65 desktop entries): the GNOME
  apps (Files, Calculator, Calendar, Characters, Clocks, Contacts, Connections, Disk Usage Analyzer,
  Fonts, Logs, Help, Image Viewer, Maps, Document Viewer, Terminal (Ptyxis), Settings, Video
  Player, Document Scanner, Camera, Software, System Monitor, Text Editor, Tour, Weather, Audio
  Player, Sound Recorder, Color Profile Viewer), Fedora and KDE system tools (Firewall, Media
  Writer, Problem Reporting, Parental Controls, Input Method Selector, SELinux Troubleshooter,
  Rygel, Remote Viewer, htop, Crashed Processes Viewer, Emoji Selector, KMail Import Wizard, KTnef,
  GnuPG Log Viewer), Wine's tools (one family: each tool's object with Wine's glass) and the
  owner's Windows 11 launcher, and the owner's own apps (ChatGPT, OpenCode, Irlume, Sunshine, Gear
  Lever, Paseo, ZCode, Shadow PC, Xournal++, Qt Designer, Qt Linguist);
* the candidates named in round 2: Ghostty, WezTerm, Zed, Emacs, Neovim, Wireshark, Docker
  Desktop, 1Password, Proton Mail (Ghostty and Docker Desktop drawn from their known marks, with no
  original at hand).

Rule added for round 3: one app, one look. No app reuses a board tile another app already stands
for, so a GNOME app and its KDE counterpart (Files and Dolphin, Calculator and KCalc, Ptyxis and
Konsole, Software and Discover) are told apart at a glance. The reviewer compared the 71 new tiles
with each other and with the 326 approved ones at 32 px and recoloured 9 that came too close (Text
Editor amber, Notepad pink, Crashed Processes Viewer orange, Ptyxis blue, ...). Generic names stay
with their meaning: Emoji Selector, Crashed Processes Viewer, KMail Import Wizard and the Windows 11
launcher name generic icons, so their tiles are filed under their desktop ids only (the shell looks
tiles up by desktop id). `nautilus` moved from the files category to GNOME Files. The capture was
rerun: GNOME Settings' panel icons (`org.gnome.Settings-*-symbolic`) and the other `-symbolic`
icons of the new apps are handed back to their hicolor files.

Checks: `validate.py` passes (3218 drawings, both themes); two builds are byte-identical; 32 names
rendered from the built theme (GNOME apps, Wine, the owner's apps, the candidates) show their tiles.
