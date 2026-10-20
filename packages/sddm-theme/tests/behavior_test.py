#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Drive the shipped QML with Qt key events and SDDM-shaped stand-ins, never a daemon.

QT_QPA_PLATFORM=offscreen python3 packages/sddm-theme/tests/behavior_test.py
Requires PySide6. No authentication, power action, live session or user data is accessed.
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

os.environ["QT_QPA_PLATFORM"] = "offscreen"

from PySide6.QtCore import (  # noqa: E402
    QAbstractListModel, QModelIndex, QObject, Property, Qt, QUrl, Signal, Slot,
)
from PySide6.QtGui import QColor, QGuiApplication, QImage  # noqa: E402
from PySide6.QtQml import QQmlExpression, qmlContext  # noqa: E402
from PySide6.QtQuick import QQuickView  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

HERE = Path(__file__).resolve().parent.parent
checks = 0
failures = 0


def check(ok, message):
    global checks, failures
    checks += 1
    failures += not ok
    print(("PASS " if ok else "FAIL ") + message)


class Model(QAbstractListModel):
    roles = {Qt.UserRole + i: role.encode() for i, role in enumerate(
        ("name", "realName", "icon", "homeDir", "exec", "comment"))}

    def __init__(self, rows):
        super().__init__()
        self.rows = rows

    def roleNames(self):
        return self.roles

    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self.rows)

    def data(self, index, role):
        return self.rows[index.row()].get(self.roles[role].decode(), "") if role in self.roles else None

    count = Property(int, lambda self: len(self.rows), constant=True)
    lastIndex = Property(int, lambda self: 0, constant=True)


class Layout(QObject):
    def __init__(self, name):
        super().__init__()
        self.name = name

    shortName = Property(str, lambda self: self.name, constant=True)
    longName = Property(str, lambda self: self.name, constant=True)


class Keyboard(QObject):
    changed = Signal()

    def __init__(self):
        super().__init__()
        self.choices = [Layout("EN"), Layout("FR")]
        self.current = 0

    def set_current(self, value):
        self.current = value
        self.changed.emit()

    layouts = Property("QVariantList", lambda self: self.choices, constant=True)
    currentLayout = Property(int, lambda self: self.current, set_current, notify=changed)
    capsLock = Property(bool, lambda self: False, constant=True)


class Proxy(QObject):
    loginFailed = Signal()
    loginSucceeded = Signal()
    informationMessage = Signal(str)
    hostName = Property(str, lambda self: "test-host", constant=True)
    canSuspend = Property(bool, lambda self: True, constant=True)
    canReboot = Property(bool, lambda self: True, constant=True)
    canPowerOff = Property(bool, lambda self: True, constant=True)

    def __init__(self):
        super().__init__()
        self.actions = []
        self.logins = []

    @Slot()
    def suspend(self):
        self.actions.append("sleep")

    @Slot()
    def reboot(self):
        self.actions.append("restart")

    @Slot()
    def powerOff(self):
        self.actions.append("power")

    @Slot(str, str, int)
    def login(self, user, password, session):
        self.logins.append((user, password, session))


class Config(QObject):
    def __init__(self, background):
        super().__init__()
        self.image = background

    background = Property(str, lambda self: self.image, constant=True)


def walk(item):
    yield item
    for child in item.childItems():
        yield from walk(child)


def accessible(item):
    value, _ = QQmlExpression(qmlContext(item), item, "Accessible.name").evaluate()
    return value or ""


def find(root, name):
    return next(item for item in walk(root) if accessible(item) == name)


def press(view, item, key, modifier=Qt.NoModifier):
    item.forceActiveFocus()
    QTest.keyClick(view, key, modifier)
    QTest.qWait(10)


def reachable(view, start, target):
    start.forceActiveFocus()
    for _ in range(50):
        QTest.keyClick(view, Qt.Key_Tab)
        if view.activeFocusItem() == target:
            return True
    return False


def main():
    app = QGuiApplication(sys.argv)
    with tempfile.TemporaryDirectory(prefix="sddm-behavior-") as tmp:
        image = QImage(32, 32, QImage.Format_RGB32)
        image.fill(QColor("#aabbcc"))
        avatar = str(Path(tmp) / "avatar.png")
        image.save(avatar)
        subprocess.run(["bash", str(HERE / "build.sh"), tmp, avatar], check=True)
        users = Model([{"name": f"user{i}", "realName": f"Person {i}", "icon": avatar}
                       for i in range(4)])
        sessions = Model([{"name": name} for name in ("Plasma", "Plasma X11", "Other session")])
        keyboard = Keyboard()
        proxy = Proxy()
        config = Config(avatar)
        view = QQuickView()
        context = view.rootContext()
        for name, obj in (("sddm", proxy), ("keyboard", keyboard), ("config", config),
                          ("userModel", users), ("sessionModel", sessions)):
            context.setContextProperty(name, obj)
        warnings = []
        view.engine().warnings.connect(lambda errors: warnings.extend(e.toString() for e in errors))
        view.setResizeMode(QQuickView.SizeRootObjectToView)
        view.setSource(QUrl.fromLocalFile(str(Path(tmp) / "plasmafusion/Main.qml")))
        check(view.status() == QQuickView.Ready, "the actual staged Main.qml loads")
        if view.status() != QQuickView.Ready:
            print("\n".join(e.toString() for e in view.errors()))
            return 1
        view.resize(1440, 900)
        view.show()
        QTest.qWait(100)
        root = view.rootObject()
        password = find(root, "Password")
        check(root.property("loginName") == "user0", "SDDM's last user populates the login card")

        layout = find(root, "Keyboard layout")
        check(reachable(view, password, layout), "Tab reaches the keyboard-layout control")
        press(view, layout, Qt.Key_Space)
        check(keyboard.current == 1, "Space changes the keyboard layout")
        keyboard.set_current(1)
        press(view, layout, Qt.Key_Return)
        check(keyboard.current == 0, "Return cycles the keyboard layout")

        for label, action in (("Sleep", "sleep"), ("Restart", "restart"), ("Shut down", "power")):
            button = find(root, label)
            check(reachable(view, password, button), f"Tab reaches {label}")
            for key in (Qt.Key_Return, Qt.Key_Space):
                proxy.actions.clear()
                press(view, button, key)
                check(proxy.actions == [action], f"{label} dispatches exactly once by {key.name}")

        third = find(root, "Person 2")
        second = find(root, "Person 1")
        press(view, third, Qt.Key_Left)
        check(view.activeFocusItem() == second, "Left from a Tab-focused third account focuses the second")
        press(view, second, Qt.Key_Return)
        check(root.property("loginName") == "user1", "Return chooses the focused account")
        password.setProperty("text", "test-input")
        press(view, third, Qt.Key_Space)
        check(root.property("loginName") == "user2" and password.property("text") == "",
              "account changes clear the previous password")
        other = find(root, "Other user")
        press(view, other, Qt.Key_Left)
        check(view.activeFocusItem() == find(root, "Person 3"), "Left from Other user focuses the last account")
        press(view, other, Qt.Key_Return)
        username = find(root, "Username")
        check(username.isVisible() and view.activeFocusItem() == username,
              "Other user exposes and focuses the username input")
        check(any(item.property("text") == "Username" and item.isVisible() for item in walk(root)),
              "Other user has a visible Username prompt")

        picker = next(item for item in walk(root) if accessible(item).startswith("Session:"))
        session = picker.parentItem()
        option = find(root, "Other session")
        check(reachable(view, password, picker), "Tab reaches the session picker")
        press(view, picker, Qt.Key_Return)
        check(option.isVisible(), "Return opens the session menu")
        check(find(root, "Plasma").mapToScene(find(root, "Plasma").boundingRect().topLeft()).x() >= 0,
              "the open session menu is not clipped off the screen's left edge")
        if not option.isVisible():
            # Still exercise the delegate independently when the old pill ignores Return.
            pos = picker.mapToScene(picker.boundingRect().center()).toPoint()
            QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, pos)
        press(view, find(root, "Plasma"), Qt.Key_Down)
        check(view.activeFocusItem() == find(root, "Plasma X11"), "Down moves between session choices")
        press(view, option, Qt.Key_Space)
        check(session.property("index") == 2 and not option.isVisible(),
              "Space chooses a session and closes the menu")
        check(view.activeFocusItem() == picker, "choosing a session returns focus to the pill")
        press(view, picker, Qt.Key_Space)
        QTest.keyClick(view, Qt.Key_Escape)
        check(not option.isVisible() and view.activeFocusItem() == picker,
              "Escape closes the session menu and restores focus")

        username.setProperty("text", "unlisted")
        password.setProperty("text", "test-input")
        proxy.logins.clear()
        press(view, password, Qt.Key_Return)
        check(proxy.logins == [("unlisted", "test-input", 2)],
              "login submits the typed username and selected session to the stand-in only")
        proxy.loginFailed.emit()
        QTest.qWait(10)
        check(password.property("text") == "", "failed login clears the password")

        reveal = find(root, "Show password")
        check(reachable(view, password, reveal), "Tab reaches password visibility")
        press(view, reveal, Qt.Key_Space)
        check(reveal.property("pressed"), "Space operates password visibility")
        # Qt's normal echo mode retains deleted input for undo. Never use a real secret here.
        reveal.setProperty("pressed", True)
        password.setProperty("text", "")
        password.forceActiveFocus()
        for letter in "test-input":
            QTest.keyClick(view, letter)
        QTest.keyClick(view, Qt.Key_A, Qt.ControlModifier)
        QTest.keyClick(view, Qt.Key_Backspace)
        QTest.keyClick(view, Qt.Key_Z, Qt.ControlModifier)
        check(password.property("text") == "", "Undo cannot recover deleted password input")
        check(not warnings, "theme behavior emits no QML warnings")
        for warning in warnings:
            print("QML", warning)
        view.close()
        view.setSource(QUrl())
        app.processEvents()
    print(f"SDDM behavior: {checks - failures}/{checks} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
