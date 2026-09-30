/*
    Plasma Fusion settings module: the Appearance page of the Plasma Fusion design.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KConfigWatcher>
#include <KQuickManagedConfigModule>

#include <QColor>
#include <QDeadlineTimer>
#include <QString>
#include <QTimer>

class QDBusPendingCallWatcher;
class QDBusServiceWatcher;

/*
    Everything on the page is read from the session when the module loads and written only when
    Apply is pressed:

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
      Dock            the org.plasmafusion.dock widgets' [General] magnify key (desktop scripting).
      Global menu     org.kde.plasma.appmenu right after org.plasmafusion.appname in the top bar.
      Hot corner      kwinrc [Effect-overview] BorderActivate 7 (top-left corner) or 9 (none).
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
    Q_PROPERTY(bool decorationInstalled READ decorationInstalled NOTIFY decorationInstalledChanged)
    // The Plasma Fusion decoration is (or will be, after Apply) KWin's window decoration.
    Q_PROPERTY(bool fusionDecoration READ fusionDecoration NOTIFY buttonStyleChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)

public:
    // Values of the properties above (QML compares plain integers).
    enum Style { OtherStyle = -1, LightStyle = 0, DarkStyle = 1, FollowSunset = 2 };
    Q_ENUM(Style)
    enum AccentMode { SchemeAccent = 0, CustomAccent = 1, WallpaperAccent = 2 };
    Q_ENUM(AccentMode)
    enum ButtonStyle { RightGlyphs = 0, LeftCircles = 1, ShowOnHover = 2 };
    Q_ENUM(ButtonStyle)

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
    bool decorationInstalled() const;
    bool fusionDecoration() const;
    QString errorText() const;

    // Switch to the Plasma Fusion window decoration (when it is installed but another one is used).
    Q_INVOKABLE void useFusionDecoration();

    // The accent colour of the colour scheme (the Blue swatch: #2f6fdf in both Plasma Fusion schemes).
    Q_INVOKABLE void setSchemeAccent();
    // A fixed accent colour (the other swatches).
    Q_INVOKABLE void setCustomAccent(const QColor &color);
    // The accent colour Plasma takes from the wallpaper.
    Q_INVOKABLE void setWallpaperAccent();

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

private:
    struct State {
        int style = DarkStyle;
        int accentMode = SchemeAccent;
        QColor accentColor;
        int buttonStyle = RightGlyphs;
        bool fusionDecoration = false;
        bool magnify = true;
        bool globalMenu = true;
        bool hotCorner = false;
        bool sameAccent(const State &other) const;
        bool operator==(const State &other) const;
    };

    bool isSaveNeeded() const override;
    bool isDefaults() const override;

    void loadConfigState(State &state) const;
    void requestShellState();
    void shellStateArrived(QDBusPendingCallWatcher *watcher);
    void requestWallpaperColor();
    void emitAll();
    void setErrorText(const QString &text);
    void addError(const QString &text);
    void onConfigChanged(const KConfigGroup &group, const QByteArrayList &names);

    bool applyStyle(int style);
    bool applyAccent(const State &state);
    bool applyDecoration(int buttonStyle);
    void applyHotCorner(bool on);
    bool applyMagnify(bool on);
    bool applyGlobalMenu(bool on);
    void reconfigureKWin(bool overviewEffect);
    QString evaluateShellScript(const QString &script, bool *ok) const;
    bool runTool(const QString &program, const QStringList &arguments);
    bool currentVariantIsLight() const;
    void updateDecorationInstalled();

    State m_current;
    State m_saved;
    QColor m_wallpaperColor;
    bool m_shellLoading = false;
    bool m_shellRunning = true;
    bool m_dockAvailable = false;
    bool m_topBarAvailable = false;
    bool m_decorationInstalled = false;
    bool m_saving = false;
    QString m_errorText;
    int m_shellRequest = 0;
    // The dock and top-bar switches are read again when the Plasma shell (re)starts.
    QDBusServiceWatcher *m_shellWatcher = nullptr;
    QTimer m_shellRetryTimer;

    KConfigWatcher::Ptr m_globalsWatcher;
    KConfigWatcher::Ptr m_kwinWatcher;
    QTimer m_reloadTimer;
    // After "Follow sunset" is applied, Plasma switches the Global Theme on its own, which puts
    // the Global Theme's window decoration back; the applied window-button choice (m_saved, also
    // when it is applied again meanwhile) is put back when that happens within this time.
    QDeadlineTimer m_reapplyDecorationUntil;
    bool reapplyingDecoration() const;
    void restoreDecorationIfReplaced();
};
