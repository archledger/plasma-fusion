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

# The sheet's backend loads Plasma's clipboard module, whose Klipper code asks the platform for X11
# when the offscreen platform offers it and crashes on the missing connection
# (clipboard_sheet_test.py does the same).
os.environ["QT_QPA_OFFSCREEN_NO_GLX"] = "1"
os.environ.setdefault("QT_QUICK_BACKEND", "software")
# Notifications from applications without a desktop file stay out of the history (Plasma's default
# plasmanotifyrc, [Applications][@other] ShowInHistory=false): the test's applications get one.
data_home = Path(tempfile.mkdtemp(prefix="pf-notify-data-"))
(data_home / "applications").mkdir()
for entry, name in (("org.plasmafusion.notifytest", "Notify test"), ("org.plasmafusion.notifyother", "Other test"),
                    ("org.plasmafusion.notifythird", "Third test"), ("org.plasmafusion.notifyfourth", "Fourth test")):
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
    // The Notification Centre's card menu: on in the second part of the keyboard checks.
    property bool menusOn: false
    property int menuRequests: 0
    UI.Backend { id: backend; objectName: "backend" }
    C.FusionMetrics { id: fusionMetrics }
    // The sheet's list (PopupContent.qml and the tablet Notification Centre use the same component):
    // the same rows, transitions and calls.
    UI.NotificationList {
        id: list
        objectName: "list"
        x: 12
        y: 12
        width: root.width - 24
        spacing: 10
        notif: backend.notif
        pal: backend.pal
        metrics: fusionMetrics
        motion: backend.pal.motion
        menus: root.menusOn
        onDone: ++root.closes
        onMenuRequested: ++root.menuRequests
    }
    // The tablet Notification Centre's content: the same rows in its own scrolling list. Made when
    // the overlap section turns it on, so it lists the notifications that arrive after it.
    property bool centreOn: false
    property real centreHeight: 1400
    // The backend under another name: inside the Centre's declaration `backend` is its own property.
    readonly property var backendItem: backend
    C.Motion { id: centreMotion }
    Loader {
        id: centre
        objectName: "centre"
        active: root.centreOn
        width: root.width
        height: root.centreHeight
        sourceComponent: UI.NotificationCentreContent {
            backend: root.backendItem
            metrics: fusionMetrics
            motion: centreMotion
            shown: true
        }
    }
    // The Centre's list (a ListView) and the row items it made.
    function centreView() {
        return centre.item ? findIn(centre.item, "notificationCentreList") : null;
    }
    function centreRows() {
        const view = centreView();
        if (!view) {
            return [];
        }
        // A ListView's rows are its contentItem's children; a Flickable holding a Column (as this PR
        // first had it; its red run) has the Column there.
        const kids = view.contentItem.children;
        return kids.length === 1 && kids[0].isGroup === undefined ? kids[0].children : kids;
    }
    function sheetRowCount() {
        return Array.from(listRows()).filter(item => item.isGroup !== undefined && item.visible && item.entry).length;
    }
    // The row at the top of the Centre's view (what someone reading it sees first).
    function centreTopRow() {
        const view = centreView();
        const item = view ? view.itemAt(view.width / 2, view.contentY + 10) : null;
        return item && item.entry ? (item.isGroup ? "group:" + item.entry.applicationName : String(item.entry.summary)) : "";
    }
    function centreScroll(offset) {
        const view = centreView();
        view.contentY = view.originY + offset;
    }

    function centreLoaded() {
        return centre.status === Loader.Ready && centre.item !== null;
    }
    function centreRowCount() {
        return Array.from(centreRows()).filter(item => item.isGroup !== undefined && item.visible && item.entry).length;
    }

    // Lookups for the test, in QML (walking the item tree from Python trips over some types).
    // The list's row items: the Column's children (a ListView keeps them in its contentItem; the red
    // run of the overlap check stages the old ListView in this component).
    function listRows() {
        return list.contentItem ? list.contentItem.children : list.children;
    }
    // The card of a notification, or with `group` the header row of an app's group.
    function cardOf(summary) {
        for (const item of listRows()) {
            if (item.card !== undefined && item.card && item.card.entry && item.card.entry.summary === summary) {
                return item.card;
            }
        }
        return null;
    }
    function groupOf(appName) {
        for (const item of listRows()) {
            if (item.isGroup === true && item.entry && item.entry.applicationName === appName) {
                return item;
            }
        }
        return null;
    }
    // The rows as the list shows them, top to bottom: "group:App" or the summary.
    function rows() {
        const result = [];
        const items = Array.from(listRows()).filter(item => item.isGroup !== undefined && item.visible && item.entry)
                                               .sort((a, b) => a.y - b.y);
        for (const item of items) {
            result.push(item.isGroup ? "group:" + item.entry.applicationName : String(item.entry.summary));
        }
        return JSON.stringify(result);
    }
    // What the list would draw over itself: a row that starts inside the one above it, a card that
    // runs into the next row, a summary or body whose wrapped lines are taller than its box. Each
    // problem is a sentence with the numbers; an empty list is a clean layout.
    function layoutProblems(which) {
        const problems = [];
        const items = Array.from(which === "centre" ? centreRows() : listRows()).filter(item => item.isGroup !== undefined && item.visible && item.entry)
                                               .sort((a, b) => a.y - b.y);
        const label = item => item.isGroup ? "the " + item.entry.applicationName + " header" : '"' + item.entry.summary + '"';
        for (let i = 0; i < items.length; ++i) {
            const item = items[i];
            const next = items[i + 1];
            if (next && next.y < item.y + item.height - 0.5) {
                problems.push(label(next) + " starts " + Math.round(item.y + item.height - next.y) + " px inside " + label(item));
            }
            const card = item.card;
            if (!card || !card.visible) {
                continue;
            }
            const cardBottom = item.y + card.mapToItem(item, 0, 0).y + card.height;
            if (next && cardBottom > next.y + 0.5) {
                problems.push("the card " + label(item) + " runs " + Math.round(cardBottom - next.y) + " px into " + label(next));
            }
            for (const name of ["summary", "body"]) {
                const text = findIn(card, name);
                if (text && text.visible && text.contentHeight > text.height + 0.5) {
                    problems.push(name + " of " + label(item) + ": " + Math.round(text.contentHeight) + " px of text in a "
                                  + Math.round(text.height) + " px box (" + text.lineCount + " lines)");
                }
            }
        }
        return JSON.stringify(problems);
    }
    function groupInfo(appName, name) {
        const group = groupOf(appName);
        const item = group ? (name ? findIn(group, name) : group) : null;
        if (!item) {
            return "";
        }
        const at = item.mapToItem(null, 0, 0);
        return JSON.stringify({ visible: item.visible, x: at.x, y: at.y, width: item.width, height: item.height,
                                text: item.text !== undefined ? String(item.text) : "" });
    }
    // The footer ("Show N More") under the last listed card of an app.
    function footerOf(appName) {
        let last = null;
        for (const item of listRows()) {
            if (item.isGroup === false && item.entry && item.entry.isInGroup && item.entry.applicationName === appName
                    && item.footer.shown) {
                last = item;
            }
        }
        const button = last ? findIn(last, "groupFooter") : null;
        if (!button) {
            return "";
        }
        const at = button.mapToItem(null, 0, 0);
        return JSON.stringify({ visible: button.visible, x: at.x, y: at.y, width: button.width, height: button.height,
                                text: String(button.text) });
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


def js(name, *args):
    text = QMetaObject.invokeMethod(root, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", a) for a in args])
    return json.loads(text) if text else None


def click_at(item):
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier,
                     QPoint(round(item["x"] + item["width"] / 2), round(item["y"] + item["height"] / 2)))


def focus(summary, name=""):
    QMetaObject.invokeMethod(root, "focusOn", Q_ARG("QVariant", summary), Q_ARG("QVariant", name))


def click(summary, name=""):
    # A row that has just appeared is laid out on the next frames.
    wait_for(lambda: (info(summary, name) or {}).get("width", 0) > 4, "%s of %r has no size" % (name, summary))
    QTest.qWait(100)
    item = info(summary, name)
    point = QPoint(round(item["x"] + item["width"] / 2), round(item["y"] + item["height"] / 2))
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, point)


def start(*args):
    proc = subprocess.Popen([sys.executable, "-B", str(here / "notify_client.py"), *args],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    proc.lines = []
    threading.Thread(target=lambda: [proc.lines.append(line.strip()) for line in proc.stdout], daemon=True).start()
    clients.append(proc)
    return proc


def job(title, *options, entry="org.plasmafusion.notifytest"):
    proc = start("job", title, "--entry", entry, *options)
    wait_for(lambda: info(title) is not None, "no card for the job %r" % title)
    return proc


def notify(summary, body, *options, entry="org.plasmafusion.notifytest"):
    app = {"org.plasmafusion.notifytest": "Notify test", "org.plasmafusion.notifyother": "Other test",
           "org.plasmafusion.notifythird": "Third test", "org.plasmafusion.notifyfourth": "Fourth test"}[entry]
    proc = subprocess.Popen([sys.executable, "-B", str(here / "notify_client.py"), "notify", summary, body,
                             "--entry", entry, "--app", app, *options],
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
    # Drawn once loaded, then laid out to the card on the next frames.
    wait_for(lambda: (info("Body image", "bodyImage") or {}).get("visible")
             and info("Body image", "bodyImage")["width"] < info("Body image")["width"], "the body's image is not drawn")
    body = info("Body image", "bodyImage")
    inset = body["x"] - body["cardX"]
    check(inset > 8 and abs(body["width"] - (body["cardWidth"] - 2 * inset)) < 1,
          "an image in the body is fitted to the card (%g px of %g)" % (body["width"], body["cardWidth"]))
    check(abs(body["width"] / body["height"] - 4) < 0.05, "its aspect kept (%gx%g)" % (body["width"], body["height"]))
    decoded = info("Body image", "bodyImage", "implicitWidth", "implicitHeight")
    check(decoded["implicitWidth"] <= body["width"] + 1 and decoded["implicitHeight"] <= body["height"] + 1,
          "decoded at the size it is drawn, not at its own 1200x300 (%gx%g)" % (decoded["implicitWidth"], decoded["implicitHeight"]))
    tall = png("tall.png", 300, 1200, "#aaaa33")
    notify("Tall body image", 'Poster: <img src="%s" alt="tall"/>' % QUrl.fromLocalFile(str(tall)).toString())
    wait_for(lambda: (info("Tall body image", "bodyImage") or {}).get("visible"), "the tall body image is not drawn")
    QTest.qWait(100)
    poster = info("Tall body image", "bodyImage", "implicitWidth", "implicitHeight")
    check(poster["implicitHeight"] <= poster["height"] + 1 and abs(poster["width"] / poster["height"] - 0.25) < 0.05,
          "a tall one is decoded at the height it is drawn, its aspect kept (%gx%g)" % (poster["implicitWidth"], poster["implicitHeight"]))
    small = png("small.png", 60, 40, "#aa33aa")
    notify("Small body image", 'Icon: <img src="%s" alt="small"/>' % QUrl.fromLocalFile(str(small)).toString())
    wait_for(lambda: (info("Small body image", "bodyImage") or {}).get("visible"), "the small body image is not drawn")
    QTest.qWait(100)
    little = info("Small body image", "bodyImage", "implicitWidth", "implicitHeight")
    check(little["implicitWidth"] == 60 and little["implicitHeight"] == 40 and abs(little["width"] - 60) < 1,
          "a smaller one keeps its own size, not scaled up (%gx%g)" % (little["width"], little["height"]))
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

    # ---- File jobs: a finished copy of one file offers Open and Open Containing Folder.
    files = start("filemanager")
    wait_for(lambda: "ready" in files.lines, "the stand-in file manager did not start")
    src, dst = tmp / "src", tmp / "dst"
    src.mkdir()
    dst.mkdir()
    (dst / "report.pdf").write_bytes(b"%PDF-1.4\n")
    copy = job("Copying", "--source", str(src / "report.pdf"), "--dest", str(dst / "report.pdf"))
    wait_for(lambda: "finished" in copy.lines, "the copy did not finish")
    wait_for(lambda: info("Copying", "summary", "text")["text"] == "Copying (Finished)", "no finished summary")
    check(True, "a finished job says so, as the stock applet: \"Copying (Finished)\"")
    body = info("Copying", "body", "text")
    check(body["visible"] and "report.pdf" in body["text"] and "href" in body["text"],
          "its text is shown, with the link to the destination: %r" % body["text"])
    check(not info("Copying", "jobProgress")["visible"], "no progress bar once finished")
    QTest.qWait(300)
    check(info("Copying", "jobOpen")["visible"] and info("Copying", "jobFolder")["visible"],
          "one file (it exists): Open and Open Containing Folder")
    opened.urls.clear()
    click("Copying", "jobOpen")
    wait_for(lambda: opened.urls, "Open did not open the file")
    check(opened.urls[-1] == QUrl.fromLocalFile(str(dst / "report.pdf")).toString(), "Open opens the copied file")
    focus("Copying", "jobFolder")
    QTest.keyClick(view, Qt.Key_Return)
    wait_for(lambda: any(line.startswith("show ") for line in files.lines), "the folder was not shown")
    check(("show " + QUrl.fromLocalFile(str(dst / "report.pdf")).toString()) in files.lines,
          "Open Containing Folder shows the file selected in the file manager (FileManager1.ShowItems)")

    # Several files: the destination folder itself.
    many = job("Copying 3 files", "--files", "3", "--source", str(src), "--dest", str(dst))
    wait_for(lambda: "finished" in many.lines and info("Copying 3 files", "jobFolder")["visible"],
             "the folder button of a finished multi-file copy is missing")
    check(not info("Copying 3 files", "jobOpen")["visible"], "several files: no Open, only the folder")
    opened.urls.clear()
    click("Copying 3 files", "jobFolder")
    wait_for(lambda: opened.urls, "the folder did not open")
    check(opened.urls[-1] == QUrl.fromLocalFile(str(dst)).toString(), "it opens the destination folder")

    # A copy whose file is gone (cancelled, moved or deleted since; Dolphin reports a cancelled
    # copy as finished without an error, ThinkPad 2026-10-11): finished, but nothing to open, as
    # the stock applet's JobItem hides its file buttons for a file that does not exist.
    gone = job("Copying gone", "--source", str(src / "gone.iso"), "--dest", str(dst / "gone.iso"))
    wait_for(lambda: "finished" in gone.lines and info("Copying gone", "summary", "text")["text"] == "Copying gone (Finished)",
             "no finished summary for the gone file")
    QTest.qWait(500)
    check(not info("Copying gone", "jobFiles")["visible"], "a finished copy whose file is gone offers no Open or folder")

    # A failed copy: why, and nothing to open.
    failed = job("Moving", "--source", str(src / "big.iso"), "--dest", str(dst / "big.iso"), "--fail", "No space left on device")
    wait_for(lambda: "finished" in failed.lines and info("Moving", "summary", "text")["text"] == "Moving (Failed)",
             "no failed summary")
    body = info("Moving", "body", "text")
    check(body["visible"] and "No space left on device" in body["text"], "a failed job shows the error text: %r" % body["text"])
    check(not info("Moving", "jobFiles")["visible"], "and offers no file to open")

    # A running copy that can be paused and cancelled.
    running = job("Downloading", "--running", "--suspendable", "--killable", "--source", str(src / "a"), "--dest", str(dst / "a"))
    wait_for(lambda: info("Downloading", "jobProgress")["visible"], "no progress bar while running")
    pause, cancel = info("Downloading", "jobPause", "text"), info("Downloading", "jobCancel")
    check(pause["visible"] and pause["text"] == "Pause" and cancel["visible"],
          "a running job offers Pause and Cancel (%r, %r)" % (pause, cancel))
    click("Downloading", "jobPause")
    wait_for(lambda: "suspend" in running.lines, "Pause did not reach the job")
    wait_for(lambda: info("Downloading", "jobPause", "text")["text"] == "Resume", "no Resume after pausing")
    check(info("Downloading", "summary", "text")["text"] == "Downloading (Paused)", "paused: \"Downloading (Paused)\" and Resume")
    click("Downloading", "jobPause")
    wait_for(lambda: "resume" in running.lines, "Resume did not reach the job")
    check(True, "Resume resumes it")
    click("Downloading", "jobCancel")
    wait_for(lambda: "cancel" in running.lines, "Cancel did not reach the job")
    check(True, "Cancel cancels it")

    # ---- Grouped by app, as the stock applet's history: a header, two notifications, Show N More.
    for number in range(1, 5):
        notify("Mail %d" % number, "From the group test", entry="org.plasmafusion.notifyother")
    QTest.qWait(300)
    rows = js("rows")
    check(rows.count("group:Other test") == 1, "an app with several notifications gets one group header: %r" % rows)
    at = rows.index("group:Other test")
    check(rows[at + 1:at + 5] == ["Mail 4", "Mail 3", "Mail 2", "Mail 1"],
          "unread notifications are all listed under it, newest first (stock expandUnread): %r" % rows[at:at + 5])
    check(js("groupInfo", "Other test", "groupClose")["visible"], "the header has Close Group")
    title = info("Mail 4", "headerText", "text")
    check(title["text"] == "Mail 4" and not info("Mail 4", "summary")["visible"],
          "in a group the card's header line carries the summary (the header names the app)")
    QMetaObject.invokeMethod(backend.property("notif"), "markRead")
    wait_for(lambda: len([r for r in js("rows") if r.startswith("Mail ")]) == 2, "read groups did not collapse to two")
    rows = js("rows")
    check([r for r in rows if r.startswith("Mail ")] == ["Mail 4", "Mail 3"], "once read, a group lists its two newest")
    footer = js("footerOf", "Other test")
    check(footer and footer["visible"] and footer["text"] == "Show 2 More", "with \"Show 2 More\" under them: %r" % footer)
    click_at(footer)
    wait_for(lambda: len([r for r in js("rows") if r.startswith("Mail ")]) == 4, "Show 2 More did not expand the group")
    footer = js("footerOf", "Other test")
    check(footer["text"] == "Show Fewer", "expanded: all four, and Show Fewer")
    click_at(footer)
    wait_for(lambda: len([r for r in js("rows") if r.startswith("Mail ")]) == 2, "Show Fewer did not collapse the group")
    check(True, "Show Fewer collapses it again")
    click_at(js("groupInfo", "Other test", "groupClose"))
    wait_for(lambda: not any(r.startswith("Mail ") or r == "group:Other test" for r in js("rows")),
             "Close Group left notifications")
    check(True, "Close Group closes all of the app's notifications, hidden ones too")

    # Clear all reaches the notifications a collapsed group hides.
    for number in range(1, 5):
        notify("Note %d" % number, "To be cleared", entry="org.plasmafusion.notifyother")
    QMetaObject.invokeMethod(backend.property("notif"), "markRead")
    wait_for(lambda: len([r for r in js("rows") if r.startswith("Note ")]) == 2, "the group did not collapse")
    QMetaObject.invokeMethod(backend.property("notif"), "clearAll")
    wait_for(lambda: not any(r.startswith("Note ") for r in js("rows")), "Clear all left notifications")
    QTest.qWait(300)
    check(not any(r.startswith("Note ") or r == "group:Other test" for r in js("rows")),
          "Clear all also closes the notifications a collapsed group hides")

    # ---- Configure: the app's notification settings from the card (the app's own "settings"
    # action here, which reaches the test client instead of opening System Settings).
    app = notify("Settings test", "With a settings action", "--action", "settings=Notification Settings",
                 entry="org.plasmafusion.notifythird")
    button = info("Settings test", "configureButton", "text", "opacity")
    check(button["text"] == "Notification Settings", "the card has Configure, with the app's label: %r" % button["text"])
    check(info("Settings test", "closeButton", "opacity") is not None, "beside the close button")
    focus("Settings test", "configureButton")
    wait_for(lambda: info("Settings test", "configureButton")["visible"], "Configure is not shown")
    QTest.qWait(100)
    shown = js("info", "Settings test", "", ["buttonsShown"])["buttonsShown"]
    check(shown, "keyboard focus on it shows the card's buttons (as hover does)")
    closes = root.property("closes")
    QTest.keyClick(view, Qt.Key_Return)
    wait_for(lambda: "action settings" in app.lines, "Configure did not reach the app (%r)" % app.lines)
    check(root.property("closes") == closes + 1, "Configure opens the app's settings and closes the sheet")
    for number in (1, 2):
        notify("Grouped %d" % number, "In a group", entry="org.plasmafusion.notifythird")
    wait_for(lambda: js("groupInfo", "Third test", "groupConfigure"), "no group header for the third app")
    check(js("groupInfo", "Third test", "groupConfigure")["visible"], "an app's group header has Configure")
    check(not info("Grouped 2", "configureButton")["visible"], "and its cards do not repeat it (as the stock applet)")

    # ---- Keyboard: the card's default action, Delete, the menu.
    app = notify("Meeting at 3", "Room 2", "--action", "default=Open", entry="org.plasmafusion.notifyother")
    focus("Meeting at 3")
    card = js("info", "Meeting at 3", "", ["activeFocus", "activeFocusOnTab"])
    check(card["activeFocus"] and card["activeFocusOnTab"], "the card takes keyboard focus and is in the tab chain")
    closes = root.property("closes")
    QTest.keyClick(view, Qt.Key_Return)
    wait_for(lambda: "action default" in app.lines, "Return did not run the default action (%r)" % app.lines)
    check(root.property("closes") == closes + 1, "Return runs the default action and closes the sheet")
    notify("Old news", "To be deleted", entry="org.plasmafusion.notifyother")
    focus("Old news")
    QTest.keyClick(view, Qt.Key_Delete)
    wait_for(lambda: info("Old news") is None, "Delete did not close the card")
    check(True, "Delete closes the focused card")
    notify("With a menu", "Long press, right click or the Menu key", entry="org.plasmafusion.notifyother")
    root.setProperty("menusOn", True)
    focus("With a menu")
    QTest.keyClick(view, Qt.Key_Menu)
    wait_for(lambda: root.property("menuRequests") == 1, "the Menu key did not ask for the card's menu")
    check(True, "the Menu key asks for the Notification Centre's card menu")
    QTest.keyClick(view, Qt.Key_F10, Qt.ShiftModifier)
    wait_for(lambda: root.property("menuRequests") == 2, "Shift+F10 did not ask for the card's menu")
    check(True, "so does Shift+F10")
    item = info("With a menu")
    QTest.mouseClick(view, Qt.RightButton, Qt.NoModifier, QPoint(round(item["x"] + 40), round(item["y"] + 40)))
    wait_for(lambda: root.property("menuRequests") == 3, "a right click did not ask for the card's menu")
    check(True, "and a right click")

    # ---- The sheet's list (PopupContent.qml) and the closing that marks the notifications read
    # (main.qml) follow the same notif.listShown: with Show notifications off the sheet has no list,
    # so opening and closing it must leave them unread.
    notif = backend.property("notif")
    notify("Unseen", "Listed only while the list is on the sheet", entry="org.plasmafusion.notifythird")
    backend.setProperty("page", "main")
    backend.setProperty("showEmptyNotifications", False)
    check(notif.property("listShown") is True, "the main page lists the notifications")
    backend.setProperty("showNotifications", False)
    check(notif.property("available") is False and notif.property("listShown") is False,
          "Show notifications off: no list on the sheet, so nothing counts as seen")
    backend.setProperty("showEmptyNotifications", True)
    check(notif.property("listShown") is False, "... also when the bell opened the sheet")
    backend.setProperty("showEmptyNotifications", False)
    backend.setProperty("showNotifications", True)
    check(notif.property("listShown") is True, "Show notifications on again: the list is back")
    backend.setProperty("page", "clipboard")
    check(notif.property("listShown") is False, "the clipboard sheet has no list")
    backend.setProperty("page", "main")
    # ---- Rows never draw over each other (owner report 2026-10-15, the sheet's list): a card whose
    # summary and body each wrap to a second line, next to its image, ran into the next row - the
    # header of a group - and two grouped cards with a wrapped body and an action overlapped.
    # The tablet Notification Centre lists the same history with the same rows: on before they arrive.
    root.setProperty("centreOn", True)
    wait_for(lambda: root.centreLoaded(), "the Notification Centre did not load")
    # In the order of the report: a one-line card, then two from one app (the group forms while the
    # list shows), then the wrapping card, which arrives on top and moves every row under it - from an
    # app with no notification yet, so it is the lists' first row, the one ListView's transitions
    # dropped the size changes of.
    notify("Could not connect to device", "", entry="org.plasmafusion.notifythird")
    for n in (1, 2):
        notify("Service Crash %d" % n, "/usr/bin/bash has encountered a fatal error and was closed.",
               "--action", "details=Details", entry="org.plasmafusion.notifyother")
    notify("Remote control enabled: Plasma Fusion project settings",
           "Your session is ready to control from your phone or another computer.",
           "--image", str(png("wrap-thumb.png", 96, 96, "#e07040")), entry="org.plasmafusion.notifyfourth")
    QTest.qWait(600)
    problems = json.loads(root.layoutProblems("sheet"))
    check(problems == [], "wrapped cards and a group: no row draws over another (%s)" % ("; ".join(problems) or "clean"))
    centre_rows = root.centreRowCount()
    check(centre_rows >= 4, "the Notification Centre lists them too (%d rows)" % centre_rows)
    problems = json.loads(root.layoutProblems("centre"))
    check(problems == [], "the same in the Notification Centre's list (%s)" % ("; ".join(problems) or "clean"))
    # A narrower sheet wraps more lines: the rows follow.
    root.setProperty("width", 320)
    QTest.qWait(400)
    problems = json.loads(root.layoutProblems("sheet"))
    check(problems == [], "after the sheet narrows: no row draws over another (%s)" % ("; ".join(problems) or "clean"))
    root.setProperty("width", 380)
    QTest.qWait(400)
    # The Centre scrolls a long history itself (review, PR #47): a virtualised ListView, which makes
    # only the rows it shows and keeps a reader's place when a notification arrives on top.
    root.setProperty("centreHeight", 600)
    for n in range(1, 11):
        notify("Filler %d" % n, "An older notification", entry="org.plasmafusion.notifytest")
    QTest.qWait(400)
    made, listed = root.centreRowCount(), root.sheetRowCount()
    check(0 < made < listed, "the Notification Centre makes only the rows it shows (%d of %d)" % (made, listed))
    root.centreScroll(400)
    QTest.qWait(200)
    top = root.centreTopRow()
    # From the app whose group is on top already: a row inserted above the view (a notification of an
    # app further down moves its whole group to the top, rows in view with it - ListView's own way).
    notify("Arrives while reading", "A new notification on top", entry="org.plasmafusion.notifytest")
    QTest.qWait(400)
    check(top != "" and root.centreTopRow() == top,
          "a notification arriving on top leaves the reader's place (%r, now %r)" % (top, root.centreTopRow()))
    root.setProperty("centreOn", False)
    root.setProperty("centreHeight", 1400)
    QTest.qWait(200)
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
