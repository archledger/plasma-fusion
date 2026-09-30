# Settings module: `kcm_plasmafusion` (System Settings > Appearance & Style > Plasma Fusion)

Status: built as the x86_64 RPM `plasma-fusion-settings` in the Fedora 44 build container on the
ThinkPad, checked offline and in private virtual sessions on the ThinkPad (dark and light, with and
without the Plasma Fusion window decoration). Not installed system-wide (the reviewer does that).
Phase 3. Last edited 2026-09-29.

## What it is

The "Appearance" page of the Main / MainLight boards (`<section aria-label="Appearance settings">`,
renders desktop-dark-1 / desktop-light-1) as a System Settings module: a C++
`KQuickManagedConfigModule` plugin with a Kirigami / KCMUtils QML page in the Plasma Fusion look.

| Section | Control | Written on Apply |
|---|---|---|
| Style | Light / Dark / Follow sunset cards (124 x 72 previews) | Light, Dark: `plasma-apply-lookandfeel --apply org.plasmafusion.{light,dark}.desktop` after kdeglobals `[KDE] DefaultLightLookAndFeel=org.plasmafusion.light.desktop`, `DefaultDarkLookAndFeel=org.plasmafusion.dark.desktop`, `AutomaticLookAndFeel=false`. Follow sunset: the same pair plus `AutomaticLookAndFeel=true` (the keys `tools/device/fusion-config.sh --auto` sets); Plasma's `lookandfeelautoswitcher` kded module then applies the theme for the time of day at once and switches at dawn and dusk |
| Accent color | Blue, Teal, Green, Amber, Orange, Pink, Violet swatches; From wallpaper | the Colors page's keys in kdeglobals `[General]`: Blue = the colour scheme's own accent (`AccentColor` and `accentColorFromWallpaper` removed; #2f6fdf in both Plasma Fusion schemes, with their own focus / hover / link colours); a swatch = `AccentColor` and `LastUsedCustomAccentColor` = the board colour (#3cc4b0, #3aa65b, #f2a65a, #e8743b, #d6457a, #9b7bf0); From wallpaper = `accentColorFromWallpaper=true` and `AccentColor` = the colour Plasma takes from the wallpaper (`org.kde.PlasmaShell.color`). Then `plasma-apply-colorscheme --accent-color <colour or transparent>` writes the colour scheme into kdeglobals again with the accent and notifies applications, as the Colors page does |
| Window buttons | Right · glyphs / Left · circles / Show on hover | `~/.config/plasmafusionrc [Decoration] ButtonStyle = RightGlyphs / LeftCircles / ShowOnHover` and kwinrc `[org.kde.kdecoration2]` (below), then KWin reconfigure |
| (switches) | Magnify dock icons on hover | the `[General] magnify` key of every `org.plasmafusion.dock` widget, through `org.kde.PlasmaShell.evaluateScript` (`writeConfig` goes through the widget's configuration scheme, so the running dock follows at once) |
| | Global menu in the top bar | adds `org.kde.plasma.appmenu` right after `org.plasmafusion.appname` in the panel that holds it (inserted at that position, not added and moved), or removes it; evaluateScript |
| | Hot corner opens Overview | kwinrc `[Effect-overview] BorderActivate` 7 (top-left corner) or 9 (none), as fusion-config.sh; KWin reconfigure and `reconfigureEffect overview` |

Window decoration written with the buttons (and again after Light / Dark, because a Global Theme
brings its own decoration):

| Decoration installed? | kwinrc `[org.kde.kdecoration2]` |
|---|---|
| `org.plasmafusion.decoration` found in `org.kde.kdecoration3` plugins | `library=org.plasmafusion.decoration`, `theme=` (empty), `NoPlugin=false`; button lists kept (the decoration draws its left circles itself), except that the left-circles lists `XIA` / `_` are put back to `M` / `IAX` when leaving Left · circles |
| no (Aurorae fallback, phase 1 decoration part) | `library=org.kde.kwin.aurorae.v2`, `theme=__aurorae__svg__PlasmaFusion{Dark,Light}` for Right · glyphs and Show on hover, `...-Left` for Left · circles (variant from the current Global Theme, else the colour scheme's brightness), `ButtonsOnLeft=M` / `ButtonsOnRight=IAX`, or `XIA` / `_` for Left · circles |

`SnapLayoutsOnHover` has no control on the board, so the page never writes it (default `true`).

## Files

| Path | What |
|---|---|
| `packages/kcm-cpp/CMakeLists.txt`, `src/CMakeLists.txt` | ECM / KCMUtils project (`kcmutils_add_qml_kcm`: plugin, QML as resources, generated `kcm_plasmafusion.desktop`) |
| `src/kcm.h`, `src/kcm.cpp` | `PlasmaFusionKcm`: state, load / save / defaults, the writes above |
| `src/kcm_plasmafusion.json` | plugin metadata: name "Plasma Fusion", icon `plasmafusion-logo`, `X-KDE-System-Settings-Parent-Category: appearance`, weight 1 (first in Appearance & Style), keywords |
| `src/ui/main.qml` | the page (`KCM.SimpleKCM`) |
| `src/ui/FusionPalette.qml` | board colours dark / light; accent-dependent ones from the colour scheme |
| `src/ui/SectionTitle.qml`, `StyleCard.qml`, `Swatch.qml`, `WallpaperPill.qml`, `Segmented.qml`, `ToggleRow.qml` | the board's controls |
| `icons/plasmafusion-logo.svg` | the logo mark (three discs), installed as hicolor `apps/plasmafusion-logo` (CC-BY-SA-4.0) |
| `plasma-fusion-settings.spec` | RPM spec (Fedora 44, `%cmake_kf6`) |
| `build-rpm.sh`, `container-build.sh` | build in the container on the ThinkPad, fetch RPMs and an unpacked root |
| `LICENSES/` | GPL-2.0-or-later (code), CC-BY-SA-4.0 (icon) |
| `tests/` | test tooling, not installed: `offscreen_preview.py` (renders the QML with a stand-in module, laptop), `make-seed.sh`, `session-common.sh`, `scenario-look.sh`, `scenario-interact.sh`, `scenario-decoration.sh`, `scenario-sunset.sh` |

## Build

```
packages/kcm-cpp/build-rpm.sh [OUTDIR]          # default OUTDIR build/kcm-cpp
```

It packs `CMakeLists.txt src icons LICENSES` into a reproducible tarball, copies it with the spec to
`/tmp/pfv-kcm-build` on the ThinkPad (`PF_REMOTE_DIR`, must be below `/tmp/pfv-`), and runs
`nice -n 10 podman run --rm --network=none -v DIR:/work:Z localhost/plasma-fusion-build:f44-6.7.5
bash /work/container-build.sh` (`rpmbuild -ba`, `-j6`). OUTDIR gets `RPMS/x86_64/`
(`plasma-fusion-settings-1.0.0-1.fc44.x86_64.rpm` plus debuginfo / debugsource), `SRPMS/`,
`build.log` (no compiler warnings with KDE's `-Wall -Wextra` set) and `root/` (the RPM unpacked,
for test sessions). About 10 s.

Package contents:

```
/usr/lib64/qt6/plugins/plasma/kcms/systemsettings/kcm_plasmafusion.so
/usr/share/applications/kcm_plasmafusion.desktop      (Exec=systemsettings kcm_plasmafusion, NoDisplay)
/usr/share/icons/hicolor/scalable/apps/plasmafusion-logo.svg
/usr/share/licenses/plasma-fusion-settings/{GPL-2.0-or-later,CC-BY-SA-4.0}.txt
```

Requires `plasma-systemsettings`, `plasma-workspace` (`plasma-apply-lookandfeel`,
`plasma-apply-colorscheme`, the accent-colour and automatic light/dark kded modules),
`kf6-kirigami`, `kf6-kcmutils`, `qt6-qtdeclarative`; all 27 requirements resolve on the ThinkPad
(checked with `rpm -q --whatprovides`).

## Install, open, roll back (reviewer / real session)

```
sudo dnf install ./plasma-fusion-settings-1.0.0-1.fc44.x86_64.rpm
systemsettings kcm_plasmafusion          # or System Settings > Appearance & Style > Plasma Fusion
kcmshell6 kcm_plasmafusion               # the page alone
sudo dnf remove plasma-fusion-settings   # rollback of the package
```

The package changes nothing by being installed. Apply writes only the keys listed above;
`tools/device/fusion-restore.sh` restores kdeglobals, kwinrc and the shell layout from a
fusion-config.sh backup; `~/.config/plasmafusionrc` is new (delete it to undo; see "Needs").

## Behaviour

- Load: every value is read from the session when the page opens (kdeglobals, kwinrc,
  plasmafusionrc; the dock and top bar through one evaluateScript call, asynchronously; the two
  switches are disabled for that moment). Style shows nothing chosen when the current Global Theme
  is not Plasma Fusion (or automatic switching uses other themes). An accent colour that is not a
  board swatch shows no swatch chosen and is kept.
- Nothing is written until Apply (checked: the state files before and after a pending change are
  identical). Reset reads everything again; Defaults = Dark, Blue (scheme accent), Right · glyphs,
  the Plasma Fusion decoration when it is installed, magnify on, global menu on, hot corner off.
  Apply writes only what changed, in this order: Style, accent (on top of the scheme the style just
  applied), window buttons and hot corner (one KWin reconfigure), dock, top bar.
- Light / Dark run `plasma-apply-lookandfeel` synchronously, like the Global Theme page applies a
  theme: System Settings waits about 1-2 s.
- "From wallpaper" asks Plasma for the colour when chosen (a read: Plasma's own accent service
  only applies it when `accentColorFromWallpaper` is set) and shows it as the ring around the pill;
  Plasma keeps updating it when the wallpaper changes. The Plasma Fusion wallpaper declares
  `#2F6FDF` as its accent colour, so "From wallpaper" on it gives the board blue (as an explicit
  accent).
- With the Plasma Fusion decoration installed but another decoration in use, a note with a
  "Use It" button appears under the window buttons. "Show on hover" without that decoration shows a
  note that the buttons stay visible (the Aurorae themes cannot hide them).
- Follow sunset: when Plasma switches the Global Theme while the page is open (it does so right
  after Apply when the other variant is due), the Global Theme brings its own decoration; the page
  notices the switch (LookAndFeelPackage notification, checks at 1.5 / 3 / 6 / 10 s) and writes the
  chosen window buttons again. Verified with and without the decoration (see Verification).
  Switches at dawn and dusk while the page is closed are not covered (see "Needs").
- Changes made elsewhere (quick-settings Dark style tile, Colors page, automatic switching) show up
  on the open page while nothing is pending (KConfigWatcher on kdeglobals and kwinrc).
- Errors (a tool failed, a theme is missing, the shell did not answer) are shown in an inline
  message at the top of the page; the dock / global-menu switches say so when the Plasma Fusion
  dock or top bar is not on the desktop.
- Keyboard: Tab reaches every card, swatch, pill, segment and switch row; Space / Enter chooses;
  Left / Right move within the segmented control; 2 px focus ring in the scheme's focus colour
  (outside the selection ring on a chosen swatch). Accessible roles and names are set (radio
  buttons, check boxes, groups, headings).

## Look (board values, logical px)

| Board (Main.dc.html / MainLight.dc.html) | Implementation |
|---|---|
| content padding 20 / 24, sections 18 apart, title to content 10 | `SimpleKCM` paddings 20 / 24, `ColumnLayout` spacing 18 / 10; section titles laid out as 16 px lines (the CSS line box is 16.4 px), so rows land on the board's: measured card top 27, segmented control 239, first switch 297 in board and session |
| section title 12 px ExtraBold #a3abc2 / #5b6278 | same (static Manrope ExtraBold via the system font family) |
| cards 124 x 72, radius 10, 2 px border rgba(255,255,255,.1) / rgba(20,24,39,.1), selected #5b9dff / #2f6fdf; bar 8 px, window 62 x 36 at 14,16 radius 5 with 0 2 6 shadow, dock 48 x 8 radius 4 at 5 from the bottom; sunset card halves 60 + 60 with a 46 x 36 window at 38 | same geometry (contents in the 120 x 68 padding box, per-corner radii); selected border = the scheme's DecorationHover (dark, #5b9dff) / DecorationFocus (light, #2f6fdf), so it follows an accent; measured exact |
| card label 12 px, #cdd3e4 / #3a4157, chosen 800 #cfe0ff / #1d4fb0 | same; with another accent: derived from it |
| swatches 26 px, 10 apart; chosen: 2 px page-colour gap and 2 px ring | same; hover grows the swatch to 1.08 |
| "From wallpaper" 26 px pill, padding 0 10, 1 px dashed rgba(255,255,255,.3) / rgba(20,24,39,.3), 11.5 px 700 | same (Canvas, 2 px dashes, 1 px gaps as the browser draws them); chosen: the swatch ring in the wallpaper colour, solid edge |
| segmented 34 px, padding and gap 3, radius 10, rgba(255,255,255,.06); segments radius 7, flex widths; chosen #2f6fdf with white 12 px 800, others 12 px 600 #cdd3e4 / #3a4157 | same; widths = text width (measured at 800) + an equal share of the rest; chosen = Selection background and text |
| switch rows 40 px, 13 px text, 1 px rgba(...,.06) lines; switch 40 x 22, knob 18 at 2 px, on #2f6fdf, off rgba(255,255,255,.18) knob #e8ebf4 / rgba(20,24,39,.18) knob white with 0 1 3 shadow | same; animated knob |

## Verification

- `qmllint` (Qt 6.11.2) on every QML file: clean apart from the usual unqualified `kcm` / `i18n`
  context names.
- Offscreen render on the laptop (`tests/offscreen_preview.py`, system PySide6 6.11.2, Kirigami,
  KDE platform theme, a kdeglobals with the Plasma Fusion scheme and fonts) at the board's pane
  width: `sbs-{dark,light}-board-vs-render-2x.png`.
- Build: 0 compiler warnings; RPM requirements all present on the ThinkPad.
- Virtual sessions on the ThinkPad (prefix `km-`; the whole Fusion stage installed with
  `fusion-config.sh --install`, the module from the unpacked RPM through `QT_PLUGIN_PATH` and
  `XDG_DATA_DIRS` in `.config/pfv-env`; pointer and keyboard through `pfinput`):

  ```
  W=build/km                                             # any scratch directory
  packages/kcm-cpp/build-rpm.sh $W/kcm
  STAGE=$W/home PF_WALLPAPER_SIZES=quick tools/build.sh
  packages/kcm-cpp/tests/make-seed.sh $W/home $W/kcm/root $W/seed-12 km-12 dark
  (cd $W && ../../tools/vsession/remote.sh km-12 ../../packages/kcm-cpp/tests/scenario-interact.sh seed-12 1440x900 360)
  # km-10 light / km-11 dark: scenario-look.sh; km-13: scenario-decoration.sh with the decoration
  # (make-seed.sh ... dark <dir with org.kde.kdecoration3/org.plasmafusion.decoration.so>);
  # km-7 / km-8: scenario-sunset.sh with / without the decoration
  ```

  - km-11 / km-10 (look): the page in System Settings under Appearance & Style (first entry, logo
    icon) and in kcmshell6, dark and light; state loaded correctly; keyboard: Tab to the first card,
    on to Teal, Space chooses it, Reset.
  - km-12 (every setting with the pointer, then Apply, state recorded after each step):
    Teal (pending: nothing written; Reset restores; applied: `AccentColor=60,196,176`, Selection
    51,148,142, the page and all applications teal) → Left · circles (`-Left` Aurorae theme,
    `XIA` / `_`, `ButtonStyle=LeftCircles`, title bars with left circles) → magnify off, global menu
    off, hot corner on (dock stops magnifying; Dolphin's menu gone from the top bar; the top-left
    corner opens Overview; `BorderActivate=7`) → Light (Global Theme applied, teal and the left
    circles kept: `PlasmaFusionLight-Left`) → From wallpaper (`accentColorFromWallpaper=true`,
    `AccentColor=47,111,223` from the wallpaper's declared colour) → Show on hover → Follow sunset
    (`AutomaticLookAndFeel=true`, Plasma picked the variant for the time of day) → page closed and
    reopened (every value read back) → Defaults + Apply (Dark, scheme accent, right glyphs,
    magnify on, global menu back right after the app name with the clock pill still centred, hot
    corner off).
  - km-13 (decoration installed): "Use It" → `library=org.plasmafusion.decoration`, empty theme,
    `ButtonStyle=RightGlyphs`; Left · circles; Show on hover (buttons hidden away from the title
    bar, shown over it); Light keeps the Plasma Fusion decoration; Defaults.
  - km-7 / km-8 (Follow sunset after Left · circles, Dark → Plasma switched to Light): the page put
    back `org.plasmafusion.decoration` (km-7) and `PlasmaFusionLight-Left` (km-8) after the
    switch replaced them.
  - No core dumps from these sessions (`coredumpctl list --since 17:10`; the entries of the same
    period belong to other agents' sessions and SSH calls: plasma-login greeter, perf-pilot
    sessions, `kscreen-doctor`, `kstart --help`).

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/kcm-cpp/`:
`sbs-{dark,light}-board-vs-session.png` (board pane left, the page in System Settings right),
`sbs-{dark,light}-board-vs-render-2x.png`, `session-{dark,light}-{systemsettings,kcmshell}.png`,
`keyboard-{dark,light}-*.png`, `dock-magnify-on-off.png`, `topbar-global-menu-off-on.png`,
`interact/` (km-12 screenshots and `state-*.txt`), `decoration/` (km-13), `follow-sunset/`
(km-7, km-8), `rpm/` (RPM, SRPM, build log, SHA256SUMS).

## Deviations from the board, with reasons

- The board's window is System Settings itself: its sidebar sections (Desktop & Dock, Top bar,
  Windows, Workspaces, Notifications, Displays) are not part of this module. The page is one
  module under Appearance & Style with System Settings' own header ("Plasma Fusion") and its
  Defaults / Reset / Apply footer; the board shows instant changes without buttons.
- The content column stops at 560 px (the board's is 420 px in its 652 px window), so in a wide
  System Settings window the segmented control and switch rows are wider than on the board;
  left-aligned like the board.
- Blue means the colour scheme's own accent (#2f6fdf with its tuned focus, hover and link colours)
  and is drawn #5b9dff as on the board; the other swatches become Plasma's accent colour, and
  Plasma (not the board) derives the selection colour from it (70 % accent over the view
  background, e.g. teal → 51,148,142 dark, 118,213,199 light with black selected text).
- States the board does not draw: "From wallpaper" chosen (swatch ring in the wallpaper colour),
  hover on cards, swatches and segments, keyboard focus rings, the notes described above.
- Text uses the session's font rendering (subpixel antialiasing), the board's is greyscale; the
  11.5 px pill text is about 4 px narrower in total.
- Follow sunset relies on Plasma's automatic light/dark switching (its schedule, idle handling
  and location), not on a Plasma Fusion service.

## Needs from other parts

- Look-and-feel (Global Themes), medium: both Global Themes set `[kwinrc][org.kde.kdecoration2]
  library=org.kde.kwin.aurorae.v2` and the Aurorae theme, and every Global Theme apply writes them
  to kdedefaults and removes the user's values. Plasma's automatic switching (Follow sunset) applies
  the Global Theme at dawn and dusk without this page, so the chosen window buttons are lost then:
  with the Plasma Fusion decoration the title bars go back to Aurorae, with the Aurorae fallback and
  Left · circles the right-hand theme is shown with the left-circles button lists. Once the
  decoration package is part of the install, name `library=org.plasmafusion.decoration` with an
  empty `theme` in both Global Themes (the decoration follows the colour scheme, and plasmafusionrc
  is not touched by a Global Theme). The page itself re-applies the buttons whenever it applies a
  theme and while it is open.
- Device scripts (`tools/device/fusion-config.sh` / `fusion-restore.sh`), low: add
  `plasmafusionrc` to the backed-up files so a restore also removes the window-button choice.
- Dock (observation, low): in the virtual sessions the name pill and the magnification stay after
  the pointer jumps off the dock (absolute EIS motion) until it comes back; worth one check with a
  real mouse.
- Lead: install the RPM after review (commands above); the module needs no other change on the
  device.

## ThinkPad changes made by this part

None outside `/tmp/pfv-*` and `/var/tmp/pfv-*`: no sudo, no system files, the RPM is not installed,
the real session untouched. Build scratch `/tmp/pfv-km-build` (tarball, rpmbuild tree) and virtual
sessions `/tmp/pfv-km-1..12` (earlier tooling) and `/var/tmp/pfv-km-*` (removed by remote.sh); the
podman containers ran with `--rm` (no image built or pulled; the SELinux relabel of `:Z` applies
only to the scratch directory). All removed at the end.
