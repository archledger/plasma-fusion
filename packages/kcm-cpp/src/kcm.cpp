/*
    Plasma Fusion settings module: the Appearance page of the Plasma Fusion design.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kcm.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KPluginFactory>
#include <KPluginMetaData>
#include <KSharedConfig>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QProcess>
#include <QStandardPaths>
#include <QThread>

using namespace Qt::StringLiterals;

K_PLUGIN_CLASS_WITH_JSON(PlasmaFusionKcm, "kcm_plasmafusion.json")

Q_LOGGING_CATEGORY(KCM_PLASMAFUSION, "org.plasmafusion.kcm", QtInfoMsg)

namespace
{
const QString s_darkLookAndFeel = u"org.plasmafusion.dark.desktop"_s;
const QString s_lightLookAndFeel = u"org.plasmafusion.light.desktop"_s;

// The Plasma Fusion window decoration (KDecoration3 plugin) and its options file.
const QString s_decorationNamespace = u"org.kde.kdecoration3"_s;
const QString s_decorationId = u"org.plasmafusion.decoration"_s;
const QString s_decorationConfig = u"plasmafusionrc"_s;
const QString s_decorationConfigGroup = u"Decoration"_s;
// Fallback without it: the Aurorae themes of the phase 1 decoration part.
const QString s_auroraeLibrary = u"org.kde.kwin.aurorae.v2"_s;
const QString s_auroraeThemePrefix = u"__aurorae__svg__"_s;
const QString s_kwinDecorationGroup = u"org.kde.kdecoration2"_s;

// KWin ElectricBorder values: the top-left corner, and no screen edge.
constexpr int s_hotCornerOn = 7;
constexpr int s_hotCornerOff = 9;

constexpr int s_dbusTimeout = 5000;
constexpr int s_toolTimeout = 60000;

const QStringList s_buttonStyleNames = {u"RightGlyphs"_s, u"LeftCircles"_s, u"ShowOnHover"_s};

int buttonStyleFromName(const QString &name)
{
    return s_buttonStyleNames.indexOf(name);
}

// Reads the shell state in one call: the dock's magnify key and whether the top bar (the panel
// holding org.plasmafusion.appname) shows the global menu.
const QString s_readShellScript = uR"JS(
var state = { docks: 0, magnify: true, topBars: 0, menu: false };
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var docks = ps[i].widgets("org.plasmafusion.dock");
    for (var j = 0; j < docks.length; ++j) {
        docks[j].currentConfigGroup = ["General"];
        if (state.docks === 0) {
            var value = docks[j].readConfig("magnify", true);
            state.magnify = !(value === false || value === "false");
        }
        ++state.docks;
    }
    if (ps[i].widgets("org.plasmafusion.appname").length > 0) {
        if (state.topBars === 0) {
            state.menu = ps[i].widgets("org.kde.plasma.appmenu").length > 0;
        }
        ++state.topBars;
    }
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

QDBusMessage shellScriptMessage(const QString &script)
{
    QDBusMessage message =
        QDBusMessage::createMethodCall(u"org.kde.plasmashell"_s, u"/PlasmaShell"_s, u"org.kde.PlasmaShell"_s, u"evaluateScript"_s);
    message << script;
    return message;
}

// evaluateScript returns everything the script printed; the result is the last line.
QString lastLine(const QString &output)
{
    const QStringList lines = output.trimmed().split(u'\n', Qt::SkipEmptyParts);
    return lines.isEmpty() ? QString() : lines.constLast().trimmed();
}

QString expectedAuroraeTheme(bool light, int buttonStyle)
{
    QString theme = light ? u"PlasmaFusionLight"_s : u"PlasmaFusionDark"_s;
    if (buttonStyle == PlasmaFusionKcm::LeftCircles) {
        theme += u"-Left"_s;
    }
    return theme;
}
} // namespace

bool PlasmaFusionKcm::State::sameAccent(const State &other) const
{
    if (accentMode != other.accentMode) {
        return false;
    }
    if (accentMode == CustomAccent) {
        return accentColor.rgb() == other.accentColor.rgb();
    }
    return true;
}

bool PlasmaFusionKcm::State::operator==(const State &other) const
{
    return style == other.style && sameAccent(other) && buttonStyle == other.buttonStyle && fusionDecoration == other.fusionDecoration
        && magnify == other.magnify && globalMenu == other.globalMenu && hotCorner == other.hotCorner;
}

PlasmaFusionKcm::PlasmaFusionKcm(QObject *parent, const KPluginMetaData &metaData)
    : KQuickManagedConfigModule(parent, metaData)
{
    setButtons(Apply | Default);

    // Changes made elsewhere (the quick-settings Dark style tile, the Colors page, Plasma's
    // automatic light/dark switching) show up here while nothing is pending.
    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(400);
    connect(&m_reloadTimer, &QTimer::timeout, this, [this] {
        if (m_saving || isSaveNeeded()) {
            return;
        }
        State state = m_current;
        loadConfigState(state);
        if (reapplyingDecoration()) {
            // The Global Theme Plasma just switched to has replaced the window decoration; the
            // choice is put back shortly (onConfigChanged), so keep showing it.
            state.buttonStyle = m_saved.buttonStyle;
            state.fusionDecoration = m_saved.fusionDecoration;
        }
        m_current = state;
        m_saved.style = state.style;
        m_saved.accentMode = state.accentMode;
        m_saved.accentColor = state.accentColor;
        m_saved.buttonStyle = state.buttonStyle;
        m_saved.fusionDecoration = state.fusionDecoration;
        m_saved.hotCorner = state.hotCorner;
        if (state.accentMode == WallpaperAccent && state.accentColor.isValid()) {
            // Plasma stores the colour it took from the (possibly new) wallpaper.
            m_wallpaperColor = state.accentColor;
            Q_EMIT wallpaperColorChanged();
        }
        emitAll();
        settingsChanged();
    });
    m_globalsWatcher = KConfigWatcher::create(KSharedConfig::openConfig(u"kdeglobals"_s));
    connect(m_globalsWatcher.data(), &KConfigWatcher::configChanged, this, &PlasmaFusionKcm::onConfigChanged);
    m_kwinWatcher = KConfigWatcher::create(KSharedConfig::openConfig(u"kwinrc"_s));
    connect(m_kwinWatcher.data(), &KConfigWatcher::configChanged, this, &PlasmaFusionKcm::onConfigChanged);

    // The dock and top-bar switches come from the Plasma shell. When it (re)starts while the page
    // is open, they are read again a moment after it takes its bus name (its panels load after).
    m_shellRetryTimer.setSingleShot(true);
    m_shellRetryTimer.setInterval(3000);
    connect(&m_shellRetryTimer, &QTimer::timeout, this, &PlasmaFusionKcm::requestShellState);
    m_shellWatcher = new QDBusServiceWatcher(u"org.kde.plasmashell"_s,
                                             QDBusConnection::sessionBus(),
                                             QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration,
                                             this);
    connect(m_shellWatcher, &QDBusServiceWatcher::serviceRegistered, this, [this] {
        m_shellRetryTimer.start();
    });
    connect(m_shellWatcher, &QDBusServiceWatcher::serviceUnregistered, this, [this] {
        m_shellRetryTimer.stop();
        ++m_shellRequest; // an answer still on its way from the old shell no longer counts
        m_shellLoading = false;
        m_shellRunning = false;
        m_dockAvailable = false;
        m_topBarAvailable = false;
        Q_EMIT shellStateChanged();
        settingsChanged();
    });
}

PlasmaFusionKcm::~PlasmaFusionKcm() = default;

int PlasmaFusionKcm::style() const
{
    return m_current.style;
}

void PlasmaFusionKcm::setStyle(int style)
{
    if (style < LightStyle || style > FollowSunset || style == m_current.style) {
        return;
    }
    m_current.style = style;
    Q_EMIT styleChanged();
    settingsChanged();
}

int PlasmaFusionKcm::accentMode() const
{
    return m_current.accentMode;
}

QColor PlasmaFusionKcm::accentColor() const
{
    if (m_current.accentMode == WallpaperAccent && m_wallpaperColor.isValid()) {
        return m_wallpaperColor;
    }
    return m_current.accentColor;
}

QColor PlasmaFusionKcm::wallpaperColor() const
{
    return m_wallpaperColor;
}

int PlasmaFusionKcm::buttonStyle() const
{
    return m_current.buttonStyle;
}

void PlasmaFusionKcm::setButtonStyle(int style)
{
    if (style < RightGlyphs || style > ShowOnHover || style == m_current.buttonStyle) {
        return;
    }
    m_current.buttonStyle = style;
    Q_EMIT buttonStyleChanged();
    settingsChanged();
}

bool PlasmaFusionKcm::magnify() const
{
    return m_current.magnify;
}

void PlasmaFusionKcm::setMagnify(bool magnify)
{
    if (magnify == m_current.magnify) {
        return;
    }
    m_current.magnify = magnify;
    Q_EMIT magnifyChanged();
    settingsChanged();
}

bool PlasmaFusionKcm::globalMenu() const
{
    return m_current.globalMenu;
}

void PlasmaFusionKcm::setGlobalMenu(bool globalMenu)
{
    if (globalMenu == m_current.globalMenu) {
        return;
    }
    m_current.globalMenu = globalMenu;
    Q_EMIT globalMenuChanged();
    settingsChanged();
}

bool PlasmaFusionKcm::hotCorner() const
{
    return m_current.hotCorner;
}

void PlasmaFusionKcm::setHotCorner(bool hotCorner)
{
    if (hotCorner == m_current.hotCorner) {
        return;
    }
    m_current.hotCorner = hotCorner;
    Q_EMIT hotCornerChanged();
    settingsChanged();
}

bool PlasmaFusionKcm::shellLoading() const
{
    return m_shellLoading;
}

bool PlasmaFusionKcm::shellRunning() const
{
    return m_shellRunning;
}

bool PlasmaFusionKcm::dockAvailable() const
{
    return m_dockAvailable;
}

bool PlasmaFusionKcm::topBarAvailable() const
{
    return m_topBarAvailable;
}

bool PlasmaFusionKcm::decorationInstalled() const
{
    return m_decorationInstalled;
}

bool PlasmaFusionKcm::fusionDecoration() const
{
    return m_current.fusionDecoration;
}

void PlasmaFusionKcm::useFusionDecoration()
{
    if (!m_decorationInstalled || m_current.fusionDecoration) {
        return;
    }
    m_current.fusionDecoration = true;
    Q_EMIT buttonStyleChanged();
    settingsChanged();
}

QString PlasmaFusionKcm::errorText() const
{
    return m_errorText;
}

void PlasmaFusionKcm::setSchemeAccent()
{
    if (m_current.accentMode == SchemeAccent) {
        return;
    }
    m_current.accentMode = SchemeAccent;
    m_current.accentColor = QColor();
    Q_EMIT accentChanged();
    settingsChanged();
}

void PlasmaFusionKcm::setCustomAccent(const QColor &color)
{
    if (!color.isValid() || (m_current.accentMode == CustomAccent && m_current.accentColor.rgb() == color.rgb())) {
        return;
    }
    m_current.accentMode = CustomAccent;
    m_current.accentColor = color.toRgb();
    m_current.accentColor.setAlpha(255);
    Q_EMIT accentChanged();
    settingsChanged();
}

void PlasmaFusionKcm::setWallpaperAccent()
{
    if (m_current.accentMode != WallpaperAccent) {
        m_current.accentMode = WallpaperAccent;
        m_current.accentColor = m_wallpaperColor;
        Q_EMIT accentChanged();
        settingsChanged();
    }
    if (!m_wallpaperColor.isValid()) {
        requestWallpaperColor();
    }
}

void PlasmaFusionKcm::emitAll()
{
    Q_EMIT styleChanged();
    Q_EMIT accentChanged();
    Q_EMIT buttonStyleChanged();
    Q_EMIT magnifyChanged();
    Q_EMIT globalMenuChanged();
    Q_EMIT hotCornerChanged();
}

void PlasmaFusionKcm::setErrorText(const QString &text)
{
    if (text == m_errorText) {
        return;
    }
    m_errorText = text;
    Q_EMIT errorTextChanged();
}

void PlasmaFusionKcm::addError(const QString &text)
{
    qCWarning(KCM_PLASMAFUSION) << text;
    setErrorText(m_errorText.isEmpty() ? text : m_errorText + u'\n' + text);
}

void PlasmaFusionKcm::updateDecorationInstalled()
{
    const bool installed = KPluginMetaData::findPluginById(s_decorationNamespace, s_decorationId).isValid();
    if (installed != m_decorationInstalled) {
        m_decorationInstalled = installed;
        Q_EMIT decorationInstalledChanged();
    }
}

bool PlasmaFusionKcm::currentVariantIsLight() const
{
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(u"kdeglobals"_s);
    globals->reparseConfiguration();
    const QString lookAndFeel = KConfigGroup(globals, u"KDE"_s).readEntry("LookAndFeelPackage", QString());
    if (lookAndFeel == s_lightLookAndFeel) {
        return true;
    }
    if (lookAndFeel == s_darkLookAndFeel) {
        return false;
    }
    const QColor window = KConfigGroup(globals, u"Colors:Window"_s).readEntry("BackgroundNormal", QColor());
    return window.isValid() && qGray(window.rgb()) > 128;
}

void PlasmaFusionKcm::loadConfigState(State &state) const
{
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(u"kdeglobals"_s);
    globals->reparseConfiguration();

    // Style
    const KConfigGroup kde(globals, u"KDE"_s);
    const QString lookAndFeel = kde.readEntry("LookAndFeelPackage", QString());
    if (kde.readEntry("AutomaticLookAndFeel", false)) {
        const bool fusionPair = kde.readEntry("DefaultLightLookAndFeel", QString()) == s_lightLookAndFeel
            && kde.readEntry("DefaultDarkLookAndFeel", QString()) == s_darkLookAndFeel;
        state.style = fusionPair ? FollowSunset : OtherStyle;
    } else if (lookAndFeel == s_lightLookAndFeel) {
        state.style = LightStyle;
    } else if (lookAndFeel == s_darkLookAndFeel) {
        state.style = DarkStyle;
    } else {
        state.style = OtherStyle;
    }

    // Accent colour, as the Colors page reads it.
    const KConfigGroup general(globals, u"General"_s);
    const QColor accent = general.readEntry("AccentColor", QColor());
    if (general.readEntry("accentColorFromWallpaper", false)) {
        state.accentMode = WallpaperAccent;
        state.accentColor = accent;
    } else if (general.hasKey("AccentColor") && accent.isValid() && accent.alpha() > 0) {
        state.accentMode = CustomAccent;
        state.accentColor = accent;
    } else {
        state.accentMode = SchemeAccent;
        state.accentColor = QColor();
    }

    // Window buttons
    KSharedConfig::Ptr kwin = KSharedConfig::openConfig(u"kwinrc"_s);
    kwin->reparseConfiguration();
    const KConfigGroup decoration(kwin, s_kwinDecorationGroup);
    const QString library = decoration.readEntry("library", QString());
    const QString theme = decoration.readEntry("theme", QString());
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_decorationConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    const int chosen = buttonStyleFromName(KConfigGroup(fusion, s_decorationConfigGroup).readEntry("ButtonStyle", QString()));
    state.fusionDecoration = library == s_decorationId;
    if (library == s_decorationId) {
        state.buttonStyle = chosen >= 0 ? chosen : RightGlyphs;
    } else if (library.startsWith(u"org.kde.kwin.aurorae"_s) && theme.startsWith(s_auroraeThemePrefix + u"PlasmaFusion"_s)) {
        // The Aurorae fallback has no show-on-hover mode; the choice is kept in plasmafusionrc.
        state.buttonStyle = theme.endsWith(u"-Left"_s) ? LeftCircles : (chosen == ShowOnHover ? ShowOnHover : RightGlyphs);
    } else {
        state.buttonStyle = chosen >= 0 ? chosen : RightGlyphs;
    }

    // Hot corner (KWin's default when the key is missing is the top-left corner).
    const QList<int> borders = KConfigGroup(kwin, u"Effect-overview"_s).readEntry("BorderActivate", QList<int>{s_hotCornerOn});
    state.hotCorner = borders.contains(s_hotCornerOn);
}

void PlasmaFusionKcm::load()
{
    KQuickManagedConfigModule::load();
    setErrorText(QString());
    updateDecorationInstalled();

    State state = m_saved;
    loadConfigState(state);
    m_current = state;
    m_saved = state;
    m_wallpaperColor = state.accentMode == WallpaperAccent ? state.accentColor : QColor();
    Q_EMIT wallpaperColorChanged();
    emitAll();
    settingsChanged();
    requestShellState();
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
    if (reply.isError()) {
        qCWarning(KCM_PLASMAFUSION) << "Could not read the Plasma shell layout:" << reply.error().message();
    } else {
        const QJsonObject state = QJsonDocument::fromJson(lastLine(reply.value()).toUtf8()).object();
        m_dockAvailable = state.value(u"docks"_s).toInt() > 0;
        m_topBarAvailable = state.value(u"topBars"_s).toInt() > 0;
        if (m_dockAvailable) {
            m_current.magnify = m_saved.magnify = state.value(u"magnify"_s).toBool(true);
        }
        if (m_topBarAvailable) {
            m_current.globalMenu = m_saved.globalMenu = state.value(u"menu"_s).toBool(true);
        }
    }
    Q_EMIT shellStateChanged();
    Q_EMIT magnifyChanged();
    Q_EMIT globalMenuChanged();
    settingsChanged();
}

void PlasmaFusionKcm::requestWallpaperColor()
{
    // Plasma computes the colour from the primary screen's wallpaper; asking for it changes nothing.
    const QDBusMessage message = QDBusMessage::createMethodCall(u"org.kde.plasmashell"_s, u"/PlasmaShell"_s, u"org.kde.PlasmaShell"_s, u"color"_s);
    const QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(message, 10000);
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        const QDBusPendingReply<uint> reply = *watcher;
        watcher->deleteLater();
        if (reply.isError()) {
            qCWarning(KCM_PLASMAFUSION) << "Could not get the wallpaper colour:" << reply.error().message();
            return;
        }
        const QColor color = QColor::fromRgba(reply.value());
        if (!color.isValid() || color.alpha() == 0) {
            return;
        }
        m_wallpaperColor = color;
        Q_EMIT wallpaperColorChanged();
        if (m_current.accentMode == WallpaperAccent) {
            m_current.accentColor = color;
            Q_EMIT accentChanged();
        }
    });
}

bool PlasmaFusionKcm::reapplyingDecoration() const
{
    return m_reapplyDecorationUntil.remainingTime() > 0 && m_saved.style == FollowSunset;
}

void PlasmaFusionKcm::restoreDecorationIfReplaced()
{
    if (m_saving || !reapplyingDecoration()) {
        return;
    }
    updateDecorationInstalled();
    KSharedConfig::Ptr kwin = KSharedConfig::openConfig(u"kwinrc"_s);
    kwin->reparseConfiguration();
    const KConfigGroup decoration(kwin, s_kwinDecorationGroup);
    const QString library = decoration.readEntry("library", QString());
    const QString theme = decoration.readEntry("theme", QString());
    const bool matches = m_decorationInstalled
        ? library == s_decorationId
        : (library == s_auroraeLibrary && theme == s_auroraeThemePrefix + expectedAuroraeTheme(currentVariantIsLight(), m_reapplyButtonStyle));
    if (!matches) {
        qCInfo(KCM_PLASMAFUSION) << "Global Theme switched: applying the window buttons again";
        applyDecoration(m_reapplyButtonStyle);
        reconfigureKWin(false);
    }
}

void PlasmaFusionKcm::onConfigChanged(const KConfigGroup &group, const QByteArrayList &names)
{
    const QString name = group.name();
    if (reapplyingDecoration() && !m_saving) {
        if (name == u"KDE" && names.contains("LookAndFeelPackage")) {
            // Plasma switched the Global Theme on its own (Follow sunset). It stores the new theme
            // first and then applies it, window decoration included, which takes a moment; check
            // a few times and put the chosen window buttons back once they were replaced.
            for (const int delay : {1500, 3000, 6000, 10000}) {
                QTimer::singleShot(delay, this, &PlasmaFusionKcm::restoreDecorationIfReplaced);
            }
        } else if (name == s_kwinDecorationGroup) {
            QTimer::singleShot(600, this, &PlasmaFusionKcm::restoreDecorationIfReplaced);
        }
    }
    if (name == u"KDE" || name == u"General" || name == s_kwinDecorationGroup || name == u"Effect-overview") {
        m_reloadTimer.start();
    }
}

bool PlasmaFusionKcm::isSaveNeeded() const
{
    return !(m_current == m_saved);
}

bool PlasmaFusionKcm::isDefaults() const
{
    const State defaults;
    return m_current.style == defaults.style && m_current.sameAccent(defaults) && m_current.buttonStyle == defaults.buttonStyle
        && m_current.fusionDecoration == m_decorationInstalled && (!m_dockAvailable || m_current.magnify == defaults.magnify) && (!m_topBarAvailable || m_current.globalMenu == defaults.globalMenu)
        && m_current.hotCorner == defaults.hotCorner;
}

void PlasmaFusionKcm::defaults()
{
    KQuickManagedConfigModule::defaults();
    State defaults;
    // With the Plasma Fusion decoration installed, the default is to use it.
    defaults.fusionDecoration = m_decorationInstalled;
    if (!m_dockAvailable) {
        defaults.magnify = m_current.magnify;
    }
    if (!m_topBarAvailable) {
        defaults.globalMenu = m_current.globalMenu;
    }
    m_current = defaults;
    emitAll();
    settingsChanged();
}

void PlasmaFusionKcm::save()
{
    KQuickManagedConfigModule::save();
    m_saving = true;
    setErrorText(QString());
    const State before = m_saved;
    const State after = m_current;

    // 1. Style. A Global Theme brings its own window decoration, so the window buttons are
    //    applied again after it.
    bool decoration = after.buttonStyle != before.buttonStyle || after.fusionDecoration != before.fusionDecoration;
    if (after.style != before.style && after.style != OtherStyle) {
        applyStyle(after.style);
        decoration = true;
    }
    // 2. Accent colour, on top of the colour scheme the style just applied.
    if (!after.sameAccent(before)) {
        applyAccent(after);
    }
    // 3. Window buttons and hot corner (KWin).
    bool reconfigure = false;
    if (decoration) {
        applyDecoration(after.buttonStyle);
        reconfigure = true;
    }
    if (after.hotCorner != before.hotCorner) {
        applyHotCorner(after.hotCorner);
        reconfigure = true;
    }
    if (reconfigure) {
        reconfigureKWin(after.hotCorner != before.hotCorner);
    }
    // 4. Plasma shell.
    if (m_dockAvailable && after.magnify != before.magnify) {
        applyMagnify(after.magnify);
    }
    if (m_topBarAvailable && after.globalMenu != before.globalMenu) {
        applyGlobalMenu(after.globalMenu);
    }

    if (after.style == FollowSunset && before.style != FollowSunset) {
        m_reapplyDecorationUntil = QDeadlineTimer(20000);
        m_reapplyButtonStyle = after.buttonStyle;
    }
    if (decoration) {
        // applyDecoration uses the Plasma Fusion decoration whenever it is installed.
        m_current.fusionDecoration = m_decorationInstalled;
        Q_EMIT buttonStyleChanged();
    }
    m_saved = m_current;
    if (!m_errorText.isEmpty()) {
        // Something could not be applied: show what is set now rather than what was asked for
        // (a failed Global Theme leaves the other style in place, and no configuration change
        // may follow that would reload the page).
        State state = m_current;
        loadConfigState(state);
        m_current = state;
        m_saved = state;
        emitAll();
        requestShellState();
    }
    m_saving = false;
    settingsChanged();
}

bool PlasmaFusionKcm::runTool(const QString &program, const QStringList &arguments)
{
    const QString path = QStandardPaths::findExecutable(program);
    if (path.isEmpty()) {
        addError(i18nc("@info", "%1 was not found.", program));
        return false;
    }
    QProcess process;
    process.setProcessChannelMode(QProcess::MergedChannels);
    process.start(path, arguments);
    if (!process.waitForStarted(s_dbusTimeout) || !process.waitForFinished(s_toolTimeout)) {
        process.kill();
        process.waitForFinished(1000);
        addError(i18nc("@info", "%1 did not finish.", program));
        return false;
    }
    const QString output = QString::fromLocal8Bit(process.readAll()).trimmed();
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        addError(i18nc("@info %1 program, %2 its output", "%1 failed: %2", program, output));
        return false;
    }
    qCDebug(KCM_PLASMAFUSION) << program << arguments << output;
    return true;
}

bool PlasmaFusionKcm::applyStyle(int style)
{
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(u"kdeglobals"_s);
    globals->reparseConfiguration();
    KConfigGroup kde(globals, u"KDE"_s);
    // The light/dark pair Plasma switches between (automatic switching and the Dark style tile).
    kde.writeEntry("DefaultLightLookAndFeel", s_lightLookAndFeel, KConfig::Notify);
    kde.writeEntry("DefaultDarkLookAndFeel", s_darkLookAndFeel, KConfig::Notify);
    if (style == FollowSunset) {
        // Plasma's lookandfeelautoswitcher applies the theme for the time of day right away.
        kde.writeEntry("AutomaticLookAndFeel", true, KConfig::Notify);
        globals->sync();
        return true;
    }
    // Automatic switching off in the same write, so the switcher (which reacts to the pair
    // changing) does not apply a theme of its own meanwhile; plasma-apply-lookandfeel (no
    // --keep-auto) turns it off as well, like choosing a Global Theme does.
    kde.writeEntry("AutomaticLookAndFeel", false, KConfig::Notify);
    globals->sync();
    return runTool(u"plasma-apply-lookandfeel"_s, {u"--apply"_s, style == LightStyle ? s_lightLookAndFeel : s_darkLookAndFeel});
}

bool PlasmaFusionKcm::applyAccent(const State &state)
{
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(u"kdeglobals"_s);
    globals->reparseConfiguration();
    KConfigGroup general(globals, u"General"_s);

    // The Colors page's keys; like its settings object, a value equal to the default is removed.
    QString accentArgument;
    switch (state.accentMode) {
    case CustomAccent:
        general.writeEntry("AccentColor", state.accentColor, KConfig::Notify);
        general.writeEntry("LastUsedCustomAccentColor", state.accentColor, KConfig::Notify);
        general.revertToDefault("accentColorFromWallpaper", KConfig::Notify);
        accentArgument = state.accentColor.name(QColor::HexRgb);
        break;
    case WallpaperAccent: {
        QColor color = m_wallpaperColor;
        if (!color.isValid()) {
            const QDBusMessage message =
                QDBusMessage::createMethodCall(u"org.kde.plasmashell"_s, u"/PlasmaShell"_s, u"org.kde.PlasmaShell"_s, u"color"_s);
            const QDBusMessage reply = QDBusConnection::sessionBus().call(message, QDBus::Block, s_dbusTimeout);
            if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
                color = QColor::fromRgba(reply.arguments().constFirst().toUInt());
            }
        }
        general.writeEntry("accentColorFromWallpaper", true, KConfig::Notify);
        if (color.isValid() && color.alpha() > 0) {
            color.setAlpha(255);
            general.writeEntry("AccentColor", color, KConfig::Notify);
            accentArgument = color.name(QColor::HexRgb);
        }
        // Without a colour yet, Plasma applies it as soon as it has one (accentColorFromWallpaper).
        break;
    }
    case SchemeAccent:
    default:
        general.revertToDefault("AccentColor", KConfig::Notify);
        general.revertToDefault("accentColorFromWallpaper", KConfig::Notify);
        accentArgument = u"transparent"_s; // the colour scheme's own accent
        break;
    }
    globals->sync();
    if (accentArgument.isEmpty()) {
        return true;
    }
    // Writes the colour scheme into kdeglobals again with the accent (as the Colors page does on
    // Apply) and tells running applications.
    return runTool(u"plasma-apply-colorscheme"_s, {u"--accent-color"_s, accentArgument});
}

bool PlasmaFusionKcm::applyDecoration(int buttonStyle)
{
    updateDecorationInstalled();
    const bool left = buttonStyle == LeftCircles;

    KSharedConfig::Ptr kwin = KSharedConfig::openConfig(u"kwinrc"_s);
    kwin->reparseConfiguration();
    KConfigGroup decoration(kwin, s_kwinDecorationGroup);
    if (m_decorationInstalled) {
        decoration.writeEntry("library", s_decorationId, KConfig::Notify);
        decoration.writeEntry("theme", QString(), KConfig::Notify);
    } else {
        const QString theme = expectedAuroraeTheme(currentVariantIsLight(), buttonStyle);
        if (QStandardPaths::locate(QStandardPaths::GenericDataLocation, u"aurorae/themes/%1/metadata.desktop"_s.arg(theme)).isEmpty()) {
            addError(i18nc("@info", "The window decoration theme %1 is not installed.", theme));
            return false;
        }
        decoration.writeEntry("library", s_auroraeLibrary, KConfig::Notify);
        decoration.writeEntry("theme", QString(s_auroraeThemePrefix + theme), KConfig::Notify);
    }
    decoration.writeEntry("NoPlugin", false, KConfig::Notify);
    // Button order. The Aurorae -Left themes need close, minimize, maximize on the left and the
    // spacer on the right; the other themes the Plasma Fusion order (application menu left,
    // minimize, maximize, close right). The Plasma Fusion decoration draws its left circles
    // itself, so there a customised order is kept and only the left-circles order is undone.
    const QString leftButtons = decoration.readEntry("ButtonsOnLeft", QString());
    const QString rightButtons = decoration.readEntry("ButtonsOnRight", QString());
    const bool leftLayoutWritten = leftButtons == u"XIA" && rightButtons == u"_";
    if (!m_decorationInstalled || (!left && leftLayoutWritten)) {
        decoration.writeEntry("ButtonsOnLeft", left ? u"XIA"_s : u"M"_s, KConfig::Notify);
        decoration.writeEntry("ButtonsOnRight", left ? u"_"_s : u"IAX"_s, KConfig::Notify);
    }
    kwin->sync();

    // The decoration reads this when KWin reconfigures.
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_decorationConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    KConfigGroup(fusion, s_decorationConfigGroup).writeEntry("ButtonStyle", s_buttonStyleNames.value(buttonStyle), KConfig::Notify);
    fusion->sync();
    return true;
}

void PlasmaFusionKcm::applyHotCorner(bool on)
{
    KSharedConfig::Ptr kwin = KSharedConfig::openConfig(u"kwinrc"_s);
    kwin->reparseConfiguration();
    KConfigGroup(kwin, u"Effect-overview"_s).writeEntry("BorderActivate", on ? s_hotCornerOn : s_hotCornerOff, KConfig::Notify);
    kwin->sync();
}

void PlasmaFusionKcm::reconfigureKWin(bool overviewEffect)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.asyncCall(QDBusMessage::createMethodCall(u"org.kde.KWin"_s, u"/KWin"_s, u"org.kde.KWin"_s, u"reconfigure"_s));
    if (overviewEffect) {
        QDBusMessage message = QDBusMessage::createMethodCall(u"org.kde.KWin"_s, u"/Effects"_s, u"org.kde.kwin.Effects"_s, u"reconfigureEffect"_s);
        message << u"overview"_s;
        bus.asyncCall(message);
    }
}

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

bool PlasmaFusionKcm::applyMagnify(bool on)
{
    bool ok = false;
    const QString result = evaluateShellScript(s_magnifyScript.arg(on ? u"true"_s : u"false"_s), &ok);
    if (!ok || result.toInt() < 1) {
        addError(i18nc("@info", "The dock setting could not be changed: %1", ok ? i18nc("@info", "no Plasma Fusion dock found") : result));
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

#include "kcm.moc"
