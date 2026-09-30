#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test tooling (not installed): render the module's QML offscreen with a stand-in for the C++
module object, to check the layout against the board without a Plasma session.

    tests/offscreen_preview.py OUT.png [dark|light] [--state key=value ...] [--width 468] [--height 560]

Uses the system Qt (PySide6 6.11 = Plasma's Qt), Kirigami, KCMUtils QML and the KDE platform
theme with a private XDG_CONFIG_HOME whose kdeglobals holds the Plasma Fusion colour scheme and
fonts (packages/color-schemes). Prints the window's QML warnings. --state sets values of the
stand-in module (style, accentMode, accentColor, buttonStyle, magnify, globalMenu, hotCorner,
shellLoading, shellRunning, dockAvailable, topBarAvailable, decorationInstalled, fusionDecoration, errorText).
Environment: PFKM_TMP (directory for the private configuration, default the system temp
directory), PFKM_THEME (Qt platform theme, default kde).
"""
import argparse
import configparser
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
UI = os.path.join(HERE, "..", "src", "ui")


def write_kdeglobals(config_home, variant):
    scheme = "PlasmaFusionDark" if variant == "dark" else "PlasmaFusionLight"
    src = os.path.join(ROOT, "packages", "color-schemes", scheme + ".colors")
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    cp.read(src)
    lines = ["[General]", "ColorScheme=" + scheme,
             "font=Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0", "",
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
    args = ap.parse_args()

    config_home = tempfile.mkdtemp(prefix="pfkm-cfg-", dir=os.environ.get("PFKM_TMP"))
    write_kdeglobals(config_home, args.variant)
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
             "magnify": True, "globalMenu": True, "hotCorner": False, "shellLoading": False, "shellRunning": True,
             "dockAvailable": True, "topBarAvailable": True, "decorationInstalled": False,
             "fusionDecoration": False,
             "errorText": ""}
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
        shellLoading = Property(bool, _get("shellLoading"), notify=changed)
        shellRunning = Property(bool, _get("shellRunning"), notify=changed)
        dockAvailable = Property(bool, _get("dockAvailable"), notify=changed)
        topBarAvailable = Property(bool, _get("topBarAvailable"), notify=changed)
        decorationInstalled = Property(bool, _get("decorationInstalled"), notify=changed)
        fusionDecoration = Property(bool, _get("fusionDecoration"), notify=changed)
        errorText = Property(str, _get("errorText"), notify=changed)

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
        def i18nc(self, context, text):
            return text

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
""" % (args.width, args.height, QUrl.fromLocalFile(os.path.abspath(os.path.join(UI, "main.qml"))).toString())
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

    def grab():
        try:
            img = win.grabWindow()
            img.save(args.out)
            for w in warnings:
                print("QML:", w)
        finally:
            app.quit()

    QTimer.singleShot(1200, grab)
    app.exec()
    import shutil
    shutil.rmtree(config_home, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
