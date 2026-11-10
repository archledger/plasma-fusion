#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The real switcher clears hidden preview assignments without destroying its card windows.

Run on a private bus with QT_QPA_PLATFORM=offscreen, passing a staged packages/kwin layout
(switcher/<id>) as the argument, as keytest.py does. The KWin stub models client assignment.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import shiboken6
from PySide6.QtCore import QCoreApplication, QEvent, QMetaObject, Qt, QUrl
from PySide6.QtGui import QGuiApplication, QKeyEvent
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

from render import I18n

CAPABILITIES = {
    "missing": (None, False),
    "zero": ("0", False),
    "negative": ("-1", False),
    "version-one": ("1", True),
    "future-version": ("2", True),
    "fractional": ("1.5", False),
    "boolean": ("true", False),
    "string": ('"1"', False),
    "null": ("null", False),
    "nan": ("NaN", False),
    "infinity": ("Infinity", False),
}


def preview_items(switcher):
    # Visual parenting and QObject ownership differ for dynamically created delegates.
    items = []
    pending = [window.contentItem() for window in switcher.findChildren(QQuickWindow)]
    while pending:
        item = pending.pop()
        items.append(item)
        pending.extend(item.childItems())
    previews = [obj for obj in items if obj.metaObject().indexOfProperty("wId") >= 0]
    assert len(previews) == 5, f"expected five retained preview objects, got {len(previews)}"
    return previews


def active_previews(switcher):
    previews = preview_items(switcher)
    # The stand-in resolves either native assignment API to the same represented client.
    values = [obj.property("win") for obj in previews]
    return sum(bool(value.toVariant() if hasattr(value, "toVariant") else value) for value in values)


def preview_identity(switcher):
    return {shiboken6.getCppPointer(item)[0] for item in preview_items(switcher)}


def exercise_case(stubs, releases_hidden):
    app = QGuiApplication(sys.argv[:1])
    engine = QQmlApplicationEngine()
    here = os.path.dirname(os.path.abspath(__file__))
    engine.addImportPath(str(stubs))
    i18n = I18n()
    engine.rootContext().setContextObject(i18n)
    for key, value in dict(count=5, otherDesktop=2, allDesktops=True, current=1, dark=True).items():
        engine.rootContext().setContextProperty(key, value)
    engine.rootContext().setContextProperty("packagesRoot", os.path.abspath(sys.argv[1]))
    engine.load(QUrl.fromLocalFile(os.path.join(here, "switcher-harness.qml")))
    assert engine.rootObjects(), "switcher harness did not load"
    switcher = engine.rootObjects()[0].property("switcher")
    assert switcher is not None, "switcher did not instantiate"
    QCoreApplication.processEvents()
    card = switcher.findChild(QQuickWindow)
    assert card is not None, "card window missing"
    retained_previews = preview_identity(switcher)
    expected_visible = 3 if releases_hidden else 5
    assert active_previews(switcher) == expected_visible, "wrong filtered preview assignments"

    QCoreApplication.sendEvent(card, QKeyEvent(QEvent.KeyPress, Qt.Key_A, Qt.NoModifier, "a"))
    QCoreApplication.processEvents()
    assert active_previews(switcher) == 5, "All workspaces did not restore every preview"
    assert preview_identity(switcher) == retained_previews, "workspace filtering recreated preview objects"
    switcher.setProperty("visible", False)
    QCoreApplication.processEvents()
    assert active_previews(switcher) == (0 if releases_hidden else 5), "wrong closed preview assignments"
    assert switcher.findChild(QQuickWindow) is card, "closing destroyed the reusable card window"
    assert preview_identity(switcher) == retained_previews, "closing destroyed the reusable previews"

    QMetaObject.invokeMethod(switcher, "aboutToShow", Qt.DirectConnection)
    switcher.setProperty("visible", True)
    QCoreApplication.processEvents()
    assert active_previews(switcher) == expected_visible, "reopening did not restore expected previews"
    assert preview_identity(switcher) == retained_previews, "reopening recreated preview objects"
    print(f"PASS: {sys.argv[2]} capability; assignments, filtering, reopen and object identity")
    app.quit()


def main():
    if len(sys.argv) == 2:
        # Each engine gets a distinct module instance and a fresh Qt process.
        for name in CAPABILITIES:
            subprocess.run([sys.executable, __file__, sys.argv[1], name], check=True)
        print(f"PASS: {len(CAPABILITIES)} thumbnail capability cases")
        return
    expression, releases_hidden = CAPABILITIES[sys.argv[2]]
    with tempfile.TemporaryDirectory(prefix="thumbnail-capability-") as directory:
        stubs = Path(directory) / "stubs"
        shutil.copytree(Path(__file__).resolve().parent / "stubs", stubs)
        if expression is not None:
            thumbnail = stubs / "org/kde/kwin/WindowThumbnail.qml"
            text = thumbnail.read_text()
            marker = "    id: thumb\n"
            assert text.count(marker) == 1
            thumbnail.write_text(text.replace(
                marker, marker + "    readonly property var plasmaFusionThumbnailSourceLifecycleVersion: "
                + expression + "\n", 1))
        exercise_case(stubs, releases_hidden)


if __name__ == "__main__":
    main()
