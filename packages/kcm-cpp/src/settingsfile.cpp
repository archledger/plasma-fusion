/*
    Plasma Fusion settings module: the settings file ("Export my settings…" and "Import
    settings…" at the end of the page).

    A settings file is one JSON object:
      {"format": "plasma-fusion-settings", "version": 1, "settings": {...}, "layout": {...}}
    "settings" holds the page's settings by their property names (kcm.h): numbers for the choices
    (the enums there), true/false for the switches, and the accent (accentMode, with accentColor
    "#rrggbb" for a fixed colour), fusionDecoration and decoration (the kwinrc
    [org.kde.kdecoration2] keys library, theme, ButtonsOnLeft and ButtonsOnRight: put back when
    the file was made with another decoration than Plasma Fusion's); a setting the file does not
    name stays as it is. "layout" is what the Global Theme's export-layout.js prints, and
    import-layout.js puts it in place (both explain it).

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kcm.h"
#include "kcm_p.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KPluginMetaData>
#include <KSharedConfig>

#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <cmath>
#include <limits>

using namespace Qt::StringLiterals;
using namespace PlasmaFusion;

namespace
{
const QString s_format = u"plasma-fusion-settings"_s;
constexpr int s_version = 1;
// A settings file is some KiB (every widget's configuration included); a larger file is not one.
constexpr qint64 s_maxFileSize = 8 * 1024 * 1024;

QString localPath(const QString &location)
{
    const QUrl url = QUrl::fromUserInput(location, QString(), QUrl::AssumeLocalFile);
    return url.isLocalFile() ? url.toLocalFile() : QString();
}

// Waits MS without taking user input, as evaluateShellScript waits for the shell.
void waitWithoutInput(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec(QEventLoop::ExcludeUserInputEvents);
}

// A whole number that fits an int.
bool wholeNumber(const QJsonValue &value, int *number)
{
    const double d = value.toDouble();
    if (!value.isDouble() || std::floor(d) != d || d < std::numeric_limits<int>::min() || d > std::numeric_limits<int>::max()) {
        return false;
    }
    *number = int(d);
    return true;
}
bool wholeNumber(const QJsonValue &value)
{
    int number = 0;
    return wholeNumber(value, &number);
}

// A list of configuration groups (export-layout.js's GROUP), or none.
bool validConfig(const QJsonValue &config)
{
    if (config.isUndefined()) {
        return true;
    }
    if (!config.isArray()) {
        return false;
    }
    for (const QJsonValue &value : config.toArray()) {
        const QJsonObject group = value.toObject();
        if (!value.isObject() || !group.value(u"group"_s).isArray() || !group.value(u"keys"_s).isObject()) {
            return false;
        }
        for (const QJsonValue &name : group.value(u"group"_s).toArray()) {
            if (!name.isString() || name.toString().isEmpty()) {
                return false;
            }
        }
        for (const QJsonValue &text : group.value(u"keys"_s).toObject()) {
            if (!text.isString()) {
                return false;
            }
        }
    }
    return true;
}

// Why LAYOUT is not a layout import-layout.js takes, or "" when it is one.
QString layoutProblem(const QJsonObject &layout)
{
    if (layout.value(u"version"_s).toInt() != 1) {
        return i18nc("@info reason", "its panels are of another version");
    }
    const QJsonValue panels = layout.value(u"panels"_s);
    if (!panels.isArray() || panels.toArray().isEmpty()) {
        return i18nc("@info reason", "it has no panels");
    }
    // Every value import-layout.js gives the new panel, as plasma-workspace 6.7.5's Panel
    // (shell/scripting/panel.cpp) takes it: the panels there are are removed before the file's
    // are added, so a value that would fail or be taken for another must not get that far.
    static const QStringList locations = {u"top"_s, u"bottom"_s, u"left"_s, u"right"_s};
    static const QHash<QString, QStringList> choices = {
        {u"lengthMode"_s, {u"fill"_s, u"fit"_s, u"custom"_s}},
        {u"alignment"_s, {u"left"_s, u"center"_s, u"right"_s}},
        {u"hiding"_s, {u"none"_s, u"autohide"_s, u"dodgewindows"_s, u"windowsgobelow"_s}},
        {u"opacity"_s, {u"adaptive"_s, u"opaque"_s, u"translucent"_s}},
    };
    for (const QJsonValue &value : panels.toArray()) {
        const QJsonObject panel = value.toObject();
        bool complete = value.isObject() && wholeNumber(panel.value(u"screen"_s)) && locations.contains(panel.value(u"location"_s).toString())
            && wholeNumber(panel.value(u"height"_s)) && panel.value(u"height"_s).toInt() > 0 && panel.value(u"floating"_s).isBool()
            && panel.value(u"floatingApplets"_s).isBool() && panel.value(u"widgets"_s).isArray() && validConfig(panel.value(u"config"_s));
        for (auto it = choices.cbegin(); it != choices.cend(); ++it) {
            complete = complete && it.value().contains(panel.value(it.key()).toString());
        }
        if (panel.value(u"lengthMode"_s).toString() == u"custom") {
            for (const QString &length : {u"offset"_s, u"length"_s, u"minimumLength"_s, u"maximumLength"_s}) {
                complete = complete && wholeNumber(panel.value(length));
            }
        }
        for (const QJsonValue &entry : panel.value(u"widgets"_s).toArray()) {
            const QJsonObject widget = entry.toObject();
            complete = complete && entry.isObject() && !widget.value(u"type"_s).toString().isEmpty()
                && (widget.value(u"shortcut"_s).isUndefined() || widget.value(u"shortcut"_s).isString()) && validConfig(widget.value(u"config"_s));
        }
        if (!complete) {
            return i18nc("@info reason", "a panel in it is not complete");
        }
    }
    return {};
}

// The settings file at PATH in *FILE, or why it is not one.
QString readSettingsFile(const QString &path, QJsonObject *file)
{
    QFile in(path);
    if (path.isEmpty() || !in.open(QIODevice::ReadOnly)) {
        return path.isEmpty() ? i18nc("@info reason", "it is not a local file") : in.errorString();
    }
    if (in.size() > s_maxFileSize) {
        return i18nc("@info reason", "it is not a Plasma Fusion settings file");
    }
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(in.readAll(), &error);
    *file = document.object();
    if (error.error != QJsonParseError::NoError || !document.isObject() || file->value(u"format"_s).toString() != s_format) {
        return i18nc("@info reason", "it is not a Plasma Fusion settings file");
    }
    if (file->value(u"version"_s).toInt() != s_version) {
        return i18nc("@info reason", "it is of another version of Plasma Fusion");
    }
    if (!file->value(u"settings"_s).isObject() || !file->value(u"layout"_s).isObject()) {
        return i18nc("@info reason", "it is not complete");
    }
    return layoutProblem(file->value(u"layout"_s).toObject());
}

} // namespace

const QList<PlasmaFusionKcm::FileSetting> &PlasmaFusionKcm::fileSettings()
{
    // High contrast comes before the glass: it selects Solid glass, which the glass of the file
    // then sets (as on the page, where the glass can be changed after it).
    static const QList<FileSetting> settings = {
        {"style", &State::style, nullptr},
        {"buttonStyle", &State::buttonStyle, nullptr},
        {"magnify", nullptr, &State::magnify},
        {"globalMenu", nullptr, &State::globalMenu},
        {"hotCorner", nullptr, &State::hotCorner},
        {"snapTrigger", &State::snapTrigger, nullptr},
        {"highContrast", nullptr, &State::highContrast},
        {"glass", &State::glass, nullptr},
        {"iconsMode", &State::iconsMode, nullptr},
        {"lockNotifications", nullptr, &State::lockNotifications},
        {"lockNotificationSummaries", nullptr, &State::lockNotificationSummaries},
        {"reduceMotion", nullptr, &State::reduceMotion},
        {"magnifiedSize", &State::magnifiedSize, nullptr},
        {"solidTopBar", nullptr, &State::solidTopBar},
        {"systemMeters", nullptr, &State::systemMeters},
        {"everyScreen", nullptr, &State::everyScreen},
        {"everyDock", nullptr, &State::everyDock},
        {"desktopIcons", nullptr, &State::desktopIcons},
        {"iconSize", &State::iconSize, nullptr},
        {"dndBehavior", &State::dndBehavior, nullptr},
        {"lighterOnCritical", nullptr, &State::lighterOnCritical},
        {"fileContentIndexing", nullptr, &State::fileContentIndexing},
        {"tabletMode", &State::tabletMode, nullptr},
        {"tabletApps", &State::tabletApps, nullptr},
        {"tabletDock", &State::tabletDock, nullptr},
        {"keyboardPolicy", &State::keyboardPolicy, nullptr},
        {"edgeLeft", nullptr, &State::edgeLeft},
        {"edgeRight", nullptr, &State::edgeRight},
        {"homeIndicator", nullptr, &State::homeIndicator},
        {"launcherRecentFiles", nullptr, &State::launcherRecentFiles},
        {"launcherRecentApps", nullptr, &State::launcherRecentApps},
        {"launcherPlaces", nullptr, &State::launcherPlaces},
    };
    return settings;
}

QJsonObject PlasmaFusionKcm::settingsToFile(const State &state) const
{
    QJsonObject settings;
    for (const FileSetting &setting : fileSettings()) {
        const QString name = QString::fromLatin1(setting.name);
        if (setting.number) {
            settings.insert(name, state.*setting.number);
        } else {
            settings.insert(name, state.*setting.flag);
        }
    }
    // Another Global Theme than Plasma Fusion's is no style of the page.
    if (state.style == OtherStyle) {
        settings.remove(u"style"_s);
    }
    settings.insert(u"accentMode"_s, state.accentMode);
    if (state.accentMode == CustomAccent && state.accentColor.isValid()) {
        settings.insert(u"accentColor"_s, state.accentColor.name());
    }
    settings.insert(u"fusionDecoration"_s, state.fusionDecoration);
    // The decoration KWin uses, for a file made with another one than Plasma Fusion's.
    KSharedConfig::Ptr kwin = KSharedConfig::openConfig(u"kwinrc"_s);
    kwin->reparseConfiguration();
    const KConfigGroup group(kwin, s_kwinDecorationGroup);
    QJsonObject decoration;
    for (const char *key : {"library", "theme", "ButtonsOnLeft", "ButtonsOnRight"}) {
        if (group.hasKey(key)) {
            decoration.insert(QString::fromLatin1(key), group.readEntry(key, QString()));
        }
    }
    settings.insert(u"decoration"_s, decoration);
    return settings;
}

int PlasmaFusionKcm::settingsFromFile(const QJsonObject &settings, QStringList *notes)
{
    int notTaken = 0;
    for (const FileSetting &setting : fileSettings()) {
        const QJsonValue value = settings.value(QString::fromLatin1(setting.name));
        if (value.isUndefined()) {
            continue;
        }
        if (setting.flag && value.isBool()) {
            if (value.toBool() && setting.flag == &State::highContrast && !m_highContrastAvailable) {
                notes->append(i18nc("@info", "High contrast is not installed on this computer, so it is off."));
                continue;
            }
            // The setters take what the page can show (as when it is set there).
            setProperty(setting.name, value.toBool());
            notTaken += m_current.*setting.flag == value.toBool() ? 0 : 1;
            continue;
        }
        int number = 0;
        if (setting.number && wholeNumber(value, &number)) {
            setProperty(setting.name, number);
            notTaken += m_current.*setting.number == number ? 0 : 1;
            continue;
        }
        ++notTaken;
    }

    const QJsonValue accent = settings.value(u"accentMode"_s);
    int mode = -1;
    if (!accent.isUndefined() && wholeNumber(accent, &mode)) {
        const QColor color = QColor::fromString(settings.value(u"accentColor"_s).toString());
        if (mode == SchemeAccent) {
            setSchemeAccent();
        } else if (mode == WallpaperAccent) {
            setWallpaperAccent();
        } else if (mode == CustomAccent && color.isValid()) {
            setCustomAccent(color);
        } else {
            ++notTaken;
        }
    } else if (!accent.isUndefined()) {
        ++notTaken;
    }

    const QJsonValue fusionDecoration = settings.value(u"fusionDecoration"_s);
    if (fusionDecoration.toBool()) {
        if (m_decorationInstalled) {
            useFusionDecoration();
        } else {
            notes->append(i18nc("@info", "The Plasma Fusion window decoration is not installed on this computer."));
        }
    } else if (!fusionDecoration.isUndefined() && !fusionDecoration.isBool()) {
        ++notTaken;
    }
    return notTaken;
}

int PlasmaFusionKcm::applyFileDecoration(const QJsonObject &settings, QStringList *notes)
{
    if (settings.value(u"fusionDecoration"_s) != QJsonValue(false)) {
        return 0;
    }
    // Apply puts Plasma Fusion's decoration on whenever it is installed; a file made with
    // another one gets that one back, when it is here (its plugin; an Aurorae SVG theme: the
    // theme's folder, as applyDecoration checks the fallback's).
    const QJsonObject decoration = settings.value(u"decoration"_s).toObject();
    const QString library = decoration.value(u"library"_s).toString();
    const QString theme = decoration.value(u"theme"_s).toString();
    bool valid = !library.isEmpty() && library != s_decorationId;
    for (auto it = decoration.constBegin(); it != decoration.constEnd(); ++it) {
        valid = valid && it.value().isString();
    }
    if (!valid) {
        return 1;
    }
    const bool installed = library.startsWith(u"org.kde.kwin.aurorae"_s) && theme.startsWith(s_auroraeThemePrefix)
        ? !QStandardPaths::locate(QStandardPaths::GenericDataLocation,
                                  u"aurorae/themes/"_s + theme.mid(s_auroraeThemePrefix.size()),
                                  QStandardPaths::LocateDirectory)
               .isEmpty()
        : KPluginMetaData::findPluginById(s_decorationNamespace, library).isValid();
    if (!installed) {
        notes->append(
            i18nc("@info %1 decoration", "The window decoration of the file (%1) is not installed on this computer.", theme.isEmpty() ? library : theme));
        return 0;
    }
    KSharedConfig::Ptr kwin = KSharedConfig::openConfig(u"kwinrc"_s);
    kwin->reparseConfiguration();
    KConfigGroup group(kwin, s_kwinDecorationGroup);
    for (const char *key : {"library", "theme", "ButtonsOnLeft", "ButtonsOnRight"}) {
        const QJsonValue value = decoration.value(QString::fromLatin1(key));
        if (value.isString()) {
            group.writeEntry(key, value.toString(), KConfig::Notify);
        } else {
            group.deleteEntry(key, KConfig::Notify);
        }
    }
    group.writeEntry("NoPlugin", false, KConfig::Notify);
    kwin->sync();
    reconfigureKWin(false);
    // The decoration chosen: not put back when "Follow sunset" switches the Global Theme now
    // (restoreDecorationIfReplaced).
    m_reapplyDecorationUntil = QDeadlineTimer();
    m_current.fusionDecoration = false;
    m_saved.fusionDecoration = false;
    Q_EMIT buttonStyleChanged();
    return 0;
}

void PlasmaFusionKcm::keepPanelChoices(const QJsonObject &settings)
{
    // Apply turns "Dock on every screen" on only with a dock to copy, and keeps the top bar's
    // opacity choice only with a top bar; on a desktop without them the file's choice would be
    // lost, though its panels bring them. finishResetLayout and ensure-topbars.js read the choice
    // from plasmafusionrc once the panels are there.
    const struct {
        const char *name;
        bool State::*field;
        const char *group;
        const char *key;
    } choices[] = {
        {"everyDock", &State::everyDock, "Dock", "EveryScreen"},
        {"solidTopBar", &State::solidTopBar, "TopBar", "SolidNextToWindows"},
    };
    KSharedConfig::Ptr fusion = KSharedConfig::openConfig(s_fusionConfig, KConfig::NoGlobals);
    fusion->reparseConfiguration();
    bool changed = false;
    for (const auto &choice : choices) {
        const QJsonValue value = settings.value(QString::fromLatin1(choice.name));
        if (!value.isBool() || m_saved.*choice.field == value.toBool()) {
            continue;
        }
        KConfigGroup(fusion, QString::fromLatin1(choice.group)).writeEntry(choice.key, value.toBool(), KConfig::Notify);
        m_current.*choice.field = value.toBool();
        m_saved.*choice.field = value.toBool();
        changed = true;
    }
    if (changed) {
        fusion->sync();
        Q_EMIT stateChanged();
    }
}

bool PlasmaFusionKcm::settingsFileAvailable() const
{
    return !layoutScriptPath(u"export-layout.js"_s).isEmpty() && !layoutScriptPath(u"import-layout.js"_s).isEmpty();
}

bool PlasmaFusionKcm::exportSettings(const QString &location)
{
    if (m_busy) {
        return false;
    }
    setErrorText(QString());
    setInfoText(QString());
    if (!m_shellRunning) {
        addError(i18nc("@info", "The settings cannot be exported while the Plasma desktop is not running."));
        return false;
    }
    const QString path = localPath(location);
    if (path.isEmpty()) {
        addError(i18nc("@info", "The settings can only be saved in a local file."));
        return false;
    }
    QFile script(layoutScriptPath(u"export-layout.js"_s));
    if (script.fileName().isEmpty() || !script.open(QIODevice::ReadOnly)) {
        addError(i18nc("@info", "The settings cannot be exported: the Global Theme's export-layout.js is not installed."));
        return false;
    }
    bool ok = false;
    const QString result = evaluateShellScript(QString::fromUtf8(script.readAll()), &ok);
    const QJsonObject layout = QJsonDocument::fromJson(result.toUtf8()).object();
    if (!ok) {
        addError(i18nc("@info", "The panels could not be read: %1", result));
        return false;
    }
    if (layout.value(u"version"_s).toInt() == 1 && layout.value(u"panels"_s).toArray().isEmpty()) {
        addError(i18nc("@info", "The settings were not exported: no panel is on a connected screen."));
        return false;
    }
    const QString problem = layoutProblem(layout);
    if (!problem.isEmpty()) {
        addError(i18nc("@info %1 reason", "The panels could not be read: %1.", problem));
        return false;
    }

    // What is applied (m_saved), as the panels are.
    const QJsonObject root{
        {u"format"_s, s_format},
        {u"version"_s, s_version},
        {u"settings"_s, settingsToFile(m_saved)},
        {u"layout"_s, layout},
    };
    // No file an import refuses (readSettingsFile takes at most s_maxFileSize).
    const QByteArray bytes = QJsonDocument(root).toJson(QJsonDocument::Indented);
    if (bytes.size() > s_maxFileSize) {
        addError(i18nc("@info %1 size, %2 limit, in MiB",
                       "The settings were not exported: the file would be %1 MiB, more than the %2 MiB an import takes.",
                       QString::number(double(bytes.size()) / (1024 * 1024), 'f', 1),
                       QString::number(s_maxFileSize / (1024 * 1024))));
        return false;
    }
    QSaveFile out(path);
    if (!out.open(QIODevice::WriteOnly) || out.write(bytes) < 0 || !out.commit()) {
        addError(i18nc("@info %1 file, %2 reason", "%1 could not be written: %2", path, out.errorString()));
        return false;
    }
    QString info = i18nc("@info %1 file", "Your settings are saved in %1.", path);
    int away = 0;
    for (const QJsonValue &reason : layout.value(u"left"_s).toArray()) {
        away += reason.toString() == u"screen" ? 1 : 0;
    }
    if (away > 0) {
        info += u' '
            + i18ncp("@info",
                     "A panel of a screen that is not connected is not in the file.",
                     "%1 panels of screens that are not connected are not in the file.",
                     away);
    }
    setInfoText(info);
    return true;
}

void PlasmaFusionKcm::importSettings(const QString &location)
{
    if (m_busy) {
        return;
    }
    setErrorText(QString());
    setInfoText(QString());
    const QString path = localPath(location);
    const QString name = path.isEmpty() ? location : QFileInfo(path).fileName();
    QJsonObject file;
    const QString problem = readSettingsFile(path, &file);
    if (!problem.isEmpty()) {
        addError(i18nc("@info %1 file, %2 reason", "%1 cannot be imported: %2.", name, problem));
        return;
    }
    // Nothing of the file is used without the shell: its settings and panels go together.
    if (!m_shellRunning) {
        addError(i18nc("@info", "The settings cannot be imported while the Plasma desktop is not running."));
        return;
    }
    QFile script(layoutScriptPath(u"import-layout.js"_s));
    if (script.fileName().isEmpty() || !script.open(QIODevice::ReadOnly)) {
        addError(i18nc("@info", "The settings cannot be imported: the Global Theme's import-layout.js is not installed."));
        return;
    }
    const QString importScript = QString::fromUtf8(script.readAll());
    setBusy(true);

    // 1. The settings, as if set on the page, then applied (Apply clears the messages first).
    QStringList notes;
    const QJsonObject settings = file.value(u"settings"_s).toObject();
    int notTaken = settingsFromFile(settings, &notes);
    save();
    notTaken += applyFileDecoration(settings, &notes);
    keepPanelChoices(settings);

    // 2. The panels. The ids there are now: the new widgets' are all above them (finishResetLayout).
    bool ok = false;
    const QJsonObject now = widgetShortcuts(&ok);
    if (!ok) {
        addError(i18nc("@info", "The Plasma desktop did not answer."));
        setBusy(false);
        return;
    }
    const QJsonObject layout = file.value(u"layout"_s).toObject();
    const QJsonValue ids = now.value(u"ids"_s);
    const QJsonValue widgetsBefore = now.value(u"widgets"_s);

    // JSON is JavaScript but for these two characters, which QJSEngine refuses in a string literal
    // (Qt 6.11.2).
    QString json = QString::fromUtf8(QJsonDocument(layout).toJson(QJsonDocument::Compact));
    json.replace(QChar(0x2028), u"\\u2028"_s).replace(QChar(0x2029), u"\\u2029"_s);
    const QString layoutLine = u"var LAYOUT = "_s + json + u";\n"_s;
    // In two steps, as a layout reset (import-layout.js explains why): the panels there are go, and
    // a moment later, once the shell has deleted their widgets, the file's come. The steps run in
    // one go, waiting as evaluateShellScript waits (no user input meanwhile), not from timers of
    // the page: leaving the page or closing System Settings in between deletes the page, and a
    // timer of it would never fire, leaving no panels. Closing System Settings ends every event
    // loop at once (QCoreApplication::exit), so the waits then return at once and the steps
    // still run, the shell's answers being read as they come.
    const QString result = evaluateShellScript(layoutLine + u"var PHASE = \"remove\";\n"_s + importScript, &ok);
    const QJsonObject removed = QJsonDocument::fromJson(result.toUtf8()).object();
    if (!ok || !removed.value(u"removed"_s).isDouble()) {
        addError(i18nc("@info %1 reason", "The panels could not be imported: %1", ok ? removed.value(u"error"_s).toString(result) : result));
        setBusy(false);
        requestShellState();
        return;
    }
    waitWithoutInput(500);
    const QString added = evaluateShellScript(layoutLine + u"var PHASE = \"add\";\n"_s + importScript, &ok);
    const QJsonObject answer = QJsonDocument::fromJson(added.toUtf8()).object();
    if (!ok || !answer.value(u"panels"_s).isDouble()) {
        addError(i18nc("@info %1 reason",
                       "The panels of the file could not be added: %1. Reset Fusion layout brings Plasma Fusion's panels back.",
                       ok ? answer.value(u"error"_s).toString(added) : added));
        setBusy(false);
        requestShellState();
        return;
    }

    QStringList outcome{i18nc("@info %1 file name", "The settings of %1 are in place.", name)};
    QStringList notInstalled;
    for (const QJsonValue &type : answer.value(u"notInstalled"_s).toArray()) {
        notInstalled << type.toString();
    }
    if (!notInstalled.isEmpty()) {
        outcome << i18nc("@info %1 list of widget ids", "Widgets that are not installed here were left out: %1.", notInstalled.join(u", "_s));
    }
    const int leftOut = answer.value(u"leftOut"_s).toInt();
    if (leftOut > 0) {
        outcome << i18ncp("@info",
                          "A panel was left out: its screen is not connected, and the first screen has a panel at that edge.",
                          "%1 panels were left out: their screens are not connected, and the first screen has panels at those edges.",
                          leftOut);
    }
    if (notTaken > 0) {
        outcome << i18ncp("@info",
                          "One setting in the file has a value this version does not take; it stays as it was.",
                          "%1 settings in the file have values this version does not take; they stay as they were.",
                          notTaken);
    }
    outcome << notes;
    // As after a layout reset: a moment for the new widgets to start, then their shortcuts (each
    // widget made gets the key the file gives it; import-layout.js lists them by id).
    waitWithoutInput(1000);
    finishResetLayout(QJsonObject{{u"ids"_s, ids}, {u"widgets"_s, widgetsBefore}, {u"assign"_s, answer.value(u"keys"_s).toArray()}}, true, outcome.join(u' '));
}
