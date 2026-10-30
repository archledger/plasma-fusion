#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The real switcher clears hidden preview assignments without destroying its card windows.

Run on a private bus with QT_QPA_PLATFORM=offscreen, passing a staged packages/kwin layout
(switcher/<id>) as the argument, as keytest.py does. The KWin stub models client assignment.
"""
import os
import sys

import shiboken6
from PySide6.QtCore import QCoreApplication, QEvent, QMetaObject, Qt, QUrl
from PySide6.QtGui import QGuiApplication, QKeyEvent
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

from render import I18n


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
    values = [obj.property("wId") for obj in previews]
    return sum(bool(value.toVariant() if hasattr(value, "toVariant") else value) for value in values)


def preview_identity(switcher):
    return {shiboken6.getCppPointer(item)[0] for item in preview_items(switcher)}


def main():
    app = QGuiApplication(sys.argv[:1])
    engine = QQmlApplicationEngine()
    here = os.path.dirname(os.path.abspath(__file__))
    engine.addImportPath(os.path.join(here, "stubs"))
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
    assert active_previews(switcher) == 3, "filtered-out cards retain thumbnail clients"

    QCoreApplication.sendEvent(card, QKeyEvent(QEvent.KeyPress, Qt.Key_A, Qt.NoModifier, "a"))
    QCoreApplication.processEvents()
    assert active_previews(switcher) == 5, "All workspaces did not restore every preview"
    assert preview_identity(switcher) == retained_previews, "workspace filtering recreated preview objects"
    switcher.setProperty("visible", False)
    QCoreApplication.processEvents()
    assert active_previews(switcher) == 0, "closed switcher retains thumbnail clients"
    assert switcher.findChild(QQuickWindow) is card, "closing destroyed the reusable card window"
    assert preview_identity(switcher) == retained_previews, "closing destroyed the reusable previews"

    QMetaObject.invokeMethod(switcher, "aboutToShow", Qt.DirectConnection)
    switcher.setProperty("visible", True)
    QCoreApplication.processEvents()
    assert active_previews(switcher) == 3, "reopening did not restore current-workspace previews"
    assert preview_identity(switcher) == retained_previews, "reopening recreated preview objects"
    print("PASS: filtered/closed preview assignments cleared; All workspaces and reopen restore them")
    app.quit()


if __name__ == "__main__":
    main()
