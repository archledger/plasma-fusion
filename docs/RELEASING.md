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
source packages. Then (owner):

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
   archledger/plasma-fusion`; Fedora 44 and 45 must succeed; rawhide is informational).
3. **AUR** (owner pushes): a fresh clone of `ssh://aur@aur.archlinux.org/plasma-fusion.git`, copy
   `packaging/arch/PKGBUILD` (it builds the signed tag; the pacman hook comes from the source), run
   `makepkg --printsrcinfo > .SRCINFO` and `makepkg` once, commit "plasma-fusion X.Y.Z" and push.
   Check the package page and the RPC (it lags by minutes).
4. **PPA** (owner signs): `debsign -k F35053398E3C80FE20891B82C10B8492BD7F30C6 ppa/*_source.changes`,
   then `dput ppa:archledger/plasma-fusion ppa/<file>_source.changes`. The lane is done when
   Launchpad shows the amd64 build published for each series (a build failure leaves users on the
   old version).
5. **NixOS**: nothing to build; the flake and the module are in the tag. Users move their input or
   `fetchGit` pin.
6. Ledger: the release, every channel's result and the evidence.

## 6. After a KWin update in a distribution

The navigation effect (and on Arch the decoration) is built against one KWin. Until it is rebuilt,
the login check keeps it off and `plasma-fusion status` says so.

- Copr: rebuild the last release's SRPM (`copr-cli build-package archledger/plasma-fusion --name
  plasma-fusion`).
- AUR: users rebuild (the pacman hook tells them); nothing to publish.
- PPA and the release `.deb`s: a new upload or release `X.Y.Z-0ppa2~series1` / `X.Y.Z-2~target1`
  built against the new KWin.

A new Plasma series (6.8) needs a Plasma Fusion release that lists it in `tested-plasma.txt`; the
installer refuses an untested series, and the login check keeps the version-bound parts off on it.
