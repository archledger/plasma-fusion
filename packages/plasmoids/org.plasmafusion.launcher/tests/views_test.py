#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The launcher card's Recent and Places views on Kicker's real models, offscreen, private D-Bus.

QT_QPA_PLATFORM=offscreen dbus-run-session --config-file=packages/kwin/tests/offscreen/session-bus.conf \
    -- python3 packages/plasmoids/org.plasmafusion.launcher/tests/views_test.py
Requires PySide6, Plasma's Kicker QML module (plasma-workspace), kactivitymanagerd and kbuildsycoca6.

A throw-away HOME gets three test apps and an activity manager; using the apps (the events Kicker
itself sends when it starts an app, and the file manager when it opens a folder) fills the history
that UsageModels.qml reads. The card (LauncherCard.qml, staged with the shared blocks as the build
does) then runs with those models: the "Recent" chip with its two lists in the right order, the
"Places" chip with the places and the recent folders, and the keyboard through them. Last, the
search ends in a row that hands the query to KRunner (with Kicker's real RunnerModel). The
settings page (ConfigGeneral.qml) lists the hidden apps by name and shows them again, and Kicker's
models see the hidden apps (and offer Hide Application) only through the applet's `configuration`
property, which main.qml now declares.
"""

import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import warnings

here = Path(__file__).resolve().parent
package = here.parent
root = package.parents[2]

# Everything below runs in a throw-away HOME, before Qt reads any of it.
home = Path(tempfile.mkdtemp(prefix="pf-launcher-views-"))
for key, sub in (("XDG_DATA_HOME", ".local/share"), ("XDG_CONFIG_HOME", ".config"), ("XDG_CACHE_HOME", ".cache")):
    os.environ[key] = str(home / sub)
    (home / sub).mkdir(parents=True)
os.environ["HOME"] = str(home)
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import dbus  # noqa: E402
from PySide6.QtCore import Q_ARG, Q_RETURN_ARG, QMetaObject, QObject, QUrl, Qt, Slot  # noqa: E402
from PySide6.QtDBus import QDBusConnection  # noqa: E402
from PySide6.QtQuick import QQuickWindow  # noqa: E402,F401 (the harness windows as QQuickWindow)
from PySide6.QtWidgets import QApplication  # noqa: E402
from PySide6.QtQml import QQmlComponent, QQmlEngine, QQmlPropertyMap  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

APPS = {"pf-test-alpha": "Alpha Test", "pf-test-beta": "Beta Test", "pf-test-gamma": "Gamma Test"}
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


def wait_for(predicate, message, seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        QTest.qWait(50)
        if predicate():
            return
    raise AssertionError(message)


def subst(text, args):
    for i, a in enumerate(args, 1):
        text = text.replace("%" + str(i), str(a))
    return text


class I18n(QObject):
    """KLocalizedContext's functions, untranslated (the card's strings are plain English here)."""

    @Slot(str, result=str)
    def i18n(self, text):
        return text

    @Slot(str, str, result=str)
    def i18nc(self, context, text):
        return text

    @Slot(str, str, "QVariant", result=str)
    def i18nc(self, context, text, a):  # noqa: F811
        return subst(text, [a])

    @Slot(str, str, str, int, result=str)
    def i18ncp(self, context, singular, plural, n):
        return subst(singular if n == 1 else plural, [n])


# The test apps, known to KService (Kicker drops history entries of apps it cannot find).
apps_dir = home / ".local/share/applications"
apps_dir.mkdir(parents=True)
for app_id, name in APPS.items():
    (apps_dir / f"{app_id}.desktop").write_text(
        f"[Desktop Entry]\nType=Application\nName={name}\nExec=true\nIcon=utilities-terminal\nCategories=Utility;\n")
subprocess.run(["kbuildsycoca6", "--noincremental"], check=True, capture_output=True, timeout=120)

# The stage of the package: contents plus the shared blocks, as tools/build.d/72-launcher.sh does.
stage = home / "stage"
shutil.copytree(package / "contents", stage / "contents")
subprocess.run(["bash", str(root / "tools/build-lib/shared-qml.sh"), "install", str(package), str(stage / "contents/ui")],
               check=True, timeout=120, env=dict(os.environ, ROOT=str(root)))

# QApplication: the card's menus are QMenus (PlasmaExtras.Menu).
app = QApplication(sys.argv[:1])
bus = QDBusConnection.sessionBus()
if not bus.isConnected():
    raise SystemExit("no session bus; run under dbus-run-session")
if bus.interface().isServiceRegistered("org.kde.plasmashell").value():
    raise SystemExit("Run on a fresh private bus; refusing a live desktop bus")
kamd_path = next((p for p in ("/usr/libexec/kactivitymanagerd", "/usr/lib/kactivitymanagerd/kactivitymanagerd",
                              "/usr/lib/x86_64-linux-gnu/libexec/kactivitymanagerd") if os.path.exists(p)), None)
if kamd_path is None:
    raise SystemExit("kactivitymanagerd is not installed")
kamd = subprocess.Popen([kamd_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

HARNESS = b"""
import QtQuick
import QtQuick.Window
import org.kde.plasma.private.kicker as Kicker
import "../code/launcher.js" as Launcher

Window {
    id: win
    width: 680
    height: 700
    visible: true

    UsageModels {
        id: usage
    }
    ListModel {
        id: empty
        function trigger(i, a, b) { return false }
        function isFavorite(id) { return false }
    }
    QtObject {
        id: mock
        property var favoritesModel: empty
        property var recentDocsModel: empty
        property var recentAppsModel: usage.recentApps
        property var frequentAppsModel: usage.frequentApps
        property var placesModel: usage.places
        property var recentFoldersModel: usage.recentFolders
        property var runnerModel: Kicker.RunnerModel {
            mergeResults: true
            runners: Launcher.searchRunners
            query: mock.searchText
        }
        property string krunnerQuery: ""
        function searchInKRunner(query) { krunnerQuery = query; close(); }
        property var rootModel: QtObject { function modelForRow(i) { return null } }
        property var chips: [
            { key: "all", label: "All", row: -1, view: "home" },
            { key: "recentapps", label: "Recent", row: -1, view: "history" },
            { key: "places", label: "Places", row: -1, view: "places" },
            { key: "office", label: "Office", row: 3, view: "category" },
        ]
        property bool designLabels: false
        property bool showRecommended: true
        property bool menuOpen: true
        property string searchText: ""
        property int closed: 0
        function close() { closed++ }
        function allAppsModel() { return null }
        function openActionMenu() {}
        function formatAge(date) { return "" }
        function dockApplet() { return null }
    }
    FusionColors {
        id: colors
    }
    FusionMetrics {
        id: metrics
    }
    LauncherCard {
        id: card
        anchors.fill: parent
        focus: true
        launcher: mock
        pal: colors
        metrics: metrics
    }

    function column(which, role) {
        const model = usage[which];
        const out = [];
        for (let i = 0; model && i < model.rowCount(); ++i) {
            out.push(String(model.data(model.index(i, 0), role)));
        }
        return JSON.stringify(out);
    }
    function names(which) { return column(which, Qt.DisplayRole); }
    function icons(which) { return column(which, Qt.DecorationRole); }
    function find(item, name) {
        if (item.objectName === name) {
            return item;
        }
        for (const child of item.children) {
            const found = find(child, name);
            if (found) {
                return found;
            }
        }
        return null;
    }
    function results() {
        const list = find(card, "searchResults");
        return JSON.stringify({ visible: list.visible, count: list.count, current: list.currentIndex, focus: list.activeFocus,
                                shown: list.handoffShown, handoff: list.handoffCurrent, query: mock.krunnerQuery,
                                closed: mock.closed, querying: mock.runnerModel.querying });
    }
    // The card's typed functions, for Python (which passes QVariant arguments).
    function openMode(mode) { card.openMode(mode, ""); }
    function selectChip(index) { card.selectChip(index); }
    function setChips(list) { mock.chips = JSON.parse(list); }
    // Ordering (0 Recent, 1 Popular) and shown items (1 OnlyApps) of both lists.
    function orderings() {
        return [usage.recentApps.ordering, usage.frequentApps.ordering, usage.recentApps.shownItems, usage.frequentApps.shownItems].join(" ");
    }
    function state() {
        const grid = card.primaryGrid();
        const last = card.lastGrid();
        return JSON.stringify({
            view: card.view, chip: card.chipIndex, chipKey: card.chips[card.chipIndex] ? card.chips[card.chipIndex].key : "",
            primaryModel: grid.model === usage.recentApps ? "recent" : grid.model === usage.frequentApps ? "frequent"
                : grid.model === usage.places ? "places" : "other",
            primaryCount: grid.count, primaryFocus: grid.activeFocus, primaryCurrent: grid.currentIndex,
            lastModel: last.model === usage.frequentApps ? "frequent" : last.model === usage.recentApps ? "recent"
                : last.model === usage.recentFolders ? "folders" : "other",
            primaryLine: grid.currentItem ? String(grid.currentItem.placeLine || "") : "",
            lastCount: last.count, lastFocus: last.activeFocus, lastVisible: last.visible,
        });
    }
}
"""


def items(item):
    """The item and every item below it in the visual tree."""
    out = [item]
    for child in item.childItems():
        out += items(child)
    return out


def type_text(window, text):
    """QTest.keyClicks for a QWindow (PySide6 has it for widgets only)."""
    for ch in text:
        QTest.keyClick(window, ch)


def call(obj, name, *args):
    return QMetaObject.invokeMethod(obj, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", a) for a in args])


try:
    wait_for(lambda: bus.interface().isServiceRegistered("org.kde.ActivityManager").value(), "kactivitymanagerd did not start")
    resources = dbus.Interface(dbus.SessionBus().get_object("org.kde.ActivityManager", "/ActivityManager/Resources"),
                               "org.kde.ActivityManager.Resources")
    # What Kicker sends when it starts an app (KActivities ResourceInstance::notifyAccessed: event 0,
    # Accessed). Gamma is used last. The history keeps seconds and writes a use about a second
    # after the last event, hence the pauses.
    for app_id in ["pf-test-alpha", "pf-test-beta", "pf-test-gamma"]:
        resources.RegisterResourceEvent("org.kde.plasma.kicker", dbus.UInt32(0), f"applications:{app_id}.desktop", dbus.UInt32(0))
        QTest.qWait(2200)
    # A folder opened in the file manager (KIO tells the activity manager the URL and its type).
    projects = home / "Projects"
    projects.mkdir()
    resources.RegisterResourceMimetype(projects.as_uri(), "inode/directory")
    resources.RegisterResourceEvent("org.kde.dolphin", dbus.UInt32(0), projects.as_uri(), dbus.UInt32(0))
    QTest.qWait(2200)

    engine = QQmlEngine()
    engine.rootContext().setContextObject(I18n(engine))
    component = QQmlComponent(engine)
    component.setData(HARNESS, QUrl.fromLocalFile(str(stage / "contents/ui/ViewsHarness.qml")))
    win = component.create()
    if win is None:
        raise AssertionError("harness did not load: " + "; ".join(e.toString() for e in component.errors()))
    wait_for(lambda: len(json.loads(call(win, "names", "recentApps"))) == 3
             and len(json.loads(call(win, "names", "frequentApps"))) == 3, "the usage models did not fill")

    check(json.loads(call(win, "names", "recentApps")) == ["Gamma Test", "Beta Test", "Alpha Test"],
          "recently used apps: the app used last comes first")
    # The use counts behind "Often used" are kactivitymanagerd's scores, which it builds over
    # minutes of use; the VM scenario checks that order. Here: the same apps, by score.
    check(sorted(json.loads(call(win, "names", "frequentApps"))) == ["Alpha Test", "Beta Test", "Gamma Test"]
          and call(win, "orderings") == "0 1 1 1", "often used apps: the same history, ordered by use (Popular)")

    call(win, "openMode", "history")
    QTest.qWait(200)
    s = json.loads(call(win, "state"))
    check(s["view"] == "history" and s["chip"] == 1, "open request \"history\" selects the Recent chip")
    check(s["primaryModel"] == "recent" and s["primaryCount"] == 3, "the first list is the recently used apps")
    check(s["lastModel"] == "frequent" and s["lastVisible"] and s["lastCount"] == 3, "below it the often used apps")

    # Keyboard: Down from the search field into the first list, Down again into the second, Up back.
    win.requestActivate()
    QTest.qWait(100)
    QTest.keyClick(win, Qt.Key_Down)
    QTest.qWait(100)
    s = json.loads(call(win, "state"))
    check(s["primaryFocus"] and s["primaryCurrent"] == 0, "Down from search reaches the first recently used app")
    QTest.keyClick(win, Qt.Key_Down)
    QTest.qWait(100)
    s = json.loads(call(win, "state"))
    check(s["lastFocus"] and not s["primaryFocus"], "Down from the recent row goes on to the often used apps")
    QTest.keyClick(win, Qt.Key_Up)
    QTest.qWait(100)
    s = json.loads(call(win, "state"))
    check(s["primaryFocus"], "Up from the often used apps goes back to the recent row")

    # Places: the file manager's places (Home first, no "Show KRunner" row) and the recent folder.
    wait_for(lambda: len(json.loads(call(win, "names", "places"))) > 0 and len(json.loads(call(win, "names", "recentFolders"))) > 0,
             "the places models did not fill")
    places = json.loads(call(win, "names", "places"))
    check(places[0] == "Home" and "Show KRunner" not in places,
          "places: the home folder first, without ComputerModel's Show KRunner row")
    check(json.loads(call(win, "icons", "computer"))[0] == "plasma-search",
          "(ComputerModel itself has that row first; the filter removed it)")
    check(json.loads(call(win, "names", "recentFolders")) == ["Projects"], "recent folders: the folder opened last")
    call(win, "openMode", "places")
    QTest.qWait(200)
    s = json.loads(call(win, "state"))
    check(s["view"] == "places" and s["chip"] == 2 and s["primaryModel"] == "places", "open request \"places\" shows the places")
    check(s["lastModel"] == "folders" and s["lastVisible"], "below them the recent folders")
    QTest.keyClick(win, Qt.Key_Down)
    QTest.qWait(100)
    s = json.loads(call(win, "state"))
    check(s["primaryFocus"] and s["primaryCurrent"] == 0 and s["primaryLine"] == "~", "Down reaches Home, shown as ~")
    QTest.keyClick(win, Qt.Key_Down)
    QTest.qWait(100)
    rows = -(-len(places) // 2)
    for _ in range(rows - 1):
        QTest.keyClick(win, Qt.Key_Down)
        QTest.qWait(100)
    s = json.loads(call(win, "state"))
    check(s["lastFocus"] and not s["primaryFocus"], "Down from the last places row goes on to the recent folders")

    # The search ends in "Search … in KRunner": after the last result (Down), and as the only row
    # when nothing matches; Enter hands the query over.
    call(win, "openMode", "home")
    QTest.qWait(100)
    type_text(win, "alpha")
    # (wait for the runners to finish: results that arrive later would move the last row)
    wait_for(lambda: json.loads(call(win, "results"))["count"] > 0 and not json.loads(call(win, "results"))["querying"],
             "no search results for \"alpha\"")
    QTest.qWait(500)
    r = json.loads(call(win, "results"))
    check(r["visible"] and r["shown"] and not r["handoff"], "search: results, then the KRunner row below them")
    QTest.keyClick(win, Qt.Key_Down)
    for _ in range(r["count"] + 1):
        QTest.qWait(50)
        if json.loads(call(win, "results"))["handoff"]:
            break
        QTest.keyClick(win, Qt.Key_Down)
    r = json.loads(call(win, "results"))
    check(r["handoff"] and r["focus"], "Down past the last result selects the KRunner row")
    QTest.keyClick(win, Qt.Key_Up)
    QTest.qWait(50)
    r = json.loads(call(win, "results"))
    check(not r["handoff"] and r["current"] == r["count"] - 1, "Up goes back to the last result")
    QTest.keyClick(win, Qt.Key_Down)
    QTest.keyClick(win, Qt.Key_Return)
    QTest.qWait(50)
    r = json.loads(call(win, "results"))
    check(r["query"] == "alpha" and r["closed"] >= 1, "Enter on it opens KRunner with the query and closes the launcher")
    call(win, "openMode", "home")
    QTest.qWait(100)
    type_text(win, "zzqxj")
    wait_for(lambda: not json.loads(call(win, "results"))["focus"] and json.loads(call(win, "results"))["visible"], "no search")
    QTest.qWait(1500)
    QTest.keyClick(win, Qt.Key_Down)
    QTest.qWait(50)
    r = json.loads(call(win, "results"))
    check(r["count"] == 0 and r["handoff"] and r["focus"], "no results: Down from the field selects the KRunner row")
    QTest.keyClick(win, Qt.Key_Return)
    QTest.qWait(50)
    check(json.loads(call(win, "results"))["query"] == "zzqxj", "and Enter hands that query over")

    # The settings page: the hidden apps by name, one shown again, then all.
    SETTINGS = b"""
import QtQuick
import QtQuick.Window
Window {
    width: 640
    height: 480
    visible: true
    ConfigGeneral {
        id: page
        anchors.fill: parent
        cfg_hiddenApplications: ["pf-test-alpha.desktop", "pf-test-gamma.desktop", "pf-removed-app.desktop"]
    }
    function hidden() { return JSON.stringify(Array.from(page.cfg_hiddenApplications)); }
    function names() { return JSON.stringify(page.hiddenIds.map(id => page.appInfo(id).name)); }
}
"""
    settings_component = QQmlComponent(engine)
    settings_component.setData(SETTINGS, QUrl.fromLocalFile(str(stage / "contents/ui/SettingsHarness.qml")))
    settings = settings_component.create()
    if settings is None:
        raise AssertionError("settings page did not load: " + "; ".join(e.toString() for e in settings_component.errors()))
    wait_for(lambda: json.loads(call(settings, "names"))[0] == "Alpha Test", "the hidden apps' names did not arrive")
    check(json.loads(call(settings, "names")) == ["Alpha Test", "Gamma Test", "pf-removed-app"],
          "settings: the hidden apps by name (an app no longer installed by its id)")
    buttons = {b.objectName(): b for b in items(settings.contentItem()) if b.objectName().startswith("unhide")}
    check(set(buttons) == {"unhide:pf-test-alpha.desktop", "unhide:pf-test-gamma.desktop", "unhide:pf-removed-app.desktop",
                           "unhideAll"}, "a Show button per hidden app, and Show All")
    QMetaObject.invokeMethod(buttons["unhide:pf-test-gamma.desktop"], "click")
    QTest.qWait(100)
    check(json.loads(call(settings, "hidden")) == ["pf-test-alpha.desktop", "pf-removed-app.desktop"],
          "Show removes that app from the hidden list (Apply then writes it)")
    QMetaObject.invokeMethod(buttons["unhideAll"], "click")
    QTest.qWait(100)
    check(json.loads(call(settings, "hidden")) == [], "Show All empties the hidden list")

    # Kicker reads hiddenApplications (and offers Hide Application) through
    # `appletInterface.configuration`, which a Plasma 6 PlasmoidItem does not have: main.qml must
    # declare it. Here a stand-in configuration hides Alpha.
    main_qml = (package / "contents/ui/main.qml").read_text()
    check(re.search(r"^    readonly property QtObject configuration: Plasmoid\.configuration$", main_qml, re.M) is not None,
          "main.qml gives Kicker the applet's configuration (appletInterface.configuration)")
    with warnings.catch_warnings():
        # PySide6 6.11 marks the constructor deprecated (its parent argument); Kicker needs the type.
        warnings.simplefilter("ignore", DeprecationWarning)
        config = QQmlPropertyMap()
    config.insert("hiddenApplications", ["pf-test-alpha.desktop"])
    engine.rootContext().setContextProperty("testConfig", config)
    KICKER = b"""
import QtQuick
import org.kde.plasma.private.kicker as Kicker
QtObject {
    id: probe
    property QtObject withConfig: QtObject { property QtObject configuration: testConfig }
    property QtObject withoutConfig: QtObject {}
    property Kicker.RootModel rootWith: Kicker.RootModel {
        autoPopulate: false; appletInterface: probe.withConfig; flat: true; sorted: true
        showAllApps: true; showRecentApps: false; showRecentDocs: false; showRecentFolders: false
    }
    property Kicker.RootModel rootWithout: Kicker.RootModel {
        autoPopulate: false; appletInterface: probe.withoutConfig; flat: true; sorted: true
        showAllApps: true; showRecentApps: false; showRecentDocs: false; showRecentFolders: false
    }
    property var readers: []
    // Test apps in the all-apps list. (Their menus are not read: Kicker builds them with the
    // applet behind appletInterface, which this stand-in is not; the VM scenario shows them.)
    function apps(which) {
        const root = which === "with" ? rootWith : rootWithout;
        root.refresh();
        const all = root.modelForRow(0);
        const reader = Qt.createQmlObject('import QtQuick; Instantiator { delegate: QtObject { '
            + 'required property string display } }', probe);
        reader.model = all;
        const out = [];
        for (let i = 0; i < reader.count; ++i) {
            const e = reader.objectAt(i);
            if (e.display.indexOf(" Test") > 0) {
                out.push(e.display);
            }
        }
        reader.destroy();
        return JSON.stringify(out.sort());
    }
}
"""
    kicker_component = QQmlComponent(engine)
    kicker_component.setData(KICKER, QUrl.fromLocalFile(str(stage / "contents/ui/KickerProbe.qml")))
    kicker = kicker_component.create()
    if kicker is None:
        raise AssertionError("Kicker probe did not load: " + "; ".join(e.toString() for e in kicker_component.errors()))
    check(json.loads(call(kicker, "apps", "with")) == ["Beta Test", "Gamma Test"],
          "with the configuration Kicker leaves the hidden app out")
    check(json.loads(call(kicker, "apps", "without")) == ["Alpha Test", "Beta Test", "Gamma Test"],
          "without it (a plain PlasmoidItem) the hidden list has no effect")

    # The chips: Left and Right walk All -> Recent -> Office.
    call(win, "openMode", "home")
    QTest.qWait(100)
    call(win, "selectChip", 1)
    QTest.qWait(100)
    check(json.loads(call(win, "state"))["view"] == "history", "the second chip is Recent")

    # The chips are rebuilt when the menu changes (Hide Application on the last app of a category
    # drops its chip): the chosen category stays chosen by key, and a category that is gone gives
    # way to "All" instead of the next category, or an empty grid titled "Pinned".
    fixed = [{"key": "all", "label": "All", "row": -1, "view": "home"},
             {"key": "recentapps", "label": "Recent", "row": -1, "view": "history"},
             {"key": "places", "label": "Places", "row": -1, "view": "places"}]
    office = {"key": "office", "label": "Office", "row": 3, "view": "category"}
    call(win, "selectChip", 3)
    QTest.qWait(100)
    s = json.loads(call(win, "state"))
    check(s["view"] == "category" and s["chip"] == 3 and s["chipKey"] == "office", "the Office chip is chosen")
    call(win, "setChips", json.dumps(fixed + [{"key": "education", "label": "Education", "row": 2, "view": "category"},
                                              dict(office, row=4)]))
    QTest.qWait(100)
    s = json.loads(call(win, "state"))
    check(s["view"] == "category" and s["chip"] == 4 and s["chipKey"] == "office",
          "a chip added before it: Office stays chosen at its new place (%s)" % s)
    call(win, "setChips", json.dumps(fixed + [{"key": "graphics", "label": "Graphics", "row": 2, "view": "category"}]))
    QTest.qWait(100)
    s = json.loads(call(win, "state"))
    check(s["view"] == "home" and s["chip"] == 0, "its category gone: back to All, not the next chip (%s)" % s)
    call(win, "setChips", json.dumps(fixed + [office]))
    call(win, "selectChip", 3)
    call(win, "setChips", json.dumps(fixed))
    QTest.qWait(100)
    s = json.loads(call(win, "state"))
    check(s["view"] == "home" and s["chip"] == 0, "the last chip gone: All, not an empty grid titled Pinned (%s)" % s)
    print(f"views: {checks} checks passed")
finally:
    kamd.terminate()
    try:
        kamd.wait(5)
    except subprocess.TimeoutExpired:
        kamd.kill()
    shutil.rmtree(home, ignore_errors=True)
