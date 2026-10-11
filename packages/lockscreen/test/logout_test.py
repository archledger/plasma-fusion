#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offscreen check of the Plasma 6.8 log-out screen (org.plasmafusion.lockshell contents/logout/).

Loads Logout.qml the way Plasma 6.8's ksmserver-logout-greeter does: one view per screen, all on
one engine, the root sized by the view (no screenGeometry context property any more,
plasma-workspace 37ae55a2), and the greeter's context properties (shutdowndlg.cpp). Checks that
the files load without warnings, that the controls are shown once and follow the pointer to the
screen it is on, that the count-down is shown with them, that the buttons and Escape send the
greeter's signals, and that the veil takes the colour scheme's Complementary background.

  QT_QPA_PLATFORM=offscreen dbus-run-session --config-file=test/session-bus.conf -- \\
      python3 test/logout_test.py [LOGOUT_DIR]

LOGOUT_DIR defaults to the package's contents/logout/. Exits 1 on a failed check.
"""
import os
import sys
import tempfile

from PySide6.QtCore import QEvent, QObject, QPoint, QPointF, Qt, QUrl, Slot
from PySide6.QtGui import QColor, QGuiApplication
from PySide6.QtQml import QQmlEngine, QQmlPropertyMap
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
LOGOUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else
                         os.path.join(HERE, "..", "org.plasmafusion.lockshell", "contents", "logout"))
SHUTDOWN_DEFAULT, SHUTDOWN_NONE, SHUTDOWN_REBOOT, SHUTDOWN_HALT = -1, 0, 1, 2
fails = []


def check(name, ok, detail=None):
    print(("PASS " if ok else "FAIL ") + name, "" if detail is None else detail)
    if not ok:
        fails.append(name)


def fmt(text, args):
    for i, a in enumerate(args):
        text = text.replace("%" + str(i + 1), str(a))
    return text.replace("&", "")


class I18n(QObject):
    """The KLocalizedContext functions the log-out screen calls (English, accelerators removed)."""

    @Slot(str, str, result=str)
    @Slot(str, str, "QVariant", result=str)
    def i18nd(self, domain, text, *args):
        return fmt(text, args)

    @Slot(str, str, str, result=str)
    @Slot(str, str, str, "QVariant", result=str)
    def i18ndc(self, domain, ctx, text, *args):
        return fmt(text, args)

    @Slot(str, str, str, "QVariant", result=str)
    def i18ndp(self, domain, singular, plural, n, *args):
        return fmt(singular if int(n) == 1 else plural, (n,) + args)


def items(root):
    found, todo = [], [root]
    while todo:
        it = todo.pop()
        found.append(it)
        todo.extend(it.childItems())
    return found


def shown_texts(view):
    """The visible button and label texts of a view (ancestors visible, opacity above 0)."""
    out = []
    for it in items(view.contentItem()):
        text = it.property("text")
        if isinstance(text, str) and text and it.isVisible() and it.opacity() > 0:
            out.append(text)
    return out


def item_with_text(view, text):
    return next((it for it in items(view.contentItem()) if it.property("text") == text and it.isVisible()), None)


def main():
    # The colour scheme the greeter reads (kdeglobals): Plasma Fusion Light, whose light
    # Complementary set made Breeze's black veil unreadable.
    cfg = tempfile.mkdtemp(prefix="pf-logout-config-")
    with open(os.path.join(ROOT, "packages", "color-schemes", "PlasmaFusionLight.colors")) as f:
        scheme = f.read()
    with open(os.path.join(cfg, "kdeglobals"), "w") as f:
        f.write(scheme)
    os.environ["XDG_CONFIG_HOME"] = cfg
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "org.kde.desktop")
    complementary = next(line.split("=", 1)[1] for line in scheme.split("[Colors:Complementary]", 1)[1].splitlines()
                         if line.startswith("BackgroundNormal="))
    expected_veil = QColor(*[int(v) for v in complementary.split(",")[:3]])

    app = QGuiApplication(sys.argv[:1])
    for sdtype in (SHUTDOWN_DEFAULT, SHUTDOWN_HALT):
        run(app, sdtype, expected_veil)
    print("logout:", "FAIL" if fails else "PASS", "(%d failed)" % len(fails))
    sys.exit(1 if fails else 0)


def run(app, sdtype, expected_veil):
    label = "default" if sdtype == SHUTDOWN_DEFAULT else "halt"
    engine = QQmlEngine()
    warnings = []
    engine.warnings.connect(lambda ws: [warnings.append(w.toString()) for w in ws])
    ctx = engine.rootContext()
    i18n = I18n()
    ctx.setContextObject(i18n)
    shutdown_type = QQmlPropertyMap()
    for key, value in (("ShutdownTypeDefault", SHUTDOWN_DEFAULT), ("ShutdownTypeNone", SHUTDOWN_NONE),
                       ("ShutdownTypeReboot", SHUTDOWN_REBOOT), ("ShutdownTypeHalt", SHUTDOWN_HALT),
                       ("ShutdownTypeLogout", 3)):
        shutdown_type.insert(key, value)
    spd = QQmlPropertyMap()
    for key, value in (("StandbyState", True), ("SuspendState", True), ("HibernateState", False)):
        spd.insert(key, value)
    for key, value in (("maysd", True), ("sdtype", sdtype), ("ShutdownType", shutdown_type),
                       ("spdMethods", spd), ("canLogout", True), ("rebootToFirmwareSetup", False),
                       ("isUefi", False), ("rebootToBootLoaderMenu", False),
                       ("rebootToBootLoaderEntry", ""), ("softwareUpdatePending", False),
                       ("bootManager", "None"), ("choose", False), ("rebootOptions", {})):
        ctx.setContextProperty(key, value)

    # Two screens side by side, one view each on the shared engine (greeter.cpp).
    views, signals = [], []
    for i in range(2):
        view = QQuickView(engine, None)
        view.setResizeMode(QQuickView.SizeRootObjectToView)
        view.resize(1280, 800)
        view.setPosition(1280 * i, 0)
        view.setSource(QUrl.fromLocalFile(os.path.join(LOGOUT, "Logout.qml")))
        root = view.rootObject()
        if root is None:
            check(label + ": Logout.qml loads", False, [e.toString() for e in view.errors()])
            return
        for name in ("logoutRequested", "haltRequested", "rebootRequested", "cancelRequested"):
            getattr(root, name).connect(lambda name=name, i=i: signals.append((i, name)))
        view.show()
        views.append(view)
    QTest.qWait(400)

    def pointer_to(i):
        # The pointer leaves the other screen (it is on one output at a time) and moves here.
        QGuiApplication.sendEvent(views[1 - i], QEvent(QEvent.Leave))
        for x in (300, 320, 340):
            QTest.mouseMove(views[i], QPoint(x, 400))
            QTest.qWait(50)
        QTest.qWait(600)

    pointer_to(1)
    action = "Shut Down" if sdtype == SHUTDOWN_DEFAULT else "Shut Down Now"
    on = [action in shown_texts(v) for v in views]
    check(label + ": the controls are shown once, on the screen with the pointer", on == [False, True], on)
    if sdtype == SHUTDOWN_HALT:
        counting = ["Shutting down in" in " ".join(shown_texts(v)) for v in views]
        check(label + ": the count-down is shown with them", counting == [False, True], counting)

    # The pointer moves to the first screen: the controls follow.
    pointer_to(0)
    on = [action in shown_texts(v) for v in views]
    check(label + ": they follow the pointer to the other screen", on == [True, False], on)

    # The veil: the first item of the root, 85 % opaque.
    veils = [next((it for it in v.rootObject().childItems() if abs(it.opacity() - 0.85) < 0.001), None) for v in views]
    colours = [QColor(veil.property("color")).name() if veil else None for veil in veils]
    check(label + ": every screen has the veil in the Complementary background",
          colours == [expected_veil.name()] * 2, (colours, expected_veil.name()))

    if sdtype == SHUTDOWN_DEFAULT:
        button = item_with_text(views[0], "Log Out")
        if button is not None:
            p = button.mapToScene(QPointF(button.width() / 2, button.height() / 2)).toPoint()
            QTest.mouseClick(views[0], Qt.LeftButton, Qt.NoModifier, p)
            QTest.qWait(200)
        check(label + ": Log Out sends logoutRequested", (0, "logoutRequested") in signals, signals)
    views[0].requestActivate()
    QTest.qWait(100)
    QTest.keyClick(views[0], Qt.Key_Escape)
    QTest.qWait(200)
    check(label + ": Escape sends cancelRequested", (0, "cancelRequested") in signals, signals)
    check(label + ": no QML warnings", warnings == [], warnings)
    for view in views:
        view.close()
        view.deleteLater()
    QTest.qWait(100)


if __name__ == "__main__":
    main()
