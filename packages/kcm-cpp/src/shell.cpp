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
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeySequence>
#include <QProcess>
#include <QStandardPaths>
#include <QSet>
#include <QThread>

#include <algorithm>
#include <limits>

using namespace Qt::StringLiterals;
using namespace PlasmaFusion;

namespace
{
// Reads the shell state in one call: the dock's keys, the top bar (the panel holding
// org.plasmafusion.appname; the one with quick settings when there are several), the quick
// settings' keyboard policy and the Folder View desktop's filter and icon size.
const QString s_readShellScript = uR"JS(
function bool(v, d) {
    if (v === undefined || v === null || v === "") {
        return d;
    }
    return !(v === false || v === "false");
}
var state = { docks: 0, magnify: true, magnifiedSize: 62, homeIndicator: true,
              topBars: 0, menu: false, topOpacity: "",
              quickSettings: 0, keyboardPolicy: "tablet",
              folders: 0, filterMode: 0, filterPattern: "*", iconSize: 3 };
var mainTopBar = false;
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
    var qs = p.widgets("org.plasmafusion.quicksettings");
    for (var j = 0; j < qs.length; ++j) {
        qs[j].currentConfigGroup = ["General"];
        if (state.quickSettings === 0) {
            state.keyboardPolicy = String(qs[j].readConfig("keyboardPolicy", "tablet"));
        }
        ++state.quickSettings;
    }
    if (p.widgets("org.plasmafusion.appname").length > 0) {
        if (state.topBars === 0 || (!mainTopBar && qs.length > 0)) {
            state.menu = p.widgets("org.kde.plasma.appmenu").length > 0;
            state.topOpacity = String(p.opacity);
            mainTopBar = qs.length > 0;
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
// widget types that have a glass key. Only panels holding Plasma Fusion widgets change.
const QString s_panelsScript = uR"JS(
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
    if (want !== "" && String(p.opacity) !== want) {
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
for (var i = 0; main !== null && i < tops.length; ++i) {
    if (tops[i].id !== main.id && tops[i].screen !== main.screen) {
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

// Shortcuts a layout reset gives when the widget had none before (owner decision 6: Meta+A
// opens quick settings, Meta+Shift+W the pen menu), as tools/device/fusion-config.sh does.
struct DefaultShortcut {
    QString plugin;
    QString key;
};
const QList<DefaultShortcut> s_defaultShortcuts = {
    {u"org.plasmafusion.quicksettings"_s, u"Meta+A"_s},
    {u"org.plasmafusion.pen"_s, u"Meta+Shift+W"_s},
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

QString PlasmaFusionKcm::evaluateShellScript(const QString &script, bool *ok) const
{
    const QDBusMessage reply = QDBusConnection::sessionBus().call(shellScriptMessage(script), QDBus::Block, s_dbusTimeout);
    if (reply.type() != QDBusMessage::ReplyMessage) {
        *ok = false;
        return reply.errorMessage();
    }
    *ok = true;
    return lastLine(reply.arguments().value(0).toString());
}

void PlasmaFusionKcm::requestShellState()
{
    const int request = ++m_shellRequest;
    m_shellLoading = true;
    Q_EMIT shellStateChanged();

    const QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(shellScriptMessage(s_readShellScript), s_dbusTimeout);
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, request](QDBusPendingCallWatcher *watcher) {
        if (request == m_shellRequest) {
            shellStateArrived(watcher);
        }
        watcher->deleteLater();
    });
}

void PlasmaFusionKcm::shellStateArrived(QDBusPendingCallWatcher *watcher)
{
    const QDBusPendingReply<QString> reply = *watcher;
    m_shellLoading = false;
    m_shellRunning = !reply.isError();
    m_dockAvailable = false;
    m_topBarAvailable = false;
    m_quickSettingsAvailable = false;
    m_folderAvailable = false;
    if (reply.isError()) {
        qCWarning(KCM_PLASMAFUSION) << "Could not read the Plasma shell layout:" << reply.error().message();
    } else {
        const QJsonObject state = QJsonDocument::fromJson(lastLine(reply.value()).toUtf8()).object();
        m_dockAvailable = state.value(u"docks"_s).toInt() > 0;
        m_topBarAvailable = state.value(u"topBars"_s).toInt() > 0;
        m_quickSettingsAvailable = state.value(u"quickSettings"_s).toInt() > 0;
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
        if (m_folderAvailable) {
            const bool hidden = state.value(u"filterMode"_s).toInt() == 1 && state.value(u"filterPattern"_s).toString() == s_hideAllPattern;
            take(m_current.desktopIcons, m_saved.desktopIcons, !hidden);
            take(m_current.iconSize, m_saved.iconSize, state.value(u"iconSize"_s).toInt(3));
        }
    }
    Q_EMIT shellStateChanged();
    Q_EMIT magnifyChanged();
    Q_EMIT globalMenuChanged();
    Q_EMIT stateChanged();
    settingsChanged();
}

bool PlasmaFusionKcm::applyMagnify(bool on)
{
    if (m_powerCritical) {
        // The power service keeps the dock still at 10 % battery and restores this value later.
        KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
        fusion->reparseConfiguration();
        KConfigGroup(fusion, u"Power"_s).writeEntry("UserDockMagnify", on, KConfig::Notify);
        fusion->sync();
        return true;
    }
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
    // The layout part's shared script, installed with both Global Themes.
    for (const QString &theme : {s_darkLookAndFeel, s_lightLookAndFeel}) {
        const QString path =
            QStandardPaths::locate(QStandardPaths::GenericDataLocation, u"plasma/look-and-feel/%1/contents/layouts/ensure-topbars.js"_s.arg(theme));
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
    // New bars take the glass level and the top-bar opacity of the page.
    return applyPanels(m_current.glass, m_current.solidTopBar, !m_powerCritical);
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

QJsonObject PlasmaFusionKcm::widgetShortcuts(bool *ok) const
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
    const QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(shellScriptMessage(s_widgetsScript), s_dbusTimeout);
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
                finishResetLayout(before);
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
// layout (an "activate widget N" entry whose widget is gone) is released first, as
// tools/device/fusion-config.sh does; a key another live action uses is left alone. Returns an
// empty string on success, otherwise the reason.
QString PlasmaFusionKcm::giveWidgetShortcut(int widgetId, const QString &key, const QList<int> &liveWidgetIds)
{
    const QKeySequence sequence = QKeySequence::fromString(key, QKeySequence::PortableText);
    if (sequence.isEmpty()) {
        return i18nc("@info", "not a valid key");
    }
    int newMin = std::numeric_limits<int>::max();
    for (const int id : liveWidgetIds) {
        newMin = std::min(newMin, id);
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

void PlasmaFusionKcm::finishResetLayout(const QJsonObject &before)
{
    bool ok = false;
    const QJsonObject now = widgetShortcuts(&ok);
    if (!ok) {
        addError(i18nc("@info", "The Plasma desktop did not answer."));
        setBusy(false);
        return;
    }
    QList<int> live;
    for (const QJsonValue &id : now.value(u"ids"_s).toArray()) {
        live << id.toInt();
    }

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

    QStringList given;
    QStringList failed;
    QSet<QString> done;
    for (const QJsonValue &value : now.value(u"widgets"_s).toArray()) {
        const QJsonObject widget = value.toObject();
        const QString type = widget.value(u"type"_s).toString();
        if (done.contains(type) || !keyByType.contains(type)) {
            continue;
        }
        done.insert(type);
        const QString key = keyByType.value(type);
        if (!widget.value(u"key"_s).toString().isEmpty()) {
            continue; // the layout gave it one already
        }
        const QString problem = giveWidgetShortcut(widget.value(u"id"_s).toInt(), key, live);
        if (problem.isEmpty()) {
            given << i18nc("@item %1 key, %2 widget", "%1 %2", QKeySequence::fromString(key).toString(QKeySequence::NativeText), widgetName(type));
        } else {
            failed << i18nc("@item %1 key, %2 widget, %3 reason", "%1 for %2 (%3)", key, widgetName(type), problem);
        }
    }

    // The glass level and the top bars follow plasmafusionrc, which a layout reset does not touch.
    if (m_saved.glass != GlassFull || !m_saved.solidTopBar) {
        applyPanels(m_saved.glass, m_saved.solidTopBar, m_saved.glass != GlassFull && !m_powerCritical);
    }
    if (!m_saved.everyScreen) {
        evaluateShellScript(s_removeExtraTopBarsScript, &ok);
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
    setInfoText(given.isEmpty() ? i18nc("@info", "The Plasma Fusion layout is back.")
                                : i18nc("@info %1 list of shortcuts", "The Plasma Fusion layout is back. Shortcuts: %1.", given.join(u", "_s)));
    setBusy(false);
    requestShellState();
}
