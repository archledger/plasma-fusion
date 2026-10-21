# Part: release tests in virtual machines

Before a release (docs/RELEASING.md, step 2) every channel is installed with the installer on a
fresh system of each supported family, in a real Plasma Wayland session in a virtual machine:
Fedora 44 (Copr), Arch (AUR), Ubuntu 26.10 (PPA), Debian testing and KDE neon (release `.deb`s) and
NixOS (the flake's module). The channels are served from the test machine in place of Copr, the
AUR, Launchpad and GitHub (`scripts/install.sh` test mode, docs/parts/installer.md). The tools are
in `tools/tests/release-vm/`.

## The machine

QEMU with KVM, user networking (the VMs reach the test machine as 10.0.2.2; IPv4 only, since QEMU's
user network announces an IPv6 route to the guest whether or not the host has one, and connections
over it hang: `PF_VM_IPV6=1` turns it on), no root and no libvirt. `PF_VM_HOME` (default `~/pf-vm`) holds the cloud images (`images/`), the VMs (`vms/NAME/`:
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

tools/tests/release-vm/refresh.sh NAME...      # before a round: each base brought up to date
tools/tests/release-vm/build-all.sh [COMMIT]   # every channel's packages, built and checked in containers
tools/tests/release-vm/run-all.sh              # the VM tests, one after another
# the SDDM login screen on real boots, on the systems whose display manager is SDDM (needs Pillow)
tools/tests/release-vm/run-all.sh debian-testing:deb:sddm ubuntu2610:ppa:sddm arch:aur:sddm fedora44:copr:sddm
# the boot splash on real boots, on every system with an installer lane (needs Pillow)
tools/tests/release-vm/run-all.sh fedora44:copr:splash arch:aur:splash ubuntu2610:ppa:splash debian-testing:deb:splash neon:deb:splash
```

| Script | What |
|---|---|
| `vm.sh` | create, start (base or a fresh run overlay; QEMU's monitor on `mon.sock`, its QMP on `qmp.sock`), wait, ssh as `pf` with the test key, QEMU screendump, stop (over ssh, then ACPI) |
| `provision.sh`, `prov-*.sh` | the cloud image with cloud-init (user `pf`, sudo, the test key), Plasma (Fedora: updates and `@kde-desktop-environment`; Arch: `plasma-meta`; Ubuntu and Debian: `kde-plasma-desktop`, on Debian the generic kernel, whose virtio-gpu driver KWin needs; neon: neon's archive and `neon-desktop`), then `prov-common.sh`: getty logs `pf` in on tty1 and `startplasma-wayland` runs there (no display manager, the same on every system) |
| `build-all.sh` | the candidate: `tools/tests/packages/` for Fedora, Arch, Debian testing, Ubuntu 26.10, neon and the shared `.deb`, each built, installed and checked (QML imports and QML parsing included) in a container of its system |
| `channels.sh` | from the candidate: a dnf repository (Copr's place), an apt repository (the PPA's), a release directory with `SHA256SUMS` signed by a throwaway key (never the release key), the Arch source, and the installer, served on 127.0.0.1:8088 |
| `vmtest.sh NAME LANE` | one VM from its base: KDE bug 524392's workaround for the test user (below); the stock desktop; the installer's dry run and install in the session (test mode: the channel, and for `.deb`s the snapshot version and the test key); `plasma-fusion status`; a logout (`org.kde.Shutdown.logout`, as the logout dialog) and a new login; the desktop, the launcher and the lock screen; `plasma-fusion status` again (a failure fails the run), then copy text's own selection where it lists the copytext part as installed (`check-copytext.sh`); the login check's log and the crashes of this boot; `uninstall`, another new login and the desktop it left; the packages left |
| `check-copytext.sh` | in the session: `Start()` on the bus, then the overlay's "shown in" line in the journal (the user's, or the system journal for the user where there is none), KWin's refusal ("no picture of") or no answer failing; the overlay ended by the PID the bus names, and a pass whose overlay is not found on the bus or cannot be ended failing |
| `sddmtest.sh NAME LANE` | the SDDM login screen on real boots, in one VM from its base: SDDM made the display manager in place of the tty1 login (installed where the base lacks it, with the display server its greeter runs on: Fedora's `sddm-wayland-plasma`, Arch's `xorg-server`, Debian's and Ubuntu's `xserver-xorg-core`) and the test user given a password; the installer as `vmtest.sh` runs it, which must offer the login screen step; a reboot to the system's own greeter (`--check` exits 1; the screenshot must not look like the Login board); `greeter-apply.sh`; a reboot to the Plasma Fusion greeter: SDDM must start it with `--theme /usr/share/sddm/themes/plasmafusion`, no greeter message may name the theme's files (Qt's own components warn without them), and the screenshot must match the Login board (`greeter-compare.py`); the password typed through QEMU's monitor must start a session for the user from SDDM (`loginctl`: `Service=sddm`), whose `plasma-fusion status` names the login screen; no crash; the installer's `uninstall`, which restores the login screen; SDDM's files without the theme; a reboot to the system's own theme again, no crash. Results in `NAME-sddm/` (`steps.log`, the journals of each boot, the screenshots and their comparisons) |
| `greeter-compare.py SHOT` | a greeter screenshot against `design/previews/Login.webp` where the board shows only its background (four regions: mid-left, the sun, the far right, the hills between the session pill and the power buttons), the board scaled and cropped to the screen as the theme fills it: each region's mean colour within 4/255 (`--expect match`) or some region more than 12/255 off (`--expect differ`, another theme). Needs Pillow (on NixOS `nix-shell -p python3Packages.pillow`) |
| `splashtest.sh NAME LANE` | the boot splash on real boots, in one VM from its base: the kernel arguments of a desktop's boot through the system's boot loader (`quiet splash`; `plymouth.ignore-serial-consoles`, since the VMs also log to a serial console and Plymouth then shows only its text splash; `plymouth.debug` for Plymouth's log; Fedora's `grubby`, a drop-in in `/etc/default/grub.d` on Debian, Ubuntu and neon, `/etc/default/grub` on Arch); the installer as `vmtest.sh` runs it, which must offer the boot splash step; a reboot with the system's own splash (installing the package never changes it), which must not look like the Splash board; `plymouth-install.sh --select`, which must select the theme; a reboot with it: one frame must match the board (`splash-capture.py`), Plymouth's log must show a pixel display (not the text splash) and the script plugin; no crash; the installer's `uninstall`, which leaves no theme and the system's theme selected again (on Arch, which had no Plymouth, not Plasma Fusion's); a reboot without the board's look. Each captured boot runs without the tty1 log-in, since Plasma Fusion's log-in splash (KSplash) looks like the board too: the lane sets the base's autologin drop-in aside before the reboot and logs in after the capture, and the desktop must start. Results in `NAME-splash/` (`steps.log`, each boot's command line, Plymouth's log and capture: `frames.tsv`, the closest frame, the first match, the last frame and a sheet of every frame) |
| `splash-capture.py QMP OUT -- CMD` | runs `CMD` (the reboot), waits for QEMU's `RESET` event, then a screendump every 0.3 s for 60 s (`PF_SPLASH_SECONDS` in `splashtest.sh`), only the frames that changed kept in order; each measured against `design/previews/Splash.webp`: the logo's three circles where the theme centres its 1440x900 frame at the scale its script picks, the wallpaper where the script scales it to cover the screen (the sun, a plain area, the lower middle, the top): every region within 6/255 in some frame (`--expect match`) or more than 18/255 off in every frame (`--expect differ`). Needs Pillow |
| `lane-env.sh` | the installer and its test-mode environment for one lane (sourced by `vmtest.sh`, `sddmtest.sh` and `splashtest.sh`) |
| `refresh.sh NAME...` | each base updated the way its system updates itself (Fedora: `dnf upgrade`, with the RPM database verified, and rebuilt if it fails, before the upgrade and after it; Arch: `pacman -Syu`; KDE neon: `apt-get full-upgrade --allow-downgrades`, as neon's updater; Ubuntu, Debian: `apt-get full-upgrade`; on the apt systems `apt-get update --error-on=any`, since without it an index that failed to download is only a warning and the update exits 0; NixOS: nothing), the Plasma versions after; a failed update, or a VM that cannot be stopped after it, fails it |
| `run-all.sh` | `channels.sh`, then `vmtest.sh` for each VM (`sddmtest.sh` for a `NAME:LANE:sddm` entry, `splashtest.sh` for `NAME:LANE:splash`) |

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

## What the 0.6.0 tests found (2026-10-18)

| System | Found | Fix |
|---|---|---|
| KDE neon | The installer's packages, built against neon's Plasma 6.8.0, upgraded KWin and `libplasma6` on a neon still at 6.7.5 and kept `plasma-workspace` 6.7.5. `libplasma6` 6.8.0 replaced the `libPlasmaQuick.so.7` that plasmashell 6.7.5 needs, so plasmashell did not start and the setup stopped. | The installer asks apt for a dry run first and stops when it would upgrade part of Plasma (#81; docs/parts/installer.md). |
| KDE neon (the test VM) | The refresh had left the VM at 6.7.5: plain `apt-get -y full-upgrade` refuses neon's pin downgrades. | `refresh.sh` and `prov-neon.sh` use `--allow-downgrades`, as neon's updater does. |
| Arch, KDE neon | `baloo_file_extractor` aborted in a loop (2514 core dumps in one run, the first before Plasma Fusion was installed) once a file appeared in `~`: KDE bug 524392 (KDE Frameworks 6.31 with Qt 6.12). On a stock Arch VM, one new file in `~` was enough. | Not Plasma Fusion's. `vmtest.sh` applies the bug's workaround for the test user before the installer's copy (`kde-baloo.service` with `QT_QPA_PLATFORM=offscreen`): skipped only where the user manager says the unit is not there (`LoadState` `not-found`), and any other failure fails the run. The crash gate is unchanged. Drop it once the tested frameworks have the fix. |
| Fedora 44 beta (the test VM) | After the refresh, the base's RPM database was malformed ("database disk image is malformed"), and the install failed. | `refresh.sh` verifies the database before the upgrade and after it, and rebuilds it if needed. |
| every system | Copy text's own selection (new in 0.6.0) was checked by a scratch after-login hook only. | `check-copytext.sh` runs in every `vmtest.sh`. It showed on all eight systems in the final round on `b0f7800` (73-128 ms after `Start()`), KWin 6.8.0 included, whose screenshot plugin changed since the beta. |

## What the SDDM lane found (2026-10-21)

The first runs of `sddmtest.sh`, on candidates from #101 (`0f5275b`, then `548c9ee`):

| System | Found | Fix |
|---|---|---|
| Debian testing | `sudo greeter-apply.sh` refused the packaged theme: "cannot be read by SDDM's greeter user". The check runs `find` as that user, `find` goes back to its starting directory, and `sudo` keeps the caller's, a 0700 home that user cannot enter. On every system with private homes (Debian, Fedora), since #98. | The check starts in `/` (#101, `548c9ee`); `greeter-sddm-root.sh` runs every apply from a directory only root may enter. |
| Fedora 44 | No greeter: SDDM logged in KDE's first-run wizard's own user (`plasma-setup`, `/etc/sddm.conf.d/99-plasma-setup.conf`), which runs until `/etc/plasma-setup-done` exists. Fedora's Wayland greeter does not log "Greeter session started successfully" either. | The lane marks the wizard done, as on an installed system, and waits for the greeter's own `Loading .../Main.qml` line, which names the theme it loaded (`embedded` for SDDM's own). |
| Arch | `pacman` timed out against the mirrors: the guest got an IPv6 route from QEMU's user network that goes nowhere on the test machine; with IPv4 only the mirrors still timed out now and then, and pacman has no retries of its own. | `vm.sh` gives the guests IPv4 only; the lane and the AUR lane's preparation (`lane-env.sh`) run pacman up to three times. |

Then all four passed on `548c9ee` (the merged `517bd03`), each from a fresh overlay:

| System | Plasma | SDDM, greeter | Stock theme (differs by) | Plasma Fusion greeter (largest delta) | Login | Restored |
|---|---|---|---|---|---|---|
| Debian testing | 6.7.4 | 0.21.0+git20260819, X11 | `debian-theme` (90.0) | `plasmafusion`, no theme warning (1.0) | Wayland session from SDDM, status "Plasma Fusion" | `debian-theme`, no crash |
| Ubuntu 26.10 | 6.7.5 | 0.21.0+git20251101, X11 | `ubuntu-budgie-login` (237.9) | as Debian (1.0) | as Debian | `ubuntu-budgie-login`, no crash |
| Arch | 6.8.0 | 0.21.0-7, X11 | SDDM's embedded theme (99.9) | as Debian (1.0) | as Debian | embedded, no crash |
| Fedora 44 | 6.7.5 | 0.21.0-13, Wayland (`sddm-wayland-plasma`) | `01-breeze-fedora` (100.7) | as Debian (1.0); no keyboard button on Wayland, as designed | as Debian | `01-breeze-fedora`, no crash |

Evidence: the project ledger's artifacts, `plasma-fusion/2026-10-21-sddm-vm-lane/run3-548c9ee/`.

## What the splash lane found (2026-10-21)

The first runs of `splashtest.sh`, on a candidate from `5ac4240` (the merged #105):

| System | Found | Fix |
|---|---|---|
| every system | Plymouth showed only its text splash: the VMs log to a serial console (`console=ttyS0`), and with a serial console active Plymouth manages the consoles alone, with details forced (`ply-device-manager.c`, `create_devices_from_terminals`, 24.004.60 and 26.134.222). | The lane adds `plymouth.ignore-serial-consoles`, Plymouth's own switch for it, next to `quiet splash`. A desktop has no serial console. |
| every system | Plasma Fusion's log-in splash (KSplash) looks like the Splash board, so a capture running into the session could match without Plymouth. | Each captured boot runs without the tty1 log-in, which follows the capture. |
| Ubuntu 26.10 | The installer failed: unattended-upgrades held dpkg's lock. Its daily run catches up at a random time within the first hour after a boot, and started at the second the installer did; `apt-get` gives up at once, where `apt` waits. | The installer waits for the lock as apt does (#106; docs/parts/installer.md). |
| Ubuntu 26.10 | The boot showed plymouthd's backtrace instead of the splash: Plymouth's script plugin dereferenced a missing console viewer, which it has when no text plugin can be loaded (fixed upstream after 26.134.222), and Ubuntu packs the FreeType one on its own. | `plymouth-install.sh` brings the text plugin where the script plugin needs it (#107; docs/parts/plymouth.md). |
| Arch | `pacman` timed out against the mirrors while `plymouth-install.sh` installed Plymouth. | The lane downloads Plymouth into pacman's cache first, three tries; the installer's own `pacman -S` installs it from there. |
| KDE neon | The installer's apt dry run failed ("held broken packages"): the base was at Plasma 6.7, the candidate built against neon's 6.8.1. | `refresh.sh neon` before the round, as the steps say. |

Then a final round on main at `f1c0597` (#106 and #107 merged): every channel built again, the
candidate's own installer served, no change by hand. All five pass, with no crash on any boot:

| System | Stock boot | After `--select` | After the uninstall | Kept by the uninstall |
|---|---|---|---|---|
| Fedora 44 | `bgrt`, differs (219.1) | matches (3.6) | `bgrt`, differs (214.5) | `plymouth-plugin-script` |
| Arch | no splash, differs (254.9) | matches (3.6) | `bgrt`, differs (219.1) | `plymouth` |
| Debian testing | `ceratopsian`, differs (205.0) | matches (3.6) | `ceratopsian`, differs (205.0) | nothing installed |
| Ubuntu 26.10 | no splash, differs (218.8) | matches (3.6) | no splash, differs (232.2) | `plymouth-label-ft` |
| KDE neon | `breeze`, differs (240.4) | matches (3.6) | `breeze`, differs (233.3) | nothing installed |

The figures are the closest frame's largest region delta (a match needs 6 or less, a difference
more than 18). Arch shows `bgrt` after the uninstall because the Plymouth the splash installer
added stays and then runs from the installed system; `plymouth-uninstall.sh --remove-plugin`
removes it. Debian's `plymouth-label` holds both text plugins and was already installed.

How long the splash shows in the VMs (Plymouth's log, from the pixel display added to removed, on
the boot after `--select`; the first round, then the final): Arch 9.4 and 9.7 s and KDE neon 6.1
and 5.3 s, from 1.5 to 2.1 s into the boot, in the initramfs; Debian testing 1.5 s and Ubuntu 26.10
1.4 s both times, the display coming only after the switch to the installed system (from 5.5 s).
Fedora 44 varies: 2.1 s with the display after the switch, then 4.5 s with it in the initramfs from
2.4 s; two of its six captured boots had it there. The lane takes a frame every 0.3 s: two or more
matched the board on each (after the fade-in).

Evidence: the project ledger's artifacts, `plasma-fusion/2026-10-21-splash-vm-lane/`
(`candidate-5ac4240/` and `final-f1c0597/`).

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
