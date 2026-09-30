/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Two columns of 52 px recent-file rows with a 6 px gap (Launcher board, "Recommended"); the
// row height follows the user's text size.
NavGrid {
    columns: 2
    gap: 6
    itemHeight: metrics ? metrics.px(52) : 52
    delegate: DocItem {}
}
