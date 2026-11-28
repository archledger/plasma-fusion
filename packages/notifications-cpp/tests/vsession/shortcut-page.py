#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

"""Check the real Shortcuts KCM through the accessibility bus of the private session."""

import os
import sys
import time

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi, GLib  # noqa: E402

ACTION = "Focus notification banner"


def nodes(root, depth=0):
    if depth > 24:
        return
    yield root
    for index in range(root.get_child_count()):
        child = root.get_child_at_index(index)
        if child is not None:
            yield from nodes(child, depth + 1)


def visible(node):
    return node.get_state_set().contains(Atspi.StateType.SHOWING)


def application(pid):
    desktop = Atspi.get_desktop(0)
    for index in range(desktop.get_child_count()):
        app = desktop.get_child_at_index(index)
        if app is not None and app.get_process_id() == pid:
            return app
    return None


def search_box(app):
    for node in nodes(app):
        if visible(node) and node.is_editable_text():
            return node
    return None


def visible_binding(visible_nodes):
    for node in visible_nodes:
        name = node.get_name()
        if not name.startswith((f"{ACTION}:", f"Editing shortcut: {ACTION}:")):
            continue
        # The collapsed delegate advertises its sequence in its own name. The expanded delegate
        # exposes the key editor as a child instead. Don't match a key from another shortcut.
        for child in nodes(node):
            if not visible(child):
                continue
            label = child.get_name().strip()
            if all(key in label for key in ("Meta", "Ctrl", "Alt")) and any(
                key in label for key in ("PgDown", "Page Down", "PageDown")
            ):
                return label
    return None


def main():
    if os.environ.get("XDG_RUNTIME_DIR") != os.environ.get("PFV", "<not a session>") + "/run":
        return 2
    pid = int(sys.argv[1])
    expected = sys.argv[2]
    Atspi.init()
    deadline = time.monotonic() + 10
    entered = False
    listing = []
    while time.monotonic() < deadline:
        try:
            app = application(pid)
            if app is not None:
                editor = search_box(app)
                if expected == "search" and not entered and editor is not None:
                    entered = editor.get_editable_text_iface().set_text_contents(ACTION)
                else:
                    visible_nodes = [node for node in nodes(app) if visible(node)]
                    listing = [node.get_name() for node in visible_nodes]
                    if expected == "search" and entered and "Plasma Workspace" in listing:
                        return 0
                    if expected == "bound":
                        binding = visible_binding(visible_nodes)
                        if binding:
                            print(f"{ACTION}: {binding}")
                            return 0
        except (GLib.Error, TypeError):
            pass
        time.sleep(0.25)
    for name in listing:
        print(name, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
