// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick

// Test stand-in: only the enum the lock screen reads (PamAuthenticator::NoninteractiveAuthenticatorType).
QtObject {
    enum NoninteractiveAuthenticatorType {
        None = 0,
        Fingerprint = 1,
        Smartcard = 2
    }
}
