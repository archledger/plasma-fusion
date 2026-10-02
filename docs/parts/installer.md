# Part: installer

`scripts/install.sh`: one command that detects the system, installs the Plasma Fusion packages
through its channel and runs the per-user setup in the user's Plasma session. A release attaches a
stamped copy as `install.sh`:

```sh
curl -fsSL https://github.com/archledger/plasma-fusion/releases/latest/download/install.sh | sh
curl -fsSL .../install.sh | sh -s -- update        # new packages, then plasma-fusion update
curl -fsSL .../install.sh | sh -s -- uninstall     # plasma-fusion restore, then remove the packages
curl -fsSL .../install.sh | sh -s -- status
curl -fsSL .../install.sh | sh -s -- --dry-run     # every check and the plan; nothing changes
```

Reading it first, with its signature:

```sh
v=v0.2.0
for f in install.sh SHA256SUMS SHA256SUMS.asc; do
  curl -fsSLO "https://github.com/archledger/plasma-fusion/releases/download/$v/$f"
done
gpg --verify SHA256SUMS.asc SHA256SUMS     # key F350 5339 8E3C 80FE 2089 1B82 C10B 8492 BD7F 30C6
sha256sum -c --ignore-missing SHA256SUMS
less install.sh && sh install.sh
```

The key is in the repository as `.github/release-signing-key.asc`; it also signs the release tags.

## Channels

| System (`/etc/os-release`) | Channel | What it runs |
|---|---|---|
| Fedora (a release Copr builds) | Copr `archledger/plasma-fusion` | `sudo dnf copr enable archledger/plasma-fusion fedora-N-x86_64`, `sudo dnf install` the four packages |
| Fedora Atomic (`/run/ostree-booted`) | prints the steps | the Copr repository file, `rpm-ostree install`, reboot |
| RHEL family, other Fedora-likes | refused | no Copr chroot |
| Arch and derivatives (`arch` in `ID`/`ID_LIKE`) | AUR | `yay -S --needed` (or `paru`) the four packages, as the user; without a helper it prints the makepkg steps and stops |
| SteamOS | refused | read-only image |
| Ubuntu (`ID=ubuntu`) on a series the PPA builds (`stonking`, 26.10) | PPA `ppa:archledger/plasma-fusion` | `add-apt-repository`, `apt-get install` the four packages |
| KDE neon (`ID=neon`) | release `.deb`s for neon | the four `~neon1` packages from the release, checked against the signed `SHA256SUMS`, in one `apt-get install` |
| Debian testing or unstable (`forky`, `sid`) | release `.deb`s for Debian testing | the four `~testing1` packages, as for neon |
| another Debian or Ubuntu family system with Plasma 6.7 or later | release `.deb` | the shared part only (`X.Y.Z-1_all`); the compiled parts need a build for that system's KWin |
| NixOS | prints the lines | the flake input and module, or the `fetchGit` import (nixos.md); it never edits `/etc/nixos` |
| anything else | refused | |

The release stamps the lists: `PF_COPR_FEDORA` (Fedora releases), `PF_PPA_SERIES`, `PF_DEB_TARGETS`
(`neon testing`) and `PF_PLASMA_SERIES` (`packaging/tested-plasma.txt`), with
`packaging/stamp-installer.sh`. An unstamped copy (the repository's) refuses to run outside test
mode.

## Checks before anything changes

All of them read only, and all come before the question:

- a release copy; not root (it asks for `sudo` for the package step only); `curl`; x86-64;
- the system and its channel (above);
- Plasma installed, 6.7 or later and in a tested series (`plasma-workspace` from the package
  database; no Plasma program is started). A newer series (6.8, or a 6.8 beta 6.7.90) is refused
  until a release tested with it;
- for install, update and uninstall: a Plasma session (`XDG_CURRENT_DESKTOP` with KDE, a session
  bus), unless `--package-only`; the running KWin (D-Bus `supportInformation`) the same as the
  installed one, otherwise "log out and in first";
- install: Plasma Fusion not installed yet (else "use update"); update: installed; no setup options
  with update (it keeps the user's choices);
- the `.deb` channel: the release's `SHA256SUMS` and its signature, before the plan is shown.

Then it shows the plan with its commands and asks once on the terminal (`--yes` answers; without a
terminal and without `--yes` it stops). `sudo -v` comes before the first change.

## Options and exit codes

| Option | Effect |
|---|---|
| `install` (default), `update`, `uninstall`, `status` | mode |
| `--yes` | no question |
| `--dry-run` | checks and plan only |
| `--package-only` | packages only, no session needed; prints `plasma-fusion setup` for each user |
| `--light`, `--dark`, `--auto`, `--no-auto`, `--keep-layout`, `--keep-shortcuts` | passed to `plasma-fusion setup` |
| `--insecure-no-sig` | release files: HTTPS and SHA256 without the signature |

The same as environment variables: `PLASMA_FUSION_YES=1`, `PLASMA_FUSION_DRY_RUN=1`,
`PLASMA_FUSION_PACKAGE_ONLY=1`, `PLASMA_FUSION_INSECURE_NO_SIG=1`.

Exit codes: 0 done or nothing to do, 1 error, 2 usage, 3 refused (nothing changed), 4 declined.

## Integrity and safety

- Copr and the PPA: dnf and apt check the repositories' signatures. The AUR package builds the git
  tag `vX.Y.Z?signed` with the release key's full fingerprint in `validpgpkeys`.
- Release files: `SHA256SUMS` must carry a signature by the pinned key (embedded in the script,
  imported into a temporary keyring; the user's keyring is never read). A missing signature, a
  signature by another key, an edited `SHA256SUMS` or a file whose checksum differs stops the
  installer before anything is installed.
- No downgrade: a release `.deb` older than the installed package is refused.
- The whole script is one function called on its last line, so a truncated download does nothing.
- It installs no Plasma, writes no package holds and touches no other user's home. Optional next
  steps it prints but never runs: the login screen (`greeter-apply.sh`) and on Fedora the boot
  splash (`plymouth-install.sh`).
- The setup step runs as the user in the session (`plasma-fusion setup`, which backs up first);
  when it stops, the installer names `plasma-fusion restore --latest` and leaves the packages.

## Test mode and tests

With `PLASMA_FUSION_DEV=1` an unstamped copy runs with test values: `PLASMA_FUSION_DEV_VERSION`,
`_SERIES`, `_COPR_FEDORA`, `_PPA_SERIES`, `_DEB_TARGETS`, test channels
(`PLASMA_FUSION_DEV_DNF_REPO` a dnf base URL, `_APT_REPO` an apt line, `_AUR_SRC` a directory with a
PKGBUILD, `_RELEASE_BASE` a release URL), `_ROOT` (a directory with `etc/os-release`) and `_KEY`,
`_KEY_FP` (a test signing key). A stamped copy reads none of these.

`tools/tests/installer/run.sh` runs the installer under dash and bash against fake systems (one
os-release file per system), fake package managers that only log their calls, and a fake release
signed with a throwaway key: every channel and refusal above, the session checks, update and
uninstall, the signature and checksum failures, no downgrade, truncated downloads (seven cut
points) and a stamped copy that must ignore test endpoints in the environment (154 checks,
2026-10-02). The `packages` workflow runs it with ShellCheck, `dash -n` and `busybox sh -n`.

The release-test VMs (docs/RELEASING.md) run it for real on Fedora 44, Arch, Ubuntu 26.10, KDE neon
and Debian testing, with the channels served from the test host.
