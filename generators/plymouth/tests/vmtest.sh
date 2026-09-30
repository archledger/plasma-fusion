#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plymouth theme test in a throw-away QEMU/KVM VM, on the test device, as a normal user. The VM
# boots the host's own running kernel with an initramfs built by dracut (crypt + plymouth, the
# installed theme selected through PLYMOUTH_THEME_NAME, which only changes the copy of
# plymouthd.conf inside that initramfs) and a small raw disk holding a LUKS2 container in a GPT
# partition named "Internal drive". Nothing on the host is changed.
#
#   vmtest.sh WORK setup                 disk images and the base initramfs (needs the theme in
#                                        /usr/share/plymouth/themes/plasma-fusion and
#                                        plymouth-plugin-script installed)
#   vmtest.sh WORK overlay THEME_DIR     initrd-test.img = base + a cpio with THEME_DIR's files
#                                        (for quick iterations) + the self-test unit
#   vmtest.sh WORK run NAME SCENARIO SIZE [base|test] [disk|bare] [bios|uefi]
#                                        boot and run a vmrun.py scenario; results in WORK/out/NAME
#                                        (uefi: OVMF, so plymouth starts on simpledrm;
#                                        PF_SECOND_HEAD=WxH adds a second display)
#   vmtest.sh WORK clean                 delete everything but WORK/out
#
# The LUKS passphrase is "fusion-test" (pbkdf2, 1000 iterations: the VM unlocks at once).
set -euo pipefail

WORK=${1:?work dir}
CMD=${2:?command}
shift 2
HERE=$(cd "$(dirname "$0")" && pwd)
KVER=$(uname -r)
mkdir -p "$WORK/out"
cd "$WORK"

luks_uuid() { cryptsetup luksUUID "$1"; }

case $CMD in
setup)
  # Disk 1: GPT, one partition "Internal drive" with the LUKS2 container.
  rm -f luks.img disk.img bare.img
  truncate -s 32M luks.img
  printf '%s' fusion-test | cryptsetup luksFormat --batch-mode --type luks2 --pbkdf pbkdf2 \
    --pbkdf-force-iterations 1000 --label pf-test --key-file - luks.img
  truncate -s 40M disk.img
  printf 'label: gpt\nstart=2048, size=65536, type=linux, name="Internal drive"\n' | sfdisk -q disk.img
  dd if=luks.img of=disk.img bs=1M seek=1 conv=notrunc status=none
  # Disk 2: the container on the whole (virtio) disk: no partition name, no model.
  cp luks.img bare.img
  luks_uuid luks.img > luks.uuid
  echo "LUKS UUID $(cat luks.uuid)"
  # Base initramfs of the running kernel. --no-hostonly with an explicit module list; the big
  # GPU drivers are left out (the VM has a bochs VGA).
  mkdir -p tmp
  PLYMOUTH_THEME_NAME=plasma-fusion nice -n 10 dracut --force --no-hostonly --no-hostonly-cmdline \
    --no-early-microcode --tmpdir "$WORK/tmp" \
    -m "bash systemd systemd-initrd systemd-udevd systemd-journald systemd-tmpfiles systemd-sysctl systemd-modules-load systemd-ask-password systemd-cryptsetup dracut-systemd kernel-modules base fs-lib rootfs-block udev-rules crypt dm drm plymouth" \
    --omit-drivers "amdgpu radeon nouveau i915 xe" \
    --kver "$KVER" "$WORK/initrd-base.img" 2> "$WORK/out/dracut.log" || { tail -20 "$WORK/out/dracut.log"; exit 1; }
  ls -la initrd-base.img
  lsinitrd initrd-base.img > out/lsinitrd-base.txt 2>/dev/null || true
  grep -E "plymouth/(script|two-step)\.so|themes/plasma-fusion/plasma-fusion\.(script|plymouth)|plymouthd\.conf|systemd-cryptsetup" \
    out/lsinitrd-base.txt | sed 's/^.* \//\//' || true
  ;;
overlay)
  THEME=${1:?theme dir}
  rm -rf ov initrd-test.img
  mkdir -p ov/usr/share/plymouth/themes/plasma-fusion ov/etc/systemd/system/initrd.target.wants ov/usr/bin
  cp "$THEME"/* ov/usr/share/plymouth/themes/plasma-fusion/
  # The installed copy carries the keyboard label; keep it in the overlay too.
  if grep -q '^PFKeyboardLayout=' /usr/share/plymouth/themes/plasma-fusion/plasma-fusion.plymouth 2>/dev/null; then
    lbl=$(sed -n 's/^PFKeyboardLayout=//p' /usr/share/plymouth/themes/plasma-fusion/plasma-fusion.plymouth | head -1)
    sed -i "/^\[script-env-vars\]/a PFKeyboardLayout=$lbl" ov/usr/share/plymouth/themes/plasma-fusion/plasma-fusion.plymouth
  fi
  install -m 0755 "$HERE/selftest/pf-selftest.sh" ov/usr/bin/pf-selftest.sh
  install -m 0644 "$HERE/selftest/pf-selftest.service" ov/etc/systemd/system/pf-selftest.service
  ln -s ../pf-selftest.service ov/etc/systemd/system/initrd.target.wants/pf-selftest.service
  (cd ov && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet) > overlay.cpio
  # The kernel reads an uncompressed cpio that follows another archive only at a 4-byte
  # aligned offset: pad the base image with zeros first.
  cp initrd-base.img initrd-test.img
  size=$(stat -c %s initrd-test.img)
  truncate -s $(( (size + 511) / 512 * 512 )) initrd-test.img
  cat overlay.cpio >> initrd-test.img
  ls -la initrd-test.img
  ;;
run)
  NAME=${1:?name}; SCEN=${2:?scenario}; SIZE=${3:-1920x1200}; WHICH=${4:-base}; DISK=${5:-disk}; FW=${6:-bios}
  UUID=$(cat luks.uuid)
  common="rhgb quiet plymouth.enable=1 loglevel=3 rd.udev.log_level=3 systemd.show_status=false plymouth.ignore-serial-consoles plymouth.debug=stream:/dev/ttyS1"
  case $SCEN in
    password) APPEND="rd.luks.uuid=$UUID root=LABEL=pf-no-root $common" ;;
    splash) APPEND="root=LABEL=pf-no-root $common" ;;
    selftest) APPEND="root=LABEL=pf-no-root pf.selftest $common" ;;
    *) echo "unknown scenario" >&2; exit 2 ;;
  esac
  UEFI=()
  if [ "$FW" = uefi ]; then UEFI=(--uefi); fi
  if [ -n "${PF_SECOND_HEAD:-}" ]; then UEFI+=(--second "$PF_SECOND_HEAD"); fi
  INITRD=initrd-base.img
  [ "$WHICH" = test ] && INITRD=initrd-test.img
  rm -rf "out/$NAME"
  python3 "$HERE/vmrun.py" --work "$WORK" --initrd "$WORK/$INITRD" --disk "$WORK/$DISK.img" --size "$SIZE" \
    --append "$APPEND" --scenario "$SCEN" --out "$WORK/out/$NAME" "${UEFI[@]}"
  ;;
clean)
  rm -rf luks.img disk.img bare.img luks.uuid initrd-base.img initrd-test.img overlay.cpio ov tmp qmp.sock probe.ppm OVMF_VARS.fd
  ;;
*)
  echo "unknown command $CMD" >&2; exit 2 ;;
esac
