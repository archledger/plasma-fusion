# Part: installer

`scripts/install.sh`: one command that detects the system, installs the Plasma Fusion packages
through its channel and runs the per-user setup in the user's Plasma session. A release attaches a
stamped copy as `install.sh`:

```sh
curl -fsSL https://github.com/archledger/plasma-fusion/releases/latest/download/install.sh | sh
curl -fsSL .../install.sh | sh -s -- update        # new packages, then plasma-fusion update
curl -fsSL .../install.sh | sh -s -- uninstall     # plasma-fusion restore, the login screen and
                                                   # boot splash looks, then remove the packages
curl -fsSL .../install.sh | sh -s -- status
curl -fsSL .../install.sh | sh -s -- --dry-run     # every check and the plan; nothing changes
curl -fsSL .../install.sh | sh -s -- --full        # Fedora: the full profile (the pinned KWin
                                                   # fork, ADR 0001) — see "The full profile"
curl -fsSL .../install.sh | sh -s -- --full-restore # back to stock KWin; the six packages stay
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
| Fedora (a release Copr builds) | Copr `archledger/plasma-fusion` | `sudo dnf copr enable archledger/plasma-fusion fedora-N-x86_64`, `sudo dnf install` the six packages |
| Fedora Atomic (`/run/ostree-booted`) | prints the steps | the Copr repository file, `rpm-ostree install`, reboot |
| RHEL family, other Fedora-likes | refused | no Copr chroot |
| Arch and derivatives (`arch` in `ID`/`ID_LIKE`) | AUR | `yay -S --needed` (or `paru`) the six packages, as the user; without a helper it prints the makepkg steps and stops |
| SteamOS | refused | read-only image |
| Ubuntu (`ID=ubuntu`) on a series the PPA builds (`stonking`, 26.10) | PPA `ppa:archledger/plasma-fusion` | `add-apt-repository`, `apt-get install` the six packages |
| KDE neon (`ID=neon`) | release `.deb`s for neon | the six `~neon1` packages from the release, checked against the signed `SHA256SUMS`, in one `apt-get install` |
| Debian testing or unstable (`forky`, `sid`) | release `.deb`s for Debian testing | the six `~testing1` packages, as for neon |
| another Debian or Ubuntu family system with Plasma 6.7 or later | release `.deb` | the shared part only (`X.Y.Z-1_all`); the compiled parts need a build for that system's KWin |
| NixOS | prints the lines | the flake input and module, or the `fetchGit` import (nixos.md); it never edits `/etc/nixos` |
| anything else | refused | |

`update` upgrades the packages that are installed and installs those a later release added (Quick
Look and copy text's selection came after 0.5.0): dnf refuses to upgrade a package that is not
installed, and apt's `--only-upgrade` skips it, so on Copr and the PPA the new ones are installed
apart; the AUR and the release `.deb`s install the whole set either way.

The release stamps the lists: `PF_COPR_FEDORA` (Fedora releases), `PF_PPA_SERIES`, `PF_DEB_TARGETS`
(`neon testing`), `PF_PLASMA_SERIES` (`packaging/tested-plasma.txt`) and `PF_FULL_FEDORA` (the
Fedora releases the full profile builds; empty until the full Copr project goes live, and then
`--full` refuses), with `packaging/stamp-installer.sh` (`--full-fedora`). An unstamped copy (the
repository's) refuses to run outside test mode.

## The full profile (`--full`, `--full-restore`)

[ADR 0001](../adr/0001-two-profile-distribution.md): the full profile replaces the stock KWin with
the maintained fork through a **separate Copr repository** (`archledger/plasma-fusion-full`), so a
stock user can never be offered a KWin replacement. It is Fedora's Copr channel only, and only on a
release that stamps `PF_FULL_FEDORA` for that Fedora release; anything else is refused with exit 3
before anything changes (the other channels and Fedora Atomic keep the stock profile). The plan
states the fork's honest limit: KWin security fixes arrive on the fork's weekly integration
cadence, which can lag Fedora by days.

`--full` (an install choice; a plain stock install never gets near the fork):

1. refuses to take over a KWin the user already pins themselves (`dnf versionlock` holding
   `kwin`, `kwin-common` or `kwin-libs`): dnf's `versionlock delete` works by name only, so a
   pre-existing entry could not be given back at restore time — nothing has changed at that
   point;
2. records the installed stock KWin EVRs (`kwin`, `kwin-common`, `kwin-libs`) to
   `/var/lib/plasma-fusion/full-restore.txt`;
3. enables `archledger/plasma-fusion-full` and installs `plasma-fusion-full` — the metapackage
   whose exact-EVR requires pull the six packages and the pinned fork in one transaction;
4. locks the KWin set (`dnf versionlock add kwin kwin-common kwin-libs`; dnf5 pins each package at
   its just-installed version), so a distribution update can never half-upgrade the set;
5. runs the unchanged per-user setup. On a stock install it switches only the compositor: no setup
   rerun (a `plasma-fusion update` runs only if the transaction moved the packages).

Already on the full profile, `--full` says so and does nothing. A fork KWin without the metapackage
(an unsupported manual state) is refused with the way back to stock.

`update` on a full system moves the pin with the metapackage in one transaction (ADR 0001's
within-series path): the version lock goes first — it would hold KWin at the old fork while the
new metapackage requires the new one — the upgrade takes the six with `plasma-fusion-full`, and
the lock comes back at the newly installed fork.

`--full-restore` (no stamp needed — a system on the full profile must always get back, including
on a Fedora release the release's stamp does not carry, where the stock lanes stay refused):
removes the version lock, the metapackage (with `--no-autoremove`: on a fresh `--full` the six
came in as its dependencies, and dnf's `clean_requirements_on_remove` default would take them
with it — the restore promises they stay) and the repository, then `dnf distro-sync`s the KWin
set **to the recorded EVRs** — the machine returns to the stock KWin it had, not to whatever the
repositories offer now. Fedora keeps only a package's newest build, so a stock that advanced
while the machine was on the fork can no longer be reinstalled: the fallback says so out loud
and takes the current stock — but only after verifying the recorded EVRs are really gone
(`dnf -q repoquery`); a transient repository or solver failure stops instead of quietly
becoming that fallback. The record's directory, `/var/lib/plasma-fusion`, can be root's alone:
`greeter-apply.sh` keeps the login screen's backups there and makes it `0700`, before `--full`
or after it. The installer runs as the user, so the restore reads the record through sudo
where the user cannot, and the plan, which asks for nothing, says "the recorded versions, which
sudo reads" in place of the versions (found on the ThinkPad, where a plain read had found
nothing and the restore had gone by the names alone). The record is read first, before the lock
goes: where it may be there and sudo cannot say (a sudo policy that names its commands and has
neither `test` nor `cat`), the restore stops with nothing changed, instead of taking the failed
read for "no record". A directory that only root can enter and that holds no record is "no
record", once sudo has looked. The restore then **verifies the distag is gone** — a repository
left enabled would win the sync, so the check catches it and says what to do. The six Plasma
Fusion packages stay installed; they run on stock KWin. `uninstall` on a full system (also
usable outside the stamp and through the Plasma-version gate, for the same reason: its job is
to return KWin to stock) runs the same restore first, then the normal uninstall.
The installer's `status` reports the profile (`full` with the pinned
KWin, or `stock`); the packaged
`plasma-fusion status` learns the profile with the capability reporting that follows the channel.

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
- `--full`: Fedora's Copr channel, a release that stamps the full build (`PF_FULL_FEDORA`), not
  already on the full profile, and no fork KWin without the metapackage; `--full-restore` needs no
  session (it runs no per-user step) and is nothing to do without the full profile;
- the `.deb` channel: the release's `SHA256SUMS` and its signature, then its `.deb` files
  (downloaded into a temporary directory, each against its sum), no downgrade, and apt's dry run of
  their install (below), all before the plan is shown, so `--dry-run` runs them too.

Then it shows the plan with its commands and asks once on the terminal (`--yes` answers; without a
terminal and without `--yes` it stops). `sudo -v` comes before the first change.

On the apt channels apt is first asked for a dry run of the install (`apt-get -s install`): for the
release `.deb`s before the plan (above), on the PPA in the package step, after the PPA is added and
`apt-get update` (the dry run cannot see the PPA before). If that would upgrade part of Plasma with
it (KWin, libplasma, `plasma-workspace`, `plasma-desktop`), the system is behind the release's
packages, which were built against a newer Plasma, and apt would leave Plasma half updated: on KDE
neon still at Plasma 6.7.5, the 6.8.0 packages took `libplasma6` 6.8.0 along, which replaced the
`libPlasmaQuick.so.7` that plasmashell 6.7.5 needs, and plasmashell no longer started (release test,
2026-10-18). The installer then stops with what apt would upgrade and says to update the system
first (KDE neon: `sudo pkcon update` or Discover; Debian and Ubuntu: `sudo apt full-upgrade`) and
log out and in; nothing is installed (on the PPA, the PPA stays added). The same goes for `update`
on the PPA. A dry run that fails stops the installer as well (exit 1, with apt's last lines): its
answer would be unknown.

The package steps wait while another package manager holds dpkg's lock (`-o
DPkg::Lock::Timeout=600`, up to 10 minutes; apt says what it waits for). `apt-get` gives up at once
by default, where `apt` itself waits (without end on a terminal, else 120 s;
`apt-private/private-cmndline.cc`), and unattended-upgrades holds the lock while it runs: its daily
run catches up at a random time within the first hour after a boot. In the release VMs it started on
Ubuntu 26.10 two minutes after boot, at the second the installer did, and the install failed ("Could
not get lock /var/lib/dpkg/lock-frontend. It is held by process 2969 (unattended-upgr)", 2026-10-21).
`apt-get update` cannot wait that way: the package lists' lock is not dpkg's (`pkgAcquire::GetLock`
takes it without a timeout), and another update (apt's daily one, Discover's) holds it for a while,
so it is tried three times, 15 s apart. The boot splash tools wait for dpkg's lock the same way.

## Options and exit codes

| Option | Effect |
|---|---|
| `install` (default), `update`, `uninstall`, `status` | mode |
| `--full` | with install: the full profile (Fedora only, stamped per release; above) |
| `--full-restore` | back to stock KWin; the six packages stay (Fedora; above) |
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
  steps it prints but never runs: the login screen (`greeter-apply.sh`, only where
  plasma-login-manager or SDDM's Qt 6 greeter is installed) and the boot splash
  (`plymouth-install.sh --select`, on Fedora, Arch, Debian, Ubuntu and KDE neon; not on NixOS,
  whose module has the option, or Fedora Atomic).
- Uninstall undoes those two first, when they were applied, because the greeter would otherwise
  point at the removed Global Theme and wallpaper: `greeter-restore.sh` when the greeter carries
  greeter-apply.sh's look (its marked block or a greeter wallpaper from Plasma Fusion's backgrounds in
  `/etc/plasmalogin.conf`, or Plasma Fusion's Global Theme in the greeter user's `kdeglobals`), and
  `greeter-restore.sh --greeter sddm` while SDDM's `kde_settings.conf` still chooses Plasma Fusion's
  theme or cursors (read as SDDM reads it, comments cut off; or the theme has a `theme.conf.user`)
  and an SDDM backup exists; each greeter is
  restored on its own, so the other's later settings stay. A theme choice the restore keeps (made by
  hand, or in a file greeter-apply.sh does not write) is named in a note; SDDM falls back to its
  built-in theme once the package is gone, so the uninstall goes on. `plymouth-uninstall.sh` when
  Plymouth's themes hold `plasma-fusion`, with `--remove-plugin`: the packages the splash installer
  added go too where no other installed package needs them (its help says when it checks that; one
   from 0.6.0 or before removes them unchecked, so the installer keeps them there). Pending splash
   state also triggers cleanup when a previous attempt removed the theme files but failed to remove
   the packages. That state is checked with sudo after confirmation because the greeter can make
   its parent directory private. If any helper stops, the Plasma Fusion packages stay installed.
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
uninstall (with the login screen and boot splash undone first), the signature and checksum failures,
no downgrade, truncated downloads (seven cut points) and a stamped copy that must ignore test
endpoints in the environment (154 checks, 2026-10-02; 8 more for the uninstall and the optional
steps, 2026-10-11; 208 in all on 2026-10-18, with the six packages and an update from a release
before Quick Look and copy text, whose fake dnf refuses to upgrade a package that is not installed,
as dnf5 does; 236 with the apt dry run, whose fake apt-get -s prints a set simulation or fails: neon
(also with `--dry-run`), the PPA and a PPA update behind the release's Plasma refused, a failed dry
run stopping it, an install that upgrades nothing of Plasma let through; 268 with the lock wait on
every apt install and remove and `apt-get update` tried again, 2026-10-21). The `packages` workflow
runs it with ShellCheck, `dash -n` and `busybox sh -n`.

The release-test VMs (docs/RELEASING.md) run it for real on Fedora 44, Arch, Ubuntu 26.10, KDE neon
and Debian testing, with the channels served from the test host.
