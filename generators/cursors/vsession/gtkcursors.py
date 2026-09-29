#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Full-screen GTK 3 test window: one cell per CSS cursor name.

    gtkcursors.py CELLS.json

GTK 3.24 does not use cursor-shape-v1; it loads the Xcursor files itself (wayland-cursor), so
this exercises the cursors/ half of the theme. Writes the cell centres to CELLS.json once shown.
"""
import json
import sys

import gi

gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

NAMES = ['default', 'pointer', 'text', 'wait', 'progress', 'move', 'all-scroll',
         'ew-resize', 'ns-resize', 'nwse-resize', 'nesw-resize', 'n-resize', 'sw-resize', 'col-resize',
         'row-resize', 'crosshair', 'cell', 'not-allowed', 'no-drop', 'copy', 'alias',
         'help', 'context-menu', 'grab', 'grabbing', 'vertical-text', 'zoom-in', 'zoom-out']


def main():
    out = sys.argv[1]
    css = Gtk.CssProvider()
    css.load_from_data(b'window { background: #10142a; } .cell { border-radius: 10px; }'
                       b' .light { background: #eef0f5; } .light label { color: #1b2031; font-weight: 600; }'
                       b' .dark { background: #1f2644; } .dark label { color: #e8ebf4; font-weight: 600; }')
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win = Gtk.Window(title='Cursor test (GTK 3)')
    grid = Gtk.Grid(row_spacing=12, column_spacing=12, margin=20, row_homogeneous=True, column_homogeneous=True)
    win.add(grid)
    boxes = []
    for i, name in enumerate(NAMES):
        eb = Gtk.EventBox()
        eb.get_style_context().add_class('cell')
        eb.get_style_context().add_class('dark' if (i // 7 + i % 7) % 2 else 'light')
        lab = Gtk.Label(label=name, valign=Gtk.Align.END, margin_bottom=10)
        eb.add(lab)
        eb.set_hexpand(True)
        eb.set_vexpand(True)
        grid.attach(eb, i % 7, i // 7, 1, 1)
        boxes.append((name, eb))

    def set_cursors(*_):
        display = Gdk.Display.get_default()
        for name, eb in boxes:
            eb.get_window().set_cursor(Gdk.Cursor.new_from_name(display, name))

    def dump():
        cells = []
        for name, eb in boxes:
            x, y = eb.translate_coordinates(win, 0, 0)[-2:]
            a = eb.get_allocation()
            cells.append({'name': name, 'x': x + a.width // 2, 'y': y + a.height // 2 - 10})
        json.dump({'cells': cells, 'theme': Gtk.Settings.get_default().props.gtk_cursor_theme_name,
                   'size': Gtk.Settings.get_default().props.gtk_cursor_theme_size}, open(out, 'w'))
        return False

    win.connect('map-event', set_cursors)
    win.connect('destroy', Gtk.main_quit)
    win.fullscreen()
    win.show_all()
    GLib.timeout_add(2500, dump)
    Gtk.main()


if __name__ == '__main__':
    main()
