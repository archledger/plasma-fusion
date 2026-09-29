#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""GTK 3 controls laid out like the Controls board (test only)."""
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib  # noqa: E402

win = Gtk.Window(title='GTK 3 controls')
win.set_default_size(620, 560)
outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
outer.set_border_width(22)
win.add(outer)


def section(text):
    lab = Gtk.Label(label=text.upper(), xalign=0)
    lab.get_style_context().add_class('dim-label')
    outer.pack_start(lab, False, False, 0)


section('Buttons')
row = Gtk.Box(spacing=10)
b = Gtk.Button(label='Save changes'); b.get_style_context().add_class('suggested-action'); row.pack_start(b, False, False, 0)
cancel = Gtk.Button(label='Cancel'); row.pack_start(cancel, False, False, 0)
b = Gtk.Button(label='Learn more'); b.get_style_context().add_class('flat'); row.pack_start(b, False, False, 0)
b = Gtk.Button(label='Delete'); b.get_style_context().add_class('destructive-action'); row.pack_start(b, False, False, 0)
b = Gtk.Button(label='Disabled'); b.set_sensitive(False); row.pack_start(b, False, False, 0)
outer.pack_start(row, False, False, 0)

section('Text fields and pickers')
grid = Gtk.Grid(column_spacing=14, row_spacing=10)
e1 = Gtk.Entry(); e1.set_placeholder_text('Untitled folder'); e1.set_hexpand(True); grid.attach(e1, 0, 0, 1, 1)
search = Gtk.SearchEntry(); search.set_text('Q3-roadmap'); search.set_hexpand(True); grid.attach(search, 1, 0, 1, 1)
combo = Gtk.ComboBoxText()
for t in ('Balanced', 'Power save', 'Performance'):
    combo.append_text(t)
combo.set_active(0); grid.attach(combo, 0, 1, 1, 1)
spin = Gtk.SpinButton.new_with_range(0, 48, 1); spin.set_value(12); grid.attach(spin, 1, 1, 1, 1)
outer.pack_start(grid, False, False, 0)

section('Checkboxes, radio buttons, switches')
row = Gtk.Box(spacing=16)
c1 = Gtk.CheckButton(label='Checked'); c1.set_active(True); row.pack_start(c1, False, False, 0)
c2 = Gtk.CheckButton(label='Mixed'); c2.set_inconsistent(True); row.pack_start(c2, False, False, 0)
c3 = Gtk.CheckButton(label='Off'); row.pack_start(c3, False, False, 0)
r1 = Gtk.RadioButton(label='Selected'); row.pack_start(r1, False, False, 0)
r2 = Gtk.RadioButton.new_with_label_from_widget(r1, 'Other'); row.pack_start(r2, False, False, 0)
s1 = Gtk.Switch(); s1.set_active(True); row.pack_start(s1, False, False, 0)
s2 = Gtk.Switch(); row.pack_start(s2, False, False, 0)
outer.pack_start(row, False, False, 0)

section('Slider, progress, segments')
scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1); scale.set_value(60); scale.set_draw_value(False)
outer.pack_start(scale, False, False, 0)
prog = Gtk.ProgressBar(); prog.set_fraction(0.64); outer.pack_start(prog, False, False, 0)
seg = Gtk.Box(); seg.get_style_context().add_class('linked')
for i, t in enumerate(('Day', 'Week', 'Month')):
    tb = Gtk.ToggleButton(label=t); tb.set_active(i == 1); seg.pack_start(tb, False, False, 0)
outer.pack_start(seg, False, False, 0)

nb = Gtk.Notebook()
for t in ('General', 'Display', 'Shortcuts'):
    nb.append_page(Gtk.Label(label=t + ' page'), Gtk.Label(label=t))
outer.pack_start(nb, True, True, 0)

menu = Gtk.Menu()
for t in ('Open', 'Open with', None, 'Copy', 'Rename', 'Compress', None, 'Move to Trash'):
    menu.append(Gtk.SeparatorMenuItem() if t is None else Gtk.MenuItem(label=t))
menu.get_children()[5].set_sensitive(False)
menu.show_all()

win.connect('destroy', Gtk.main_quit)
win.show_all()
cancel.grab_focus()
win.set_focus_visible(True)
if 'menu' in sys.argv:
    GLib.timeout_add(1500, lambda: (menu.popup_at_widget(cancel, 3, 1, None), False)[1])
    GLib.timeout_add(2600, lambda: (menu.select_item(menu.get_children()[3]), False)[1])
Gtk.main()
