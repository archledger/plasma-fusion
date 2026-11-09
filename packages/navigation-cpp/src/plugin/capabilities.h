// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QMetaType>
#include <QObject>
#include <QVariant>

namespace KWin
{

// A matching version string does not establish the fork's compositor-opacity semantics.
inline bool fusionSupportsOffscreenOpacity(const QObject *effect)
{
    const QVariant version = effect ? effect->property("plasmaFusionOffscreenOpacityVersion") : QVariant();
    return version.metaType().id() == QMetaType::Int && version.toInt() >= 1;
}

} // namespace KWin
