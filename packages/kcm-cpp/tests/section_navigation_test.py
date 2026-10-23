#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the real responsive settings navigation without changing desktop settings."""

import os
from pathlib import Path
import sys
import subprocess
import tempfile
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QObject, QPoint, QPointF, QUrl, Qt
from PySide6.QtGui import QAccessible, QAccessibleActionInterface, QGuiApplication, QWheelEvent
from PySide6.QtQml import QQmlApplicationEngine, QQmlExpression, qmlContext
from PySide6.QtTest import QTest
from PySide6.QtQuick import QQuickWindow
from shiboken6 import Shiboken

UI = Path(__file__).resolve().parents[1] / "src/ui"
CHECKS = 0
KDE_STYLE = "--kde-style" in sys.argv


def check(condition, message):
    global CHECKS
    if not condition:
        raise AssertionError(message)
    CHECKS += 1
    print("PASS", message)


def main():
    os.environ["QT_QUICK_CONTROLS_STYLE"] = "org.kde.desktop" if KDE_STYLE else "Basic"
    app = QGuiApplication(sys.argv[:1])
    engine = QQmlApplicationEngine()
    warnings = []
    engine.warnings.connect(lambda items: warnings.extend(item.toString() for item in items))
    with tempfile.TemporaryDirectory(prefix="pf-kcm-navigation-") as directory:
        path = Path(directory) / "test.qml"
        path.write_text('''import QtQuick
import QtQuick.Controls
import "%s" as UI
ApplicationWindow {
    width: 1200; height: 180; visible: true
    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true
    property int selected: 0
    property bool pendingEdit: true
    UI.SectionNavigation {
        objectName: "navigation"
        width: parent.width
        labels: ["Appearance", "Desktop", "Windows & Input", "Power & Session", "Backup & Reset"]
        accessibleName: "Settings section"
        currentIndex: selected
        onSelectionRequested: index => selected = index
    }
}
''' % QUrl.fromLocalFile(str(UI)).toString())
        engine.load(QUrl.fromLocalFile(str(path)))
        check(bool(engine.rootObjects()), "navigation component loads: " + "; ".join(warnings))
        root = engine.rootObjects()[0]
        window = Shiboken.wrapInstance(Shiboken.getCppPointer(root)[0], QQuickWindow)
        nav = root.findChild(QObject, "navigation")

        def visual_item(name):
            items = [window.contentItem()]
            while items:
                item = items.pop()
                if item.objectName() == name:
                    return item
                items.extend(item.childItems())
            return None

        def settle(predicate):
            until = time.monotonic() + 3
            while time.monotonic() < until:
                app.processEvents()
                if predicate():
                    return
                QTest.qWait(10)
            raise AssertionError("navigation did not settle")

        settle(lambda: nav.property("width") == 1200)
        tabs = root.findChild(QObject, "sectionTabs")
        combo = root.findChild(QObject, "sectionCombo")
        check(not nav.property("compact"), "wide layout shows tabs")
        check(tabs.property("count") == 5, "five destinations")
        check(tabs.property("visible") and not combo.property("visible"), "one navigation surface visible")
        natural_width = sum(visual_item("sectionTab" + str(i)).property("implicitWidth") for i in range(5))
        natural_width += tabs.property("leftPadding") + tabs.property("rightPadding") + 4 * tabs.property("spacing")
        window.resize(int(natural_width) + 2, 180)
        settle(lambda: nav.property("width") == int(natural_width) + 2)
        check(not nav.property("compact"), "tabs remain visible when their natural widths fit")
        window.resize(1200, 180)
        first = visual_item("sectionTab0")
        check(first is not None, "first tab is discoverable in the visual tree")
        first.forceActiveFocus()
        QTest.keyClick(window, Qt.Key.Key_Right)
        settle(lambda: root.property("selected") == 1)
        check(root.property("pendingEdit"), "keyboard tab switch keeps pending state")
        root.setProperty("selected", 4)
        settle(lambda: tabs.property("currentIndex") == 4)
        check(nav.property("currentIndex") == 4, "programmatic selection stays synchronized")
        accessible = QAccessible.queryAccessibleInterface(visual_item("sectionTab2"))
        action = accessible.actionInterface()
        check(QAccessibleActionInterface.pressAction() in action.actionNames(), "tabs expose an accessible press action")
        action.doAction(QAccessibleActionInterface.pressAction())
        settle(lambda: root.property("selected") == 2)
        check(tabs.property("currentIndex") == 2, "accessible activation selects the section")
        root.setProperty("selected", 4)
        settle(lambda: tabs.property("currentIndex") == 4)

        window.resize(320, 180)
        settle(lambda: nav.property("compact"))
        check(combo.property("visible") and not tabs.property("visible"), "narrow layout uses the labelled selector")
        check(combo.property("currentIndex") == 4, "responsive switch keeps selected section")
        active = window.activeFocusItem()
        check(active is not None and active.isVisible() and active.isEnabled(),
              "resizing never leaves focus on hidden navigation")
        combo.forceActiveFocus()
        QTest.keyClick(window, Qt.Key.Key_Home)
        settle(lambda: root.property("selected") == 0)
        check(root.property("pendingEdit"), "compact navigation keeps pending state")

        # An open menu receives keys differently from the closed ComboBox in the KDE style.
        popup_visible = QQmlExpression(qmlContext(combo), combo, "popup.visible")
        QTest.keyClick(window, Qt.Key.Key_Space)
        settle(lambda: popup_visible.evaluate()[0])
        key_window = app.focusWindow() or window
        QTest.keyClick(key_window, Qt.Key.Key_Down)
        QTest.keyClick(key_window, Qt.Key.Key_Down)
        QTest.keyClick(key_window, Qt.Key.Key_Return)
        settle(lambda: root.property("selected") == 2)
        settle(lambda: not popup_visible.evaluate()[0])
        check(root.property("pendingEdit"), "open selector keyboard activation keeps pending state")
        root.setProperty("selected", 0)
        settle(lambda: combo.property("currentIndex") == 0)
        QTest.mouseClick(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier,
                         QPoint(int(combo.width() / 2), int(combo.height() / 2)))
        settle(lambda: popup_visible.evaluate()[0])
        key_window = app.focusWindow() or window
        QTest.keyClick(key_window, Qt.Key.Key_Down)
        QTest.keyClick(key_window, Qt.Key.Key_Escape)
        settle(lambda: not popup_visible.evaluate()[0])
        check(root.property("selected") == 0, "Escape cancels a pointer-opened selector without switching")

        QTest.keyClick(window, Qt.Key.Key_Space)
        settle(lambda: popup_visible.evaluate()[0])
        window.resize(1200, 180)
        settle(lambda: not nav.property("compact"))
        settle(lambda: not popup_visible.evaluate()[0])
        check(window.activeFocusItem() is first, "widening an open selector closes it and focuses its tab")
        check(tabs.property("currentIndex") == 0, "returning to tabs retains selection")
        app.setLayoutDirection(Qt.LayoutDirection.RightToLeft)
        app.processEvents()
        first.forceActiveFocus()
        QTest.keyClick(window, Qt.Key.Key_Left)
        settle(lambda: root.property("selected") == 1)
        check(root.property("selected") == 1, "RTL arrow navigation follows reading direction")

        if not KDE_STYLE:
            # Basic follows the inherited control font. KDE instead reads its platform font;
            # section_page_test exercises that real path with a private kdeglobals file.
            old_font = app.font()
            larger_font = app.font()
            larger_font.setPointSizeF(old_font.pointSizeF() * 2)
            old_minimum = nav.property("minimumTabsWidth")
            root.setProperty("font", larger_font)
            settle(lambda: nav.property("minimumTabsWidth") > old_minimum)
            between_widths = int((old_minimum + nav.property("minimumTabsWidth")) / 2)
            window.resize(between_widths, 180)
            settle(lambda: nav.property("compact"))
            check(combo.property("currentIndex") == 1, "larger text keeps the selected section")
            window.resize(2000, 180)
            settle(lambda: not nav.property("compact"))
            check(tabs.property("currentIndex") == 1, "wide large-text navigation restores tabs")
            for index in range(5):
                tab = visual_item("sectionTab" + str(index))
                label = tab.property("contentItem")
                check(label.property("width") + 1 >= label.property("implicitWidth"),
                      f"large-text tab {index} is not truncated")
            root.setProperty("font", old_font)
        app.setLayoutDirection(Qt.LayoutDirection.LeftToRight)
        window.resize(1200, 180)
        root.setProperty("selected", 0)
        settle(lambda: not nav.property("compact") and tabs.property("currentIndex") == 0)
        position = QPointF(25, 10)
        if KDE_STYLE:
            wheel = QWheelEvent(position, QPointF(window.mapToGlobal(position.toPoint())),
                                QPoint(), QPoint(0, -120), Qt.MouseButton.NoButton,
                                Qt.KeyboardModifier.NoModifier, Qt.ScrollPhase.NoScrollPhase, False)
            QGuiApplication.sendEvent(window, wheel)
        else:
            first.forceActiveFocus()
            QTest.keyClick(window, Qt.Key.Key_Right)
        settle(lambda: root.property("selected") == 1)
        check(tabs.property("currentIndex") == 1, "KDE wheel navigation selects the next tab")
        window.resize(320, 180)
        settle(lambda: nav.property("compact"))
        combo.forceActiveFocus()
        QTest.keyClick(window, Qt.Key.Key_End)
        settle(lambda: root.property("selected") == 4)
        window.resize(1200, 180)
        settle(lambda: not nav.property("compact"))
        check(tabs.property("currentIndex") == 4, "wheel then compact selection keeps the wide tab synchronized")
        check(not warnings, "no QML warnings: " + "; ".join(warnings))
        window.close()
        print(f"section_navigation_test ({'KDE' if KDE_STYLE else 'Basic'}): {CHECKS} checks passed")


if __name__ == "__main__":
    main()
    if not KDE_STYLE:
        subprocess.run([sys.executable, __file__, "--kde-style"], check=True)
