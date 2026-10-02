# Login check (update safety) and switching back

Status: built and tested on the ThinkPad in private sessions (gt-a, gt-ld) and against throw-away
HOME trees, then reviewed and fixed (see Review); not installed in the real session (the lead
deploys). Last edited 2026-09-30.

Covers ADAPTIVE.md fixes 9 and 10, GAPS.md G14 and G15, test matrix M27
(`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-adaptive/`).

## What it is

| Piece | What it does |
|---|---|
| Login check (`tools/device/gate/plasma-fusion-gate.sh`) | Runs at every login before KWin starts. After a Plasma, KWin, kscreenlocker, libplasma, KDecoration or Qt update, or when the lock-screen files changed, it uses Plasma's own lock screen and the Aurorae title bars until the new versions are checked, and queues one notification. While another Global Theme is chosen, it switches the Fusion-only parts off. |
| "My previous desktop" (`org.plasmafusion.previous.desktop`) | A normal Global Theme with the look the computer had before Plasma Fusion, saved before the first `fusion-config.sh` apply. |
| `fusion-config.sh` | Installs the check, records the installed versions as tested, turns back on what the check switched off, saves "My previous desktop". |
| `fusion-restore.sh` | The full undo, now also of the check. |

## Files

| Path (repository) | Installed as | What |
|---|---|---|
| `tools/device/gate/plasma-fusion-gate.sh` | `~/.local/share/plasma-fusion/gate/plasma-fusion-gate.sh` | the check: `login`, `check`, `deploy [--dry-run]`, `notify`, `status` |
| (written by `fusion-config.sh`, section 8) | `~/.config/plasma-workspace/env/plasma-fusion-gate.sh` | env stub startplasma sources at login |
| (same) | `~/.config/systemd/user/plasma-fusion-gate-notify.service` + `xdg-desktop-autostart.target.wants/` link | shows the queued notification once the desktop is up |
| `tools/device/previous-theme.py` | `~/.local/share/plasma/look-and-feel/org.plasmafusion.previous.desktop/` | "My previous desktop" generator |
| `tools/device/tests/gate-unit.sh`, `gate-stub.sh`, `vsession/*` | not installed | tests (see Verification) |

State, all under `~/.local/state/plasma-fusion/`: `gate.log` (one line per run plus details),
`gate/tested` (the record `fusion-config.sh` writes: package versions, lock-screen hash and the
path of the `fusion-config.sh` that wrote it), `gate/cache` (installed versions keyed by the
package database's stamp: the rpm database's inode, size and time on Fedora), `gate/off` (what
the check switched off), `gate/saved/` (the
lock-screen drop-in while it is aside), `gate/notify` (queued notification), `gate/notified`
(the change already reported), `gate/status` (for other parts, see below).

## When a login runs it (plasma-workspace 6.7.5, verified in the source)

`startplasma-wayland.cpp` main: `runEnvironmentScripts()` first, then `setupPlasmaEnvironment()`
(adds `~/.config/kdedefaults` to `XDG_CONFIG_DIRS`), `runStartupConfig()`, `syncDBusEnvironment()`,
`importSystemdEnvrionment()`, then `startPlasmaSession()`, which calls systemd `Manager.Reload`
(`reloadSystemd()`) and only then `StartUnit plasma-workspace-wayland.target` (KWin's
`plasma-kwin_wayland.service`; `plasma-core.target` with plasmashell comes after KWin).

`runEnvironmentScripts()` (`startplasma.cpp`) collects `plasma-workspace/env/*.sh` from every config
directory, system ones first and `~/.config` last, each in name order, and runs ONE process:
`/bin/sh /usr/libexec/plasma-sourceenv.sh FILE...`, which does `. $i >/dev/null` for each file and
then `env -0`; startplasma imports that environment (minus `_`, `SHELL`, `SHLVL*`). It waits with
`waitForFinished(-1)` and never looks at the exit status. So:

- a slow or hanging script holds the whole login (black screen, no time limit);
- `exit`, or an error under a `set -e` an earlier script left on, ends the shell before `env -0`,
  and every variable all env scripts set is lost (SSH agent, Fedora's `XDG_*`), without an error;
- output to stdout is discarded, stderr is captured and dropped;
- variables a script sets stay in the environment of the whole session.

The stub therefore only runs the check as its own process and never exits:

```sh
[ -r '/home/USER/.local/share/plasma-fusion/gate/plasma-fusion-gate.sh' ] &&
  timeout -k 1 4 /bin/bash '/home/USER/.local/share/plasma-fusion/gate/plasma-fusion-gate.sh' login </dev/null >/dev/null 2>&1 || :
```

Worst case (a hung check) the login waits 5 s. The check itself runs no GUI or Qt program, makes
no D-Bus or systemd call at login, reads the configuration with one `awk` run, edits files in place
(one `awk` run per file, written next to the file and renamed over it, permissions kept) and always
exits 0. A drop-in it moves aside counts for this login because startplasma reloads systemd before
it starts KWin; `kwinrc` is read by KWin when it starts.

## What the check decides

| Part | "On" when | Needs |
|---|---|---|
| lock screen | `~/.config/systemd/user/plasma-kwin_wayland.service.d/plasma-fusion-lockscreen.conf` exists | Fusion theme, tested versions, tested lock-screen files |
| decoration | effective `kwinrc [org.kde.kdecoration2] library=org.plasmafusion.decoration` (user file or kdedefaults) | tested versions |
| navigation (TABLET2 N1) | effective `kwinrc [Plugins] plasmafusion_navigationEnabled=true` (the compiled tablet navigation effect, built against KWin's internal classes) | Fusion theme, tested versions |
| desktop (TABLET2 H1) | a top-level `[Containments][N]` group of the user's `plasma-org.kde.plasma.desktop-appletsrc` has `plugin=org.plasmafusion.desktop` (the Folder View fork, `docs/parts/desktop.md`) | Fusion theme, tested versions, the package installed |
| snap, attach | `kwinrc [Plugins] plasmafusion-snapEnabled` / `plasmafusion-attachEnabled` = true | Fusion theme |
| outline | `kwinrc [Outline] QmlPath` contains `plasmafusion` | Fusion theme |
| switcher | effective `kwinrc [TabBox]` or `[TabBoxAlternative] LayoutName=org.plasmafusion.switcher` | Fusion theme |
| tablet (DEVICE-1) | effective `kwinrc [Plugins] plasmafusion-tabletEnabled=true` | Fusion theme |
| inputmethod (DEVICE-1) | user `kwinrc [Wayland] InputMethod` empty or plasma-keyboard (the Fusion keyboard policy's values) | Fusion theme |
| powerfx, pengarage (DEVICE-1) | `~/.config/systemd/user/graphical-session.target.wants/plasma-fusion-{powerfx,pen-garage}.service` exists | Fusion theme |

"Fusion theme": `kdeglobals [KDE] LookAndFeelPackage` is `org.plasmafusion.dark.desktop` or
`org.plasmafusion.light.desktop` ("My previous desktop" is not), or automatic light/dark switching
(`AutomaticLookAndFeel=true`) names one of them as `DefaultLightLookAndFeel` or
`DefaultDarkLookAndFeel`: startplasma picks the light or dark theme only after the env scripts ran
(`setupPlasmaEnvironment` → `determineLookAndFeel`), so `LookAndFeelPackage` can still name the
other one when the check runs. "Tested versions": the upstream
version (`%{VERSION}`, not the release: a distribution rebuild keeps the interfaces) of
`plasma-workspace plasma-desktop kwin kscreenlocker libplasma kdecoration qt6-qtbase qt6-qtdeclarative` equals the
record (on other distributions the same packages under their names there, see "Other
distributions" below); a missing or unreadable record, or no package database reporting the
versions (rpm failing or taking over 3 s on Fedora), counts as untested.
"Tested lock-screen files": sha256 over the files and relative names of the installed
`org.plasmafusion.lockshell` (user copy first, as kscreenlocker finds it) equals the record, and the
package exists. Versions and the lock-screen hash are only looked at while the lock screen or the
decoration is on (or held off by the check); `rpm -q` only runs after the rpm database changed.

Switching off (recorded first in `gate/off`, then written):

| Part | Change |
|---|---|
| lock screen | drop-in moved to `gate/saved/` (as `lockscreen-disable.sh` removes it), empty directory removed |
| decoration | when `~/.config/kdedefaults` (the Global Theme) names `org.kde.kwin.aurorae.v2` with `__aurorae__svg__PlasmaFusion{Dark,Light}`: the user's `library` and `theme` keys are removed, so the title bars follow a light/dark switch startplasma makes after the check (with Follow sunset it writes only kdedefaults). Otherwise user `kwinrc` `library=org.kde.kwin.aurorae.v2`, `theme=__aurorae__svg__PlasmaFusion{Dark,Light}` (variant from the Global Theme, else the colour scheme's name or window colour); with `plasmafusionrc [Decoration] ButtonStyle=LeftCircles` the `-Left` theme and `ButtonsOnLeft=XIA`, `ButtonsOnRight=_` as the settings module does; Breeze if the Aurorae themes are missing |
| snap, attach | the `[Plugins]` key removed (the scripts are `EnabledByDefault: false`) |
| outline | `[Outline] QmlPath` removed (KWin's own outline) |
| switcher | `LayoutName` removed, or set to KWin's default `thumbnail_grid` where kdedefaults still names the Fusion switcher (a Global Theme without a switcher of its own, such as Breeze, leaves it there); `DesktopMode=0` and `HighlightWindows=false` (fusion-config.sh's values for the Fusion switcher) removed |
| tablet | `plasmafusion-tabletEnabled=false` written (not removed: the script's EnabledByDefault is not the check's to know) |
| navigation | `plasmafusion_navigationEnabled=false` written; the notification says the session uses "KWin's own edges instead of the tablet gestures". The plugin also checks at start that the running KWin is the one it was built for (`KWIN_VERSION_STRING` against the application version) and otherwise stays idle, for the case where a later fusion-config.sh run turned it back on before the package was rebuilt |
| desktop | each such containment's `plugin` becomes `org.kde.plasma.folder` (stock Folder View reads the same keys: icons, cards, wallpaper stay); the notification says "Folder View instead of the tablet home screen". A missing package does the same without a notification, and the record stays while it is missing |
| inputmethod | the user key removed, so Fedora's default keyboard (`/usr/share/kde-settings/kde-profile/default/xdg/kwinrc`) returns; another input method the user chose is never touched |
| powerfx, pengarage | the wants link moved to `gate/saved/` (record kind `link`, checked against the one allowed path); the service does not start at this login because startplasma reloads the systemd user manager after the check. It comes back only while the unit file is still installed |

Added by DEVICE-1 (2026-09-30); see `device.md`. Tests: `tests/gate-unit.sh` cases `t`, `t3`, `t4`, `t5`.

Turning back on happens when a part's needs hold again at a login, or when `fusion-config.sh` runs
(`deploy`). A key is put back only while it still holds what the check wrote; anything changed
since is left alone. The decoration is the exception: every Global Theme apply (also the automatic
light/dark switch and the quick-settings Dark tile) removes the user's decoration keys, so the
compiled decoration comes back whenever the title bars are still a Plasma Fusion Aurorae theme (and
the plugin is installed), written to the user file unless kdedefaults already names it. The
drop-in comes back only when it is not there already and the lock-screen package is installed.

A missing plugin (added 2026-09-30 with LAYOUT-1, whose Global Themes name the compiled decoration
in their defaults): while `org.plasmafusion.decoration` is named, by the user or by kdedefaults, and
its plugin is not installed, KWin would fall back to its built-in default, so the check chooses the
matching Plasma Fusion Aurorae theme at login (as for an update, the `-Left` pair with left circles),
records it with the reason `missing` and queues no notification. The record stays while the plugin
is missing; at the first login after it is installed again the compiled decoration comes back (the
user's keys are removed when kdedefaults names it). Unit test `p` in `tests/gate-unit.sh`.

A part switched off because of the Global Theme is switched off once: if the user turns it on
again under that theme (for example snap layouts under Breeze), it stays on. Parts held off because
of an update are enforced at every login.

Notification: when the check holds the lock screen or the decoration off because of an update,
it writes `gate/notify` (summary "Safe mode after a Plasma change", body with the changed versions
and what the session uses, and the `fusion-config.sh` that recorded the versions as the way back,
or `tools/device/fusion-config.sh` when that file is gone). At login it only
writes the file; `plasma-fusion-gate-notify.service` (`Type=exec`, `After=graphical-session.target
plasma-workspace.target`, wanted by `xdg-desktop-autostart.target`, `ConditionPathExists` on that
file: the same ordering systemd gives XDG autostart units) runs `plasma-fusion-gate.sh notify`,
which waits for `org.freedesktop.Notifications` (plasmashell), sends it with `notify-send` (gdbus
as fallback) and removes the file. The same change is reported once (`gate/notified`); a switch
back to the tested versions clears both.

`gate/status` (written only when it changes) tells other parts what is held off:

```
format=1
lookandfeel=org.plasmafusion.dark.desktop
versions=changed        # or tested
held=lockscreen decoration
```

## fusion-config.sh and fusion-restore.sh

`fusion-config.sh` (dry run prints all of it):

- section 0, "Previous look": when `org.plasmafusion.previous.desktop` does not exist yet, runs
  `previous-theme.py` on the newest backup taken while the Global Theme was not a Plasma Fusion one
  (on a first run: the backup it just took);
- section 8, "Login check": copies the check to `~/.local/share/plasma-fusion/gate/`, writes the
  stub and the unit (absolute paths), links the unit into `xdg-desktop-autostart.target.wants`,
  `systemctl --user daemon-reload` when the unit changed, then `plasma-fusion-gate.sh deploy`:
  records the installed versions and lock-screen hash as tested, turns back on what a login switched
  off, clears a queued notification, and KWin reconfigures;
- the stub, the unit and the link are in the backup list, so a restore of a later backup puts them
  back as they were. A second run reports them unchanged (0 changes from this section).

`fusion-restore.sh`: when the restored backup does not have the stub (every backup from before the
check existed, and the pre-Fusion one), it removes the stub, the unit and its link, the check
itself and `gate/` (records, cache, saved drop-in), keeps `gate.log`, and reloads systemd.
"My previous desktop" stays installed.

## My previous desktop

`previous-theme.py --backup BACKUP` (or `--config-dir DIR --lookandfeel ID`) writes a
`Plasma/LookAndFeel` package, Name "My previous desktop", with the values that were in effect:
the user's file, else the backup's `kdedefaults` (what the previous Global Theme wrote), else the
previous Global Theme's own defaults, else the system config directories (on Fedora
`/usr/share/kde-settings/kde-profile/default/xdg`, which is in the session's `XDG_CONFIG_DIRS`),
else Plasma 6.7.5's built-in default. A `kdedefaults` directory is never used as a system
directory: a Plasma session's `XDG_CONFIG_DIRS` starts with the live `~/.config/kdedefaults`
(Plasma Fusion's values once it was applied), and `fusion-config.sh` takes that variable from
plasmashell.

| Package file | Keys |
|---|---|
| `contents/defaults` | kdeglobals `[KDE] widgetStyle`, `[General] ColorScheme`, `[Icons] Theme`, `[General] font fixed smallestReadableFont toolBarFont menuFont`, `[WM] activeFont`; plasmarc `[Theme] name`; kcminputrc `[Mouse] cursorTheme`; kwinrc `[org.kde.kdecoration2] library theme NoPlugin BorderSize`, `[WindowSwitcher] LayoutName` (from `[TabBox] LayoutName`); ksplashrc `[KSplash] Theme`; `[Wallpaper] Image` when the previous theme names one |
| `contents/layouts/defaults` | kwinrc `ButtonsOnLeft`, `ButtonsOnRight`, `[Windows] BorderlessMaximizedWindows` |
| `contents/previews/` | the previous theme's `preview.png` and `fullscreenpreview.jpg` |

The comment at the top of both defaults files names the previous theme (its `metadata.json`
`KPlugin` `Name`, on one line, so a name with line breaks cannot add keys) and the backup; a
`metadata.json` that is not an object, or has no usable name, gives the theme's id instead
(2026-10-02: such a file stopped the generator before). `tests/previous_theme_test.py`, run by
`tests/gate-unit.sh` (case `g`), covers this and the KConfig parsing.

Upstream details this relies on (libklookandfeel 6.7.5 `klookandfeelmanager.cpp`):

- The fonts are applied only when the package "provides" them, and `packageContents()` looks for
  `font..menuFont` in `[kdeglobals][WM]` and `activeFont` in `[kdeglobals][General]` (the groups are
  swapped against where `save()` reads them). The package therefore also carries
  `[kdeglobals][WM] font=` as a marker; nothing ever writes it.
- The border size: `fusion-config.sh` sets `BorderSizeAuto=false`, so the package names the size
  the previous decoration asks for (Breeze: `None`, `breeze.json recommendedBorderSize`) unless the
  user had set one.
- Title-bar buttons are read from `layouts/defaults` and applied only with "Desktop and window
  layout".
- Every Global Theme other than Breeze falls back to `org.kde.breeze.desktop` for missing files
  (`lookandfeel.cpp pathChanged`): the package has no layout script, so "Desktop and window layout"
  rebuilds Plasma's default Breeze panel (as for any theme without one), and its splash entry is
  Breeze's. It cannot give back the old panels; `fusion-restore.sh` can.

Not restored by the package (a Global Theme cannot carry them): the panels and desktop widgets, the
desktop wallpaper of the existing desktop (the package names the previous theme's wallpaper, the
running desktop keeps its own), `BorderSizeAuto`, an accent colour, a "None" splash, colour edits
not saved as a scheme, workspaces and shortcuts. `fusion-restore.sh` is the full undo.

## Commands

```
~/.local/share/plasma-fusion/gate/plasma-fusion-gate.sh status   # record, switched-off parts, last runs
~/.local/share/plasma-fusion/gate/plasma-fusion-gate.sh check    # what the next login would do
tools/device/fusion-config.sh                                    # after checking a Plasma update: record and turn back on
plasma-apply-lookandfeel -a org.plasmafusion.previous.desktop    # My previous desktop
```

Test hooks (never set in a real session): `PF_GATE_FAKE_VERSIONS="kwin=6.8.0 kscreenlocker=6.8.0"`
replaces installed versions in memory (never cached); `PF_GATE_RPM` names the rpm program;
`PF_GATE_ROOT` is put in front of the package databases' paths and the Nix system profile.
`fusion-config.sh` passes `PF_GATE_TOOL` (its own absolute path) to `deploy`, which stores it in the
record for the notification.

## Rollback

`tools/device/fusion-restore.sh` (full undo, removes the check). To remove only the check: delete
`~/.config/plasma-workspace/env/plasma-fusion-gate.sh`, `~/.config/systemd/user/plasma-fusion-gate-notify.service`
and its link in `xdg-desktop-autostart.target.wants/`, `~/.local/share/plasma-fusion/gate/`, then
`systemctl --user daemon-reload`; if `gate/off` lists parts, run `fusion-config.sh` first (it turns
them back on). Removing "My previous desktop": delete
`~/.local/share/plasma/look-and-feel/org.plasmafusion.previous.desktop` while another theme is active.

## Verification (2026-09-30)

All on the ThinkPad unless noted; evidence in
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/gate/`.

- `bash -n` and `shellcheck -S warning` clean for every script; `previous-theme.py` compiles.
- `tests/gate-unit.sh BASE [--real-rpm]` (throw-away HOMEs, fake rpm, KConfig's `kreadconfig6` as
  the reader for hand-edited files): 69 pass, 1 skipped on the ThinkPad (the "plugin not installed"
  case, the plugin is installed system-wide there), 71 pass on the laptop. Cases: (a) matching
  versions change no config value and log "no change"; (b) faked KWin/kscreenlocker, Qt
  (light, left circles), lock-screen files only: parts off, a second login changes nothing and
  queues no second notification, the matching login gives every value back; deploy brings the
  compiled decoration back after fusion-config.sh's theme apply removed its keys; a decoration the
  user picked meanwhile is kept; (c) Breeze: parts off, a part the user turns on again stays on,
  Fusion Dark again gives every value back; (i) comments, repeated groups, localised keys,
  `key[$e]`, spaces around `=` and file permissions survive; (e) corrupt, binary or hostile record
  (no command from it runs), missing record, corrupt records and cache, rpm hanging (3.1 s, falls
  back), unreadable kwinrc, empty HOME, no HOME: always exit 0.
- `tests/gate-stub.sh BASE`: the stub sourced through `/usr/libexec/plasma-sourceenv.sh` after
  Fedora's own env scripts: exit 0, captured environment identical with and without the stub, the
  check logged; a hanging check ends after 4.1 s with the environment captured and no process left;
  a failing, noisy check and `set -e` left on by an earlier script do not lose the environment
  (13/13).
- Private sessions (tools/vsession, stage from a clean HEAD aaf13da snapshot plus these tools):
  - gt-a phase 1: Breeze Dark with a user font, `fusion-config.sh --install` (dry run changes
    nothing), "My previous desktop" written from the backup, check installed and deployed; a second
    run reports the check unchanged; (a) matching login: config unchanged; (c) Breeze applied,
    login: snap, attach, outline, switcher and lock screen off and KWin unloads snap after a
    reconfigure; Fusion Dark again, login: all back, KWin loads snap; (d) listed by
    `plasma-apply-lookandfeel --list`, applying it gives back colour scheme, icons, widget style,
    the user's font, default menu and title fonts, cursor, Plasma style, Breeze decoration (KWin
    loads `org.kde.breeze`) and splash; a login under it switches the Fusion-only parts off.
  - login simulated between sessions with `tools/device/tests/vsession/login-sim.sh` (the system
    env scripts and the stub through `plasma-sourceenv.sh`, private runtime directory) with
    `kwin=6.8.0 kscreenlocker=6.8.0`: phase 2's new KWin starts with
    `org.kde.kwin.aurorae.v2 / __aurorae__svg__PlasmaFusionDark`, the drop-in is aside, snap still
    loads, the notification shows over the desktop (`05b-notification.png`) and is dequeued, a
    second mismatching login changes nothing; after a matching login, phase 3's KWin loads
    `org.plasmafusion.decoration` again with the drop-in back and no records; another login changes
    nothing; `fusion-restore.sh` gives back exactly the seed's values (Breeze Dark, user font) and
    removes the check, keeping its log and "My previous desktop".
  - gt-ld: the lead's `scen-ld1.sh` unchanged with HEAD's tools as old and these as new: effective
    fonts, cursor and theme identical to the lead's ld1 at all 8 steps; the check installed at the
    upgrade, unchanged on reruns, kept by `restore --latest`, next login "no change".
  - `systemd-analyze --user verify` of the generated unit (offline): clean. `coredumpctl`: none.
- Timing (M27 / fix 9), ThinkPad, 21 runs each. With one other agent's session running (load
  0.6): a login with the lock screen and the compiled decoration on, versions cached, median 15 ms
  wall (bash start included) and 13 ms inside the check; first login after an rpm transaction
  (runs `rpm -q`) 40 ms; a login that switches off 32 ms, one that turns back on 30 ms. With
  another agent's performance session running: 23 / 20 ms, 59 ms, 50 ms, 41 ms. The stub adds
  6-13 ms to startplasma's env-script step when nothing is on (11 interleaved runs with and
  without it; Fedora's own env scripts take 55-80 ms). Always exits 0; a hung check is cut at 4-5 s.

Not tested: the lock screen itself (the virtual sessions run KWin with `--no-lockscreen`; the
drop-in's effect on `plasma-kwin_wayland.service` and startplasma's reload are verified from the
source, not in a real login), the notify unit under a real systemd login (its command was run by
hand in the session), a real Plasma update.

## Review (2026-09-30)

An adversarial review re-ran every test, read the code line by line and checked the claims
against the 6.7.5 sources. Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/gate/review-*`.
The builder's Verification section above is kept as it was; the numbers below are the review's.

Found and fixed:

| Severity | Finding | Fix |
|---|---|---|
| high | In some locales bash's `[A-Za-z]` misses ASCII letters (tr_TR: `i`). The record and cache names `kwin`, `libplasma`... failed the name check, so in a Turkish session every login read the record as unreadable: safe mode (Plasma's lock screen, Aurorae title bars) at every login, and `rpm -q` every time. | POSIX classes (`[[:alnum:]]`, `[[:digit:]]`); tests `l` (tr_TR, et_EE, de_DE). |
| high | `previous-theme.py` used every `XDG_CONFIG_DIRS` entry as a "system" layer. `fusion-config.sh` takes that variable from plasmashell, and it starts with the live `~/.config/kdedefaults`, which holds Plasma Fusion's values once it was applied. On the real device (Plasma Fusion applied long before, package made later from the pre-Fusion backup) "My previous desktop" would have named Manrope for five fonts, the Fusion window switcher and Fusion's title-bar buttons (`review-previous-theme-real-backup.txt`). The builder's dry run was made without that variable, so it did not show. | `kdedefaults` directories are never a system layer; scenario check `(d0)` and the upgrade scenario count Plasma Fusion values in the package (0). |
| medium | The RPM (`packaging/plasma-fusion.spec.in`) installs only `tools/device/*.sh`: a system-wide install gets neither the check nor "My previous desktop". | Not in this lane: see Needs (exact lines). |
| low | The awk writer got its operations through `awk -v`, which turns backslashes into escape sequences: a restored value with a KConfig escape (`\s`, `\\`) lost its backslash, against "byte for byte". | Operations through `ENVIRON`; test `w`. |
| low | Replacing a key that is the last line of its group dropped the new value into a second `[group]` at the end of the file (KConfig still read it). | Appended at the group's last line also when that line is the replaced key; test `w2`. |
| low | Follow sunset: safe mode wrote the current variant's Aurorae theme into the user file; startplasma switches light/dark after the env scripts and writes only kdedefaults (`Mode::Defaults`), so a login that switched got the other variant's title bars. | When kdedefaults names the Fusion Aurorae theme the user's keys are removed instead (the -Left case still writes them); tests `b`, `b7`, `b8`. The first version of this fix would have put the compiled decoration back over a Breeze theme chosen during safe mode; the added test `b9` caught it and the relaxed restore now ignores removal records in its "still ours" test. |
| low | Automatic light/dark: `LookAndFeelPackage` can name the other theme when the check runs (startplasma picks later). With a Plasma Fusion theme as one of the two, a login could switch the Fusion parts off for a session that then came up as Plasma Fusion. | Automatic switching with a Plasma Fusion default counts as Plasma Fusion; test `m`. |
| low | The notification said "run tools/device/fusion-config.sh", which is no path on the device. | `deploy` records the calling `fusion-config.sh` (`PF_GATE_TOOL`), the notification names it (`~/...`), falling back to the old text when it is gone; test `b`. |
| low | "shellcheck clean" was not true for the four vsession scenarios (SC2148, error: no shell). | `# shellcheck shell=bash` directives. |

Re-verified with the fixed code (ThinkPad unless noted):

- `bash -n`, `shellcheck -S warning` clean for every file in `tools/device` (scenarios included);
  `previous-theme.py` compiles.
- `tests/gate-unit.sh`: 96/96 on the laptop, 94/94 on the ThinkPad with `--real-rpm` (case b6, two
  checks, skipped: the plugin is installed system-wide there). The new cases fail on the builder's engine (b, b8, l tr_TR, m, w, w2)
  and b9 on the first fix. `tests/gate-stub.sh`: 13/13.
- Private sessions from a clean snapshot of HEAD 31affe9 (stage built from it, these tools copied
  over): rgt-a phase 1 (install, dry run, rerun, (a), (c), (d0), (d)), login with faked
  kwin/kscreenlocker 6.8.0, phase 2 (Aurorae from kdedefaults, drop-in aside, notification shown
  with the recorded path, second login no change), matching login, phase 3 (compiled decoration and
  drop-in back, no records, fusion-restore.sh: every seed value back, cfg-0 = cfg-7): 43 PASS,
  0 FAIL. The lead's `scen-ld1.sh` A/B: HEAD's tools as new (rgt-ld0) and these tools (rgt-ld) give
  identical `state.txt` at all 8 steps; "My previous desktop" made at the upgrade has no Plasma
  Fusion value; the check survives `restore --latest` and the next login reports no change.
- Timing, ThinkPad, real rpm, with another agent's session running (load 0.9-1.3): match path
  median 24 ms wall (max 29, n=31); first login after an rpm transaction 52 ms; switching off
  46 ms; turning back on 45 ms (n=11 each). Builder's and reviewed engine interleaved: 24 vs 25 ms.
  The stub costs about 8 ms in startplasma's env-script step (11 interleaved runs, 61 vs 53 ms). A
  hung check ends after 4.1 s.

Still open (not fixed):

- As before: no real login (the drop-in's effect through startplasma's reload and the notify unit
  under systemd are verified from the source), no real Plasma update.
- With `ButtonStyle=LeftCircles`, safe mode still writes the variant's `-Left` theme into the user
  file, so a login-time light/dark switch under Follow sunset keeps the other variant's title bars
  for that session.
- `deploy` (fusion-config.sh, live session) edits `kwinrc` without KConfig's lock file; a KWin
  write in the same few milliseconds could be lost. It only writes when a record must be undone.
- KDE Frameworks (Kirigami, KSvg) are not in the version list, by design of the task: their QML API
  is kept stable within 6.x and they update monthly.
- The dry run with `--install` shows the lock-screen hash of the package installed before the
  copy, not of the build.

## Needs from other parts

- Lock screen (packages/lockscreen): `LockScreenUi.qml` imports `org.kde.plasma.private.sessions`,
  `org.kde.plasma.private.keyboardindicator`, `org.kde.plasma.workspace.keyboardlayout`,
  `org.kde.plasma.clock` and `org.kde.breeze.components` at the top; `MainBlock.qml`
  `org.kde.breeze.components`, `org.kde.kscreenlocker`, `org.kde.config`; `MediaControls.qml`
  `org.kde.plasma.private.mpris`; `StatusChip.qml` `org.kde.plasma.private.battery` and
  `org.kde.plasma.workspace.components`; `NetworkIndicator.qml` `org.kde.plasma.networkmanagement`;
  `LockNotifications.qml` `org.kde.notificationmanager`; `LockOsd.qml`
  `org.kde.plasma.workspace.osd`; `Backdrop.qml` `Qt5Compat.GraphicalEffects`. A missing or changed
  module fails the whole file that imports it. Move each private import into a leaf file loaded
  through a `Loader { source: ... }` with a plain fallback, so only that piece disappears; keep the
  core (`LockScreen.qml`, the password field, `org.kde.kscreenlocker`) on stable imports.
- Settings module (packages/kcm-cpp): read `~/.local/state/plasma-fusion/gate/status`; while
  `versions=changed` and `held` lists `decoration`, do not write
  `library=org.plasmafusion.decoration` (use the Aurorae fallback the page already has, and say why);
  the page re-applies the decoration when it opens today, which would undo the safe mode for this
  session.
- Look and feel (Global Themes): if the themes' `contents/defaults` name
  `library=org.plasmafusion.decoration` (as kcm-cpp.md asks), an in-session theme apply (Follow
  sunset, the Dark tile) during a safe-mode session removes the check's user keys and brings the
  compiled decoration back until the next login. Either keep Aurorae in the themes, or have the
  settings module / quick settings respect `gate/status` as above.
- Packaging (`packaging/plasma-fusion.spec.in`, %install): the scripts loop installs only
  `tools/device/*.sh`, so a system-wide install has neither the check nor "My previous desktop"
  (`fusion-config.sh` then prints that `gate/plasma-fusion-gate.sh` and `previous-theme.py` are
  missing). After the loop add
  `install -D -m 0755 tools/device/gate/plasma-fusion-gate.sh "$dest/plasma-fusion/tools/device/gate/plasma-fusion-gate.sh"`
  and `install -m 0644 tools/device/previous-theme.py "$dest/plasma-fusion/tools/device/"`
  (`fusion-config.sh` runs it with `python3`; `tools/device/tests/` stays out). `%files` already
  covers `%{_datadir}/plasma-fusion/tools/`.
- Lead: after a Plasma or Qt update, check the session (lock screen, decoration) and run
  `fusion-config.sh` to record the new versions; until then the device stays in safe mode
  (decision D17).

## Navigation effect (TABLET2 N1, 2026-10-01)

The tablet navigation effect (`packages/navigation-cpp`, RPM plasma-fusion-navigation) uses KWin's
internal classes, which have no binary compatibility between releases, so it is a version-checked
part like the compiled decoration: `navigation` joins `PARTS`, the `[Plugins]` key joins `WANT`, a
login with the effect on checks the versions (also without the lock screen or the decoration), and a
difference writes `plasmafusion_navigationEnabled=false` and names it in the notification (three
parts are joined "A, B and C"). Tests (`tools/device/tests/gate-unit.sh`): `b` (off with the lock
screen and decoration, notification, restored), `b10` (only the effect on: a KWin 6.7.6 update and a
Qt Quick 6.12 update switch it off, matching logins turn it back on), `c` (another Global Theme):
128 passed; the 3 `p` failures (plugin-missing cases) fail the same way without this change on a
machine with plasma-fusion-decoration installed (the laptop since its 314c89a deploy).

## Desktop containment (TABLET2 H1, 2026-10-01)

The Plasma Fusion desktop (`org.plasmafusion.desktop`) is a copy of plasma-desktop 6.7.5's Folder
View QML; it imports plasma-desktop's private `org.kde.private.desktopcontainment.folder` plugin and
plasma-workspace's containment layout manager, so it is version-checked too: `plasma-desktop` joins
`PACKAGES`, and `desktop` joins `PARTS`. The containment groups of the layout file are found with one
`grep` and their `plugin` keys read in the same `awk` run as the other keys (user file only); the
records are ordinary key records with the group `Containments][N`, so the generic restore puts the
plugin back while it is still `org.kde.plasma.folder`, and leaves a containment the user changed
since (for example to Desktop in Desktop and Wallpaper). The check runs before plasmashell starts, so
the edit is not overwritten by plasmashell's own layout save. A missing package switches the desktop
to Folder View without a notification (like a missing decoration plugin), and back once it is
installed. The notification now joins any number of parts ("A, B, C and D").

Tests (`gate-unit.sh` `b11`): a plasma-desktop 6.8.0 update switches the desktop to Folder View
(its `[General]` keys and the panel untouched, KConfig reads the new value, notification text), a
matching login restores the file exactly; a removed package switches without a notification and
keeps the record while missing, a reinstalled one restores the file exactly; a containment the
user changed while held off is left as it is and the record cleared. `c` also checks the desktop
under another Global Theme. The cases no longer depend on the machine: `PF_GATE_SYSTEM_PLUGINS`
(tests only) replaces the system plugin directories, so the `p` cases pass on a machine with
plasma-fusion-decoration installed. Run 2026-10-01: 144 passed, 0 failed.

## Other distributions (2026-10-02)

Plan: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-10-02-other-distros/INSTALL-OTHER-DISTROS.md`
section 5, P2. Before this the check read versions only with rpm; without rpm it recorded every
version as `no-rpm`, so on Arch, Debian or NixOS it always "matched" and never switched anything
off.

The versions now come from the first package database that knows one of the packages (a foreign
package manager installed next to the system's, such as pacman or dpkg on Fedora, knows none of
them and is skipped):

| Database | Query | Package names | Version kept | Cache stamp |
|---|---|---|---|---|
| rpm (Fedora) | `rpm -q --qf '%{NAME}=%{VERSION}\n'` | `qt6-qtbase`, `qt6-qtdeclarative` | `%{VERSION}` | inode, size and time of `rpmdb.sqlite` (+ `-wal`), as before |
| pacman (Arch) | `pacman -Q` | `qt6-base`, `qt6-declarative` | without epoch and pkgrel | `/var/lib/pacman/local` (a directory per package, replaced at every upgrade) |
| dpkg (Debian) | `dpkg-query -W -f '${db:Status-Status} ${source:Package}=${source:Version}\n'` over all packages | source packages `qt6-base`, `qt6-declarative` (the binary names change between releases: `kwin-wayland`, `libkscreenlocker6`...) | without epoch and Debian revision (`6.11.2+dfsg`); removed packages that kept their configuration files do not count | `/var/lib/dpkg/status` (rewritten and renamed over by every dpkg run) |
| Nix (NixOS) | `nix-store --query --requisites /run/current-system/sw` (`nix-store` from PATH, else from the system profile) | store names `qtbase`, `qtdeclarative`; the name ends before the first `-digit`, so `kwin-x11-6.6.6` is not `kwin` | the store name's version (`kwin-6.6.6-dev` gives 6.6.6) | `readlink /run/current-system/sw` |

The other six names (`plasma-workspace plasma-desktop kwin kscreenlocker libplasma kdecoration`)
are the same everywhere. A database that does not answer within 3 s ends the search.

When no database answers, the versions are unknown: `deploy` records nothing (exit 1, "could not
read the installed versions: no package database (rpm, pacman, dpkg or Nix) was found" or "... with
rpm"), and a login switches the version-bound parts off with the notification ("Plasma Fusion cannot
tell which Plasma it was checked with (...)"), once per change as before.

Records and caches stay readable both ways. A record or cache written from rpm is byte for byte
what the earlier check wrote (no `db=` line; the cache key `list=` unchanged), so a Fedora machine
that recorded with the earlier check sees "no change" at its first login with this one and keeps
its cache (test `v7`). The other databases add `db=pacman|dpkg|nix` (the earlier check ignores the
line). A record from one database is not compared with versions from another ("it was recorded with
rpm, the versions now come from pacman"), and a record of the earlier check on a system without rpm
(`no-rpm` values) counts as untested ("it was recorded without a package database"); in both cases
the next `fusion-config.sh` run records the versions again.

Tests (`tools/device/tests/gate-unit.sh`) no longer depend on the machine: PATH holds the machine's
programs without `rpm`, `pacman`, `dpkg-query` and `nix-store` (fakes go in front per case), the
package databases are below `PF_GATE_ROOT`, and `XDG_DATA_DIRS` and `XDG_CONFIG_DIRS` are empty
directories (an installed plasma-fusion package's `org.plasmafusion.desktop` failed `b11`; `b6` no
longer needs to be skipped where the compiled decoration is installed). New cases:

- `v1` pacman: record `db=pacman`, `kwin=6.7.5` from `1:6.7.5-2`, `qt6-base`; a matching login
  changes nothing and a second one does not run pacman (cache); an upgrade (new directory in
  `local/`) switches off and names `kwin 6.7.5 → 6.8.0`; `deploy` records it and turns back on; a
  hanging pacman is cut at 3 s and falls back.
- `v2` dpkg: source names and versions (`plasma-desktop` from a binNMU, `qt6-base=6.11.2+dfsg`, a
  `config-files` kwin 6.3.6 ignored); cached until the status file is replaced; upgrade and
  downgrade.
- `v3` Nix: a system profile in a store below `PF_GATE_ROOT`, `nix-store` only in the profile;
  `kwin-x11` and the `-dev` output do not count; cached per profile; a switch to 6.7.5 switches off,
  a rollback turns back on.
- `v4` no database: `deploy` fails and records nothing; logins switch off with the reason, one
  notification; `v4b` a record made with rpm and no database later; `v4c` the earlier check's
  `no-rpm` record.
- `v5` an rpm that knows none of the packages (next to pacman) does not answer; `v6` a record from
  rpm against versions from pacman.
- `v7` the engine of a95f707 records and logs in (fake rpm, the machine's rpm database stamp), then
  this one: "no change", record and cache unchanged, rpm not run.

Run 2026-10-02 on the laptop (plasma-fusion and plasma-fusion-decoration installed, pacman,
dpkg and nix-store present): 199 passed, 0 failed, nothing skipped.
