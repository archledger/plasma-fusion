#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""splashtest.sh against a stand-in VM and a stand-in QMP socket: three boots (the system's splash,
Plasma Fusion's, the system's again after the uninstall), the screendumps of each from the reset on,
and every gate failing the run with the overlay kept: the kernel arguments, the installer's offer,
the reset, the boot's command line, the selection, the board comparison, Plymouth's log (a pixel
display, the script plugin), the desktop after the splash, the uninstall leaving no splash and the
system's theme, a crash after either boot. Needs Pillow."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import unittest

from PIL import Image

HERE = Path(__file__).resolve().parent
TOP = HERE.parents[2]
spec = importlib.util.spec_from_file_location("splash_capture", HERE / "splash-capture.py")
splash_capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(splash_capture)

THEME = "/usr/share/plymouth/themes/plasma-fusion"
# The stand-in vm.sh: the boot count in $PF_VM_HOME/boot (a reboot adds one), the selected theme in
# $PF_VM_HOME/theme; the command line, Plymouth's log and the desktop follow the boot and FAULT.
BOUNDARY = r'''#!/bin/bash
set -eu
cmd=$1; name=$2; shift 2
V=$PF_VM_HOME
echo "$cmd $*" >>"$V/calls"
boot=$(cat "$V/boot" 2>/dev/null || echo 0)
stock=ceratopsian
[ "$FAULT" != arch ] || stock=none
[ -f "$V/theme" ] || echo "$stock" >"$V/theme"
case "$cmd" in
  start) printf overlay >"$V/vms/$name/run.qcow2" ;;
  wait|stop) exit 0 ;;
  ssh)
    case "$*" in
      *'systemctl reboot'*) echo $((boot + 1)) >"$V/boot" ;;
      *'autologin.conf.off'*) [ "$FAULT" != login ] || [ "$boot" = 0 ] ;;
      *os-release*) echo 'PRETTY_NAME="Stand-in"'; echo ID=standin ;;
      *'ARGS='*) [ "$FAULT" != cmdline ] ;;
      *'pacman -Sw'*) [ "$FAULT" != nodownload ] ;;
      *'install.sh --yes'*) [ "$FAULT" = nooffer ] ||
          echo "Optional: the boot splash (sudo /usr/share/plasma-fusion/tools/system/plymouth-install.sh --select)." ;;
      'sudo sh -s') cat "$V/theme" ;;
      *'plymouth-install.sh --select')
        [ "$FAULT" != select ] || exit 1
        if [ "$FAULT" = wrongselect ]; then echo ceratopsian; else echo plasma-fusion; fi >"$V/theme" ;;
      *'cat /proc/cmdline'*)
        if [ "$FAULT" = nocmdline ]; then echo "BOOT_IMAGE=/vmlinuz root=/dev/vda1 quiet"
        else echo "BOOT_IMAGE=/vmlinuz root=/dev/vda1 quiet splash plymouth.ignore-serial-consoles plymouth.debug"; fi ;;
      *'cat /var/log/plymouth-debug.log'*)
        [ "$boot" = 2 ] || exit 0
        # (as Plymouth writes its trace: "HH:MM:SS.mmm FILE:LINE:FUNCTION", padded to 75, ": " message)
        [ "$FAULT" = textsplash ] ||
          printf '%-75.75s: %s\n' "00:00:02.103 ply-boot-splash.c:142:ply_boot_splash_add_pixel_display" "adding 1280x800 pixel display"
        printf '%-75.75s: %s\n' "00:00:01.020 main.c:458:find_system_default_splash" "System configured theme file is 'THEME/plasma-fusion.plymouth'"
        [ "$FAULT" = noscript ] ||
          printf '%-75.75s: %s\n' "00:00:02.110 ./plugin.c:352:start_script_animation" "executing script file" ;;
      *'install.sh uninstall --yes'*)
        [ "$FAULT" != uninstall ] || exit 1
        case $FAULT in
          stilltheme) echo plasma-fusion ;;
          othertheme) echo spinner ;;
          arch) echo bgrt ;;
          *) echo "$stock" ;;
        esac >"$V/theme" ;;
      *'ls -d THEME'*)
        [ "$FAULT" != leftover ] || echo "THEME"
        [ "$FAULT" != leftrecord ] || echo previous-theme ;;
      *'cat /var/lib/plasma-fusion/plymouth/installed-packages'*) [ "$FAULT" != arch ] || printf 'plymouth\nplymouth-label-ft\n' ;;
      # (the crash count: one after the Plasma Fusion boot or the restored one, or no collector)
      'python3 -')
        [ "$FAULT" != nocollector ] || exit 1
        case "$FAULT:$boot" in crash:2|crashafter:3) echo 1 ;; *) echo 0 ;; esac ;;
      # (after the others: the commands run in the session start with a pgrep of plasmashell too)
      *'pgrep -u pf'*) [ "$FAULT" != nodesktop ] || [ "$boot" != 2 ] ;;
    esac ;;
esac
'''.replace("THEME", THEME)


class FakeQMP(threading.Thread):
    """QEMU's QMP socket: the greeting, capabilities, a RESET event after them (none with FAULT
    noreset: the connection closes, as when QEMU goes away), and screendumps of the stock or the
    Plasma Fusion screen by the boot count in HOME/boot."""

    def __init__(self, path, home, fault):
        super().__init__(daemon=True)
        self.home, self.fault = home, fault
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(str(path))
        self.server.listen()
        self.dumps = 0

    def image(self):
        boot = int((self.home / "boot").read_text()) if (self.home / "boot").exists() else 0
        fusion = {1: self.fault == "stocklook", 2: self.fault != "look", 3: self.fault == "stillfusion"}
        return self.home / ("fusion.png" if fusion.get(boot) else "stock.png")

    def run(self):
        while True:
            try:
                client, _ = self.server.accept()
            except OSError:
                return
            with client:
                client.sendall(b'{"QMP": {"version": {}, "capabilities": []}}\n')
                for line in client.makefile("rb"):
                    msg = json.loads(line)
                    if msg["execute"] == "screendump":
                        # (QMP's default format, as splash-capture.py asks for it)
                        Image.open(self.image()).save(msg["arguments"]["filename"], format="PPM")
                        self.dumps += 1
                    client.sendall(b'{"return": {}}\n')
                    if msg["execute"] == "qmp_capabilities":
                        if self.fault == "noreset":
                            break
                        client.sendall(b'{"event": "RESET", "data": {"guest": true, "reason": "guest-reset"}}\n')


class SplashTest(unittest.TestCase):
    def run_lane(self, fault="none", lane="copr"):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / "repo/tools/tests/release-vm"
            root.mkdir(parents=True)
            for filename in ["splashtest.sh", "lane-env.sh", "splash-capture.py", "crash-count.py"]:
                shutil.copy2(HERE / filename, root / filename)
            (home / "repo/design/previews").mkdir(parents=True)
            shutil.copy2(TOP / "design/previews/Splash.webp", home / "repo/design/previews/Splash.webp")
            (root / "vm.sh").write_text(BOUNDARY)
            (home / "vms/test").mkdir(parents=True)
            (root / "bin").mkdir()
            (root / "bin/sleep").write_text("#!/bin/sh\nexit 0\n")
            (root / "bin/sleep").chmod(0o755)
            board = Image.open(TOP / "design/previews/Splash.webp").convert("RGB")
            splash_capture.expected(board, (1280, 800)).save(home / "fusion.png")
            Image.new("RGB", (1280, 800), (40, 100, 140)).save(home / "stock.png")
            qmp = FakeQMP(home / "vms/test/qmp.sock", home, fault)
            qmp.start()
            result = subprocess.run(["bash", str(root / "splashtest.sh"), "test", lane], capture_output=True,
                                    text=True, env={**os.environ, "PF_VM_HOME": directory, "PF_PUBLIC": "1",
                                                    "FAULT": fault, "PF_SPLASH_SECONDS": "1",
                                                    "PATH": str(root / "bin") + ":" + os.environ["PATH"]})
            qmp.server.close()
            self.dumps = qmp.dumps
            self.boots = int((home / "boot").read_text()) if (home / "boot").exists() else 0
            self.calls = (home / "calls").read_text().splitlines()
            self.locked = (home / "vms/test/run.qcow2").exists()
            self.preserved = list((home / "vms/test").glob("failed-splash-run-*.qcow2"))
            out = home / "results/test-splash"
            self.kept = sorted(p.name for p in (out / "32-fusion").iterdir()) if (out / "32-fusion").is_dir() else []
            return result

    def assert_failed(self, result, message):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("FAIL: " + message, result.stdout)
        self.assertIn("stop ", self.calls)
        self.assertFalse(self.locked)
        self.assertEqual(len(self.preserved), 1)

    def test_pass(self):
        result = self.run_lane()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.boots, 3)
        self.assertGreater(self.dumps, 3)
        self.assertIn("kernel arguments added: quiet splash plymouth.ignore-serial-consoles plymouth.debug", result.stdout)
        self.assertIn("the installer offers the boot splash step", result.stdout)
        self.assertIn("stock splash theme: ceratopsian", result.stdout)
        self.assertIn("selected: plasma-fusion", result.stdout)
        self.assertIn("match: closest frame's largest delta 0.0", result.stdout)
        self.assertIn("plymouth: adding 1280x800 pixel display", result.stdout)
        self.assertIn(f"plymouth: System configured theme file is '{THEME}/plasma-fusion.plymouth'", result.stdout)
        self.assertIn("splash theme after uninstall: ceratopsian", result.stdout)
        self.assertEqual(result.stdout.count("differs: closest frame's largest delta"), 2)
        self.assertIn("done test (boot splash)", result.stdout)
        self.assertEqual(self.kept, ["best.png", "first-match.png", "frames.tsv", "last.png", "sheet.png"])
        # Each captured boot runs without the tty1 log-in, which follows the capture
        steps = [c for c in self.calls if "autologin.conf" in c or "systemctl reboot" in c]
        self.assertEqual(len(steps), 9)
        for i in range(0, 9, 3):
            self.assertIn("mv /etc/systemd/system/getty@tty1.service.d/autologin.conf /etc/", steps[i])
            self.assertIn("systemctl reboot", steps[i + 1])
            self.assertIn("autologin.conf.off /etc/systemd/system/getty@tty1.service.d/autologin.conf", steps[i + 2])
            self.assertIn("systemctl restart getty@tty1", steps[i + 2])
        self.assertFalse(self.locked)
        self.assertFalse(self.preserved)

    def test_without_plymouth_before(self):
        # Arch: no Plymouth before the install; the one it brings stays, with its own default theme
        result = self.run_lane("arch", "aur")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # Plymouth downloaded first (the installer's pacman then installs it from the cache)
        downloads = [i for i, c in enumerate(self.calls) if "pacman -Sw --needed --noconfirm plymouth" in c]
        selects = [i for i, c in enumerate(self.calls) if "plymouth-install.sh --select" in c]
        self.assertEqual(len(downloads), 1)
        self.assertLess(downloads[0], selects[0])
        self.assertIn("stock splash theme: none", result.stdout)
        self.assertIn("splash theme after uninstall: bgrt", result.stdout)
        self.assertIn("kept: the packages the splash installer installed (plymouth plymouth-label-ft)", result.stdout)

    def test_download_gate(self):
        self.assert_failed(self.run_lane("nodownload", "aur"), "could not download Plymouth")

    def test_gates(self):
        for fault, message in [
            ("cmdline", "could not add the splash's kernel arguments"),
            ("nooffer", "the installer did not offer the boot splash step"),
            ("noreset", "the VM did not reset (20-stock)"),
            ("nocmdline", "the boot's command line lacks splash (20-stock)"),
            ("stocklook", "the stock boot looks like the Splash board"),
            ("select", "plymouth-install.sh --select"),
            ("wrongselect", "plymouth-install.sh selected ceratopsian"),
            ("login", "could not log in on tty1 again (20-stock)"),
            ("nodesktop", "no desktop after the reboot (32-fusion)"),
            ("look", "no frame of the boot looks like the Splash board"),
            ("textsplash", "Plymouth's log names no pixel display"),
            ("noscript", "Plymouth's log does not show the script plugin running"),
            ("crash", "crashes found"),
            ("nocollector", "crash collector unavailable or failed"),
            ("uninstall", "uninstall"),
            ("leftover", "the splash is still installed after uninstall"),
            ("leftrecord", "the splash is still installed after uninstall"),
            ("stilltheme", "the splash theme after uninstall is plasma-fusion"),
            ("othertheme", "the splash theme after uninstall is spinner, not the stock ceratopsian"),
            ("stillfusion", "the boot after uninstall still looks like the Splash board"),
            ("crashafter", "crashes found after the uninstall"),
        ]:
            with self.subTest(fault=fault):
                self.assert_failed(self.run_lane(fault), message)


class CompareTest(unittest.TestCase):
    """The comparison alone: the board as the theme draws it matches on the release VMs' 1280x800
    and on other screens; a dark screen without the logo does not."""

    def test_regions(self):
        board = Image.open(TOP / "design/previews/Splash.webp").convert("RGB")
        for size in [(1280, 800), (1920, 1080), (2880, 1800), (1024, 768)]:
            with self.subTest(size=size):
                cache = {}
                drawn = splash_capture.expected(board, size)
                self.assertLessEqual(max(splash_capture.deltas(drawn, board, cache).values()), 1.0)
                dark = Image.new("RGB", size, (13, 17, 32))
                self.assertGreater(max(splash_capture.deltas(dark, board, cache).values()), 18)


if __name__ == "__main__":
    unittest.main()
