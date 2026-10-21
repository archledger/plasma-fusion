#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""sddmtest.sh against a stand-in VM: three boots (the stock greeter, Plasma Fusion's, the stock one
after the uninstall), the password typed into QEMU's monitor, and every gate failing the run with
the overlay kept: the theme SDDM started, warnings from the theme's files (Qt's own pass), the
board comparison, the session from SDDM, the uninstall leaving SDDM's files clean. Needs Pillow."""
import importlib.util
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
spec = importlib.util.spec_from_file_location("greeter_compare", HERE / "greeter-compare.py")
greeter_compare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(greeter_compare)

THEMES = "/usr/share/sddm/themes"
# The stand-in vm.sh: the boot count in $PF_VM_HOME/boot, a reboot makes the next "ssh true" fail
# once (the VM went down), the journal and the screenshot follow the boot and FAULT.
BOUNDARY = r'''#!/bin/bash
set -eu
cmd=$1; name=$2; shift 2
V=$PF_VM_HOME
echo "$cmd" >>"$V/calls"
boot=$(cat "$V/boot" 2>/dev/null || echo 0)
case "$cmd" in
  start) printf overlay >"$V/vms/$name/run.qcow2" ;;
  wait|stop) exit 0 ;;
  shot)
    img=stock
    case $boot in 2) [ "$FAULT" = look ] || img=fusion ;; 3) [ "$FAULT" != stillfusion ] || img=fusion ;; esac
    cp "$V/$img.png" "$1" ;;
  ssh)
    case "$*" in
      *'systemctl reboot'*) echo $((boot + 1)) >"$V/boot"; touch "$V/down" ;;
      true) if [ -f "$V/down" ]; then rm "$V/down"; exit 1; fi ;;
      *'-u sddm'*) [ "$FAULT" != nogreeter ] ;;
      *short-monotonic*)
        theme=debian-theme
        if [ "$boot" = 2 ]; then
          theme=plasmafusion; [ "$FAULT" != wrongtheme ] || theme=breeze
        elif [ "$boot" = 3 ] && [ "$FAULT" = stilltheme ]; then theme=plasmafusion; fi
        echo "[ 5.1] pf sddm-helper[9]: Starting X11 session: \"\" \"/usr/bin/sddm-greeter-qt6 --socket /tmp/sddm-:0-x --theme THEMES/$theme\""
        echo "[ 5.2] pf sddm[8]: Greeter session started successfully"
        if [ "$FAULT" = nogreeter ]; then :
        elif [ "$FAULT" = embedded ] && [ "$boot" != 2 ]; then
          echo "[ 5.3] pf sddm-greeter-qt6[10]: Loading qrc:/theme/Main.qml..."
        else echo "[ 5.3] pf sddm-greeter-qt6[10]: Loading file://THEMES/$theme/Main.qml..."; fi
        echo "[ 5.4] pf sddm-greeter-qt6[10]: Member contentWidth of the object PopupList_QMLTYPE_33 overrides a member of the base object."
        [ "$FAULT" != warning ] || [ "$boot" != 2 ] ||
          echo "[ 5.5] pf sddm-greeter-qt6[10]: file://THEMES/plasmafusion/LoginCard.qml:42: TypeError: Cannot read property 'x' of null"
        ;;
      *'display manager:'*) [ "$FAULT" != sddmsetup ] || exit 1
        echo "display manager: /usr/lib/systemd/system/sddm.service"; echo "sddm 0.21.0" ;;
      *'greeter-apply.sh --check'*) if [ -f "$V/applied" ] || [ "$FAULT" = checkyes ]; then exit 0; else exit 1; fi ;;
      *'sudo /usr/share/plasma-fusion/tools/system/greeter-apply.sh') touch "$V/applied"; [ "$FAULT" != apply ] ;;
      *'install.sh uninstall --yes'*) rm -f "$V/applied"; echo "Undo the run of greeter-apply.sh"; [ "$FAULT" != uninstall ] ;;
      *'install.sh --yes'*) [ "$FAULT" = nooffer ] ||
          echo "Optional: the login screen (sudo /usr/share/plasma-fusion/tools/system/greeter-apply.sh)." ;;
      *'loginctl list-sessions'*)
        if [ "$FAULT" = nosession ]; then printf 'Service=login\nType=tty\nState=active\n'
        else printf 'Service=sddm\nType=x11\nState=active\n'; fi ;;
      *'plasma-fusion status'*) echo "  login screen (SDDM): Plasma Fusion" ;;
      *'/etc/sddm.conf.d/kde_settings.conf /etc/sddm.conf'*)
        if [ "$FAULT" = leftover ]; then printf '== /etc/sddm.conf.d/kde_settings.conf\n[Theme]\nCurrent=plasmafusion\n'
        else echo greeter-backup-20261021T000000Z; fi ;;
      'python3 -') echo 0 ;;
    esac ;;
esac
'''.replace("THEMES", THEMES)


class Monitor(threading.Thread):
    """QEMU's monitor socket: the banner, then every line a client sends."""

    def __init__(self, path):
        super().__init__(daemon=True)
        self.lines = []
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(str(path))
        self.server.listen()

    def run(self):
        while True:
            try:
                client, _ = self.server.accept()
            except OSError:
                return
            client.sendall(b"QEMU monitor\n(qemu) ")
            data = b""
            while chunk := client.recv(4096):
                data += chunk
            client.close()
            self.lines += data.decode().splitlines()


class SddmTest(unittest.TestCase):
    def run_lane(self, fault="none"):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home / "repo/tools/tests/release-vm"
            root.mkdir(parents=True)
            for filename in ["sddmtest.sh", "lane-env.sh", "greeter-compare.py", "crash-count.py"]:
                shutil.copy2(HERE / filename, root / filename)
            (home / "repo/design/previews").mkdir(parents=True)
            shutil.copy2(TOP / "design/previews/Login.webp", home / "repo/design/previews/Login.webp")
            (root / "vm.sh").write_text(BOUNDARY)
            (home / "vms/test").mkdir(parents=True)
            (root / "bin").mkdir()
            (root / "bin/sleep").write_text("#!/bin/sh\nexit 0\n")
            (root / "bin/sleep").chmod(0o755)
            board = Image.open(TOP / "design/previews/Login.webp").convert("RGB")
            greeter_compare.fill(board, (1280, 800)).save(home / "fusion.png")
            Image.new("RGB", (1280, 800), (40, 100, 140)).save(home / "stock.png")
            monitor = Monitor(home / "vms/test/mon.sock")
            monitor.start()
            result = subprocess.run(["bash", str(root / "sddmtest.sh"), "test", "copr"], capture_output=True,
                                    text=True, env={**os.environ, "PF_VM_HOME": directory, "PF_PUBLIC": "1",
                                                    "FAULT": fault,
                                                    "PATH": str(root / "bin") + ":" + os.environ["PATH"]})
            monitor.server.close()
            self.keys = monitor.lines
            self.boots = int((home / "boot").read_text()) if (home / "boot").exists() else 0
            self.calls = (home / "calls").read_text().splitlines()
            self.locked = (home / "vms/test/run.qcow2").exists()
            self.preserved = list((home / "vms/test").glob("failed-sddm-run-*.qcow2"))
            return result

    def assert_failed(self, result, message):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("FAIL: " + message, result.stdout)
        self.assertIn("stop", self.calls)
        self.assertFalse(self.locked)
        self.assertEqual(len(self.preserved), 1)

    def test_pass(self):
        result = self.run_lane()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.boots, 3)
        self.assertIn(f"stock greeter theme: {THEMES}/debian-theme", result.stdout)
        self.assertIn(f"greeter theme: {THEMES}/plasmafusion", result.stdout)
        self.assertIn("warnings from the theme's files: 0", result.stdout)
        self.assertIn("match: largest delta", result.stdout)
        self.assertIn("session: Service=sddm Type=x11 State=active", result.stdout)
        self.assertIn(f"greeter theme after uninstall: {THEMES}/debian-theme", result.stdout)
        self.assertIn("done test (SDDM)", result.stdout)
        self.assertFalse(self.locked)
        self.assertFalse(self.preserved)

    def test_embedded_stock_theme(self):
        # Fedora without its theme package: SDDM's own theme before and after
        result = self.run_lane("embedded")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("stock greeter theme: embedded", result.stdout)
        self.assertIn("greeter theme after uninstall: embedded", result.stdout)

    def test_password_typed_then_return(self):
        self.run_lane()
        typed = [line for line in self.keys if line.startswith("sendkey ")]
        self.assertEqual(typed, ["sendkey " + k for k in
                                 ["p", "f", "minus", "s", "d", "d", "m", "minus", "t", "e", "s", "t", "ret"]])

    def test_gates(self):
        for fault, message in [
            ("sddmsetup", "could not make SDDM the display manager"),
            ("nooffer", "the installer did not offer the login screen step"),
            ("checkyes", "greeter-apply.sh --check before: rc=0"),
            ("nogreeter", "SDDM's greeter did not start (20-stock-greeter)"),
            ("apply", "greeter-apply.sh"),
            ("wrongtheme", f"SDDM started its greeter with {THEMES}/breeze"),
            ("warning", "the greeter warned about the theme"),
            ("look", "the greeter does not look like the Login board"),
            ("nosession", "no session for pf from SDDM after the password"),
            ("uninstall", "uninstall"),
            ("leftover", "SDDM's files still name the theme after uninstall"),
            ("stilltheme", f"the greeter theme after uninstall is {THEMES}/plasmafusion"),
            ("stillfusion", "the restored greeter still looks like the Login board"),
        ]:
            with self.subTest(fault=fault):
                self.assert_failed(self.run_lane(fault), message)


if __name__ == "__main__":
    unittest.main()
