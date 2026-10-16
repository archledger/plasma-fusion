# Settings module: `kcm_plasmafusion` (System Settings > Appearance & Style > Plasma Fusion)

Status: `plasma-fusion-settings-1.0.0-4` (work package KCM-1 of the one-pass plan): the Appearance
page of 1.0.0-3 plus the Plasma Fusion switches that have no page of their own (snap layouts,
glass, high contrast, reduce motion, dock size, top bar, desktop icons, file drag, battery, tablet)
and two actions (restore the previous desktop, reset the Plasma Fusion layout). Built as the x86_64
RPM in the Fedora 44 build container on the ThinkPad and checked in private virtual sessions on the
ThinkPad (see "Verification, 1.0.0-4"). Not installed (the lead installs it at DEPLOY-1). 1.0.0-3
(reviewed) is installed in the real session since 2026-09-30 01:19Z. Last edited 2026-09-30.

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
| | System meters in the top bar (0.5.0) | adds `org.plasmafusion.meters` right before `org.plasmafusion.quicksettings` in every top bar that has none (inserted at that position, then checked and moved there in a second call, as the global menu), or removes every meters widget from the panels; read back as on when the main top bar has one. The second call moves only the widgets the first one added (by id; meters placed by hand stay where they are) and runs from the event loop, every 300 ms for up to 3 s until the shell lists them, so Apply does not wait for it. A top bar without quick settings gets no meters: when no top bar can take them (and none has them), or the shell cannot make the widget (`addWidget` returns an Error object), Apply shows an error and the switch reads the layout again. A top bar added later ("Top bar on every screen", a screen connected) gets them too while the main bar has them (`ensure-topbars.js`). Off by default (the widget is in no layout); disabled with a note while the widget is not installed (`knownWidgetTypes`); evaluateScript. The widget's own settings turn each meter on or off (`docs/parts/shell-meters.md`). Added while the power tier is not full, the power service is asked to apply it to them (`systemctl --user try-reload-or-restart plasma-fusion-powerfx.service`) |
| | Hot corner opens Overview | kwinrc `[Effect-overview] BorderActivate`: the top-left corner (7) is added or removed; other screen edges set for Overview are kept, and 9 (none) is written when no edge is left, as fusion-config.sh does; KWin reconfigure and `reconfigureEffect overview` |

Window decoration written with the buttons (and again after Light / Dark, because a Global Theme
brings its own decoration):

| Decoration installed? | kwinrc `[org.kde.kdecoration2]` |
|---|---|
| `org.plasmafusion.decoration` found in `org.kde.kdecoration3` plugins | `library=org.plasmafusion.decoration`, `theme=` (empty), `NoPlugin=false`; button lists kept (the decoration draws its left circles itself), except that the left-circles lists `XIA` / `_` are put back to `M` / `IAX` when leaving Left · circles |
| no (Aurorae fallback, phase 1 decoration part) | `library=org.kde.kwin.aurorae.v2`, `theme=__aurorae__svg__PlasmaFusion{Dark,Light}` for Right · glyphs and Show on hover, `...-Left` for Left · circles (variant from the current Global Theme, else the colour scheme's brightness), `ButtonsOnLeft=M` / `ButtonsOnRight=IAX`, or `XIA` / `_` for Left · circles |

### Below the board (1.0.0-4)

The board ends with the three switches; everything below them is new in 1.0.0-4 and has no board of
its own (same section titles, segmented controls and switch rows; a row with a label and a segmented
control is `ChoiceRow`, an action row `ActionRow`). The keys are the plan's registry
(`docs/PLAN.md`, one-pass plan section 2) plus two new `[TopBar]` keys (marked *new*).

| Section | Control | Written on Apply |
|---|---|---|
| Windows | Snap layouts on maximize: Hold / Hover | plasmafusionrc `[Decoration] SnapLayoutsOnHover` `false` / `true`, always written (the installed decoration 1.0-2 reads a missing key as hover; 1.0-3 defaults to hold, owner decision 4), then KWin reconfigure. The note under it gives the caveat of Hover (a click on maximize only closes an open picker) and says when the Plasma Fusion title bars are not in use |
| Glass and motion | Glass: Full / Reduced / Solid | plasmafusionrc `[Effects] Glass=Full\|Reduced\|Solid` (EFFECTS.md 2, 3.3). Full and Reduced: kwinrc `[Plugins] blurEnabled` removed and `org.kde.kwin.Effects.loadEffect blur`; Solid: `blurEnabled=false` and `unloadEffect blur`. Reduced: both Fusion panels `opacity = "opaque"`; Full / Solid: top bar `adaptive` or `translucent` (next switch), dock `translucent`. The `[General] glass` key (`full` / `reduced` / `solid`) of every dock, quick-settings, launcher and system-card widget. One evaluateScript call for panels and widgets |
| | High contrast colors | `plasma-apply-colorscheme PlasmaFusionHighContrast` (the style part's scheme; the switch is disabled with a note while it is not installed) and the gsettings key `org.gnome.desktop.a11y.interface high-contrast`, written quietly when gsettings is present: that key is what the XDG settings portal's `contrast` is served from (xdg-desktop-portal-kde 6.7.5 does not serve the key at all, the GTK impl does), so applications that follow the portal see the mode too; turning it on selects Solid on the page (GAPS.md G10), which can be changed before Apply. Off: the scheme of the Global Theme in use (`PlasmaFusionDark` / `PlasmaFusionLight`). The accent colour is kept. After Light / Dark it is applied again on top of the theme's scheme; Follow sunset's switches at dawn and dusk bring the normal scheme back (the note says so) |
| | Reduce motion | kdeglobals `[KDE] AnimationDurationFactor=0` with notification; the previous factor goes to plasmafusionrc `[Motion] PreviousAnimationDurationFactor` (not written when the key was missing, = 1.0). Off: the saved factor is written back, or the key removed; the saved one is then removed. The switch shows the live state (`factor == 0`), so it follows the Animations page's slider |
| Dock and top bar | Magnified icon size: 56 px / 62 px | every dock's `[General] magnifiedSize` (disabled while magnification is off; another value shows no segment chosen and is kept) |
| | Solid top bar next to windows | the top bars' panel `opacity`: `adaptive` (owner decision 5) or `translucent`; plasmafusionrc `[TopBar] SolidNextToWindows` (*new*) keeps the choice, which Reduced glass cannot show (both bars opaque; the switch is disabled with a note then). The opacity of a panel whose screen is gone (the top bar of a monitor that was unplugged) is neither read nor set (0.5.0): Plasma 6.8 keeps such a panel on its missing screen, and plasmashell crashes reading it (`docs/parts/kwin-tablet.md`, "Panels without a screen"); its widgets still get the glass key |
| | Top bar on every screen | plasmafusionrc `[TopBar] EveryScreen` (*new*, default `true`, owner decision 8). Off: the top bars on screens other than the main one (the top bar with quick settings on the lowest screen number, as every bar has quick settings since 2026-10-09) are removed, and `ensure-topbars.js` adds none while the key is false; on: the layout part's `ensure-topbars.js` is run when it is installed (`contents/layouts/` of either Plasma Fusion Global Theme), then the page's glass and top-bar opacity are applied to the new bars and, when the power tier is not full, the power service is asked to apply it to them |
| | Dock on every screen | plasmafusionrc `[Dock] EveryScreen` (*new*, default `false`: one dock). On: `ensure-topbars.js` runs at once and gives every screen without one a dock like the main one, each listing its own screen's windows (docs/parts/lookandfeel.md); off: the docks `ensure-topbars.js` added (marked as copies) are removed with their panels and launchers (`s_removeExtraDocksScript`), docks the user made stay, and each dock left gets back the `showOnlyCurrentScreen` it had (with no other dock on a screen that is there, because the user removed it or its monitor is unplugged, the copy on the lowest screen stays as the one dock, no longer a copy, listing every screen's windows, and stands in for the unplugged screens' docks, `[PlasmaFusion] standInFor`, until one of them is back, when `ensure-topbars.js` removes it; a copy's panel whose dock the user removed goes too); when the removal fails the choice stays on (the page shows it on, with the error). Turned on, a dock `ensure-topbars.js` could not make ("not made N") is an error too. Disabled with a note while no Fusion dock is in a panel, except that while on it can always be turned off (the user may have removed every dock; off removes the copies' panels), and Defaults turns it off then too; after a layout reset with it on, the other docks come back, and the page shows an error when they cannot (`ensure-topbars.js` missing or failing) |
| Launcher | Recent files under the pinned apps; Recently used apps (the Recent chip); Places and drives (the Places chip) | every `org.plasmafusion.launcher` widget's `[General] showRecommended`, `showRecentApps`, `showPlaces` (default `true`; the launcher next to the Fusion dock is hidden but holds the keys), through `evaluateScript` as the dock's keys; a section shows on only while every launcher has it on; with launchers that differ the row says so ("Some launchers show this and some do not"), and setting its switch is a change even when it ends where it was (also across a shell restart, while they still differ), so Apply writes it, on or off, to all (Defaults too); disabled with a note while no launcher widget is in a panel, which keeps the values (docs/parts/shell-launcher.md) |
| Desktop | Icons on the desktop | every Folder View desktop: off = `[General] filterPattern=/` and `filterMode=1` ("show files matching" a pattern no file name can match; `QRegularExpression::fromWildcard` anchors it); on = `filterMode=0`, `filterPattern=*`, only when the desktop holds exactly that state (a filter set up in Folder View's own settings is left alone). Positions are kept: Folder View's positioner only adds entries while items are filtered out (`positioner.cpp` sourceRowsRemoved / updatePositionsList) |
| | Icon size: Small / Medium / Large | Folder View `[General] iconSize` 1 / 2 / 3 (32 / 48 / 64 px; Medium is the Plasma Fusion default, BACKLOG M1) |
| | When I drag files between folders: Ask / Move | kdeglobals `[KDE] DndBehavior`: Ask = key removed (KDE's default `AlwaysAsk`), Move = `MoveIfSameDevice` (the General Behavior page's key; BACKLOG S7) |
| Icons | Application icons: Real app icons / Designed tiles | `plasmafusionrc [Icons] AppIcons` = `familiar` / `designs` (the key `fusion-config.sh` and the app-icons service read; an absent key is `familiar`, the service's default). Real app icons keeps the per-app tiles the service draws and updates; Designed tiles writes `designs`, after which a service refresh removes the apps' own icons and only the designed Plasma Fusion tiles show (docs/parts/app-icons.md) |
| Lock & Login | Notification cards on the lock screen; Show the newest notification's title (never bodies or actions); Clock and media card (opens Screen Locking) | `kscreenlockerrc [Greeter][LnF][General]` `showNotifications` / `showNotificationSummaries` (the two lock shell keys no Plasma page shows; the lock shell defaults are true / false). The clock and media card keys stay on System Settings > Screen Locking > Appearance (`kcm_screenlocker`, opened by the row's button) |
| Battery | Lighter at 10 % battery | plasmafusionrc `[Power] LighterOnCritical` (`true` default), read by the power service |
| Tablet | Tablet mode: Automatic / Always / Never | kwinrc `[Input] TabletMode` removed / `on` / `off` with notification (KWin's TabletModeManager watches it). The note shows KWin's current mode (`org.kde.KWin.TabletModeManager`, one GetAll and its two signals) |
| | Apps in tablet mode: Full screen / Windowed | kwinrc `[Script-plasmafusion-tablet] WindowMode=fullscreen\|windowed` |
| | Dock in tablet mode: Hide over apps / Always show | `[Script-plasmafusion-tablet] DockHiding=dodgewindows\|none` |
| | On-screen keyboard: Tablet mode / On touch / Never | every quick-settings widget's `[General] keyboardPolicy=tablet\|touch\|never` |
| | Swipe from the left / right edge | `[Script-plasmafusion-tablet] EdgeLeft`, `EdgeRight` |
| | Home indicator | every dock's `[General] homeIndicator` |
| | (after any of the four script keys) | kglobalaccel `invokeShortcut "Plasma Fusion: Tablet Window Mode"` on `/component/kwin` (the tablet script re-reads its keys; nothing happens without the script) |
| Start over | Export my settings… (file dialog) | at once, no Apply: a JSON settings file (`src/settingsfile.cpp`; "Settings file" below) with the applied settings of this page (a change not applied yet is not in it; the row says so) and the panels as the Global Theme's `export-layout.js` reads them in plasmashell. Disabled without the shell or without the Global Theme's export and import scripts |
| | Import settings… (file dialog, confirmation) | at once: a file that is not a Plasma Fusion settings file of this version changes nothing; otherwise its settings are set on the page and applied as Apply does, and its panels take the place of the ones there are (`import-layout.js`), then the widgets get their keys and the panels their glass, top bars and docks as after "Reset Fusion layout" ("Settings file" below). Disabled as Export |
| | Restore my previous desktop… (confirmation) | `plasma-apply-lookandfeel --apply org.plasmafusion.previous.desktop` at once (the gate lane's "My previous desktop"); automatic light/dark switching goes off with it. The login check switches the Fusion lock screen, title bars and KWin scripts off at the next login. Panels and desktop widgets stay (the confirmation says so; `fusion-restore.sh` is the full undo). Disabled when the package does not exist |
| | Reset Fusion layout… (confirmation) | `org.kde.PlasmaShell.loadLookAndFeelDefaultLayout` with the Plasma Fusion Global Theme in use (only the layout: no colours, decoration or fonts are applied). The widgets' global shortcuts are read first; the rebuilt layout's widgets get the key their type had (quick settings Meta+A under owner decision 6, Meta+N before it), and quick settings gets Meta+A when its type had none, the way `fusion-config.sh`'s `ensure_widget_shortcut` does (the pen menu gets Meta+Shift+W only when the old one had it: the setup gives it with `--pen` only; before 0.5.0 the reset gave it to every pen menu): a key still held by a widget of the old layout (an `activate widget N` entry whose widget is gone; old ids are always lower than the new ones) is released with `unregister`, a key another live action holds is left alone and reported, the key is set through the widget and read back. Meta+N for the notification list is a kglobalaccel component of its own (DEVICE-1), not tied to a widget id, so it needs nothing. The widgets' own settings go back to their defaults, as the confirmation says (quick settings' tile order and hidden tiles, its other settings and the keyboard policy among them; the page then reads them from the new widgets); what the page keeps in plasmafusionrc stays. Then the glass level and the top-bar choice are applied to the new panels, extra top bars are removed when Every screen is off, and a running power service is restarted when its tier is not full, so it applies itself to the new widgets. Disabled without a Plasma Fusion Global Theme or without the shell |

With the power service at its critical tier (plasmafusionrc `[Power] Tier=critical` and
`LighterOnCritical`), it holds the glass at Solid and dock magnification off and gives the user's
values back when the battery recovers. The page then shows the magnification the service will give
back (`[Power] UserDockMagnify`) and notes the state; a change of Glass writes `[Effects] Glass`,
`[Power] PageGlass` and the panel opacity, but leaves blur and the widgets' glass key to the
service; a change of magnification writes `UserDockMagnify` and `[Power] PageDockMagnify` instead of
the dock. At recovery the service gives every glass widget and every dock the page's choice instead
of its remembered value, and blur as the page sets it (on for Full and Reduced, also when it was off
for an earlier Solid), then removes the two keys (docs/parts/powerfx.md). Outside critical an
apply removes them, so an old choice never overrides a newer one. Before 0.5.0 the page wrote
`UserGlass`, which nothing read: the widgets got their remembered level back and blur could stay
off.

## Files

| Path | What |
|---|---|
| `packages/kcm-cpp/CMakeLists.txt`, `src/CMakeLists.txt` | ECM / KCMUtils project (`kcmutils_add_qml_kcm`: plugin, QML as resources, generated `kcm_plasmafusion.desktop`) |
| `src/kcm.h`, `src/kcm.cpp` | `PlasmaFusionKcm`: state, load / save / defaults, the configuration-file writes above |
| `src/shell.cpp` | everything through the Plasma shell (desktop scripting over `evaluateScript`: dock, top bar, panels, glass keys, Folder View, widget keys) and the two actions (restore, layout reset with the widgets' shortcuts) |
| `src/settingsfile.cpp` | the settings file: Export my settings, Import settings ("Settings file" below) |
| `src/kcm_p.h` | names and helpers shared by the source files |
| `src/kcm_plasmafusion.json` | plugin metadata: name "Plasma Fusion", icon `plasmafusion-logo`, `X-KDE-System-Settings-Parent-Category: appearance`, weight 1 (first in Appearance & Style), keywords |
| `src/ui/main.qml` | the page (`KCM.SimpleKCM`) |
| `src/ui/FusionPalette.qml` | board colours dark / light; accent-dependent ones from the colour scheme |
| `src/ui/SectionTitle.qml`, `StyleCard.qml`, `Swatch.qml`, `WallpaperPill.qml`, `Segmented.qml`, `ToggleRow.qml` | the board's controls |
| `src/ui/ChoiceRow.qml`, `ActionRow.qml` | a label with a segmented control (side by side, stacked in a narrow window), an action with its explanation and button |
| `packages/common/FusionMetrics.qml` (shared, not this part's) | compiled into the module's resources next to `main.qml` (`src/CMakeLists.txt`; `common/` in the source tarball): board text through `m.font()`, text-holding heights through `m.px()`, so the page follows the user's font size (identical at the default font) |
| `icons/plasmafusion-logo.svg` | the logo mark (three discs), installed as hicolor `apps/plasmafusion-logo` (CC-BY-SA-4.0) |
| `build-remote.sh`, `container-build.sh` | development: build in the container on the ThinkPad and fetch the installed tree (`root/`) for test sessions; the package is built by `packaging/build-rpm.sh --compiled` (system.md) |
| `LICENSES/` | GPL-2.0-or-later (code), CC-BY-SA-4.0 (icon) |
| `tests/` | test tooling, not installed: `offscreen_preview.py` (renders the QML with a stand-in module, laptop; `--report` prints where the content column is), `page_layout_test.py` (the column's place in System Settings' widths, CI `build`), `make-seed.sh`, `session-common.sh`, `scenario-look.sh`, `scenario-interact.sh`, `scenario-decoration.sh`, `scenario-sunset.sh`; 1.0.0-4: `kcmctl/` (loads the plugin as System Settings does and drives it from stdin commands: set, save, load, defaults, call, get, dump; its first line names the plugin file it loaded), `scenario-controls.sh`, `scenario-actions.sh`, `scenario-page.sh`, `scenario-everydock.sh` ("Dock on every screen" on two outputs) |
| `tests/CMakeLists.txt`, `tests/run-kcmctl.sh`, `tests/run-power-tier.sh`, `tests/run-reset-layout.sh`, `tests/run-settings-file.sh`, `tests/shell-panels.sh`, `tests/session-bus.conf` | with `BUILD_TESTING` (on by default; the RPM build turns it off) `kcmctl` is built with the module, and the ctest test `kcmctl-load` loads the built module in a scratch HOME on a private D-Bus session without service activation: every property read, the defaults applied in memory, every property read again; nothing is saved. `tests/fuzz-kcmctl.sh` (ctest test `kcmctl-fuzz`) writes random configuration files and settings files and drives the module with random commands, saving and importing included, in a scratch HOME with stand-ins for the programs it starts. `tests/meters-switch.sh` (ctest test `kcmctl-meters`) turns the system meters switch on and off against `fakeshell` (`tests/fakeshell/`: a stand-in Plasma shell answering `evaluateScript` with a QJSEngine model of desktop scripting, `shell.js`, that can list new widgets late, per bar too, add them at the bar's end or fail to make them): meters placed by hand stay, the new ones are placed before quick settings, also on two bars whose meters are listed 0.4 s and 1.8 s late (the module placed only the first bar's before a71fb66), the errors without quick settings and when the widget cannot be made, Apply returning at once while the shell is slow, and off removing every one. `tests/shell-panels.sh` (ctest test `kcmctl-panels`) changes the panels against it: with a top bar on a missing screen (the model crashes on its opacity, as plasmashell 6.8 does) the state is read and the look applied without touching that bar; with a shell that answers 7 s late (`scriptDelayMs`, `slowFrom`) the page reads it, and turning on the system meters or "Top bar on every screen" reports no error while kcmctl's `heartbeat` timer keeps ticking during Apply. `tests/run-power-tier.sh` (ctest test `kcmctl-power`, with node and python3-gobject) runs the module and the power service against a stand-in plasmashell and KWin (`packages/powerfx/tests/mock-session.py`): the page's choices while a tier is held; `tests/run-reset-layout.sh` (`kcmctl-reset`) the layout reset and the keys it gives, `tests/run-settings-file.sh` (`kcmctl-settingsfile`) the settings file. The `compiled` and `sanitizers` workflows run all seven (docs/parts/ci.md, "Dynamic analysis") |

## Build

```
packages/kcm-cpp/build-remote.sh [OUTDIR]       # default OUTDIR build/kcm-cpp
```

It packs `CMakeLists.txt src icons LICENSES` and `common/FusionMetrics.qml` (from
`packages/common`) into a reproducible tarball (run it from a clean checkout of the commit to
package, not a working tree with other lanes' edits), copies it with the spec to
`/tmp/pfv-kcm-build` on the ThinkPad (`PF_REMOTE_DIR`, must be below `/tmp/pfv-`), and runs
`nice -n 10 podman run --rm --network=none -v DIR:/work:Z localhost/plasma-fusion-build:f44-6.7.5
bash /work/container-build.sh` (`rpmbuild -ba`, `-j6`). OUTDIR gets `RPMS/x86_64/`
(`plasma-fusion-settings-1.0.0-4.fc44.x86_64.rpm` plus debuginfo / debugsource), `SRPMS/`,
`build.log` (no compiler warnings with KDE's `-Wall -Wextra` set) and `root/` (the RPM unpacked,
for test sessions). About a minute, most of it copying.

Package contents:

```
/usr/lib64/qt6/plugins/plasma/kcms/systemsettings/kcm_plasmafusion.so
/usr/share/applications/kcm_plasmafusion.desktop      (Exec=systemsettings kcm_plasmafusion, NoDisplay)
/usr/share/icons/hicolor/scalable/apps/plasmafusion-logo.svg
/usr/share/licenses/plasma-fusion-settings/{GPL-2.0-or-later,CC-BY-SA-4.0}.txt
```

Requires `plasma-systemsettings`, `plasma-workspace` (`plasma-apply-lookandfeel`,
`plasma-apply-colorscheme`, the accent-colour and automatic light/dark kded modules),
`kf6-kirigami`, `kf6-kcmutils`, `qt6-qtdeclarative`, `hicolor-icon-theme`; all 28 requirements of
1.0.0-3 resolve on the ThinkPad (checked with `rpm -q --whatprovides`). 1.0.0-4 adds no requirement
(the layout reset and the power-service restart use `org.kde.PlasmaShell` and `systemctl`, present
on every Plasma session).

The spec's QML time stamp (`SOURCE_DATE_EPOCH` from a hash of the sources) includes
`common/*.qml`, so a changed FusionMetrics gives a new stamp too.

## Install, open, roll back (lead / real session)

1.0.0-3 is installed (2026-09-30 01:19Z). The 1.0.0-4 RPM of KCM-1 is in
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build2/KCM-1/rpm/` (with `SHA256SUMS`); PKG-1
builds the final one from the INT-1 commit with `build-rpm.sh`. The lead installs it at DEPLOY-1:

```
sudo dnf install ./plasma-fusion-settings-1.0.0-4.fc44.x86_64.rpm   # upgrades 1.0.0-3
systemsettings kcm_plasmafusion          # or System Settings > Appearance & Style > Plasma Fusion
kcmshell6 kcm_plasmafusion               # the page alone
sudo dnf remove plasma-fusion-settings   # rollback of the package (or dnf downgrade to 1.0.0-3)
```

The package changes nothing by being installed. Apply writes only the keys listed above, and every
control can be set back on the page (Defaults gives the Plasma Fusion defaults). The two actions
are undone by choosing Light / Dark (restore) or by `fusion-restore.sh` with a backup taken
before (layout reset: panels, pins and desktop icon positions come from the backed-up
`plasma-org.kde.plasma.desktop-appletsrc`). `tools/device/fusion-restore.sh` restores kdeglobals,
kwinrc, plasmafusionrc and the shell layout from a fusion-config.sh backup.

## Behaviour

- Load: every value is read from the session when the page opens (kdeglobals, kwinrc,
  plasmafusionrc; the dock, top bars, quick settings, launcher and Folder View desktop through one
  evaluateScript call, asynchronously; the controls that depend on them are disabled for that
  moment). Style shows nothing chosen when the current Global Theme
  is not Plasma Fusion (or automatic switching uses other themes). An accent colour that is not a
  board swatch shows no swatch chosen and is kept.
- Nothing is written until Apply (checked: the state files before and after a pending change are
  identical). Reset reads everything again; Defaults = Dark, Blue (scheme accent), Right · glyphs,
  the Plasma Fusion decoration when it is installed, magnify on, global menu on, hot corner off;
  1.0.0-4: snap layouts on hold, Glass Full, high contrast off, reduce motion off, 62 px, solid top
  bar next to windows, a top bar on every screen, desktop icons on at Medium, file drag Ask,
  lighter at 10 % on, tablet mode Automatic, apps full screen, dock hides over apps, keyboard in
  tablet mode only, edge swipes off, home indicator on; the launcher's three sections on (2026-10-16).
  Apply writes only what changed, in this
  order: Style, colour scheme (high contrast), accent (on top of the scheme just applied), window
  buttons, snap layouts and hot corner (one KWin reconfigure), glass (plasmafusionrc and blur),
  motion, file drag, battery, tablet keys (then the tablet script's shortcut), then the shell:
  dock, home indicator, top bar menu, panels and glass keys, top bars on other screens, desktop,
  keyboard policy.
- The shell steps of Apply and of the two actions run one evaluateScript call after the other,
  each on the answer of the one before. Each call may take up to 25 s (Qt's default D-Bus
  timeout; 5 s until 0.5.0): right after a plasmashell restart a script that adds widgets or bars
  took longer than 5 s in the test VMs, the change was still made, and the page showed "Did not
  receive a reply" for "Top bar on every screen" and the system meters switch. The page waits in a
  local event loop that holds back user input (not with a blocking call), so it keeps drawing and
  shows that it is busy, and KWin does not take it for a frozen window; the shell state read when
  the page opens and the meters' placement are asynchronous and use the same 25 s. A shell state
  answer that arrives while Apply or an action is running is read again after it. D-Bus calls to
  KWin and kglobalaccel keep 5 s.
- Light / Dark run `plasma-apply-lookandfeel` synchronously, like the Global Theme page applies a
  theme: System Settings waits about 1-2 s.
- "From wallpaper" asks Plasma for the colour when chosen (a read: Plasma's own accent service
  only applies it when `accentColorFromWallpaper` is set) and shows it as the ring around the pill;
  Plasma keeps updating it when the wallpaper changes. The Plasma Fusion wallpaper declares
  `#2F6FDF` as its accent colour, so "From wallpaper" on it gives `AccentColor=47,111,223`; as for
  any accent colour, Plasma then derives the selection colour itself (light: 109,154,232 with
  black selected text; dark: 42,88,175), so the page and the desktop look paler than with Blue,
  which keeps the colour scheme's own tuned colours.
- With the Plasma Fusion decoration installed but another decoration in use, a note with a
  "Use It" button appears under the window buttons. "Show on hover" without that decoration shows a
  note that the buttons stay visible (the Aurorae themes cannot hide them).
- Follow sunset: when Plasma switches the Global Theme while the page is open (it does so right
  after Apply when the other variant is due), the Global Theme brings its own decoration; the page
  notices the switch (LookAndFeelPackage notification, checks at 1.5 / 3 / 6 / 10 s) and writes the
  chosen window buttons again. Verified with and without the decoration (see Verification).
  Switches at dawn and dusk while the page is closed are not covered (see "Needs").
- Changes made elsewhere (quick-settings Dark style tile, Colors page, automatic switching, the
  Animations page's slider, the quick-settings tablet switches, the power service) show up on the
  open page while nothing is pending (KConfigWatcher on kdeglobals, kwinrc and plasmafusionrc).
- Errors (a tool failed, a theme is missing, the shell did not answer) are shown in an inline
  message at the top of the page; the dock / global-menu switches say so when the Plasma Fusion
  dock or top bar is not on the desktop, or when the Plasma shell is not running (they are read
  again 3 s after it starts; a change still pending on them is kept). A dock or top-bar change
  that cannot be applied because the shell stopped meanwhile is dropped on Apply, so the page shows
  what is in effect. 1.0.0-4: the same holds for every control that goes through the shell (glass,
  magnified size, solid top bar, every screen, desktop icons and size, keyboard, home indicator)
  and for the layout reset; each has the same notes (not running / widget or Folder View desktop
  missing).
- The two actions run at once after their confirmation (a Kirigami prompt), not on Apply; a busy
  indicator shows next to "Start over" and both buttons are disabled meanwhile. The result or an
  error is shown in the message area at the top (a positive message lists the shortcuts the
  reset gave). Restore reloads the page (the Global Theme changed everything); the layout reset
  keeps changes still pending on the page.
- Keyboard: Tab reaches every card, swatch, pill, segment and switch row (each is a tab stop, as
  with Qt Quick radio buttons); Space chooses or toggles (Return does not, as in other Qt Quick
  controls); Left / Right in the segmented control choose the neighbouring segment and move the
  focus with it; 2 px focus ring in the scheme's focus colour (outside the selection ring on a
  chosen swatch or pill, 1 px outside a segment). Accessible roles and names are set (radio
  buttons, check boxes, groups, headings).

## Look (board values, logical px)

| Board (Main.dc.html / MainLight.dc.html) | Implementation |
|---|---|
| content padding 20 / 24, sections 18 apart, title to content 10 | `SimpleKCM` paddings 20 / 24, `ColumnLayout` spacing 18 / 10; section titles laid out as 16 px lines (the CSS line box is 16.4 px), so rows land on the board's: measured card top 27, segmented control 239, first switch 297 in board and session |
| section title 12 px ExtraBold #a3abc2 / #5b6278 | same (static Manrope ExtraBold via the system font family) |
| cards 124 x 72, radius 10, 2 px border rgba(255,255,255,.1) / rgba(20,24,39,.1), selected #5b9dff / #2f6fdf; bar 8 px, window 62 x 36 at 14,16 radius 5 with 0 2 6 shadow, dock 48 x 8 radius 4 at 5 from the bottom; sunset card halves 60 + 60 with a 46 x 36 window at 38 | same geometry (contents in the 120 x 68 padding box, per-corner radii); selected border = the scheme's DecorationHover (dark, #5b9dff) / DecorationFocus (light, #2f6fdf), so it follows an accent; measured exact |
| card label 12 px, #cdd3e4 / #3a4157, chosen 800 #cfe0ff / #1d4fb0 | same; with another accent: derived from it |
| swatches 26 px, 10 apart; chosen: 2 px page-colour gap and 2 px ring | same; hover grows the swatch to 1.08 |
| "From wallpaper" 26 px pill, padding 0 10, 1 px dashed rgba(255,255,255,.3) / rgba(20,24,39,.3), 11.5 px 700 | same: text width + 22 (padding and border), Canvas edge with 2 px dashes and 1 px gaps as the browser draws them; chosen: the swatch ring in the wallpaper colour, solid edge; measured 104 px wide against the board's 106 (text rendering) |
| segmented 34 px, padding and gap 3, radius 10, rgba(255,255,255,.06); segments radius 7, flex widths; chosen #2f6fdf with white 12 px 800, others 12 px 600 #cdd3e4 / #3a4157 | same; widths = text width (measured at 800) + an equal share of the rest; chosen = Selection background and text |
| switch rows 40 px, 13 px text, 1 px rgba(...,.06) lines; switch 40 x 22, knob 18 at 2 px, on #2f6fdf, off rgba(255,255,255,.18) knob #e8ebf4 / rgba(20,24,39,.18) knob white with 0 1 3 shadow | same; animated knob |

## Verification

The builder's checks (1.0.0-1); the review's checks of 1.0.0-3 are under "Review" at the end.

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

## Verification, 1.0.0-4

KCM-1 builder `o1km`; the lead took the lane over at 04:31Z and made the final build and runs.

- Build: the x86_64 RPM in the Fedora 44 build container on the ThinkPad (`build-rpm.sh`), 0 compiler
  warnings; rpmlint as 1.0.0-3. Local compile check with the laptop's KF6: 0 warnings. qmllint: only
  the unqualified `kcm` / `i18n*` names, as at HEAD.
- `o1km-a` (`tests/scenario-controls.sh`, 1920 x 1200 at 4/3, the module driven through `kcmctl`):
  96/96. Covered: pending changes, Apply and Reset; snap layouts hold or hover; Glass Full, Reduced
  and Solid (blur loaded or not, panel opacity, each Fusion widget's `glass`, the top-bar choice
  kept); reduce motion (factor 0, the previous factor kept and given back); dock magnification 56,
  62 and off; desktop icons off and on (filter keys; icon positions unchanged, also across a shell
  restart); icon size; file drag; battery; tablet always, never and automatic (KWin follows the
  key, the page follows KWin), apps windowed or full screen, the dock in tablet mode, edge swipes,
  keyboard policy, home indicator; high contrast (scheme, forced Solid, kept after Light, off gives
  Dark and Full back; switching it off before Apply leaves nothing pending); pending changes
  survive a page restart; a stopped shell; the critical power tier (the user's glass and
  magnification remembered, blur left unloaded, the dock's glass left to the power service);
  Defaults.
- `o1km-b` (`tests/scenario-actions.sh`, two outputs): 23/23. Top bar on every screen off and on;
  Reset layout twice (the quick-settings key carried over, Meta+N and Meta+A; the pen widget gets
  Meta+Shift+W; the glass applied to the new panels); Restore previous desktop ("My previous
  desktop", the page then shows no Fusion style and offers the layout reset only with a Fusion
  theme).
- `o1km-c` (`tests/scenario-page.sh`, 1440 x 2400 at 1): the whole page in System Settings and in
  `kcmshell6` (`p01-systemsettings-top.png`, `p02-kcmshell-full.png`). The High Contrast switch is
  disabled there ("not installed"): that stage has no High Contrast scheme yet (STYLE-1).
- Lead change: after `plasma-apply-colorscheme --accent-color` the module announces the palette
  change again (KGlobalSettings `notifyChange`, PaletteChanged). The tool's accent path in
  plasma-workspace 6.7.5 announces it before kdeglobals is written (it does not sync; the file is
  written when the tool exits), so plasmashell could read the old accent (BASE-1 found it).

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build2/KCM-1/` (RPMs with
`SHA256SUMS`, the three runs, notes).

## Deviations from the board, with reasons

- The board's window is System Settings itself: its sidebar sections (Desktop & Dock, Top bar,
  Windows, Workspaces, Notifications, Displays) are not part of this module. The page is one
  module under Appearance & Style with System Settings' own header ("Plasma Fusion") and its
  Defaults / Reset / Apply footer; the board shows instant changes without buttons.
- The content column stops at 560 px (the board's is 420 px in its 652 px window), so in a wide
  System Settings window the segmented control and switch rows are wider than on the board. There
  the column stands in the middle of the page, on a whole pixel, as System Settings' own pages
  centre their form (Kirigami 6.31 `FormLayout.qml`: `anchors.horizontalCenter:
  root.horizontalCenter`); the board's window is no wider than its column, so it shows no
  difference. Until 2026-10-16 the column stood at the page's left edge.
- Blue means the colour scheme's own accent (#2f6fdf with its tuned focus, hover and link colours)
  and is drawn #5b9dff as on the board; the other swatches become Plasma's accent colour, and
  Plasma (not the board) derives the selection colour from it (70 % accent over the view
  background, e.g. teal → 51,148,142 dark, 118,213,199 light with black selected text).
- States the board does not draw: "From wallpaper" chosen (swatch ring in the wallpaper colour),
  hover on cards, swatches and segments, keyboard focus rings, the notes described above.
- Text uses the session's font rendering (subpixel antialiasing, whole-pixel glyph advances), the
  board's is greyscale with fractional advances; the 11.5 px pill text is about 2 px narrower.
- Follow sunset relies on Plasma's automatic light/dark switching (its schedule, idle handling
  and location), not on a Plasma Fusion service.
- 1.0.0-4: the controls below the board have no board. They reuse the board's section titles,
  segmented control and switch rows; a segmented control in a row sits right of its label (under
  it in a narrow window). The dock magnification is the board's switch plus a size row (56 / 62 px)
  rather than one Off / 56 / 62 control, so the board's rows stay where they are.
- "On-screen keyboard: Tablet mode only" (TABLET.md 4.15) reads "Tablet mode" to fit the row.
- Text sizes follow the user's font size (FusionMetrics); the board's values hold at the Plasma
  Fusion default font.

## Needs from other parts

1.0.0-4 (KCM-1). Keys the page writes for other parts, and what those parts need to do with them:

- Lead (registry, low): two plasmafusionrc keys are new and belong in the registry (plan section 2,
  `docs/PLAN.md`): `[TopBar] EveryScreen` (bool, default true; "Top bar on every screen", decision
  8, which had no key) and `[TopBar] SolidNextToWindows` (bool, default true; the "Solid next to
  windows" choice while Reduced glass makes the bars opaque, and for bars added later). The page
  also writes the power service's `[Power] UserGlass` / `UserDockMagnify` while the tier is
  critical (below).
- Layout (LAYOUT-1), medium: `ensure-topbars.js` (installed as `contents/layouts/ensure-topbars.js`
  of both Global Themes, where the page looks for it) should do nothing when plasmafusionrc
  `[TopBar] EveryScreen` is `false` (`ConfigFile("plasmafusionrc", "TopBar").readEntry("EveryScreen")`),
  so KWin's hot-plug hook (KWIN-2) respects the switch, and give a new bar the opacity of the
  page: `opaque` when `[Effects] Glass=Reduced`, else `adaptive` when `[TopBar] SolidNextToWindows`
  is not `false`, else `translucent` (the page applies both after it runs the script itself). The
  layout script can do the same for a fresh layout; after "Reset Fusion layout" the page applies
  them anyway.
- Style (STYLE-1), medium: the page looks for the high-contrast scheme as
  `color-schemes/PlasmaFusionHighContrast.colors` (scheme id `PlasmaFusionHighContrast`); name the
  file that way, or tell the settings lane the id. The switch is disabled until it is installed.
- Power (POWER-1), medium: the page reads `[Power] Tier` (expects `critical` for the critical tier)
  and, while critical and `LighterOnCritical`, writes the user's choices into `[Power] UserGlass`
  (`Full` / `Reduced` / `Solid`, the `[Effects] Glass` names) and `UserDockMagnify` (`true` /
  `false`) instead of loading blur or changing the dock, so the service restores what the user
  chose when the battery recovers. The service should use exactly these names and values (or tell
  the settings lane). The page restarts the service (`systemctl --user try-restart
  plasma-fusion-powerfx.service`) after a layout reset when the tier is not `full`, so it applies
  its `powerTier` keys to the new widgets.
- KWin tablet script (KWIN-1), low: the "Plasma Fusion: Tablet Window Mode" shortcut handler
  should also re-read `EdgeLeft` and `EdgeRight` (TABLET.md 4.2 names only `WindowMode` and
  `DockHiding`); the page invokes it after any of the four keys changes.
- Quick settings (QS-1), dock (DOCK-2), launcher (LAUNCH-1), cards (CARD-2): declare the keys the
  page writes in each widget's `main.xml` so the running widget follows at once (the page writes
  through the widget's configuration scheme): `glass` (String `full` / `reduced` / `solid`) on the
  dock, quick settings, launcher and system card; `keyboardPolicy` (`tablet` / `touch` / `never`)
  on quick settings; `homeIndicator` (Bool) on the dock. Until then the key is stored and read at
  the next start of the widget.
- Decoration (DECO-1), low: the page always writes `[Decoration] SnapLayoutsOnHover` `true` or
  `false` and reconfigures KWin; the decoration reads it at reconfigure (it does today).
- Device scripts (DEVICE-1), low: `fusion-restore.sh` restores plasmafusionrc from the backup
  (already), which undoes `[Effects]`, `[Motion]` and `[TopBar]`; the kdeglobals keys
  (`DndBehavior`, `AnimationDurationFactor`) and the kwinrc keys (`[Input] TabletMode`,
  `[Script-plasmafusion-tablet]`, `[Plugins] blurEnabled`) are in files it already restores. If the
  restore does not load blur again after a Solid level, add `qdbus org.kde.KWin /Effects
  loadEffect blur`.
- Tests (TEST-1), note: after desktop icons were hidden and the shell restarted, Plasma rewrites
  the positions JSON header (row count and rows per column: `["1","9"]` instead of `["5","7"]`
  in o1km-a) while every file's entry stays the same; an M2 check that compares the whole JSON
  byte for byte across such a restart would report a change. Compare the entries (as
  `tests/session-common.sh same_positions` does), or the screenshots.
- Not built (open): the S11 "What changed" list for `[Config] FusionConfigVersion` (DEVICE-1 writes
  the change list; the page has no list yet: its format is DEVICE-1's), and "Use stock widgets
  (safe mode)" (deferred by the plan).

Earlier (1.0.0-3), kept for the record:

- Look-and-feel (Global Themes), medium, now actionable: both Global Themes still set
  `[kwinrc][org.kde.kdecoration2] library=org.kde.kwin.aurorae.v2` and the Aurorae theme, and every
  Global Theme apply writes them to kdedefaults and removes the user's values. Everything that
  applies a Global Theme without this page therefore drops the chosen window buttons: Plasma's
  automatic switching at dawn and dusk (Follow sunset), the quick-settings Dark style tile
  (`plasma-apply-lookandfeel -a`), fusion-config.sh. With the Plasma Fusion decoration the title
  bars go back to Aurorae (the page then shows its "Use It" note); with the Aurorae fallback and
  Left · circles the right-hand theme is shown with the left-circles button lists. The decoration
  package is installed system-wide on the ThinkPad since 2026-09-30 00:08Z, so name
  `library=org.plasmafusion.decoration` with an empty `theme` in both Global Themes (the decoration
  follows the colour scheme, plasmafusionrc is not touched by a Global Theme, and Plasma skips a
  decoration that is not installed). The page itself re-applies the buttons whenever it applies a
  theme and while it is open (verified).
- Device scripts (`tools/device/fusion-config.sh` / `fusion-restore.sh`), low: add
  `plasmafusionrc` to the backed-up files so a restore also removes the window-button choice.
- Dock (observation, low): in the virtual sessions the name pill and the magnification stay after
  the pointer jumps off the dock (absolute EIS motion) until it comes back; worth one check with a
  real mouse.
- Lead: install `plasma-fusion-settings-1.0.0-3` (commands above); the module needs no other
  change on the device. With the decoration installed, the first visit shows the "Use It" note
  until the Plasma Fusion decoration is chosen (Use It, any window-button choice, Light / Dark, or
  Defaults, then Apply).

## ThinkPad changes made by this part

None outside `/tmp/pfv-*` and `/var/tmp/pfv-*`: no sudo, no system files, the RPM is not installed,
the real session untouched. Build scratch `/tmp/pfv-km-build` (tarball, rpmbuild tree) and virtual
sessions `/tmp/pfv-km-1..12` (earlier tooling) and `/var/tmp/pfv-km-*` (removed by remote.sh); the
podman containers ran with `--rm` (no image built or pulled; the SELinux relabel of `:Z` applies
only to the scratch directory). All removed at the end.

Review (2026-09-29, prefixes `rkm-` and `rkm2-`): build scratch `/tmp/pfv-rkm2-build` and virtual
sessions `/var/tmp/pfv-rkm2-1..5` (removed); the final RPM and its `.sha256` copied to
`/var/tmp/plasma-fusion-rpms/kcm-cpp/` for the lead (kept). One session (rkm2-1) ran inside an
unprivileged `bwrap` mount namespace that hid the system-wide decoration plugin from that session
only. No sudo,
no install, no input to the real session, no processes of the real session touched.

## Review

Adversarial review, 2026-09-29. It continues the first review (prefix `rkm-`, killed by the
laptop reboot at 23:50Z; its fixes are in commit 12d00d3, its run rkm-6 left no results). Every
earlier fix was checked again in the code and in the runs below. Result: `1.0.0-3`, ready to
install.

Build checks (1.0.0-3, `build/rkm2/kcm`): 0 compiler warnings with KDE's `-Wall -Wextra` set;
rpmlint only `no-url-tag`, `no-documentation`, `no-%check-section`, `invalid-url Source0`,
`desktopfile-without-binary` (System Settings is not on the build host) and `incorrect-fsf-address`
in the verbatim GPL-2.0 text (licence text left as published); `desktop-file-validate` clean;
qmllint (Qt 6.11.2) clean apart from the unqualified `kcm` / `i18n` context names; the SRPM's
tarball and spec are identical to the tree; all 28 requirements resolve on the ThinkPad.

Runs (private virtual sessions on the ThinkPad with the whole stage installed by fusion-config.sh;
scenarios, state dumps and logs in the share's `kcm-cpp/review-states/`; `build/rkm2/remote-run.sh`
is `tools/vsession/remote.sh` plus the optional `bwrap` wrapper):

| Run | Setup | Checked |
|---|---|---|
| rkm2-1 | Light, 1440x900, scale 1, decoration hidden (Aurorae fallback) | the missing rkm-6 checks: board comparison, From wallpaper, Show on hover note, Left · circles + Follow sunset (after dusk Plasma switched to Dark and the page put `PlasmaFusionDark-Left` back within 3 s); keyboard; a second Apply inside the re-apply window; 8 Apply clicks within a second (one apply, no error); a Global Theme applied from outside while the page is open (page follows) |
| rkm2-2 | Dark, scale 1, the system-wide decoration | Use It, Right · glyphs / Left · circles / Show on hover (hidden away from the title bar, shown over it), Light, Follow sunset from Light (decoration kept after the switch to Dark), Dark, a pending switch across a shell restart, no panels, no shell, a Global Theme applied while the page is closed then Use It again, Defaults |
| rkm2-3 | Dark then Light, 1920x1200 at scale 1.325 (the real session's) | look and focus rings at the fractional scale, kcmshell6 |
| rkm2-4 | Dark, scale 1, final build | Overview edges `7,3` → off `3` → on `7,3` → off without the shell `3`; segment focus ring; pill width |
| rkm2-5 | Dark and Light, scale 1, final build | the board state in both variants; a switch change that cannot be applied (shell stopped) is dropped; regression pass (Teal + Left · circles + hot corner, Light, Defaults) |

Board comparison (rkm2-5, System Settings at scale 1 against desktop-dark-1 / desktop-light-1,
`review-sbs-*-board-vs-session-2x.png`): measured from the section title's top, the card top (22),
swatches (161-186), segmented track (231-264), switches (292, 333, 374) and row lines (323, 364)
are on the board's rows in both variants; colours within 1-2 levels of the render (page, card
fills, track, chosen segment #2f6fdf, switch on / off, knob). Remaining differences are the
documented ones (560 px column, text rendering: the pill is 104 px against 106).

Decoration contract with the system copy (`plasma-fusion-decoration-1.0-2`, `rpm -V` clean): the
session's `QT_PLUGIN_PATH` held only the module's directory (no `org.kde.kdecoration3` in it); after
Use It KWin's supportInformation shows `Plugin: org.plasmafusion.decoration` with an empty theme,
and every button style, Light / Dark, Follow sunset and Defaults work with it.

Re-verified fixes of the first review: switch rows 41 px apart (measured); `ComponentBehavior:
Bound`, minimum width and wrapping (qmllint, runs); absolute OUTDIR; `hicolor-icon-theme`; the
source-derived QML time stamp (rkm-2 showed stale QML without it and the new QML with it; each of
this review's builds got a new stamp); `quit_app` / `session_pids` (used in every run, only PIDs of
the private session; whether the builder's old `pkill -f "^systemsettings"` ever closed the real
session's System Settings cannot be established afterwards); reload after a failed Apply (code;
rkm-2); the shell watcher (rkm2-2, rkm2-5: notes switch to "not running" and back).

Findings of this review, fixed in 1.0.0-3:

- Medium: after Follow sunset, a second Apply within 20 s (for example another window-button
  choice) was undone at the next re-apply check, which still used the button style of the first
  Apply. The re-apply now uses the applied choice (`m_saved`); rkm2-1 kept Right · glyphs.
- Medium: a pending dock or top-bar switch change was silently replaced when the Plasma shell
  restarted while the page was open. It is kept now (rkm2-2); a change whose dock or top bar is gone
  at Apply (shell stopped) is dropped instead of being shown as applied (rkm2-5).
- Low: the hot-corner switch overwrote every Overview screen edge the user had set on the Screen
  Edges page; now only the top-left corner is added or removed (rkm2-4).
- Low (keyboard): Left / Right in the window-button control chose the neighbour but left the focus
  on the old segment, and the focus mark on the chosen segment was a faint white inner edge. The
  focus now moves with the choice, and every segment gets the page's 2 px focus ring 1 px outside
  (rkm2-1, rkm2-4).
- Low (look): the From wallpaper pill left out the CSS border (text + 20 instead of text + 22).
- Docs: Return does not choose (only Space; the doc said Space / Enter); From wallpaper on the
  Plasma Fusion wallpaper does not give the Blue look (Plasma derives a paler selection from any
  accent colour); the pill text difference is about 2 px, not 4.
- Test tooling: `dump_state` wrote the scenario's `set -x` trace into every state file.

Open (not in this part's files):

- The Global Themes still name the Aurorae decoration, so Follow sunset at dawn and dusk with the
  page closed, the quick-settings Dark style tile and fusion-config.sh put Aurorae back (see
  "Needs"). This matters now that the decoration is installed.
- Without the decoration, Show on hover keeps the buttons visible (Aurorae limit; the page says so).
- Not checked with real hardware input; everything above used KWin's EIS input in virtual
  sessions.

## INT-1 (2026-09-30)

`tests/scenario-controls.sh` against the integration build 321228a (plain dock frame, LAYOUT-1's
layout): 96/96 after three expectations were brought up to date. Since LAYOUT-1 the layout makes
the top bar solid next to maximized windows (owner decision 5), so after Reduced the top-bar choice
kept is `SolidNextToWindows=true` and Solid gives back `adaptive` (the test expected the old
`false` / `translucent`); and the "Reset" check now takes the tablet-mode choice the session
started with (the integration runs start with `TabletMode=off`, the lane's with automatic). No
change in the module.

## Search inside file contents (1.0.0-6, 2026-10-01)

Battery section: "Search inside file contents" (Apply/Reset like every row). It is Baloo's own key,
`baloofilerc [General] only basic indexing`, the one System Settings > File Search writes; after
writing it the module calls `org.kde.baloo / org.kde.baloo.main updateConfig`, as that page does
(`Baloo::IndexerConfig::refresh`). On by default (owner: keep content indexing, let the user turn it
off). Baloo already stops content indexing on battery (baloo `FileIndexScheduler::powerManagementStatusChanged`),
so the switch mostly saves power while charging; file names stay searchable. Search keywords: file
search, file contents, indexing, baloo. Test: `scenario-controls.sh` now 98 checks (off writes `true`,
on writes `false`), all PASS.

## Content in the middle of the page (2026-10-16)

In a System Settings window wider than the 560 px column, the column now stands in the middle of
the page instead of at its left edge, as System Settings' own pages centre their form (the
owner's request; "Deviations from the board" has the reason the board shows no difference).

- `tests/page_layout_test.py` (CI `build`, offscreen, through `offscreen_preview.py --report`):
  in windows of 1720, 900 and 640 px the 560 px column stands in the middle of the page on a
  whole pixel; at 500 px it takes the page's whole width. Without the change the three wide
  windows fail (the column at x 0).

## Launcher sections (2026-10-16)

A Launcher group after Dock and top bar: recent files under the pinned apps, the Recent chip
(recently and often used apps) and the Places chip, each a switch over every launcher widget's
key (`showRecommended`, `showRecentApps`, `showPlaces`), read and written through the shell as the
dock's keys. Before, only the recent files could be turned off, in the launcher's own settings
(the next-queue proposal's item 1, approved 2026-10-16).

- `tests/shell-panels.sh` (ctest `kcmctl-panels`), cases `launcher` and `nolauncher`, against the
  stand-in shell (which now takes widget configuration in the layout and lists it with
  `showConfig`): the keys read (an unset key as on, `"false"` as off), Apply writes the two that
  changed and leaves the third alone, no error; without a launcher widget the switches are not
  available and keep their value, and nothing is written. Case `twolaunchers` (review): two
  launchers, the second with the Places chip off, show it off, and turning it on writes it to
  both. Case `mixedoff` (review): the same launchers; the page says the Places chip is mixed (not
  the Recent chip, which they agree on), the switch turned on and back off still needs Apply, and
  Apply writes off to both, after which they agree. Case `mixedrestart` (review): the same, with the
  stand-in shell stopped and started again between the switch and Apply: the switch set before is
  still a change, and Apply still writes off to both. Without the module's write, read or launcher
  count the cases fail; reading the first launcher only fails `twolaunchers`; without the mixed
  state `mixedoff` fails (the first launcher kept the Places chip on); clearing it when the shell
  goes away fails `mixedrestart`.

## Dock on every screen (2026-10-16)

The next queue's item 3 (approved 2026-10-16): per-monitor behaviour (PowerToys' "independent
desktops per monitor", 338 thumbs-up; Microsoft lists per-monitor taskbar positions as
"evaluating"). Before, one dock on the main screen; the top bar already had "Top bar on every
screen". The new switch under it keeps its choice in plasmafusionrc `[Dock] EveryScreen`, which
`ensure-topbars.js` reads at login, when a screen is added, after Apply and after a layout reset.

- `tests/shell-panels.sh` (ctest `kcmctl-panels`), cases `docksoff`, `docksofffail` and `dockson`
  against the stand-in shell (whose panels now have a stable id and can be removed, and which can
  answer a script with an error, `failScripts`, as plasmashell answers a failing script):
  turned off, the copy's panel goes, a second dock of the user's on the main screen stays, and the
  docks left get back the `showOnlyCurrentScreen` they remembered (their `onlyCurrentScreenBefore`
  emptied); with the removal failing, an error, the choice stays on in plasmafusionrc and on the
  page, and every panel is still there; with only copies left (`docksoffcopies`), the one on screen
  0 stays, no longer a copy, listing every screen's windows; a copy's panel without its dock goes
  too (`docksoffpanel`); with the one original on an unplugged screen (`docksoffunplugged`) the copy
  on screen 0 stays, standing in for the unplugged one, and the unplugged dock gets its value back;
  with every dock widget removed (`docksoffnodock`) the switch still turns off, the copy's panel
  goes and the choice is stored, and so do Defaults and Apply (`docksdefaults`); turned on by
  another program while the page is open (`docksexternal`, `kwriteconfig6 --notify`), the page reads
  it, as plasmafusionrc `[Dock]` is one of the groups it watches; turned on, the choice is kept and
  ensure-topbars.js runs, and a script that says it could not make a dock (`docksnotmade`) or that
  the docks are not on a screen yet (`docksskipped`) gives an error.
  The removal of every dock but the lowest screen's (before review) fails `docksoff`, and no
  roll-back fails `docksofffail`. The layout side is tested in
  packages/look-and-feel/tests/layout.test.js.
- Session test (`tests/scenario-everydock.sh`; 2026-10-16, a private session on the Fedora 44 test
  laptop with two outputs, Plasma 6.7.5, the module and kcmctl from this change; the real
  plasmashell and `ensure-topbars.js`): **7 checks pass**, also again after the fourth review
  round's changes. After the setup, one dock on screen 0
  listing every screen's windows; turned on, a dock on each screen, the new one a copy with a
  launcher of its own and both listing their own screen only, no error; turned off, the copy's
  panel goes and the dock left lists every screen's windows again, no error.
- `tests/run-reset-layout.sh` (ctest `kcmctl-reset`, review): with the switch saved on, the layout
  reset runs ensure-topbars.js (a stand-in) and reports nothing about the docks; without the script
  it says the other screens' docks could not be added back, and with a script that fails it says
  the docks could not be added. Before, both were silent and the reset said the layout was back.

## Settings file (2026-10-16)

"Export my settings…" and "Import settings…" (at the start of Start over) move this page's
settings and the panels to another computer or back to later (`src/settingsfile.cpp`). No board has
them; they are two more `ActionRow`s with the system's file dialog (`QtQuick.Dialogs`), Documents
and `plasma-fusion-settings.json` by default.

The file is one JSON object, `{"format": "plasma-fusion-settings", "version": 1, "settings": {...},
"layout": {...}}`:

- `settings`: the page's settings by their property names (`kcm.h`), numbers for the choices (the
  enums there), `true` / `false` for the switches, plus `accentMode`, `accentColor` (`#rrggbb`, for
  a fixed colour), `fusionDecoration` and `decoration`, the decoration KWin uses (kwinrc
  `[org.kde.kdecoration2]` `library`, `theme`, `ButtonsOnLeft`, `ButtonsOnRight`; Apply always
  uses Plasma Fusion's when it is installed, so a file made with another one names it).
  `style` is left out while another Global Theme than
  Plasma Fusion's is in use. These are the applied values: the power service's held values do not
  show on the page (it shows the user's), and neither does a change not applied yet.
- `layout`: what the Global Theme's `export-layout.js` prints in plasmashell
  (docs/parts/lookandfeel.md, "Settings file"): each panel with its screen, place, look and own
  configuration, its widgets in order with their global shortcut and every configuration group.
  The docks "Dock on every screen" made and the panels of screens that are not connected are left
  out; the page says how many of the latter.

A file larger than an import takes (8 MiB) is not written: the page says how large it would be.

Import first reads the whole file, a regular file only and no more than 8 MiB of it (a FIFO
would block the page when it is opened, until something writes to it, and a device such as
`/dev/zero` has no size and no end; Qt 6.11.2 takes only `S_IFREG` for a file): one that is not
JSON, not of this format or version, without panels, or with a panel or widget that is not
complete is refused with the reason, and nothing changes. Complete means every value `import-layout.js` gives the new panel as plasma-workspace
6.7.5's `Panel` takes it (the old panels are gone before the new ones are made): a whole screen
number, an edge, a whole height above 0, `floating` and `floatingApplets` true or false, one of
the length modes, alignments, hiding and opacity modes `Panel` knows, the four lengths as whole
numbers when the length is custom, widgets with a type, a shortcut as text, configuration values
as text. Then:

1. the settings are set as if on the page (each setter takes only what the page can show; high
   contrast before the glass, which it would otherwise set to Solid) and applied by Apply's own
   code. High contrast without its colour scheme and the Fusion decoration where it is not
   installed are named; a value the page does not take (out of range, or of the wrong type) is
   counted and left as it was. After Apply, a file made with another decoration gets it back
   (the four kwinrc keys, then KWin reconfigures) when it is installed here (its plugin in
   `org.kde.kdecoration3`; an Aurorae SVG theme: its theme folder, as Apply checks the fallback's),
   and the "Follow sunset" watch does not put Plasma Fusion's back over it; one that is not
   installed is named. Apply turns "Dock on every screen" on only with a dock to copy and keeps
   the top bar's opacity choice only with a top bar; on a desktop without them the file's choice
   is written anyway (plasmafusionrc `[Dock] EveryScreen`, `[TopBar] SolidNextToWindows`), as the
   file's panels bring them;
2. the panels: `import-layout.js` gets the file's layout in front of it (`var LAYOUT = ...;`, the
   JSON with U+2028 and U+2029 escaped: Qt 6.11.2's QJSEngine refuses them in a string literal)
   and puts its panels in place of the ones there are, in two steps half a second apart, as a
   layout reset unloads before it loads: the panels there are go (`PHASE = "remove"`), then the
   file's come (`"add"`). A removed widget is deleted only on the shell's next turn, its
   configuration already reset (libplasma 6.7.5 `AppletPrivate::cleanUpAndDelete`), and quick
   settings' widgets share their state: in one step the new ones counted the old ones too (the
   session log showed "3 in this shell" for the first new one; in two steps it is 1). When the
   file's panels cannot be added after the old ones went, the page says that "Reset Fusion
   layout" brings Plasma Fusion's panels back. A panel of a screen this computer does not have
   goes to the first screen when that edge is free there, else it is left out; a widget that is
   not installed is left out; the page names both;
3. as after "Reset Fusion layout" (`finishResetLayout`): each widget the import made gets the key
   the file gives it (`import-layout.js` lists the new widgets' ids with their keys, so two
   widgets of one type keep their own), and a widget the file gives none gets none (no default:
   the file is what the user had). First every key the removed widgets held is released
   (kglobalaccel `unregister` of `plasmashell` / `activate widget ID`): libplasma 6.7.5 releases
   only a removed panel's own key (`AppletPrivate::cleanUpAndDelete`) and deletes its widgets
   without (`~Applet`), so their keys stayed taken; the desktop's widgets, which an import keeps,
   keep theirs. A key a widget of the old layout still holds is released when it is given (the
   new panels' ids are all higher than every id there was: libplasma 6.7.5 counts one id up for
   containments and widgets, `applet_p.cpp` and `corona.cpp`); the glass and
   the top-bar choice are applied, `ensure-topbars.js` runs with "Top bar on every screen" or
   "Dock on every screen" on (the screens the file had no bars for), and the power service applies
   its tier to the new widgets.

The three steps run in one go, waiting as the page waits for the shell (no user input meanwhile)
rather than from timers of the page: leaving the page or closing System Settings deletes the page,
and a timer of it would never fire, leaving no panels between the two steps. Closing System
Settings ends every event loop at once (Qt 6.11.2 `QCoreApplication::exit`), after which a wait
returns at once (`QEventLoop::exec`) and the shell's answer is still read (a pending D-Bus
reply's value waits for it), so the steps run to the end.

The desktop and its widgets are not in the file (only the desktop icon settings, which are this
page's).

Tests:

- `packages/look-and-feel/tests/layout.test.js` (node), the two scripts against the stand-in
  shell: the export (panels, widgets in order, every configuration group, the left-out panels and
  keys, a custom length, the panel view's `floatingApplets`, the user's values while the power
  service holds keys, the copy taken as the dock when the main dock's screen is unplugged); the
  import and a second export giving the same; a panel of a missing screen moved to the first
  screen or left out, a widget not installed skipped; a file of another version or without panels
  changing nothing. Each rule fails its test when taken out.
- `tests/run-settings-file.sh` (ctest `kcmctl-settingsfile`), against the stand-in plasmashell
  with stand-ins for the two scripts: the export writes the applied settings and not a pending
  change, and the layout the script printed; an import into a fresh HOME applies the settings
  (plasmafusionrc, kwinrc, kdeglobals), hands the file's layout (with a U+2028 in a value) to the
  import script in its two steps (removed first, then added), tries the file's key for quick
  settings and the second quick settings' own key, puts the file's decoration (another one than
  Plasma Fusion's) back with its button order, runs `ensure-topbars.js` and says what was left
  out; with the add step failing, the page says how to get panels back; twelve bad files (not
  JSON, another format or version, no panels, a panel at no edge, a value that is not text, a
  custom length without its lengths, `floating` as text, a hiding mode `Panel` does not know, the
  height as text, no `floatingApplets`, no file) change nothing; a decoration that is not
  installed is named; a file without keys gets none tried, Plasma Fusion's Meta+A neither; the
  page left right after an import (kcmctl's `unload`) and System Settings closed during it
  (`quitafter`, `QCoreApplication::exit`) still get the file's panels added; an export larger than
  an import takes is not written; the removed quick settings' Meta+A is released and a desktop
  widget's key kept (the stand-in session answers as kglobalaccel, `mock-session.py
  --kglobalaccel`, and logs each `unregister`); a FIFO and `/dev/zero` are refused at once and a
  9 MiB file as too large (each kcmctl run is bounded by `timeout`, so a page that hangs fails its
  checks); imported on a desktop without panels, the file's
  "Dock on every screen" and top-bar choices are kept and `ensure-topbars.js` runs; values the page does not take are counted and
  left as they were; without `export-layout.js` the action is not offered and an export says why.
  Each of the module's steps fails a check when taken out (the escape too: the stand-in shell
  refuses an unescaped U+2028 as QJSEngine does).
- `tests/fuzz-kcmctl.sh` (ctest `kcmctl-fuzz`): every other round imports a random settings file
  (valid, odd and wrongly typed values, cut short, or none), and the commands can import or export.
- Session test (`tests/scenario-settingsfile.sh`; 2026-10-16, a private session on the Fedora 44
  test laptop with two outputs, Plasma 6.7.5, the module and kcmctl from this change; the real
  plasmashell, kglobalaccel and the layout part's scripts): **22 checks pass** (review round 3).
  Before the import the app name of the reset layout gets Meta+Ctrl+F9, which the file does not
  give: after it, kglobalshortcutsrc has no `activate widget ID` entry for it any more.
  The page and the panels changed (Reduced glass, the keyboard on touch, 56 px icons, a dock on
  every screen, the pen menu removed, KWin's Breeze decoration) and exported: the file holds both
  screens' bars and the main dock, not the copy, Breeze, and Meta+A for quick settings; after the
  settings were changed back, the Plasma Fusion decoration chosen and the layout reset, the
  import brings back the settings (page, plasmafusionrc, the widgets' keys), Breeze, the same
  panels with the copy made again, and Meta+A on the new quick settings, with no error; after a plasmashell restart the panels are still on their screens and Meta+A still
  set. Seen in the shell's log: two `TypeError: Value is null and could not be converted to an
  object` from Plasma's D-Bus QML module during the remove step, only when the page has just
  applied changes to those widgets (the import's Apply, then the removal); the same Apply alone,
  and removing the panels alone (one at a time, both docks, both top bars), log nothing, and every
  check passes. Which widget's reply handler it is is a follow-up.
