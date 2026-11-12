<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# The full profile (scaffolding)

Status: scaffolding, per [ADR 0001](adr/0001-two-profile-distribution.md). Nothing here ships
until the verification below passes; the stock profile is unchanged by all of it.

## What the profile is

The `plasma-fusion-full` metapackage pins the six Plasma Fusion packages together with the
maintained KWin fork (`kwin`, `kwin-common`, `kwin-libs`) at one exact EVR — the pin — so a
distribution update can never half-upgrade the set. The fork ships in its own Copr project;
enabling the stock repository never offers a KWin replacement.

## The pin

The pin lives in the Fedora spec (`%global kwin_full_pin`): unset means the metapackage is not
built; a release pair sets it to the fork tag's exact EVR (for example `6.8.2-3.fc44.pf2`) in
the same release PR that bumps the version, and `packaging/check-version.sh` validates its
shape. The pin moves only through a release, never in place. The metapackage builds only when
three conditions meet: the full profile's own project builds the spec `--with full`, the target
is the Fedora release the pin carries, and the pin is set — so the stock repository's builds
never emit it, even with the pin present in the spec.

## What is built and what is not

| Piece | State |
|---|---|
| `plasma-fusion-full` subpackage (spec) | built only `--with full`, on the pin's Fedora release, with the pin set; never in the stock repository's builds |
| The fork's RPMs (from `archledger/kwin` tags, distag `.pfN`) | spec + build script committed on the fork's `packaging/fork-rpm` branch |
| The full Copr project (`archledger/plasma-fusion-full`) | not yet created; an owner account action |
| `plasma-fusion status`'s profile reporting | the CLI command's own slice: the profile, the pinned tag and the capabilities (ADR 0001) land with the capability reporting that follows the channel — before the profile goes live, gated together with the stamp |
| Installer `--full` / `--full-restore` | implemented (`scripts/install.sh`); goes live when a release stamps `PF_FULL_FEDORA` (`--full-fedora` in `packaging/stamp-installer.sh`), which follows the full Copr project going live |
| Arch: `kwin-fusion` PKGBUILD | scaffolded in `packaging/arch/kwin-fusion.PKGBUILD` — builds from the fork's signed tag, conflicts/provides kwin; the pf sequence is part of `pkgver` (`6.8.2.pf3`) so a new tag of the same upstream version compares newer (verified with `vercmp`) and the dependency names are Arch's own (verified against the image that builds the fork's KWin) |
| Arch: `plasma-fusion-full` PKGBUILD | scaffolded in `packaging/arch/plasma-fusion-full.PKGBUILD` (+ its `.install` scriptlet, registered with `install=`) — the metapackage with the exact-version pins and the IgnorePkg guidance in the messages pacman shows |
| Debian-family: `kwin-fusion` control | scaffolded in `packaging/debian/control-fusion` — kwin-fusion/kwin-common-fusion/kwin-libs-fusion (each provides/conflicts/replaces its stock counterpart, kwin included) + plasma-fusion-full; every Build-Depends name verified to exist in Debian testing |
| NixOS: `kwin-fusion.nix` | scaffolded in `packaging/nix/kwin-fusion.nix` — the fork's KWin derivation from the nixpkgs dependency set; evaluates against the repository's pinned nixpkgs |
| NixOS: `plasma-fusion-full.nix` | scaffolded in `packaging/nix/plasma-fusion-full.nix` — a `symlinkJoin` metapackage whose closure carries the seven packages (verified: all seven in its references), plus the `systemPackages` list |

Each lane's scaffolding is packaging-only: it builds and installs, but the qualification lanes
(install, restore, login check, no crash) per ADR 0001 must pass per lane before it ships.

## Verification before anything ships (ADR 0001)

1. Copr builds the fork tag and the metapackage; their tests and the stock package tests pass in
   the full project.
2. A Fedora virtual-machine lane installs the full profile (plan, packages, lock, setup, login
   check, no crash), exercises both gated features and their fallbacks, then `--full-restore`
   returns the machine to stock KWin with Plasma Fusion still working.
3. The same on the physical test convertible, including a reboot between the profile switches.
4. `plasma-fusion status` is correct on stock, on full, and after restore.
5. A security-cadence round: publisher integration → new tag → Copr rebuild → one `dnf update`
   transaction on a full-profile machine.
