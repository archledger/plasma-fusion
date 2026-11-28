/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>

// Empty on success. Checks load, stock identity and embedded resources, not QML instantiation.
QString checkNotificationPlugin(const QString &absolutePath);
