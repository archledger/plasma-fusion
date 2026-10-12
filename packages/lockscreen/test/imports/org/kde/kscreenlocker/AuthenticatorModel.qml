// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma Singleton
import QtQuick

// Test stand-in for Plasma 6.8's PAMAuthenticatorModel: one row per way to unlock, with the same
// roles. The rows come from the mock authenticator's `ways` (MockAuthenticator68.qml).
ListModel {
    id: model

    function setFunctional(type, functional) {
        for (let i = 0; i < count; ++i) {
            if (get(i).type === type) {
                setProperty(i, "functional", functional);
            }
        }
    }

    Component.onCompleted: {
        // qmllint disable unqualified
        const ways = typeof authenticator !== "undefined" && authenticator.ways ? authenticator.ways : [];
        // qmllint enable unqualified
        for (const way of ways) {
            append(way);
        }
    }
}
