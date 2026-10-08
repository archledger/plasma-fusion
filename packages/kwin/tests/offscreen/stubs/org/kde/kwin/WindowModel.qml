// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

ListModel {
    dynamicRoles: true
    Component.onCompleted: {
        for (const win of Workspace.windows) {
            append({window: win});
        }
    }
}
