# Part: polish across the phase-1 parts

Fixes for the review findings and cross-part needs that phase 1 left open
(`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/phase1-open-items.txt`, 87 items),
checked against the boards at 1:1 in private virtual sessions on the ThinkPad and, read-only, on
its real session at scale 4/3.

Status: done and reviewed (see Review), not yet deployed to the real session (the lead deploys).
Last edited 2026-09-29.
Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/polish/`.

## Changed files

| File | Change |
|---|---|
| `generators/plasma-style/gen_plasma_style.py` | `widgets/menubaritem`: 26 px pill inset in the 34 px bar with the board's 2 px gap; light hover/open pill readable (see 1, 2). New `dialogs/background` prefix `snaplayouts` (radius 16, fill .90, edge .14, margins 12, with mask) |
| `tools/device/fusion-config.sh` | top bar `floatingApplets=1` before the last plasmashell restart (3); Meta+N for the quick-settings pop-up when free (7), after removing a dead entry left by a layout rebuild (review); note on why kxkbrc is not touched (4) |
| `tools/device/fusion-restore.sh` | header text names the two new settings it undoes; `--help` printed the whole script (end pattern fixed); also undoes the shortcut and workspace records of later runs (review) |
| `packages/look-and-feel/common/contents/layouts/org.kde.plasma.desktop-layout.js` | top-bar section only: writes `floatingApplets=1` for the new top bar before its location is set, so a layout applied from System Settings floats its pop-ups too (3) |
| `packages/plasmoids/org.plasmafusion.{appname,clockpill,launcher}/contents/ui/FusionText.qml`, `packages/look-and-feel/common/contents/splash/Splash.qml` | plain CSS weights on the static font files (5) |
| `packages/lockscreen/org.plasmafusion.lockshell/contents/lockscreen/PfStyle.qml` | comment only (the style-name approach is right for static files too) |
| `packages/kwin/switcher/org.plasmafusion.switcher/contents/ui/main.qml` | keys typed before the card's first frame are handled (6) |
| `packages/kwin/tests/offscreen/keytest.py` (new, test only) | regression test for 6 |
| `generators/look-and-feel/tests/session-common.sh`, `generators/plasma-style/tests/vsession-integrated.sh` | comments: the kdedefaults workaround is a no-op with the current `tools/vsession` |

`tools/build.d/*` and `tools/vsession/*` are unchanged (not this part's files).

## The seven must-fix items

### 1. Global menu text contrast (light: 1.3:1 before)

The stock appmenu (`MenuDelegate.qml`) and window-list (`MenuButton.qml`) draw a hovered or
open title in `Kirigami.Theme.highlightedTextColor`, the colour scheme's Selection foreground,
which is white in both Fusion schemes and, with a custom accent, whatever KDE's accent code
picks as readable on that accent. A Plasma style cannot change that text colour without a
`colors` file, which would freeze every shell colour and stop accent colours from following.

- Dark: unchanged board look, white on a white .10 pill (open menu .14).
- Light: the pill is the accent (Selection background, `ColorScheme-Highlight`) darkened with
  the light boards' ink, .10 for hover and .18 for an open menu: white on it is 5.4:1 and 6.0:1
  nominal. The board's grey pill with dark text is not reachable (deviation below).
- Measured on screenshots (text = the lightest pixel of 13 px antialiased text, so this is the
  worst case): light 4.91:1 hover, 5.45:1 open; dark 12.9:1 hover, 11.6:1 open
  (`measurements.txt`, `globalmenu-{dark,light}-board-hover-open.png`).

### 2. Global menu pill 26 px, inset 4 px

The appmenu is `CanFillArea` and its titles fill the panel height with no spacing, so the frame
now carries the geometry: `hover`/`pressed`/`normal` have 4 px of transparent space above and
below the pill and 1 px at each side (`svgkit.Frame.insets`); the margins (4, 4, 9, 9) keep the
board's 8 px text padding inside the pill. Measured: pill rows 4..29 (board 4..29), 2 px between
neighbouring pills, fill (35,39,58) against the board's (35,41,57).

### 3. Top-bar pop-ups float (plasmashellrc `floatingApplets=1`)

- `fusion-config.sh`: after the Global Theme step, for every full-width top panel it sets
  `plasmashellrc [PlasmaViews][Panel <id>] floatingApplets=1` (kwriteconfig6, backed up with
  plasmashellrc) and makes sure one plasmashell restart follows: the restart it does anyway
  (install or rebuilt layout), or one of its own when only this key changed. A second run
  reports it unchanged and does not restart. Without a running plasmashell it prints a note to
  run the script again once the shell runs.
- Layout script: plasmashell reads the key when the panel view gets its location, so the
  script writes it through `ConfigFile("plasmashellrc", ...)` (the shell's own shared config
  object) between `new Panel` and `topBar.location = "top"`. A Global Theme applied from System
  Settings then floats the pop-ups at once, without a restart (verified with
  `plasma-apply-lookandfeel --resetLayout` in a running session, `tray-popup-floating-dark-live-layout.png`).
- `fusion-restore.sh` needs no change: it puts the backed-up plasmashellrc back as a whole
  (verified: after the restore the key is gone, `logs/apply-reapply-restore-state.txt`).
- Result: tray and stock applet pop-ups 8 px under the bar with all corners rounded, dark and
  light (`tray-popup-floating-{dark,light}.png`).

### 4. Keyboard layout badge

Decision: the quick-settings badge (and the lock screen's) shows the current layout's
`kxkbrc [Layout] DisplayNames` entry when the user set one, else the layout's short name in
capitals, and it is shown with a single layout too (`keyboardLayoutAlways`, default true). On the
ThinkPad (XKB_DEFAULT_LAYOUT=us) that is "US"; the board's "EN" is sample content. The widget
already did this (`services/Keyboard.qml`), so no code changed. `fusion-config.sh` writes nothing
to kxkbrc: `Use`/`LayoutList` would replace the layouts KWin takes from the system, and a
`DisplayNames` entry is a per-layout user label. A user who wants "EN" sets the display name in
System Settings > Keyboard > Layouts. When KWin reports no layout at all (no LayoutList and no
XKB_DEFAULT_LAYOUT, as in the virtual sessions) the badge stays hidden.

### 5. Heavy or light bold text

With the static per-weight font files (commit 0918220) Qt no longer synthesises bold: it only
emboldens a file whose OS/2 weight is below 700, and each static file carries its real weight.
But four places still used the variable-font workaround (`font.weight: Normal` plus
`font.variableAxes: {"wght": N}`), which a static file ignores: they drew **regular** text where
the board has 600-800. Seen on the real session too (app name, date, time;
`real-session-4x3-topbar-before-deploy.png`). Fixed by using the CSS weight as the font weight:

- `org.plasmafusion.appname` (name 13 px 800), `org.plasmafusion.clockpill` (date 13 px 700, time
  Space Grotesk 13 px 600, calendar pop-up), `org.plasmafusion.launcher` (every label), the splash
  (title Space Grotesk 600, status 700).

Measured ink against Pillow renders of the same static files (1.0 = same ink): board "Settings"
1.005, build app name 0.965 (0.557 before); board date 1.044, build 0.956; quick-settings tile
title 1.023 board, 0.935 build. Window title (kdeglobals `[WM] activeFont` Manrope 10.5 pt = 14 px,
weight 800 → the static ExtraBold file): 0.982, the same as Qt's own offscreen ExtraBold render
(0.98), board 0.946; its width matches ExtraBold (127 px for "Welcome — KWrite"), so no synthetic
bold, and the font string stays as it is. The `Font.Bold`/`Font.ExtraBold` uses in quick settings,
dock, switcher and snap script, and the lock screen's `DemiBold` + style name, resolve to the right
static files (checked in the screenshots). `QT_NO_SYNTHESIZED_BOLD` is not needed and not installed.

One trap found on the way: a KWin that started before the fonts were installed (a virtual
session, or the first `fusion-config.sh --install` on a live session) draws window titles with
synthetic bold until it restarts (fontconfig had no ExtraBold file yet). A log-out/log-in, which
the script already asks for, clears it.

### 6. Switcher: first-frame key loss

KWin sends the switcher's key presses to the first QQuickWindow below the switcher object. For
up to one frame after the switcher opens that is the dim layer (the card is created after the
dim layer has drawn, so it is stacked above it); the dim window never becomes active, so Qt Quick
had no focus item and dropped the key. The keys are now handled by one function (`handleKey`)
used by the card and by a focus item in the dim layer, which takes active focus itself.
`packages/kwin/tests/offscreen/keytest.py` sends Key_A the way KWin does, before any frame: this
revision toggles "All workspaces", commit 0918220 loses the key (`measurements.txt`). Keys pressed
during KWin's own 90 ms show delay (`[TabBox] DelayTime`) still go nowhere, as with every switcher.

### 7. Keyboard access

- Quick settings had no key: `fusion-config.sh` gives the widget Meta+N when the widget has no
  shortcut and kglobalaccel reports the key free (`globalShortcutAvailable`); it records it so
  `fusion-restore.sh` removes it. Meta+Alt+S is Plasma's screen-reader toggle and Meta+A walks
  activities on the ThinkPad, so the notification key of other desktops is used (the pop-up holds
  the notifications). Verified: Meta+N opens and Esc closes the pop-up
  (`quicksettings-meta-n-{dark,light}.png`), a re-run keeps it, restore sets it to none.
- Switcher keys in the first frame: 6.
- Meta-opened launcher not lighting the logo (item 81): no longer reproducible. With real input
  the logo shows the pressed state after Meta, loses it when the logo closes the launcher, gets it
  back when the logo opens it and loses it on Esc (pixel values in `measurements.txt`).
- Panel keyboard navigation shows the shell's accent underline and the widgets' focus ring
  together (items 82, 86): kept. The underline (`widgets/tabbar` `north-active-tab`) is also the
  expanded-applet indicator and the only focus indicator of the stock tray icons, so the style
  cannot drop it, and the Fusion widgets' ring is the Controls board's focus style.

## Triage of the 87 items

Numbers are the order of the `[part|severity]` lines in `phase1-open-items.txt`.

| # | Item | Verdict |
|---|---|---|
| 1, 4 | Kontact and KMail pinned as two Mail tiles | Already fixed (0918220: a slot is pinned once; launcher shows one Mail tile) |
| 2, 5, 6 | KWin icon lookups fall back to Breeze in vsessions; check on the device | Fixed by the lead's vsession change (kdedefaults); verified: KWrite title icon and Alt+Tab show the Fusion tiles (po-2, po-3) |
| 3 | kscreen, mouse, keyboard, phone battery icons stay Breeze | Accepted (icons part's deliberate choice; changing them would change KCM icons) |
| 7, 24, 51, 63, 87 | Shared-ledger checkpoints | Lead (process) |
| 8, 33 | Tray media controller and expander arrow | Media controller already hidden (TRAY_ITEMS_REPLACED); the arrow is being handled by the desktop-cards part, which owns the tray section now |
| 9, 14, 19, 20 | Global Theme not applied in vsessions (kdedefaults) | Fixed by the lead (vsession.sh); verified: style, icons, cursor, decoration applied in every po- run |
| 10, 13, 85 | Top bar 48 px | Already fixed by the Plasma style (6 px unprefixed tiles); thickness=34 in every run |
| 11 | Notifications inside the quick-settings card | Accepted deviation (one blurred window per card is not possible in 6.7.5) |
| 12 | Hide media controller, keyboard layout, KDE Connect, clipboard in the tray | Already fixed (layout script) |
| 15 | pfinput.py into tools/vsession | Done by the lead; this part's tests use a copy with all letters and press/release (evidence `test-tooling/pfin.py`), see Needs |
| 16, 38 | kxkbrc DisplayNames=en for "EN" | Decided not to set (must-fix 4) |
| 17 | Fonts through named instances | Superseded by the static files |
| 18 | One launcher right-click without a menu | Not reproducible: 3 of 3 right-clicks opened the menu with real input (po-6) |
| 21, 46 | Keep the `launcher` prefix | Kept (unchanged) |
| 22 | Launcher API for the dock | Nothing to do |
| 23, 54, 56, 60 | Synthetic bold on the variable fonts | Fixed by the static files (lead) plus must-fix 5 here |
| 25 | Kirigami "not placed in the graphics scene" on the dock settings | Upstream PageRow behaviour, not the dock |
| 26 | Subpixel antialiasing makes pill text look heavier | System font setting (fontconfig), same for all Plasma text; left as is |
| 27 | Dock real-pointer interaction unchecked | Checked with real input (po-6): magnification and name pill, right-click menu (Open, Keep in Dock), drag to reorder (moves while dragging, order kept after release). Drops onto the dock were not exercised (`dock-pointer-hover-menu-drag.png`) |
| 28 | QT_FORCE_STDERR_LOGGING in vsessions | Fixed by the lead |
| 29 | Ark uses the Breeze icon | Accepted: the boards have no Ark/archive app tile (only the Archive file type) |
| 30, 52, 58, 59, 77 | Confirmations that something is in place | Still true at this revision |
| 31, 32, 34 | Desktop cards too large; system-monitor race | Desktop-cards part (new widgets under way) |
| 35 | KWin keys in fusion-config.sh | In place (TabBox, Outline, sheet, scripts) |
| 36 | Keep the small unprefixed panel tiles | Kept |
| 37 | lockscreen-enable.sh `--check` format | Kept, fusion-config.sh still parses it |
| 39 | remote.sh `--delete` overwrites results when a NAME is reused | Lead's tool; this part used a new NAME per run |
| 40, 43 | floatingApplets for the top bar | Fixed here (must-fix 3) |
| 41 | Bottom panels at least 64 px | Accepted (dock contract) |
| 42 | Unchecked PC3 checkbox is round | Accepted: CheckIndicator draws the button frame at 16 px; a square box would change every button |
| 44, 71 | Colour scheme values others rely on | Verified unchanged (Tooltip 12,15,28 / 27,32,49, Selection 47,111,223, DecorationFocus 138,184,255 / 47,111,223, Header 34,40,64 / 236,239,246) |
| 45 | Dock keeps CanFillArea | Unchanged |
| 47 | Switcher first-frame keys | Fixed here (must-fix 6) |
| 48 | Text widths 4-5 % off the board render | Rasteriser difference (FreeType vs the browser); positions match |
| 49 | `snaplayouts` prefix for the Meta+Z flyout | Added: radius 16, fill .90, edge .14, margins 12; the flyout picks it up by itself and now matches the board (`snap-flyout-{dark,light}-board-vs-build.png`) |
| 50, 72 | Decoration features (hold-on-maximize, sheet variant, tiled corners) | decoration-cpp part (phase 3) |
| 53 | Lock-screen badge hidden without layout information | Accepted, graceful (same rule as the quick-settings badge) |
| 55 | Authentication contract | Verified by the lock-screen review, unchanged here |
| 57 | Window-title font 800 synthetic | Not real any more: 800 picks the static ExtraBold file, measured equal to Qt's ExtraBold (must-fix 5); string unchanged |
| 61 | Install QT_NO_SYNTHESIZED_BOLD | Not needed with the static files, not installed (it would also stop Qt from emboldening fallback fonts that have no bold, such as some CJK fonts) |
| 62 | Space Grotesk DemiBold picks Bold | Fixed by the static SemiBold file (lead) |
| 64 | Ready-made splash background | Nothing to do (the splash has its own pre-blurred background) |
| 65, 66, 67, 68 | Aurorae stale shadow, clipped long titles, rounded tiled corners, dimmer board edge | Upstream Aurorae limits / kept spec value; for the decoration-cpp part |
| 69 | kdedefaults merge in look-and-feel / plasma-style test helpers | No longer needed with the current vsession.sh; comments updated, merge left as a no-op for older copies |
| 70 | BorderSizeAuto/BorderSize kept; "Left · circles" write path | In place; the write path belongs to the kcm-cpp part |
| 73, 76 | Cursor not applied in vsessions | Fixed by the lead's vsession change (cursorTheme PlasmaFusion-cursors read through kdedefaults) |
| 74, 75 | Move cursor on drag, heavier shadow at 48/64 px | Accepted cursor deviations |
| 78 | Greeter cursor (phase 2) | System part |
| 79, 83 | Light global menu contrast | Fixed here (must-fix 1) |
| 80, 84 | Global menu pill 34 px | Fixed here (must-fix 2) |
| 81 | Meta-opened launcher does not light the logo | Not reproducible (must-fix 7) |
| 82, 86 | Two focus indicators during panel navigation | Kept (must-fix 7) |

## Verification

- Offline: `qmllint` on every changed QML file (clean; the switcher with the offscreen stubs);
  `node --check` on the layout script; `bash -n` and shellcheck on the device scripts;
  `generators/plasma-style/tests/validate.py` on both styles (0 errors); the style generator gives
  identical output on two runs; `packages/kwin/tests/offscreen/keytest.py` (this revision handles
  the early key, commit 0918220 loses it); the splash rendered offscreen with the static fonts
  (title now 600 instead of regular).
- Virtual sessions on the ThinkPad, 1440x900, everything built into `build/po/home` and applied
  with `tools/device/fusion-config.sh --install`, then a login-style plasmashell restart, real
  pointer and keyboard input through KWin's EIS:
  po-1 baseline at commit 0918220 (regular weights, 34 px pill); po-2 / po-4 fixes dark / light;
  po-3 switcher keys; po-5 window-title weights; po-6 dock pointer, launcher right-click, Meta+Z;
  po-7 first install, simulated older deployment, second and third run, `fusion-restore.sh`;
  po-8 / po-9 final evidence dark / light (plus the layout rebuilt live in dark).
- Read-only screenshots of the real session at 4/3 (before deploy): regular-weight app name,
  date and time confirmed there; nothing else from this part's list visible.
- Core dumps since the start of this work (17:11 on the ThinkPad): none from these tests. The
  list shows `kdialog` as the `plasmalogin` user (uid 981) and one `plasma-login-greeter` /
  `plasma-login-wallpaper` crash (17:37) from the login-greeter work of another part.

## Deploying and undoing

The lead's usual deploy covers everything: build, then `tools/device/fusion-config.sh --install
<stage>` in the session. On the real session this adds, on top of the files:
`plasmashellrc [PlasmaViews][Panel <top bar id>] floatingApplets=1` with one plasmashell restart,
and Meta+N for the quick-settings widget if the key is free. Log out and in afterwards so KWin
picks up the static fonts for window titles if it started before them.

Undo: `tools/device/fusion-restore.sh` (plasmashellrc back from the backup, Meta+N set to none).
By hand: `kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel <id>" --key
floatingApplets --delete` and restart plasmashell; remove the widget's shortcut in its settings
(Keyboard Shortcuts page) or in System Settings > Shortcuts > plasmashell.

## Deviations added

- Light global menu: hovered / open title is white on the (darkened) accent instead of the
  board's dark text on a grey pill (text colour is fixed by the stock applet; see 1).
- Quick settings: Meta+N is not on the boards.
- Keyboard badge reads the real layout name ("US"), not the board's sample "EN".

## Needs from other parts

- Lead: deploy (fusion-config.sh restarts plasmashell once for the new key); ledger checkpoint.
- Lead / tools/vsession: `pfinput.py` could take the additions of this part's copy (all letters
  and digits, `press KEY` / `release KEY` to hold Alt, extra keys); the copy is in the evidence
  folder under `test-tooling/`.
- Desktop-cards part: the tray expander arrow (items 8, 33); the layout script's top-bar section
  now also writes `floatingApplets` (keep the comment and two lines right after
  `var topBar = new Panel;` when editing the file).
- System part: the core dumps of `kdialog` (uid 981) and `plasma-login-greeter` seen at 17:36-17:46.
- decoration-cpp part: items 50, 65-68, 72.

## Review (2026-09-29)

Adversarial review of this part at the current working tree: static reading of every changed
file against the 6.7.5 sources (appmenu `MenuDelegate.qml`, `PanelView::restore`, the scripting
`ConfigFile`, KWin's `TabBoxHandler::grabbedKeyEvent`, libplasma's applet shortcut clean-up),
the full build (`STAGE=build/rpo/home PF_WALLPAPER_SIZES=quick tools/build.sh`, rc 0), offline
checks, and five integrated virtual sessions on the ThinkPad (rpo-1..rpo-5, 1440x900, the whole
stage applied with `fusion-config.sh --install`, real input through KWin EIS). Evidence:
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/polish/review-*` (images,
`review-logs/`, `review-tooling/`).

### Findings fixed in this review

1. **`fusion-restore.sh` did not undo Meta+N on the ThinkPad's path** (medium). Each run records
   only the shortcuts it changes itself, and the default restore picks the newest backup taken
   before Plasma Fusion. On the ThinkPad that backup comes from the 0918220 deployment, which never
   set Meta+N; the key is set by the next run and recorded in its own, later backup. The restore
   put the files back but left `activate widget <id>` = Meta+N in kglobalaccel (a dead entry that
   keeps the key taken). Reproduced in rpo-1 with the real 0918220 `fusion-config.sh` followed by
   this revision's. Fix: the restore also replays the shortcut records (and created-workspace
   lists) of every later backup, newest first, before the chosen one's. Verified in rpo-2, rpo-3
   and rpo-5: after the default restore Meta+N is free and the entry is `none`.
2. **Meta+N lost after a layout rebuild** (medium). plasmashell rebuilds a layout by unloading the
   old containments without the per-widget clean-up (`ShellCorona::loadLookAndFeelDefaultLayout`
   calls `unload()`, not `destroy()`), so the old widget's `activate widget <old id>` keeps Meta+N.
   `fusion-config.sh --reset-layout` (and any run after a Global Theme applied with its layout in
   System Settings) then reported the key "in use" and the new widget stayed without a shortcut,
   while the dead entry kept the key (rpo-3). Fix: `release_dead_widget_key` asks kglobalaccel
   which actions hold the key (`globalShortcutsByKey`) and unregisters a plasmashell
   `activate widget N` whose widget is not in `plasma-org.kde.plasma.desktop-appletsrc` any more
   (widgets of other activities stay, as they are in the file); a dry run reports it. Verified in
   rpo-5: `--reset-layout` moves Meta+N from widget 47 to the new widget 77, a live
   `plasma-apply-lookandfeel --resetLayout` followed by a plain run moves it to widget 107, Meta+N
   opens the pop-up each time, and the restore frees the key.
3. The "key in use" note now says "in use or could not be checked" (the check also fails when
   kglobalaccel cannot answer). Header comments of both scripts and the doc lines that said the
   restore was unchanged were corrected (`lookandfeel.md`, `shell-quicksettings.md` Polish
   sections).

### Verified as reported

- Must-fix 1 and 2: pill rows 4..29 (26 px) with 2 px gaps in dark and light; contrast of the
  hovered / open title measured again: dark 12.9:1 / 11.6:1, light 4.91:1 / 5.45:1
  (`review-globalmenu-{dark,light}-hover-open.png`, `review-logs/measurements-review.txt`).
- Must-fix 3: with the key deleted (older layout), stock tray pop-ups are attached with square
  corners; this revision's `fusion-config.sh --install` sets the key, restarts once and the pop-up
  floats with every corner rounded (`review-tray-popup-before-after-floatingapplets.png`). A re-run
  reports it unchanged; the layout script writes it during a live rebuild (rpo-5 state C); the
  restore removes it.
- Must-fix 4: the badge code does what the doc says (display name, else short name, capitals);
  nothing writes kxkbrc.
- Must-fix 5: app name, date, time, launcher labels and splash title match the boards' weights
  (`review-topbar-board-vs-build.png`, `review-launcher-board-vs-build.png`,
  `review-splash-board-vs-build.png`); no `variableAxes` use is left in the Fusion QML; the
  window-title string (Manrope 10.5 pt, 800) matches the boards' 14 px / 800.
- Must-fix 6: the offscreen key test passes; the switcher works with real Alt+Tab input
  (`review-switcher-dark.png`). KWin's own focus hand-off (`handleFocusWindowChanged` on the
  first window at show time) is consistent with the fix.
- Offline: `qmllint` clean on the changed QML (switcher with the offscreen stubs), `node --check`
  on the layout script, `bash -n` and shellcheck (warning level) on both device scripts,
  `validate.py` 0 errors on both styles, generator output identical on two runs and equal to the
  stage.
- Core dumps on the ThinkPad during the review (18:07-18:33): none from these sessions. The list
  shows kwin_wayland/spectacle from the `perf-pilot-*` sessions and `kscreen-doctor --help`,
  `kstart --help`, `spectacle --help` run over SSH by other agents.

### Left as they are (not this part, or accepted)

- The tray expander arrow is still visible at the current revision (Vaults, Disks & Devices and
  Display Configuration are passive items in the tray's pop-up): desktop-cards part.
- Date and time in the clock pill sit 1 px lower / higher than on the board (the two fonts'
  line boxes, centred separately); within the 1 px tolerance of the phase-1 reviews.
- The light global-menu pill (accent instead of the board's grey) and the rest colour stay the
  documented deviations.
- Konsole's "Could not find ''" line in the virtual sessions comes from the test sessions having
  no `SHELL` variable; a real login sets it (the profile has no `Command=`, as intended).
