#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Release-test VMs on this machine (qemu, user networking, no root). One directory per VM below
# ~/pf-vm/vms/NAME: base.qcow2 (provisioned: Plasma installed) and run.qcow2 (a test run on top).
#
#   vm.sh create NAME IMAGE        overlay of a cloud image + cloud-init seed (user pf, test key)
#   vm.sh start NAME [base|run]    boot (base: provisioning; run: a fresh overlay of base)
#   vm.sh ssh NAME [CMD...]        ssh as pf (port from the VM's index)
#   vm.sh shot NAME FILE.png       QEMU screendump of the display
#   vm.sh stop NAME                power off (ACPI, then kill)
#   vm.sh wait NAME                wait for ssh
set -euo pipefail
H=${PF_VM_HOME:-$HOME/pf-vm}
cmd=$1 name=$2
shift 2
d=$H/vms/$name
port() { echo $((2200 + $(cat "$d/index"))); }
mem=${PF_VM_MEM:-4096} cpus=${PF_VM_CPUS:-4}
sshv() { ssh -q -i "$H/id_ed25519" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -p "$(port)" pf@127.0.0.1 "$@"; }
case $cmd in
  create)
    img=$1
    mkdir -p "$d"
    [ -f "$d/index" ] || { n=$(ls "$H/vms" | wc -l); echo "$n" >"$d/index"; }
    qemu-img create -q -f qcow2 -F qcow2 -b "$H/images/$img" "$d/base.qcow2" 40G
    pub=$(cat "$H/id_ed25519.pub")
    cat >"$d/user-data" <<UD
#cloud-config
hostname: pf-$name
users:
  - name: pf
    gecos: Plasma Fusion test
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys: [$pub]
ssh_pwauth: false
growpart: {mode: auto, devices: ['/']}
UD
    printf 'instance-id: pf-%s\nlocal-hostname: pf-%s\n' "$name" "$name" >"$d/meta-data"
    genisoimage -quiet -output "$d/seed.iso" -volid cidata -joliet -rock "$d/user-data" "$d/meta-data"
    echo "created $d (ssh port $(port))" ;;
  start)
    which=${1:-base}
    disk=$d/base.qcow2
    if [ "$which" = run ]; then
      qemu-img create -q -f qcow2 -F qcow2 -b "$d/base.qcow2" "$d/run.qcow2"
      disk=$d/run.qcow2
    fi
    qemu-system-x86_64 -name "pf-$name" -enable-kvm -cpu host -smp "$cpus" -m "$mem" -machine q35 \
      -drive "file=$disk,if=virtio,discard=unmap" -drive "file=$d/seed.iso,media=cdrom,readonly=on" \
      -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$(port)-:22" \
      -device virtio-vga -display none -vnc "127.0.0.1:$(( $(cat "$d/index") + 10 ))" \
      -monitor "unix:$d/mon.sock,server,nowait" -serial "file:$d/serial.log" \
      -daemonize -pidfile "$d/qemu.pid"
    echo "started $name ($which), pid $(cat "$d/qemu.pid")" ;;
  wait)
    for _ in $(seq 1 120); do sshv true 2>/dev/null && { echo "$name: ssh up"; exit 0; }; sleep 5; done
    echo "$name: no ssh after 10 min" >&2; exit 1 ;;
  ssh) sshv "$@" ;;
  shot)
    out=$(realpath -m "$1")
    printf 'screendump %s -f png\n' "$out" | python3 -c "
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect('$d/mon.sock'); time.sleep(0.3); s.recv(65536)
s.sendall(sys.stdin.read().encode()); time.sleep(1.5); s.close()"
    [ -s "$out" ] && echo "$out" ;;
  stop)
    [ -f "$d/qemu.pid" ] || exit 0
    pid=$(cat "$d/qemu.pid")
    # In a Plasma session the power button opens the logout dialog: power off over ssh first.
    sshv sudo systemctl poweroff 2>/dev/null || true
    for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 2; done
    kill -0 "$pid" 2>/dev/null && printf 'system_powerdown\n' | python3 -c "
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect('$d/mon.sock'); time.sleep(0.3); s.sendall(sys.stdin.read().encode()); time.sleep(0.5)" 2>/dev/null || true
    for _ in $(seq 1 15); do kill -0 "$pid" 2>/dev/null || break; sleep 2; done
    kill -0 "$pid" 2>/dev/null && kill "$pid"
    rm -f "$d/qemu.pid"; echo "stopped $name" ;;
  *) echo "unknown command $cmd" >&2; exit 2 ;;
esac
