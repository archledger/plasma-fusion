/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Six-column grid of 84 px app tiles with a 4 px gap (Launcher board).
NavGrid {
    columns: 6
    gap: 4
    itemHeight: 84
    delegate: AppTile {}
}
