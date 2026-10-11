#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The notification cards of quick settings' history, fed by Plasma's own notification server on a
private D-Bus bus (offscreen, the staged package).

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 tests/notifications_card_test.py STAGE_HOME
Requires PySide6, python3-dbus, python3-gobject, Pillow-free Qt image writing (QImage) and Plasma's
org.kde.notificationmanager QML module. STAGE_HOME is a tools/build.sh stage (the cards use the
shared blocks the build copies in).

The real Backend.qml and its notification service run the server; tests/notify_client.py sends
notifications like an application, in its own process (this one answers the server's calls), and
reports the actions and replies the cards send back. Files opened from a card reach a URL handler
here instead of a file manager.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

os.environ.setdefault("QT_QUICK_BACKEND", "software")
# Notifications from applications without a desktop file stay out of the history (Plasma's default
# plasmanotifyrc, [Applications][@other] ShowInHistory=false): the test's applications get one.
data_home = Path(tempfile.mkdtemp(prefix="pf-notify-data-"))
(data_home / "applications").mkdir()
for entry, name in (("org.plasmafusion.notifytest", "Notify test"), ("org.plasmafusion.notifyother", "Other test")):
    (data_home / "applications" / (entry + ".desktop")).write_text(
        "[Desktop Entry]\nType=Application\nName=%s\nExec=true\nIcon=dialog-information\n" % name)
os.environ["XDG_DATA_HOME"] = str(data_home)
import dbus  # noqa: E402
from PySide6.QtCore import Q_ARG, Q_RETURN_ARG, QMetaObject, QObject, QPoint, Qt, QUrl, Slot  # noqa: E402
from PySide6.QtGui import QColor, QDesktopServices, QGuiApplication, QImage  # noqa: E402
from PySide6.QtQuick import QQuickView  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

here = Path(__file__).resolve().parent
bus = dbus.SessionBus()
if bus.name_has_owner("org.freedesktop.Notifications") or bus.name_has_owner("org.kde.plasmashell"):
    raise SystemExit("Run on a fresh private bus; refusing a live desktop bus")
stage = Path(sys.argv[1]).resolve() / ".local/share/plasma/plasmoids/org.plasmafusion.quicksettings/contents/ui"


class Context(QObject):
    """The i18n functions Plasma provides (KLocalizedContext), without translations."""

    @staticmethod
    def fill(text, args):
        for number, arg in enumerate(args, 1):
            text = text.replace("%" + str(number), str(arg))
        return text

    @Slot(str, result=str)
    @Slot(str, str, result=str)
    @Slot(str, str, str, result=str)
    def i18n(self, text, a1=None, a2=None):
        return self.fill(text, [a for a in (a1, a2) if a is not None])

    @Slot(str, str, result=str)
    @Slot(str, str, str, result=str)
    @Slot(str, str, str, str, result=str)
    def i18nc(self, context, text, a1=None, a2=None):
        return self.fill(text, [a for a in (a1, a2) if a is not None])

    @Slot(str, str, str, int, result=str)
    @Slot(str, str, str, int, str, result=str)
    def i18ncp(self, context, singular, plural, count, a2=None):
        return self.fill(singular if count == 1 else plural, [count] + ([a2] if a2 is not None else []))


class Opened(QObject):
    """Takes the URLs the cards open (QDesktopServices handler)."""

    def __init__(self):
        super().__init__()
        self.urls = []

    @Slot(QUrl)
    def open(self, url):
        self.urls.append(url.toString())


HARNESS = """
import QtQuick
import "file://%(ui)s" as UI
import "file://%(ui)s/components" as C
Item {
    id: root
    width: 380
    height: 1400
    property var opened: []
    property int closes: 0
    UI.Backend { id: backend; objectName: "backend" }
    C.FusionMetrics { id: fusionMetrics }
    // The sheet's list (PopupContent.qml): the same card and the same calls.
    ListView {
        id: list
        objectName: "list"
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        interactive: false
        model: backend.notif.model
        delegate: UI.NotificationCard {
            width: ListView.view.width
            pal: backend.pal
            metrics: fusionMetrics
            onActionInvoked: name => backend.notif.invokeAction(index, name, !!model.resident)
            onReplied: text => backend.notif.reply(index, text, !!model.resident)
            onUrlOpened: url => {
                backend.notif.openUrl(index, url);
                ++root.closes;
            }
            onCloseClicked: backend.notif.close(index)
            onKillJobClicked: backend.notif.killJob(index)
        }
    }

    // Lookups for the test, in QML (walking the item tree from Python trips over some types).
    function cardOf(summary) {
        for (const item of list.contentItem.children) {
            if (item.entry !== undefined && item.bodyParts !== undefined && item.entry && item.entry.summary === summary) {
                return item;
            }
        }
        return null;
    }
    function findIn(item, name) {
        if (!item) {
            return null;
        }
        if (item.objectName === name) {
            return item;
        }
        for (const child of item.children) {
            const found = findIn(child, name);
            if (found) {
                return found;
            }
        }
        return null;
    }
    function target(summary, name) {
        const card = cardOf(summary);
        return name ? findIn(card, name) : card;
    }
    // Geometry and chosen properties of an item of a card, as JSON ("" when there is none).
    function info(summary, name, props) {
        const card = cardOf(summary);
        const item = target(summary, name);
        if (!item) {
            return "";
        }
        const at = item.mapToItem(null, 0, 0);
        const result = { visible: item.visible, x: at.x, y: at.y, width: item.width, height: item.height,
                         cardX: card.mapToItem(null, 0, 0).x, cardWidth: card.width };
        for (const key of props) {
            const value = item[key];
            result[key] = value !== null && typeof value === "object" && !Array.isArray(value) ? String(value) : value;
        }
        return JSON.stringify(result);
    }
    function focusOn(summary, name) {
        target(summary, name).forceActiveFocus(Qt.TabFocusReason);
    }
}
""" % {"ui": stage}

app = QGuiApplication(sys.argv[:1])
opened = Opened()
QDesktopServices.setUrlHandler("file", opened, "open")
view = QQuickView()
context = Context()
view.rootContext().setContextObject(context)
tmp = Path(tempfile.mkdtemp(prefix="pf-notify-"))
(tmp / "harness.qml").write_text(HARNESS)
view.setSource(QUrl.fromLocalFile(str(tmp / "harness.qml")))
if view.status() == QQuickView.Error:
    raise SystemExit("Harness failed to load: " + "; ".join(e.toString() for e in view.errors()))
root = view.rootObject()
view.resize(380, 1400)
view.show()
view.requestActivate()
QTest.qWaitForWindowActive(view)
checks = 0
clients = []


def wait_for(predicate, message, seconds=5):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        QTest.qWait(20)
        if predicate():
            return
    raise AssertionError(message)


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


def info(summary, name="", *props):
    text = QMetaObject.invokeMethod(root, "info", Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", summary),
                                    Q_ARG("QVariant", name), Q_ARG("QVariant", list(props)))
    return json.loads(text) if text else None


def focus(summary, name=""):
    QMetaObject.invokeMethod(root, "focusOn", Q_ARG("QVariant", summary), Q_ARG("QVariant", name))


def click(summary, name=""):
    item = info(summary, name)
    point = QPoint(round(item["x"] + item["width"] / 2), round(item["y"] + item["height"] / 2))
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, point)


def notify(summary, body, *options, entry="org.plasmafusion.notifytest"):
    proc = subprocess.Popen([sys.executable, "-B", str(here / "notify_client.py"), "notify", summary, body,
                             "--entry", entry, *options],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    proc.lines = []
    threading.Thread(target=lambda: [proc.lines.append(line.strip()) for line in proc.stdout], daemon=True).start()
    clients.append(proc)
    wait_for(lambda: info(summary) is not None, "no card for %r" % summary)
    QTest.qWait(150)
    return proc


def type_text(text):
    for char in text:
        QTest.keyClick(view, char)


def png(name, width, height, colour):
    image = QImage(width, height, QImage.Format_ARGB32)
    image.fill(QColor(colour))
    path = tmp / name
    image.save(str(path))
    return path


backend = root.findChild(QObject, "backend")
wait_for(lambda: bus.name_has_owner("org.freedesktop.Notifications"), "Plasma's notification server did not register")
try:
    # ---- Images: the notification's own, in the body, and a linked file.
    side = png("side.png", 96, 64, "#e05a2b")
    wide = png("wide.png", 1200, 300, "#2b7de0")
    shot = png("screenshot.png", 800, 450, "#33aa55")
    notify("With an image", "A picture beside the text", "--image", str(side))
    image = info("With an image", "notificationImage", "valid")
    check(image["visible"] and image["valid"], "the notification's image is drawn on its card")
    check(image["width"] == image["height"] == 48, "at Plasma's large icon size, as the stock applet (%gx%g)"
          % (image["width"], image["height"]))
    check(image["x"] - image["cardX"] > image["cardWidth"] / 2, "beside the text, on the right")

    notify("Body image", 'Look: <img src="%s" alt="wide"/> done' % QUrl.fromLocalFile(str(wide)).toString())
    wait_for(lambda: (info("Body image", "bodyImage") or {}).get("visible"), "the body's image is not drawn")
    body = info("Body image", "bodyImage")
    inset = body["x"] - body["cardX"]
    check(inset > 8 and abs(body["width"] - (body["cardWidth"] - 2 * inset)) < 1,
          "an image in the body is fitted to the card (%g px of %g)" % (body["width"], body["cardWidth"]))
    check(abs(body["width"] / body["height"] - 4) < 0.05, "its aspect kept (%gx%g)" % (body["width"], body["height"]))
    text = json.loads(QMetaObject.invokeMethod(root, "info", Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", "Body image"),
                                               Q_ARG("QVariant", ""), Q_ARG("QVariant", ["bodyText"])) or "{}")
    check("<img" not in text.get("bodyText", "<img") and "Look:" in text.get("bodyText", ""), "the text is drawn without the tag")

    notify("Screenshot taken", "Saved", "--url", QUrl.fromLocalFile(str(shot)).toString())
    wait_for(lambda: info("Screenshot taken", "notificationThumbnail", "previewKind")["previewKind"] in ("image", "kio"),
             "the linked file has no preview")
    thumb = info("Screenshot taken", "notificationThumbnail", "previewKind")
    check(thumb["visible"] and thumb["height"] == 128, "a linked file is previewed in a strip of the enormous icon size")
    click("Screenshot taken", "notificationThumbnail")
    wait_for(lambda: opened.urls, "clicking the preview did not open the file")
    check(opened.urls[-1] == QUrl.fromLocalFile(str(shot)).toString(), "clicking the preview opens the file")
    check(root.property("closes") == 1, "and asks the sheet to close")
    opened.urls.clear()
    focus("Screenshot taken", "notificationThumbnail")
    QTest.keyClick(view, Qt.Key_Return)
    wait_for(lambda: opened.urls, "Return on the preview did not open the file")
    check(True, "the preview opens from the keyboard too")

    # ---- Inline reply: the field at once when replying is all the notification offers.
    chat = notify("Message from Ana", "Are you coming?", "--reply", "Reply")
    row = info("Message from Ana", "replyRow")
    check(row["visible"] and not info("Message from Ana", "replyButton")["visible"],
          "reply as the only action: the field is shown at once, no Reply button")
    check(info("Message from Ana", "replyField", "placeholderText")["placeholderText"] == "Reply to the test…",
          "the app's placeholder text")
    check(not info("Message from Ana", "replySend", "enabled")["enabled"], "Send waits for text")
    focus("Message from Ana", "replyField")
    type_text("On my way")
    QTest.keyClick(view, Qt.Key_Return)
    wait_for(lambda: "reply On my way" in chat.lines, "the reply did not reach the app (%r)" % chat.lines)
    check(True, "Return sends the reply to the app")
    wait_for(lambda: info("Message from Ana") is None, "the notification stayed after the reply")
    check(True, "and the notification closes, as in the stock applet")

    # A Reply button first when there are other actions; Escape goes back to them.
    chat = notify("Message from Bo", "Lunch?", "--reply", "Answer", "--action", "later=Later")
    button = info("Message from Bo", "replyButton", "text")
    check(button["visible"] and button["text"] == "Answer" and not info("Message from Bo", "replyRow")["visible"],
          "with other actions: the app's Reply label first, the field closed")
    focus("Message from Bo", "replyButton")
    QTest.keyClick(view, Qt.Key_Space)
    wait_for(lambda: info("Message from Bo", "replyField", "activeFocus")["activeFocus"], "the field did not take the focus")
    check(info("Message from Bo", "replyRow")["visible"], "the Reply button opens the field, with the focus")
    QTest.keyClick(view, Qt.Key_Escape)
    wait_for(lambda: not info("Message from Bo", "replyRow")["visible"], "Escape did not close the field")
    check(info("Message from Bo", "replyButton")["visible"], "Escape goes back to the actions")
    click("Message from Bo", "replyButton")
    type_text("Yes")
    click("Message from Bo", "replySend")
    wait_for(lambda: "reply Yes" in chat.lines, "Send did not reach the app (%r)" % chat.lines)
    check(True, "Send sends the reply")
    print(f"Notification cards: {checks} checks, 0 failures")
finally:
    for proc in clients:
        if proc.poll() is None:
            proc.stdin.close()
    deadline = time.monotonic() + 5
    while any(p.poll() is None for p in clients) and time.monotonic() < deadline:
        QTest.qWait(20)
    for proc in clients:
        if proc.poll() is None:
            proc.kill()
