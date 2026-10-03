<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Changelog

Newest first. Each release lists the Plasma series it was tested with and the systems it supports.

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
