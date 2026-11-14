<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# The full profile

Status: ships with 0.8.0 on Fedora 44, per [ADR 0001](adr/0001-two-profile-distribution.md),
after the verification below. The other lanes are packaging scaffolding and do not ship. The
stock profile is unchanged by any of it.

## What the profile is

The `plasma-fusion-full` metapackage pins the six Plasma Fusion packages together with the
maintained KWin fork (`kwin`, `kwin-common`, `kwin-libs`) at one exact EVR — the pin — so a
distribution update can never half-upgrade the set. The fork ships in its own Copr project;
enabling the stock repository never offers a KWin replacement.

## The pin

The pin lives in the Fedora spec (`%global kwin_full_pin`): unset means the metapackage is not
built; a release pair sets it to the fork tag's exact EVR (for example `6.8.2-3.fc44.pf2`) in
the same release PR that bumps the version, and `packaging/check-version.sh` validates its
shape. The pin moves only through a release, never in place. 0.8.0 pins `6.8.2-3.fc44.pf5`
(fork tag `v6.8.2-pf5`). The metapackage builds only when
three conditions meet: the full profile's own project builds the spec `--with full`, the target
is the Fedora release the pin carries, and the pin is set — so the stock repository's builds
never emit it, even with the pin present in the spec.

## What is built and what is not

| Piece | State |
|---|---|
| `plasma-fusion-full` subpackage (spec) | built only `--with full`, on the pin's Fedora release, with the pin set; never in the stock repository's builds |
| The fork's RPMs (from `archledger/kwin` tags, distag `.pfN`) | `packaging/fedora/kwin-fusion.spec` and `build-fork-rpm.sh` on the fork's main branch (archledger/kwin#29, #31: the source package carries the tag's number, as Copr rebuilds it from its spec alone); built in the full Copr project from the signed tags `v6.8.2-pf3`, `pf4` and `pf5` |
| The full Copr project (`archledger/plasma-fusion-full`) | live: the fork's KWin builds and Plasma Fusion's packages built `--with full`; unlisted while the candidates were tested |
| `plasma-fusion status`'s profile reporting | implemented (`tools/plasma-fusion`, [`parts/system.md`](parts/system.md)): the profile and the pin from the record the metapackage installs (`share/plasma-fusion/full-profile`), and what the running KWin advertises of the three capabilities; verified on stock, on full and after a restore with the lanes below |
| Installer `--full` / `--full-restore` / `update` | live from 0.8.0 (`scripts/install.sh`): `packaging/release-assets.sh` stamps the pin's Fedora release (`--full-fedora 44`; `PF_FULL_FEDORA` overrides it) |
| Arch: `kwin-fusion` PKGBUILD | scaffolded in `packaging/arch/kwin-fusion.PKGBUILD` — builds from the fork's signed tag, conflicts/provides kwin; the pf sequence is part of `pkgver` (`6.8.2.pf3`) so a new tag of the same upstream version compares newer (verified with `vercmp`) and the dependency names are Arch's own (verified against the image that builds the fork's KWin) |
| Arch: `plasma-fusion-full` PKGBUILD | scaffolded in `packaging/arch/plasma-fusion-full.PKGBUILD` (+ its `.install` scriptlet, registered with `install=`) — the metapackage with the exact-version pins and the IgnorePkg guidance in the messages pacman shows |
| Debian-family: `kwin-fusion` control | scaffolded in `packaging/debian/control-fusion` — kwin-fusion/kwin-common-fusion/kwin-libs-fusion (each provides/conflicts/replaces its stock counterpart, kwin included) + plasma-fusion-full; every Build-Depends name verified to exist in Debian testing |
| NixOS: `kwin-fusion.nix` | scaffolded in `packaging/nix/kwin-fusion.nix` — the fork's KWin derivation from the nixpkgs dependency set; evaluates against the repository's pinned nixpkgs |
| NixOS: `plasma-fusion-full.nix` | scaffolded in `packaging/nix/plasma-fusion-full.nix` — a `symlinkJoin` metapackage whose closure carries the seven packages (verified: all seven in its references), plus the `systemPackages` list |

Each lane's scaffolding is packaging-only: it builds and installs, but the qualification lanes
(install, restore, login check, no crash) per ADR 0001 must pass per lane before it ships.

## Verification before anything ships (ADR 0001)

1. Copr builds the fork tag and the metapackage; their tests and the stock package tests pass in
   the full project. Done for `v6.8.2-pf3`, `pf4` and `pf5` and the candidates of 0.8.0: the
   fork's 27 suites on each tag's line before the tag, and Plasma Fusion's own `%check` in each
   of its Copr builds (the KWin spec has none).
2. A Fedora virtual-machine lane installs the full profile (plan, packages, lock, setup, login
   check, no crash), exercises both gated features and their fallbacks, then `--full-restore`
   returns the machine to stock KWin with Plasma Fusion still working
   (`tools/tests/release-vm/fulltest.sh`: `fresh`, and `switch` from the stock profile with the
   record's directory root's alone). Run on the 0.8.0 candidates.
3. The same on the physical test convertible, including a reboot between the profile switches.
   Done on the ThinkPad X13 Yoga with the pf3 candidates: `--full`, a reboot, the checks (37),
   the tiler's matrix, `--full-restore` to the recorded versions, a reboot, the stock checks
   (28), `--full` again, a reboot, the checks (37).
4. `plasma-fusion status` is correct on stock, on full, and after restore. Done in both lanes.
5. A security-cadence round: publisher integration → new tag → Copr rebuild → one `dnf update`
   transaction on a full-profile machine. Done with the real `v6.8.2-pf4`: a Fedora 44 VM on the
   pf3 candidate ran `install.sh update`, which was one dnf transaction (the KWin packages to
   `pf4`, the metapackage and the six packages to the pf4 candidate) and left the version lock at
   `pf4`.
