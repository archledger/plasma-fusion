/*
    Plasma Fusion settings module: everything that goes through the Plasma shell (desktop
    scripting over org.kde.PlasmaShell.evaluateScript), and the two actions at the end of the page.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kcm.h"
#include "kcm_p.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KSharedConfig>

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QEventLoop>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeySequence>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QThread>

#include <algorithm>
#include <limits>

using namespace Qt::StringLiterals;
using namespace PlasmaFusion;

namespace
{
// Reads the shell state in one call: the dock's and the launcher's keys, the top bar (the panel holding
// org.plasmafusion.appname; the one with quick settings when there are several) and whether it
// has the system meters, the quick settings' keyboard policy and the Folder View desktop's filter
// and icon size. A panel's opacity and sizes are read only while its screen is there: for a
// panel of a monitor that was unplugged (Plasma 6.8 keeps it on that screen) plasmashell reads
// them from an invalid config group and crashes (WorkspaceScripting::Panel, KConfigGroup).
const QString s_readShellScript =
    uR"JS(
function bool(v, d) {
    if (v === undefined || v === null || v === "") {
        return d;
    }
    return !(v === false || v === "false");
}
var state = { docks: 0, magnify: true, magnifiedSize: 62, homeIndicator: true,
              topBars: 0, menu: false, topOpacity: "", meters: false,
              metersInstalled: knownWidgetTypes.indexOf("org.plasmafusion.meters") !== -1,
              quickSettings: 0, keyboardPolicy: "tablet",
              launchers: 0, recentFiles: true, recentApps: true, places: true,
              recentFilesOn: 0, recentAppsOn: 0, placesOn: 0,
              folders: 0, filterMode: 0, filterPattern: "*", iconSize: 3 };
var mainTopBar = false, chosenTopBar = false;
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var p = ps[i];
    var docks = p.widgets("org.plasmafusion.dock");
    for (var j = 0; j < docks.length; ++j) {
        docks[j].currentConfigGroup = ["General"];
        if (state.docks === 0) {
            state.magnify = bool(docks[j].readConfig("magnify", true), true);
            state.magnifiedSize = Number(docks[j].readConfig("magnifiedSize", 62)) || 62;
            state.homeIndicator = bool(docks[j].readConfig("homeIndicator", true), true);
        }
        ++state.docks;
    }
    // A section is on only while every launcher shows it: with launchers that differ, the page
    // shows it off (and says they differ: how many show it), and setting it writes it to all.
    var launchers = p.widgets("org.plasmafusion.launcher");
    for (var j = 0; j < launchers.length; ++j) {
        launchers[j].currentConfigGroup = ["General"];
        var recentFiles = bool(launchers[j].readConfig("showRecommended", true), true);
        var recentApps = bool(launchers[j].readConfig("showRecentApps", true), true);
        var places = bool(launchers[j].readConfig("showPlaces", true), true);
        state.recentFiles = state.recentFiles && recentFiles;
        state.recentApps = state.recentApps && recentApps;
        state.places = state.places && places;
        state.recentFilesOn += recentFiles ? 1 : 0;
        state.recentAppsOn += recentApps ? 1 : 0;
        state.placesOn += places ? 1 : 0;
        ++state.launchers;
    }
    var qs = p.widgets("org.plasmafusion.quicksettings");
    for (var j = 0; j < qs.length; ++j) {
        qs[j].currentConfigGroup = ["General"];
        if (state.quickSettings === 0) {
            state.keyboardPolicy = String(qs[j].readConfig("keyboardPolicy", "tablet"));
        }
        ++state.quickSettings;
    }
    if (p.widgets("org.plasmafusion.appname").length > 0) {
        var onScreen = p.screen >= 0 && p.screen < screenCount;
        if (onScreen && (!chosenTopBar || (!mainTopBar && qs.length > 0))) {
            state.menu = p.widgets("org.kde.plasma.appmenu").length > 0;
            state.meters = p.widgets("org.plasmafusion.meters").length > 0;
            state.topOpacity = String(p.opacity);
            mainTopBar = qs.length > 0;
            chosenTopBar = true;
        }
        ++state.topBars;
    }
}
var ds = desktops();
for (var i = 0; i < ds.length; ++i) {
    var d = ds[i];
    if (d.type !== "org.kde.plasma.folder" && d.type !== "org.plasmafusion.desktop") {
        continue;
    }
    d.currentConfigGroup = ["General"];
    if (state.folders === 0) {
        state.filterMode = Number(d.readConfig("filterMode", 0));
        state.filterPattern = String(d.readConfig("filterPattern", "*"));
        state.iconSize = Number(d.readConfig("iconSize", 3));
    }
    ++state.folders;
}
print(JSON.stringify(state));
)JS"_s;

// %1: true or false. Writing through the widget's configuration scheme updates the running dock.
const QString s_magnifyScript = uR"JS(
var value = %1;
var count = 0;
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var docks = ps[i].widgets("org.plasmafusion.dock");
    for (var j = 0; j < docks.length; ++j) {
        docks[j].currentConfigGroup = ["General"];
        docks[j].writeConfig("magnify", value);
        ++count;
    }
}
print(count);
)JS"_s;

// %1 widget plugin, %2 key, %3 value (JavaScript literals): the [General] key of every such
// widget in a panel.
const QString s_widgetKeyScript = uR"JS(
var plugin = %1, key = %2, value = %3;
var count = 0;
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var ws = ps[i].widgets(plugin);
    for (var j = 0; j < ws.length; ++j) {
        ws[j].currentConfigGroup = ["General"];
        ws[j].writeConfig(key, value);
        ++count;
    }
}
print(count);
)JS"_s;

// %1: true (add the stock global menu to the top bar) or false (remove it). The menu is added
// at the position just right of the application name, so the panel inserts it there directly
// (adding it at the end and moving it afterwards left the clock pill off-centre until the next
// shell start).
const QString s_globalMenuScript = uR"JS(
var want = %1;
var changed = 0;
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var names = ps[i].widgets("org.plasmafusion.appname");
    if (names.length === 0) {
        continue;
    }
    var menus = ps[i].widgets("org.kde.plasma.appmenu");
    if (want && menus.length === 0) {
        var g = names[0].geometry;
        var menu = g ? ps[i].addWidget("org.kde.plasma.appmenu", Math.max(0, g.x + g.width + 2), 1, -1, -1)
                     : ps[i].addWidget("org.kde.plasma.appmenu");
        if (menu) {
            ++changed;
        }
    } else if (!want) {
        for (var j = 0; j < menus.length; ++j) {
            menus[j].remove();
            ++changed;
        }
    }
}
print(changed);
)JS"_s;

// %1: true (add the system meters to every top bar that has none, right before quick settings)
// or false (remove every meters widget from the panels). As the global menu, the widget is added
// at the position just left of quick settings, so the panel inserts it there directly. Prints
// {added: [ids of the new widgets], present: top bars that had meters, failed: adds that failed}.
// addWidget returns an Error object, which is truthy, when the shell cannot make the widget.
const QString s_metersScript =
    uR"JS(
var want = %1;
var result = { added: [], present: 0, failed: 0 };
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var meters = ps[i].widgets("org.plasmafusion.meters");
    if (!want) {
        for (var j = 0; j < meters.length; ++j) {
            meters[j].remove();
        }
        continue;
    }
    if (ps[i].widgets("org.plasmafusion.appname").length === 0) {
        continue;
    }
    if (meters.length > 0) {
        ++result.present;
        continue;
    }
    var qs = ps[i].widgets("org.plasmafusion.quicksettings");
    if (qs.length === 0) {
        continue;
    }
    var g = qs[0].geometry;
    var added = g ? ps[i].addWidget("org.plasmafusion.meters", Math.max(0, g.x - 2), 1, -1, -1)
                  : ps[i].addWidget("org.plasmafusion.meters");
    if (added && !(added instanceof Error)) {
        result.added.push(added.id);
    } else {
        ++result.failed;
    }
}
print(JSON.stringify(result));
)JS"_s;

// %1: the ids of the meters widgets just added (a JSON array of numbers). Checks that each sits
// right before quick settings in its panel and moves it there if not (a second call, as for the
// global menu); prints how many of them the shell lists. Meters placed by hand stay where they are.
const QString s_placeMetersScript =
    uR"JS(
var ids = %1;
var placed = 0;
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var qs = ps[i].widgets("org.plasmafusion.quicksettings");
    var meters = ps[i].widgets("org.plasmafusion.meters");
    for (var j = 0; j < meters.length && qs.length > 0; ++j) {
        if (ids.indexOf(meters[j].id) === -1) {
            continue;
        }
        // Moving up the order, the widget lands at the index given; moving down, the ones in
        // between move up a place.
        var at = meters[j].index < qs[0].index ? qs[0].index - 1 : qs[0].index;
        if (meters[j].index !== at) {
            meters[j].index = at;
        }
        ++placed;
    }
}
print(placed);
)JS"_s;

// Checks that the global menu sits right after the application name and moves it there if not
// (the panel saves its order on the next event loop pass, so this runs as a second call).
const QString s_placeMenuScript = uR"JS(
var placed = 0;
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var names = ps[i].widgets("org.plasmafusion.appname");
    var menus = ps[i].widgets("org.kde.plasma.appmenu");
    if (names.length === 0 || menus.length === 0) {
        continue;
    }
    var at = names[0].index + 1;
    if (menus[0].index !== at) {
        menus[0].index = at;
    }
    ++placed;
}
print(placed);
)JS"_s;

// %1 top-bar opacity, %2 dock opacity, %3 the widgets' glass value or null (leave them), %4 the
// widget types that have a glass key. Only panels holding Plasma Fusion widgets change; a panel
// whose screen is gone keeps its opacity (reading or writing it crashes plasmashell 6.8, see
// s_readShellScript), its widgets get the glass value.
const QString s_panelsScript =
    uR"JS(
var topOpacity = %1, dockOpacity = %2, glass = %3, glassTypes = %4;
var result = { panels: 0, widgets: 0 };
function glassFor(c) {
    if (glass === null) {
        return;
    }
    var ws = c.widgets();
    for (var j = 0; j < ws.length; ++j) {
        if (glassTypes.indexOf(String(ws[j].type)) < 0) {
            continue;
        }
        ws[j].currentConfigGroup = ["General"];
        ws[j].writeConfig("glass", glass);
        ++result.widgets;
    }
}
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var p = ps[i];
    var top = p.widgets("org.plasmafusion.appname").length > 0 || p.widgets("org.plasmafusion.clockpill").length > 0
        || p.widgets("org.plasmafusion.quicksettings").length > 0;
    var dock = p.widgets("org.plasmafusion.dock").length > 0;
    var want = top ? topOpacity : dock ? dockOpacity : "";
    if (want !== "" && p.screen >= 0 && p.screen < screenCount && String(p.opacity) !== want) {
        p.opacity = want;
        ++result.panels;
    }
    glassFor(p);
}
var ds = desktops();
for (var i = 0; i < ds.length; ++i) {
    glassFor(ds[i]);
}
print(JSON.stringify(result));
)JS"_s;

// The docks "Dock on every screen" added (their panels and docks marked [PlasmaFusion]
// everyScreenCopy by ensure-topbars.js) are removed with their panels (their launchers too); every
// other dock gets back the showOnlyCurrentScreen it had before (its [PlasmaFusion]
// onlyCurrentScreenBefore, kept by ensure-topbars.js; then emptied). Docks the user made stay. When
// no dock but copies is left on a screen that is there (the user removed the one there was, or it
// is on a monitor that is unplugged), the copy on the lowest screen stays as the one dock: no
// longer a copy, listing every screen's windows, and standing in for the unplugged screens' docks
// ([PlasmaFusion] standInFor, their panel ids; ensure-topbars.js removes it when one is back).
// Prints how many panels went.
const QString s_removeExtraDocksScript =
    uR"JS(
function mark(w, key) {
    w.currentConfigGroup = ["PlasmaFusion"];
    var value = String(w.readConfig(key, ""));
    w.currentConfigGroup = [];
    return value;
}
function isCopy(p, docks) {
    var copy = mark(p, "everyScreenCopy") === "true";
    for (var j = 0; j < docks.length; ++j) {
        copy = copy || mark(docks[j], "everyScreenCopy") === "true";
    }
    return copy;
}
function shown(p) {
    return p.screen >= 0 && p.screen < screenCount;
}
var removed = 0, keep = null, original = false, away = [];
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var docks = ps[i].widgets("org.plasmafusion.dock");
    if (docks.length === 0) {
        continue;
    }
    if (!isCopy(ps[i], docks)) {
        original = original || shown(ps[i]);
        if (!shown(ps[i])) {
            away.push(ps[i].id);
        }
    } else if (shown(ps[i]) && (keep === null || ps[i].screen < keep.screen)) {
        keep = ps[i];
    }
}
if (original) {
    keep = null;
}
for (var i = 0; i < ps.length; ++i) {
    var docks = ps[i].widgets("org.plasmafusion.dock");
    var copy = isCopy(ps[i], docks);
    if (keep !== null && ps[i].id === keep.id) {
        // It stands in for the docks of unplugged screens: ensure-topbars.js removes it when one
        // of them is on a screen again.
        ps[i].currentConfigGroup = ["PlasmaFusion"];
        ps[i].writeConfig("everyScreenCopy", "");
        ps[i].writeConfig("standInFor", away.join(","));
        ps[i].currentConfigGroup = [];
        for (var j = 0; j < docks.length; ++j) {
            docks[j].currentConfigGroup = ["PlasmaFusion"];
            docks[j].writeConfig("everyScreenCopy", "");
            docks[j].currentConfigGroup = ["General"];
            docks[j].writeConfig("showOnlyCurrentScreen", false);
            docks[j].currentConfigGroup = [];
        }
        continue;
    }
    if (copy) {
        ps[i].remove();
        ++removed;
        continue;
    }
    for (var j = 0; j < docks.length; ++j) {
        var before = mark(docks[j], "onlyCurrentScreenBefore");
        if (before !== "") {
            docks[j].currentConfigGroup = ["PlasmaFusion"];
            docks[j].writeConfig("onlyCurrentScreenBefore", "");
            docks[j].currentConfigGroup = ["General"];
            docks[j].writeConfig("showOnlyCurrentScreen", before === "true");
            docks[j].currentConfigGroup = [];
        }
    }
}
print(removed);
)JS"_s;

// Top bars on the screens other than the main one are removed. The main one is the top bar with
// quick settings on the lowest screen number (every screen's bar has quick settings since
// 2026-10-09; the primary screen is 0), else the top bar on the lowest screen number.
const QString s_removeExtraTopBarsScript =
    uR"JS(
var tops = [], main = null, removed = 0;
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var p = ps[i];
    if (p.widgets("org.plasmafusion.appname").length === 0 && p.widgets("org.plasmafusion.clockpill").length === 0) {
        continue;
    }
    tops.push(p);
    if (p.widgets("org.plasmafusion.quicksettings").length > 0 && p.screen >= 0
            && (main === null || p.screen < main.screen)) {
        main = p;
    }
}
if (main === null) {
    for (var i = 0; i < tops.length; ++i) {
        if (main === null || tops[i].screen < main.screen) {
            main = tops[i];
        }
    }
}
// A shortcut held by quick settings in a removed bar moves to the main bar's quick settings.
var mainQs = main !== null ? main.widgets("org.plasmafusion.quicksettings") : [];
for (var i = 0; main !== null && i < tops.length; ++i) {
    if (tops[i].id !== main.id && tops[i].screen !== main.screen) {
        var qs = tops[i].widgets("org.plasmafusion.quicksettings");
        for (var j = 0; j < qs.length; ++j) {
            var key = String(qs[j].globalShortcut || "");
            if (key !== "" && mainQs.length > 0 && String(mainQs[0].globalShortcut || "") === "") {
                qs[j].globalShortcut = "";
                mainQs[0].globalShortcut = key;
            }
        }
        tops[i].remove();
        ++removed;
    }
}
print(removed);
)JS"_s;

// %1: true (show icons), false (hide them) or null (leave); %2: iconSize or null. Hidden =
// filterMode 1 ("show files matching") with a pattern no file name matches; Folder View keeps
// the positions of filtered items (positioner.cpp only adds entries while items are away), so
// they come back where they were. A filter the user set up in Folder View is left alone when
// the icons are shown again.
const QString s_desktopScript = uR"JS(
var icons = %1, size = %2, hideAll = %3;
var count = 0;
var ds = desktops();
for (var i = 0; i < ds.length; ++i) {
    var d = ds[i];
    if (d.type !== "org.kde.plasma.folder" && d.type !== "org.plasmafusion.desktop") {
        continue;
    }
    d.currentConfigGroup = ["General"];
    if (icons === false) {
        d.writeConfig("filterPattern", hideAll);
        d.writeConfig("filterMode", 1);
    } else if (icons === true && Number(d.readConfig("filterMode", 0)) === 1 && String(d.readConfig("filterPattern", "*")) === hideAll) {
        d.writeConfig("filterMode", 0);
        d.writeConfig("filterPattern", "*");
    }
    if (size !== null) {
        d.writeConfig("iconSize", size);
    }
    ++count;
}
print(count);
)JS"_s;

// Every widget of the panels and desktops with its global shortcut, and all their ids.
const QString s_widgetsScript = uR"JS(
var out = { panels: 0, widgets: [], ids: [] };
function collect(c) {
    out.ids.push(c.id);
    var ws = c.widgets();
    for (var j = 0; j < ws.length; ++j) {
        out.ids.push(ws[j].id);
        out.widgets.push({ type: String(ws[j].type), id: ws[j].id, key: String(ws[j].globalShortcut || "") });
    }
}
var ps = panels();
out.panels = ps.length;
for (var i = 0; i < ps.length; ++i) {
    collect(ps[i]);
}
var ds = desktops();
for (var i = 0; i < ds.length; ++i) {
    collect(ds[i]);
}
print(JSON.stringify(out));
)JS"_s;

// %1 widget id, %2 key sequence (portable text).
const QString s_setShortcutScript = uR"JS(
var id = %1, key = %2, found = false, now = "";
var cs = [panels(), desktops()];
for (var k = 0; k < cs.length && !found; ++k) {
    for (var i = 0; i < cs[k].length && !found; ++i) {
        var w = cs[k][i].widgetById(id);
        if (w) {
            w.globalShortcut = key;
            now = String(w.globalShortcut || "");
            found = true;
        }
    }
}
print(JSON.stringify({ found: found, key: now }));
)JS"_s;

// Shortcuts a layout reset gives when the widget type had none before (owner decision 6: Meta+A
// opens quick settings), as tools/device/fusion-config.sh does. The pen menu's Meta+Shift+W is
// fusion-config.sh --pen's, so it comes back only when the old pen menu had it (keyByType).
struct DefaultShortcut {
    QString plugin;
    QString key;
};
const QList<DefaultShortcut> s_defaultShortcuts = {
    {u"org.plasmafusion.quicksettings"_s, u"Meta+A"_s},
};

// A key sequence as kglobalaccel's D-Bus type (ai): four Qt key codes.
QDBusArgument keyArgument(const QKeySequence &sequence)
{
    QDBusArgument argument;
    argument.beginStructure();
    argument.beginArray(QMetaType::fromType<int>());
    for (int i = 0; i < 4; ++i) {
        argument << (i < sequence.count() ? sequence[i].toCombined() : 0);
    }
    argument.endArray();
    argument.endStructure();
    return argument;
}

QDBusMessage kglobalaccel(const QString &method)
{
    return QDBusMessage::createMethodCall(u"org.kde.kglobalaccel"_s, u"/kglobalaccel"_s, u"org.kde.KGlobalAccel"_s, method);
}

QString widgetName(const QString &plugin)
{
    if (plugin == u"org.plasmafusion.quicksettings") {
        return i18nc("@item widget name", "quick settings");
    }
    if (plugin == u"org.plasmafusion.pen") {
        return i18nc("@item widget name", "pen menu");
    }
    if (plugin == u"org.plasmafusion.launcher") {
        return i18nc("@item widget name", "launcher");
    }
    return plugin;
}
} // namespace

// Apply and the actions change the shell step by step, each step on the answer of the one before.
// The answer is awaited in a local event loop rather than with QDBus::Block: a shell that is slow
// to answer (just restarted, up to s_shellTimeout) must not freeze the page, and KWin offers to end
// a window that has not answered its ping for 5 s. User input waits meanwhile, so no other change
// can start; the page shows that it is busy. A shell state answer arriving meanwhile is read again
// afterwards (requestShellState).
QString PlasmaFusionKcm::evaluateShellScript(const QString &script, bool *ok)
{
    const QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(shellScriptMessage(script), s_shellTimeout);
    if (!call.isFinished()) {
        QDBusPendingCallWatcher watcher(call);
        QEventLoop loop;
        connect(&watcher, &QDBusPendingCallWatcher::finished, &loop, &QEventLoop::quit);
        const bool wasBusy = m_busy;
        setBusy(true);
        loop.exec(QEventLoop::ExcludeUserInputEvents);
        setBusy(wasBusy);
    }
    const QDBusPendingReply<QString> reply = call;
    if (reply.isError()) {
        *ok = false;
        return reply.error().message();
    }
    *ok = true;
    return lastLine(reply.value());
}

void PlasmaFusionKcm::requestShellState()
{
    const int request = ++m_shellRequest;
    m_shellLoading = true;
    Q_EMIT shellStateChanged();

    const QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(shellScriptMessage(s_readShellScript), s_shellTimeout);
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, request](QDBusPendingCallWatcher *watcher) {
        watcher->deleteLater();
        if (request != m_shellRequest) {
            return;
        }
        if (m_saving || m_busy) {
            // Inside Apply or an action (waiting in evaluateShellScript): the state may already be
            // older than the change being made.
            m_shellStateDeferred = true;
            return;
        }
        shellStateArrived(watcher);
    });
}

void PlasmaFusionKcm::shellStateArrived(QDBusPendingCallWatcher *watcher)
{
    const QDBusPendingReply<QString> reply = *watcher;
    m_shellLoading = false;
    m_shellRunning = !reply.isError();
    m_dockAvailable = false;
    m_topBarAvailable = false;
    m_metersAvailable = false;
    m_quickSettingsAvailable = false;
    m_launcherAvailable = false;
    m_launcherMixed.clear();
    m_folderAvailable = false;
    if (reply.isError()) {
        qCWarning(KCM_PLASMAFUSION) << "Could not read the Plasma shell layout:" << reply.error().message();
    } else {
        const QJsonObject state = QJsonDocument::fromJson(lastLine(reply.value()).toUtf8()).object();
        m_dockAvailable = state.value(u"docks"_s).toInt() > 0;
        m_topBarAvailable = state.value(u"topBars"_s).toInt() > 0;
        m_metersAvailable = state.value(u"metersInstalled"_s).toBool();
        m_quickSettingsAvailable = state.value(u"quickSettings"_s).toInt() > 0;
        m_launcherAvailable = state.value(u"launchers"_s).toInt() > 0;
        m_folderAvailable = state.value(u"folders"_s).toInt() > 0;

        // A change still pending on the page (the shell restarted meanwhile) is kept.
        const auto take = [](auto &current, auto &saved, const auto value) {
            const bool pending = current != saved;
            saved = value;
            if (!pending) {
                current = value;
            }
        };
        if (m_dockAvailable) {
            bool magnify = state.value(u"magnify"_s).toBool(true);
            if (m_powerCritical) {
                // The power service holds the magnification off; show the value it will restore.
                KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
                fusion->reparseConfiguration();
                magnify = KConfigGroup(fusion, u"Power"_s).readEntry("UserDockMagnify", magnify);
            }
            take(m_current.magnify, m_saved.magnify, magnify);
            take(m_current.magnifiedSize, m_saved.magnifiedSize, state.value(u"magnifiedSize"_s).toInt(62));
            take(m_current.homeIndicator, m_saved.homeIndicator, state.value(u"homeIndicator"_s).toBool(true));
        }
        if (m_topBarAvailable) {
            take(m_current.globalMenu, m_saved.globalMenu, state.value(u"menu"_s).toBool(true));
            take(m_current.systemMeters, m_saved.systemMeters, state.value(u"meters"_s).toBool(false));
            // "adaptive": solid next to windows; "translucent": always glass. With Reduced glass
            // the bar is opaque, and the choice the page made last is in plasmafusionrc.
            const QString opacity = state.value(u"topOpacity"_s).toString();
            if (opacity == u"adaptive" || opacity == u"translucent") {
                take(m_current.solidTopBar, m_saved.solidTopBar, opacity == u"adaptive");
            } else {
                KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
                fusion->reparseConfiguration();
                take(m_current.solidTopBar, m_saved.solidTopBar, KConfigGroup(fusion, u"TopBar"_s).readEntry("SolidNextToWindows", true));
            }
        }
        if (m_quickSettingsAvailable) {
            static const QStringList policies = {u"tablet"_s, u"touch"_s, u"never"_s};
            const int policy = policies.indexOf(state.value(u"keyboardPolicy"_s).toString());
            take(m_current.keyboardPolicy, m_saved.keyboardPolicy, policy >= 0 ? policy : int(KeyboardTablet));
        }
        if (m_launcherAvailable) {
            take(m_current.launcherRecentFiles, m_saved.launcherRecentFiles, state.value(u"recentFiles"_s).toBool(true));
            take(m_current.launcherRecentApps, m_saved.launcherRecentApps, state.value(u"recentApps"_s).toBool(true));
            take(m_current.launcherPlaces, m_saved.launcherPlaces, state.value(u"places"_s).toBool(true));
            // The keys some launchers show and some do not.
            const int launchers = state.value(u"launchers"_s).toInt();
            const std::pair<QString, QString> counts[] = {
                {u"recentFilesOn"_s, u"showRecommended"_s},
                {u"recentAppsOn"_s, u"showRecentApps"_s},
                {u"placesOn"_s, u"showPlaces"_s},
            };
            for (const auto &[count, key] : counts) {
                const int on = state.value(count).toInt();
                if (on > 0 && on < launchers) {
                    m_launcherMixed.insert(key);
                }
            }
        }
        if (m_folderAvailable) {
            const bool hidden = state.value(u"filterMode"_s).toInt() == 1 && state.value(u"filterPattern"_s).toString() == s_hideAllPattern;
            take(m_current.desktopIcons, m_saved.desktopIcons, !hidden);
            take(m_current.iconSize, m_saved.iconSize, state.value(u"iconSize"_s).toInt(3));
        }
        // A switch set while its key was mixed stays a change while the launchers still differ
        // (also across a shell restart; a read that failed changes nothing).
        m_launcherMixedSet.intersect(m_launcherMixed);
    }
    Q_EMIT shellStateChanged();
    Q_EMIT magnifyChanged();
    Q_EMIT globalMenuChanged();
    Q_EMIT stateChanged();
    settingsChanged();
}

bool PlasmaFusionKcm::applyMagnify(bool on)
{
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    KConfigGroup power(fusion, u"Power"_s);
    if (m_powerCritical) {
        // The power service keeps the dock still at 10 % battery and gives every dock this value
        // when the battery recovers ([Power] PageDockMagnify); UserDockMagnify is what the page
        // shows meanwhile.
        power.writeEntry("UserDockMagnify", on, KConfig::Notify);
        power.writeEntry("PageDockMagnify", on, KConfig::Notify);
        fusion->sync();
        return true;
    }
    power.deleteEntry("PageDockMagnify", KConfig::Notify);
    fusion->sync();
    bool ok = false;
    const QString result = evaluateShellScript(s_magnifyScript.arg(on ? u"true"_s : u"false"_s), &ok);
    if (!ok || result.toInt() < 1) {
        addError(i18nc("@info", "The dock setting could not be changed: %1", ok ? i18nc("@info", "no Plasma Fusion dock found") : result));
        return false;
    }
    return true;
}

bool PlasmaFusionKcm::applyMagnifiedSize(int size)
{
    return applyWidgetKey(u"org.plasmafusion.dock"_s, u"magnifiedSize"_s, QString::number(size), i18nc("@info", "The dock setting could not be changed."));
}

bool PlasmaFusionKcm::applyWidgetKey(const QString &plugin, const QString &key, const QString &jsValue, const QString &what)
{
    bool ok = false;
    const QString result = evaluateShellScript(s_widgetKeyScript.arg(jsString(plugin), jsString(key), jsValue), &ok);
    if (!ok || result.toInt() < 1) {
        addError(ok ? what : i18nc("@info %1 what failed, %2 error", "%1 %2", what, result));
        return false;
    }
    return true;
}

bool PlasmaFusionKcm::applyGlobalMenu(bool on)
{
    bool ok = false;
    const QString result = evaluateShellScript(s_globalMenuScript.arg(on ? u"true"_s : u"false"_s), &ok);
    if (!ok) {
        addError(i18nc("@info", "The top bar could not be changed: %1", result));
        return false;
    }
    if (on) {
        // Let the panel store its new widget order before moving the menu.
        QThread::msleep(300);
        const QString placed = evaluateShellScript(s_placeMenuScript, &ok);
        if (!ok || placed.toInt() < 1) {
            addError(i18nc("@info", "The global menu could not be placed after the application name."));
            return false;
        }
    }
    return true;
}

bool PlasmaFusionKcm::applySystemMeters(bool on)
{
    // A placement still running for an earlier Apply stops.
    const int request = ++m_metersPlacement;
    bool ok = false;
    const QString output = evaluateShellScript(s_metersScript.arg(on ? u"true"_s : u"false"_s), &ok);
    if (!ok) {
        addError(i18nc("@info", "The top bar could not be changed: %1", output));
        return false;
    }
    if (!on) {
        return true;
    }
    const QJsonObject result = QJsonDocument::fromJson(output.toUtf8()).object();
    QList<int> ids;
    for (const QJsonValue &id : result.value(u"added"_s).toArray()) {
        ids << id.toInt();
    }
    if (result.value(u"failed"_s).toInt() > 0) {
        addError(i18nc("@info", "The system meters could not be added to the top bar."));
    } else if (ids.isEmpty() && result.value(u"present"_s).toInt() == 0) {
        // The meters go next to quick settings; a top bar without it (the stock system tray in
        // its place, for example) gets none.
        addError(i18nc("@info", "The top bar has no Quick Settings to place the system meters next to."));
    }
    if (ids.isEmpty()) {
        return m_errorText.isEmpty();
    }
    // The power service gives the new meters the current tier (they run at full rate otherwise).
    reapplyPowerTier();
    // Let the panel store its new widget order before moving the meters. A QML widget the shell
    // loads for the first time is listed only once it is built (about 0.5 s in the test VM), so
    // the placement asks again, from the event loop, for up to 3 s.
    QTimer::singleShot(300, this, [this, ids, request] {
        placeSystemMeters(ids, 0, request);
    });
    return true;
}

void PlasmaFusionKcm::placeSystemMeters(const QList<int> &ids, int attempt, int request)
{
    if (request != m_metersPlacement) {
        return;
    }
    QStringList list;
    for (const int id : ids) {
        list << QString::number(id);
    }
    const QString script = s_placeMetersScript.arg(u'[' + list.join(u',') + u']');
    const QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(shellScriptMessage(script), s_shellTimeout);
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, ids, attempt, request](QDBusPendingCallWatcher *watcher) {
        const QDBusPendingReply<QString> reply = *watcher;
        watcher->deleteLater();
        if (request != m_metersPlacement) {
            return;
        }
        if (!reply.isError() && lastLine(reply.value()).toInt() >= ids.size()) {
            return;
        }
        if (attempt < 9) {
            QTimer::singleShot(300, this, [this, ids, attempt, request] {
                placeSystemMeters(ids, attempt + 1, request);
            });
            return;
        }
        addError(i18nc("@info", "The system meters could not be placed before quick settings."));
    });
}

// The power service sets a tier's keys (the meters' and cards' powerTier, the glass held at
// critical) on the widgets there are when the tier changes or plasmashell starts; a widget added
// later would run at full rate until the next change. Its reload (SIGHUP) applies the tier again;
// try-reload-or-restart does nothing when the service is not running.
void PlasmaFusionKcm::reapplyPowerTier()
{
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    const QString tier = KConfigGroup(fusion, u"Power"_s).readEntry("Tier", QString());
    if (tier.isEmpty() || tier.compare(u"full"_s, Qt::CaseInsensitive) == 0) {
        return;
    }
    QProcess::startDetached(u"systemctl"_s, {u"--user"_s, u"try-reload-or-restart"_s, u"plasma-fusion-powerfx.service"_s});
}

// EFFECTS.md 3.3: Reduced makes both Fusion panels opaque; otherwise the top bar is adaptive
// (solid next to a maximized window, owner decision 5) or translucent, and the dock translucent.
// With widgetGlass the Fusion widgets' glass key follows the level too.
bool PlasmaFusionKcm::applyPanels(int glass, bool solidTopBar, bool widgetGlass)
{
    // Kept for when the bars are opaque (Reduced glass) and for top bars added later
    // (ensure-topbars.js).
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    KConfigGroup(fusion, u"TopBar"_s).writeEntry("SolidNextToWindows", solidTopBar, KConfig::Notify);
    fusion->sync();

    static const QStringList widgetValues = {u"full"_s, u"reduced"_s, u"solid"_s};
    const QString top = glass == GlassReduced ? u"opaque"_s : solidTopBar ? u"adaptive"_s : u"translucent"_s;
    const QString dock = glass == GlassReduced ? u"opaque"_s : u"translucent"_s;
    QStringList types;
    for (const QString &type : s_glassWidgets) {
        types << jsString(type);
    }
    bool ok = false;
    const QString result = evaluateShellScript(s_panelsScript.arg(jsString(top),
                                                                  jsString(dock),
                                                                  widgetGlass ? jsString(widgetValues.value(glass)) : u"null"_s,
                                                                  u"["_s + types.join(u',') + u']'),
                                               &ok);
    if (!ok) {
        addError(i18nc("@info", "The panels could not be changed: %1", result));
        return false;
    }
    qCDebug(KCM_PLASMAFUSION) << "panels:" << result;
    return true;
}

QString PlasmaFusionKcm::topBarScriptPath() const
{
    return layoutScriptPath(u"ensure-topbars.js"_s);
}

QString PlasmaFusionKcm::layoutScriptPath(const QString &name) const
{
    // The layout part's shared scripts, installed with both Global Themes.
    for (const QString &theme : {s_darkLookAndFeel, s_lightLookAndFeel}) {
        const QString path = QStandardPaths::locate(QStandardPaths::GenericDataLocation, u"plasma/look-and-feel/%1/contents/layouts/%2"_s.arg(theme, name));
        if (!path.isEmpty()) {
            return path;
        }
    }
    return {};
}

// Decision 8: a top bar (app name, menu, clock) on every screen. The choice is kept in
// plasmafusionrc [TopBar] EveryScreen, which ensure-topbars.js (also run by KWin when a screen
// is connected) reads.
bool PlasmaFusionKcm::applyEveryScreen(bool on)
{
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    KConfigGroup(fusion, u"TopBar"_s).writeEntry("EveryScreen", on, KConfig::Notify);
    fusion->sync();

    bool ok = false;
    if (!on) {
        const QString result = evaluateShellScript(s_removeExtraTopBarsScript, &ok);
        if (!ok) {
            addError(i18nc("@info", "The top bars could not be changed: %1", result));
            return false;
        }
        qCDebug(KCM_PLASMAFUSION) << "top bars removed:" << result;
        return true;
    }
    const QString path = topBarScriptPath();
    if (path.isEmpty()) {
        // Nothing to run yet; the choice is stored for the layout.
        return true;
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        addError(i18nc("@info", "%1 could not be read.", path));
        return false;
    }
    const QString result = evaluateShellScript(QString::fromUtf8(file.readAll()), &ok);
    if (!ok) {
        addError(i18nc("@info", "The top bars could not be added: %1", result));
        return false;
    }
    // New bars take the glass level and the top-bar opacity of the page, and the power tier.
    const bool panels = applyPanels(m_current.glass, m_current.solidTopBar, !m_powerCritical);
    reapplyPowerTier();
    return panels;
}

// plasmafusionrc [Dock] EveryScreen, which ensure-topbars.js (also run by KWin when a screen is
// added and at login) reads: on, it adds the docks now; off, the other docks go.
bool PlasmaFusionKcm::applyEveryDock(bool on)
{
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    KConfigGroup(fusion, u"Dock"_s).writeEntry("EveryScreen", on, KConfig::Notify);
    fusion->sync();

    bool ok = false;
    if (!on) {
        const QString result = evaluateShellScript(s_removeExtraDocksScript, &ok);
        if (!ok) {
            // The docks are still there: the choice stays on, so the page shows it on again and
            // Apply, the next login or a new screen goes on from there.
            KConfigGroup(fusion, u"Dock"_s).writeEntry("EveryScreen", true, KConfig::Notify);
            fusion->sync();
            addError(i18nc("@info", "The docks could not be changed: %1", result));
            return false;
        }
        qCDebug(KCM_PLASMAFUSION) << "docks removed:" << result;
        return true;
    }
    bool ran = false;
    if (!runDockScript(&ran)) {
        return false;
    }
    if (!ran) {
        // Nothing to run yet; the choice is stored for the next login.
        return true;
    }
    // New docks take the glass level and the power tier, as new top bars do.
    const bool panels = applyPanels(m_current.glass, m_current.solidTopBar, !m_powerCritical);
    reapplyPowerTier();
    return panels;
}

// Runs ensure-topbars.js, which gives every screen without one a dock while [Dock] EveryScreen is
// true. False, with the error shown, when the script cannot be read or fails, or says it could not
// make a dock; *ran is false when there is none to run (the Global Theme is not installed).
bool PlasmaFusionKcm::runDockScript(bool *ran)
{
    *ran = false;
    const QString path = topBarScriptPath();
    if (path.isEmpty()) {
        return true;
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        addError(i18nc("@info", "%1 could not be read.", path));
        return false;
    }
    bool ok = false;
    const QString result = evaluateShellScript(QString::fromUtf8(file.readAll()), &ok);
    if (!ok) {
        addError(i18nc("@info", "The docks could not be added: %1", result));
        return false;
    }
    *ran = true;
    // The shell had not put the docks on their screens yet ("docks: skipped, ..."): nothing could
    // be copied.
    const qsizetype skipped = result.indexOf(u"docks: skipped"_s);
    if (skipped >= 0) {
        addError(i18nc("@info %1 the script's reason", "The docks could not be added yet: %1", result.mid(skipped + 15).trimmed()));
        return false;
    }
    // The script ran, but the shell could not make some docks ("docks: ..., not made N"): those
    // screens have none.
    const QRegularExpressionMatch notMade = QRegularExpression(u"not made (\\d+)"_s).match(result);
    if (notMade.hasMatch()) {
        addError(i18np("The dock of one screen could not be made.", "The docks of %1 screens could not be made.", notMade.captured(1).toInt()));
        return false;
    }
    return true;
}

bool PlasmaFusionKcm::applyDesktop(const State &before, const State &after)
{
    const QString icons = after.desktopIcons == before.desktopIcons ? u"null"_s : after.desktopIcons ? u"true"_s : u"false"_s;
    const QString size = after.iconSize == before.iconSize ? u"null"_s : QString::number(after.iconSize);
    bool ok = false;
    const QString result = evaluateShellScript(s_desktopScript.arg(icons, size, jsString(s_hideAllPattern)), &ok);
    if (!ok || result.toInt() < 1) {
        addError(i18nc("@info", "The desktop could not be changed: %1", ok ? i18nc("@info", "the desktop does not show icons") : result));
        return false;
    }
    return true;
}

// ---------- Restore my previous desktop ----------

void PlasmaFusionKcm::restorePreviousDesktop()
{
    if (m_busy || !m_previousDesktopAvailable) {
        return;
    }
    setBusy(true);
    setErrorText(QString());
    setInfoText(QString());
    // Let the page show that it is busy before the (synchronous) apply.
    QTimer::singleShot(50, this, [this] {
        // As the Global Theme page applies a theme (no layout change); it also turns automatic
        // light/dark switching off. The login check switches the Plasma Fusion lock screen,
        // title bars and KWin scripts off at the next login while another theme is chosen.
        const bool ok = runTool(u"plasma-apply-lookandfeel"_s, {u"--apply"_s, s_previousLookAndFeel});
        const QString error = m_errorText;
        load();
        setErrorText(error);
        if (ok) {
            setInfoText(i18nc("@info",
                              "Your previous desktop look is applied. Plasma Fusion's lock screen, title bars and window tools switch off at "
                              "your next login. Choose Light or Dark above to come back."));
        }
        setBusy(false);
    });
}

// ---------- Reset Fusion layout ----------

QJsonObject PlasmaFusionKcm::widgetShortcuts(bool *ok)
{
    const QString result = evaluateShellScript(s_widgetsScript, ok);
    if (!*ok) {
        return {};
    }
    return QJsonDocument::fromJson(result.toUtf8()).object();
}

void PlasmaFusionKcm::resetLayout()
{
    if (m_busy || !m_shellRunning) {
        return;
    }
    setBusy(true);
    setErrorText(QString());
    setInfoText(QString());

    // The global shortcuts of the widgets now: the rebuilt layout has new widgets, and the old
    // ones keep their keys in kglobalaccel (the shell drops them without releasing them).
    bool ok = false;
    const QJsonObject before = widgetShortcuts(&ok);
    if (!ok) {
        addError(i18nc("@info", "The Plasma desktop did not answer."));
        setBusy(false);
        return;
    }

    // The layout of the Plasma Fusion Global Theme in use (both run the same layout script).
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(u"kdeglobals"_s);
    globals->reparseConfiguration();
    const QString lookAndFeel = KConfigGroup(globals, u"KDE"_s).readEntry("LookAndFeelPackage", QString());
    const QString package = lookAndFeel == s_lightLookAndFeel ? s_lightLookAndFeel : s_darkLookAndFeel;

    QDBusMessage message = QDBusMessage::createMethodCall(u"org.kde.plasmashell"_s,
                                                          u"/PlasmaShell"_s,
                                                          u"org.kde.PlasmaShell"_s,
                                                          u"loadLookAndFeelDefaultLayout"_s);
    message << package;
    const QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(message, 30000);
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, before](QDBusPendingCallWatcher *watcher) {
        const QDBusPendingReply<> reply = *watcher;
        watcher->deleteLater();
        if (reply.isError()) {
            addError(i18nc("@info", "The layout could not be reset: %1", reply.error().message()));
            setBusy(false);
            return;
        }
        // The shell rebuilds on its next event-loop pass; wait until the new widgets exist.
        QTimer::singleShot(500, this, [this, before] {
            pollResetLayout(before, 0);
        });
    });
}

void PlasmaFusionKcm::pollResetLayout(const QJsonObject &before, int attempt)
{
    int oldMax = 0;
    for (const QJsonValue &id : before.value(u"ids"_s).toArray()) {
        oldMax = std::max(oldMax, id.toInt());
    }
    const QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(shellScriptMessage(s_widgetsScript), s_shellTimeout);
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, before, attempt, oldMax](QDBusPendingCallWatcher *watcher) {
        const QDBusPendingReply<QString> reply = *watcher;
        watcher->deleteLater();
        bool done = false;
        if (!reply.isError()) {
            const QJsonObject now = QJsonDocument::fromJson(lastLine(reply.value()).toUtf8()).object();
            const QJsonArray ids = now.value(u"ids"_s).toArray();
            // New widgets always get new ids (libplasma counts up), so the rebuild is complete
            // when panels exist and no old id is left.
            done = now.value(u"panels"_s).toInt() > 0 && !ids.isEmpty();
            for (const QJsonValue &id : ids) {
                done = done && id.toInt() > oldMax;
            }
        }
        if (done) {
            // Give the new widgets a moment to finish starting before their shortcuts are set.
            QTimer::singleShot(1000, this, [this, before] {
                finishResetLayout(before, false, i18nc("@info", "The Plasma Fusion layout is back."));
            });
        } else if (attempt < 40) {
            QTimer::singleShot(500, this, [this, before, attempt] {
                pollResetLayout(before, attempt + 1);
            });
        } else {
            addError(i18nc("@info", "The Plasma desktop did not finish rebuilding the layout."));
            setBusy(false);
            requestShellState();
        }
    });
}

// Gives widget `widgetId` the global shortcut `key`. A key still held by a widget of the old
// layout (an "activate widget N" entry whose widget is gone; the new layout's ids are `newMin` and
// up) is released first, as tools/device/fusion-config.sh does; a key another live action uses is
// left alone. Returns an empty string on success, otherwise the reason.
QString PlasmaFusionKcm::giveWidgetShortcut(int widgetId, const QString &key, const QList<int> &liveWidgetIds, int newMin)
{
    const QKeySequence sequence = QKeySequence::fromString(key, QKeySequence::PortableText);
    if (sequence.isEmpty()) {
        return i18nc("@info", "not a valid key");
    }
    static const QString prefix = u"activate widget "_s;
    const QString ownAction = prefix + QString::number(widgetId);
    QDBusConnection bus = QDBusConnection::sessionBus();
    for (int attempt = 0; attempt < 5; ++attempt) {
        QDBusMessage query = kglobalaccel(u"actionList"_s);
        query << QVariant::fromValue(keyArgument(sequence));
        const QDBusMessage reply = bus.call(query, QDBus::Block, s_dbusTimeout);
        if (reply.type() != QDBusMessage::ReplyMessage) {
            return reply.errorMessage();
        }
        const QStringList holder = reply.arguments().value(0).toStringList();
        if (holder.size() < 2) {
            break;
        }
        if (holder.at(0) == u"plasmashell" && holder.at(1) == ownAction) {
            return {};
        }
        if (holder.at(0) == u"plasmashell" && holder.at(1).startsWith(prefix)) {
            bool isNumber = false;
            const int other = holder.at(1).mid(prefix.size()).toInt(&isNumber);
            // Widgets of the old layout have lower ids than every widget of the new one.
            if (isNumber && !liveWidgetIds.contains(other) && other < newMin) {
                QDBusMessage release = kglobalaccel(u"unregister"_s);
                release << holder.at(0) << holder.at(1);
                bus.call(release, QDBus::Block, s_dbusTimeout);
                qCInfo(KCM_PLASMAFUSION) << "released" << key << "from the removed widget" << other;
                continue;
            }
        }
        return i18nc("@info %1 program, %2 action", "used by %1: %2", holder.value(2, holder.at(0)), holder.value(3, holder.at(1)));
    }
    QDBusMessage available = kglobalaccel(u"globalShortcutAvailable"_s);
    available << QVariant::fromValue(keyArgument(sequence)) << u"plasmashell"_s;
    const QDBusMessage free = bus.call(available, QDBus::Block, s_dbusTimeout);
    if (free.type() == QDBusMessage::ReplyMessage && !free.arguments().value(0).toBool()) {
        return i18nc("@info", "in use");
    }
    bool ok = false;
    const QString result = evaluateShellScript(s_setShortcutScript.arg(QString::number(widgetId), jsString(key)), &ok);
    if (!ok) {
        return result;
    }
    const QJsonObject set = QJsonDocument::fromJson(result.toUtf8()).object();
    const QKeySequence now = QKeySequence::fromString(set.value(u"key"_s).toString(), QKeySequence::PortableText);
    if (!set.value(u"found"_s).toBool() || now != sequence) {
        return i18nc("@info", "not accepted");
    }
    return {};
}

void PlasmaFusionKcm::finishResetLayout(const QJsonObject &before, bool imported, const QString &outcome)
{
    bool ok = false;
    const QJsonObject now = widgetShortcuts(&ok);
    if (!ok) {
        addError(i18nc("@info", "The Plasma desktop did not answer."));
        setBusy(false);
        return;
    }
    // New containments and widgets always get new ids (libplasma counts up): the rebuilt panels'
    // are above every id there was (an import keeps the desktop and its widgets).
    int oldMax = 0;
    for (const QJsonValue &id : before.value(u"ids"_s).toArray()) {
        oldMax = std::max(oldMax, id.toInt());
    }
    QList<int> live;
    int newMin = std::numeric_limits<int>::max();
    for (const QJsonValue &id : now.value(u"ids"_s).toArray()) {
        live << id.toInt();
        if (id.toInt() > oldMax) {
            newMin = std::min(newMin, id.toInt());
        }
    }

    QStringList given;
    QStringList failed;
    const auto give = [&](int id, const QString &type, const QString &key) {
        const QString problem = giveWidgetShortcut(id, key, live, newMin);
        if (problem.isEmpty()) {
            given << i18nc("@item %1 key, %2 widget", "%1 %2", QKeySequence::fromString(key).toString(QKeySequence::NativeText), widgetName(type));
        } else {
            failed << i18nc("@item %1 key, %2 widget, %3 reason", "%1 for %2 (%3)", key, widgetName(type), problem);
        }
    };
    if (imported) {
        // Widget by widget, as the file has them (two widgets of one type keep their own keys); a
        // widget the file gives no key gets none.
        for (const QJsonValue &value : before.value(u"assign"_s).toArray()) {
            const QJsonObject widget = value.toObject();
            give(widget.value(u"id"_s).toInt(), widget.value(u"type"_s).toString(), widget.value(u"key"_s).toString());
        }
    } else {
        // The key each widget type had before (the first widget of the type with a shortcut).
        QHash<QString, QString> keyByType;
        for (const QJsonValue &value : before.value(u"widgets"_s).toArray()) {
            const QJsonObject widget = value.toObject();
            const QString type = widget.value(u"type"_s).toString();
            const QString key = widget.value(u"key"_s).toString();
            if (!key.isEmpty() && !keyByType.contains(type)) {
                keyByType.insert(type, key);
            }
        }
        for (const DefaultShortcut &shortcut : s_defaultShortcuts) {
            if (!keyByType.contains(shortcut.plugin)) {
                keyByType.insert(shortcut.plugin, shortcut.key);
            }
        }
        QSet<QString> done;
        for (const QJsonValue &value : now.value(u"widgets"_s).toArray()) {
            const QJsonObject widget = value.toObject();
            const QString type = widget.value(u"type"_s).toString();
            if (done.contains(type) || !keyByType.contains(type)) {
                continue;
            }
            done.insert(type);
            if (!widget.value(u"key"_s).toString().isEmpty()) {
                continue; // the layout gave it one already
            }
            give(widget.value(u"id"_s).toInt(), type, keyByType.value(type));
        }
    }

    // The glass level and the top bars follow plasmafusionrc, which a layout reset does not touch.
    if (m_saved.glass != GlassFull || !m_saved.solidTopBar) {
        applyPanels(m_saved.glass, m_saved.solidTopBar, m_saved.glass != GlassFull && !m_powerCritical);
    }
    if (!m_saved.everyScreen) {
        evaluateShellScript(s_removeExtraTopBarsScript, &ok);
    }
    // The layout makes one dock; with a dock on every screen the others come back (they copy the
    // main dock's look, set above). When they cannot, the page says so: the switch is on but the
    // other screens have no dock until it is set again. A settings file has the top bars of the
    // screens its computer had; ensure-topbars.js gives the other screens theirs too.
    if (m_saved.everyDock || (imported && m_saved.everyScreen)) {
        bool ran = false;
        if (runDockScript(&ran) && !ran && m_saved.everyDock) {
            addError(i18nc("@info", "The docks of the other screens could not be added back: the Global Theme's ensure-topbars.js is not installed."));
        }
    }
    // The power service applies its tier to the new widgets when it restarts.
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    const QString tier = KConfigGroup(fusion, u"Power"_s).readEntry("Tier", QString());
    if (!tier.isEmpty() && tier.compare(u"full"_s, Qt::CaseInsensitive) != 0) {
        QProcess::startDetached(u"systemctl"_s, {u"--user"_s, u"try-restart"_s, u"plasma-fusion-powerfx.service"_s});
    }

    if (!failed.isEmpty()) {
        addError(i18nc("@info %1 list of shortcuts", "Some widget shortcuts could not be set: %1", failed.join(u", "_s)));
    }
    setInfoText(given.isEmpty() ? outcome : outcome + u' ' + i18nc("@info %1 list of shortcuts", "Shortcuts: %1.", given.join(u", "_s)));
    setBusy(false);
    requestShellState();
}
