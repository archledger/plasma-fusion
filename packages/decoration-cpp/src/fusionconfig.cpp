/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "fusionconfig.h"

#include <KConfig>
#include <KConfigGroup>

#include <QTimer>

namespace PlasmaFusion
{

namespace
{
FusionConfig s_config;
bool s_loaded = false;
bool s_readThisBurst = false;

FusionConfig readConfig()
{
    FusionConfig c;

    // Fresh KConfig objects: never touch KWin's own shared kwinrc instance.
    KConfig fusionrc(QStringLiteral("plasmafusionrc"), KConfig::NoGlobals);
    const KConfigGroup deco(&fusionrc, QStringLiteral("Decoration"));
    c.buttonStyle = FusionConfig::parseStyle(deco.readEntry("ButtonStyle", QStringLiteral("RightGlyphs")));
    c.snapLayoutsOnHover = deco.readEntry("SnapLayoutsOnHover", true);

    KConfig kwinrc(QStringLiteral("kwinrc"), KConfig::NoGlobals);
    const KConfigGroup plugins(&kwinrc, QStringLiteral("Plugins"));
    c.snapScriptEnabled = plugins.readEntry("plasmafusion-snapEnabled", false);

    // Cascaded like KWin's own read (user file over kdedefaults and /etc/xdg).
    KConfig globals(QStringLiteral("kdeglobals"), KConfig::CascadeConfig);
    const KConfigGroup kde(&globals, QStringLiteral("KDE"));
    c.animationFactor = qBound(0.0, kde.readEntry("AnimationDurationFactor", 1.0), 10.0);
    return c;
}
} // namespace

ButtonStyle FusionConfig::parseStyle(const QString &value)
{
    const QString v = value.trimmed();
    if (v.compare(QLatin1String("LeftCircles"), Qt::CaseInsensitive) == 0) {
        return ButtonStyle::LeftCircles;
    }
    if (v.compare(QLatin1String("ShowOnHover"), Qt::CaseInsensitive) == 0) {
        return ButtonStyle::ShowOnHover;
    }
    return ButtonStyle::RightGlyphs;
}

const FusionConfig &FusionConfig::self()
{
    if (!s_loaded) {
        reload();
    }
    return s_config;
}

void FusionConfig::reload()
{
    // Every decoration reacts to the same reconfigure signal, all in one event-loop pass: read the
    // files once for that pass.
    if (s_loaded && s_readThisBurst) {
        return;
    }
    s_config = readConfig();
    s_loaded = true;
    s_readThisBurst = true;
    QTimer::singleShot(0, [] {
        s_readThisBurst = false;
    });
}

} // namespace PlasmaFusion
