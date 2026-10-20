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
    QAbstractListModel, QMetaObject, QModelIndex, QObject, QPoint, Property, Qt, QUrl, Signal, Slot,
)
from PySide6.QtGui import (  # noqa: E402
    QAccessible, QAccessibleActionInterface, QColor, QGuiApplication, QImage, QInputMethod,
    QInputMethodEvent,
)
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
        ("name", "realName", "icon", "homeDir", "exec", "comment", "needsPassword"))}

    def __init__(self, rows):
        super().__init__()
        self.rows = rows
        self.last_index = 0

    def reset_rows(self, rows, during_reset=None):
        self.beginResetModel()
        self.rows = rows
        if during_reset:
            during_reset()
        self.endResetModel()

    def rename_row(self, row, name):
        self.rows[row]["name"] = name
        role = next(role for role, value in self.roles.items() if value == b"name")
        self.dataChanged.emit(self.index(row, 0), self.index(row, 0), [role])

    def roleNames(self):
        return self.roles

    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self.rows)

    def data(self, index, role):
        if not index.isValid() or not 0 <= index.row() < len(self.rows):
            return None
        return self.rows[index.row()].get(self.roles[role].decode(), "") if role in self.roles else None

    count = Property(int, lambda self: len(self.rows), constant=True)
    lastIndex = Property(int, lambda self: self.last_index, constant=True)


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
        self.choices = [Layout("<b>EN</b>"), Layout("FR")]
        self.current = 0
        self.caps = False

    def set_current(self, value):
        self.current = value
        self.changed.emit()

    layouts = Property("QVariantList", lambda self: self.choices, constant=True)
    currentLayout = Property(int, lambda self: self.current, set_current, notify=changed)
    capsLock = Property(bool, lambda self: self.caps, notify=changed)


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
    context = qmlContext(item)
    # Flickable's native contentItem has no QML context. Do not pass null to QQmlExpression;
    # its QML-authored descendants still carry the accessible names the test searches for.
    if context is None:
        return ""
    value, _ = QQmlExpression(context, item, "Accessible.name").evaluate()
    return value or ""


def find(root, name):
    return next(item for item in walk(root) if accessible(item) == name)


def plain_labels(root, text):
    labels = [item for item in walk(root)
              if item.property("text") == text and item.metaObject().indexOfProperty("textFormat") >= 0]
    return bool(labels) and all(QQmlExpression(qmlContext(item), item,
                                              "textFormat === Text.PlainText").evaluate()[0]
                                for item in labels)


def rendered_text(root, text):
    return next(item for item in walk(root)
                if item.property("text") == text and item.metaObject().indexOfProperty("lineCount") >= 0)


def visible_initial(root, letter):
    return any(item.property("text") == letter and item.isVisible()
               and item.metaObject().indexOfProperty("textFormat") >= 0 for item in walk(root))


def press(view, item, key, modifier=Qt.NoModifier):
    item.forceActiveFocus()
    QTest.keyClick(view, key, modifier)
    QTest.qWait(10)


def activate(item):
    """Invoke the accessibility Press action, not a key or pointer shortcut."""
    interface = QAccessible.queryAccessibleInterface(item)
    actions = interface.actionInterface() if interface is not None else None
    press_name = QAccessibleActionInterface.pressAction()
    available = actions is not None and press_name in actions.actionNames()
    check(available, f"assistive press is available for {accessible(item) or 'control'}")
    if not available:
        return
    actions.doAction(press_name)
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
        missing_avatar = str(Path(tmp) / "missing-avatar.png")
        invalid_avatar = str(Path(tmp) / "invalid-avatar.png")
        Path(invalid_avatar).write_bytes(b"not an image")
        broken_urls = [QUrl.fromLocalFile(p).toString() for p in (missing_avatar, invalid_avatar)]
        subprocess.run(["bash", str(HERE / "build.sh"), tmp, avatar], check=True)
        account_name = "<b>Account</b> " * 10
        users = Model([{"name": f"user{i}", "realName": account_name if i == 0 else f"Person {i}",
                        "icon": avatar, "needsPassword": i != 6} for i in range(20)])
        users.rows[4]["icon"] = missing_avatar
        users.rows[5]["icon"] = invalid_avatar
        session_name = "<b>Odd session</b> " + "Z" * 300
        sessions = Model([{"name": name} for name in ("Plasma", "Plasma X11", "Other session")]
                         + [{"name": f"Additional {i}"} for i in range(12)]
                         + [{"name": session_name}])
        sessions.last_index = 1
        keyboard = Keyboard()
        proxy = Proxy()
        config = Config(avatar)
        view = QQuickView()
        context = view.rootContext()
        for name, obj in (("sddm", proxy), ("keyboard", keyboard), ("config", config),
                          ("userModel", users), ("sessionModel", sessions)):
            context.setContextProperty(name, obj)
        warnings = []
        image_errors = []

        def note_warnings(errors):
            for error in errors:
                message = error.toString()
                # These two owned bad-file fixtures intentionally produce Image.Error. Keep every
                # other QML warning fatal, and verify the expected errors actually occurred below.
                if (any(url in message for url in broken_urls) and "QML Image:" in message
                        and ("Cannot open:" in message or "Error decoding:" in message)):
                    image_errors.append(message)
                else:
                    warnings.append(message)

        view.engine().warnings.connect(note_warnings)
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
        # Qt 6.11.2 deliberately suppresses Accessible.name on passwordEdit items. Use the
        # stable object name, while asserting the protected state and static description below.
        password = root.findChild(QObject, "passwordInput")
        check(password is not None, "the protected password input is available to the harness")
        if password is None:
            return 1
        reveal = find(root, "Show password")
        card = next(item for item in walk(root) if item.property("promptName") is not None)
        check(root.property("loginName") == "user0", "SDDM's last user populates the login card")
        check(len(image_errors) >= 2, "the missing and invalid avatar fixtures reached the image error path")
        check(visible_initial(find(root, "Person 4"), "P"), "a missing tile avatar falls back to its initial")
        check(visible_initial(find(root, "Person 5"), "P"), "an invalid tile avatar falls back to its initial")
        check(password.hasActiveFocus() and
              any(item.property("text") == "Password" and item.isVisible() for item in walk(root)),
              "the initially focused password field has a visible prompt")
        switcher = next(item for item in walk(root) if item.property("choiceCount") is not None)
        person0 = find(root, account_name)
        check(QQmlExpression(qmlContext(person0), person0, "Accessible.selected").evaluate()[0],
              "the remembered account is exposed as selected to assistive technology")
        not_selected = find(root, "Person 1")
        check(not QQmlExpression(qmlContext(not_selected), not_selected,
                                "Accessible.selected").evaluate()[0],
              "other accounts are exposed as not selected")
        other_tile = find(root, "Other user")
        check(not QQmlExpression(qmlContext(other_tile), other_tile,
                                "Accessible.selected").evaluate()[0],
              "Other user is not selected when the remembered account is chosen")

        no_password = root.findChild(QObject, "noPasswordLabel")
        passwordless = find(root, "Person 6")
        press(view, passwordless, Qt.Key_Space)
        QTest.qWait(30)
        check(not password.isVisible() and no_password.isVisible(),
              "an account without a password hides the password field")
        check(view.activeFocusItem() == find(root, "Sign in"),
              "a passwordless account focuses its sign-in control")
        check(QQmlExpression(qmlContext(passwordless), passwordless,
                            "Accessible.selected").evaluate()[0],
              "the passwordless account becomes the assistive selection")
        proxy.logins.clear()
        activate(find(root, "Sign in"))
        check(proxy.logins == [("user6", "", 1)],
              "passwordless sign-in submits an empty password")
        press(view, person0, Qt.Key_Space)
        QTest.qWait(30)
        check(password.isVisible() and not no_password.isVisible(),
              "a password account restores the password field")
        check(plain_labels(root, account_name), "account names and captions render markup literally")
        check(plain_labels(root, "<b>EN</b>"), "keyboard layout labels render markup literally")
        proxy.informationMessage.emit("<b>Notice</b>")
        QTest.qWait(50)
        check(plain_labels(root, "<b>Notice</b>"), "daemon information renders markup literally")
        before_message = card.height()
        long_message = "Read all of these authentication instructions before continuing. " * 80
        proxy.informationMessage.emit(long_message)
        QTest.qWait(50)
        message = rendered_text(root, long_message)
        check(message.property("lineCount") > 1 and not message.property("truncated"),
              "long authentication instructions wrap without losing their ending")
        check(card.height() > before_message, "the card grows to show wrapped authentication text")
        message_view = next((item for item in walk(root) if accessible(item) == "Authentication message"), None)
        check(message_view is not None and message_view.property("contentHeight") > message_view.height(),
              "overlong authentication instructions have a bounded scrolling view")
        paged = False
        short_fit = False
        caps_fit = False
        other_caps_fit = False
        if message_view is not None:
            check(reachable(view, password, message_view), "Tab reaches overflowing authentication instructions")
            press(view, message_view, Qt.Key_PageDown)
            paged = message_view.property("contentY") > 0
            view.resize(1440, 480)
            QTest.qWait(50)
            picker = next(item for item in walk(root) if accessible(item).startswith("Session:"))
            footer_top = min(picker.mapToScene(picker.boundingRect().topLeft()).y(),
                             find(root, "Sleep").mapToScene(find(root, "Sleep").boundingRect().topLeft()).y())
            short_fit = (card.y() + card.height() <= switcher.y()
                         and switcher.y() + switcher.height() <= footer_top)
            keyboard.caps = True
            keyboard.changed.emit()
            QTest.qWait(50)
            caps_fit = (card.y() + card.height() <= switcher.y()
                        and switcher.y() + switcher.height() <= footer_top)
            press(view, find(root, "Other user"), Qt.Key_Return)
            # Selection clears the old account's feedback. This is a new message for Other user.
            proxy.informationMessage.emit(long_message)
            QTest.qWait(50)
            other_caps_fit = (card.y() + card.height() <= switcher.y()
                              and switcher.y() + switcher.height() <= footer_top)
            keyboard.caps = False
            keyboard.changed.emit()
            message_view.forceActiveFocus()
            pages = int(message_view.property("contentHeight") / max(1, message_view.height())) + 2
            for _ in range(pages):
                QTest.keyClick(view, Qt.Key_PageDown)
            check(message_view.property("contentY") >= message_view.property("contentHeight") - message_view.height() - 1,
                  "keyboard paging can reach the end of all authentication instructions")
            view.resize(1440, 900)
            QTest.qWait(50)
        else:
            check(False, "Tab reaches overflowing authentication instructions")
            check(False, "keyboard paging can reach the end of all authentication instructions")
        check(paged, "Page Down scrolls authentication instructions")
        check(short_fit, "long instructions keep the form, accounts and footer separate on a short screen")
        check(caps_fit, "caps-lock warnings and long instructions fit together on a short screen")
        check(other_caps_fit, "Other user, caps-lock warning and long instructions remain usable together")
        unbroken_message = "X" * 200
        proxy.informationMessage.emit(unbroken_message)
        QTest.qWait(50)
        message = rendered_text(root, unbroken_message)
        check(message.property("lineCount") > 1 and message.property("contentWidth") <= message.width(),
              "long unbroken authentication text also remains within the message row")
        proxy.informationMessage.emit("")
        check(switcher.width() <= root.width() - 64 and switcher.x() >= 32,
              "many accounts and a long name stay in a viewport inside the screen margins")

        layout = find(root, "Keyboard layout")
        check(reachable(view, password, layout), "Tab reaches the keyboard-layout control")
        press(view, layout, Qt.Key_Space)
        check(keyboard.current == 1, "Space changes the keyboard layout")
        layout_name = QQmlExpression(qmlContext(layout), layout, "Accessible.description").evaluate()[0]
        check(layout_name == "FR", "the keyboard control announces the selected layout")
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
        reveal.setProperty("pressed", True)
        press(view, third, Qt.Key_Space)
        check(root.property("loginName") == "user2" and password.property("text") == "",
              "account changes clear the previous password")
        check(not reveal.property("pressed"), "account changes reset password visibility")
        proxy.informationMessage.emit("Feedback for the previous account")
        press(view, find(root, "Person 4"), Qt.Key_Space)
        check(card.property("message") == "", "listed-account changes discard prior authentication feedback")
        check(root.property("loginName") == "user4" and visible_initial(card, "P"),
              "a missing login-card avatar falls back to its initial")
        press(view, find(root, "Person 5"), Qt.Key_Space)
        check(root.property("loginName") == "user5" and visible_initial(card, "P"),
              "an invalid login-card avatar falls back to its initial")
        press(view, third, Qt.Key_Space)
        check(not visible_initial(card, "P"), "a loaded login-card photo replaces the initial")
        other = find(root, "Other user")
        press(view, other, Qt.Key_Left)
        last = find(root, "Person 19")
        check(view.activeFocusItem() == last, "Left from Other user focuses the last account")
        left = last.mapToScene(last.boundingRect().topLeft()).x()
        check(left >= 32 and left + last.width() <= root.width() - 32,
              "keyboard focus scrolls the last account fully into the viewport")
        viewport = next(item for item in walk(switcher) if item.property("contentX") is not None)
        before = viewport.property("contentX")
        start = viewport.mapToScene(viewport.boundingRect().center()).toPoint()
        QTest.mousePress(view, Qt.LeftButton, Qt.NoModifier, start)
        QTest.qWait(30)
        # First cross the drag threshold, then move after Flickable takes the pointer grab.
        QTest.mouseMove(view, start + QPoint(30, 0), 30)
        QTest.qWait(30)
        QTest.mouseMove(view, start + QPoint(230, 0), 30)
        QTest.qWait(30)
        QTest.mouseMove(view, start + QPoint(330, 0), 30)
        QTest.mouseRelease(view, Qt.LeftButton, Qt.NoModifier, start + QPoint(330, 0))
        QMetaObject.invokeMethod(viewport, "cancelFlick")
        check(viewport.property("contentX") < before, "a pointer drag scrolls hidden accounts into view")
        proxy.informationMessage.emit("Feedback before Other user")
        press(view, other, Qt.Key_Return)
        check(card.property("message") == "", "Other-user selection discards prior authentication feedback")
        username = find(root, "Username")
        check(username.isVisible() and view.activeFocusItem() == username,
              "Other user exposes and focuses the username input")
        check(any(item.property("text") == "Username" and item.isVisible() for item in walk(root)),
              "Other user has a visible Username prompt")
        username_hint = QQmlExpression(qmlContext(username), username,
                                       "inputMethodHints & Qt.ImhNoAutoUppercase").evaluate()[0]
        check(bool(username_hint), "the username field prevents automatic IME capitalization")
        check(not bool(QQmlExpression(qmlContext(reveal), reveal,
                                     "Accessible.checkable && Accessible.checked").evaluate()[0]),
              "the reveal toggle reports its unchecked state")
        password.setProperty("text", "test-input")
        proxy.logins.clear()
        press(view, password, Qt.Key_Return)
        check(not proxy.logins and card.property("message") == "Enter a username"
              and view.activeFocusItem() == username,
              "an empty Other-user name is reported and refocused")
        check(password.property("text") == "", "an empty-name submit clears the stale password")

        view.resize(1440, 480)
        QTest.qWait(20)
        check(card.y() + card.height() + 16 <= switcher.y(),
              "the account strip does not cover the login fields on a short screen")
        picker = next(item for item in walk(root) if accessible(item).startswith("Session:"))
        footer_top = min(picker.mapToScene(picker.boundingRect().topLeft()).y(),
                         find(root, "Sleep").mapToScene(find(root, "Sleep").boundingRect().topLeft()).y())
        check(switcher.y() + switcher.height() + 16 <= footer_top,
              "the account strip stays above the footer controls on a short screen")
        session = picker.parentItem()
        check(session.property("index") == 1 and session.property("selectedName") == "Plasma X11",
              "initial selection still honors the remembered session")
        option = find(root, "Other session")
        check(reachable(view, password, picker), "Tab reaches the session picker")
        press(view, picker, Qt.Key_Return)
        check(option.isVisible(), "Return opens the session menu")
        menu = next(item for item in walk(root) if item.property("open") is not None)
        check(menu.mapToScene(menu.boundingRect().topLeft()).y() >= 32,
              "an overfull session menu stays below the top screen margin")
        check(plain_labels(root, session_name), "session choices render markup literally")
        check(find(root, "Plasma").mapToScene(find(root, "Plasma").boundingRect().topLeft()).x() >= 0,
              "the open session menu is not clipped off the screen's left edge")
        if not option.isVisible():
            # Still exercise the delegate independently when the old pill ignores Return.
            pos = picker.mapToScene(picker.boundingRect().center()).toPoint()
            QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, pos)
        press(view, find(root, "Plasma"), Qt.Key_Down)
        check(view.activeFocusItem() == find(root, "Plasma X11"), "Down moves between session choices")
        final_session = find(root, session_name)
        press(view, final_session, Qt.Key_Down)
        first = find(root, "Plasma")
        check(view.activeFocusItem() == first and first.mapToScene(first.boundingRect().topLeft()).y() >= 32,
              "wrapped session focus scrolls the first choice fully onto the screen")
        press(view, final_session, Qt.Key_Up)
        scroller = next((item for item in walk(menu) if item.property("contentY") is not None), None)
        moved = False
        if scroller is not None:
            before = scroller.property("contentY")
            start = scroller.mapToScene(scroller.boundingRect().center()).toPoint()
            QTest.mousePress(view, Qt.LeftButton, Qt.NoModifier, start)
            for delta in (20, 60, 100):
                QTest.mouseMove(view, start + QPoint(0, delta), 30)
                QTest.qWait(30)
            QTest.mouseRelease(view, Qt.LeftButton, Qt.NoModifier, start + QPoint(0, 100))
            QMetaObject.invokeMethod(scroller, "cancelFlick")
            moved = scroller.property("contentY") < before
        check(moved, "a pointer drag reaches the overfull session list")
        press(view, final_session, Qt.Key_Space)
        QTest.qWait(50)
        check(session.property("index") == 15 and plain_labels(root, session_name),
              "the selected session pill renders its name literally")
        check(picker.width() <= 240, "a long selected session name stays inside a bounded pill")
        press(view, picker, Qt.Key_Return)
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
        reveal.setProperty("pressed", True)
        proxy.loginFailed.emit()
        QTest.qWait(10)
        check(password.property("text") == "", "failed login clears the password")
        check(not reveal.property("pressed"), "failed login resets password visibility")
        check(any(item.property("text") == "Login failed" and item.isVisible() for item in walk(root)),
              "an undiagnosed failure shows a generic login message")

        check(reachable(view, password, reveal), "Tab reaches password visibility")
        press(view, reveal, Qt.Key_Space)
        check(reveal.property("pressed"), "Space operates password visibility")
        check(QQmlExpression(qmlContext(reveal), reveal,
                            "Accessible.checkable && Accessible.checked").evaluate()[0],
              "the reveal toggle reports its checked state")
        password.forceActiveFocus()
        hints = QInputMethod.queryFocusObject(Qt.ImHints, None)
        hints = getattr(hints, "value", hints)
        required_hints = (Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData).value
        check(hints is not None and hints & required_hints == required_hints,
              "revealed password input still requests sensitive, nonpredictive IME handling")
        check(QQmlExpression(qmlContext(password), password,
                            'Accessible.passwordEdit && Accessible.description === qsTr("Password")').evaluate()[0],
              "revealed input retains protected semantics and a non-secret description")
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
        reveal.setProperty("pressed", False)
        password.forceActiveFocus()
        QGuiApplication.sendEvent(password, QInputMethodEvent("preedit-test", []))
        check(password.property("preeditText") == "preedit-test", "the IME fixture has active composition")
        proxy.loginFailed.emit()
        QTest.qWait(10)
        check(password.property("preeditText") == "" and not password.property("inputMethodComposing"),
              "clearing a password also resets uncommitted IME input")
        view.resize(480, 900)
        QTest.qWait(20)
        check(switcher.width() <= 416 and switcher.x() >= 32,
              "the account viewport follows a narrow screen")
        check(card.y() == 210 and switcher.y() == 600,
              "normal-height layouts keep the Login board's vertical positions")
        press(view, picker, Qt.Key_Return)
        press(view, final_session, Qt.Key_Space)
        QTest.qWait(50)
        power_row = find(root, "Sleep").parentItem().parentItem()
        power_left = power_row.mapToScene(power_row.boundingRect().topLeft()).x()
        check(picker.mapToScene(picker.boundingRect().topRight()).x() + 16 <= power_left,
              "a long session pill keeps a gap before the narrow-screen power controls")
        press(view, picker, Qt.Key_Return)
        power_top = power_row.mapToScene(power_row.boundingRect().topLeft()).y()
        check(menu.mapToScene(menu.boundingRect().bottomRight()).y() + 8 <= power_top,
              "the open session menu stays above every footer control")
        press(view, final_session, Qt.Key_Escape)
        proxy.logins.clear()

        def login_during_reset():
            # Exercise both the immediate signal handler and a later event-loop turn.
            for _ in range(2):
                password.setProperty("text", "test-input")
                press(view, password, Qt.Key_Return)
            check(not proxy.logins, "login is blocked while the session model is resetting")

        sessions.reset_rows([{"name": "Replacement"}], login_during_reset)
        QTest.qWait(50)
        check(session.property("index") == 0 and session.property("selectedName") == "Replacement",
              "a session reset replaces the old index and label coherently")
        sessions.rename_row(0, "Renamed session")
        QTest.qWait(50)
        check(session.property("selectedName") == "Renamed session", "selected session names follow model data changes")
        sessions.reset_rows([])
        QTest.qWait(50)
        proxy.logins.clear()
        password.setProperty("text", "test-input")
        press(view, password, Qt.Key_Return)
        check(session.property("index") == -1 and not proxy.logins, "an empty session model never sends an invalid index")
        check(any(item.property("text") == "No sessions available" and item.isVisible() for item in walk(root)),
              "an empty session model gives an actionable message")
        sessions.reset_rows([{"name": "Recovered"}, {"name": "Alternative"}])
        QTest.qWait(50)
        check(session.property("index") == 0 and session.property("selectedName") == "Recovered",
              "session selection recovers when entries reappear")
        proxy.logins.clear()
        password.setProperty("text", "test-input")
        press(view, password, Qt.Key_Return)
        check(proxy.logins == [("unlisted", "test-input", 0)], "recovered logins use the displayed session index")

        # Screen readers activate Accessible.Button items through pressAction, which is separate
        # from their key and pointer handlers. Exercise every custom control in the theme.
        keyboard.set_current(0)
        activate(layout)
        check(keyboard.current == 1, "assistive press changes the keyboard layout")
        activate(reveal)
        check(reveal.property("pressed"), "assistive press reveals the password")
        activate(reveal)
        check(not reveal.property("pressed"), "assistive press hides the password again")
        activate(find(root, "Person 2"))
        check(root.property("loginName") == "user2", "assistive press selects a listed account")
        activate(find(root, "Other user"))
        check(card.property("promptName") and view.activeFocusItem() == find(root, "Username"),
              "assistive press selects Other user")
        username.setProperty("text", "unlisted")
        password.setProperty("text", "test-input")
        proxy.logins.clear()
        activate(find(root, "Sign in"))
        check(proxy.logins == [("unlisted", "test-input", 0)],
              "assistive press submits the sign-in fields")
        activate(picker)
        recovered_choice = find(root, "Recovered")
        check(recovered_choice.isVisible(), "assistive press opens the session menu")
        activate(recovered_choice)
        check(session.property("index") == 0 and not recovered_choice.isVisible(),
              "assistive press chooses a session")
        for label, action in (("Sleep", "sleep"), ("Restart", "restart"), ("Shut down", "power")):
            proxy.actions.clear()
            activate(find(root, label))
            check(proxy.actions == [action], f"assistive press triggers {label.lower()} once")
        check(not warnings, "theme behavior emits no unexpected QML warnings")
        for warning in warnings:
            print("QML", warning)
        view.close()
        view.setSource(QUrl())
        app.processEvents()
    print(f"SDDM behavior: {checks - failures}/{checks} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
