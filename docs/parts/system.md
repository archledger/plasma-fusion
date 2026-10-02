# Part: system-wide packages and login greeter

Three pieces:

1. **The packages** (one source, one version, four packages on every channel): `plasma-fusion`,
   everything of Plasma Fusion that all users can share (themes, widgets, icons, fonts, KWin
   scripts, the helpers, the setup tools and the `plasma-fusion` command), and the compiled parts
   `plasma-fusion-decoration`, `plasma-fusion-settings` and `plasma-fusion-navigation`. Fedora
   (Copr), Arch (AUR), Ubuntu (PPA), KDE neon and Debian testing (release `.deb`s) and NixOS (flake
   or module) build them from the same files; the installer (docs/parts/installer.md) picks the
   channel.
2. **Login greeter styling** (`tools/system/greeter-apply.sh`, `greeter-restore.sh`): Plasma Fusion
   Dark for the plasma-login-manager 6.7.5 greeter, the way System Settings' "Apply Plasma
   Settings…" would do it, plus the greeter wallpaper.
3. **Kate and Marknote** installed with dnf for the design's Code and Notes slots.

Owned files: `packaging/` (version, source tarball, the shared install script, the Fedora spec,
the PKGBUILD, the Debian packaging, the Nix packages, rpmlint filters, licence texts),
`.packit.yaml`, `tools/plasma-fusion`, `tools/system/greeter-apply.sh`,
`tools/system/greeter-restore.sh`, this file. The per-user step is `plasma-fusion setup`
(`tools/device/fusion-config.sh`; not owned here).

## 0. One version, one source, one install script

| File | What |
|---|---|
| `VERSION` | the only version (`0.2.0`); `packaging/check-version.sh` checks that the spec, the PKGBUILD and the Debian changelog agree (build workflow, Packit) |
| `packaging/version.sh [--rpm\|--deb\|--plain]` | the version of a commit: `X.Y.Z` at the tag `vX.Y.Z`; before it `X.Y.Z~N.gitHASH` (N commits in all), after it `X.Y.Z^N.gitHASH` (rpm) or `X.Y.Z+N.gitHASH` (dpkg) with N commits since the tag. A snapshot sorts above the release before it and below the one it leads to |
| `packaging/make-source.sh [--ref REF\|--worktree]` | `plasma-fusion-X.Y.Z.tar.gz`: `git archive` of a tag (the release asset every channel builds from) or the working tree (test builds); sorted, owners 0, the commit's time, `gzip -n`: the same commit gives the same bytes |
| `packaging/install-tree.sh` | installs the shared part into a package root for every channel: what `tools/build.sh` staged, the Plymouth theme (as the source `plymouth-install.sh` installs, or on NixOS as a theme), the per-user templates, the setup tools, `plasma-fusion` in `bin/`, `version`, `tested-plasma.txt`, `items.txt` and the documentation. `--libexecdir` (Arch: `/usr/lib`) and `--system-share` (NixOS: the system profile) set the paths the charge limit's polkit action and tile, the on-screen keyboard's desktop file and the icon names handed back to Breeze and hicolor use; every replacement must find its text. It fails when the build staged anything it does not install |
| `packaging/tested-plasma.txt` | the Plasma series this version was tested with (`6.7`); the login check records no other series as tested (gate.md) |
| `packaging/fedora/plasma-fusion.spec` | the Fedora spec Copr builds (`.packit.yaml`) |
| `packaging/arch/PKGBUILD` | the AUR package (split: `plasma-fusion` any, the compiled parts x86_64), from the signed tag; a pacman hook names the compiled part due for a rebuild after a kwin or kdecoration upgrade |
| `packaging/debian/`, `packaging/build-deb.sh` | one source package, four binaries; `--target ubuntu:SERIES` (PPA, `X.Y.Z-0ppa1~SERIES1`), `neon`, `debian:testing` (`X.Y.Z-1~TARGET1`) or `plain` (`X.Y.Z-1`, the shared part for other Debian-family systems); `--source` makes the unsigned source package for Launchpad. The navigation package depends on the KWin series it was built against (`kwin-wayland (>= built, << next minor~)`) |
| `packaging/nix/`, `flake.nix` | the Nix packages and the NixOS module (nixos.md) |
| `packaging/stamp-installer.sh` | the release's installer (installer.md) |

Each compiled part installs `share/plasma-fusion/built-against/<part>` (the KWin or KDecoration and
Qt it was built with); `plasma-fusion status` compares it with the running KWin. The CI workflow
`packages` builds, lints, installs and checks every channel in a container of its system
(`tools/tests/packages/`); ci.md.

## 1. The RPMs

### Build

```
packaging/build-rpm.sh [--topdir DIR] [--compiled] [--no-lint]   # default DIR: build/rpmbuild (git-ignored)
```

* `packaging/fedora/plasma-fusion.spec` with this tree's version (`packaging/version.sh --rpm`) and
  Release `1`, plus `.dirty<UTC yyyymmddHHMM>` when the working tree differs from the revision
  (each dirty test build sorts newer than the one before). Example:
  `0.2.0~281.gitcde5bb0-1.fc44`. A snapshot gets its own changelog entry.
* Without `--compiled` it builds the shared part only (`rpmbuild --without compiled`; the build
  workflow does this); with it all four packages (KWin, KDecoration and KDE Frameworks development
  packages needed: `dnf builddep packaging/fedora/plasma-fusion.spec`).
* The source tarball is the working tree as it is (tracked plus untracked, not git-ignored files;
  `git ls-files --cached --others --exclude-standard`), stable order, owners 0, the revision's
  commit time as mtime. git is only read (`--no-optional-locks`: no index refresh).
* Repeatable: `SOURCE_DATE_EPOCH` is the revision's commit time, rpm takes it as the package's
  build time (`use_source_date_epoch_as_buildtime`) and clamps the files' times to it, and the
  build host is recorded as `reproducible`.
* `%build` runs `tools/build.sh` into `_stage/` (no display, `QT_QPA_PLATFORM=offscreen`, session
  variables removed) and the Plymouth generator; with the compiled parts, the three CMake builds
  (the settings page's QML gets a time stamp derived from its sources, kcm-cpp.md).
* `%install` runs `packaging/install-tree.sh` and `cmake --install` of the three parts; the effect's
  QML files get times derived from their content (navigation-cpp README).
* `%check`: every naming-table package has its `metadata.json` (the pen menu, the desktop cards,
  the two layout templates and the tablet script included), all four icon/cursor themes their
  `index.theme`, the login background exists, and what the per-user step takes from the package
  is there (power-tiers unit and the five helpers, pen templates, login check, pen defaults, the
  Global Themes' `ensure-topbars.js`, the font fallback, the switcher's shader, the snap script's
  `ensureTopBars.js`, the command and its version files, each compiled part's record); no absolute
  links; no link is dangling (Breeze's two themes are linked into the buildroot for the moment of
  the check).
* The shared part holds no compiled code but is built per architecture with the compiled parts:
  rpm builds noarch subpackages of an arched package, not the other way round.

### Contents (`rpm -qpl`, 12 000+ entries, 10 MB)

| Installed at | From the build | Notes |
|---|---|---|
| `/usr/share/color-schemes/PlasmaFusion{Dark,Light,HighContrast}.colors` | foundation | directory has no owner in Fedora 44: co-owned |
| `/usr/share/plasma/look-and-feel/org.plasmafusion.{dark,light}.desktop/` | lookandfeel | |
| `/usr/share/plasma/desktoptheme/plasma-fusion-{dark,light}/` | plasma-style | |
| `/usr/share/plasma/plasmoids/org.plasmafusion.*/` | top bar, quick settings, launcher, dock, desktop cards | glob, so new Plasma Fusion widgets are packaged without a spec change |
| `/usr/share/plasma/shells/org.plasmafusion.lockshell/` | lockscreen | |
| `/usr/share/plasma/layout-templates/org.plasmafusion.panel.{topbar,dock}/` | lookandfeel | the "Add Panel" entries; the directory belongs to plasma-desktop |
| `/usr/share/icons/{PlasmaFusion,PlasmaFusion-Dark,PlasmaFusion-cursors,PlasmaFusion-Light-cursors}/` | icons, cursors | all 8 816 links kept (see below) |
| `/usr/share/aurorae/themes/PlasmaFusion{Dark,Light}{,-Left}/` | decoration | `aurorae/` and `aurorae/themes/` co-owned (no owner in Fedora) |
| `/usr/share/wallpapers/PlasmaFusion{,-*}/` | foundation | |
| `/usr/share/kwin/tabbox/org.plasmafusion.switcher/`, `/usr/share/kwin/scripts/plasmafusion-{snap,attach,tablet}/` | kwin, kwin-tablet | see "KWin paths"; the switcher's compiled shader (`shaders/thumbnail.frag.qsb`) is the repository's file unless `qsb` is installed at build time |
| `/usr/share/konsole/PlasmaFusion{Dark,Light}.colorscheme`, `Plasma Fusion.profile` | foundation | `konsole/` co-owned (Konsole 26.08 installs nothing there) |
| `/usr/share/org.kde.syntax-highlighting/themes/Plasma Fusion {Dark,Light}.theme` | foundation | `themes/` co-owned |
| `/usr/share/fonts/plasma-fusion/*.ttf` + `OFL-Manrope.txt`, `OFL-SpaceGrotesk.txt` | foundation (static per-weight files) | the OFL texts are marked `%license`; `font(manrope)` etc. provides generated automatically |
| `/usr/share/plasma-fusion/backgrounds/` | foundation | `dusk-ridge-dark-{dimmed,blurred,login,splash}.png` |
| `/usr/share/plasma-fusion/pen/templates/{Note,Whiteboard}.xopp` | pen | the pen menu finds them with StandardPaths |
| `/usr/share/plasma-fusion/powerfx/plasma-fusion-powerfx.service` | powerfx | where `fusion-config.sh` looks for the unit to enable it per user |
| `/usr/libexec/plasma-fusion/plasma-fusion-powerfx` | powerfx (`.local/libexec` of the build) | in the unit's `ExecSearchPath` (as `/usr/lib/plasma-fusion/` on distributions without `/usr/libexec`); nothing is enabled by the package |
| `/usr/share/plasma-fusion/config/` | the build's `.config`: `gtk-{3,4}.0/{gtk.css,plasma-fusion.css}`, `fontconfig/conf.d/60-plasma-fusion-fallback.conf`, `systemd/user/plasma-fusion-powerfx.service` | templates for the per-user step only (the user unit is installed from `plasma-fusion/powerfx/` instead); the package writes nothing into a home directory |
| `/usr/share/plasma-fusion/tools/{device,system,pen}/*.sh`, `tools/device/gate/plasma-fusion-gate.sh`, `tools/device/previous-theme.py` | `tools/device`, `tools/system`, `tools/pen` | shebangs become `/usr/bin/bash` (Fedora's brp-mangle-shebangs); the login check and "My previous desktop" generator sit where `fusion-config.sh` expects them |
| `/usr/share/plasma-fusion/docs/` | `README.md`, `docs/PLAN.md`, `docs/parts/*.md` | `%doc` |
| `/usr/bin/plasma-fusion` | `tools/plasma-fusion` | `setup`, `update`, `status`, `restore`, `drop-user-copy`, `version` (device.md) |
| `/usr/share/plasma-fusion/{version,tested-plasma.txt,items.txt}` | `VERSION`, `packaging/tested-plasma.txt`, install-tree.sh | the version, the tested Plasma series (login check), the package's top-level entries (`drop-user-copy`) |
| `/usr/share/plasma-fusion/built-against/{decoration,settings,navigation}` | the compiled parts' CMake | one per installed compiled part |
| `/usr/share/licenses/plasma-fusion/{GPL-2.0-or-later,CC-BY-SA-4.0}.txt` | `packaging/LICENSES/` | `%license` |

Not in the RPM: per-user files (`~/.config/gtk-*`, the lock-screen systemd drop-in, kdeglobals and
every other setting). `fusion-config.sh` stays the per-user step.

License tag: `GPL-2.0-or-later AND CC-BY-SA-4.0 AND OFL-1.1` (code; artwork; fonts).

**KWin paths (checked in 6.7.5).** KWin looks up window switchers in `kwin-wayland/tabbox/` then
`kwin/tabbox/` (`tabboxhandler.cpp`), scripts in `kwin-wayland/scripts/` and `kwin/scripts/`
(`scripting.cpp`, the scripts KCM, screen-edge KCM), and the outline QML by the relative
`[Outline] QmlPath` in all data directories. The KPackage structures install to `kwin/tabbox/` and
`kwin/scripts/` (`plugins/kpackage/*`), which is also where the build puts them per user; the
package uses the same `kwin/` paths. `/usr/share/kwin/tabbox` belongs to kdeplasma-addons,
`/usr/share/kwin` and `kwin/scripts` to nobody: all three are co-owned.

**Icon links.** The per-user themes hand 1 658 names back to Breeze with absolute links into
`/usr/share/icons/breeze{,-dark}` (right for `~/.local/share`). In the package they become
relative links (`../../../../breeze/actions/16/x.svg`, computed lexically with `realpath -m -s`, so
the link still names the Breeze file, not what that file points to today). They resolve in any
root the package is installed to, and rpmbuild no longer prints 3 316 "absolute symlink"
warnings. Relative links inside the themes (into `art/`, `glyphs/`, the `@2x` directories) are
unchanged. Requires `breeze-icon-theme >= 6.30` (the version the links were made against).

**Scriptlets: none.** Fontconfig's file trigger (`fc-cache -s` on `/usr/share/fonts`) refreshes the
font cache. The only icon-cache triggers on Fedora 44 are per theme (hicolor, Adwaita, Breeze
each carry their own); following the icons part ("No icon cache is shipped") the Plasma Fusion
themes get no `icon-theme.cache`, so there is no cache that could go stale after an update. KPackage
reads `metadata.json` directly (no sycoca step).

**Requires** (`plasma-fusion`): `plasma-workspace`, `plasma-desktop`, `libplasma`, `kwin`,
`aurorae`, `plasma5support` (all >= 6.7), `breeze-icon-theme >= 6.30`, `fonts-filesystem`,
`kde-filesystem`, `python3`, `polkit`, `/usr/bin/{kreadconfig6,kwriteconfig6,busctl,setpriv}` (the
scripts), Pillow and rsvg-convert or PySide6 (app icons). **Recommends**: the decoration and
settings parts of the same build. **Suggests**: the navigation part, `xournalpp` (the pen menu's
tiles; as a weak dependency it would bring TeX Live, about 300 MB, so `setup --pen` installs it
without its own weak dependencies), `python3-pyside6`, `kate`, `marknote`, `konsole`,
`plasma-login-manager`. Each compiled part
requires `plasma-fusion` of the same version and release, and KDecoration or KWin >= 6.7.

**rpmlint**: no errors with the justified filters of `packaging/plasma-fusion.rpmlintrc`:
`dangling-relative-symlink` for the Breeze and hicolor hand-back links (targets in a required
package or an app's own; `%check` proves the Breeze ones resolve), `dangling-symlink` for the Flatpak
ones, `no-binary` for the shared part (arched only because of the compiled subpackages),
`incorrect-fsf-address` (the GPL text as published, in each package), `spelling-error 'usr'` (paths
in `%description`). The warnings left: no manual page for `plasma-fusion`, no documentation in the
decoration and settings packages, the two font files the Plymouth theme carries again, and a
desktop file without its own binary (System Settings runs the module).

### Install, upgrade, remove (root)

```
dnf install ./plasma-fusion*-0.2.0*.rpm                    # also upgrades an older build
rpm -V plasma-fusion                                        # verify (no output = clean)
dnf remove plasma-fusion                                    # rollback (run greeter-restore.sh first
                                                            # when the greeter uses Plasma Fusion)
```

Per-user copies in `~/.local/share` win over `/usr/share` (XDG data order), so installing the
package does not change a session that already has the per-user build: `plasma-fusion status` warns
about them and `plasma-fusion drop-user-copy` moves them aside (device.md).

Each user then runs, inside their Plasma session, `plasma-fusion setup` (after later updates
`plasma-fusion update`; a login notice says when). Most people use the installer instead
(installer.md), which picks the channel and runs that step.

### Rebuilt Fedora packages

`packaging/patches/` holds patches to Fedora packages that Plasma Fusion needs before upstream ships
them, each directory with a build script and a README (what, why, rebuild, when to drop). They are
not part of the plasma-fusion RPM; a machine installs them separately.

| Package | Release | Why | Test (ThinkPad private sessions, plasmashell under gdb, 2026-10-02) |
|---|---|---|---|
| plasma-workspace | `6.7.5-1.fc44.pf1` | the global menu's Search crashed plasmashell after the active app rebuilt a submenu (KDE [bug 526561](https://bugs.kde.org/show_bug.cgi?id=526561), unfixed on master 19e67e2); the top bar shows Search only with this build (`menuSearch`, docs/parts/shell-topbar.md) | stock applet: the bug report's reproducer, a window switch with stale results and the typing sequence crash (3 of 3, twice); rebuilt applet: 0 crashes in 9 sequences with results shown each time, a result activated with Return |

## 2. The login greeter (plasma-login-manager 6.7.5)

Sources read: `plasma-login-manager` v6.7.5 from invent.kde.org (`build/sy/src/`), KConfig v6.30.0
(`src/core/kconfig.cpp`, `kconfigdata.cpp`), plasma-workspace 6.7.5 (`kcms/colors`,
`wallpapers/image`).

### What "Apply Plasma Settings…" does

* `kcm.cpp` `PlasmaLoginKcm::synchronizeSettings()` reads the user's `kdeglobals`, `plasmarc`,
  `plasma-localerc`, `kcminputrc`, `kwinoutputconfig.json`, `fontconfig/fonts.conf` and `kxkbrc`
  (each `QStandardPaths::locate(GenericConfigLocation, …)`, i.e. `~/.config` first) and passes their
  text to the KAuth action `org.kde.kcontrol.kcmplasmalogin.sync`.
* `plasmaloginauthhelper.cpp` `sync()`: repairs ownership of the greeter home (6.6 upgrade), then
  **as the `plasmalogin` user** (fork + setgid/setuid) removes `~/.cache` (the Plasma style cache,
  see `ThemePrivate::useCache`) and writes each file to `/var/lib/plasmalogin/.config/<name>` with
  mode 0644. Files it was not given are left alone. `reset()` removes `.config` and `.cache`.
* The greeter session start, `startplasma-login-wayland` (`startplasma.cpp`
  `setupPlasmaEnvironment()`): puts `~/.config/kdedefaults` first in `XDG_CONFIG_DIRS`; when
  `kdeglobals [KDE] LookAndFeelPackage` (default `org.kde.breeze.desktop`) differs from
  `kdedefaults/package`, writes that Global Theme's defaults there (`KLookAndFeelManager`, mode
  Defaults); applies the colour scheme when `[General] ColorSchemeHash` differs from the scheme
  file's SHA-1. So a synced Fusion user's kdeglobals (`LookAndFeelPackage=org.plasmafusion.dark.desktop`)
  needs the Global Theme **installed system-wide**, which is what the RPM provides.
* The wallpaper: the KCM's `save()` (action `…save`) writes the non-default settings, including
  `[Greeter] WallpaperPlugin` and `[Greeter][Wallpaper][<plugin>][General]`, to
  **`/etc/plasmalogin.conf`** (whole file, comments dropped) and copies a user image to
  `/var/lib/plasmalogin/wallpapers/` (images outside the greeter's reach only).
  `plasma-login-wallpaper` reads the same configuration through `PlasmaLoginSettings`.

**Configuration precedence (a finding that differs from the research).** `PlasmaLoginSettings::getInstance()`
opens `/etc/plasmalogin.conf` and calls `addConfigSources` with `/etc/plasmalogin.conf.d/*`, then
`/usr/lib/plasmalogin/defaults.conf`, then `/usr/lib/plasmalogin/plasmalogin.conf.d/*`. KConfig
6.30 parses the added sources in the order they were added and a later file overwrites an earlier
one (`parseUserConfigFiles`, `KEntryMap::setEntry`), the main file last. Effective order, lowest to
highest: `/etc/plasmalogin.conf.d/*` < `/usr/lib/plasmalogin/defaults.conf` <
`/usr/lib/plasmalogin/plasmalogin.conf.d/*` < `/etc/plasmalogin.conf`. Fedora's
`kde-settings-plasmalogin` ships `defaults.conf` with `Image` **and** `PreviewImage` =
`/usr/share/wallpapers/Fedora/`, so a `[Greeter]` drop-in in `/etc/plasmalogin.conf.d/` has no effect
on Fedora. Confirmed in a virtual session: with the drop-in in place the greeter wallpaper stayed
Fedora's (first test run, `sy-greeter` 00-wallpaper, superseded). The image wallpaper also shows
`PreviewImage` instead of `Image` whenever it is not `"null"` (`imagepackage/contents/ui/main.qml`),
so both keys must be set.

### `tools/system/greeter-apply.sh` (root)

```
greeter-apply.sh [--display-from FILE] [--dry-run] [--check]
greeter-apply.sh --output DIR [--data-dir DIR] [--display-from FILE]   # no root: write into DIR (tests)
```

Recommended call (in the user's Plasma session, so `~` is that user's home):
`sudo /usr/share/plasma-fusion/tools/system/greeter-apply.sh --display-from ~/.config/kwinoutputconfig.json`.
`--display-from` copies that display configuration to the greeter, as "Apply Plasma Settings…"
does with `kwinoutputconfig.json`. The file is read by its owner (`setpriv`, never by root; a link
is refused), must be at most 1 MiB and must parse as KWin's output configuration (a list with an
`outputs` section). Without it the greeter keeps its own display scale: on the ThinkPad that is 1
(1920x1200 logical), so the whole greeter is drawn at 3/4 of the size the session uses at 4/3.

Values come from the installed Global Theme's `contents/defaults` (one source of truth):
colour scheme `PlasmaFusionDark`, Plasma style `plasma-fusion-dark`, icons `PlasmaFusion-Dark`,
cursors `PlasmaFusion-cursors`, widget style `Breeze`, fonts `font`, `menuFont`, `toolBarFont`
(Manrope 9.75 pt = 13 px) and `smallestReadableFont` (Manrope 9 pt).

As the greeter user (`setpriv --reuid=plasmalogin --regid=… --init-groups --no-new-privs`, like the
helper; nothing in the greeter home is touched as root), in a clean environment (offscreen, no bus,
a temporary HOME):
1. copies the greeter's current `kdeglobals`, `plasmarc`, `kcminputrc` to a temporary directory
   (keys it does not set are kept: a previous sync's keyboard, touchpad, locale settings);
2. applies the colour scheme with `plasma-apply-colorscheme` (the same applicator as System
   Settings: every `[Colors:*]`, `[ColorEffects:*]`, `[WM]` group, `ColorSchemeHash`), after
   removing `[General] ColorScheme` so it always applies;
   `[General] AccentColor` and `accentColorFromWallpaper` are removed first: `applyScheme()` tints
   every colour with an accent it finds in kdeglobals (one could come from an earlier "Apply
   Plasma Settings…"), and the greeter shows the scheme's own colours as designed;
3. sets `[KDE] LookAndFeelPackage=org.plasmafusion.dark.desktop`, `widgetStyle`, the four fonts,
   `[Icons] Theme`; `plasmarc [Theme] name`; `kcminputrc [Mouse] cursorTheme`; with
   `--display-from`, `kwinoutputconfig.json`;
4. after the backup, puts the three files in place (write next to the target, then rename; 0644 as
   the helper does) and removes `~/.cache`.

As root: `/etc/plasmalogin.conf` gets `[Greeter] WallpaperPlugin=org.kde.image` and
`[Greeter][Wallpaper][org.kde.image][General] Image` and `PreviewImage` =
`file:///usr/share/plasma-fusion/backgrounds/dusk-ridge-dark-login.png` (the Login board's background:
Dusk Ridge dark, blurred, zoomed, under a 50 % veil; rendered by the foundation part). While the file
has no `[Greeter]` group the block is appended as text, so its comments stay; otherwise the keys are
written with `kwriteconfig6` (which drops comments, as the KCM's save does). Then `restorecon`, and a
check that the effective values (all four configuration layers in plasma-login's order) are ours.

`kdedefaults/` is left to the greeter: its next start rewrites it from the Fusion Global Theme
(`LookAndFeelPackage` changed). The explicit keys in `~/.config` win over `kdedefaults` either way.

Backup before any change: `/var/lib/plasma-fusion/greeter-backup-<UTC>/` (root, 0700, a new
directory per run): the greeter's whole `~/.config` (streamed out by the greeter user),
`/etc/plasmalogin.conf`, a `manifest` (present/absent per file the run writes), `info` (with
`before=plasma-fusion` or `before=other`: whether the greeter's `LookAndFeelPackage` already was
Plasma Fusion Dark, and `display_from=` when used), and `etc/plasmalogin.conf.applied` (what was
written, only when the file changed).

`--check` compares the greeter's files and the effective wallpaper keys with the wanted values
(exit 0 = Plasma Fusion) and prints the greeter's display scale. `--dry-run` prints unified diffs
of every file. The configuration directories are listed as plasma-login lists them (`QDir::Files`:
no hidden files, links to files included).

Nothing is restarted: the greeter shows the change the next time it starts (next logout or reboot).

### `tools/system/greeter-restore.sh [BACKUP_DIR] [--dry-run]` (root)

Goes back to the state saved in BACKUP_DIR by undoing every run of greeter-apply.sh, newest
first, down to and including that one. Default BACKUP_DIR: the newest backup whose `info` does not
say `before=plasma-fusion`, i.e. the look from before Plasma Fusion. (A second run of
greeter-apply.sh, for example after a package update, makes a backup of the Plasma Fusion state;
restoring only the newest backup would undo nothing.) Backups of the first version of the script
have no `before=` line and count as taken before Plasma Fusion.

For each backup: as the greeter user, puts back the files that run wrote (`kdeglobals`, `plasmarc`,
`kcminputrc`, `kwinoutputconfig.json`; with their old modes) or removes them when there were none,
and replaces `kdedefaults/` with the saved copy (the greeter's session start rewrote it). Root only
reads regular files from the backup; a link that was in the greeter's `~/.config` is made again by
the greeter user and never followed by root. `/etc/plasmalogin.conf`: the saved copy goes back byte
for byte while the file is still what that run wrote; otherwise only the three wallpaper keys get
their old values (keys that already have them are left alone, because kwriteconfig6 drops the
file's comments). A drop-in `/etc/plasmalogin.conf.d/plasma-fusion.conf` from the first version
of the script is removed. At the end `~/.cache` is removed. `--dry-run` evaluates every step
against the current files (a later step does not see what an earlier one would change).
Tested on the ThinkPad: after restoring the first backup, `diff -r` of the greeter `.config` against
the backup was empty (`kwinoutputconfig.json` and `kglobalshortcutsrc` left out of the comparison;
neither script touches them), `kdeglobals` had the backup's checksum and mode 0600 again.

Manual rollback without the script (root): `cp -a /var/lib/plasma-fusion/greeter-backup-<t>/etc/plasmalogin.conf /etc/`;
as `plasmalogin`: copy back `config/kdeglobals`, delete `.config/plasmarc`, `.config/kcminputrc`,
replace `.config/kdedefaults/`, delete `.cache`. Or System Settings > Login Screen > "Reset…"
(the helper's `reset()`) and pick a wallpaper there.

### Preview without logging out

`plasma-login-greeter --test` exists (`main.cpp`: `MockGreeterProxy` instead of the daemon socket),
but paints its window dark grey. The preview therefore starts, inside a private virtual session
(tools/vsession, name `sy-greeter`), `plasma-login-wallpaper` and `plasma-login-greeter` **without**
`--test` and without `SDDM_SOCKET` (the proxy's connect to an empty socket name fails; no daemon is
contacted), `QT_QPA_PLATFORMTHEME=kde` as `startplasma-login` sets it, and HOME holding a copy of
the real `/var/lib/plasmalogin/.config` after greeter-apply.sh (its `kdedefaults` still Breeze: the
worst case). Scenario: `build/sy/scen-greeter.sh`. The daemon configuration is the real one in `/etc`.

Result (evidence `greeter-*.png`):
* idle: the Login board's background, measured equal to the render (mean RGB in three regions
  within 1/255), Manrope clock and date;
* prompt: Plasma Fusion text field (dark fill, radius, blue focus ring), Manrope, PlasmaFusion-Dark
  action icons, battery indicator; KWin's cursor theme `PlasmaFusion-cursors` (supportInformation).
  plasma-login-wallpaper blurs and adjusts the background for the prompt (contrast 0.8, saturation
  1.5, intensity 0.7), so dark areas come out up to 8/255 lighter than the board;
* the same greeter with the old (Breeze) settings for comparison: `greeter-stock-settings-prompt.png`.

The real greeter could not be checked: that waits for the user's next logout (or reboot).

### Deviations from the Login board (startup-4)

The greeter's QML is compiled into `plasma-login-greeter` (qrc), so only styling changes (accepted
deviation in PLAN.md). Stock layout: large centred clock and date (Manrope; the board: 28 px Space
Grotesk clock top left), user list with the account picture or a generic face (board: 112 px letter
avatar), Plasma text field with a separate login button (board: 340 × 48 pill with inline arrow and
reveal button and halo), power actions as a centred row of icons (board: glass circles bottom
right), session name bottom left and battery bottom right (board: session pill; EN / accessibility /
Wi-Fi / battery chips top right). No "Use fingerprint" hint (the greeter has none).

## 3. Kate and Marknote

`dnf install kate marknote` (with the weak dependencies `kate-plugins`, `kate-krunner-plugin`).
In a fresh session with only the system-wide copies (`sy-system`, `sy-systemp`, `sy-final`) and in
the per-user session (`sy-peruser2`):
* the launcher pinned `applications:org.kde.kate.desktop` (Code) and
  `applications:org.kde.marknote.desktop` (Notes) (KActivities store, agent
  `org.kde.plasma.favorites.applications`, `pins-systemwide.txt`); the Notes tile appears after
  Calendar; clicking Code opens Kate, clicking Notes opens Marknote (real clicks with pfinput);
* the dock's Code item is Kate: with Kate running the Code item shows the running mark and no extra
  task appears; Marknote (not a dock pin) appears as a task with the Notes tile icon
  (`dock-kate-marknote.png`).

The real session will not pick them up by itself: the launcher pins its defaults only when its pin
list is empty, and the dock replaced the missing Kate with KWrite once and saved that
(`applyLauncherFallbacks`). Both happened when the real session was set up without Kate (see Needs).

## Verification (ThinkPad, 2026-09-29)

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/system/` (screenshots, settings
dumps, `thinkpad-verification.txt`, `rpm-build-summary.txt`, the RPM and SRPM, the fusion-config patch).
Scenarios and seeds: `build/sy/scen-*.sh`, `build/sy/seed-common/pf-sy/` (git-ignored).


* `rpm -V plasma-fusion`: clean. 8 816 links in the four themes, none dangling, none absolute.
  12 font files in `fc-list`. `greeter-apply.sh --check`: all ok (`thinkpad-verification.txt`).
* Per-user vs system-wide (same package content; the per-user seed is the RPM payload mapped back to
  `~/.local/share` with the absolute Breeze links restored):
  `sy-peruser2` (`fusion-config.sh --install`) vs `sy-systemp` (empty HOME, RPM only, patched
  `fusion-config.sh`): settings identical except the lock-screen wallpaper path (now the system one);
  screenshots of desktop, launcher, quick settings, dock hover, Konsole, Kate, Marknote differ in
  0.05–0.19 % of the pixels, all in the clock, CPU/memory and battery text (`system-vs-peruser.png`).
  With `fusion-config.sh` as packaged (`sy-system`): no `[Outline] QmlPath`, no Konsole profile, no
  Kate/KWrite colour theme, no GTK stylesheets, lock-screen wallpaper pointing at a missing
  `~/.local/share/wallpapers/PlasmaFusion/` (Konsole 13 % of the pixels different).
* Greeter: see above. Restore tested for real, apply run again after it.
* Core dumps since the start (`coredumpctl list --since "2026-09-29 17:11:38"`): 18 `kdialog`
  (uid plasmalogin) at 17:36–17:46 from the first version of `greeter-apply.sh --check`: it ran
  `kreadconfig6` as the greeter user with root's HOME, KConfig found no writable config directory
  and tried a message box without a display. Fixed (every KDE tool now runs with a private HOME,
  offscreen; three runs since, no new dumps). 2 aborts at 17:37:51 of `plasma-login-greeter --help`
  and `plasma-login-wallpaper --help`, started by hand over SSH without a display (Qt has no
  platform). None came from the virtual sessions. The 18 kdialog entries have no core file
  (`Storage: none`); the two `--help` aborts (uid 1000) do have core files (1.1 MB each,
  `coredumpctl list` shows `present`; corrected in the review).

## ThinkPad system changes (all reversible)

| Change | Rollback |
|---|---|
| `dnf install` of `plasma-fusion` (builder: `0.1.0-6.git913b0c8.dirty202609292204.fc44` over three earlier test builds; review, 18:25: upgraded to `0.1.0-7.git380cc97.dirty202609292222.fc44`, built from the tree with the review fixes) | `sudo dnf remove plasma-fusion` (after `greeter-restore.sh`) |
| `dnf install kate marknote` (+ `kate-plugins`, `kate-krunner-plugin`) | `sudo dnf remove kate marknote kate-plugins kate-krunner-plugin` |
| Each dnf transaction invalidated a pending dnf5daemon offline update (the Sep 25 one was already stale: its rpmdb cookie predates later installs; the review's upgrade at 18:25 printed "Pending offline transaction has been invalidated" once more) | Discover prepares it again |
| `/var/lib/plasmalogin/.config/{kdeglobals,plasmarc,kcminputrc}` written, `/var/lib/plasmalogin/.cache` removed (twice: first version, restore, current version) | `sudo /usr/share/plasma-fusion/tools/system/greeter-restore.sh /var/lib/plasma-fusion/greeter-backup-20260929T214643Z` |
| `/etc/plasmalogin.conf`: `[Greeter]` wallpaper block appended | same command (puts the original back byte for byte) |
| `/etc/plasmalogin.conf.d/plasma-fusion.conf` (first version) | already removed by the restore of backup `…213719Z` |
| Review, 18:29–18:30: greeter `~/.config/kwinoutputconfig.json` scale 1 -> 4/3 (`greeter-apply.sh --display-from` with the greeter's own file, eDP-1 scale set to 4/3); applied, restored for real (whole `.config` identical to the backup afterwards), applied again. Backups `…222950Z`, `…223003Z` (`before=plasma-fusion`) | this run only: `sudo /usr/share/plasma-fusion/tools/system/greeter-restore.sh /var/lib/plasma-fusion/greeter-backup-20260929T223003Z`; everything, back to Breeze: `sudo /usr/share/plasma-fusion/tools/system/greeter-restore.sh` (undoes `…223003Z`, `…222950Z`, `…214643Z` in that order) |
| `/var/lib/plasma-fusion/` (root 0700): backups `greeter-backup-20260929T213719Z` (first version), `…214643Z`, `…222950Z`, `…223003Z`. The directory also holds `plymouth/` of the Plymouth part | `sudo rm -r /var/lib/plasma-fusion/greeter-backup-*` once no longer needed (not the whole directory: `plymouth-uninstall.sh` needs `plymouth/`) |
| `/tmp/pfv-sy-*` (virtual sessions), `/tmp/pfv-sy-rpm/` (RPM copies) | removed at the end |
| Review: `/var/tmp/pfv-rsy-gr1`, `rsy-gr43`, `rsy2-*` (virtual sessions), `/tmp/pfv-rsy-rpm/`, `/var/tmp/pfv-rsy-display/` | removed at the end |

Not touched: the real session (no input, settings, panels or processes), plasmalogin.service,
PAM, irlume, fprintd.

## Needs from other parts

* **Device setup (`tools/device/fusion-config.sh`, lead):** apply
  `build/sy/fusion-config-systemwide.patch` (copy in the evidence folder; `git apply --check` clean
  against the current file). Without it, a user with only the RPM gets no snap-zone outline, no
  Konsole profile, no Kate/KWrite colour theme, no GTK stylesheets and a lock-screen wallpaper URL that
  points into `~/.local/share` (does not exist). The patch adds `data_path()` (user data directory,
  or the build with `--install`, then `XDG_DATA_DIRS`) for those four checks and the wallpaper URL,
  and installs the GTK stylesheets from `/usr/share/plasma-fusion/config/` with the same merge logic
  as `--install` (backed up the same way). Tested in `sy-systemp` / `sy-final`, and again in the
  review (`rsy2-sysp`, against the fusion-config.sh of 18:32; the patch was regenerated there with
  `build/sy/patched/make-patch.py`, same hunks, new offsets).
* **Lead, real session (after Kate and Marknote):** the launcher and dock there were set up without
  Kate/Marknote. Code stays KWrite and Notes is missing until the user re-pins (launcher: drag from
  All apps; dock: pin Kate, unpin KWrite) or the pins are reset (launcher favorites in the
  KActivities store `org.kde.plasma.favorites.applications`; dock `launchers` in
  plasma-org.kde.plasma.desktop-appletsrc). Not done here (no changes to the real session).
* **Lead:** rebuild the RPM after the next commit (the current one says `.dirty…`: other parts were
  editing while it was built). Record this checkpoint in the shared ledger (not written by this part).
* **Lead, greeter display scale:** the greeter now uses 4/3 (review). If the user's panel
  configuration changes, run in the user's session
  `sudo /usr/share/plasma-fusion/tools/system/greeter-apply.sh --display-from ~/.config/kwinoutputconfig.json`
  so the greeter follows the session's scale again.
* **Plymouth part:** `tools/system/plymouth-install.sh` and `plymouth-uninstall.sh` are packaged
  automatically (`tools/system/*.sh` go to `/usr/share/plasma-fusion/tools/system/`), but
  `plymouth-install.sh` needs a theme directory built by `generators/plymouth/build.sh`, which the
  RPM does not carry: from the package alone the script cannot be used. Either the theme goes into
  the RPM (for example a `plasma-fusion-plymouth` subpackage with `%install`/`%files` lines here,
  `Requires: plymouth-plugin-script`) or the scripts stay repository-only. Decision for the lead.
* **Dock (observation, low):** in the virtual sessions the name pill and magnification of the item
  hovered in the dock-hover shot (Mail) stayed after the pointer left and windows opened; likely the
  known virtual-pointer limit, worth a look on the real session.

## Review (2026-09-29, 18:08–18:45 EDT)

An adversarial review of the RPM, the greeter scripts and the Kate/Marknote step, with fixes in this
part's files. Scratch: `build/rsy/`, `build/rsy2/` (git-ignored). Evidence: `review-*.png` in the
evidence folder.

### Findings and fixes

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | medium | The greeter ran at display scale 1 on the ThinkPad's 1920x1200 panel (its own `kwinoutputconfig.json`), so it was drawn at 3/4 of the board's sizes, while the session and Plymouth use 4/3. The builder's preview ran at 1440x900 and did not show this. "Apply Plasma Settings…" copies `kwinoutputconfig.json`; greeter-apply.sh did not. | `greeter-apply.sh --display-from FILE` copies a display configuration as the KCM does. The file is read by its owner, never by root, links are refused, and it must parse as KWin output configuration of at most 1 MiB. `--check` prints the greeter's scale. Applied on the ThinkPad (eDP-1 at 4/3). Previews at 1920x1200 in both states: `review-greeter-scale.png`. |
| 2 | medium | After a second run of greeter-apply.sh (for example after a package update), `greeter-restore.sh` with no argument restored the newest backup, which holds the Plasma Fusion state: "undo" silently did nothing. A backup also covered only the files its own run wrote. | The backup `info` records `before=plasma-fusion` or `before=other`. Restore undoes the runs newest first, down to and including the target. The default target is the newest backup from before Plasma Fusion. Tested for real on the ThinkPad (see Verification below). |
| 3 | medium | greeter-restore.sh read backup files as root with `<"$BACKUP/config/$f"`. A symlink that the greeter user had in its `~/.config` is kept as a link in the backup, because tar stores links. Root would then follow it and copy the target (for example `/etc/shadow`) into a greeter-readable file. The report said everything in the greeter home is handled as the greeter user; the restore path was the exception. | Restore reads only regular files. A link in the backup is made again by the greeter user with `ln -sfn` and is never followed by root. The manifest records links as present. |
| 4 | medium | The documented rollback `sudo rm -r /var/lib/plasma-fusion` would also delete `/var/lib/plasma-fusion/plymouth/`, the Plymouth part's saved theme and `plymouthd.conf`, which `plymouth-uninstall.sh` needs. | Docs, table and report now say `sudo rm -r /var/lib/plasma-fusion/greeter-backup-*`. |
| 5 | low | `%install` copies a fixed list of directories. A part that stages a new directory would be left out of the RPM without any error. | `%install` compares the staged file list with the copied one and fails, naming the files, when anything is missing or when the stage has anything outside `.local/share` and `.config`. Tested with a simulated stage: it fails on the extras and passes without them. |
| 6 | low | `applyScheme()` tints the colours with an `AccentColor` it finds in kdeglobals. An accent left by an earlier "Apply Plasma Settings…" would recolour the Fusion greeter. | `[General] AccentColor` and `accentColorFromWallpaper` are removed before the scheme is applied. |
| 7 | low | The restore's "file changed since" path ran `kwriteconfig6 --delete` or a write even for keys that already had their old value. kwriteconfig6 rewrites the whole file and drops the comments of `/etc/plasmalogin.conf`. | Keys that already have their old value are skipped. |
| 8 | low | `effective()` listed the conf.d directories with `find -type f` and word splitting. plasma-login lists them with `QDir::Files`: hidden files are skipped and links to files are included. | A QDir-like listing, read line by line. |
| 9 | low | Two runs of greeter-apply.sh in the same second would share one backup directory (`install -d`). | One new directory per run (`mkdir`, fails if it exists). |
| 10 | low (report) | "No core files were stored" was wrong. The two `--help` aborts of plasma-login-greeter and plasma-login-wallpaper at 17:37:51 have core files (1.1 MB each). | Corrected in Verification. |
| 11 | observation | The dock keeps a stale hover name pill ("KMail", "Search") in later shots. This is the dock part's item, already listed below. | — |

Not changed, checked:
* Configuration precedence: `plasmaloginsettings.cpp` adds `/etc/plasmalogin.conf.d/*`, then
  `defaults.conf`, then `/usr/lib/plasmalogin/plasmalogin.conf.d/*`. KConfig 6.30 (`parseUserConfigFiles`)
  parses the extra sources in that order and the main file last. The builder's finding holds.
* `startplasma-login-wayland` (`startplasma.cpp`) rewrites `kdedefaults` from `LookAndFeelPackage`
  and re-applies the colour scheme when `ColorSchemeHash` differs. The greeter's kdeglobals carries
  the hash of the installed `PlasmaFusionDark.colors` (`bbd104eb…`), so a package update that
  changes the scheme is picked up at the next greeter start.
* `rpm -V plasma-login-manager` reports `/var/lib/plasmalogin` mode `.M`. This is not from this
  part: Fedora's tmpfiles.d sets 0750, while the RPM says 1770.

### Verification

* **RPM.** Built twice from the current tree (revision 380cc97 plus the working tree). Both times
  rpmlint reported 0 errors and 0 warnings; the unfiltered findings are the same five justified
  ones. The RPM payload against a fresh `tools/build.sh` stage: every staged file is packaged and
  has the same content. The 8 816 links match the stage's targets once made relative, and none is
  absolute.
* **ThinkPad.** Upgraded to `plasma-fusion-0.1.0-7.git380cc97.dirty202609292222`. `rpm -V` is
  clean. PlasmaFusion and PlasmaFusion-Dark have 4 184 links each, the cursor themes 224 each; none
  is dangling or absolute. 12 font files in `fc-list`. The 8 plasmoids include the three desktop
  cards.
* **Greeter.**
  * `--check`: all ok, display `eDP-1 x1.3333`. Before the change, `--dry-run` showed that only
    the scale line (and the JSON formatting) would change: the other files were already identical.
  * Real restore of the display run: afterwards, `diff -r` of the whole greeter `.config` against
    the backup was empty, and `/etc/plasmalogin.conf` was untouched (byte-identical).
  * Default restore `--dry-run` now chains `…223003Z`, `…222950Z` and `…214643Z` back to Breeze.
    Explicit `…213719Z` chains all four.
  * Previews (rsy-gr1, rsy-gr43): 1920x1200 at scale 1 and at 4/3.
* **Integrated test (current stage plus current RPM).** Three sessions:
  * `rsy2-user`: `--install` from the stage;
  * `rsy2-sysp`: empty HOME, RPM only, patched fusion-config.sh;
  * `rsy2-sys`: empty HOME, RPM only, fusion-config.sh as packaged.

  `rsy2-user` and `rsy2-sysp` have identical settings apart from the lock wallpaper path, and
  identical launcher pins, Kate and Marknote included. Their screenshots differ in 0.10–0.27 % of
  the pixels, in these shots: desktop, launcher, quick settings, dock hover, Konsole, switcher,
  launcher pins, dock with Kate, and the Light desktop, launcher and quick settings. The differing
  pixels are the clock, the CPU/memory card, the battery and the phase of the dock's hover
  animation (`review-systemwide-vs-peruser.png`). `rsy2-sys` still misses the Outline QmlPath, the
  Konsole profile, the Kate/KWrite theme and the GTK stylesheets, and points the lock wallpaper at
  `~/.local`, so the fusion-config.sh patch is still needed.
* **Kate and Marknote.** With Kate running, the dock's Code item shows the running mark
  (`review-systemwide-dock-kate.png`). The launcher pins `org.kde.kate.desktop` and
  `org.kde.marknote.desktop` (`review-systemwide-launcher-pins.png`).
* **Core dumps since 18:08.**
  * From other agents: kscreen-doctor, kstart and spectacle aborts from sub-second SSH probes
    (`--help`, or `-o` without a display), and kwin_wayland and spectacle from `perf-pilot-*`.
  * From this review's sessions and scripts: none. The greeter runs as the greeter user left no
    kdialog aborts.
* **ThinkPad `/tmp`.** During the review it ran out of inodes (1 048 576 used) because of leftover
  `/tmp/pfv-*` sessions from other parts. Reported to the lead, then cleaned up (11 % at 18:40).
  The vsession tools now default to `/var/tmp`.
* **Not touched:** the real session, plasmalogin.service, the display manager's running state,
  PAM, irlume, fprintd.
