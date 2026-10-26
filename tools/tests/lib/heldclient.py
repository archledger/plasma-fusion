#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""An xdg-shell window whose answers to configure events a private-session scenario controls.

Ordinary apps answer a configure at once, so a test cannot make one commit a tile-sized frame
after the window was untiled (KDE bug 527821). This client can: xdg-shell lets a client
acknowledge a configure and commit later.

    heldclient.py APP_ID [WIDTHxHEIGHT]

Commands on stdin, one per line:
    hold          keep later configure events (logged) instead of answering them
    auto          answer every configure at once (the start mode), also the newest one held
    ack SERIAL    acknowledge a held configure; its size is the next buffer's
    commit        attach a buffer of the acknowledged size and commit it
    maximize      ask to be maximized (xdg_toplevel.set_maximized): KWin answers with a configure
    unmaximize    ask to be restored (xdg_toplevel.unset_maximized)
    quit          destroy the window and exit
Events on stdout, one JSON object per line: ready, configure, ack, commit, command, close.
Errors go to stderr with exit status 2. It runs only inside a tools/vsession private session
(PFV=/var/tmp/pfv-NAME, XDG_RUNTIME_DIR=$PFV/run), never on a logged-in desktop, and exits after
300 seconds at the latest.
"""
import array
import json
import mmap
import os
import select
import sys
import time

from pywayland.client import Display
from pywayland.protocol.wayland import WlCompositor, WlShm
from pywayland.protocol.xdg_shell import XdgWmBase

LIFETIME = 300
FORMAT_XRGB8888 = 1


def die(message):
    print(f"heldclient: {message}", file=sys.stderr, flush=True)
    sys.exit(2)


def emit(event, **fields):
    print(json.dumps({"event": event, **fields, "time": time.monotonic()}), flush=True)


def guarded():
    pfv = os.environ.get("PFV", "")
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    if not pfv or not runtime:
        return False
    real = os.path.realpath(pfv)
    private_dir = os.path.dirname(real) in ("/var/tmp", "/tmp")
    private_dir = private_dir and os.path.basename(real).startswith("pfv-")
    return private_dir and os.path.realpath(runtime) == os.path.join(real, "run")


class Client:
    def __init__(self, app_id, width, height):
        self.width, self.height = width, height  # the size the next buffer has
        self.pending = (width, height)  # the newest xdg_toplevel.configure size
        self.held = {}  # serial -> (width, height) of configure events not acknowledged yet
        self.automatic = True
        self.running = True
        self.buffers = []  # [wl_buffer, mmap] pairs, released by the compositor
        self.display = Display()
        self.display.connect()
        self.globals = {}
        registry = self.display.get_registry()
        registry.dispatcher["global"] = self.on_global
        self.display.roundtrip()
        for name in ("wl_compositor", "wl_shm", "xdg_wm_base"):
            if name not in self.globals:
                die(f"the compositor has no {name}")
        self.compositor = registry.bind(*self.binding("wl_compositor", WlCompositor, 4))
        self.shm = registry.bind(*self.binding("wl_shm", WlShm, 1))
        self.shell = registry.bind(*self.binding("xdg_wm_base", XdgWmBase, XdgWmBase.version))
        self.shell.dispatcher["ping"] = lambda shell, serial: shell.pong(serial)
        self.surface = self.compositor.create_surface()
        self.xdg = self.shell.get_xdg_surface(self.surface)
        self.xdg.dispatcher["configure"] = self.on_configure
        self.top = self.xdg.get_toplevel()
        self.top.dispatcher["configure"] = self.on_toplevel_configure
        self.top.dispatcher["close"] = self.on_close
        self.top.set_app_id(app_id)
        self.top.set_title(f"Held client {app_id}")
        self.top.set_min_size(100, 100)
        self.surface.commit()  # the first commit carries no buffer
        emit("ready", appId=app_id)

    def binding(self, name, interface, wanted):
        number, version = self.globals[name]
        return number, interface, min(version, wanted)

    def on_global(self, registry, name, interface, version):
        self.globals[interface] = (name, version)

    def on_toplevel_configure(self, top, width, height, states):
        # 0 leaves the size to the client: keep the current one.
        self.pending = (width if width > 0 else self.width, height if height > 0 else self.height)
        # A wl_array of native-endian uint32 state values (xdg_toplevel.state).
        self.pending_states = list(array.array("I", bytes(states)))

    def on_configure(self, xdg, serial):
        self.held[serial] = self.pending
        emit("configure", serial=serial, width=self.pending[0], height=self.pending[1],
             states=getattr(self, "pending_states", []))
        if self.automatic:
            self.ack(serial)
            self.commit()

    def on_close(self, top):
        emit("close")
        self.running = False

    def ack(self, serial):
        if serial not in self.held:
            die(f"no held configure {serial} (held: {sorted(self.held)})")
        self.xdg.ack_configure(serial)
        self.width, self.height = self.held[serial]
        # Acknowledging a configure supersedes every earlier one (xdg_surface.ack_configure).
        self.held = {s: size for s, size in self.held.items() if s > serial}
        emit("ack", serial=serial, width=self.width, height=self.height)

    def commit(self):
        stride = self.width * 4
        size = stride * self.height
        fd = os.memfd_create("heldclient-buffer", os.MFD_CLOEXEC)
        try:
            os.ftruncate(fd, size)
            data = mmap.mmap(fd, size)
            data.write(b"\x40\x80\xc0\xff" * (self.width * self.height))
            pool = self.shm.create_pool(fd, size)
            buffer = pool.create_buffer(0, self.width, self.height, stride, FORMAT_XRGB8888)
            pool.destroy()
        finally:
            os.close(fd)
        entry = [buffer, data]
        self.buffers.append(entry)

        def released(buf, entry=entry):
            buf.destroy()
            entry[1].close()
            self.buffers.remove(entry)

        buffer.dispatcher["release"] = released
        self.surface.attach(buffer, 0, 0)
        self.surface.damage_buffer(0, 0, self.width, self.height)
        self.surface.commit()
        emit("commit", width=self.width, height=self.height)

    def command(self, line):
        words = line.split()
        if words == ["hold"]:
            self.automatic = False
        elif words == ["auto"]:
            self.automatic = True
            if self.held:
                self.ack(max(self.held))
                self.commit()
        elif len(words) == 2 and words[0] == "ack" and words[1].isdigit():
            self.ack(int(words[1]))
        elif words == ["commit"]:
            self.commit()
        elif words == ["maximize"]:
            self.top.set_maximized()
        elif words == ["unmaximize"]:
            self.top.unset_maximized()
        elif words == ["quit"]:
            self.running = False
        else:
            die(f"unknown command {line!r}")
        emit("command", line=line, automatic=self.automatic)

    def run(self):
        deadline = time.monotonic() + LIFETIME
        fd = self.display.get_fd()
        pending = b""
        stdin_open = True
        while self.running:
            if time.monotonic() > deadline:
                die("lifetime limit")
            self.display.dispatch(block=False)
            self.display.flush()
            if not self.running:
                break
            watch = [fd] + ([sys.stdin.fileno()] if stdin_open else [])
            readable, _, _ = select.select(watch, [], [], 1.0)
            if fd in readable:
                self.display.read()
                self.display.dispatch(block=False)
            if stdin_open and sys.stdin.fileno() in readable:
                chunk = os.read(sys.stdin.fileno(), 4096)
                if not chunk:
                    stdin_open = False  # the scenario closed its end: keep the window as it is
                pending += chunk
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    if line.strip():
                        self.command(line.decode().strip())
        self.top.destroy()
        self.xdg.destroy()
        self.surface.destroy()
        self.shell.destroy()
        self.display.flush()
        self.display.roundtrip()
        self.display.disconnect()


def main():
    if not guarded():
        die("refused outside a tools/vsession private session")
    if len(sys.argv) not in (2, 3):
        die("usage: heldclient.py APP_ID [WIDTHxHEIGHT]")
    width, height = 430, 310
    if len(sys.argv) == 3:
        try:
            width, height = (int(v) for v in sys.argv[2].split("x"))
        except ValueError:
            die(f"bad size {sys.argv[2]!r}")
    Client(sys.argv[1], width, height).run()


if __name__ == "__main__":
    main()
