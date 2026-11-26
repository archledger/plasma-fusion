/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    Plasma Fusion: the banner keyboard triage (SPEC-notification-triage.md) is offered only while
    the running Plasma is the one this copy of the applet was built from.
    PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION is the version of KDE's applets/notifications tree this
    package holds (README.md). plasmashell's own version is that of the plasma-workspace it was
    built from, as KWin's is for the navigation effect.
*/

#pragma once

#include <QCoreApplication>
#include <QString>

namespace PlasmaFusion
{
inline bool bannerTriageAvailable(const QString &runningVersion, const QString &builtVersion)
{
    return !runningVersion.isEmpty() && runningVersion == builtVersion;
}

inline bool bannerTriageAvailable()
{
    return bannerTriageAvailable(QCoreApplication::applicationVersion(), QStringLiteral(PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION));
}
}
