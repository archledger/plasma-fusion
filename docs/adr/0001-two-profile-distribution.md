<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# ADR 0001: Two distribution profiles — stock and full

Status: Accepted 2026-11-11.

## Context

Plasma Fusion ships six packages — `plasma-fusion` and the five compiled parts — through Copr,
the AUR, a PPA, `.deb` sets and a Nix flake, and every channel installs them next to the
distribution's own KWin ([`RELEASING.md`](../RELEASING.md)). Nothing Plasma Fusion installs
replaces a Plasma package. Two features already behave differently depending on the compositor:

- The window switcher releases a hidden card's thumbnail assignment only when the compositor
  advertises a lifecycle capability; stock KWin keeps the assignment (the retained fallback,
  [`parts/kwin.md`](../parts/kwin.md)).
- The tablet navigation effect dims secondary quick views only when the compositor propagates
  offscreen opacity to the compositor side ([`parts/navigation-cpp.md`](../parts/navigation-cpp.md)).

The maintained KWin fork [`archledger/kwin`](https://github.com/archledger/kwin) exists for exactly
those compositor-side guarantees. Its `plasma-fusion` branch is upstream KWin 6.8.2 plus the
KDE stable branch through `6e1c7993ef8c` and the downstream corrections; a weekly publisher
integrates the stable branch, and fork CI builds and tests every change. It advertises the two
capabilities above as versioned, constant, read-only QML properties:

| Capability property | Version | Guarantees | Consumer |
|---|---|---|---|
| `WindowThumbnail.plasmaFusionThumbnailSourceLifecycleVersion` | 1 | bounded per-(view, client) cleanup in the weak thumbnail cache | switcher |
| `QuickSceneEffect.plasmaFusionOffscreenOpacityVersion` | 1 | `OffscreenQuickView::setOpacity()` reaches the compositor-side item; a non-unit opacity reports a non-opaque region | navigation |

Dynamic tiling ([#115](https://github.com/archledger/plasma-fusion/issues/115)) is blocked on
compositor behaviour stock KWin does not offer: a separately owned tile root that is released when
its output or desktop disappears, and a serial-aware settling mark the placement memory can trust.
The tested corrections are KWin-side, and the project does not submit further upstream KWin
patches, so the fork is the only intended vehicle. #115 stays closed until its owner is
production-qualified; this ADR is the packaging decision that lets it ship into a profile at all.

The problem: there is no honest way to offer the fork's guarantees through the current channels.
Replacing KWin for every Copr/AUR/PPA user is unacceptable — the fork lags distribution security
updates by its weekly cadence — and hiding fork-only behaviour behind version checks without
telling the user which compositor they run makes support and bug reports ambiguous.

## Decision

Plasma Fusion is distributed in **two profiles**:

1. **Stock profile** — exactly what ships today: the six packages, installed next to the
   distribution's own KWin, on every current channel. Every fork-dependent feature keeps its
   documented stock fallback. The stock profile is the default everywhere and its support matrix
   (Fedora 44/45, Arch, Ubuntu 26.10, KDE neon, Debian testing, NixOS) is unchanged.

2. **Full profile** — the six packages plus an exactly pinned release of the maintained KWin
   fork, expressed as one metapackage `plasma-fusion-full` that `Requires` the six packages and
   the fork's `kwin`, `kwin-common` and `kwin-libs` at one exact version. The full profile is
   opt-in, Fedora first, and is the only supported way to run the fork with Plasma Fusion.

### Capability gating

- The fork advertises each guarantee as a **constant, read-only, integer QML property** named
  `plasmaFusion<Capability>Version`, available before first use; version 1 denotes exactly the
  documented guarantees, and a later version only adds to them.
- A Plasma Fusion feature that needs a fork guarantee must **gate on the property** — QML:
  `Number.isInteger(version) && version >= 1`; C++: a QObject property lookup like
  `fusionSupportsOffscreenOpacity()` in `navigation-cpp` — and must keep a stock fallback that
  the part's tests cover.
- **Version strings must not be used to detect the fork**: stock KWin 6.8.2 and the fork report
  the same version string. A missing or non-integer property means stock or an older fork:
  unsupported, no error.
- A new capability is added to the fork as one commit pair (implementation + version property)
  with tests, and to this repository together with its consumer's fallback tests. The table above
  grows with each one; a version is never silently redefined.

### Exact KWin pins

- A full-profile release binds **one exact fork tag** `v<upstream>-pf<N>` (first release:
  whichever tag the qualification run approves; today's fork tip is the `plasma-fusion` branch).
  Fork tags carry only Plasma Fusion release pins; upstream tags are not mirrored.
- On Fedora the fork packages carry a dist tag: `kwin-6.8.2-3.fc44.pf2` (this set is built and
  installed on the project's test convertible today). The metapackage `Requires` those exact
  EVRs, and the installer applies a version lock, so a distribution update can never
  half-upgrade the set: KWin, the fork packages and the six packages move together or not at all.

### Installer

- `install.sh --full` (Fedora first): checks the distribution and Plasma series are supported,
  records the installed stock KWin EVRs to a restore file, enables the full profile's repository,
  installs the metapackage set, applies the version lock and then runs the unchanged per-user
  setup. `--dry-run` and `--yes` behave as today; unsupported systems are refused with exit 3 and
  nothing changed.
- `install.sh --full-restore`: removes the lock and the metapackage, reinstalls the recorded
  stock KWin EVRs (`distro-sync`), and leaves the six Plasma Fusion packages installed — they run
  on stock. `uninstall` on a full system performs the restore step first.
- `plasma-fusion status` reports the profile, the pinned tag and whether the running compositor
  advertises each capability.
- The installer never installs the fork silently: `--full` is a separate, named choice, and the
  plan it prints names the packages it replaces.

### Signing

- Fork source is pushed only as signed commits on the protected `plasma-fusion` branch (no force
  pushes, no merge commits); fork tags are signed; fork CI builds and tests every push and tag.
- Full-profile RPMs are built by Copr from those tags and signed with the Copr repository key,
  exactly like the stock profile's RPMs today.
- The Plasma Fusion release key and the installer's `SHA256SUMS` verification are unchanged; no
  new key is introduced by this ADR.

### Compatibility and channels (Fedora first)

- The full profile launches **on Fedora 44 only** — the one series with a qualified fork build
  and install evidence. Each additional series (Fedora 45, Arch, …) is added only after its
  install and restore lanes pass like the stock release lanes ([`parts/release-tests.md`](../parts/release-tests.md)),
  plus one new lane: restore back to stock KWin.
- The full profile lives in **its own Copr project** (proposed `archledger/plasma-fusion-full`).
  Enabling the stock repository must never offer a KWin replacement; the two profiles are separate
  repositories so a stock user cannot install the fork by accident.
- AUR, PPA, `.deb` and Nix stay stock-only until the Fedora full lane is established; porting the
  full profile to them is a later, separately tested decision.

### KWin security-update cadence

- The weekly publisher integrates KDE's stable Plasma/6.8 branch — including its security fixes —
  into the fork, and fork CI builds and tests each integration.
- The pin moves only through a **new `pf` tag, a Copr rebuild and a full-profile metapackage
  update**: one transaction for the user, no silent in-place moves. A security-relevant fix in
  the stable stream is published ahead of the weekly timer.
- The honest limit is stated to the user in the installer plan and the repository description:
  the full profile receives KWin security fixes on the fork's cadence, which can lag the
  distribution by days. Users who cannot accept that use the stock profile.

### Release lanes and upgrades

- **Stock lane**: the current `vX.Y.Z` releases on all channels, unchanged.
- **Full lane**: fork tags `v<upstream>-pf<N>` in `archledger/kwin` and the metapackage in the
  full Copr project. A full-profile release is a named pair: one `plasma-fusion` release and one
  fork tag it pins; the metapackage requires at least that release.
- **stock → full**: `install.sh --full` (records, swaps, locks, sets up).
- **full → stock**: `install.sh --full-restore` (or `uninstall`), then normal updates.
- **Within a series**: a new `pf` tag plus metapackage update arrives as one `dnf update`
  transaction.
- **Plasma major upgrade** (a Fedora release with a new Plasma): the version lock holds KWin back
  and `plasma-fusion status` warns that the pinned series no longer matches the installed one.
  The supported path is `--full-restore` before the system upgrade, or waiting for the new
  series' qualified pin. Upgrading the system with the fork held back is the user's explicit
  responsibility, stated in the installer plan.

## Consequences

- The stock profile, its channels and its release process do not change at all.
- The fork gains a supported, named, reversible distribution route, and #115 has a place to ship
  into once its owner is production-qualified and the re-entry tests pass — those gates are
  unchanged by this ADR and remain the blocker recorded in [`DEFERRED.md`](../DEFERRED.md).
- The visible value of the full profile at launch is the two existing capabilities (thumbnail
  release, offscreen dimming). That is modest, known, and accepted: the profile exists so
  fork-dependent behaviour has an honest, testable home — not to promise tiling before its
  qualification.
- Costs and risks the project accepts knowingly: maintaining a KWin replacement on at least one
  distribution, the security-update lag described above, and one more release lane to qualify.
- Rejected alternatives: replacing KWin in the existing channels (unacceptable risk for stock
  users); a `plasma-fusion-kwin` package name parallel to `kwin` (KWin is not
  parallel-installable: same files, same units); and detecting the fork by version string
  (stock and fork report the same string).

## Verification

Before the full profile ships, all of this must pass, and it repeats per series:

1. Copr builds the fork tag and the metapackage; their tests and the stock package tests pass in
   the full project.
2. A Fedora virtual-machine lane installs the full profile (plan, packages, lock, setup, login
   check, no crash) and exercises both gated features and their fallbacks, then
   `--full-restore` returns the machine to stock KWin with Plasma Fusion still working.
3. The same on the physical test convertible, including a reboot between the profile switches.
4. `plasma-fusion status` is correct on stock, on full, and after restore.
5. A simulated security-cadence round: publisher integration → new tag → Copr rebuild → one
   `dnf update` transaction on a full-profile machine.

The capability-gating behaviour itself is already covered by the switcher's enabled/fallback
matrix and the navigation capability tests; each new capability adds its own pair there.
