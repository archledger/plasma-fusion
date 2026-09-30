/*
    Plasma Fusion settings module: helpers shared by kcm.cpp and shell.cpp.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QDBusMessage>
#include <QLoggingCategory>
#include <QString>
#include <QStringList>

Q_DECLARE_LOGGING_CATEGORY(KCM_PLASMAFUSION)

namespace PlasmaFusion
{
using namespace Qt::StringLiterals;

inline const QString s_darkLookAndFeel = u"org.plasmafusion.dark.desktop"_s;
inline const QString s_lightLookAndFeel = u"org.plasmafusion.light.desktop"_s;
inline const QString s_previousLookAndFeel = u"org.plasmafusion.previous.desktop"_s;

// Colour schemes of the two Global Themes and the high-contrast scheme (style part).
inline const QString s_darkScheme = u"PlasmaFusionDark"_s;
inline const QString s_lightScheme = u"PlasmaFusionLight"_s;
inline const QString s_highContrastScheme = u"PlasmaFusionHighContrast"_s;

// ~/.config/plasmafusionrc (shared with the decoration, the power service and the layout).
inline const QString s_fusionConfig = u"plasmafusionrc"_s;

// The KWin script of the tablet lane and its shortcut (TABLET.md 4.2).
inline const QString s_tabletScriptGroup = u"Script-plasmafusion-tablet"_s;
inline const QString s_tabletShortcut = u"Plasma Fusion: Tablet Window Mode"_s;

// Widgets whose [General] glass key follows the Glass level (EFFECTS.md 2).
inline const QStringList s_glassWidgets = {
    u"org.plasmafusion.dock"_s,
    u"org.plasmafusion.quicksettings"_s,
    u"org.plasmafusion.launcher"_s,
    u"org.plasmafusion.systemcard"_s,
};

// Folder View hides every item with filterMode 1 ("show files matching") and this pattern:
// QRegularExpression::fromWildcard anchors it, and no file name can be "/".
inline const QString s_hideAllPattern = u"/"_s;

inline constexpr int s_dbusTimeout = 5000;
inline constexpr int s_toolTimeout = 60000;

inline QDBusMessage shellScriptMessage(const QString &script)
{
    QDBusMessage message =
        QDBusMessage::createMethodCall(u"org.kde.plasmashell"_s, u"/PlasmaShell"_s, u"org.kde.PlasmaShell"_s, u"evaluateScript"_s);
    message << script;
    return message;
}

// evaluateScript returns everything the script printed; the result is the last line.
inline QString lastLine(const QString &output)
{
    const QStringList lines = output.trimmed().split(u'\n', Qt::SkipEmptyParts);
    return lines.isEmpty() ? QString() : lines.constLast().trimmed();
}

// A string as a JavaScript literal (for values put into a shell script).
QString jsString(const QString &value);
} // namespace PlasmaFusion
