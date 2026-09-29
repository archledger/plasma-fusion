#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""A normal (decorated) test window for the pointer over window edges, the title bar and a text
field. place.js moves it to a known geometry; the window title is how the script finds it.

    edgewin.py
"""
import sys

from PySide6.QtWidgets import QApplication, QLabel, QLineEdit, QVBoxLayout, QWidget


def main():
    app = QApplication(sys.argv[:1])
    w = QWidget()
    w.setWindowTitle('Cursor edges')
    lay = QVBoxLayout(w)
    lay.setContentsMargins(40, 40, 40, 40)
    lay.addWidget(QLabel('The pointer over the window frame, the title bar and a text field.'))
    field = QLineEdit('Text field (I-beam pointer)')
    field.setMinimumHeight(40)
    lay.addWidget(field)
    lay.addStretch(1)
    w.resize(720, 360)
    w.show()
    app.exec()


if __name__ == '__main__':
    main()
