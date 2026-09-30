/*
    Plasma Fusion settings module: the Appearance page of the Plasma Fusion design, and the
    Plasma Fusion switches that have no page of their own in System Settings.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KConfigWatcher>
#include <KQuickManagedConfigModule>

#include <QColor>
#include <QDeadlineTimer>
#include <QJsonObject>
#include <QString>
#include <QTimer>

class QDBusPendingCallWatcher;
class QDBusServiceWatcher;

/*
    Everything on the page is read from the session when the module loads and written only when
    Apply is pressed (the two actions at the end of the page run at once, after a confirmation):

      Style           Light / Dark apply the Global Theme org.plasmafusion.light/dark.desktop
                      (plasma-apply-lookandfeel); Follow sunset sets kdeglobals [KDE]
                      DefaultLightLookAndFeel, DefaultDarkLookAndFeel, AutomaticLookAndFeel=true,
                      as tools/device/fusion-config.sh --auto does, and Plasma's own
                      lookandfeelautoswitcher module switches between them.
      Accent color    kdeglobals [General] AccentColor, LastUsedCustomAccentColor,
                      accentColorFromWallpaper (the keys the Colors page writes), then the colour
                      scheme is applied again with the accent (plasma-apply-colorscheme).
      Window buttons  ~/.config/plasmafusionrc [Decoration] ButtonStyle for the Plasma Fusion
                      decoration (org.plasmafusion.decoration); without it the Aurorae themes
                      PlasmaFusion{Dark,Light}[-Left]; kwinrc [org.kde.kdecoration2].
      Snap layouts    plasmafusionrc [Decoration] SnapLayoutsOnHover (false: hold, true: hover).
      Dock            the org.plasmafusion.dock widgets' [General] magnify and magnifiedSize keys
                      (desktop scripting).
      Global menu     org.kde.plasma.appmenu right after org.plasmafusion.appname in the top bar.
      Hot corner      kwinrc [Effect-overview] BorderActivate 7 (top-left corner) or 9 (none).
      Glass           plasmafusionrc [Effects] Glass=Full|Reduced|Solid; Solid: kwinrc [Plugins]
                      blurEnabled=false and the blur effect unloaded; Reduced: both Fusion panels
                      opaque; the dock, quick-settings, launcher and system-card widgets' glass key.
      High contrast   the Plasma Fusion High Contrast colour scheme (selects Solid glass).
      Reduce motion   kdeglobals [KDE] AnimationDurationFactor=0; the previous value is kept in
                      plasmafusionrc [Motion] PreviousAnimationDurationFactor and put back.
      Top bar         panel opacity adaptive (solid next to windows) or translucent, kept in
                      plasmafusionrc [TopBar] SolidNextToWindows for opaque (Reduced) bars;
                      [TopBar] EveryScreen with a top bar on every screen (ensure-topbars.js).
      Desktop icons   Folder View [General] filterMode=1 with the pattern "/", which matches no
                      file name (positions are kept), and iconSize.
      File drag       kdeglobals [KDE] DndBehavior (AlwaysAsk / MoveIfSameDevice).
      Battery         plasmafusionrc [Power] LighterOnCritical.
      Tablet          kwinrc [Input] TabletMode, [Script-plasmafusion-tablet] WindowMode,
                      DockHiding, EdgeLeft, EdgeRight (then the "Plasma Fusion: Tablet Window
                      Mode" shortcut), the quick-settings widgets' keyboardPolicy and the docks'
                      homeIndicator.
      Actions         "Restore my previous desktop" applies org.plasmafusion.previous.desktop;
                      "Reset Fusion layout" rebuilds the panels and desktop from the Global Theme's
                      layout and gives the new widgets the global shortcuts the old ones had.
*/
class PlasmaFusionKcm : public KQuickManagedConfigModule
{
    Q_OBJECT

    Q_PROPERTY(int style READ style WRITE setStyle NOTIFY styleChanged)
    Q_PROPERTY(int accentMode READ accentMode NOTIFY accentChanged)
    Q_PROPERTY(QColor accentColor READ accentColor NOTIFY accentChanged)
    Q_PROPERTY(QColor wallpaperColor READ wallpaperColor NOTIFY wallpaperColorChanged)
    Q_PROPERTY(int buttonStyle READ buttonStyle WRITE setButtonStyle NOTIFY buttonStyleChanged)
    Q_PROPERTY(bool magnify READ magnify WRITE setMagnify NOTIFY magnifyChanged)
    Q_PROPERTY(bool globalMenu READ globalMenu WRITE setGlobalMenu NOTIFY globalMenuChanged)
    Q_PROPERTY(bool hotCorner READ hotCorner WRITE setHotCorner NOTIFY hotCornerChanged)
    Q_PROPERTY(bool shellLoading READ shellLoading NOTIFY shellStateChanged)
    // The Plasma shell answered the last layout query (false: not running or not answering).
    Q_PROPERTY(bool shellRunning READ shellRunning NOTIFY shellStateChanged)
    Q_PROPERTY(bool dockAvailable READ dockAvailable NOTIFY shellStateChanged)
    Q_PROPERTY(bool topBarAvailable READ topBarAvailable NOTIFY shellStateChanged)
    Q_PROPERTY(bool quickSettingsAvailable READ quickSettingsAvailable NOTIFY shellStateChanged)
    // The desktop is a Folder View (the only desktop type that shows icons).
    Q_PROPERTY(bool folderAvailable READ folderAvailable NOTIFY shellStateChanged)
    Q_PROPERTY(bool decorationInstalled READ decorationInstalled NOTIFY decorationInstalledChanged)
    // The Plasma Fusion decoration is (or will be, after Apply) KWin's window decoration.
    Q_PROPERTY(bool fusionDecoration READ fusionDecoration NOTIFY buttonStyleChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)
    Q_PROPERTY(QString infoText READ infoText NOTIFY infoTextChanged)

    // The switches below all notify through stateChanged.
    Q_PROPERTY(int snapTrigger READ snapTrigger WRITE setSnapTrigger NOTIFY stateChanged)
    Q_PROPERTY(int glass READ glass WRITE setGlass NOTIFY stateChanged)
    Q_PROPERTY(bool highContrast READ highContrast WRITE setHighContrast NOTIFY stateChanged)
    Q_PROPERTY(bool reduceMotion READ reduceMotion WRITE setReduceMotion NOTIFY stateChanged)
    Q_PROPERTY(int magnifiedSize READ magnifiedSize WRITE setMagnifiedSize NOTIFY stateChanged)
    Q_PROPERTY(bool solidTopBar READ solidTopBar WRITE setSolidTopBar NOTIFY stateChanged)
    Q_PROPERTY(bool everyScreen READ everyScreen WRITE setEveryScreen NOTIFY stateChanged)
    Q_PROPERTY(bool desktopIcons READ desktopIcons WRITE setDesktopIcons NOTIFY stateChanged)
    Q_PROPERTY(int iconSize READ iconSize WRITE setIconSize NOTIFY stateChanged)
    Q_PROPERTY(int dndBehavior READ dndBehavior WRITE setDndBehavior NOTIFY stateChanged)
    Q_PROPERTY(bool lighterOnCritical READ lighterOnCritical WRITE setLighterOnCritical NOTIFY stateChanged)
    Q_PROPERTY(int tabletMode READ tabletMode WRITE setTabletMode NOTIFY stateChanged)
    Q_PROPERTY(int tabletApps READ tabletApps WRITE setTabletApps NOTIFY stateChanged)
    Q_PROPERTY(int tabletDock READ tabletDock WRITE setTabletDock NOTIFY stateChanged)
    Q_PROPERTY(int keyboardPolicy READ keyboardPolicy WRITE setKeyboardPolicy NOTIFY stateChanged)
    Q_PROPERTY(bool edgeLeft READ edgeLeft WRITE setEdgeLeft NOTIFY stateChanged)
    Q_PROPERTY(bool edgeRight READ edgeRight WRITE setEdgeRight NOTIFY stateChanged)
    Q_PROPERTY(bool homeIndicator READ homeIndicator WRITE setHomeIndicator NOTIFY stateChanged)

    // What the session offers (read-only).
    Q_PROPERTY(bool highContrastAvailable READ highContrastAvailable NOTIFY environmentChanged)
    Q_PROPERTY(bool previousDesktopAvailable READ previousDesktopAvailable NOTIFY environmentChanged)
    Q_PROPERTY(bool topBarScriptAvailable READ topBarScriptAvailable NOTIFY environmentChanged)
    // KWin's TabletModeManager: a hinge or tablet switch exists / the effective mode now.
    Q_PROPERTY(bool tabletModeAvailable READ tabletModeAvailable NOTIFY environmentChanged)
    Q_PROPERTY(bool tabletModeActive READ tabletModeActive NOTIFY environmentChanged)
    // The power service holds the glass solid and magnification off (10 % battery or less).
    Q_PROPERTY(bool powerCritical READ powerCritical NOTIFY environmentChanged)
    // A Global Theme of Plasma Fusion is in use (the layout reset needs one).
    Q_PROPERTY(bool fusionLookAndFeel READ fusionLookAndFeel NOTIFY styleChanged)
    // An action (restore, layout reset) is running.
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    // Values of the properties above (QML compares plain integers).
    enum Style { OtherStyle = -1, LightStyle = 0, DarkStyle = 1, FollowSunset = 2 };
    Q_ENUM(Style)
    enum AccentMode { SchemeAccent = 0, CustomAccent = 1, WallpaperAccent = 2 };
    Q_ENUM(AccentMode)
    enum ButtonStyle { RightGlyphs = 0, LeftCircles = 1, ShowOnHover = 2 };
    Q_ENUM(ButtonStyle)
    enum SnapTrigger { SnapHold = 0, SnapHover = 1 };
    Q_ENUM(SnapTrigger)
    enum Glass { GlassFull = 0, GlassReduced = 1, GlassSolid = 2 };
    Q_ENUM(Glass)
    enum DndBehavior { DndAsk = 0, DndMove = 1 };
    Q_ENUM(DndBehavior)
    enum TabletMode { TabletAuto = 0, TabletOn = 1, TabletOff = 2 };
    Q_ENUM(TabletMode)
    enum TabletApps { AppsFullScreen = 0, AppsWindowed = 1 };
    Q_ENUM(TabletApps)
    enum TabletDock { DockHideOverApps = 0, DockAlwaysShow = 1 };
    Q_ENUM(TabletDock)
    enum KeyboardPolicy { KeyboardTablet = 0, KeyboardTouch = 1, KeyboardNever = 2 };
    Q_ENUM(KeyboardPolicy)

    explicit PlasmaFusionKcm(QObject *parent, const KPluginMetaData &metaData);
    ~PlasmaFusionKcm() override;

    int style() const;
    void setStyle(int style);
    int accentMode() const;
    QColor accentColor() const;
    QColor wallpaperColor() const;
    int buttonStyle() const;
    void setButtonStyle(int style);
    bool magnify() const;
    void setMagnify(bool magnify);
    bool globalMenu() const;
    void setGlobalMenu(bool globalMenu);
    bool hotCorner() const;
    void setHotCorner(bool hotCorner);
    bool shellLoading() const;
    bool shellRunning() const;
    bool dockAvailable() const;
    bool topBarAvailable() const;
    bool quickSettingsAvailable() const;
    bool folderAvailable() const;
    bool decorationInstalled() const;
    bool fusionDecoration() const;
    QString errorText() const;
    QString infoText() const;

    int snapTrigger() const;
    void setSnapTrigger(int value);
    int glass() const;
    void setGlass(int value);
    bool highContrast() const;
    void setHighContrast(bool value);
    bool reduceMotion() const;
    void setReduceMotion(bool value);
    int magnifiedSize() const;
    void setMagnifiedSize(int value);
    bool solidTopBar() const;
    void setSolidTopBar(bool value);
    bool everyScreen() const;
    void setEveryScreen(bool value);
    bool desktopIcons() const;
    void setDesktopIcons(bool value);
    int iconSize() const;
    void setIconSize(int value);
    int dndBehavior() const;
    void setDndBehavior(int value);
    bool lighterOnCritical() const;
    void setLighterOnCritical(bool value);
    int tabletMode() const;
    void setTabletMode(int value);
    int tabletApps() const;
    void setTabletApps(int value);
    int tabletDock() const;
    void setTabletDock(int value);
    int keyboardPolicy() const;
    void setKeyboardPolicy(int value);
    bool edgeLeft() const;
    void setEdgeLeft(bool value);
    bool edgeRight() const;
    void setEdgeRight(bool value);
    bool homeIndicator() const;
    void setHomeIndicator(bool value);

    bool highContrastAvailable() const;
    bool previousDesktopAvailable() const;
    bool topBarScriptAvailable() const;
    bool tabletModeAvailable() const;
    bool tabletModeActive() const;
    bool powerCritical() const;
    bool fusionLookAndFeel() const;
    bool busy() const;

    // Switch to the Plasma Fusion window decoration (when it is installed but another one is used).
    Q_INVOKABLE void useFusionDecoration();

    // The accent colour of the colour scheme (the Blue swatch: #2f6fdf in both Plasma Fusion schemes).
    Q_INVOKABLE void setSchemeAccent();
    // A fixed accent colour (the other swatches).
    Q_INVOKABLE void setCustomAccent(const QColor &color);
    // The accent colour Plasma takes from the wallpaper.
    Q_INVOKABLE void setWallpaperAccent();

    // Actions (the page asks for a confirmation first). Both run at once, not on Apply; a change
    // still pending on the page is kept.
    Q_INVOKABLE void restorePreviousDesktop();
    Q_INVOKABLE void resetLayout();

public Q_SLOTS:
    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void styleChanged();
    void accentChanged();
    void wallpaperColorChanged();
    void buttonStyleChanged();
    void magnifyChanged();
    void globalMenuChanged();
    void hotCornerChanged();
    void shellStateChanged();
    void decorationInstalledChanged();
    void errorTextChanged();
    void infoTextChanged();
    void stateChanged();
    void environmentChanged();
    void busyChanged();

private Q_SLOTS:
    // KWin's TabletModeManager signals (connected by name).
    void onTabletModeSignal(bool active);
    void onTabletModeAvailableSignal(bool available);

private:
    struct State {
        // Appearance (the board)
        int style = DarkStyle;
        int accentMode = SchemeAccent;
        QColor accentColor;
        int buttonStyle = RightGlyphs;
        bool fusionDecoration = false;
        bool magnify = true;
        bool globalMenu = true;
        bool hotCorner = false;
        // Configuration files
        int snapTrigger = SnapHold;
        int glass = GlassFull;
        bool highContrast = false;
        bool reduceMotion = false;
        bool everyScreen = true;
        int dndBehavior = DndAsk;
        bool lighterOnCritical = true;
        int tabletMode = TabletAuto;
        int tabletApps = AppsFullScreen;
        int tabletDock = DockHideOverApps;
        bool edgeLeft = false;
        bool edgeRight = false;
        // Plasma shell (widgets and panels)
        int magnifiedSize = 62;
        bool solidTopBar = true;
        bool desktopIcons = true;
        int iconSize = 2;
        int keyboardPolicy = KeyboardTablet;
        bool homeIndicator = true;

        bool sameAccent(const State &other) const;
        bool operator==(const State &other) const;
    };

    bool isSaveNeeded() const override;
    bool isDefaults() const override;
    State defaultState() const;

    template<typename T>
    void setField(T State::*field, T value);

    void loadConfigState(State &state) const;
    void copyConfigState(const State &from, State &to) const;
    void requestShellState();
    void shellStateArrived(QDBusPendingCallWatcher *watcher);
    void requestWallpaperColor();
    void requestTabletState();
    void updateEnvironment();
    void emitAll();
    void setErrorText(const QString &text);
    void addError(const QString &text);
    void setInfoText(const QString &text);
    void setBusy(bool busy);
    void onConfigChanged(const KConfigGroup &group, const QByteArrayList &names);

    bool applyStyle(int style);
    bool applyColorScheme(bool highContrast);
    bool applyAccent(const State &state);
    bool applyDecoration(int buttonStyle);
    void applySnapTrigger(int trigger);
    void applyHotCorner(bool on);
    void reconfigureKWin(bool overviewEffect);
    void applyGlassConfig(int glass);
    void applyReduceMotion(bool on);
    void applyDndBehavior(int behavior);
    void applyLighterOnCritical(bool on);
    void applyTabletConfig(const State &before, const State &after);
    bool applyMagnify(bool on);
    bool applyMagnifiedSize(int size);
    bool applyGlobalMenu(bool on);
    bool applyPanels(int glass, bool solidTopBar, bool widgetGlass);
    bool applyEveryScreen(bool on);
    bool applyDesktop(const State &before, const State &after);
    bool applyWidgetKey(const QString &plugin, const QString &key, const QString &jsValue, const QString &what);
    QString evaluateShellScript(const QString &script, bool *ok) const;
    bool runTool(const QString &program, const QStringList &arguments);
    bool currentVariantIsLight() const;
    void updateDecorationInstalled();
    QString topBarScriptPath() const;

    // Global shortcuts of widgets (Reset Fusion layout).
    QJsonObject widgetShortcuts(bool *ok) const;
    QString giveWidgetShortcut(int widgetId, const QString &key, const QList<int> &liveWidgetIds);
    void finishResetLayout(const QJsonObject &before);
    void pollResetLayout(const QJsonObject &before, int attempt);

    State m_current;
    State m_saved;
    QColor m_wallpaperColor;
    bool m_shellLoading = false;
    bool m_shellRunning = true;
    bool m_dockAvailable = false;
    bool m_topBarAvailable = false;
    bool m_quickSettingsAvailable = false;
    bool m_folderAvailable = false;
    bool m_decorationInstalled = false;
    bool m_highContrastAvailable = false;
    bool m_previousDesktopAvailable = false;
    bool m_tabletModeAvailable = false;
    bool m_tabletModeActive = false;
    bool m_powerCritical = false;
    bool m_busy = false;
    bool m_saving = false;
    QString m_errorText;
    QString m_infoText;
    int m_shellRequest = 0;
    // The dock and top-bar switches are read again when the Plasma shell (re)starts.
    QDBusServiceWatcher *m_shellWatcher = nullptr;
    QTimer m_shellRetryTimer;

    KConfigWatcher::Ptr m_globalsWatcher;
    KConfigWatcher::Ptr m_kwinWatcher;
    KConfigWatcher::Ptr m_fusionWatcher;
    QTimer m_reloadTimer;
    // After "Follow sunset" is applied, Plasma switches the Global Theme on its own, which puts
    // the Global Theme's window decoration back; the applied window-button choice (m_saved, also
    // when it is applied again meanwhile) is put back when that happens within this time.
    QDeadlineTimer m_reapplyDecorationUntil;
    bool reapplyingDecoration() const;
    void restoreDecorationIfReplaced();
};
