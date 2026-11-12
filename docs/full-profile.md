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
| The fork's RPMs (from `archledger/kwin` tags, distag `.pfN`) | the fork repository's packaging; not yet produced |
| The full Copr project (`archledger/plasma-fusion-full`) | not yet created; an owner account action |
| Installer `--full` / `--full-restore` | designed in ADR 0001; follows the channel, not before |

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
