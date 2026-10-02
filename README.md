# Plasma Fusion

[![build](https://github.com/archledger/plasma-fusion/actions/workflows/build.yml/badge.svg)](https://github.com/archledger/plasma-fusion/actions/workflows/build.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/archledger/plasma-fusion/badge)](https://scorecard.dev/viewer/?uri=github.com/archledger/plasma-fusion)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15168/badge)](https://www.bestpractices.dev/projects/15168)

A KDE Plasma 6 desktop built from the Plasma Fusion design concept: ideas from macOS,
GNOME and Windows 11 on top of Plasma's Global Theme structure, in a dark and a light scheme,
with a tablet posture for convertibles.

<table>
<tr>
<td><a href="design/previews/Main.webp"><img src="design/previews/Main.webp" width="420" alt="Plasma Fusion desktop, dark"></a></td>
<td><a href="design/previews/MainLight.webp"><img src="design/previews/MainLight.webp" width="420" alt="Plasma Fusion desktop, light"></a></td>
</tr>
</table>

These are design boards, the reference for every colour, size and drawing used here. All 25
boards are pictured in [`design/`](design/README.md), with their canvas sources in
`design/boards/`.

## Status

Experimental; the first release, 0.2.0, is being prepared. Developed on Fedora 44 KDE (Plasma
6.7.5, KDE Frameworks 6.30, Qt 6.11) on a ThinkPad X13 Yoga Gen 4 convertible and an ASUS Zenbook
laptop; packaged for Fedora, Arch, Ubuntu 26.10, KDE neon, Debian testing and NixOS, and tested on
each in a virtual machine before a release. It needs Plasma 6.7. Everything it changes for your
account can be undone (`plasma-fusion restore`).

## What it contains

- Global Themes (dark and light), Plasma style, colour schemes, icon and cursor themes,
  wallpapers, fonts (Manrope, Space Grotesk), boot splash and login screen styling
- Window decoration (Aurorae, and a compiled KDecoration3 plugin)
- Shell: top bar with a clock pill and app menu, dock, centred launcher, quick settings and
  Notification Centre, desktop cards
- Tablet posture: full-screen apps, home screen with app pages, gestures from the bottom edge,
  split screen, on-screen keyboard keys, pen menu
- App icons: 407 KDE, GNOME and common Linux apps redrawn as Plasma Fusion tiles that keep each app's
  own mark; every other installed app's own icon placed on a Plasma Fusion tile
- A settings module, a lock screen, power tiers for battery life

Each part is described in `docs/parts/`; the overall plan and decisions are in `docs/PLAN.md`.

## Install

In a terminal of your Plasma session (as yourself; it asks for sudo for the packages):

```sh
curl -fsSL https://github.com/archledger/plasma-fusion/releases/latest/download/install.sh | sh
```

It finds your system's channel, shows what it will do and asks once, installs the packages, then
applies Plasma Fusion to your account (a backup is taken first). Log out and back in once.
`... | sh -s -- --dry-run` shows the plan without changing anything; `update`, `uninstall` and
`status` work the same way. How to check the script's signature first, and what it does on each
system, is in [`docs/parts/installer.md`](docs/parts/installer.md).

| System | Channel |
|---|---|
| Fedora 44, 45 | Copr `archledger/plasma-fusion` |
| Arch and derivatives | AUR `plasma-fusion` |
| Kubuntu / Ubuntu 26.10 | PPA `ppa:archledger/plasma-fusion` |
| KDE neon, Debian testing | the release's `.deb` packages |
| NixOS (unstable) | the flake or module ([`docs/parts/nixos.md`](docs/parts/nixos.md)) |

Afterwards, per account: `plasma-fusion setup` (other users), `plasma-fusion update` (after a
package update; a notice tells you), `plasma-fusion status`, `plasma-fusion restore` (your desktop
as it was before).

## From the sources

For development, or to try the current state: Fedora 44 KDE (Plasma 6.7) and a few minutes. Apart from the build's Python modules,
everything happens in your own account, and a backup is taken first.

```sh
sudo dnf install git python3-pillow python3-pyside6     # the build's Python modules
git clone https://github.com/archledger/plasma-fusion
cd plasma-fusion
tools/build.sh                                       # build every part into stage/home
tools/device/fusion-config.sh --install stage/home   # in a terminal of your Plasma session
```

Then log out and back in once. `tools/device/fusion-config.sh --help` lists the options (light
scheme, keep your panel layout, `--dry-run` to see every change first). To undo everything:

```sh
tools/device/fusion-restore.sh                       # back to the state before Plasma Fusion
```

To update later, get the new sources, build again and run the install again, then log out and
back in:

```sh
git pull
tools/build.sh
tools/device/fusion-config.sh --install stage/home
```

Each run takes a new backup first. Settings you changed yourself are kept. When the configuration
version changes, `~/.local/state/plasma-fusion/config-changes` lists the settings that were
changed and the ones that were kept ([`docs/parts/device.md`](docs/parts/device.md)).

How the parts fit together is in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

The packages (one version, four packages on every channel: the shared part and the compiled
decoration, settings page and tablet gestures, which the source install leaves out) are built
from `packaging/`: [`docs/parts/system.md`](docs/parts/system.md). Releasing is in
[`docs/RELEASING.md`](docs/RELEASING.md), the changes per version in [`CHANGELOG.md`](CHANGELOG.md).

## Contributing

Bug reports, fixes and ideas are welcome: see [`CONTRIBUTING.md`](CONTRIBUTING.md). Security
problems go privately, as [`SECURITY.md`](SECURITY.md) explains.

## Project documents

| Document | What it says |
|---|---|
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | how to report and change things, the coding standards |
| [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) | the Contributor Covenant 2.1 and whom to contact |
| [`GOVERNANCE.md`](GOVERNANCE.md) | how decisions are made, roles, continuity |
| [`SECURITY.md`](SECURITY.md) | how to report a vulnerability and how reports are handled |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | what the next year is meant to bring, and what is left out |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | the parts, how they are built and installed, where state lives |
| [`docs/SECURITY-ASSURANCE.md`](docs/SECURITY-ASSURANCE.md) | what you can and cannot expect in security, and why |
| [`docs/PLAN.md`](docs/PLAN.md), [`docs/parts/`](docs/parts/) | the build plan, decisions and one page per part |

## Licence

Plasma Fusion follows KDE's licensing policy:

| Part | Licence |
|---|---|
| Code (widgets, KWin scripts and effects, settings module, decoration, tools) | GPL-2.0-or-later |
| Files kept from KDE's own sources (parts of the desktop, lock screen and task switcher) | their original licence (GPL-2.0-or-later or LGPL-2.0-or-later) |
| Artwork and documentation | CC-BY-SA-4.0 |
| Metadata and plain data | CC0-1.0 |
| Bundled fonts (Manrope, Space Grotesk) | OFL-1.1, by their authors |

Every file states its licence in an SPDX header or in `REUSE.toml`; the licence texts are in
`LICENSES/`. The project is [REUSE](https://reuse.software) compliant (`reuse lint`).
