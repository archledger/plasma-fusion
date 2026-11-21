#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The clock's settings pages, offscreen.

First the three pages as Plasma's settings dialog opens and applies them (plasma-desktop's
AppletConfiguration.qml, the same at v6.7.5 and v6.8.3 in open() and saveConfig()): it passes every
key of the configuration to the page as cfg_<key>, and the configuration lists each key of main.xml
twice, as <key> and as its default <key>Default (KConfig 6.32's KConfigPropertyMap, loadConfig());
Apply calls the page's saveConfig(), then copies back every cfg_ property the page declares, and
writeConfig() saves what the configuration then holds. A stand-in for org.kde.plasma.plasmoid hands
the pages that configuration. While a page is open, the clock's layout request, the layout
provider's answer and the layout control's visibility change in the configuration; Apply must leave
each as it now is, unless the page itself edits it.

Then the Calendar settings page follows enabledCalendarPlugins when it changes from outside
(Defaults, Reset) and after a click. Offscreen, with the native calendar provider manager.
Run, as the specification does: QT_QPA_PLATFORM=offscreen dbus-run-session
--config-file=packages/kwin/tests/offscreen/session-bus.conf -- python3
packages/plasmoids/org.plasmafusion.clockpill/tests/calendar_config_test.py"""
import json
import os
from pathlib import Path
import sys
import tempfile
import xml.etree.ElementTree as ElementTree

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QMetaObject, QObject, QUrl, Slot  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlComponent, QQmlEngine  # noqa: E402
from PySide6.QtQuick import QQuickItem  # noqa: E402,F401  (registers the QQuickItem* converter)

PACKAGE = Path(os.environ.get("PF_CLOCK_PACKAGE", Path(__file__).resolve().parent.parent))
PAGE = Path(os.environ.get("PF_CALENDAR_CONFIG_PAGE", PACKAGE / "contents/ui/ConfigCalendar.qml"))
failures = 0


def check(condition, message):
    global failures
    print(("PASS " if condition else "FAIL ") + message)
    failures += 0 if condition else 1


class Context(QObject):
    """The pages' translation calls, untranslated."""

    @Slot(str, result=str)
    def i18n(self, text):
        return text

    @Slot(str, str, result=str)
    @Slot(str, str, str, result=str)
    def i18nc(self, context, text, argument=None):
        return text if argument is None else text.replace("%1", argument)


# The stand-in for org.kde.plasma.plasmoid, first on the import path: Plasmoid.configuration is
# whatever configuration the test hands it.
stand_in = tempfile.TemporaryDirectory(prefix="pf-clock-config-")
module = Path(stand_in.name) / "org/kde/plasma/plasmoid"
module.mkdir(parents=True)
(module / "qmldir").write_text("module org.kde.plasma.plasmoid\nsingleton Plasmoid 1.0 Plasmoid.qml\n")
(module / "Plasmoid.qml").write_text("pragma Singleton\nimport QtQml\nQtObject {\n    property QtObject configuration\n}\n")

app = QGuiApplication(sys.argv)
engine = QQmlEngine()
engine.addImportPath(stand_in.name)
context = Context()
engine.rootContext().setContextObject(context)
holder = QQmlComponent(engine)
holder.setData(b"import QtQml\nimport org.kde.plasma.plasmoid\nQtObject { readonly property QtObject plasmoid: Plasmoid }\n",
               QUrl("file:///plasmoid.qml"))
plasmoid = holder.create().property("plasmoid")

KCFG = "{http://www.kde.org/standards/kcfg/1.0}"


def schema():
    """main.xml's entries: name -> (group, type, default as KConfig reads it)."""
    entries = {}
    for group in ElementTree.parse(PACKAGE / "contents/config/main.xml").getroot().iter(KCFG + "group"):
        for entry in group.iter(KCFG + "entry"):
            kind, text = entry.get("type"), entry.findtext(KCFG + "default") or ""
            value = (text == "true" if kind == "Bool" else int(text) if kind in ("Int", "UInt")
                     else (text.split(",") if text else []) if kind == "StringList" else text)
            entries[entry.get("name")] = (group.get("name"), kind, value)
    return entries


ENTRIES = schema()
KEYS = [key for name in ENTRIES for key in (name + "Default", name)]
# PySide destroys what a component created along with the component: each is kept here.
components = []


def configuration(saved):
    """The widget's configuration: every key and its default, the saved values among them."""
    body = "".join(f"    property var {key}\n" for key in KEYS)
    component = QQmlComponent(engine)
    component.setData(("import QtQml\nQtObject {\n" + body + "}\n").encode(), QUrl("file:///configuration.qml"))
    components.append(component)
    config = component.create()
    for name, (_, _, default) in ENTRIES.items():
        config.setProperty(name + "Default", default)
        config.setProperty(name, saved.get(name, default))
    return config


def snapshot(config):
    return {key: config.property(key) for key in KEYS}


def open_page(name, config):
    """The page as the dialog opens it: every key of the configuration as cfg_<key>."""
    plasmoid.setProperty("configuration", config)
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(PACKAGE / "contents/ui" / name)))
    page = component.createWithInitialProperties({"title": name} | {"cfg_" + key: config.property(key) for key in KEYS})
    app.processEvents()
    return component, page


def apply(page, config):
    """Apply as the dialog does it: the page's saveConfig(), then every cfg_ property it declares."""
    if page.metaObject().indexOfMethod("saveConfig()") >= 0:
        QMetaObject.invokeMethod(page, "saveConfig")
    for key in KEYS:
        if page.metaObject().indexOfProperty("cfg_" + key) >= 0:
            config.setProperty(key, page.property("cfg_" + key))


def find(item, text):
    """The page's item with a checked property and this text."""
    for child in item.childItems():
        if child.metaObject().indexOfProperty("checked") >= 0 and child.property("text") == text:
            return child
        found = find(child, text)
        if found is not None:
            return found
    return None


# The control's visibility and the two fields of the layout transport (the placement script's
# layout provider reads layoutRequest and writes layoutResponse, both in General).
LAYOUT = {"showLayoutControl": ("General", "Bool", True), "layoutRequest": ("General", "String", ""),
          "layoutResponse": ("General", "String", "")}
for name, wanted in LAYOUT.items():
    check(ENTRIES.get(name) == wanted, "main.xml declares %s in General, %s, default %r (%s)" % (name, wanted[1], wanted[2], ENTRIES.get(name)))
LAYOUT_KEYS = [key for name in LAYOUT for key in (name, name + "Default")]
REQUEST = [json.dumps({"version": 1, "intent": "query", "consumer": "c" * 32, "request": n, "outputName": "Virtual-0"}) for n in (1, 2)]
ANSWER = [json.dumps({"version": 1, "consumer": "c" * 32, "request": n, "epoch": "e" * 32, "revision": n + 2, "status": "online",
                      "capable": True, "tiled": n == 2, "view": {"desktopId": "d", "activityId": "", "outputName": "Virtual-0"}})
          for n in (1, 2)]
# The page that edits the visibility choice, and the two that only refresh it.
PAGES = {"ConfigGeneral.qml": True, "ConfigCalendar.qml": False, "ConfigTimeZones.qml": False}
for name, edits in PAGES.items():
    config = configuration({"showLayoutControl": True, "layoutRequest": REQUEST[0], "layoutResponse": ANSWER[0]})
    saved = snapshot(config)
    component, page = open_page(name, config)
    if page is None:
        errors = "; ".join(e.toString() for e in component.errors())
        missing = "is not installed" in errors
        print(("SKIP " if missing else "FAIL ") + "%s cannot load: %s" % (name, errors))
        failures += 0 if missing else 1
        continue
    absent = [key for key in KEYS if page.metaObject().indexOfProperty("cfg_" + key) < 0]
    check(not absent, "%s takes every key and default the dialog passes (absent: %s)" % (name, absent))
    check(all(page.metaObject().indexOfProperty("cfg_" + key) >= 0 and page.property("cfg_" + key) == config.property(key)
              for key in LAYOUT_KEYS), "%s takes the saved visibility choice, request and answer, with their defaults" % name)
    check(snapshot(config) == saved, "%s writes nothing to the configuration when it opens" % name)
    # While the page is open, the clock asks again, the provider answers, and where the page does
    # not edit it, the visibility choice changes too (desktop scripting, say).
    config.setProperty("layoutRequest", REQUEST[1])
    config.setProperty("layoutResponse", ANSWER[1])
    if not edits:
        config.setProperty("showLayoutControl", False)
    apply(page, config)
    check("layoutRequest" in ENTRIES and "layoutResponse" in ENTRIES
          and config.property("layoutRequest") == REQUEST[1] and config.property("layoutResponse") == ANSWER[1],
          "%s: Apply replays no earlier request and replaces no fresher answer" % name)
    if not edits:
        check("showLayoutControl" in ENTRIES and config.property("showLayoutControl") is False,
              "%s: Apply does not undo a visibility choice made while it was open" % name)
    page.deleteLater()
    app.processEvents()

# The General page's own control: it shows the saved choice, and the user's choice reaches the
# configuration on Apply while the transport's fields keep what was written meanwhile.
config = configuration({"showLayoutControl": False, "layoutRequest": REQUEST[0], "layoutResponse": ANSWER[0]})
component, page = open_page("ConfigGeneral.qml", config)
box = find(page, "Show the dynamic tiling control") if page is not None else None
check(box is not None and box.property("checked") is False, "General: the dynamic tiling control's checkbox shows the saved choice")
if box is not None:
    box.setProperty("checked", True)
    config.setProperty("layoutResponse", ANSWER[1])
    apply(page, config)
    check(config.property("showLayoutControl") is True and config.property("layoutRequest") == REQUEST[0]
          and config.property("layoutResponse") == ANSWER[1],
          "General: Apply writes the user's visibility choice and keeps the answer written meanwhile")
if page is not None:
    page.deleteLater()
    app.processEvents()

# The setting hides the control independently of the workspace dots (the specification): with the
# dots off, the checkbox stays enabled and shown.
config = configuration({"showWorkspaces": False})
component, page = open_page("ConfigGeneral.qml", config)
box = find(page, "Show the dynamic tiling control") if page is not None else None
check(box is not None and box.property("enabled") is True and box.property("visible") is True and box.property("checked") is True,
      "General: with the workspace dots off, the dynamic tiling control's checkbox stays enabled and shown")
if page is not None:
    page.deleteLater()
    app.processEvents()


def delegates(root):
    """The provider check delegates: items with a checked and a text property."""
    found = []

    def walk(item):
        for child in item.childItems():
            if child.metaObject().indexOfProperty("checked") >= 0 and child.property("text"):
                found.append(child)
            walk(child)
    walk(root)
    return found


component = QQmlComponent(engine, QUrl.fromLocalFile(str(PAGE)))
page = component.create()
if page is None:
    print("cannot load the page: " + "; ".join(e.toString() for e in component.errors()))
    sys.exit(0 if not failures and any("is not installed" in e.toString() for e in component.errors()) else 1)
app.processEvents()
items = delegates(page.property("contentItem") or page)
if not items:
    print("SKIP no calendar providers installed")
    sys.exit(1 if failures else 0)
first = items[0]
name = first.property("text")


def enabled():
    return [str(i) for i in (page.property("cfg_enabledCalendarPlugins") or [])]


def checks():
    app.processEvents()
    return {i.property("text"): bool(i.property("checked")) for i in delegates(page.property("contentItem") or page)}


# Reset/Defaults from outside: none, then everything the click below will produce, then none.
page.setProperty("cfg_enabledCalendarPlugins", [])
check(not any(checks().values()), "no provider checked after the key is emptied (Defaults)")
# A click: the delegate toggles, then reports clicked().
target = [i for i in delegates(page.property("contentItem") or page) if i.property("text") == name][0]
target.setProperty("checked", True)
QMetaObject.invokeMethod(target, "clicked")
app.processEvents()
after_click = enabled()
check(len(after_click) == 1, "a click enables that provider in the key (%s)" % after_click)
page.setProperty("cfg_enabledCalendarPlugins", [])
check(not checks().get(name, True), "Defaults after a click unchecks it again (the check follows the model)")
page.setProperty("cfg_enabledCalendarPlugins", after_click)
check(checks().get(name, False), "Reset to the saved value checks it again")
print("calendar config: %d failure(s)" % failures)
sys.exit(1 if failures else 0)
