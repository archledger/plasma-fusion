<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Changelog

Newest first. Each release lists the Plasma series it was tested with and the systems it supports.

## Unreleased

- The greeter's wallpaper can match the lock screen's treatment (`greeter-apply.sh --login-image
  dimmed`); the other choices are the Login board's blur with its veil (the default) and the same
  blur without it. The greeter's clock and layout stay compiled into plasma-login-greeter.
- The Plasma Fusion settings module gains an Icons section (Designed tiles / Real app icons) and a
  Lock & Login section (notification cards and titles on the lock screen). High contrast now reaches
  applications that follow the XDG settings portal, and the generated reference palette kits
  (`docs/parts/consistency.md`) let apps built on other toolkits match the theme.
- The live date patch on the Calendar tiles no longer shows as a seam: it paints the tile art's
  own colours. The launcher shows Merkuro Calendar's live date again (its app list had a typo),
  and GNOME Calendar keeps its own tile art: the patch only covers tiles that carry the art's
  fixed SEP 28.
- The dock shows one tile per app: on a system without a web browser, the Browser pin
  (`preferred://browser`) resolves to whatever handles HTML's `text/plain` parent type (Kate on a
  minimal install) and the dock showed two identical Kate tiles. A `preferred://` pin that
  resolves to an app pinned explicitly is hidden while the explicit pin stays; it reappears once
  the system has a real app for the role.
- Setup waits until plasmashell has finished redrawing before it restarts it: a shell stopped
  right after a live theme change could crash on exit while it still compiled the new theme's
  shaders (seen with Mesa's software renderer in virtual machines).
- On Arch, `install.sh uninstall` also removes the `plasma-fusion-debug` package that an AUR
  helper installs.
- Ready for Plasma 6.8 (tested with the 6.8 beta): menus and drop-down lists are readable in
  Plasma Fusion Light; the lock screen asks for the password even when the stock lock screen last
  unlocked another way; split screen from the home screen and the launcher works again; the dock's
  Meta+Alt+1..9 keys go through Plasma Fusion's own shortcuts; the tablet navigation starts from a
  defined state.
- The window decoration supports the shadow-only style of Plasma 6.8 when built against
  KDecoration 6.8: windows with the "Only shadow" window rule get the Plasma Fusion shadow and
  outline without a title bar, instead of falling back to the app's own decoration. Builds against
  Plasma 6.7 are unchanged.
- The log-out screen is Plasma Fusion's again on Plasma 6.8: 6.8's log-out greeter reads the
  log-out QML from the shell package, so the screen ships in the org.plasmafusion.lockshell shell
  package and the Plasma Fusion lock screen setup starts the greeter with that package through a
  per-user D-Bus service override. Plasma 6.7 is unchanged (its greeter reads the Global Theme).
- The launcher's Calendar tile shows today's month and day over the tile art (as the dock
  already did) instead of the art's fixed SEP 28.

## 0.2.0 (2026-10-03)

The first release. Tested with Plasma 6.7 (6.7.5 on Fedora 44, Arch, Ubuntu 26.10 and KDE neon,
6.7.4 on Debian testing).

- Packages for every system from one source and one version: `plasma-fusion` (themes, widgets,
  icons, fonts, KWin scripts, the setup tools) and the compiled window decoration, settings page and
  tablet navigation. Fedora 44 and 45: Copr `archledger/plasma-fusion`. Arch and derivatives: AUR
  `plasma-fusion`. Kubuntu / Ubuntu 26.10: `ppa:archledger/plasma-fusion`. KDE neon and Debian
  testing: the release's `.deb` packages. NixOS (unstable): the flake or the module.
- An installer for all of them: `curl -fsSL
  https://github.com/archledger/plasma-fusion/releases/latest/download/install.sh | sh`
  (docs/parts/installer.md). Release files are checked against the signed `SHA256SUMS`.
- The `plasma-fusion` command: `setup`, `update`, `status`, `restore`, `drop-user-copy`.
- The login check records only the tested Plasma series as tested: on a newer Plasma the parts
  that depend on Plasma internals stay off until a Plasma Fusion update, and a package update with
  new settings brings a notice to run `plasma-fusion update`.
- Running setup again keeps your light, dark or automatic choice.

Not covered: the boot splash and the login screen styling are for Fedora only; the tablet
navigation needs a rebuild after every KWin update (Copr and the PPA rebuild it, AUR users rebuild
the package; the login check keeps it off until then).
