# Releasing Plasma Fusion

One version (`VERSION`), one signed tag `vX.Y.Z`, one source tarball; every channel builds the same
six packages from it (docs/parts/system.md). Steps marked **owner** need the release key or an
account; the rest can be done by a maintainer or an agent and are recorded in the project ledger.

The release key: F350 5339 8E3C 80FE 2089 1B82 C10B 8492 BD7F 30C6 (ed25519, expires 2028-07-02;
`.github/release-signing-key.asc`). It signs the tag, `SHA256SUMS` and the PPA uploads, and is the
key in the AUR package's `validpgpkeys` and the installer.

## 1. Prepare (pull request)

1. `VERSION`, the spec's `Version:`, the PKGBUILD's `pkgver=` and a new top entry in
   `packaging/debian/changelog` say X.Y.Z (`packaging/check-version.sh`); the spec gets a
   `%changelog` entry.
2. `packaging/tested-plasma.txt` lists every Plasma series this version was tested with, and
   `packaging/tested-versions.txt` the exact versions.
3. `CHANGELOG.md`: the new version on top (newest first), with the tested Plasma series, the
   supported and refused systems, and "Thanks to @user" for outside reporters and contributors.
4. The `build`, `compiled` and `packages` workflows are green on the pull request.
5. A release with the full profile ([full-profile.md](full-profile.md)) pins one fork tag. A new
   tag is built first, from archledger/kwin in the fork's CI image:
   `SRPM=1 packaging/fedora/build-fork-rpm.sh v<upstream>-pf<N> OUT`, and the same source
   package goes to the candidates project and to the live one:
   `copr-cli build archledger/plasma-fusion-full-candidates OUT/SRPMS/kwin-*.src.rpm`, then the
   same with `archledger/plasma-fusion-full`. Plasma Fusion's `--with full` build compiles
   against its project's own KWin: it requires the fork's `kwin-devel` at exactly the pin (not
   `cmake(KWin)`, which would take Fedora's once Fedora's KWin is newer than the pin, #191), so
   each project needs the tag before a candidate or the release is built in it. In the live
   project the new KWin waits: the current metapackage requires the old pin exactly, and the
   version lock holds every full-profile machine at the old one. The spec's `%global kwin_full_pin`
   is the builds' exact EVR (the same in both projects: `6.8.2-3.fc44.pf5`);
   `packaging/check-version.sh` checks its shape and `packaging/check-full-profile.sh` the
   gates with it. Both need `rpmspec`: run them in a Fedora container.

## 2. Test the candidate (before the tag)

On the merged commit, build every channel and install it with the installer in a virtual machine
of each system, in a real Plasma session: Fedora 44, Arch, Ubuntu 26.10, Debian testing, KDE neon
and NixOS (`tools/tests/release-vm/refresh.sh` for each VM first, then `build-all.sh` and
`run-all.sh`; docs/parts/release-tests.md). Per system: the installer's plan and run, `plasma-fusion
status`, a new login (the desktop, the launcher and the lock screen), copy text's own selection
shown, the login check's log, no crash, then `uninstall` and a new login with the previous desktop.
Then the SDDM login screen on real boots of the systems whose display manager is SDDM (`run-all.sh
debian-testing:deb:sddm ubuntu2610:ppa:sddm arch:aur:sddm fedora44:copr:sddm`, with Pillow): the
system's own greeter, `greeter-apply.sh`, the Plasma Fusion greeter compared with the Login board, a
login typed into it, `uninstall` and the system's own greeter again. And the boot splash on real
boots of every system with an installer lane (`run-all.sh fedora44:copr:splash arch:aur:splash
ubuntu2610:ppa:splash debian-testing:deb:splash neon:deb:splash`, with Pillow): the system's own
splash, `plymouth-install.sh --select`, the boot captured from the reset on and compared with the
Splash board, `uninstall` and the system's own splash again.
Every system must pass; the evidence goes to the ledger's artifacts.

With a pin, the full profile too, in the candidates project
(`archledger/plasma-fusion-full-candidates`, unlisted, test builds only). The live project has
users, and a candidate there would reach them: its version sorts above the last release.
- A candidate of the release branch goes to the candidates project: `packaging/build-rpm.sh`'s
  source package, then `copr-cli build archledger/plasma-fusion-full-candidates`. Its version,
  `X.Y.Z~N.gitHASH`, sorts above every earlier snapshot and below the release.
- `PF_FULL_REPO=archledger/plasma-fusion-full-candidates tools/tests/release-vm/fulltest.sh
  fedora44lane fresh` and `... switch` run against it (docs/parts/release-tests.md): the
  installer they stamp enables that project, and the lane checks that it is the one enabled.
- So does the update from the previous pin: a VM with the last release's full profile (the
  published installer, from the live project) moves to the candidates project
  (`sudo dnf copr remove archledger/plasma-fusion-full`, then
  `sudo dnf copr enable archledger/plasma-fusion-full-candidates fedora-44-x86_64`) and updates
  with the candidate's `install.sh update`. That must be one dnf transaction (the KWin packages,
  the metapackage and the six packages together), ending with the version lock at the new pin:
  ADR 0001's security-cadence round.

Then the depth features' check on the merged commit's HOME tree, on the test host and on the
Plasma beta container (`tools/tests/depth/run.sh`, docs/parts/testing.md "Depth features"): window
placement memory, snap groups, dynamic workspaces, copy text, Quick Look and live chips, each
feature's session scenario. Every feature must pass; its summary goes with the evidence.

## 3. Tag (owner)

```sh
git tag -s vX.Y.Z -m "Plasma Fusion X.Y.Z"     # at the release key's pinentry
git push origin vX.Y.Z
```

Only `vX.Y.Z` tags: Packit takes the newest tag matching `v\d+\.\d+\.\d+$` as the version.

## 4. Release files

```sh
git checkout vX.Y.Z
packaging/release-assets.sh vX.Y.Z build/release-X.Y.Z
```

It checks the tag's signature, VERSION and a clean tree, then builds `plasma-fusion-X.Y.Z.tar.gz`,
the stamped `install.sh`, the neon and Debian testing `.deb` sets and the shared `.deb`
(`X.Y.Z-1_all`), each installed and checked in its container, and `SHA256SUMS`; and the unsigned PPA
source packages. With a pin in the spec, `install.sh` is stamped with the pin's Fedora release
(`--full-fedora`; `PF_FULL_FEDORA` overrides it), which turns on `--full`. Then (owner):

```sh
cd build/release-X.Y.Z/release
gpg -u 'F35053398E3C80FE20891B82C10B8492BD7F30C6!' --armor --detach-sign -o SHA256SUMS.asc SHA256SUMS
```

Create a **draft** GitHub release for the tag with every file in `release/` and the notes from
`CHANGELOG.md` (tested Plasma, systems, install line, how to verify, known limits). Check the draft:
download each asset, `gpg --verify SHA256SUMS.asc SHA256SUMS`, `sha256sum -c SHA256SUMS`, and run
the installer from the draft's URL with `--dry-run` on one system.

## 5. Publish (owner), then the channels

1. Publish the release. `releases/latest/download/install.sh` now serves the new installer.
2. **Copr** (Packit, on the release): read each chroot's result back (`copr-cli list-builds
   archledger/plasma-fusion`; Fedora 44 and 45 must succeed; rawhide is informational). Packit
   can miss a release (it missed 0.8.0, while its service was down): when no build of the tag
   has started a few minutes after publishing, build the source package at the tag in a Fedora
   container (`packaging/build-rpm.sh --topdir DIR`) and submit it by hand:
   `copr-cli build archledger/plasma-fusion DIR/SRPMS/plasma-fusion-X.Y.Z-1.fc44.src.rpm`.
3. **Copr, full profile** (with a pin): the release's source package is built in
   `archledger/plasma-fusion-full` as well, which builds `--with full` and so adds the
   metapackage: `copr-cli build archledger/plasma-fusion-full plasma-fusion-X.Y.Z-1.fc44.src.rpm`
   (the source package of Packit's build, or `packaging/build-rpm.sh` at the tag). Its packages'
   release carries `.full` (`X.Y.Z-1.fc44.full`, from either source package: the suffix is in the
   dist tag), so they sort above the stock project's builds of the same version and a machine
   that switches profiles takes them (#197). Read the result
   back; fedora-44 must succeed. A full-profile machine then updates with `install.sh update`.
4. **The fork's release** (with a new fork tag; owner): a GitHub release of archledger/kwin for
   the tag (`Plasma Fusion KWin v<upstream>-pf<N>`), with notes and no files: the fork's only
   channel is the full project (ADR 0001). The notes name the KWin package's EVR and the Plasma
   Fusion release that pins it, what the tag adds to KDE's release, how to get it (the installer's
   `--full`), the security cadence and how to verify the signed tag. Then read the full project's
   page back: unlisted, with instructions (the install line, the Fedora releases) that still hold
   for the release; change them with `copr-cli modify --instructions` (copr-cli has no homepage
   option: python-copr's `project_proxy.edit` sets that).
5. **AUR** (owner pushes): a fresh clone of `ssh://aur@aur.archlinux.org/plasma-fusion.git`, copy
   `packaging/arch/PKGBUILD` (it builds the signed tag; the pacman hook comes from the source), run
   `makepkg --printsrcinfo > .SRCINFO` and `makepkg` once, commit "plasma-fusion X.Y.Z" and push.
   Check the package page and the RPC (it lags by minutes).
6. **PPA** (owner signs): `debsign -k F35053398E3C80FE20891B82C10B8492BD7F30C6 ppa/*_source.changes`,
   then `dput ppa:archledger/plasma-fusion ppa/<file>_source.changes`. The lane is done when
   Launchpad shows the amd64 build published for each series (a build failure leaves users on the
   old version).
7. **NixOS**: nothing to build; the flake and the module are in the tag. Users move their input or
   `fetchGit` pin.
8. Ledger: the release, every channel's result and the evidence.

## 6. After a KWin update in a distribution

The navigation effect (and on Arch the decoration) is built against one KWin. Until it is rebuilt,
the login check keeps it off and `plasma-fusion status` says so.

- Copr (`archledger/plasma-fusion`): the last release's source package again with its release
  raised, built once the new KWin is in Fedora's stable updates (the build root takes it from
  there; a fresh Fedora container's `dnf repoquery kwin-devel` shows it). The release must be
  higher: dnf moves an installed package only to a newer version-release, so `X.Y.Z-1` built again
  would reach new installs only. `copr-cli build-package` does not do this: it builds the
  package's default source, and for these uploaded packages that is the first upload's temporary
  link (0.2.0's, gone: 404 on 2026-11-15). In a Fedora container:
  1. The release's source package: its build is the newest `plasma-fusion` in
     `copr-cli list-builds archledger/plasma-fusion`, and
     `curl -s https://copr.fedorainfracloud.org/api_3/build/BUILD` names it in
     `source_package.url` (`.../srpm-builds/BUILD/plasma-fusion-X.Y.Z-N.fc44.src.rpm`). Download it
     and check it with `rpm -K`.
  2. `rpm -i --define "_topdir $PWD/top" plasma-fusion-X.Y.Z-N.fc44.src.rpm`, then (rpmdevtools)
     `rpmdev-bumpspec -c "Rebuilt against KWin A.B.C" -u "NAME <EMAIL>" SPEC`, where SPEC is
     `top/SPECS/plasma-fusion.spec`: the release becomes N+1 with a changelog entry, and the
     sources stay the release's.
  3. `rpmbuild -bs --define "_topdir $PWD/top" top/SPECS/plasma-fusion.spec`.
  4. (owner) `copr-cli build archledger/plasma-fusion top/SRPMS/plasma-fusion-*.src.rpm` (every
     chroot, as for a release), then read each chroot's result back. On an updated machine,
     `plasma-fusion status` lists the navigation part as built against the new KWin, without a
     note to rebuild it.

  The full project (`archledger/plasma-fusion-full`) needs no rebuild: its KWin is the pinned
  fork, which a distribution's update does not move.
- AUR: users rebuild (the pacman hook tells them); nothing to publish.
- PPA and the release `.deb`s: a new upload or release `X.Y.Z-0ppa2~series1` / `X.Y.Z-2~target1`
  built against the new KWin.

A new Plasma series (6.8) needs a Plasma Fusion release that lists it in `tested-plasma.txt`; the
installer refuses an untested series, and the login check keeps the version-bound parts off on it.
