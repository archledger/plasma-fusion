#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Parse the Plasma Fusion GTK CSS with GTK's own parser (no display is needed).

    check_css.py 3.0|4.0 FILE...

Exit status 1 on a parse error, 0 when every file parses, 2 when PyGObject or that GTK version
is not installed (the build then skips the check). Named colours are resolved only when a widget
is styled, so the files are checked on their own, without colors.css.
"""
import sys


def main(argv):
    ver, files = argv[0], argv[1:]
    try:
        import gi
        gi.require_version('Gtk', ver)
        from gi.repository import GLib, Gtk
    except (ImportError, ValueError, AttributeError) as e:
        # AttributeError: a 'gi' namespace directory left by another package, without PyGObject
        print('GTK %s not available (%s): check skipped' % (ver, e))
        return 2
    errors = []
    for path in files:
        provider = Gtk.CssProvider()

        def on_error(_provider, section, error, path=path):
            if ver == '4.0':
                line = section.get_start_location().lines + 1
            else:
                line = section.get_start_line() + 1
            errors.append('%s:%d: %s' % (path, line, error.message))

        provider.connect('parsing-error', on_error)
        with open(path, encoding='utf-8') as f:
            data = f.read()
        try:
            if ver == '4.0':
                provider.load_from_string(data)
            else:
                provider.load_from_data(data.encode('utf-8'))
        except GLib.Error as e:
            errors.append('%s: %s' % (path, e.message))
    for e in errors:
        print(e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
