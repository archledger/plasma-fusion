#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Full-screen Qt test window: one cell per Qt::CursorShape (cursor-shape-v1 -> KWin SVG cursors).

    qtcursors.py CELLS.json

Writes the cell centres (window = screen coordinates, the window is full screen on the only
output) to CELLS.json once the window is shown, then stays open until killed.
"""
import json
import sys

from PySide6.QtCore import Qt, QTimer
from PySide6.QtWidgets import QApplication, QGridLayout, QLabel, QWidget

SHAPES = [
    ('ArrowCursor', 'default'), ('UpArrowCursor', 'up-arrow'), ('CrossCursor', 'crosshair'),
    ('WaitCursor', 'wait'), ('IBeamCursor', 'text'), ('SizeVerCursor', 'ns-resize'),
    ('SizeHorCursor', 'ew-resize'), ('SizeBDiagCursor', 'nesw-resize'), ('SizeFDiagCursor', 'nwse-resize'),
    ('SizeAllCursor', 'all-scroll'), ('SplitVCursor', 'row-resize'), ('SplitHCursor', 'col-resize'),
    ('PointingHandCursor', 'pointer'), ('ForbiddenCursor', 'not-allowed'), ('WhatsThisCursor', 'help'),
    ('BusyCursor', 'progress'), ('OpenHandCursor', 'grab'), ('ClosedHandCursor', 'grabbing'),
    ('DragCopyCursor', 'copy'), ('DragMoveCursor', 'move'), ('DragLinkCursor', 'alias'),
]


def main():
    out = sys.argv[1]
    app = QApplication(sys.argv[:1])
    w = QWidget()
    w.setWindowTitle('Cursor test (Qt)')
    # cells alternate between a light and a dark card so the outline and fill both show
    w.setStyleSheet('QWidget { background: #10142a; } QLabel { font: 600 13px "Manrope"; border-radius: 10px; }'
                    ' QLabel[tone="light"] { background: #eef0f5; color: #1b2031; }'
                    ' QLabel[tone="dark"] { background: #1f2644; color: #e8ebf4; }')
    grid = QGridLayout(w)
    grid.setContentsMargins(20, 20, 20, 20)
    grid.setSpacing(12)
    labels = []
    for i, (qt, css) in enumerate(SHAPES):
        lab = QLabel(f'{qt}\n{css}')
        lab.setAlignment(Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignBottom)
        lab.setCursor(getattr(Qt.CursorShape, qt))
        lab.setProperty('tone', 'dark' if (i // 7 + i % 7) % 2 else 'light')
        grid.addWidget(lab, i // 7, i % 7)
        labels.append((css, lab))

    def dump():
        cells = []
        for css, lab in labels:
            c = lab.geometry().center()
            cells.append({'name': css, 'x': c.x(), 'y': c.y() - 10})
        json.dump({'window': [w.width(), w.height()], 'cells': cells}, open(out, 'w'))

    w.showFullScreen()
    QTimer.singleShot(2500, dump)
    app.exec()


if __name__ == '__main__':
    main()
