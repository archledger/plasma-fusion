#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Boot the test VM (QEMU/KVM, headless) and drive one scenario through QMP: screenshots with
the monitor's screendump command, keys with send-key. Runs on the test device (stdlib only).

    vmrun.py --work DIR --initrd FILE --disk FILE --size WxH --append CMDLINE --scenario NAME --out DIR

Scenarios:
  password   wait for the unlock field, type, Caps Lock, Esc (details) and back, unlock
  splash     no password: screenshots of the logo and the pulsing dots
  selftest   the self-test unit in the initramfs overlay shows a message, asks a question,
             other prompts and a system update; each step is announced on ttyS0
"""
import argparse
import json
import os
import socket
import subprocess
import sys
import time

PASSPHRASE = "fusion-test"


class QMP:
    def __init__(self, path, timeout=30):
        end = time.time() + timeout
        while True:
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(path)
                break
            except OSError:
                if time.time() > end:
                    raise
                time.sleep(0.2)
        self.buf = b""
        self._read()
        self.cmd("qmp_capabilities")

    def _read(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError("QMP closed")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line)

    def cmd(self, name, **args):
        msg = {"execute": name}
        if args:
            msg["arguments"] = args
        self.sock.sendall(json.dumps(msg).encode() + b"\n")
        while True:
            r = self._read()
            if "return" in r or "error" in r:
                if "error" in r:
                    raise RuntimeError(f"{name}: {r['error']}")
                return r["return"]

    def keys(self, *qcodes, hold=60):
        self.cmd("send-key", keys=[{"type": "qcode", "data": q} for q in qcodes], **{"hold-time": hold})
        time.sleep(0.12)

    def type(self, text):
        names = {"-": "minus", " ": "spc", ".": "dot", "/": "slash", "_": ("shift", "minus"), ":": ("shift", "semicolon")}
        for ch in text:
            if ch in names:
                q = names[ch]
                self.keys(*(q if isinstance(q, tuple) else (q,)))
            elif ch.isupper():
                self.keys("shift", ch.lower())
            else:
                self.keys(ch)


def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    parts, pos = [], 0
    while len(parts) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            pos = data.index(b"\n", pos) + 1
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        parts.append(data[pos:end])
        pos = end
    pos += 1
    w, h = int(parts[1]), int(parts[2])
    return w, h, data[pos:]


class VM:
    def __init__(self, a):
        self.a = a
        self.work = a.work
        self.out = a.out
        os.makedirs(self.out, exist_ok=True)
        w, h = a.size.split("x")
        self.w, self.h = int(w), int(h)
        self.qmp_path = os.path.join(self.work, "qmp.sock")
        self.serial = os.path.join(self.out, "serial.log")
        for p in (self.qmp_path, self.serial):
            if os.path.exists(p):
                os.remove(p)
        cmd = ["nice", "-n", "10", "qemu-system-x86_64", "-enable-kvm", "-cpu", "host", "-smp", "2", "-m", "2048",
               "-machine", "q35", "-nodefaults", "-no-reboot",
               "-kernel", a.kernel, "-initrd", a.initrd, "-append", a.append,
               "-drive", f"file={a.disk},if=virtio,format=raw",
               "-device", f"VGA,edid=on,xres={self.w},yres={self.h},vgamem_mb=64",
               "-display", "none",
               *self.firmware(), *self.second_head(),
               "-qmp", f"unix:{self.qmp_path},server=on,wait=off",
               "-serial", f"file:{self.serial}",
               "-serial", f"file:{os.path.join(self.out, 'plymouth-debug.log')}"]
        self.proc = subprocess.Popen(cmd, stdout=open(os.path.join(self.out, "qemu.log"), "w"),
                                     stderr=subprocess.STDOUT)
        self.q = QMP(self.qmp_path)
        self.t0 = time.time()
        self.log = open(os.path.join(self.out, "steps.log"), "w")

    def firmware(self):
        """UEFI (OVMF) gives the kernel an EFI framebuffer, so plymouth starts on simpledrm and
        moves to bochs-drm when it loads (like the ThinkPad: simpledrm, then i915)."""
        if not self.a.uefi:
            return []
        vars_copy = os.path.join(self.work, "OVMF_VARS.fd")
        with open("/usr/share/edk2/ovmf/OVMF_VARS.fd", "rb") as src, open(vars_copy, "wb") as dst:
            dst.write(src.read())
        return ["-drive", "if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd",
                "-drive", f"if=pflash,format=raw,unit=1,file={vars_copy}"]

    def second_head(self):
        """A second, smaller display on its own virtio GPU (multi-monitor layout test)."""
        if not self.a.second:
            return []
        w, h = self.a.second.split("x")
        return ["-device", f"virtio-gpu-pci,id=gpu2,xres={w},yres={h}"]

    def note(self, text):
        line = f"{time.time() - self.t0:7.2f} {text}"
        print(line, flush=True)
        self.log.write(line + "\n")
        self.log.flush()

    def shot(self, name):
        path = os.path.join(self.out, f"{name}.png")
        self.q.cmd("screendump", filename=path, format="png")
        if self.a.second:
            self.q.cmd("screendump", filename=os.path.join(self.out, f"{name}-head2.png"),
                       format="png", device="gpu2")
        self.note(f"shot {name}")
        return path

    def pixel_probe(self):
        tmp = os.path.join(self.work, "probe.ppm")
        self.q.cmd("screendump", filename=tmp)
        return read_ppm(tmp)

    def wait_pixel(self, fx, fy, colour, tol=24, timeout=120, what=""):
        """Wait until the pixel at (fx*w, fy*h)-relative board position has `colour`."""
        end = time.time() + timeout
        while time.time() < end:
            w, h, px = self.pixel_probe()
            x, y = fx(w, h), fy(w, h)
            i = (y * w + x) * 3
            c = tuple(px[i:i + 3])
            if all(abs(c[k] - colour[k]) <= tol for k in range(3)):
                self.note(f"seen {what} at {x},{y}: {c}")
                return True
            time.sleep(0.5)
        self.note(f"timeout waiting for {what}")
        return False

    def wait_serial(self, marker, timeout=120):
        end = time.time() + timeout
        while time.time() < end:
            try:
                with open(self.serial, errors="replace") as f:
                    if marker in f.read():
                        self.note(f"serial: {marker}")
                        return True
            except FileNotFoundError:
                pass
            time.sleep(0.3)
        self.note(f"timeout waiting for serial {marker}")
        return False

    def stop(self):
        try:
            self.q.cmd("quit")
        except Exception:
            pass
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.note("stopped")


def scale_of(w, h):
    scales = [1, 1.25, 4 / 3, 1.5, 1.75, 2, 2.5]
    fit = min(w / 1440, h / 900)
    s = scales[0]
    for v in scales:
        if v <= fit + 0.06:
            s = v
    return s


def frame_pos(bx, by):
    """Board position -> screen pixel, as the script lays out the centred frame."""
    def fx(w, h):
        s = scale_of(w, h)
        return (w - round(1440 * s)) // 2 + int(bx * s)

    def fy(w, h):
        s = scale_of(w, h)
        return (h - round(900 * s)) // 2 + int(by * s)
    return fx, fy


BUTTON = frame_pos(875.5, 433)      # upper part of the round submit button (off the arrow)
BUTTON_RGB = (0x2F, 0x6F, 0xDF)
LOGO_BLUE = frame_pos(720, 266)     # top of the blue circle
BLUE_RGB = (0x5B, 0x9D, 0xFF)


def scenario_password(vm):
    if not vm.wait_pixel(*BUTTON, BUTTON_RGB, what="unlock field"):
        vm.shot("error-no-field")
        return 1
    time.sleep(0.4)
    vm.shot("01-prompt")
    time.sleep(0.55)
    vm.shot("01-prompt-caret")
    vm.q.type(PASSPHRASE[:6])
    time.sleep(0.4)
    vm.shot("02-typed-6")
    vm.q.type(PASSPHRASE[6:])
    time.sleep(0.4)
    vm.shot("03-typed-all")
    vm.q.keys("caps_lock")
    time.sleep(0.6)
    vm.shot("04-capslock")
    vm.q.keys("caps_lock")
    time.sleep(0.6)
    vm.shot("05-capslock-off")
    vm.q.keys("esc")
    time.sleep(1.0)
    vm.shot("06-esc-details")
    vm.q.keys("esc")
    time.sleep(1.0)
    vm.shot("07-esc-back")
    vm.q.keys("ret")
    time.sleep(1.2)
    vm.shot("08-unlocked")
    time.sleep(0.47)
    vm.shot("09-unlocked-later")
    time.sleep(4)
    vm.shot("10-unlocked-4s")
    return 0


def scenario_splash(vm):
    if not vm.wait_pixel(*LOGO_BLUE, BLUE_RGB, what="logo"):
        vm.shot("error-no-logo")
        return 1
    time.sleep(1.5)
    for i in range(5):
        vm.shot(f"splash-{i}")
        time.sleep(0.28)
    return 0


def scenario_selftest(vm):
    steps = [
        ("PFSTEP message", "st-01-message", None),
        ("PFSTEP question", "st-02-question", "backup-01"),
        ("PFSTEP recovery", "st-03-recovery-prompt", "abcdefgh"),
        ("PFSTEP pin", "st-04-pin", "1234"),
        ("PFSTEP other", "st-05-other-prompt", "secret"),
        ("PFSTEP update", "st-06-update-42", None),
        ("PFSTEP update2", "st-07-update-87", None),
    ]
    for marker, shot, answer in steps:
        if not vm.wait_serial(marker, timeout=90):
            vm.shot("error-" + shot)
            return 1
        time.sleep(1.0)
        vm.shot(shot)
        if answer:
            vm.q.type(answer)
            time.sleep(0.4)
            vm.shot(shot + "-typed")
            vm.q.keys("ret")
    vm.wait_serial("PFSTEP done", timeout=60)
    time.sleep(0.5)
    vm.shot("st-08-done")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--kernel", default=f"/boot/vmlinuz-{os.uname().release}")
    ap.add_argument("--initrd", required=True)
    ap.add_argument("--disk", required=True)
    ap.add_argument("--size", default="1920x1200")
    ap.add_argument("--append", required=True)
    ap.add_argument("--scenario", required=True, choices=["password", "splash", "selftest"])
    ap.add_argument("--out", required=True)
    ap.add_argument("--uefi", action="store_true")
    ap.add_argument("--second", help="WxH of a second display")
    a = ap.parse_args()
    vm = VM(a)
    rc = 1
    try:
        rc = {"password": scenario_password, "splash": scenario_splash, "selftest": scenario_selftest}[a.scenario](vm)
    finally:
        vm.stop()
    sys.exit(rc)


if __name__ == "__main__":
    main()
