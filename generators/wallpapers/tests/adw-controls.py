#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""libadwaita (GTK 4) controls like the Controls board (test only)."""
import sys
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402


def build(app):
    win = Adw.ApplicationWindow(application=app, title='libadwaita controls')
    win.set_default_size(640, 620)
    view = Adw.ToolbarView()
    header = Adw.HeaderBar()
    menu = Gio.Menu()
    for t in ('Open', 'Open with', 'Copy', 'Rename', 'Move to Trash'):
        menu.append(t, 'app.noop')
    mb = Gtk.MenuButton(icon_name='open-menu-symbolic', menu_model=menu)
    header.pack_end(mb)
    view.add_top_bar(header)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin_top=18, margin_bottom=18,
                  margin_start=22, margin_end=22)
    row = Gtk.Box(spacing=10)
    for label, cls in (('Save changes', 'suggested-action'), ('Cancel', None), ('Learn more', 'flat'),
                       ('Delete', 'destructive-action')):
        b = Gtk.Button(label=label)
        if cls:
            b.add_css_class(cls)
        row.append(b)
        if label == 'Cancel':
            cancel = b
    box.append(row)
    grid = Gtk.Grid(column_spacing=14, row_spacing=10)
    e1 = Gtk.Entry(placeholder_text='Untitled folder', hexpand=True)
    grid.attach(e1, 0, 0, 1, 1)
    s = Gtk.SearchEntry(text='Q3-roadmap', hexpand=True)
    grid.attach(s, 1, 0, 1, 1)
    dd = Gtk.DropDown.new_from_strings(['Balanced', 'Power save', 'Performance'])
    grid.attach(dd, 0, 1, 1, 1)
    grid.attach(Gtk.SpinButton.new_with_range(0, 48, 1), 1, 1, 1, 1)
    box.append(grid)
    row = Gtk.Box(spacing=16)
    c1 = Gtk.CheckButton(label='Checked', active=True)
    row.append(c1)
    c2 = Gtk.CheckButton(label='Mixed', inconsistent=True)
    row.append(c2)
    row.append(Gtk.CheckButton(label='Off'))
    sw = Gtk.Switch(active=True, valign=Gtk.Align.CENTER)
    row.append(sw)
    row.append(Gtk.Switch(valign=Gtk.Align.CENTER))
    box.append(row)
    sc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
    sc.set_value(60)
    box.append(sc)
    pb = Gtk.ProgressBar(fraction=0.64)
    box.append(pb)
    grp = Adw.PreferencesGroup(title='Appearance')
    r = Adw.SwitchRow(title='Magnify dock icons on hover', active=True)
    grp.add(r)
    r = Adw.SwitchRow(title='Hot corner opens Overview')
    grp.add(r)
    r = Adw.ComboRow(title='Window buttons', model=Gtk.StringList.new(['Right · glyphs', 'Left · circles']))
    grp.add(r)
    box.append(grp)
    sw_ = Gtk.ScrolledWindow(vexpand=True)
    sw_.set_child(box)
    view.set_content(sw_)
    win.set_content(view)
    win.present()

    def focus():
        cancel.grab_focus()
        win.set_focus_visible(True)
        return False
    GLib.timeout_add(600, focus)
    GLib.timeout_add(2500, focus)
    if 'menu' in sys.argv:
        GLib.timeout_add(1500, lambda: (mb.popup(), False)[1])


app = Adw.Application(application_id='org.plasmafusion.AdwTest', flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect('activate', build)
act = Gio.SimpleAction.new('noop', None)
app.add_action(act)
app.run([sys.argv[0]])
