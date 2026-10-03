# Part: release tests in virtual machines

Before a release (docs/RELEASING.md, step 2) every channel is installed with the installer on a
fresh system of each supported family, in a real Plasma Wayland session in a virtual machine:
Fedora 44 (Copr), Arch (AUR), Ubuntu 26.10 (PPA), Debian testing and KDE neon (release `.deb`s) and
NixOS (the flake's module). The channels are served from the test machine in place of Copr, the
AUR, Launchpad and GitHub (`scripts/install.sh` test mode, docs/parts/installer.md). The tools are
in `tools/tests/release-vm/`.

## The machine

QEMU with KVM, user networking (the VMs reach the test machine as 10.0.2.2), no root and no
libvirt. `PF_VM_HOME` (default `~/pf-vm`) holds the cloud images (`images/`), the VMs (`vms/NAME/`:
`base.qcow2`, the provisioned system; `run.qcow2`, a test run on top of it) and the results;
`PF_REL` (default `~/pf-rel`) the candidate's packages and the served channels. 4 GB of memory and
4 cores per VM; one VM at a time on a 16 GB machine. Keep a laptop on AC power: a critical battery
suspends the machine and with it the VMs (2026-10-02).

## Steps

```sh
# once per system: the cloud image in $PF_VM_HOME/images, then Plasma into it
tools/tests/release-vm/provision.sh fedora44 fedora44.qcow2 fedora
tools/tests/release-vm/provision.sh arch arch.qcow2 arch
tools/tests/release-vm/provision.sh ubuntu2610 ubuntu2610.img ubuntu
tools/tests/release-vm/provision.sh debian-testing debian-testing.qcow2 debian
tools/tests/release-vm/provision.sh neon noble.img neon
# NixOS: an image with the module, built on a machine with Nix
tools/tests/release-vm/nixos/build-image.sh SRC ~/pf-vm/id_ed25519.pub nixos.qcow2   # then vm.sh create nixos nixos.qcow2

tools/tests/release-vm/build-all.sh [COMMIT]   # every channel's packages, built and checked in containers
tools/tests/release-vm/run-all.sh              # the VM tests, one after another
```

| Script | What |
|---|---|
| `vm.sh` | create, start (base or a fresh run overlay), wait, ssh as `pf` with the test key, QEMU screendump, stop (over ssh, then ACPI) |
| `provision.sh`, `prov-*.sh` | the cloud image with cloud-init (user `pf`, sudo, the test key), Plasma (Fedora: updates and `@kde-desktop-environment`; Arch: `plasma-meta`; Ubuntu and Debian: `kde-plasma-desktop`, on Debian the generic kernel, whose virtio-gpu driver KWin needs; neon: neon's archive and `neon-desktop`), then `prov-common.sh`: getty logs `pf` in on tty1 and `startplasma-wayland` runs there (no display manager, the same on every system) |
| `build-all.sh` | the candidate: `tools/tests/packages/` for Fedora, Arch, Debian testing, Ubuntu 26.10, neon and the shared `.deb`, each built, installed and checked (QML imports and QML parsing included) in a container of its system |
| `channels.sh` | from the candidate: a dnf repository (Copr's place), an apt repository (the PPA's), a release directory with `SHA256SUMS` signed by a throwaway key (never the release key), the Arch source, and the installer, served on 127.0.0.1:8088 |
| `vmtest.sh NAME LANE` | one VM from its base: the stock desktop; the installer's dry run and install in the session (test mode: the channel, and for `.deb`s the snapshot version and the test key); `plasma-fusion status`; a logout (`org.kde.Shutdown.logout`, as the logout dialog) and a new login; the desktop, the launcher and the lock screen; the login check's log and the crashes of this boot; `uninstall`, another new login and the desktop it left; the packages left |
| `run-all.sh` | `channels.sh`, then `vmtest.sh` for each VM |

Results: `$PF_VM_HOME/results/NAME/` (`steps.log`, the installer's output, status, logs and the
screenshots). Things the harness itself shows that are not Plasma Fusion's: on Ubuntu, a logout and
login on the tty session brings Plasma's "control network connections" password prompt in a stock
session too (the session is a tty one, not a display manager's).

## What the tests found (2026-10-02/03)

Each fixed before the final round:

| System | Found | Fix |
|---|---|---|
| Ubuntu 26.10 | KWin aborted during setup's shortcut step and the session ended: setup sent kglobalaccel key sequences with one key code; KF6 reads four, and Ubuntu's libdbus makes the failed check fatal | `fusion-config.sh` sends four (`08a17e6`) |
| Ubuntu 26.10, Debian testing | the dock failed to load: `org.kde.layershell` is a separate package there (`qml6-module-org-kde-layershell`; their `layer-shell-qt` is only the plugin) | Depends per target (`31d059d`); `tools/tests/packages/qml-imports.sh` |
| Debian testing | the clock pill failed to parse: Qt 6.10 reserves `short` | renamed (`7d55dbe`); `tools/tests/packages/qml-parse.sh` |
| Fedora 44 | Xournal++ as a weak dependency pulled in TeX Live, 322 MiB | suggested only (`0117bc2`) |
| every system | `plasma-fusion status` called the app icons layer a hiding per-user copy | `ec7d635` |
| NixOS | setup stopped with "python3 is missing" on a system without a system-wide Python, and the Python tools kept `#!/usr/bin/python3` | the Nix package brings a Python with Pillow and wraps the command and tools (`781b082`) |

The test images needed fixes of their own, not Plasma Fusion's: Debian's cloud kernel has no
virtio-gpu driver (the generic kernel), the NixOS image the QEMU guest profile and
`hardware.graphics.enable` (a display manager would turn it on), and the harness NixOS's wrapped
process names (`.plasmashell-wrapped`).

## Final round

Every channel built from `399fe3e` (Fedora 44, Arch, Debian testing, Ubuntu 26.10, KDE neon and the
shared `.deb`: built, installed, QML imports present, every QML file parsed by the system's Qt, no
lintian or rpmlint error), then the VMs, each from a fresh overlay of its provisioned system:

| System | Plasma | Installer | Setup | New login | Crashes | Uninstall |
|---|---|---|---|---|---|---|
| Fedora 44 | 6.7.5, Qt 6.11.2 | Copr lane (test repository), 27 s | 114 changes | Plasma Fusion desktop, launcher, lock screen; login check "versions=tested lock=tested; no change" | 0 | Fedora's desktop back, no package left |
| Arch | 6.7.5, Qt 6.11.2 | AUR lane, `makepkg -si` in the VM, about 3 min | 114 changes | as Fedora | 0 | as Fedora |
| Ubuntu 26.10 | 6.7.5, Qt 6.11.2 | PPA lane (test apt repository) | 114 changes | as Fedora, full dock | 0 | as Fedora |
| Debian testing | 6.7.4, Qt 6.10.2 | release `.deb` lane, `~testing1` set, signed `SHA256SUMS` | 114 changes | as Fedora, clock pill with date and time | 0 | as Fedora |
| KDE neon (noble) | 6.7.5, Qt 6.11.1 | release `.deb` lane, `~neon1` set | 114 changes | as Fedora | 0 | as Fedora |
| NixOS (unstable, image from `55afc07`) | 6.7.5, Qt 6.11.2 | prints the flake and module lines; the image has the module; `plasma-fusion setup` | 109 changes | as Fedora | 0 | `plasma-fusion restore`: the stock desktop back |

Every system passed (2026-10-03). Evidence: the project ledger's artifacts,
`plasma-fusion/2026-10-02-release/vm-tests/`.
