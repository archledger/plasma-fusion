#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Keys on a release VM's keyboard, with screenshots in between, through QEMU's QMP socket.

  vm-keys.py QMP_SOCKET STEP...

STEP: down:KEY, up:KEY, tap:KEY (QEMU's key names: alt, tab, esc, meta_l, ...), sleep:SECONDS,
shot:FILE.png. A switcher is on the screen only while its modifier is held, which a shortcut
called over the bus cannot do: down:alt tap:tab sleep:2 shot:switcher.png up:alt. Every key
still down at the end, or when a step fails, is released.
"""

import json
import os
import socket
import sys
import time


class Qmp:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(20)
        self.sock.connect(path)
        self.buffer = b""
        self.read()  # the greeting
        self.command("qmp_capabilities")

    def read(self):
        while b"\n" not in self.buffer:
            data = self.sock.recv(65536)
            if not data:
                raise RuntimeError("QMP closed the connection")
            self.buffer += data
        line, self.buffer = self.buffer.split(b"\n", 1)
        return json.loads(line)

    def command(self, name, **arguments):
        message = {"execute": name}
        if arguments:
            message["arguments"] = arguments
        self.sock.sendall(json.dumps(message).encode() + b"\n")
        while True:
            answer = self.read()
            if "error" in answer:
                raise RuntimeError("%s: %s" % (name, answer["error"].get("desc", answer["error"])))
            if "return" in answer:
                return answer["return"]

    def key(self, name, down):
        event = {"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": name}}}
        self.command("input-send-event", events=[event])


def run(qmp, steps):
    held = []
    try:
        for step in steps:
            action, _, value = step.partition(":")
            if action == "down":
                qmp.key(value, True)
                held.append(value)
            elif action == "up":
                qmp.key(value, False)
                if value in held:
                    held.remove(value)
            elif action == "tap":
                qmp.key(value, True)
                time.sleep(0.08)
                qmp.key(value, False)
            elif action == "sleep":
                time.sleep(float(value))
            elif action == "shot":
                path = os.path.abspath(value)
                qmp.command("screendump", filename=path, format="png")
                if not (os.path.isfile(path) and os.path.getsize(path) > 0):
                    raise RuntimeError("no screenshot at " + path)
            else:
                raise SystemExit("vm-keys: unknown step " + step)
            time.sleep(0.12)
    finally:
        for name in reversed(held):
            try:
                qmp.key(name, False)
            except (OSError, RuntimeError):
                pass


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__.strip())
    try:
        run(Qmp(sys.argv[1]), sys.argv[2:])
    except (OSError, RuntimeError, ValueError) as error:
        raise SystemExit("vm-keys: " + str(error))


if __name__ == "__main__":
    main()
