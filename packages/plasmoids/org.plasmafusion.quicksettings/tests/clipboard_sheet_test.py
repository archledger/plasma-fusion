#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The clipboard sheet on Plasma's own clipboard model, offscreen, in a throw-away HOME.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 clipboard_sheet_test.py STAGE_HOME

The staged quick settings (tools/build.sh quicksettings) with Plasma's clipboard QML module
(plasma-workspace): the service (services/Clipboard.qml) on Klipper's HistoryModel, newest first,
search, stars shared with every other view of the history and kept in Klipper's own storage, choose,
edit, remove, clear; then the page (ClipboardPage.qml) by keyboard. The history comes from this
process's clipboard, as Klipper takes it from the session's.
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

# Klipper's clipboard code asks the platform for X11 when the offscreen platform offers it, and
# crashes on its missing connection; and its history lives in the HOME it finds.
os.environ["QT_QPA_OFFSCREEN_NO_GLX"] = "1"
os.environ.setdefault("QT_QUICK_BACKEND", "software")
HOME = tempfile.mkdtemp(prefix="pf-clipboard-")
for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
    os.environ.pop(key, None)
os.environ["HOME"] = HOME
# Klipper's own confirmations (clear the history, remove a starred entry) answered "Continue" as a
# user who ticked "Do not ask again" (KMessageBox reads the application's config).
APP = "pfclipboardtest"
Path(HOME, ".config").mkdir(parents=True)
Path(HOME, ".config", APP + "rc").write_text(
    "[Notification Messages]\nklipperClearHistoryAskAgain=false\nklipperRemoveStarredItemAskAgain=false\n")
# Klipper keeps no images by default ("Always ignore images"); the user turns that off.
Path(HOME, ".config", "klipperrc").write_text("[General]\nIgnoreImages=false\n")

from PySide6.QtCore import QMetaObject, QMimeData, QObject, QSortFilterProxyModel, Q_ARG, Q_RETURN_ARG, Qt, QUrl, Slot  # noqa: E402
from PySide6.QtGui import QColor, QCursor, QImage  # noqa: E402
from PySide6.QtQml import QQmlComponent  # noqa: E402
from PySide6.QtQuick import QQuickItem, QQuickView  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402
from PySide6.QtWidgets import QApplication  # noqa: E402
import shiboken6  # noqa: E402


def fill(text, args):
    for i, a in enumerate(args):
        text = text.replace("%" + str(i + 1), str(a))
    return text


class Context(QObject):
    @Slot(str, result=str)
    @Slot(str, "QVariant", result=str)
    def i18n(self, text, *args):
        return fill(text, args)

    @Slot(str, str, result=str)
    @Slot(str, str, "QVariant", result=str)
    @Slot(str, str, "QVariant", "QVariant", result=str)
    def i18nc(self, context, text, *args):
        return fill(text, args)

    @Slot(str, str, str, "QVariant", result=str)
    @Slot(str, str, str, "QVariant", "QVariant", result=str)
    def i18ncp(self, context, singular, plural, count, *args):
        return fill(singular if count == 1 else plural, (count,) + args)


app = QApplication(sys.argv[:1])
app.setApplicationName(APP)
stage = Path(sys.argv[1]).resolve() / ".local/share/plasma/plasmoids/org.plasmafusion.quicksettings/contents/ui"
if not (stage / "ClipboardPage.qml").exists():
    raise SystemExit(f"no staged quick settings with the clipboard sheet in {stage}")
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


def wait_for(predicate, message, timeout=5000):
    waited = 0
    while waited < timeout:
        if predicate():
            return
        QTest.qWait(20)
        waited += 20
    raise AssertionError(message)


def model_of(obj, name):
    return shiboken6.wrapInstance(shiboken6.getCppPointer(obj.findChild(QObject, name))[0], QSortFilterProxyModel)


def copy(text):
    before = filtered.rowCount() if "filtered" in globals() else 0
    app.clipboard().setText(text)
    QTest.qWait(150)
    return before


view = QQuickView()
translations = Context()
view.rootContext().setContextObject(translations)
harness = Path(HOME, "harness.qml")
harness.write_text(f'''
import QtQuick
import "{stage.as_uri()}"
import "{stage.as_uri()}/components"
import "{stage.as_uri()}/services" as Services
Item {{
    id: root
    width: 400
    height: 700
    property int closes: 0
    property int emojis: 0
    property string chosenUuid: ""
    Services.Clipboard {{ id: history; objectName: "clipboardService" }}
    FusionMetrics {{ id: fusionMetrics }}
    property bool touch: false
    property FusionPalette pal: FusionPalette {{ touch: root.touch }}
    // What Backend.qml gives the page: the service, choose (on the clipboard, then the sheet
    // closes) and the emoji selector.
    QtObject {{
        id: stubBackend
        signal closeRequested()
        onCloseRequested: root.closes++
        property var clipboard: QtObject {{
            readonly property var service: history
            function choose(uuid) {{ history.choose(uuid); root.chosenUuid = uuid; stubBackend.closeRequested(); }}
            function openEmoji() {{ root.emojis++; stubBackend.closeRequested(); }}
        }}
    }}
    // The sheet used to make a new page each time it opens; it now keeps the clipboard page and
    // resets it (PopupContent.qml, survey 4 2026-10-12). The test keeps a fresh page per show to
    // test the page itself; reset() is what the kept page gets on every open (checked below where
    // the page's state is driven).
    property bool pageShown: false
    Loader {{
        anchors.fill: parent
        active: root.pageShown
        focus: true
        sourceComponent: ClipboardPage {{
            objectName: "clipboardPage"
            backend: stubBackend
            pal: root.pal
            metrics: fusionMetrics
        }}
    }}
}}
''')
view.setSource(QUrl.fromLocalFile(str(harness)))
if view.status() == QQuickView.Error:
    raise SystemExit("Clipboard sheet failed to load: " + "; ".join(e.toString() for e in view.errors()))
root = view.rootObject()
view.resize(400, 700)
# The pointer away from the sheet: a tooltip under it would open a window of its own, which the
# offscreen platform makes the focus window (Wayland gives a tooltip no focus).
QCursor.setPos(5000, 5000)
view.show()
QTest.qWaitForWindowExposed(view)
service = root.findChild(QObject, "clipboardService")
filtered = model_of(root, "clipboardFiltered")


def items(item):
    yield item
    for child in item.childItems():
        yield from items(child)


def classes(item):
    """The item's meta object chain (its C++ bases included)."""
    names, mo = [], item.metaObject()
    while mo is not None:
        names.append(mo.className())
        mo = mo.superClass()
    return names


def rows():
    return [filtered.data(filtered.index(i, 0)) for i in range(filtered.rowCount())]


def uuid(row):
    return filtered.data(filtered.index(row, 0), 257)


def call(obj, name, *args, ret=None):
    qargs = [Q_ARG(type(a), a) for a in args]
    if ret is not None:
        return QMetaObject.invokeMethod(obj, name, Q_RETURN_ARG(ret), *qargs)
    return QMetaObject.invokeMethod(obj, name, *qargs)


# ---- the service on Klipper's model
check(service.property("sourceCount") == 0 and filtered.rowCount() == 0, "a new HOME starts with an empty history")
for text in ["alpha one", "Beta two", "Café crème (1)"]:
    copy(text)
wait_for(lambda: filtered.rowCount() == 3, "Klipper's model did not take the copied texts")
check(rows() == ["Café crème (1)", "Beta two", "alpha one"], "the history is newest first")

service.setProperty("query", "beta")
QTest.qWait(30)
check(rows() == ["Beta two"], "search finds an entry in any case")
service.setProperty("query", "creme (1")
QTest.qWait(30)
check(rows() == ["Café crème (1)"], "search ignores accents and takes brackets as text")
service.setProperty("query", "two alpha")
QTest.qWait(30)
check(rows() == [], "search needs every word in the same entry")
service.setProperty("query", "")
QTest.qWait(30)

img = QImage(40, 30, QImage.Format_RGB32)
img.fill(QColor("#2f6fdf"))
app.clipboard().setImage(img)
wait_for(lambda: filtered.rowCount() == 4, "Klipper's model did not take the copied image")
check(filtered.data(filtered.index(0, 0), 259) == 4, "an image is an image entry")


def picture_file():
    url = filtered.data(filtered.index(0, 0), 260)
    return Path(url.toLocalFile()) if url is not None and url.isLocalFile() else None


# Klipper writes the picture in the background.
wait_for(lambda: picture_file() is not None and picture_file().is_file(), "the image entry has no picture file")
check(QImage(str(picture_file())).size().width() == 40, "an image entry has its picture for the thumbnail")
service.setProperty("imageWords", "image picture")
service.setProperty("query", "picture")
QTest.qWait(30)
check(filtered.rowCount() == 1 and filtered.data(filtered.index(0, 0), 259) == 4, "an image is found by the word picture")
service.setProperty("query", "")
QTest.qWait(30)

beta = uuid(2)
call(service, "setStarred", beta, True)
QTest.qWait(50)
check(service.property("starredCount") == 1, "a star counts")
# A second view of the history (as the stock Clipboard widget's) sees the same star.
other_component = QQmlComponent(view.engine(), QUrl.fromLocalFile(str(stage / "services/Clipboard.qml")))
other = other_component.create()
other_model = model_of(other, "clipboardFiltered")
starred_rows = [other_model.data(other_model.index(i, 0)) for i in range(other_model.rowCount())
                if other_model.data(other_model.index(i, 0), 262)]
check(starred_rows == ["Beta two"], "another view of the history shows the same star")
service.setProperty("starredOnly", True)
QTest.qWait(30)
check(rows() == ["Beta two"] and other_model.rowCount() == 4, "Starred shows the starred entries in this view only")
service.setProperty("starredOnly", False)
QTest.qWait(30)
# Klipper keeps stars in its own database: a new process on the same HOME finds the star.
probe = subprocess.run([sys.executable, "-c", f'''
import os, sys
os.environ["QT_QPA_OFFSCREEN_NO_GLX"] = "1"
from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
c = QQmlComponent(engine, QUrl.fromLocalFile({str(stage / "services/Clipboard.qml")!r}))
o = c.create()
print(o.property("starredCount") if o else "error " + str([e.toString() for e in c.errors()]))
'''], capture_output=True, text=True, timeout=60, env=dict(os.environ, QT_QPA_PLATFORM="offscreen"))
check(probe.stdout.strip().splitlines()[-1:] == ["1"], "the star is kept in Klipper's storage (" + probe.stdout.strip() + ")")

alpha = uuid(3)
call(service, "choose", alpha)
QTest.qWait(200)
check(app.clipboard().text() == "alpha one" and rows()[0] == "alpha one", "choosing puts the entry on the clipboard and at the top")

new = call(service, "edit", uuid(0), "alpha edited", ret=str)
QTest.qWait(200)
check(new != "" and rows()[0] == "alpha edited" and app.clipboard().text() == "alpha edited",
      "editing replaces the text and puts it on the clipboard")

count = filtered.rowCount()
call(service, "remove", uuid(filtered.rowCount() - 1))
QTest.qWait(100)
check(filtered.rowCount() == count - 1, "remove takes one entry out")

# The hint after choosing: Plasma's on-screen display, here a stand-in on the private bus that
# writes what it was asked to show.
shown = Path(HOME, "osd.txt")
osd = subprocess.Popen([sys.executable, "-c", f'''
import dbus, dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName("org.kde.plasmashell", bus)
class Osd(dbus.service.Object):
    @dbus.service.method("org.kde.osdService", in_signature="ss")
    def showText(self, icon, text):
        open({str(shown)!r}, "a").write(icon + "|" + text + "\\n")
Osd(bus, "/org/kde/osdService")
GLib.MainLoop().run()
'''])
try:
    import dbus
    session = dbus.SessionBus()
    wait_for(lambda: session.name_has_owner("org.kde.plasmashell"), "the on-screen display stand-in did not start")
    call(service, "showPasteHint")
    wait_for(lambda: shown.exists() and shown.read_text() != "", "nothing was asked of the on-screen display")
    check(shown.read_text().strip() == "edit-paste|Copied, press Ctrl+V to paste",
          "after choosing, the on-screen display says to press Ctrl+V")
finally:
    osd.terminate()
    osd.wait(timeout=5)

# ---- the page, by keyboard
copy("gamma three")
copy("delta four")
wait_for(lambda: filtered.rowCount() == count + 1, "the new copies did not arrive")
root.setProperty("pageShown", True)
QTest.qWait(100)
page = root.findChild(QObject, "clipboardPage")
lst = root.findChild(QObject, "clipboardList")
search = root.findChild(QObject, "clipboardSearch")
first = page.property("firstFocusItem")
check(first is not None and first.objectName() == "clipboardList", "the list takes the focus first when there are entries")
QMetaObject.invokeMethod(first, "forceActiveFocus")
QTest.qWait(50)
check(lst.property("currentIndex") == 0 and lst.property("activeFocus"), "the newest entry is current")
QTest.keyClick(view, Qt.Key_Down)
QTest.keyClick(view, Qt.Key_Down)
check(lst.property("currentIndex") == 2, "Down moves through the entries")
QTest.keyClick(view, Qt.Key_Up)
QTest.keyClick(view, Qt.Key_Up)
check(lst.property("currentIndex") == 0, "Up moves back")
QTest.keyClick(view, Qt.Key_Up)
check(search.property("activeFocus"), "Up on the first entry goes to the search field")
QTest.keyClick(view, Qt.Key_Down)
check(lst.property("activeFocus"), "Down from the search field goes to the list")
for ch in "gam":
    QTest.keyClick(view, ch)
QTest.qWait(50)
check(search.property("text") == "gam" and search.property("activeFocus"), "typing on the list goes to the search field")
check(rows() == ["gamma three"], "the list shows what matches")
QTest.keyClick(view, Qt.Key_Return)
QTest.qWait(150)
check(app.clipboard().text() == "gamma three" and root.property("closes") == 1,
      "Enter in the search field chooses the first match and closes the sheet")
QTest.keyClick(view, Qt.Key_Escape)
QTest.qWait(50)
check(search.property("text") == "" and filtered.rowCount() > 1, "Escape clears the search")
check(lst.property("activeFocus"), "... and goes back to the list")
lst.setProperty("currentIndex", 1)
spaced = rows()[1]
QTest.keyClick(view, Qt.Key_Space)
QTest.qWait(150)
check(app.clipboard().text() == spaced and root.property("closes") == 2 and search.property("text") == "",
      "Space chooses the current entry, as Enter (not a space typed into the search)")

before = filtered.rowCount()
lst.setProperty("currentIndex", 1)
victim = rows()[1]
QTest.keyClick(view, Qt.Key_Delete)
QTest.qWait(100)
check(filtered.rowCount() == before - 1 and victim not in rows(), "Delete removes the current entry")

lst.setProperty("currentIndex", 0)
QTest.keyClick(view, Qt.Key_Right)
QTest.qWait(50)
check(page.property("expandedUuid") == uuid(0), "Right opens the current entry's actions")
# ---- The open entry's action buttons reach the touch minimum in touch mode (the sheet is the
# touch surface in tablet posture; the actions come from TextButton.qml, whose target grows there).
root.setProperty("touch", True)
QTest.qWait(100)
buttons = [i for i in items(page) if i.isVisible() and "QQuickAbstractButton" in classes(i)]
small = [(i.objectName() or str(i.property("text") or "")[:24], round(i.width(), 1), round(i.height(), 1))
         for i in buttons if i.width() + 0.5 < 44 or i.height() + 0.5 < 44]
check(len(buttons) >= 3 and not small,
      "touch mode: the entry's action buttons reach 44 x 44 (%d buttons, small: %r)" % (len(buttons), small))
root.setProperty("touch", False)
QTest.qWait(50)
starred_before = service.property("starredCount")
QTest.keyClick(view, Qt.Key_Return)
QTest.qWait(50)
check(service.property("starredCount") == starred_before + 1, "Enter presses the first action, Star")
QTest.keyClick(view, Qt.Key_Right)
check(page.property("actionIndex") == 1 and lst.property("activeFocus"), "Right moves to the next action, the list keeping the focus")
QTest.keyClick(view, Qt.Key_Left)
QTest.keyClick(view, Qt.Key_Left)
check(page.property("expandedUuid") == "", "Left past the first action closes them")
QTest.keyClick(view, Qt.Key_Right)
QTest.keyClick(view, Qt.Key_Escape)
QTest.qWait(50)
check(page.property("expandedUuid") == "" and lst.property("activeFocus"), "Escape closes them again")

call(page, "openMode", "qr", 0)
QTest.qWait(100)
qr = page.property("modeFocus")
check(page.property("mode") == "qr" and qr is not None and qr.property("activeFocus"), "the QR code view opens with the focus")
QTest.keyClick(view, Qt.Key_Escape)
QTest.qWait(50)
check(page.property("mode") == "list", "Escape goes back from the QR code to the list")

call(page, "openMode", "edit", 0)
QTest.qWait(100)
editor = root.findChild(QObject, "clipboardEditor")
check(editor is not None and editor.property("text") == rows()[0], "the editor opens with the entry's text")
editor.setProperty("text", "edited from the sheet")
save = root.findChild(QObject, "clipboardSave")
QMetaObject.invokeMethod(save, "clicked")
QTest.qWait(200)
check(page.property("mode") == "list" and rows()[0] == "edited from the sheet" and app.clipboard().text() == "edited from the sheet",
      "Save keeps the edited text on the clipboard")

call(page, "openMode", "edit", 0)
QTest.qWait(100)
editor = root.findChild(QObject, "clipboardEditor")
QTest.keyClick(view, Qt.Key_End)
for ch in " ok":
    QTest.keyClick(view, ch)
check(editor.property("text") == "edited from the sheet ok", "the editor takes typing")
QTest.keyClick(view, Qt.Key_Return)
QTest.qWait(200)
check(page.property("mode") == "list" and rows()[0] == "edited from the sheet ok", "Enter in the editor saves")
call(page, "openMode", "edit", 0)
QTest.qWait(100)
for ch in "zz":
    QTest.keyClick(view, ch)
QTest.keyClick(view, Qt.Key_Escape)
QTest.qWait(100)
check(page.property("mode") == "list" and rows()[0] == "edited from the sheet ok", "Escape leaves the editor without saving")
QTest.qWait(50)
check(lst.property("activeFocus"), "... with the focus back on the list")
QTest.keyClick(view, Qt.Key_Tab)
QTest.qWait(50)
check(not lst.property("activeFocus"), "Tab leaves the list")

emoji = root.findChild(QObject, "clipboardEmoji")
QMetaObject.invokeMethod(emoji, "clicked")
check(root.property("emojis") == 1, "the Emoji button asks for the emoji selector")

# The rows are the list's delegates, not QObject children: reach the first one's star through it.
first_row = QMetaObject.invokeMethod(lst, "itemAtIndex", Q_RETURN_ARG(QQuickItem), Q_ARG(int, 0))
star = first_row.findChild(QObject, "clipboardStar")
check(star.property("toolTip") != "", "with a pointer, a row's star has its tooltip")
root.setProperty("touch", True)
QTest.qWait(50)
check(star.property("toolTip") == "" and star.property("text") != "",
      "in touch mode it has none (a tap would leave it over the row's actions), and keeps its name")
root.setProperty("touch", False)

# A copied file: its row shows the file's preview from Klipper's preview provider, which answers
# an empty picture unless it is asked for a width and a height (the ThinkPad showed an empty tile).
shot = Path(HOME, "shot.png")
picture = QImage(64, 48, QImage.Format_RGB32)
picture.fill(QColor("#3b56a0"))
picture.save(str(shot))
files = QMimeData()
files.setUrls([QUrl.fromLocalFile(str(shot))])
app.clipboard().setMimeData(files)
wait_for(lambda: filtered.data(filtered.index(0, 0), 259) == 8, "Klipper's model did not take the copied file")
lst.setProperty("currentIndex", 0)
file_row = QMetaObject.invokeMethod(lst, "itemAtIndex", Q_RETURN_ARG(QQuickItem), Q_ARG(int, 0))
preview = file_row.findChild(QObject, "clipboardThumbnail")
check(preview is not None and preview.property("visible"), "a copied file's row has a preview")
# (the Image's status enum does not reach Python; its progress does)
wait_for(lambda: preview.property("progress") == 1.0, "the file's preview did not load")
QTest.qWait(200)
check(preview.property("implicitWidth") > 0 and preview.property("implicitHeight") > 0,
      "the preview has a picture (%sx%s)" % (preview.property("implicitWidth"), preview.property("implicitHeight")))

starred = service.property("starredCount")
call(service, "clearHistory")
QTest.qWait(200)
check(filtered.rowCount() == starred and service.property("starredCount") == starred,
      "Clear all (after Klipper's confirmation) keeps the starred entries")

# The kept page's per-open reset(): the sheet calls it when the page becomes visible again
# (PopupContent.qml); a fresh page had all of this by construction.
copy("reset probe")
search = root.findChild(QObject, "clipboardSearch")
call(search, "insert", 0, "sum")
call(page, "openMode", "edit", 0)
QTest.qWait(100)
call(page, "reset")
QTest.qWait(100)
check(search.property("text") == "", "reset(): the search is cleared")
check(page.property("mode") == "list", "reset(): the page is back in list mode")
check(lst.property("currentIndex") == 0, "reset(): the newest entry is current")
print(f"Clipboard sheet: {checks} checks, 0 failures")
