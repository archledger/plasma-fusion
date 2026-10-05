/*
    Plasma Fusion settings module: the Appearance page of the Plasma Fusion design.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kcm.h"
#include "kcm_p.h"

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
#include <QProcess>
#include <QStandardPaths>

using namespace Qt::StringLiterals;
using namespace PlasmaFusion;

K_PLUGIN_CLASS_WITH_JSON(PlasmaFusionKcm, "kcm_plasmafusion.json")

Q_LOGGING_CATEGORY(KCM_PLASMAFUSION, "org.plasmafusion.kcm", QtInfoMsg)

namespace
{
// The Plasma Fusion window decoration (KDecoration3 plugin) and its options file.
const QString s_decorationNamespace = u"org.kde.kdecoration3"_s;
const QString s_decorationId = u"org.plasmafusion.decoration"_s;
const QString s_decorationConfigGroup = u"Decoration"_s;
// Fallback without it: the Aurorae themes of the phase 1 decoration part.
const QString s_auroraeLibrary = u"org.kde.kwin.aurorae.v2"_s;
const QString s_auroraeThemePrefix = u"__aurorae__svg__"_s;
const QString s_kwinDecorationGroup = u"org.kde.kdecoration2"_s;

// KWin ElectricBorder values: the top-left corner, and no screen edge.
constexpr int s_hotCornerOn = 7;
constexpr int s_hotCornerOff = 9;

const QStringList s_buttonStyleNames = {u"RightGlyphs"_s, u"LeftCircles"_s, u"ShowOnHover"_s};
const QStringList s_glassNames = {u"Full"_s, u"Reduced"_s, u"Solid"_s};

int buttonStyleFromName(const QString &name)
{
    return s_buttonStyleNames.indexOf(name);
}

int glassFromName(const QString &name)
{
    for (int i = 0; i < s_glassNames.size(); ++i) {
        if (s_glassNames.at(i).compare(name, Qt::CaseInsensitive) == 0) {
            return i;
        }
    }
    return PlasmaFusionKcm::GlassFull;
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

QString PlasmaFusion::jsString(const QString &value)
{
    QString out = u"\""_s;
    for (const QChar c : value) {
        switch (c.unicode()) {
        case '"':
            out += u"\\\""_s;
            break;
        case '\\':
            out += u"\\\\"_s;
            break;
        case '\n':
            out += u"\\n"_s;
            break;
        default:
            if (c.unicode() < 0x20) {
                out += u"\\u"_s + QString::number(c.unicode(), 16).rightJustified(4, u'0');
            } else {
                out += c;
            }
        }
    }
    return out + u'"';
}

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
        && magnify == other.magnify && globalMenu == other.globalMenu && hotCorner == other.hotCorner && snapTrigger == other.snapTrigger
        && glass == other.glass && highContrast == other.highContrast && reduceMotion == other.reduceMotion && everyScreen == other.everyScreen
        && dndBehavior == other.dndBehavior && lighterOnCritical == other.lighterOnCritical
        && fileContentIndexing == other.fileContentIndexing && iconsMode == other.iconsMode && tabletMode == other.tabletMode
        && tabletApps == other.tabletApps && tabletDock == other.tabletDock && edgeLeft == other.edgeLeft && edgeRight == other.edgeRight
        && magnifiedSize == other.magnifiedSize && solidTopBar == other.solidTopBar && desktopIcons == other.desktopIcons
        && iconSize == other.iconSize && keyboardPolicy == other.keyboardPolicy && homeIndicator == other.homeIndicator;
}

PlasmaFusionKcm::PlasmaFusionKcm(QObject *parent, const KPluginMetaData &metaData)
    : KQuickManagedConfigModule(parent, metaData)
{
    setButtons(Apply | Default);

    // Changes made elsewhere (the quick-settings Dark style tile, the Colors page, Plasma's
    // automatic light/dark switching, the Animations page, the power service) show up here
    // while nothing is pending.
    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(400);
    connect(&m_reloadTimer, &QTimer::timeout, this, [this] {
        updateEnvironment();
        if (m_saving || m_busy || isSaveNeeded()) {
            return;
        }
        State state = m_current;
        loadConfigState(state);
        if (reapplyingDecoration()) {
            // The Global Theme Plasma just switched to has replaced the window decoration and the
            // colour scheme; the choice is put back shortly (onConfigChanged), so keep showing it.
            state.buttonStyle = m_saved.buttonStyle;
            state.fusionDecoration = m_saved.fusionDecoration;
            state.highContrast = m_saved.highContrast;
        }
        copyConfigState(state, m_current);
        copyConfigState(state, m_saved);
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
    m_fusionWatcher = KConfigWatcher::create(KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals));
    connect(m_fusionWatcher.data(), &KConfigWatcher::configChanged, this, &PlasmaFusionKcm::onConfigChanged);

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
        m_quickSettingsAvailable = false;
        m_folderAvailable = false;
        Q_EMIT shellStateChanged();
        settingsChanged();
    });

    // KWin's tablet mode (shown next to the Tablet mode choice). One call, then its signals.
    QDBusConnection::sessionBus().connect(u"org.kde.KWin"_s,
                                          u"/org/kde/KWin"_s,
                                          u"org.kde.KWin.TabletModeManager"_s,
                                          u"tabletModeChanged"_s,
                                          this,
                                          SLOT(onTabletModeSignal(bool)));
    QDBusConnection::sessionBus().connect(u"org.kde.KWin"_s,
                                          u"/org/kde/KWin"_s,
                                          u"org.kde.KWin.TabletModeManager"_s,
                                          u"tabletModeAvailableChanged"_s,
                                          this,
                                          SLOT(onTabletModeAvailableSignal(bool)));
}

PlasmaFusionKcm::~PlasmaFusionKcm() = default;

template<typename T>
void PlasmaFusionKcm::setField(T State::*field, T value)
{
    if (m_current.*field == value) {
        return;
    }
    m_current.*field = value;
    Q_EMIT stateChanged();
    settingsChanged();
}

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

bool PlasmaFusionKcm::quickSettingsAvailable() const
{
    return m_quickSettingsAvailable;
}

bool PlasmaFusionKcm::folderAvailable() const
{
    return m_folderAvailable;
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

QString PlasmaFusionKcm::infoText() const
{
    return m_infoText;
}

int PlasmaFusionKcm::snapTrigger() const
{
    return m_current.snapTrigger;
}

void PlasmaFusionKcm::setSnapTrigger(int value)
{
    if (value == SnapHold || value == SnapHover) {
        setField(&State::snapTrigger, value);
    }
}

int PlasmaFusionKcm::glass() const
{
    return m_current.glass;
}

void PlasmaFusionKcm::setGlass(int value)
{
    if (value >= GlassFull && value <= GlassSolid) {
        setField(&State::glass, value);
    }
}

int PlasmaFusionKcm::iconsMode() const
{
    return m_current.iconsMode;
}

void PlasmaFusionKcm::setIconsMode(int value)
{
    if (value == IconsDesigned || value == IconsFamiliar) {
        setField(&State::iconsMode, value);
    }
}

bool PlasmaFusionKcm::highContrast() const
{
    return m_current.highContrast;
}

void PlasmaFusionKcm::setHighContrast(bool value)
{
    if (value == m_current.highContrast || (value && !m_highContrastAvailable)) {
        return;
    }
    m_current.highContrast = value;
    // High contrast selects Solid glass (GAPS.md G10, EFFECTS.md 3.3); the Glass choice can
    // still be changed before Apply. Turned off again before Apply, the glass goes back too.
    if (value) {
        m_current.glass = GlassSolid;
    } else if (!m_saved.highContrast && m_current.glass == GlassSolid) {
        m_current.glass = m_saved.glass;
    }
    Q_EMIT stateChanged();
    settingsChanged();
}

bool PlasmaFusionKcm::reduceMotion() const
{
    return m_current.reduceMotion;
}

void PlasmaFusionKcm::setReduceMotion(bool value)
{
    setField(&State::reduceMotion, value);
}

int PlasmaFusionKcm::magnifiedSize() const
{
    return m_current.magnifiedSize;
}

void PlasmaFusionKcm::setMagnifiedSize(int value)
{
    // The dock's kcfg range.
    if (value >= 48 && value <= 72) {
        setField(&State::magnifiedSize, value);
    }
}

bool PlasmaFusionKcm::solidTopBar() const
{
    return m_current.solidTopBar;
}

void PlasmaFusionKcm::setSolidTopBar(bool value)
{
    setField(&State::solidTopBar, value);
}

bool PlasmaFusionKcm::everyScreen() const
{
    return m_current.everyScreen;
}

void PlasmaFusionKcm::setEveryScreen(bool value)
{
    setField(&State::everyScreen, value);
}

bool PlasmaFusionKcm::desktopIcons() const
{
    return m_current.desktopIcons;
}

void PlasmaFusionKcm::setDesktopIcons(bool value)
{
    setField(&State::desktopIcons, value);
}

int PlasmaFusionKcm::iconSize() const
{
    return m_current.iconSize;
}

void PlasmaFusionKcm::setIconSize(int value)
{
    // Folder View's iconSize: 0 = 22 px ... 6 = 256 px.
    if (value >= 0 && value <= 6) {
        setField(&State::iconSize, value);
    }
}

int PlasmaFusionKcm::dndBehavior() const
{
    return m_current.dndBehavior;
}

void PlasmaFusionKcm::setDndBehavior(int value)
{
    if (value == DndAsk || value == DndMove) {
        setField(&State::dndBehavior, value);
    }
}

bool PlasmaFusionKcm::lighterOnCritical() const
{
    return m_current.lighterOnCritical;
}

void PlasmaFusionKcm::setLighterOnCritical(bool value)
{
    setField(&State::lighterOnCritical, value);
}

bool PlasmaFusionKcm::fileContentIndexing() const
{
    return m_current.fileContentIndexing;
}

void PlasmaFusionKcm::setFileContentIndexing(bool value)
{
    setField(&State::fileContentIndexing, value);
}

int PlasmaFusionKcm::tabletMode() const
{
    return m_current.tabletMode;
}

void PlasmaFusionKcm::setTabletMode(int value)
{
    if (value >= TabletAuto && value <= TabletOff) {
        setField(&State::tabletMode, value);
    }
}

int PlasmaFusionKcm::tabletApps() const
{
    return m_current.tabletApps;
}

void PlasmaFusionKcm::setTabletApps(int value)
{
    if (value == AppsFullScreen || value == AppsWindowed) {
        setField(&State::tabletApps, value);
    }
}

int PlasmaFusionKcm::tabletDock() const
{
    return m_current.tabletDock;
}

void PlasmaFusionKcm::setTabletDock(int value)
{
    if (value == DockHideOverApps || value == DockAlwaysShow) {
        setField(&State::tabletDock, value);
    }
}

int PlasmaFusionKcm::keyboardPolicy() const
{
    return m_current.keyboardPolicy;
}

void PlasmaFusionKcm::setKeyboardPolicy(int value)
{
    if (value >= KeyboardTablet && value <= KeyboardNever) {
        setField(&State::keyboardPolicy, value);
    }
}

bool PlasmaFusionKcm::edgeLeft() const
{
    return m_current.edgeLeft;
}

void PlasmaFusionKcm::setEdgeLeft(bool value)
{
    setField(&State::edgeLeft, value);
}

bool PlasmaFusionKcm::edgeRight() const
{
    return m_current.edgeRight;
}

void PlasmaFusionKcm::setEdgeRight(bool value)
{
    setField(&State::edgeRight, value);
}

bool PlasmaFusionKcm::homeIndicator() const
{
    return m_current.homeIndicator;
}

void PlasmaFusionKcm::setHomeIndicator(bool value)
{
    setField(&State::homeIndicator, value);
}

bool PlasmaFusionKcm::highContrastAvailable() const
{
    return m_highContrastAvailable;
}

bool PlasmaFusionKcm::previousDesktopAvailable() const
{
    return m_previousDesktopAvailable;
}

bool PlasmaFusionKcm::topBarScriptAvailable() const
{
    return !topBarScriptPath().isEmpty();
}

bool PlasmaFusionKcm::tabletModeAvailable() const
{
    return m_tabletModeAvailable;
}

bool PlasmaFusionKcm::tabletModeActive() const
{
    return m_tabletModeActive;
}

bool PlasmaFusionKcm::powerCritical() const
{
    return m_powerCritical;
}

bool PlasmaFusionKcm::fusionLookAndFeel() const
{
    return m_saved.style != OtherStyle;
}

bool PlasmaFusionKcm::busy() const
{
    return m_busy;
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
    Q_EMIT stateChanged();
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

void PlasmaFusionKcm::setInfoText(const QString &text)
{
    if (text == m_infoText) {
        return;
    }
    m_infoText = text;
    Q_EMIT infoTextChanged();
}

void PlasmaFusionKcm::setBusy(bool busy)
{
    if (busy == m_busy) {
        return;
    }
    m_busy = busy;
    Q_EMIT busyChanged();
}

void PlasmaFusionKcm::updateDecorationInstalled()
{
    const bool installed = KPluginMetaData::findPluginById(s_decorationNamespace, s_decorationId).isValid();
    if (installed != m_decorationInstalled) {
        m_decorationInstalled = installed;
        Q_EMIT decorationInstalledChanged();
    }
}

void PlasmaFusionKcm::updateEnvironment()
{
    const bool highContrast =
        !QStandardPaths::locate(QStandardPaths::GenericDataLocation, u"color-schemes/%1.colors"_s.arg(s_highContrastScheme)).isEmpty();
    const bool previous =
        !QStandardPaths::locate(QStandardPaths::GenericDataLocation, u"plasma/look-and-feel/%1/metadata.json"_s.arg(s_previousLookAndFeel)).isEmpty();

    // The power service (plasma-fusion-powerfx) writes the tier it applies; at "critical" it
    // holds the glass solid and the dock magnification off when LighterOnCritical is set, and
    // restores the remembered user values ([Power] UserGlass, UserDockMagnify) afterwards.
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    const KConfigGroup power(fusion, u"Power"_s);
    const bool critical = power.readEntry("Tier", QString()).compare(u"critical"_s, Qt::CaseInsensitive) == 0
        && power.readEntry("LighterOnCritical", true);

    if (highContrast != m_highContrastAvailable || previous != m_previousDesktopAvailable || critical != m_powerCritical) {
        m_highContrastAvailable = highContrast;
        m_previousDesktopAvailable = previous;
        m_powerCritical = critical;
        Q_EMIT environmentChanged();
    }
}

void PlasmaFusionKcm::requestTabletState()
{
    QDBusMessage message = QDBusMessage::createMethodCall(u"org.kde.KWin"_s, u"/org/kde/KWin"_s, u"org.freedesktop.DBus.Properties"_s, u"GetAll"_s);
    message << u"org.kde.KWin.TabletModeManager"_s;
    const QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(message, s_dbusTimeout);
    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        const QDBusPendingReply<QVariantMap> reply = *watcher;
        watcher->deleteLater();
        if (reply.isError()) {
            return;
        }
        const QVariantMap properties = reply.value();
        m_tabletModeAvailable = properties.value(u"tabletModeAvailable"_s).toBool();
        m_tabletModeActive = properties.value(u"tabletMode"_s).toBool();
        Q_EMIT environmentChanged();
    });
}

void PlasmaFusionKcm::onTabletModeSignal(bool active)
{
    m_tabletModeActive = active;
    Q_EMIT environmentChanged();
}

void PlasmaFusionKcm::onTabletModeAvailableSignal(bool available)
{
    m_tabletModeAvailable = available;
    Q_EMIT environmentChanged();
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
    state.highContrast = general.readEntry("ColorScheme", QString()) == s_highContrastScheme;

    // Motion: the live state, so the switch follows System Settings' own Animation speed slider.
    state.reduceMotion = qFuzzyIsNull(kde.readEntry("AnimationDurationFactor", 1.0));
    state.dndBehavior = kde.readEntry("DndBehavior", QString()) == u"MoveIfSameDevice" ? DndMove : DndAsk;

    // Window buttons
    KSharedConfig::Ptr kwin = KSharedConfig::openConfig(u"kwinrc"_s);
    kwin->reparseConfiguration();
    const KConfigGroup decoration(kwin, s_kwinDecorationGroup);
    const QString library = decoration.readEntry("library", QString());
    const QString theme = decoration.readEntry("theme", QString());
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    const KConfigGroup fusionDecoration(fusion, s_decorationConfigGroup);
    const int chosen = buttonStyleFromName(fusionDecoration.readEntry("ButtonStyle", QString()));
    state.fusionDecoration = library == s_decorationId;
    if (library == s_decorationId) {
        state.buttonStyle = chosen >= 0 ? chosen : RightGlyphs;
    } else if (library.startsWith(u"org.kde.kwin.aurorae"_s) && theme.startsWith(s_auroraeThemePrefix + u"PlasmaFusion"_s)) {
        // The Aurorae fallback has no show-on-hover mode; the choice is kept in plasmafusionrc.
        state.buttonStyle = theme.endsWith(u"-Left"_s) ? LeftCircles : (chosen == ShowOnHover ? ShowOnHover : RightGlyphs);
    } else {
        state.buttonStyle = chosen >= 0 ? chosen : RightGlyphs;
    }
    // Hold is the default (owner decision 4); the key is written either way, because the
    // decoration 1.0-2 still reads a missing key as hover.
    state.snapTrigger = fusionDecoration.readEntry("SnapLayoutsOnHover", false) ? SnapHover : SnapHold;

    // Hot corner (KWin's default when the key is missing is the top-left corner).
    const QList<int> borders = KConfigGroup(kwin, u"Effect-overview"_s).readEntry("BorderActivate", QList<int>{s_hotCornerOn});
    state.hotCorner = borders.contains(s_hotCornerOn);

    // Glass, top bars, battery, app icons (plasmafusionrc)
    state.glass = glassFromName(KConfigGroup(fusion, u"Effects"_s).readEntry("Glass", QString()));
    state.everyScreen = KConfigGroup(fusion, u"TopBar"_s).readEntry("EveryScreen", true);
    state.lighterOnCritical = KConfigGroup(fusion, u"Power"_s).readEntry("LighterOnCritical", true);
    // The app-icons service treats anything but "designs" as familiar (docs/parts/app-icons.md).
    state.iconsMode = KConfigGroup(fusion, u"Icons"_s).readEntry("AppIcons", QString()) == u"designs"_s ? IconsDesigned : IconsFamiliar;
    // File contents in search: Baloo's own key (System Settings > File Search), on by default.
    const KSharedConfig::Ptr baloo = KSharedConfig::openConfig(u"baloofilerc"_s, KConfig::NoGlobals);
    baloo->reparseConfiguration();
    state.fileContentIndexing = !KConfigGroup(baloo, u"General"_s).readEntry("only basic indexing", false);

    // Tablet (KWin)
    const QString tabletMode = KConfigGroup(kwin, u"Input"_s).readEntry("TabletMode", QString());
    state.tabletMode = tabletMode == u"on" ? TabletOn : tabletMode == u"off" ? TabletOff : TabletAuto;
    const KConfigGroup tablet(kwin, s_tabletScriptGroup);
    state.tabletApps = tablet.readEntry("WindowMode", QString()) == u"windowed" ? AppsWindowed : AppsFullScreen;
    state.tabletDock = tablet.readEntry("DockHiding", QString()) == u"none" ? DockAlwaysShow : DockHideOverApps;
    state.edgeLeft = tablet.readEntry("EdgeLeft", false);
    state.edgeRight = tablet.readEntry("EdgeRight", false);
}

void PlasmaFusionKcm::copyConfigState(const State &from, State &to) const
{
    to.style = from.style;
    to.accentMode = from.accentMode;
    to.accentColor = from.accentColor;
    to.buttonStyle = from.buttonStyle;
    to.fusionDecoration = from.fusionDecoration;
    to.hotCorner = from.hotCorner;
    to.snapTrigger = from.snapTrigger;
    to.glass = from.glass;
    to.highContrast = from.highContrast;
    to.reduceMotion = from.reduceMotion;
    to.everyScreen = from.everyScreen;
    to.dndBehavior = from.dndBehavior;
    to.lighterOnCritical = from.lighterOnCritical;
    to.fileContentIndexing = from.fileContentIndexing;
    to.tabletMode = from.tabletMode;
    to.tabletApps = from.tabletApps;
    to.tabletDock = from.tabletDock;
    to.edgeLeft = from.edgeLeft;
    to.edgeRight = from.edgeRight;
}

void PlasmaFusionKcm::load()
{
    KQuickManagedConfigModule::load();
    setErrorText(QString());
    updateDecorationInstalled();
    updateEnvironment();

    State state = m_saved;
    loadConfigState(state);
    m_current = state;
    m_saved = state;
    m_wallpaperColor = state.accentMode == WallpaperAccent ? state.accentColor : QColor();
    Q_EMIT wallpaperColorChanged();
    Q_EMIT environmentChanged();
    emitAll();
    settingsChanged();
    requestShellState();
    requestTabletState();
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
    // The last applied choice: an Apply made after "Follow sunset" (still within the time above)
    // may have changed it.
    const int buttonStyle = m_saved.buttonStyle;
    const bool matches = m_decorationInstalled
        ? library == s_decorationId
        : (library == s_auroraeLibrary && theme == s_auroraeThemePrefix + expectedAuroraeTheme(currentVariantIsLight(), buttonStyle));
    if (!matches) {
        qCInfo(KCM_PLASMAFUSION) << "Global Theme switched: applying the window buttons again";
        applyDecoration(buttonStyle);
        reconfigureKWin(false);
    }
    // The Global Theme also brings its own colour scheme.
    if (m_saved.highContrast) {
        KSharedConfig::Ptr globals = KSharedConfig::openConfig(u"kdeglobals"_s);
        globals->reparseConfiguration();
        if (KConfigGroup(globals, u"General"_s).readEntry("ColorScheme", QString()) != s_highContrastScheme) {
            qCInfo(KCM_PLASMAFUSION) << "Global Theme switched: applying high contrast again";
            applyColorScheme(true);
        }
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
    static const QStringList watched = {
        u"KDE"_s,
        u"General"_s,
        s_kwinDecorationGroup,
        u"Effect-overview"_s,
        u"Input"_s,
        s_tabletScriptGroup,
        u"Decoration"_s,
        u"Effects"_s,
        u"Icons"_s,
        u"Power"_s,
        u"TopBar"_s,
    };
    if (watched.contains(name)) {
        m_reloadTimer.start();
    }
}

bool PlasmaFusionKcm::isSaveNeeded() const
{
    return !(m_current == m_saved);
}

// The defaults, except for what cannot be changed right now (a missing dock, top bar, quick
// settings or Folder View desktop, a stopped shell, no high-contrast scheme): those keep the
// value on the page.
PlasmaFusionKcm::State PlasmaFusionKcm::defaultState() const
{
    State defaults;
    // With the Plasma Fusion decoration installed, the default is to use it.
    defaults.fusionDecoration = m_decorationInstalled;
    if (!m_dockAvailable) {
        defaults.magnify = m_current.magnify;
        defaults.magnifiedSize = m_current.magnifiedSize;
        defaults.homeIndicator = m_current.homeIndicator;
    }
    if (!m_topBarAvailable) {
        defaults.globalMenu = m_current.globalMenu;
        defaults.solidTopBar = m_current.solidTopBar;
    }
    if (!m_quickSettingsAvailable) {
        defaults.keyboardPolicy = m_current.keyboardPolicy;
    }
    if (!m_folderAvailable) {
        defaults.desktopIcons = m_current.desktopIcons;
        defaults.iconSize = m_current.iconSize;
    }
    if (!m_shellRunning) {
        defaults.glass = m_current.glass;
        defaults.everyScreen = m_current.everyScreen;
    }
    return defaults;
}

bool PlasmaFusionKcm::isDefaults() const
{
    return m_current == defaultState();
}

void PlasmaFusionKcm::defaults()
{
    KQuickManagedConfigModule::defaults();
    m_current = defaultState();
    emitAll();
    settingsChanged();
}

void PlasmaFusionKcm::save()
{
    KQuickManagedConfigModule::save();
    m_saving = true;
    setErrorText(QString());
    setInfoText(QString());
    updateEnvironment();
    const State before = m_saved;
    const State after = m_current;

    // 1. Style. A Global Theme brings its own window decoration and colour scheme, so the window
    //    buttons and high contrast are applied again after it.
    bool decoration = after.buttonStyle != before.buttonStyle || after.fusionDecoration != before.fusionDecoration;
    bool themeApplied = false;
    if (after.style != before.style && after.style != OtherStyle) {
        themeApplied = applyStyle(after.style) && after.style != FollowSunset;
        decoration = true;
    }
    // 2. Colour scheme: high contrast on top of the Global Theme's scheme, or back to it, and the
    //    gsettings key the portal's contrast is served from.
    if (after.highContrast != before.highContrast || (after.highContrast && themeApplied)) {
        applyColorScheme(after.highContrast);
        setPortalHighContrast(after.highContrast);
    }
    // 3. Accent colour, on top of the colour scheme the style just applied.
    if (!after.sameAccent(before)) {
        applyAccent(after);
    }
    // 4. KWin: window buttons, snap layouts, hot corner (one reconfigure), glass, tablet.
    bool reconfigure = false;
    if (decoration) {
        applyDecoration(after.buttonStyle);
        reconfigure = true;
    }
    if (after.snapTrigger != before.snapTrigger) {
        applySnapTrigger(after.snapTrigger);
        reconfigure = true;
    }
    if (after.hotCorner != before.hotCorner) {
        applyHotCorner(after.hotCorner);
        reconfigure = true;
    }
    if (reconfigure) {
        reconfigureKWin(after.hotCorner != before.hotCorner);
    }
    // Glass also changes the panels and widgets (step 6), so it needs the shell.
    const bool glassChanged = after.glass != before.glass && m_shellRunning;
    if (glassChanged) {
        applyGlassConfig(after.glass);
    } else if (after.glass != before.glass) {
        m_current.glass = before.glass;
    }
    // 5. Motion, file drag, battery, tablet.
    if (after.reduceMotion != before.reduceMotion) {
        applyReduceMotion(after.reduceMotion);
    }
    if (after.dndBehavior != before.dndBehavior) {
        applyDndBehavior(after.dndBehavior);
    }
    if (after.lighterOnCritical != before.lighterOnCritical) {
        applyLighterOnCritical(after.lighterOnCritical);
    }
    if (after.fileContentIndexing != before.fileContentIndexing) {
        applyFileContentIndexing(after.fileContentIndexing);
    }
    if (after.iconsMode != before.iconsMode) {
        applyIconsMode(after.iconsMode);
    }
    applyTabletConfig(before, after);

    // 6. Plasma shell. A switch whose dock, top bar or desktop went away meanwhile (the shell
    //    stopped) keeps the value last read, so the page shows what is in effect.
    if (after.magnify != before.magnify) {
        if (m_dockAvailable) {
            applyMagnify(after.magnify);
        } else {
            m_current.magnify = before.magnify;
        }
    }
    if (after.magnifiedSize != before.magnifiedSize) {
        if (m_dockAvailable) {
            applyMagnifiedSize(after.magnifiedSize);
        } else {
            m_current.magnifiedSize = before.magnifiedSize;
        }
    }
    if (after.homeIndicator != before.homeIndicator) {
        if (m_dockAvailable) {
            applyWidgetKey(u"org.plasmafusion.dock"_s,
                           u"homeIndicator"_s,
                           after.homeIndicator ? u"true"_s : u"false"_s,
                           i18nc("@info", "The dock setting could not be changed."));
        } else {
            m_current.homeIndicator = before.homeIndicator;
        }
    }
    if (after.globalMenu != before.globalMenu) {
        if (m_topBarAvailable) {
            applyGlobalMenu(after.globalMenu);
        } else {
            m_current.globalMenu = before.globalMenu;
        }
    }
    const bool topBarChanged = after.solidTopBar != before.solidTopBar;
    if (topBarChanged && !m_topBarAvailable) {
        m_current.solidTopBar = before.solidTopBar;
    }
    if (glassChanged || (topBarChanged && m_topBarAvailable)) {
        // At 10 % battery the power service holds the widgets at solid; they follow the level
        // when it restores the remembered one.
        applyPanels(m_current.glass, m_current.solidTopBar, glassChanged && !m_powerCritical);
    }
    if (after.everyScreen != before.everyScreen) {
        if (m_shellRunning) {
            applyEveryScreen(after.everyScreen);
        } else {
            m_current.everyScreen = before.everyScreen;
        }
    }
    if (after.desktopIcons != before.desktopIcons || after.iconSize != before.iconSize) {
        if (m_folderAvailable) {
            applyDesktop(before, after);
        } else {
            m_current.desktopIcons = before.desktopIcons;
            m_current.iconSize = before.iconSize;
        }
    }
    if (after.keyboardPolicy != before.keyboardPolicy) {
        if (m_quickSettingsAvailable) {
            static const QStringList policies = {u"tablet"_s, u"touch"_s, u"never"_s};
            applyWidgetKey(u"org.plasmafusion.quicksettings"_s,
                           u"keyboardPolicy"_s,
                           jsString(policies.value(after.keyboardPolicy)),
                           i18nc("@info", "The on-screen keyboard setting could not be changed."));
        } else {
            m_current.keyboardPolicy = before.keyboardPolicy;
        }
    }

    if (after.style == FollowSunset && before.style != FollowSunset) {
        m_reapplyDecorationUntil = QDeadlineTimer(20000);
    }
    if (decoration) {
        // applyDecoration uses the Plasma Fusion decoration whenever it is installed.
        m_current.fusionDecoration = m_decorationInstalled;
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
        requestShellState();
    }
    updateEnvironment();
    emitAll();
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

// High contrast on: the Plasma Fusion High Contrast scheme. Off: the scheme of the Global Theme
// in use (Plasma Fusion Light or Dark). plasma-apply-colorscheme keeps the accent colour.
bool PlasmaFusionKcm::applyColorScheme(bool highContrast)
{
    const QString scheme = highContrast ? s_highContrastScheme : (currentVariantIsLight() ? s_lightScheme : s_darkScheme);
    return runTool(u"plasma-apply-colorscheme"_s, {scheme});
}

// The XDG settings portal's contrast key is served by the GTK portal from the gsettings key
// org.gnome.desktop.a11y.interface high-contrast; xdg-desktop-portal-kde 6.7.5 does not serve
// contrast at all (its appearance keys are color-scheme, accent-color and reduced-motion), so the
// scheme alone cannot reach applications that follow the portal. Written quietly: gsettings or its
// schema can be absent, which is not an error the user needs to see (settings plan task 2,
// artifacts/plasma-fusion/2026-10-05-settings-plan/PLAN.md).
void PlasmaFusionKcm::setPortalHighContrast(bool value)
{
    if (QStandardPaths::findExecutable(u"gsettings"_s).isEmpty()) {
        qCDebug(KCM_PLASMAFUSION) << "gsettings not found; the portal contrast key is not written";
        return;
    }
    QProcess process;
    process.setProcessChannelMode(QProcess::MergedChannels);
    process.start(u"gsettings"_s,
                  {u"set"_s, u"org.gnome.desktop.a11y.interface"_s, u"high-contrast"_s, value ? u"true"_s : u"false"_s});
    if (!process.waitForFinished(s_toolTimeout)) {
        process.kill();
        process.waitForFinished(1000);
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        qCDebug(KCM_PLASMAFUSION) << "gsettings high-contrast not written (schema missing?)";
    }
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
    if (!runTool(u"plasma-apply-colorscheme"_s, {u"--accent-color"_s, accentArgument})) {
        return false;
    }
    // plasma-apply-colorscheme 6.7.5 announces the palette change (KGlobalSettings notifyChange,
    // PaletteChanged) before kdeglobals is written: its accent path does not sync, so the file is
    // written when the tool exits, and plasmashell can read the old accent. The tool has finished
    // now, so the change is announced again.
    QDBusMessage paletteChanged = QDBusMessage::createSignal(u"/KGlobalSettings"_s, u"org.kde.KGlobalSettings"_s, u"notifyChange"_s);
    paletteChanged.setArguments({0 /* PaletteChanged */, 0});
    QDBusConnection::sessionBus().send(paletteChanged);
    return true;
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
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    KConfigGroup(fusion, s_decorationConfigGroup).writeEntry("ButtonStyle", s_buttonStyleNames.value(buttonStyle), KConfig::Notify);
    fusion->sync();
    return true;
}

void PlasmaFusionKcm::applySnapTrigger(int trigger)
{
    // Read by the decoration when KWin reconfigures (fusionconfig.cpp).
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    KConfigGroup(fusion, s_decorationConfigGroup).writeEntry("SnapLayoutsOnHover", trigger == SnapHover, KConfig::Notify);
    fusion->sync();
}

void PlasmaFusionKcm::applyHotCorner(bool on)
{
    KSharedConfig::Ptr kwin = KSharedConfig::openConfig(u"kwinrc"_s);
    kwin->reparseConfiguration();
    KConfigGroup overview(kwin, u"Effect-overview"_s);
    // Only the top-left corner changes; other screen edges set for Overview (Screen Edges page)
    // are kept. With no edge left the value is 9 (none), as tools/device/fusion-config.sh writes.
    QList<int> borders = overview.readEntry("BorderActivate", QList<int>{s_hotCornerOn});
    borders.removeAll(s_hotCornerOn);
    borders.removeAll(s_hotCornerOff);
    if (on) {
        borders.prepend(s_hotCornerOn);
    }
    if (borders.isEmpty()) {
        borders.append(s_hotCornerOff);
    }
    overview.writeEntry("BorderActivate", borders, KConfig::Notify);
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

// plasmafusionrc [Effects] Glass and KWin's blur (EFFECTS.md 2, 3.3). The panels and widgets
// follow in applyPanels.
void PlasmaFusionKcm::applyGlassConfig(int glass)
{
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    KConfigGroup(fusion, u"Effects"_s).writeEntry("Glass", s_glassNames.value(glass), KConfig::Notify);
    if (m_powerCritical) {
        // The power service keeps the glass solid until the battery recovers and then restores
        // the level it remembered; this is the level it restores now.
        KConfigGroup(fusion, u"Power"_s).writeEntry("UserGlass", s_glassNames.value(glass), KConfig::Notify);
        fusion->sync();
        return;
    }
    fusion->sync();

    KSharedConfig::Ptr kwin = KSharedConfig::openConfig(u"kwinrc"_s);
    kwin->reparseConfiguration();
    KConfigGroup plugins(kwin, u"Plugins"_s);
    if (glass == GlassSolid) {
        plugins.writeEntry("blurEnabled", false, KConfig::Notify);
    } else {
        plugins.deleteEntry("blurEnabled", KConfig::Notify);
    }
    kwin->sync();
    // The key alone takes effect at KWin's next start; the running KWin loads or unloads now.
    QDBusMessage message = QDBusMessage::createMethodCall(u"org.kde.KWin"_s,
                                                          u"/Effects"_s,
                                                          u"org.kde.kwin.Effects"_s,
                                                          glass == GlassSolid ? u"unloadEffect"_s : u"loadEffect"_s);
    message << u"blur"_s;
    QDBusConnection::sessionBus().asyncCall(message);
}

// Reduce motion is Plasma's own "Instant" animation speed (EFFECTS.md 7): factor 0, with the
// previous factor kept to put back (absent = 1.0, so the key is removed again).
// plasmafusionrc [Icons] AppIcons: the apps' own familiar icons on Fusion tiles (the default) or
// the designed tiles only (docs/parts/app-icons.md; the app-icons service reads the same key and
// treats anything but "designs" as familiar).
void PlasmaFusionKcm::applyIconsMode(int mode)
{
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    KConfigGroup(fusion, u"Icons"_s).writeEntry("AppIcons", mode == IconsDesigned ? u"designs"_s : u"familiar"_s, KConfig::Notify);
    fusion->sync();
}

void PlasmaFusionKcm::applyReduceMotion(bool on)
{
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(u"kdeglobals"_s);
    globals->reparseConfiguration();
    KConfigGroup kde(globals, u"KDE"_s);
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    KConfigGroup motion(fusion, u"Motion"_s);
    if (on) {
        const double factor = kde.readEntry("AnimationDurationFactor", 1.0);
        if (kde.hasKey("AnimationDurationFactor") && !qFuzzyIsNull(factor)) {
            motion.writeEntry("PreviousAnimationDurationFactor", factor);
        } else {
            motion.deleteEntry("PreviousAnimationDurationFactor");
        }
        fusion->sync();
        kde.writeEntry("AnimationDurationFactor", 0.0, KConfig::Notify);
    } else {
        const double previous = motion.readEntry("PreviousAnimationDurationFactor", 0.0);
        if (motion.hasKey("PreviousAnimationDurationFactor") && previous > 0) {
            kde.writeEntry("AnimationDurationFactor", previous, KConfig::Notify);
        } else {
            kde.deleteEntry("AnimationDurationFactor", KConfig::Notify);
        }
        motion.deleteEntry("PreviousAnimationDurationFactor");
        fusion->sync();
    }
    globals->sync();
}

// Dragging files between folders (BACKLOG S7): the General Behavior page's key; Ask is the
// default, so it is removed.
void PlasmaFusionKcm::applyDndBehavior(int behavior)
{
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(u"kdeglobals"_s);
    globals->reparseConfiguration();
    KConfigGroup kde(globals, u"KDE"_s);
    if (behavior == DndMove) {
        kde.writeEntry("DndBehavior", u"MoveIfSameDevice"_s, KConfig::Notify);
    } else {
        kde.revertToDefault("DndBehavior", KConfig::Notify);
    }
    globals->sync();
}

void PlasmaFusionKcm::applyLighterOnCritical(bool on)
{
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    KConfigGroup(fusion, u"Power"_s).writeEntry("LighterOnCritical", on, KConfig::Notify);
    fusion->sync();
}

// Baloo's own key, then its file indexer reads its configuration again: what System Settings >
// File Search does (Baloo::IndexerConfig::refresh). Baloo pauses content indexing on battery by
// itself, so this mostly saves power while charging; file names stay searchable either way.
void PlasmaFusionKcm::applyFileContentIndexing(bool on)
{
    KSharedConfig::Ptr baloo = KSharedConfig::openConfig(u"baloofilerc"_s, KConfig::NoGlobals);
    baloo->reparseConfiguration();
    KConfigGroup(baloo, u"General"_s).writeEntry("only basic indexing", !on);
    baloo->sync();
    QDBusConnection::sessionBus().asyncCall(
        QDBusMessage::createMethodCall(u"org.kde.baloo"_s, u"/"_s, u"org.kde.baloo.main"_s, u"updateConfig"_s));
}

// TABLET.md 3.2 and 4.15: kwinrc with a notification (KWin's KConfigWatcher reparses it), then the
// tablet script's shortcut, which reads its keys again and applies them.
void PlasmaFusionKcm::applyTabletConfig(const State &before, const State &after)
{
    const bool mode = after.tabletMode != before.tabletMode;
    const bool script = after.tabletApps != before.tabletApps || after.tabletDock != before.tabletDock || after.edgeLeft != before.edgeLeft
        || after.edgeRight != before.edgeRight;
    if (!mode && !script) {
        return;
    }
    KSharedConfig::Ptr kwin = KSharedConfig::openConfig(u"kwinrc"_s);
    kwin->reparseConfiguration();
    if (mode) {
        KConfigGroup input(kwin, u"Input"_s);
        if (after.tabletMode == TabletAuto) {
            input.deleteEntry("TabletMode", KConfig::Notify);
        } else {
            input.writeEntry("TabletMode", after.tabletMode == TabletOn ? u"on"_s : u"off"_s, KConfig::Notify);
        }
    }
    KConfigGroup tablet(kwin, s_tabletScriptGroup);
    if (after.tabletApps != before.tabletApps) {
        tablet.writeEntry("WindowMode", after.tabletApps == AppsWindowed ? u"windowed"_s : u"fullscreen"_s, KConfig::Notify);
    }
    if (after.tabletDock != before.tabletDock) {
        tablet.writeEntry("DockHiding", after.tabletDock == DockAlwaysShow ? u"none"_s : u"dodgewindows"_s, KConfig::Notify);
    }
    if (after.edgeLeft != before.edgeLeft) {
        tablet.writeEntry("EdgeLeft", after.edgeLeft, KConfig::Notify);
    }
    if (after.edgeRight != before.edgeRight) {
        tablet.writeEntry("EdgeRight", after.edgeRight, KConfig::Notify);
    }
    kwin->sync();
    if (script) {
        // Registered by the plasmafusion-tablet KWin script; nothing happens without it.
        QDBusMessage message =
            QDBusMessage::createMethodCall(u"org.kde.kglobalaccel"_s, u"/component/kwin"_s, u"org.kde.kglobalaccel.Component"_s, u"invokeShortcut"_s);
        message << s_tabletShortcut;
        QDBusConnection::sessionBus().asyncCall(message);
    }
}

#include "kcm.moc"
