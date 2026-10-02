# Familiar app icons

Every installed app keeps its own icon, on a Plasma Fusion tile: people recognise their apps, and
the dock, the home screen, the launcher, the task switcher and the apps' own windows show the same
row of tiles. Owner decision 2026-10-01 after the design comparison (ICONS-BLEND.md on the shared
project memory: designed tiles, icons as installed, harmonized originals, familiar tiles).

Since 2026-10-02 the 336 apps with a designed tile of their own (docs/parts/icons.md, "Per-app
tiles") keep it in both modes; familiar icons are drawn for the other apps only.

## What a familiar icon is

A 64-unit Fusion tile (the AppIcon board's: radius 15, a 4-unit lip under a 60-unit base, a 9 %
white sheen on the top 28 units, a 1-unit 14 % white edge) holding the app's own artwork:

- **The original is already a tile** (a square, cover >= 0.96, or a rounded square, cover >= 0.88
  with one colour along the middle of its four sides; aspect 0.95-1.05; Konsole, System Settings,
  KOrganizer, Bitwarden, Kleopatra): it becomes the tile. Its corners take the tile's radius, gaps
  are filled with its side colour, a darker band (18 % black) marks the lip, the sheen and the edge
  go on top. The artwork keeps its proportions.
- **Any other original** keeps its shape and sits larger on a tile in its own main colour at 90 %
  lightness (the saturation-weighted mean hue of its saturated pixels). Logos with several hues
  (hue spread > 0.45: Chrome, Maps) and grey ones sit on the neutral `#eef1f8`. Keylines inside
  the tile: square 66 %, round 76 %, wide 76 % of the width, tall 74 % of the height, centred on the
  60-unit base.

Not done, on purpose: one grey or glass plate for every icon (macOS 26's "squircle jail", widely
criticised for making icons hard to tell apart), and redrawing or recolouring the artwork.

## How it works

`packages/appicons/plasma-fusion-app-icons` (installed in `~/.local/libexec/plasma-fusion/` by
fusion-config.sh, `/usr/libexec/plasma-fusion/` by the package):

1. Reads the visible desktop entries (data directories, Flatpak exports; the first file of a
   desktop id wins; NoDisplay/Hidden skipped) and their `Icon=` names, leaving out the names the
   theme draws with a designed tile (`designed-apps.txt` in the per-user copy of the
   `PlasmaFusion` theme, else the system one), and the names the theme hands back to Breeze or to
   apps' own icons (its `breeze/`, `hicolor/` and `flatpak/` folders; KMail's Import Wizard names
   `kontact-import-wizard`, a Breeze action in KMail's menus). A familiar icon built earlier for such
   a name is dropped.
2. Finds each original as Plasma would without Plasma Fusion: Breeze (48, 64, 32, scalable, ...),
   then hicolor (scalable, then the largest), then `pixmaps`. For the per-app tile (below) also an
   `Icon=` that is a file path, and any Breeze icon outside the app folders (Emoji Selector names
   `preferences-desktop-emoticons`).
3. Renders it with QtSvg (PySide6; what Plasma draws icons with) or rsvg-convert, measures the drawn
   box and its cover, picks the kind and the tile colour, and writes
   `apps/scalable/<name>.svg` in both Fusion themes of `~/.local/share/icons`: the artwork as an
   embedded PNG at 4x (256 px for a 64-unit tile), about 30 KiB per icon. Each Icon= name found among
   app icons gets a file under that name (what other programs look up); each app without a design
   also gets one under `plasmafusion_app.<desktop id>` with `_` for `-` (what the shell looks up; no
   dash, so the icon loader's dash fallback cannot answer it with another icon). File paths and
   generic Breeze names get only the per-app file, so the generic name keeps its meaning.
4. Writes the marker icon `plasmafusion-familiar` (kept for older shells), records what it built from which file and
   mtime (`~/.local/state/plasma-fusion/app-icons.json`) and sends KIconLoader's `iconChanged`.

A per-user icon file the tool would replace is kept in `~/.local/state/plasma-fusion/app-icons-backup`
and put back by `remove`. Only files carrying the tool's marker comment are ever deleted. The backup
is always the newest file a familiar icon hides, and when something else (a redeployed per-user copy
of the theme) has replaced a familiar icon since, that file stays and the out-of-date backup is
discarded; such a name is built again at the next refresh.

`plasma-fusion-app-icons.service` (user unit, enabled by fusion-config.sh) runs `watch`: a refresh
at login, then it sleeps on inotify watches of the application directories, the Plasma Fusion
theme roots (a theme update changes `designed-apps.txt`) and ~/.config (every
30 s a few stat calls where inotify is unavailable; a directory created later is picked up within
10 minutes). When an application directory's or plasmafusionrc's time changed (an rpm transaction,
a Flatpak install, a mode change) it waits 3 s for the burst to settle and runs `refresh` in a child
process, so the watcher itself stays small (8.3 MiB on the ThinkPad) and wakes only on changes.
`systemctl --user reload plasma-fusion-app-icons.service` refreshes at once.

Running programs keep the icons they already drew: neither KIconLoader's `iconChanged` (any group)
nor KGlobalSettings `notifyChange(IconChanged)` makes plasmashell draw an icon again while the theme
name stays the same (tested on the ThinkPad, 2026-10-02: no pixel of the dock changed). A newly
installed app is looked up for the first time when it shows up, by then usually after its familiar
icon exists (about 4 s after the install); a mode change shows in the shell after
`systemctl --user restart plasma-plasmashell.service` or the next login, in apps when they start again.

`FusionIconTile` (dock, launcher, home screen, window cards) looks an app up by its desktop id:
an id with a designed tile (`FusionIconNames.designed()`) shows that tile, whatever icon the desktop
entry names (KDebugSettings names `debug-run`, which the theme keeps for the action); otherwise the
per-app familiar tile when the tool made one (`familiar`); otherwise the app's own icon on the
neutral tile. Both lookups are hidden `Kirigami.Icon` probes, so with another icon theme active
nothing resolves and the tile behaves as before. `packages/common/tests/icontile.sh` checks the three
cases under PlasmaFusion and Breeze (offscreen, private bus without service activation).

## Commands

    plasma-fusion-app-icons refresh [--force] [--dry-run]
    plasma-fusion-app-icons watch
    plasma-fusion-app-icons remove     # the designed tiles again (until the next refresh in familiar mode)
    plasma-fusion-app-icons status

Mode: `plasmafusionrc [Icons] AppIcons=familiar` (default) or `designs`; in `designs` mode a refresh
removes the familiar icons. fusion-restore.sh stops the service and runs `remove`.

## Checks

`tools/build.d/89-app-icons.sh`: compile, the unit's key lines, `packages/appicons/tests/designed_test.py`
(a designed name gets no familiar icon; a file-path icon, a generic Breeze name and a name the theme
hands back get a per-app tile only; dropping a familiar icon puts the theme's link back, keeps a link that replaced it since, and
the backup is the newest file; standard library only),
`packages/appicons/tests/parse_test.py` (what the tool reads from other programs' files: a desktop
entry's first value of a key wins, other groups and hidden entries are left out; plasmafusionrc and
`designed-apps.txt` with bytes that are not UTF-8 are read, not a crash; standard library only),
`packages/appicons/tests/compose_test.py`
(a square and a rounded square become the tile; a one-colour circle gets a light tile in its hue; a
three-colour logo the neutral tile; a wide shape a plate).

Measured: laptop (Fedora 44, 87 visible apps) a full build in 4.9 s with QtSvg, 2.5 MiB per theme,
16 originals became the tile, 71 sit on a tinted tile, none failed; ThinkPad (90 apps) 2.3 s, 20
tiles of their own, 70 on a tinted tile, none failed. Switching to `designs` and back restored the
267 files of the per-user theme copy exactly (37 designed tiles had been kept in the backup).
