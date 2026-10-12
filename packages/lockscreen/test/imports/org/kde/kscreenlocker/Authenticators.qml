// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick

// Test stand-in: Plasma 6.8's PamAuthenticators::Authenticator enum (the ways to unlock).
QtObject {
    enum Authenticator {
        Regular,
        Fingerprint,
        Smartcard,
        Face,
        Universal2Factor
    }
}
