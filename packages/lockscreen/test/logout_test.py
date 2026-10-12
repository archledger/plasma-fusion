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

from PySide6.QtCore import QEvent, QObject, QPoint, QPointF, QRect, Qt, QUrl, Slot
from PySide6.QtGui import QColor, QGuiApplication
from PySide6.QtQml import QQmlEngine, QQmlExpression, QQmlPropertyMap
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
LOGOUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else
                         os.path.join(HERE, "..", "org.plasmafusion.lockshell", "contents", "logout"))
# Plasma 6.7's log-out screen, in the Global Theme.
LOGOUT67 = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else
                           os.path.join(ROOT, "packages", "look-and-feel", "common", "contents", "logout"))
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


def shared(root, expression):
    """Evaluates an expression in the scope of a screen's root, where the shared libraries are."""
    value, error = QQmlExpression(QQmlEngine.contextForObject(root), root, expression).evaluate()
    return None if error else value


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
    run67()
    print("logout:", "FAIL" if fails else "PASS", "(%d failed)" % len(fails))
    sys.exit(1 if fails else 0)


def greeter_engine(sdtype):
    """The greeter's shared engine with its context properties (shutdowndlg.cpp); the objects
    behind them are returned to be kept alive."""
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
    return engine, warnings, (i18n, shutdown_type, spd)


def run(app, sdtype, expected_veil):
    label = "default" if sdtype == SHUTDOWN_DEFAULT else "halt"
    engine, warnings, _kept = greeter_engine(sdtype)

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

    # An output unplugged while the greeter is open (its view goes): the controls are the children
    # of the first screen's root, which made them, also while they are shown on the other screen.
    # The screen left shows them at once, without the pointer moving; and when that view goes too
    # with the pointer on a third screen, the third shows them.
    pointer_to(1)
    third = QQuickView(engine, None)
    third.setResizeMode(QQuickView.SizeRootObjectToView)
    third.resize(1280, 800)
    third.setPosition(2560, 0)
    third.setSource(QUrl.fromLocalFile(os.path.join(LOGOUT, "Logout.qml")))
    third.show()
    QTest.qWait(400)
    views[0].close()
    views[0].deleteLater()
    QTest.qWait(1000)
    on = [action in shown_texts(v) for v in (views[1], third)]
    check(label + ": the first screen unplugged: the screen with the pointer still shows the controls", on == [True, False], on)
    if sdtype == SHUTDOWN_HALT:
        # A key pressed on the controls stops the count-down on every screen left (timer.js): the
        # count-down of the screen that went must not keep the others counting to the shut-down.
        roots = [v.rootObject() for v in (views[1], third)]
        counting = [r.property("countingDown") for r in roots]
        check(label + ": the screens left still count down", counting == [True, True], counting)
        registry = shared(roots[0], "AutoTriggerTimer.callbacks.length")
        check(label + ": the screen that went took its count-down out of the shared list", registry == 2, registry)
        # And a callback that fails (such as one left behind) does not stop the ones after it.
        shared(roots[0], "AutoTriggerTimer.callbacks.unshift(function() { throw new Error('gone'); })")
        button = item_with_text(views[1], action)
        if button is not None:
            views[1].requestActivate()
            button.forceActiveFocus()
            QTest.qWait(100)
            QTest.keyClick(views[1], Qt.Key_Left)
            QTest.qWait(1300)
        counting = [r.property("countingDown") for r in roots]
        times = [r.property("remainingTime") for r in roots]
        check(label + ": a key pressed after it stops the count-down on every screen left",
              counting == [False, False], (counting, times))
    QGuiApplication.sendEvent(views[1], QEvent(QEvent.Leave))
    for x in (300, 320, 340):
        QTest.mouseMove(third, QPoint(x, 400))
        QTest.qWait(50)
    QTest.qWait(600)
    on = [action in shown_texts(v) for v in (views[1], third)]
    check(label + ": and they follow the pointer to the third screen", on == [False, True], on)
    views[1].close()
    views[1].deleteLater()
    QTest.qWait(1000)
    check(label + ": the screen that made them again unplugged: the third shows them", action in shown_texts(third),
          shown_texts(third))
    check(label + ": no QML warnings", warnings == [], warnings)
    third.close()
    third.deleteLater()
    QTest.qWait(100)


def run67():
    """Plasma 6.7's greeter reads the Global Theme's copy: one view per screen on one engine as
    well (QuickViewSharedEngine), each screen with its own controls and count-down, sized by the
    screenGeometry context property. Only the count-downs' shared list (timer.js) is checked."""
    engine, warnings, _kept = greeter_engine(SHUTDOWN_HALT)
    engine.rootContext().setContextProperty("screenGeometry", QRect(0, 0, 1280, 800))
    views = []
    for i in range(2):
        view = QQuickView(engine, None)
        view.resize(1280, 800)
        view.setPosition(1280 * i, 0)
        view.setSource(QUrl.fromLocalFile(os.path.join(LOGOUT67, "Logout.qml")))
        if view.rootObject() is None:
            check("6.7: Logout.qml loads", False, [e.toString() for e in view.errors()])
            return
        view.show()
        views.append(view)
    QTest.qWait(400)
    # The first screen's output unplugged (greeter.cpp deletes its view), then a key pressed on
    # the second screen's focused button.
    views[0].close()
    views[0].deleteLater()
    QTest.qWait(500)
    root = views[1].rootObject()
    registry = shared(root, "AutoTriggerTimer.callbacks.length")
    check("6.7: the screen that went took its count-down out of the shared list", registry == 1, registry)
    views[1].requestActivate()
    QTest.qWait(200)
    focused = views[1].activeFocusItem()
    QTest.keyClick(views[1], Qt.Key_Left)
    QTest.qWait(100)
    before = root.property("remainingTime")
    QTest.qWait(1300)
    after = root.property("remainingTime")
    check("6.7: a key pressed after it stops the count-down of the screen left", before == after,
          (focused.property("text") if focused else None, before, after))
    check("6.7: no QML warnings", warnings == [], warnings)
    views[1].close()
    views[1].deleteLater()
    QTest.qWait(100)


if __name__ == "__main__":
    main()
