#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Render a KWin QML package outside KWin (test use only).

    render.py HARNESS.qml OUT.png [name=value ...]

Loads HARNESS.qml with the stand-in org.kde.kwin module from ./stubs, gives it the context
properties passed as name=value (numbers and true/false are converted), waits until the
harness sets `ready`, then composites every visible window (in the order the harness lists
them in `captureOrder`, else creation order) into one 1440x900 image. Run through run.sh,
which prepares the Plasma style, colours, icons and fonts.
"""
import sys
import os
import re

from PySide6.QtCore import QObject, QTimer, QUrl, Slot, QPoint
from PySide6.QtGui import QGuiApplication, QImage, QPainter, QColor, QCursor
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
import shiboken6

HERE = os.path.dirname(os.path.abspath(__file__))


def subst(text, args):
    for i, a in enumerate(args, 1):
        text = text.replace("%" + str(i), str(a))
    return text


class I18n(QObject):
    """The i18n functions KWin's QML engine provides (KLocalizedContext), untranslated."""

    @Slot(str, str, result=str)
    @Slot(str, str, "QVariant", result=str)
    def i18nd(self, domain, text, *args):
        return subst(text, args)

    @Slot(str, str, str, result=str)
    @Slot(str, str, str, "QVariant", result=str)
    def i18ndc(self, domain, context, text, *args):
        return subst(text, args)

    @Slot(str, str, str, int, result=str)
    def i18ndp(self, domain, singular, plural, n):
        return subst(singular if n == 1 else plural, [n])

    @Slot(str, result=str)
    @Slot(str, "QVariant", result=str)
    def i18n(self, text, *args):
        return subst(text, args)


def convert(value):
    if value in ("true", "false"):
        return value == "true"
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    if re.fullmatch(r"-?\d+\.\d*", value):
        return float(value)
    return value


def main():
    harness, out = sys.argv[1], sys.argv[2]
    props = dict(a.split("=", 1) for a in sys.argv[3:])
    app = QGuiApplication(sys.argv[:1])
    QCursor.setPos(int(props.get("pointerX", "1439")), int(props.get("pointerY", "899")))
    engine = QQmlApplicationEngine()
    engine.setProperty("_kirigamiTheme", "KirigamiPlasmaStyle")
    engine.addImportPath(os.path.join(HERE, "stubs"))
    i18n = I18n()
    engine.rootContext().setContextObject(i18n)
    for k, v in props.items():
        engine.rootContext().setContextProperty(k, convert(v))
    # PFK_PACKAGES: a tree with switcher/ and scripts/ built by tools/build.d/80-kwin.sh (the packages
    # with their shared QML blocks); the default is the source tree.
    packages = os.environ.get("PFK_PACKAGES") or os.path.normpath(os.path.join(HERE, "..", ".."))
    engine.rootContext().setContextProperty("packagesRoot", os.path.abspath(packages))
    engine.warnings.connect(lambda ws: [print("QML:", w.toString(), file=sys.stderr) for w in ws])
    engine.load(QUrl.fromLocalFile(os.path.abspath(harness)))
    if not engine.rootObjects():
        print("harness failed to load", file=sys.stderr)
        sys.exit(1)
    root = engine.rootObjects()[0]
    waited = [0]

    def capture():
        waited[0] += 100
        if not root.property("ready") and waited[0] < 8000:
            QTimer.singleShot(100, capture)
            return
        QTimer.singleShot(int(props.get("settle", "600")), grab)

    def grab():
        try:
            canvas = QImage(1440, 900, QImage.Format_ARGB32_Premultiplied)
            canvas.fill(QColor(0, 0, 0))
            p = QPainter(canvas)
            windows = [w for w in QGuiApplication.topLevelWindows() if w.isVisible() and w.inherits("QQuickWindow")]
            order = root.property("captureOrder")
            if hasattr(order, "toVariant"):
                order = order.toVariant()
            order = list(order or [])
            def rank(w):
                name = w.objectName() or w.title()
                for i, key in enumerate(order):
                    if key and key in name:
                        return i
                return len(order)
            windows.sort(key=rank)
            for w in windows:
                q = shiboken6.wrapInstance(shiboken6.getCppPointer(w)[0], QQuickWindow)
                img = q.grabWindow()
                print("window", repr(w.title()), w.x(), w.y(), w.width(), w.height(), file=sys.stderr)
                p.drawImage(QPoint(w.x(), w.y()), img)
            p.end()
            canvas.save(out)
        finally:
            app.quit()

    QTimer.singleShot(300, capture)
    app.exec()


if __name__ == "__main__":
    main()
