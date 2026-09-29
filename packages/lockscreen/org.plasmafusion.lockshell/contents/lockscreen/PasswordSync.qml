/*
    SPDX-FileCopyrightText: 2025 Yifan Zhu <fanzhuyifan@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma Singleton

import QtQuick

// Keeps the password text of every screen's lock view in sync (one engine, one instance).
QtObject {
    property string password
}
