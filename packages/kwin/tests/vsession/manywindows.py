#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Opens many plain windows in one process (test use only: switcher and picker with many windows).

    manywindows.py COUNT [SECONDS]

Each window is 560x380 and titled "Document N — Notes"; the last one has a very long title to
check eliding. The process quits after SECONDS (default 120).
"""
import sys

from PySide6.QtCore import QTimer
from PySide6.QtGui import QColor, QPalette
from PySide6.QtWidgets import QApplication, QLabel, QVBoxLayout, QWidget

COLOURS = ["#2e3d73", "#f4f1ea", "#1b2031", "#3aa65b", "#e8743b", "#9b7bf0", "#0f1320", "#dfe8e2"]


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 12
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 120
    app = QApplication(sys.argv[:1])
    app.setApplicationName("notes")
    app.setDesktopFileName("notes")
    windows = []
    for n in range(count):
        w = QWidget()
        title = f"Document {n + 1}"
        if n == count - 1:
            title = "A document with a very long name that has to be cut short somewhere in the card"
        w.setWindowTitle(f"{title} — Notes")
        pal = w.palette()
        pal.setColor(QPalette.Window, QColor(COLOURS[n % len(COLOURS)]))
        w.setPalette(pal)
        w.setAutoFillBackground(True)
        layout = QVBoxLayout(w)
        label = QLabel(title)
        layout.addWidget(label)
        w.resize(560, 380)
        w.show()
        windows.append(w)
    QTimer.singleShot(int(seconds * 1000), app.quit)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
