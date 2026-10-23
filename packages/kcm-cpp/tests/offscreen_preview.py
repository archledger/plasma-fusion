#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test tooling (not installed): render the module's QML offscreen with a stand-in for the C++
module object, to check the layout against the board without a Plasma session.

    tests/offscreen_preview.py OUT.png [dark|light] [--state key=value ...] [--width 468] [--height 560] [--font-pt 9.75] [--report]
                               [--open-dropdown N]

Uses the system Qt (PySide6 6.11 = Plasma's Qt), Kirigami, KCMUtils QML and the KDE platform
theme with a private XDG_CONFIG_HOME whose kdeglobals holds the Plasma Fusion colour scheme and
fonts (packages/color-schemes). Prints the window's QML warnings. --state sets values of the
stand-in module (every property of PlasmaFusionKcm, for example style, glass, tabletMode,
shellRunning, dockAvailable, powerCritical, errorText, infoText). The page's QML and the shared
packages/common/FusionMetrics.qml are copied into one directory first, as the module's
resources hold them. --report prints, once the page is laid out, where its content column is
("REPORT {json}": its x and width in the page's content item, that item's width, and its x and
width in the window).
Environment: PFKM_TMP (directory for the private configuration, default the system temp
directory), PFKM_THEME (Qt platform theme, default kde).
"""
import argparse
import configparser
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
UI = os.path.join(HERE, "..", "src", "ui")
COMMON = os.path.join(ROOT, "packages", "common")


def write_kdeglobals(config_home, variant, font_pt=9.75):
    scheme = "PlasmaFusionDark" if variant == "dark" else "PlasmaFusionLight"
    src = os.path.join(ROOT, "packages", "color-schemes", scheme + ".colors")
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    cp.read(src)
    lines = ["[General]", "ColorScheme=" + scheme,
             "font=Manrope,%g,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0" % font_pt, "",
             "[KDE]", "widgetStyle=Breeze", ""]
    for section in cp.sections():
        if section.startswith("Colors:") or section.startswith("WM"):
            lines.append("[%s]" % section.replace(":Inactive", "][Inactive"))
            for k, v in cp.items(section):
                lines.append("%s=%s" % (k, v))
            lines.append("")
    with open(os.path.join(config_home, "kdeglobals"), "w") as f:
        f.write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("variant", nargs="?", default="dark")
    ap.add_argument("--state", nargs="*", default=[])
    ap.add_argument("--width", type=int, default=468)
    ap.add_argument("--height", type=int, default=560)
    ap.add_argument("--font-pt", type=float, default=9.75, help="UI font size (the text scale is pt / 9.75)")
    ap.add_argument("--report", action="store_true", help="print where the page's content column is")
    ap.add_argument("--navigation", action="store_true", help="report section navigation and visible section titles")
    ap.add_argument("--section", type=int, default=None, help="select a settings section before reporting")
    ap.add_argument("--section-roundtrip", action="store_true", help="visit every section before reporting")
    ap.add_argument("--scroll-roundtrip", action="store_true", help="leave and restore a scrolled section")
    ap.add_argument("--rapid-switch", action="store_true", help="check saved scroll offsets during same-turn navigation")
    ap.add_argument("--focus-switch", action="store_true", help="switch sections while a setting has keyboard focus")
    ap.add_argument("--open-dropdown", type=int, default=-1,
                    help="open the Nth drop-down's list (0: the first) and print where it is (REPORT_DROPDOWN)")
    ap.add_argument("--gestures", action="store_true",
                    help="print the touchpad gesture rows: label, choice and note, the one-row switch and the"
                         " stand-in module's values (REPORT_GESTURES)")
    ap.add_argument("--rows", action="store_true",
                    help="print the page's choice and switch rows (text, choice or state, labels, note) and the stand-in"
                         " module's dock values (REPORT_ROWS)")
    ap.add_argument("--act", action="append", default=[], metavar="ROW[=N]",
                    help="first do what a click does on the row with that text: a switch row toggles, a choice row"
                         " picks its Nth choice (repeatable)")
    ap.add_argument("--key-dropdown", nargs=2, metavar=("N", "KEY"),
                    help="first give the Nth drop-down the focus and press KEY in it (Qt's key name: Down, Up, End)")
    args = ap.parse_args()

    config_home = tempfile.mkdtemp(prefix="pfkm-cfg-", dir=os.environ.get("PFKM_TMP"))
    write_kdeglobals(config_home, args.variant, args.font_pt)
    os.environ["XDG_CONFIG_HOME"] = config_home
    os.environ["QT_QPA_PLATFORM"] = "offscreen"
    os.environ.setdefault("QT_QUICK_BACKEND", "software")
    os.environ["QT_QPA_PLATFORMTHEME"] = os.environ.get("PFKM_THEME", "kde")
    os.environ["QT_QUICK_CONTROLS_STYLE"] = "org.kde.desktop"
    fonts = os.path.join(ROOT, "fonts")

    from PySide6.QtCore import QObject, Property, Signal, Slot, QUrl, QTimer
    from PySide6.QtGui import QGuiApplication, QColor, QFontDatabase
    from PySide6.QtQml import QQmlApplicationEngine

    app = QGuiApplication(sys.argv)
    for sub in ("manrope/static", "spacegrotesk/static"):
        d = os.path.join(fonts, sub)
        for f in sorted(os.listdir(d)):
            QFontDatabase.addApplicationFont(os.path.join(d, f))

    state = {"style": 1, "accentMode": 0, "accentColor": "#00000000", "buttonStyle": 0,
             "systemMeters": False, "metersAvailable": True,
             "magnify": True, "globalMenu": True, "hotCorner": False, "shellLoading": False, "shellRunning": True,
             "dockAvailable": True, "topBarAvailable": True, "topBarHidingAvailable": True, "decorationInstalled": False,
             "fusionDecoration": False,
             "errorText": "", "infoText": "",
             "snapTrigger": 0, "glass": 0, "highContrast": False, "reduceMotion": False, "magnifiedSize": 62, "dockSize": 1,
             "dockPosition": 0, "groupWindows": True,
             "solidTopBar": True, "topBarAutoHide": False, "everyScreen": True, "everyDock": False, "desktopIcons": True, "iconSize": 2, "dndBehavior": 0,
             "lighterOnCritical": True, "tabletMode": 0, "tabletApps": 0, "tabletDock": 0, "keyboardPolicy": 0,
             "edgeLeft": False, "edgeRight": False, "homeIndicator": True,
             "launcherAvailable": True, "launcherRecentFiles": True, "launcherRecentApps": True, "launcherPlaces": True,
             "launcherRecentFilesMixed": False, "launcherRecentAppsMixed": False, "launcherPlacesMixed": False,
             "fileContentIndexing": True,
             "iconsMode": 1, "lockNotifications": True, "lockNotificationSummaries": False,
             "quickSettingsAvailable": True, "folderAvailable": True, "highContrastAvailable": True,
             "previousDesktopAvailable": True, "topBarScriptAvailable": True, "tabletModeAvailable": True,
             "tabletModeActive": False, "powerCritical": False, "fusionLookAndFeel": True, "busy": False,
             "settingsFileAvailable": True, "needsSave": False,
             "gestureSwipeUp": 1, "gestureSwipeDown": 2, "gestureSwipeLeft": 0, "gestureSwipeRight": 0,
             "gesturePinchIn": 5, "gesturePinchOut": 2, "desktopsInOneRow": True,
             "gestureSidewaysShared": False, "gestureUpDownShared": False, "snapScriptOn": True}
    for kv in args.state:
        k, v = kv.split("=", 1)
        cur = state[k]
        state[k] = (v == "true") if isinstance(cur, bool) else int(v) if isinstance(cur, int) else v

    class Kcm(QObject):
        changed = Signal()

        def __init__(self):
            super().__init__()
            self.s = dict(state)

        def _get(name):
            return lambda self: self.s[name]

        def _set(name):
            def setter(self, v):
                self.s[name] = v
                self.changed.emit()
            return setter

        name = Property(str, lambda self: "Plasma Fusion", constant=True)
        style = Property(int, _get("style"), _set("style"), notify=changed)
        accentMode = Property(int, _get("accentMode"), notify=changed)
        accentColor = Property(QColor, lambda self: QColor(self.s["accentColor"]), notify=changed)
        wallpaperColor = Property(QColor, lambda self: QColor(self.s["accentColor"]), notify=changed)
        buttonStyle = Property(int, _get("buttonStyle"), _set("buttonStyle"), notify=changed)
        magnify = Property(bool, _get("magnify"), _set("magnify"), notify=changed)
        globalMenu = Property(bool, _get("globalMenu"), _set("globalMenu"), notify=changed)
        hotCorner = Property(bool, _get("hotCorner"), _set("hotCorner"), notify=changed)
        systemMeters = Property(bool, _get("systemMeters"), _set("systemMeters"), notify=changed)
        metersAvailable = Property(bool, _get("metersAvailable"), notify=changed)
        shellLoading = Property(bool, _get("shellLoading"), notify=changed)
        shellRunning = Property(bool, _get("shellRunning"), notify=changed)
        dockAvailable = Property(bool, _get("dockAvailable"), notify=changed)
        topBarAvailable = Property(bool, _get("topBarAvailable"), notify=changed)
        topBarHidingAvailable = Property(bool, _get("topBarHidingAvailable"), notify=changed)
        decorationInstalled = Property(bool, _get("decorationInstalled"), notify=changed)
        fusionDecoration = Property(bool, _get("fusionDecoration"), notify=changed)
        errorText = Property(str, _get("errorText"), notify=changed)
        infoText = Property(str, _get("infoText"), notify=changed)
        snapTrigger = Property(int, _get("snapTrigger"), _set("snapTrigger"), notify=changed)
        glass = Property(int, _get("glass"), _set("glass"), notify=changed)
        highContrast = Property(bool, _get("highContrast"), _set("highContrast"), notify=changed)
        reduceMotion = Property(bool, _get("reduceMotion"), _set("reduceMotion"), notify=changed)
        iconsMode = Property(int, _get("iconsMode"), _set("iconsMode"), notify=changed)
        fileContentIndexing = Property(bool, _get("fileContentIndexing"), _set("fileContentIndexing"), notify=changed)
        lockNotifications = Property(bool, _get("lockNotifications"), _set("lockNotifications"), notify=changed)
        lockNotificationSummaries = Property(bool, _get("lockNotificationSummaries"), _set("lockNotificationSummaries"), notify=changed)
        magnifiedSize = Property(int, _get("magnifiedSize"), _set("magnifiedSize"), notify=changed)
        dockSize = Property(int, _get("dockSize"), _set("dockSize"), notify=changed)
        dockPosition = Property(int, _get("dockPosition"), _set("dockPosition"), notify=changed)
        groupWindows = Property(bool, _get("groupWindows"), _set("groupWindows"), notify=changed)
        solidTopBar = Property(bool, _get("solidTopBar"), _set("solidTopBar"), notify=changed)
        topBarAutoHide = Property(bool, _get("topBarAutoHide"), _set("topBarAutoHide"), notify=changed)
        everyScreen = Property(bool, _get("everyScreen"), _set("everyScreen"), notify=changed)
        everyDock = Property(bool, _get("everyDock"), _set("everyDock"), notify=changed)
        desktopIcons = Property(bool, _get("desktopIcons"), _set("desktopIcons"), notify=changed)
        iconSize = Property(int, _get("iconSize"), _set("iconSize"), notify=changed)
        dndBehavior = Property(int, _get("dndBehavior"), _set("dndBehavior"), notify=changed)
        lighterOnCritical = Property(bool, _get("lighterOnCritical"), _set("lighterOnCritical"), notify=changed)
        tabletMode = Property(int, _get("tabletMode"), _set("tabletMode"), notify=changed)
        tabletApps = Property(int, _get("tabletApps"), _set("tabletApps"), notify=changed)
        tabletDock = Property(int, _get("tabletDock"), _set("tabletDock"), notify=changed)
        keyboardPolicy = Property(int, _get("keyboardPolicy"), _set("keyboardPolicy"), notify=changed)
        edgeLeft = Property(bool, _get("edgeLeft"), _set("edgeLeft"), notify=changed)
        edgeRight = Property(bool, _get("edgeRight"), _set("edgeRight"), notify=changed)
        homeIndicator = Property(bool, _get("homeIndicator"), _set("homeIndicator"), notify=changed)
        launcherAvailable = Property(bool, _get("launcherAvailable"), notify=changed)
        launcherRecentFiles = Property(bool, _get("launcherRecentFiles"), _set("launcherRecentFiles"), notify=changed)
        launcherRecentApps = Property(bool, _get("launcherRecentApps"), _set("launcherRecentApps"), notify=changed)
        launcherPlaces = Property(bool, _get("launcherPlaces"), _set("launcherPlaces"), notify=changed)
        launcherRecentFilesMixed = Property(bool, _get("launcherRecentFilesMixed"), notify=changed)
        launcherRecentAppsMixed = Property(bool, _get("launcherRecentAppsMixed"), notify=changed)
        launcherPlacesMixed = Property(bool, _get("launcherPlacesMixed"), notify=changed)
        quickSettingsAvailable = Property(bool, _get("quickSettingsAvailable"), notify=changed)
        folderAvailable = Property(bool, _get("folderAvailable"), notify=changed)
        highContrastAvailable = Property(bool, _get("highContrastAvailable"), notify=changed)
        previousDesktopAvailable = Property(bool, _get("previousDesktopAvailable"), notify=changed)
        topBarScriptAvailable = Property(bool, _get("topBarScriptAvailable"), notify=changed)
        tabletModeAvailable = Property(bool, _get("tabletModeAvailable"), notify=changed)
        tabletModeActive = Property(bool, _get("tabletModeActive"), notify=changed)
        powerCritical = Property(bool, _get("powerCritical"), notify=changed)
        fusionLookAndFeel = Property(bool, _get("fusionLookAndFeel"), notify=changed)
        busy = Property(bool, _get("busy"), notify=changed)
        settingsFileAvailable = Property(bool, _get("settingsFileAvailable"), notify=changed)
        needsSave = Property(bool, _get("needsSave"), notify=changed)
        gestureSwipeUp = Property(int, _get("gestureSwipeUp"), _set("gestureSwipeUp"), notify=changed)
        gestureSwipeDown = Property(int, _get("gestureSwipeDown"), _set("gestureSwipeDown"), notify=changed)
        gestureSwipeLeft = Property(int, _get("gestureSwipeLeft"), _set("gestureSwipeLeft"), notify=changed)
        gestureSwipeRight = Property(int, _get("gestureSwipeRight"), _set("gestureSwipeRight"), notify=changed)
        gesturePinchIn = Property(int, _get("gesturePinchIn"), _set("gesturePinchIn"), notify=changed)
        gesturePinchOut = Property(int, _get("gesturePinchOut"), _set("gesturePinchOut"), notify=changed)
        desktopsInOneRow = Property(bool, _get("desktopsInOneRow"), _set("desktopsInOneRow"), notify=changed)
        gestureSidewaysShared = Property(bool, _get("gestureSidewaysShared"), notify=changed)
        gestureUpDownShared = Property(bool, _get("gestureUpDownShared"), notify=changed)
        snapScriptOn = Property(bool, _get("snapScriptOn"), notify=changed)

        @Slot()
        def restorePreviousDesktop(self):
            pass

        @Slot()
        def resetLayout(self):
            pass

        @Slot(str, result=bool)
        def exportSettings(self, location):
            return True

        @Slot(str)
        def importSettings(self, location):
            pass

        @Slot()
        def setSchemeAccent(self):
            self.s["accentMode"] = 0
            self.changed.emit()

        @Slot(QColor)
        def setCustomAccent(self, c):
            self.s["accentMode"] = 1
            self.s["accentColor"] = c.name()
            self.changed.emit()

        @Slot()
        def useFusionDecoration(self):
            self.s["fusionDecoration"] = True
            self.changed.emit()

        @Slot()
        def setWallpaperAccent(self):
            self.s["accentMode"] = 2
            self.changed.emit()

    class I18n(QObject):
        # Stand-in for KLocalizedContext: the untranslated text.
        @Slot(str, result=str)
        def i18n(self, text):
            return text

        @Slot(str, str, result=str)
        @Slot(str, str, str, result=str)
        def i18nc(self, context, text, arg=None):
            return text if arg is None else text.replace("%1", arg)

    import shutil
    ui_dir = os.path.join(config_home, "ui")
    shutil.copytree(UI, ui_dir)
    shutil.copy(os.path.join(COMMON, "FusionMetrics.qml"), ui_dir)

    kcm = Kcm()
    i18n = I18n()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("kcm", kcm)
    engine.rootContext().setContextObject(i18n)
    warnings = []
    engine.warnings.connect(lambda ws: warnings.extend(w.toString() for w in ws))
    qml = """
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
QQC2.ApplicationWindow {
    width: %d; height: %d; visible: true
    color: Kirigami.Theme.backgroundColor
    Loader { anchors.fill: parent; source: "%s" }
}
""" % (args.width, args.height, QUrl.fromLocalFile(os.path.join(ui_dir, "main.qml")).toString())
    path = os.path.join(config_home, "harness.qml")
    with open(path, "w") as f:
        f.write(qml)
    engine.load(QUrl.fromLocalFile(path))
    if not engine.rootObjects():
        print("\n".join(warnings))
        return 1
    from PySide6.QtQuick import QQuickWindow
    from shiboken6 import Shiboken
    root = engine.rootObjects()[0]
    win = Shiboken.wrapInstance(Shiboken.getCppPointer(root)[0], QQuickWindow)

    def settings_page():
        return root.findChild(QObject, "settingsRoot")

    def select_section(index):
        from PySide6.QtQml import QQmlEngine, QQmlExpression
        page = settings_page()
        if page is not None:
            expression = QQmlExpression(QQmlEngine.contextForObject(page), page, "selectSection(%d)" % index)
            expression.evaluate()
            if expression.hasError():
                raise RuntimeError(expression.error().toString())

    def page_evaluate(text):
        from PySide6.QtQml import QQmlEngine, QQmlExpression
        page = settings_page()
        expression = QQmlExpression(QQmlEngine.contextForObject(page), page, text)
        value, _ = expression.evaluate()
        if expression.hasError():
            raise RuntimeError(expression.error().toString())
        return value

    def prepare_section():
        if args.section_roundtrip:
            for index in range(5):
                select_section(index)
        if args.section is not None:
            select_section(args.section)
        elif args.gestures or args.key_dropdown or args.open_dropdown >= 0:
            select_section(2)
        elif args.rows or args.act:
            select_section(1)
        else:
            select_section(0)

    def navigation_report():
        from PySide6.QtQuick import QQuickItem
        page = settings_page()
        if page is None:
            print("REPORT_NAVIGATION " + json.dumps({"available": False}))
            return
        nav = root.findChild(QQuickItem, "sectionNavigation")
        labels = nav.property("labels")
        if hasattr(labels, "toVariant"):
            labels = labels.toVariant()
        titles = [item.property("text") for item in root.findChildren(QQuickItem)
                  if item.metaObject().className().startswith("SectionTitle_QMLTYPE") and item.isVisible()]
        error = root.findChild(QQuickItem, "settingsError")
        info = root.findChild(QQuickItem, "settingsInfo")
        pending = root.findChild(QQuickItem, "pendingSettingsNote")
        print("REPORT_NAVIGATION " + json.dumps({
            "available": True, "labels": labels, "selected": page.property("currentSection"),
            "compact": nav.property("compact"), "titles": titles, "state": kcm.s,
            "errorVisible": error.isVisible(), "infoVisible": info.isVisible(),
            "pendingVisible": pending.isVisible(), "scroll": scroll_result,
            "rapid": rapid_result, "focus": focus_result, "warnings": warnings}))

    scroll_result = {}
    rapid_result = {}
    focus_result = {}

    def scroll_roundtrip():
        page_evaluate("flickable.contentY = 220")
        scroll_result["before"] = page_evaluate("flickable.contentY")
        select_section(4)
        QTimer.singleShot(100, lambda: select_section(args.section if args.section is not None else 0))
        QTimer.singleShot(300, lambda: scroll_result.update(after=page_evaluate("flickable.contentY")))

    def rapid_switch():
        page_evaluate("flickable.contentY = 100")
        select_section(2)

        def remember_second():
            page_evaluate("flickable.contentY = 220")
            rapid_result["before"] = page_evaluate("flickable.contentY")
            select_section(1)

        def switch_twice():
            select_section(2)
            select_section(4)

        QTimer.singleShot(100, remember_second)
        QTimer.singleShot(200, switch_twice)
        QTimer.singleShot(300, lambda: select_section(2))
        QTimer.singleShot(500, lambda: rapid_result.update(after=page_evaluate("flickable.contentY")))

    def focus_switch():
        from PySide6.QtCore import Qt
        from PySide6.QtQuick import QQuickItem
        from PySide6.QtTest import QTest
        row = next(item for item in root.findChildren(QQuickItem)
                   if item.metaObject().className().startswith("ToggleRow_QMLTYPE")
                   and item.property("text") == "Reduce motion")
        row.forceActiveFocus()
        focus_result["before"] = kcm.s["reduceMotion"]
        select_section(1)

        def press_after_switch():
            active = win.activeFocusItem()
            focus_result["visible"] = bool(active and active.isVisible() and active.isEnabled())
            QTest.keyClick(win, Qt.Key.Key_Space)
            focus_result["after"] = kcm.s["reduceMotion"]
            QTest.keyClick(win, Qt.Key.Key_Escape)

        def traverse_section():
            column = root.findChild(QQuickItem, "pageColumn")
            navigation = root.findChild(QQuickItem, "sectionNavigation")

            def within(item, ancestor):
                while item is not None:
                    if item is ancestor:
                        return True
                    item = item.parentItem()
                return False

            valid = True
            for _ in range(8):
                QTest.keyClick(win, Qt.Key.Key_Tab)
                active = win.activeFocusItem()
                valid = valid and bool(active and active.isVisible() and active.isEnabled())
                if within(active, column):
                    break
            focus_result["tabIntoSection"] = valid and within(active, column)
            QTest.keyClick(win, Qt.Key.Key_Backtab)
            focus_result["backtabToNavigation"] = within(win.activeFocusItem(), navigation)

        QTimer.singleShot(100, press_after_switch)
        QTimer.singleShot(350, traverse_section)

    def grab():
        try:
            img = win.grabWindow()
            img.save(args.out)
            if args.report:
                from PySide6.QtCore import QPointF
                from PySide6.QtQuick import QQuickItem
                column = root.findChild(QQuickItem, "pageColumn")
                if column is None:
                    print("REPORT null")
                else:
                    at = column.mapToScene(QPointF(0, 0))
                    print("REPORT " + json.dumps({"x": column.x(), "width": column.width(),
                                                  "parentWidth": column.parentItem().width(),
                                                  "windowX": at.x(), "windowWidth": win.width()}))
            for w in warnings:
                print("QML:", w)
        finally:
            app.quit()

    def open_dropdown():
        from PySide6.QtCore import QPointF
        from PySide6.QtQml import QQmlEngine, QQmlExpression
        from PySide6.QtQuick import QQuickItem
        drops = [i for i in root.findChildren(QQuickItem) if i.metaObject().className().startswith("DropDown_QMLTYPE")]
        if args.open_dropdown >= len(drops):
            print("REPORT_DROPDOWN null")
            return
        drop = drops[args.open_dropdown]
        # QQuickPopup has no Python type: the drop-down opens its list itself.
        QQmlExpression(QQmlEngine.contextForObject(drop), drop, "popup.open()").evaluate()
        at = drop.mapToScene(QPointF(0, 0))
        print("REPORT_DROPDOWN " + json.dumps({"x": at.x(), "y": at.y(), "width": drop.width(), "height": drop.height()}))

    def drop_downs():
        from PySide6.QtQuick import QQuickItem
        return [i for i in root.findChildren(QQuickItem) if i.metaObject().className().startswith("DropDown_QMLTYPE")]

    def press_key():
        from PySide6.QtCore import QEvent, Qt
        from PySide6.QtGui import QKeyEvent
        drop = drop_downs()[int(args.key_dropdown[0])]
        drop.forceActiveFocus()
        key = getattr(Qt.Key, "Key_" + args.key_dropdown[1])
        for kind in (QEvent.Type.KeyPress, QEvent.Type.KeyRelease):
            QGuiApplication.sendEvent(drop, QKeyEvent(kind, key, Qt.KeyboardModifier.NoModifier))

    def gesture_report():
        from PySide6.QtQuick import QQuickItem
        items = root.findChildren(QQuickItem)
        rows = [i for i in items if i.metaObject().className().startswith("DropDownRow_QMLTYPE")]
        switch = [i for i in items if i.metaObject().className().startswith("ToggleRow_QMLTYPE")
                  and i.property("text") == "Keep desktops in one row"]
        names = ("gestureSwipeUp", "gestureSwipeDown", "gestureSwipeLeft", "gestureSwipeRight", "gesturePinchIn",
                 "gesturePinchOut", "desktopsInOneRow")
        note = root.findChild(QQuickItem, "snapScriptOffNote")
        print("REPORT_GESTURES " + json.dumps({
            "rows": [{"text": r.property("text"), "index": r.property("currentIndex"), "note": r.property("note")}
                     for r in rows],
            "choices": [d.property("displayText") for d in drop_downs()],
            "oneRow": switch[0].property("checked") if switch else None,
            "snapOffNote": note.property("text") if note and note.property("visible") else None,
            "kcm": {n: kcm.s[n] for n in names}}))

    def choice_and_switch_rows():
        from PySide6.QtQuick import QQuickItem
        return [i for i in root.findChildren(QQuickItem)
                if i.metaObject().className().startswith(("ChoiceRow_QMLTYPE", "ToggleRow_QMLTYPE"))]

    def act():
        from PySide6.QtQml import QQmlEngine, QQmlExpression
        from PySide6.QtQuick import QQuickItem
        for spec in args.act:
            text, _, index = spec.partition("=")
            for row in choice_and_switch_rows():
                if row.property("text") != text:
                    continue
                if row.metaObject().className().startswith("ToggleRow_QMLTYPE"):
                    QQmlExpression(QQmlEngine.contextForObject(row), row, "requestToggle()").evaluate()
                else:
                    # A click on a segment: the Segmented control's activated(index).
                    seg = [c for c in row.findChildren(QQuickItem) if c.metaObject().className().startswith("Segmented_QMLTYPE")][0]
                    QQmlExpression(QQmlEngine.contextForObject(seg), seg, "activated(%d)" % int(index)).evaluate()

    def rows_report():
        out = []
        for row in choice_and_switch_rows():
            toggle = row.metaObject().className().startswith("ToggleRow_QMLTYPE")
            entry = {"text": row.property("text"), "note": row.property("note"), "enabled": row.isEnabled()}
            if toggle:
                entry["checked"] = row.property("checked")
            else:
                model = row.property("model")
                entry["labels"] = list(model.toVariant()) if hasattr(model, "toVariant") else list(model or [])
                entry["index"] = row.property("currentIndex")
            out.append(entry)
        names = ("dockSize", "dockPosition", "groupWindows", "magnifiedSize", "topBarAutoHide")
        print("REPORT_ROWS " + json.dumps({"rows": out, "kcm": {n: kcm.s[n] for n in names}}))

    if args.act:
        QTimer.singleShot(600, act)
    QTimer.singleShot(200, prepare_section)
    if args.scroll_roundtrip:
        QTimer.singleShot(400, scroll_roundtrip)
    if args.rapid_switch:
        QTimer.singleShot(400, rapid_switch)
    if args.focus_switch:
        QTimer.singleShot(400, focus_switch)
    if args.navigation:
        QTimer.singleShot(1000, navigation_report)
    if args.rows:
        QTimer.singleShot(1000, rows_report)
    if args.key_dropdown:
        QTimer.singleShot(600, press_key)
    if args.gestures:
        QTimer.singleShot(1000, gesture_report)
    if args.open_dropdown >= 0:
        QTimer.singleShot(700, open_dropdown)
    QTimer.singleShot(1200, grab)
    app.exec()
    import shutil
    shutil.rmtree(config_home, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
