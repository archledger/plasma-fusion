# Device scripts: configure, upgrade and undo the real session (DEVICE-1)

Status: built and tested in private sessions on the ThinkPad against stand-ins for the parts other
lanes are still building (see Verification; one open item, Meta+N); not run in the real session
(the lead deploys).
Last edited 2026-09-30.

Covers PLAN.md (2026-09-30-decisions) DEVICE-1: owner decisions 5, 6 and 8 as they reach an
existing desktop, GAPS D9, D10, D17, G11, G12, G14, G15, ADAPTIVE fixes 9, 10 and 20, BACKLOG M1
(in place), M8 (tooltips), S10 (shortcuts), S11 (versioned upgrades), TABLET T6 and 3.5, PEN 2 and 3.2,
EFFECTS 8.3 (install side). The login check itself is described in `gate.md`; this part adds to it.

## What changed

| Script | Change |
|---|---|
| `tools/device/fusion-config.sh` | in-place layout migration; the Windows-style shortcut set; `--pen`, `--pen-garage`, `--screens`, `--shortcuts`, `--keep-shortcuts`; text rendering; GTK file dialogs; the power service; `[TabBox] DelayTime`; the tablet KWin script; the on-screen keyboard key; tooltip delay 300 ms; `FusionConfigVersion` with the upgrade rule and a change list |
| `tools/device/fusion-restore.sh` | undoes all of the above (pen, services, keyboard key, shortcuts, files below `~/.local`, blur) |
| `tools/device/gate/plasma-fusion-gate.sh` | four more Fusion-only parts: `tablet`, `inputmethod`, `powerfx`, `pengarage` |
| `tools/device/backup-profile.sh` | never starts a Qt program without the session's display; more files |
| `tools/device/restore-profile.sh` | knows the new Plasma Fusion paths |
| `tools/device/tests/gate-unit.sh` | cases `t`, `t3`, `t4`, `t5` for the new gate parts |
| `tools/device/tests/restore-keys-unit.sh` | `fusion-restore.sh` releases the keys of widgets the restored layout does not have (0.5.0) |
| `tools/device/tests/layout-migration-unit.sh` | the in-place layout migration against a scratch HOME: what a later run keeps (0.5.0) |

## fusion-config.sh

```
fusion-config.sh [--install DIR] [--dry-run] [--light|--dark] [--auto|--no-auto]
                 [--reset-layout|--keep-layout] [--hot-corner] [--fonts] [--pen [--pen-garage]]
                 [--screens] [--shortcuts|--keep-shortcuts]
```

With a package it runs as `plasma-fusion setup [options]`, and `plasma-fusion update` (no options)
after a package update. Without `--light`/`--dark` and `--auto`/`--no-auto`, a home already on
Plasma Fusion keeps its variant (the current Global Theme) and its automatic light/dark switching;
any other home gets Dark without switching. It records the package version it applied
(`~/.local/state/plasma-fusion/setup-version`; gate.md, "Package updates with new settings").

The command (`tools/plasma-fusion`, installed as `/usr/bin/plasma-fusion`) finds the package next
to itself (`../share/plasma-fusion`), so the same script serves `/usr` and a Nix store path:

| Command | What |
|---|---|
| `plasma-fusion setup [OPTIONS]` | `fusion-config.sh OPTIONS` in the session |
| `plasma-fusion update` | `fusion-config.sh` without options (keeps the user's choices) |
| `plasma-fusion status` | version, each compiled part and what it was built against (a part built against another KWin than the running one is named), the tested Plasma series, the version this account was set up with, per-user copies that hide the package, the login check's status |
| `plasma-fusion restore [OPTIONS]` | `fusion-restore.sh` (by default the state before Plasma Fusion; `--latest`, `--list`) |
| `plasma-fusion drop-user-copy` | moves the per-user copies of the package's files (`items.txt`, from an earlier `--install`) and `~/.local/libexec/plasma-fusion` to `~/.local/state/plasma-fusion/user-copy-<UTC>/` and prints how to put them back; Plasma prefers `~/.local/share`, so without this a package update would not show |
| `plasma-fusion version` | the package version |

The order of a run: backup, "My previous desktop", install, Global Theme, **layout migration**
(inside the plasmashell restart the run needs anyway), fonts and cursor (first run only), workspaces,
**shortcuts**, KWin, shell, lock screen, terminal and editor, **text rendering**, **GTK file
dialogs**, **power tiers**, **pen**, **screens**, login check, **configuration version**.

### Configuration version and the upgrade rule (BACKLOG S11)

`plasmafusionrc [Config] FusionConfigVersion` is `2` after this run. A HOME without the key is
version 1 when an earlier Plasma Fusion configured it (the Global Theme is `org.plasmafusion.*` or
`[Setup] FontsAndCursor=done`), else 0 (first run).

Every setting the script owns goes through `managed_key FILE GROUP KEY VALUE PREVIOUS...`:

- version 0 (first run): set;
- otherwise set only while the key is unset or still holds a value an earlier release wrote
  (`PREVIOUS`); a value the user chose is kept and reported.

So a rerun no longer resets a setting the user changed (before, every run wrote every key again).
The tooltip delay moves from 600 to 300 ms only where it still reads 600.

On an upgrade (version 1 to 2) the changed and the kept settings are written to
`~/.local/state/plasma-fusion/config-changes`, for the settings module's "What changed" page:

```
# Plasma Fusion configuration upgrade 1 -> 2, 2026-09-30T04:02:11Z, backup /home/USER/.local/state/plasma-fusion/backup-...
changed	plasmarc	PlasmaToolTips	Delay	600	300
kept	plasmanotifyrc	Notifications	PopupTimeout	8000	5000
changed	kwinrc	TabBox	DelayTime	__plasma_fusion_unset__	120
```

Tab-separated: status, file, group (nested groups joined by `/`), key, old value, new value;
`__plasma_fusion_unset__` means "not set". Reverting a line: write the old value back (or delete the
key for the unset marker) with `kwriteconfig6 --notify`.

Settings under the rule: `[TabBox]` and `[TabBoxAlternative]` switcher keys, `[TabBox] DelayTime`
(new, 120), blur strength/noise/saturation, `BorderSizeAuto`, `[Plugins]` script keys (snap,
attach, tablet, sheet), `[Outline] QmlPath`, `[Wayland] InputMethod`, tooltip delay, OSD,
notification position and timeout, `krunnerrc FreeFloating`, lock-screen wallpaper, Konsole profile,
Kate/KWrite colour theme, the three `Xft*` keys. The hot corner without `--hot-corner` is stricter:
`[Effect-overview] BorderActivate=9` is written on a first run only, and a later run keeps whatever
the key holds, unset included (KWin's default is the top-left corner, so System Settings > Screen
Edges deletes the key when the user turns that corner on); with `--hot-corner` it is written, 7.
Options the user passes each time (`--light`, `--auto`) and the Global Theme defaults stay plain
writes.

### Layout migration (an existing Plasma Fusion layout)

A fresh layout comes from the Global Theme's layout script (LAYOUT-1). An existing one (the real
session since round 2) is migrated in place, so panels, pins, cards and their positions stay. It
runs only in the default layout mode, when the layout is a Plasma Fusion one and a change is due;
plasmashell is stopped (it writes the layout file when it quits), the files are edited with
`kwriteconfig6`, and it starts again: one restart for the whole run.

| Change | Only when |
|---|---|
| desktop containment `org.kde.desktopcontainment` or `org.kde.plasma.folder` becomes `org.plasmafusion.desktop` (Folder View with the tablet home screen, TABLET2 H1, `docs/parts/desktop.md`; Folder View's keys, so applets and their `ItemGeometries*` keys stay); without that package `org.kde.desktopcontainment` becomes `org.kde.plasma.folder` (desktop icons, BACKLOG M1), and a desktop naming the missing package becomes `org.kde.plasma.folder` | the plugin is another of the three, on a HOME below configuration version 2 |
| the `[General]` keys below | the plugin was `org.kde.desktopcontainment` (a Folder View keeps its own) |
| `[General]` `url=desktop:/ sortMode=-1 arrangement=1 alignment=0 iconSize=2 popups=false toolTips=false selectionMarkers=true useTypeAhead=true previewPlugins=` (the installed ones of imagethumbnail, jpegthumbnail, svgthumbnail, gsthumbnail, opendocumentthumbnail, ffmpegthumbs) | per key, when the key is not set |
| portrait card positions `ItemGeometries-<H>x<W>` and `ItemGeometriesVertical`: the first two cards side by side under the bar, right-aligned on the 16 px grid, the rest under the right one (the CPU/memory card hides itself in portrait, CARD-2) | neither key exists; sizes from the landscape positions; screen size from the shell |
| top bar `plasmashellrc [PlasmaViews][Panel <id>] panelOpacity` 2 (translucent) becomes 0 (adaptive: solid next to maximized windows, decision 5) | it is still 2, on a HOME below configuration version 2, and the settings page has not chosen translucent (`[TopBar] SolidNextToWindows=false`) |
| tray: `org.kde.plasma.vault`, `org.kde.plasma.devicenotifier`, `org.kde.kscreen`, `org.kde.plasma.printmanager`, `org.kde.plasma.manage-inputmethod` added to `hiddenItems` and `disabledStatusNotifiers` (no expander arrow; quick settings has its own keyboard button) | missing from the list, on a HOME below configuration version 2 |
| tray where quick settings is in the bar: `org.kde.plasma.devicenotifier` out of `extraItems` and in `knownItems` (not loaded: the quick-settings Disks & Devices page replaces it) | it is in `extraItems`, or not in `knownItems`; once (plasmafusionrc `[Setup] TrayDevices=done`, written after the first run that looked at the layout or built a new one, unless its migration stopped part way) |
| every app menu `[Configuration][Appearance] allScreens=false` (decision 8) | the key is not set |
| pen widget `org.plasmafusion.pen` added to the top bar between the tray and quick settings (next free applet id, `AppletOrder`) | the widget is installed and not in the bar, on a HOME below configuration version 2 |
| live chips `org.plasmafusion.livechips` added right before the tray of every Plasma Fusion top bar with a tray (a free applet id each, `AppletOrder`), and the tray items they replace (`plasmashell_microphone`, `org.kde.plasma.cameraindicator`, `xdg-desktop-portal-kde`, `Spectacle`) added to that tray's `hiddenItems` and `disabledStatusNotifiers` (docs/parts/shell-livechips.md) | the widget is installed and not in that bar; once (plasmafusionrc `[Setup] LiveChips=done`, written after the first run that looked at the layout or built a new one while the widget was installed, unless its migration stopped part way) |

The rows "below configuration version 2" bring a layout from before 0.2.0 up to it; every release
since ran them at its first run. Until 0.5.0 they ran at every run, so each `plasma-fusion update`
made the settings page's translucent top bar adaptive again, put a tray item the user set to
"Always shown" back into the hidden lists (quick settings then hid it again while passive), added
back a removed pen menu or desktop, and, since such a change is a migration, stopped and started
plasmashell (ending Keep awake). Now a later run finds nothing to migrate on a layout the user
left alone, and changes nothing the user changed (`tools/device/tests/layout-migration-unit.sh`).
Each step reads the layout as the steps before it left it in the same run (their writes are queued
and applied together), so step 7 keeps the pen menu step 6 put into the bar's order and the items
step 4 hid.

Whether the layout is a Plasma Fusion one (a full-width top panel and a floating, fit-content
bottom panel), the top bars that get `floatingApplets` and the bar thickness the run sets are read
from the panels on the screens that are there (0.5.0). A panel of a monitor that was unplugged
stays on its missing screen in Plasma 6.8, and reading its length mode, floating or height crashed
plasmashell (`docs/parts/kwin-tablet.md`, "Panels without a screen"); the layout check then
answered "no", and a run in the default layout mode would have built a new layout over the
user's. `tools/device/tests/panel-scripts-unit.sh` (build workflow) runs the three scripts against
a model of desktop scripting with such a panel (the scripts of 8cf0b3d fail 4 of its 6 checks).

The landscape card positions are not touched. After the 4/3 scale change the shell reads
`ItemGeometries-1440x900`, which does not exist, and falls back to `ItemGeometriesHorizontal`
(`x=1232`, 16 px from the right edge at 1440 px). LAYOUT-1 owns card geometry for fresh layouts;
if its portrait rule differs, the migration follows it (see Needs).

### Shortcuts (owner decision 6)

Applied once per configuration version (`--shortcuts` again, `--keep-shortcuts` never).
`tools/device/tests/launcher-keys-unit.sh` (CI step "Setup search keys") runs the search-key part
against a table standing in for kglobalaccel: the set, the one-time Alt+F2 upgrade and the cases
where the user's own keys stay. Every other
action holding one of these keys loses it; each change is recorded in the backup's `shortcuts`
file, so `fusion-restore.sh` gives every key back.

| Key | Target (kglobalaccel component / action) |
|---|---|
| Meta+Space, Meta+S, Alt+Space, Search (KRunner's other `_launch` keys) | `plasmashell` / `activate application launcher`: the shell activates the launcher on the active screen, exactly as for Meta |
| Alt+F2 | `org.kde.krunner.desktop` / `_launch`, its only key: the full KRunner (every plugin, web shortcuts too). Alt+F2 is the run-command key of KDE since its first release and of GNOME and Xfce, so whoever presses it wants a command line; the Windows and macOS search keys and Alt+Space stay with the launcher, whose last search row hands the query to KRunner. `RunClipboard` keeps no key. On a HOME an earlier release set up (the launcher had Alt+F2, KRunner nothing; the key set does not run again there) the setup moves Alt+F2 back once, only while the launcher still holds it and KRunner has no key (`plasmafusionrc [Shortcuts] KRunnerKey=1`; recorded in the backup like every key) |
| Meta+A | the quick-settings widget's own "activate widget <id>" (widget API, as before) |
| Meta+N | `org.plasmafusion.notifications.desktop` / `_launch`: a desktop file in `~/.local/share/kglobalaccel/` (how System Settings adds a command shortcut) that writes the quick-settings widget's `[General] openRequest = "notifications:<ms>"` through `evaluateScript` (`busctl`) |
| Meta+V | `org.plasmafusion.clipboard.desktop` / `_launch`, a component of the same kind that writes `openRequest = "clipboard:<ms>"`: quick settings' clipboard sheet on the screen in use (a second Meta+V closes it); Klipper's `plasmashell` / `show-on-mouse-pos` ("Show Clipboard Items at Mouse Position", Plasma's Meta+V) loses the key and keeps its others |
| Meta+Up / Meta+Down | `kwin` / `Window Maximize` (a toggle in KWin 6.7.5) / `Window Restore` (Meta+PgUp and Meta+Backspace stay) |
| Meta+Alt+Up / Meta+Alt+Down | `kwin` / `Window Quick Tile Top` / `Bottom` (`Switch Window Up/Down` lose them) |
| Meta+Tab | `kwin` / `Overview` (Meta+W stays; `Walk Through Windows` keeps Alt+Tab) |
| Meta+Alt+1..9 | `kwin` / `Plasma Fusion: Activate Dock Entry 1..9` (the snap KWin script; the dock's `activateTaskAtIndex` through its `activateRequest` key, on Plasma 6.7 and 6.8); plasmashell's `activate task manager entry 1..9` lose Meta+5..9, and a Meta+Alt+N an earlier version gave them moves to the new action |
| Meta+1..4 | `kwin` / `Switch to Desktop 1..4` (unchanged) |
| Meta+Shift+W (with `--pen`) | the pen widget's "activate widget <id>", only when free |
| Meta+Shift+T (every run, not part of the Windows set) | `org.plasmafusion.copytext.desktop` / `_launch` (0.5.0): copy text from the screen, a component like Meta+N whose command is the helper `plasma-fusion-copytext` (`spectacle --region` without the helper, and in 0.5.0); set only when no action holds the key, a key the user gave it is kept, nothing without Spectacle |

**Copy text from the screen** (survey F6; PowerToys Text Extractor's Win+Shift+T, macOS Live Text).
Meta+Shift+T, or the button next to the screenshot button in quick settings' header: select an area,
and its text is on the clipboard, with a "Text copied" notification that shows its first line
(2026-10-15; in 0.5.0 Spectacle's window opened and Extract Text took one more click). Spectacle
6.7.5 (OCR since 6.6, Tesseract) recognises text only in its own window: `spectacle --help` and its
D-Bus interface (`org.kde.Spectacle`: FullScreen, CurrentScreen, ActiveWindow, WindowUnderCursor,
RectangularRegion, Record*, OpenWithoutScreenshot) have no text option, and neither has Plasma 6.8's
or master's command line (KDE bug 516767 asks for it). Its background mode saves the chosen area to
a file and exits: without `-o` into Pictures/Screenshots (VM, 2026-10-11), with `-o FILE` to FILE
alone, as its "save automatically" and "copy to clipboard" settings are not applied in background
mode (`SpectacleCore.cpp`, 6.7.5). So the helper `plasma-fusion-copytext` (`packages/copytext/`; in
the helper directory: `/usr/libexec/plasma-fusion`, `/usr/lib/plasma-fusion` on Arch, the system
profile on NixOS, `~/.local/libexec/plasma-fusion` with `--install`) does it in four steps:

1. capture: `spectacle -b -n -r -o $XDG_RUNTIME_DIR/plasma-fusion-copytext.XXXXXX/region.png`, the
   directory removed when the helper ends; Esc ends it without a word;
2. read: `tesseract FILE stdout -l LANGS --psm 3` with the languages Spectacle would use
   (`OcrManager.cpp`: `spectaclerc [General] ocrLanguages`, the installed ones in its order, no osd,
   no repeats, at most four; else the first installed language other than osd), so the languages
   chosen in Spectacle's settings apply; each line trimmed and empty lines dropped, as Extract Text
   joins them;
3. copy: Klipper's `setClipboardContents` (the clipboard history keeps the text), else `wl-copy`;
4. say so: "Text copied" (the first line, at most 80 characters, and how many lines follow), "No
   text found", "Could not read the text" or "Could not copy the text" - transient notifications,
   not kept in the history - and "No text recognition languages" with the package names when
   Tesseract has no language data (then nothing is captured).

Spectacle runs once per session: a request goes to the Spectacle already open, which drops its
window for the new capture (as its own Rectangular Region key does) and, for a background request,
quits after saving (`SpectacleCore::activate`, 6.7.5). So while Spectacle is open
(`org.kde.spectacle` on the session bus) the helper leaves the capture to it, and where the
`tesseract` command is missing it opens Spectacle as before: `spectacle --region`, the area in
Spectacle's window, where **Extract Text** on the selection's toolbar copies the text; the window
stays afterwards unless its "Close after extraction" setting (`spectaclerc [General] closeAfterOcr`)
is on. A second press while the area is being chosen does nothing (a lock in the runtime directory,
not handed on to Spectacle or wl-copy, which stay). The packages recommend Tesseract (Fedora
`tesseract`, Debian `tesseract-ocr`, Arch's optional `tesseract` with a `tesseract-data-*`
language); on NixOS add `pkgs.tesseract` to the system packages. The setup's component runs the
helper by its path (in double quotes when the path holds a space; a path with `"`, `` ` ``, `$`, `\`
or `%` is not used) and `spectacle --region` when no helper is installed (the tools run from a
source tree). kglobalaccel launches a component with the command it read when it loaded it
(`KServiceActionComponent` keeps its `KService`, kglobalacceld 6.7), so when the setup changes the
command of a loaded component (`plasma-fusion update` in a running session after 0.5.0), it
unregisters `_launch` - kglobalacceld drops a component left without actions when it writes its
settings, 500 ms later - and registers it again, which makes the component from the new file; the
keys it had are given back as they were (not recorded as a change). Quick settings' button runs the
helper from the same places in the same order (`Backend.copyTextCommand`), else `spectacle
--region`. Meta+Shift+T was free in KWin, Plasma and Spectacle 6.7.5 and in the Windows-style set
(`globalShortcutsByKey` empty in the parity VM). kglobalaccel makes a component it loads at login
active but leaves one registered while it runs inactive (`isActive` false, no key grab) until the
next login, so the setup gives the key again as present (`setShortcut` with SetPresent |
NoAutoloading, as a running application does): the key works at once. `fusion-restore.sh` gives the
key back (none), unregisters the component and removes its desktop file (an `absent-file` entry of
the backup). Tests: `tools/device/tests/copytext-unit.sh` (CI, 24 checks) runs the setup step and
the restore's sections against a fake kglobalaccel: a free key set and given as present, the old key
recorded, a second run unchanged, a key in use left with its action, the user's own key kept,
nothing without Spectacle, and the restore; the component's command (the helper, quoted for a path
with a space, not used for one with a `$` or a `%`, `spectacle --region` without it, a 0.5.0 file
written again); a loaded 0.5.0 component made again with the user's key kept and no change recorded,
and no reload on a second run; quick settings' command run as Plasma's executable source runs it
(the helper, else `spectacle --region`; its places and their order against `HELPER_DIRS`).
`packages/copytext/tests/helper-unit.sh` (CI, 28 checks) runs the helper itself with a PATH of
stand-ins (Spectacle, Tesseract, kreadconfig6, busctl, wl-copy): the capture's arguments and its
directory, the text Klipper gets, the notifications, nothing left behind, Esc, Spectacle open, a
second press, the language choice, no language data, no `tesseract` command, no text, Tesseract
failing, text that starts with a dash or holds markup, a long line cut in characters, wl-copy
(without the helper's lock: it stays to serve the clipboard), no clipboard; then on a private bus
with the real `busctl` (`fake_session.py` owns Klipper's and the notification server's names; text
that starts like an option), and real Tesseract on a line drawn in Manrope at 14 px.
`packages/copytext/tests/vsession/scenario-copytext.sh` (a private session, 25 checks; KWin and
Spectacle 6.7.5, Tesseract 5.5.3) drives the real Spectacle, Tesseract and Klipper with KWin's
emulated keys and pointer: 0.5.0's component, loaded first, starts `spectacle --region` from
Meta+Shift+T; the setup makes it again with the helper and keeps the key (without that, the key went
on starting `spectacle --region` and nothing was copied); then Meta+Shift+T and a drag around a line
put exactly that line on Klipper's clipboard with a "Text copied" notification, no image left and no
Spectacle left running; Esc copies and says nothing; with Spectacle's window open the area goes to
that Spectacle, which keeps running with it, and the helper copies nothing; a second line follows
(both in Klipper's history); quick settings' button does the same as the key. VM (0.5.0, real keys
from a uinput keyboard): after the setup Meta+Shift+T started `spectacle --region` without a new
login, the header button too; after the restore the key holds nothing and starts nothing.

**Quick Look in Dolphin** (2026-10-15; docs/parts/quicklook-cpp.md). With Dolphin and the
`plasma-fusion-quicklook` package installed (its program in PATH and its service menu in a data
directory), the setup gives Space in Dolphin to Quick Look: Dolphin lists the service-menu action
among its shortcuts (`servicemenu_plasma-fusion-quicklook.desktop::quicklook`, Dolphin 26.04 and
later) and keeps the user's shortcuts in `~/.local/share/kxmlgui5/dolphin/dolphinui.rc`
(`ActionProperties`). Without that file the setup writes one of version 0 holding only the two
entries (Quick Look `Space`, "Select Files and Folders" `toggle_selection_mode` none): it is older
than Dolphin's own interface, so KXmlGui merges its shortcuts into Dolphin's file and keeps nothing
else (`KXmlGuiVersionHandler`, kxmlgui master), and the menus and toolbars stay Dolphin's. With the
file (the user changed shortcuts or toolbars) the two entries are added to its `ActionProperties`
and the rest is kept. Selection mode loses Space only while it has its default key (two actions
on Space would be ambiguous and neither would run); its button and menu entry stay. A Space the
user gave an action, a key the user gave Quick Look, or an earlier run's entry is kept; a file that
is not XML is left alone with a warning. Dolphin reads the file when it starts. The file is in the
backup (`absent-file` or `present-file`), so `fusion-restore.sh` removes it or puts it back. When
the setup gave the keys it leaves a mark (`quicklook-space` in its state folder); a later run with
Quick Look no longer installed takes the two entries out again (Dolphin drops the entry of an
action that is gone, but selection mode would keep none, and Space would do nothing): a file of
version 0 left with nothing else is removed, another one keeps the rest; without the mark the file
is left as it is. Test: `tools/device/tests/quicklook-keys-unit.sh` (CI, 20 checks) runs the step in a throw-away HOME with
stand-ins for Dolphin and Quick Look and the restore's file loop: nothing without Dolphin or Quick
Look; a new file of version 0 with only the two entries, unchanged on a second run, removed by the
restore; Dolphin's own merged file keeping the user's keys, menus, toolbars and version, put back
as it was by the restore; selection mode on the user's own key keeping it; a Space the user gave
selection mode or another action left alone; the user's own key for Quick Look kept; an unreadable
file left alone; after Quick Look is removed, the setup's own file removed and the two entries taken
out of Dolphin's merged file (the user's keys kept), and a file without the mark left alone.

Widget keys (quick settings, pen) are also set on later runs when the widget has none (a layout
rebuild drops them; a dead entry of a dropped widget is cleared first), but then only when the key is
free. With `--keep-shortcuts` quick settings keeps Meta+N, as before, and Klipper's pop-up keeps
Meta+V (no clipboard component is added; the clipboard button still opens the sheet). A later run
without the set adds the Meta+V component and gives it Meta+V only when nothing holds the key (on a
stock Plasma Klipper does), so "Plasma Fusion: Clipboard" can be given a key in System Settings >
Shortcuts; `--shortcuts` moves Meta+V to it. One exception, for a HOME an earlier release set up
with the Windows-style set (Meta+N is the notification list's and Meta+S the launcher's there, as
read before the run's own Meta+N step, and the set does not run again): the first 0.5.0 run moves
Meta+V to the sheet once, while Klipper's pop-up still has it and the sheet has no key
(plasmafusionrc `[Shortcuts] ClipboardKey`); a key the user gave either of them stays. Meta+N alone
is not the mark: a run without the set gives the notification list a free Meta+N too, so a
`--keep-shortcuts` setup whose quick settings lost Meta+N would have lost Meta+V to the sheet.
The setup run right after the component's `_launch` was unregistered (as `fusion-restore.sh` does)
lost the key: an unregistered `_launch` leaves its component without actions, kglobalacceld forgets
such a component only at its next settings write-out (0.5 s later) and reads a component's desktop
file only when it makes the component, so in that moment the registration gave it no `_launch`, and
the step reported "none -> Meta+N" for a key bound to nothing until the next login (VM 2, 6.7.5:
the step 0 s after the unregister lost Meta+N and Meta+V; 2 s after, the component was made from its
file again and the keys worked). Now `register_command_component` registers `_launch` by name as
well (it finds the file's own and changes nothing, or makes the missing one, which runs the file's
command too) and `command_key_present` gives the key as present, as the copy-text step does, so the
key works at once either way; with no key (Klipper keeps Meta+V) a key chosen later in System
Settings works at once too.
Tested by `tests/shortcut-keys-unit.sh` (41 checks against a fake kglobalaccel that models
kglobalacceld 6.7's components, their write-out, present actions and `setShortcut`: the claim, Klipper's other keys,
the backup record that `fusion-restore.sh` replays, the executable desktop file, the Meta+N and
Meta+V keys starting their command at once, also when the setup runs right after a restore's
unregister or after the write-out, later runs, a user's own key, a dry run, which kind of run claims, the one-time
upgrade and the former `--keep-shortcuts` setups).

### Other settings

- **Text rendering** (GAPS D9, fix 20): `~/.config/fontconfig/fonts.conf` gets KXftConfig's four
  `<match target="font">` assign edits (rgba `none`, hintstyle `hintslight`, hinting `true`,
  antialias `true`), other rules in the file kept; `kdeglobals [General] XftAntialias=true`,
  `XftHintStyle=hintslight`, `XftSubPixel=none`; `refreshFonts`. This is what System Settings >
  Fonts writes (plasma-workspace `kcms/fonts`). Fedora's
  `/etc/fonts/conf.d/10-sub-pixel-rgb-for-kde.conf` turns subpixel colours on; the user file is read
  later (`50-user.conf`) and wins, for Qt and GTK alike (both use fontconfig; kde-gtk-config 6.7.5
  does not handle these keys). Programs started afterwards use it; plasmashell after its restart.
  Qt Quick text drawn with distance fields (plain `Text`, the shell's labels) does not go through
  fontconfig: on desktop GL it uses subpixel antialiasing by default (qtdeclarative
  `qsgdefaultcontext.cpp`), which gave the top bar's colour fringes. The session env file (below)
  sets `QSG_DISTANCEFIELD_ANTIALIASING=gray` from the next login.
- **Session environment** (G12, fix 20): `~/.config/plasma-workspace/env/plasma-fusion-session.sh`
  (startplasma sources it at login and passes it to systemd and D-Bus activation; it only sets
  variables) exports `GTK_USE_PORTAL=1` and `QSG_DISTANCEFIELD_ANTIALIASING=gray`. GTK programs
  that use GTK's native file chooser (`GtkFileChooserNative`) then open the KDE file dialog through
  the portal; a program that builds its own `GtkFileChooserDialog` keeps GTK's dialog (Xournal++
  1.3.7's Open dialog does).
- **Window switcher**: `kwinrc [TabBox] DelayTime=120` (KWin's default 90).
- **Tablet KWin script**: `[Plugins] plasmafusion-tabletEnabled=true` when installed.
- **Tablet navigation effect** (TABLET2 N1): `[Plugins] plasmafusion_navigationEnabled=true` when the
  plasma-fusion-navigation package is installed, then loaded through `org.kde.kwin.Effects.loadEffect`
  (KWin's reconfigure does not load a newly enabled effect; private session `n5`: unset -> true, loaded).
- **On-screen keyboard** (T6): in laptop posture `kwinrc [Wayland] InputMethod=` (empty) unless the
  user chose another input method or quick settings' keyboard policy is "On touch" (asked of the
  running plasmashell, else read from the layout file; 0.5.0: before, every run turned the
  keyboard off for that policy until the next login or posture change, since quick settings
  writes the key only when the posture or the policy changes); in tablet posture left alone. Quick
  settings switches it with the posture afterwards (`tests/config-keys-unit.sh` covers the step). `plasmakeyboardrc [General] diacriticsPopupEnabled=false` (TABLET2 P0):
  plasma-keyboard 6.7 shows an accent pop-up when a physical key is held 600 ms while it runs,
  which broke password entry for users (Fedora discussion 194845); the on-screen keys keep their
  long-press accents. The file is in the backup (`fusion-restore.sh` removes it if it was absent;
  private session `cfg1`: set, unchanged on a second run, removed by restore).
- **Tooltips** (M8): `plasmarc [PlasmaToolTips] Delay=300`.
- **Title bars**: every run applies the Global Theme (`plasma-apply-lookandfeel -a`), which removes
  the user's own `kwinrc [org.kde.kdecoration2] library` and `theme`, so the theme's Aurorae value
  comes back. When the compiled decoration was chosen (DEPLOY-1 step 7) and is installed, the script
  chooses it again after the apply (review finding; before, the next run after DEPLOY-1 would have
  switched the title bars back to Aurorae).
- **Panel thickness check** now uses the layout script's text scale (it forced 34 px before) and
  leaves the panels alone in tablet posture (the tablet script owns them there).

### Power tiers (POWER-1's service)

`install_user_service plasma-fusion-powerfx.service powerfx`: the unit is looked for as
`plasma-fusion/powerfx/plasma-fusion-powerfx.service` in the data directories (the build or the
system package), else `packages/powerfx/` next to the tools. It is copied to
`~/.config/systemd/user/`; when its `ExecStart` names `%h/.local/libexec/plasma-fusion/<program>`,
that program is copied there from the unit's directory (mode 0755). The `graphical-session.target.wants`
link is written as `systemctl --user enable` writes it; then `daemon-reload` and `restart` only in
this session's own systemd manager (its environment names this session bus), so a private test
session never touches the logged-in user's manager. The unit is recorded in the backup's `services`.

### Pen (`--pen`, `--pen-garage`)

`tools/pen/pen-defaults.sh --no-install` (nothing installed from here; Xournal++ is recommended by
the package); its backup directory is recorded in the backup (`pen-backup`). Then Meta+Shift+W for
the pen widget. `--pen-garage` (only after hand check V2 showed the garage events) installs
`plasma-fusion-pen-garage.service` the same way as the power service (from `plasma-fusion/pen/`) and
sets `plasmafusionrc [Pen] GarageService=true`.

### Screens (`--screens`)

Runs `contents/layouts/ensure-topbars.js` of the chosen Global Theme in plasmashell (a top bar on
every screen, decision 8, with the status area since 2026-10-09) and prints what it prints. When
it added or completed a bar, the power service is asked to apply its tier to the new widgets
(`systemctl --user try-reload-or-restart plasma-fusion-powerfx.service`; nothing when it is not
running). The layout migration keeps the hidden tray items in every Plasma Fusion top bar's tray,
not only the main one.

### Decision 7

No code: the owner named no apps, so KMail, KOrganizer and Akonadi stay. When apps are named, the
pins go into the dock's `launchers` and `~/.config/autostart/org.kde.kalendarac.desktop` gets
`Hidden=true` (with a backup entry), both in this script.

## fusion-restore.sh

In addition to what `gate.md` describes, for the chosen backup and every later run, newest first:

1. shortcuts through kglobalaccel (the Windows-style set included, so Klipper's pop-up gets Meta+V
   back); the Meta+N and Meta+V components are unregistered when the restored state has no desktop
   file for them, and a component file that a backup older than the component does not list is
   removed;
2. pen defaults: `pen-defaults.sh --restore <pen backup>` (KWin reads them at once);
3. user services: stopped in this session's own manager (`plasma-fusion-powerfx` gives the
   power-tier values back in `ExecStopPost=... --apply full`); without a manager its program runs
   `--apply full` itself;
4. the backup's `[Wayland] InputMethod` told to KWin with `kwriteconfig6 --notify` (a restored file
   alone does not start or stop the keyboard);
5. files: `~/.config` as listed in the manifest (layout, plasmashellrc, kwinrc, fonts.conf, the
   portal env file, units and their links) and the new `present-file`/`absent-file` entries below
   `$HOME` (`~/.local/share/kglobalaccel/org.plasmafusion.notifications.desktop`,
   `~/.local/share/kglobalaccel/org.plasmafusion.copytext.desktop`,
   `~/.local/share/kglobalaccel/org.plasmafusion.clipboard.desktop`,
   `~/.local/libexec/plasma-fusion`, `~/.local/share/kxmlgui5/dolphin/dolphinui.rc`);
6. widget shortcuts: every plasmashell `activate widget N` action whose widget N is not in the
   restored layout is unregistered (0.5.0). kglobalaccel keeps a widget's key after the widget is
   gone, and step 1 gives back only the keys the setup recorded, not the Meta+A that the settings
   module's "Reset Fusion layout" gave the rebuilt quick settings, so after a restore that key
   stayed held by nothing (`tests/restore-keys-unit.sh`);
7. `daemon-reload`, KWin reconfigure, blur loaded again unless the restored kwinrc turns it off,
   `fc-cache`, plasmashell started.

## Login check additions (gate.md)

| Part | "On" when | Switched off (Fusion not the Global Theme) |
|---|---|---|
| `tablet` | `kwinrc [Plugins] plasmafusion-tabletEnabled=true` | written `false` (not removed: the script's EnabledByDefault is not the check's to know) |
| `navigation` | `kwinrc [Plugins] plasmafusion_navigationEnabled=true` | written `false`; also after a KWin or Qt update (version-checked like the compiled decoration) |
| `inputmethod` | user `kwinrc [Wayland] InputMethod` is empty or `/usr/share/applications/org.kde.plasma.keyboard.desktop` (the values the Fusion policy writes; on other distributions the same file in another system data directory, such as `/run/current-system/sw/share/applications/`) | the user key removed, so Fedora's default keyboard returns; another input method is never touched |
| `powerfx`, `pengarage` | `~/.config/systemd/user/graphical-session.target.wants/plasma-fusion-{powerfx,pen-garage}.service` exists | the link moved to `~/.local/state/plasma-fusion/gate/saved/` (no systemd call at login: startplasma reloads the manager after the check, so the service does not start at this login) |

They follow the existing theme-part rules: recorded first, switched off once (a part the user turns
on again stays on), turned back on at the next Fusion login or by `fusion-config.sh` (`deploy`),
and only while the value is still the one written. A link comes back only when the unit file is
still installed. Link records are checked against the one allowed path, so a hand-edited record
cannot move another file.

## backup-profile.sh

It started `kscreen-doctor -j` and `plasmashell --version` unconditionally; over SSH without
`WAYLAND_DISPLAY` both aborted (2026-09-30 02:56Z, `kscreen.json` empty). Now:

- the display comes from the plasmashell on this user's own session bus (`/run/user/UID/bus`
  unless `DBUS_SESSION_BUS_ADDRESS` names another), as `fusion-config.sh` does; `kscreen-doctor -j`
  runs only when that Wayland socket exists (15 s limit), else `kscreen.json` holds an error note
  (`~/.config/kwinoutputconfig.json`, which has the scale, is always in the tarball);
- the Plasma version comes from `rpm -q plasma-workspace` (fallback `plasmashell --version` with
  `QT_QPA_PLATFORM=offscreen`);
- more paths: `plasmafusionrc`, `krunnerrc`, the Plasma Fusion user units and their wants links,
  `libwacom`, `~/.local/share/kglobalaccel`, `~/.local/libexec/plasma-fusion`;
- its work directory is below the destination, not in `/tmp`;
- the window placement memory (`plasmafusion-placementrc`). `restore-profile.sh` removes it and
  the `plasmafusion-placement` script package when the snapshot had neither, and unloads the
  running placement script before it restores anything (the shell is stopped then, so the script's
  last write goes nowhere): a script left running would write its newer map over the restored file.
  The closing reconfigure loads it again when the restored `kwinrc` enables it. The dynamic
  workspaces script (`plasmafusion-workspaces`) is unloaded the same way, and its package removed
  when the snapshot had none: KWin writes its whole `[Desktops]` group to `kwinrc` at every
  workspace the script adds or removes, which would land over the restored desktops. It must not
  load again in this session either - the closing reconfigure loads every script the restored
  `kwinrc` enables - so when the snapshot enables it, its key is off while KWin reads the restored
  file, and the snapshot's `kwinrc` is copied back exactly afterwards; the next login starts it.
  `tests/profile-unit.sh` checks both sides in throw-away HOMEs (`env -i`, the restore with
  `--dry-run`; in CI).

## Commands for DEPLOY-1

```
# step 2 (over SSH is fine now)
~test/.local/state/plasma-fusion/deploy-<rev>/tools/device/backup-profile.sh
# step 4, decision 1 (exactly 4/3), in the real session's environment (from plasmashell's environ)
kscreen-doctor output.eDP-1.scale.1.3333333
# step 6
deploy-<rev>/tools/device/fusion-config.sh --install deploy-<rev>/home --pen [--screens]
# undo step 6
deploy-<rev>/tools/device/fusion-restore.sh <the backup it printed>
```

## Verification

Private sessions on the ThinkPad (1920 x 1200 at 4/3 unless noted), `build/o1dv/`; builder `o1dv`
until 04:19Z, then the lead (review notes `build/o1dv/REVIEW.md`). Seeds: a clean HEAD stage, stand-ins
for the parts other lanes are still building (tablet script, powerfx, pen widget and garage,
ensure-topbars.js), the deployed d4afee8 tools (upgrade path) and these tools.

- Laptop: `tests/gate-unit.sh` 117/117, `tests/gate-stub.sh` 13/13 (both now accept a relative
  scratch path); `bash -n` and `shellcheck -S warning` clean.
- Upgrade from the deployed d4afee8 configuration (`o1dv-up`, `o1dv-up3`): dry run without changes
  and without a second backup; 81 changes in 12-13 s; the panels, pins and cards kept, the desktop a
  Folder View with the icons in the left column, the pen widget added between the tray and quick
  settings, portrait card positions written, the top bar adaptive; a user-changed value kept and
  listed in `config-changes`; FusionConfigVersion 2; every decision-6 key bound exactly once in
  `kglobalshortcutsrc`; a second run changes 3 things and neither re-applies the key set nor
  migrates again; `fusion-restore.sh` gives the shortcuts and the layout back.
- Keys (screenshots and window probes): Meta+Space, Meta+S, Alt+Space and Alt+F2 open the launcher
  (KRunner never starts; since 0.5.0 Alt+F2 opens KRunner instead, VM check of 2026-10-11),
  Meta+A quick settings, Meta+Up maximizes, Meta+Down restores,
  Meta+Alt+Up tiles to the top half (with KWin's 6 px tile gap), Meta+Tab Overview, Meta+Alt+1 the
  first dock app, Meta+1 workspace 1, Meta+Shift+W the pen widget. Meta+N: see the open items.
- Text: with the session environment, the top bar's clock text has no colour fringes (0 strongly
  coloured pixels in the clock box against 475 before, `o1dv-up` run 2, landscape; portrait not
  measured). A GTK 3 `GtkFileChooserNative` opens the KDE file dialog
  (`org.freedesktop.impl.portal.desktop.kde`); Xournal++'s Open dialog stays GTK's own (above).
- Upgrade from a phase-1 (0918220) configuration with one user-changed key (`o1dv-u0`): the user's
  tooltip delay 800 kept, an unchanged Fusion value stays, the new keys added, the desktop migrated,
  quick settings on Meta+A. M24: fonts, cursor and button side survive Light and Dark;
  plasmafusionrc untouched by the theme switches.
- Fresh HOME configured from outside the session, as over SSH (`o1dv-fr`, `o1dv-fr2`): the session
  environment taken from plasmashell; the garage unit with `--pen-garage`; a matching login changes
  nothing and the login environment has `GTK_USE_PORTAL=1`; M27 (faked KWin and kscreenlocker
  versions): the stock lock screen, the Aurorae title bars, one notification, none at the second
  login, and the next matching login gives both back ("lockscreen back on; decoration back on",
  after the title-bar fix above); Breeze chosen: powerfx and the garage are not started at the next
  login, the tablet script off, the keyboard key removed; Plasma Fusion again: all back on; the
  restore gives the shortcuts, the layout and the pre-Fusion files back, powerfx and the gate stub
  gone. Remaining differences after the restore are Plasma's own GTK colour files
  (`gtk-3.0/colors.css`, `window_decorations.css`, `assets`, written by Plasma's GTK integration
  on every colour change).
- No core dumps from these sessions.

Open items:
- Meta+N (the notification list): the component's desktop file is now installed executable (KDE
  refused to run it without the bit), but in a private session neither the key nor
  `invokeShortcut` launches it, while its command run directly works. Found in 0.5.0: the setup
  registered the component's `_launch` action itself, and kglobalacceld then put an action no
  program owns in place of the desktop file's own `_launch` (it reads the file when the component is
  first named, then adds the named action anew), so the key did nothing until the next login read
  the file again. The setup now registers it as System Settings' "Add Command" does (an action with
  an empty name, removed again: `register_command_component`), and the key works at once
  (`tests/shortcut-keys-unit.sh` against a fake kglobalaccel made the way kglobalacceld 6.7
  behaves; the Meta+V component, registered the same way, opened the clipboard sheet at once in
  VM 3 without a new login). The private-session case is not checked again.
- Portrait fringe measurement and the real GTK apps the owner uses (hand checks).

## Needs from other parts

(See the report; kept in sync.)

## Measuring the glass's battery cost (tools/device/power-ab.sh, 2026-10-01)

Research D-desktop found no data on the battery cost of blur; E-phone ranks battery life first. In the
Plasma session, on battery, run `tools/device/power-ab.sh [MINUTES=10] [BLOCKS=8]` and leave the
machine alone: KWin's blur effect alternates on and off per block (nothing else changes), sleep and
screen-off are inhibited (kde-inhibit), battery power is sampled every 10 s (power_now, or current x
voltage), and the effect is restored at the end. `summary.txt`: mean watts with and without blur
(each block's first minute skipped) and the difference. Plugging in stops the run. Test mode:
`PF_POWER_AB_FAKE=DIR` (a fake power_supply tree; the effect is not touched).
