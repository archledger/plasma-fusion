// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kscreenlocker as ScreenLocker

// Test stand-in for Plasma 6.8's PamAuthenticators: the 6.7 interface plus the chosen way to unlock
// (`authenticator`, kscreenlocker's Authenticators enum) and `unlocked`; startAuthenticating() has
// no guard, as in 6.8. The ways the model offers come from `ways` (the stub AuthenticatorModel
// reads them). It never authenticates anything.
MockAuthenticator {
    id: mock

    property int authenticator: ScreenLocker.Authenticators.Regular
    property var ways: []
    property var chosenLog: []
    property int stopCount: 0

    onAuthenticatorChanged: {
        chosenLog = chosenLog.concat([authenticator]);
        // The greeter starts the new way's conversation and clears the old messages.
        infoMessage = "";
        errorMessage = "";
    }

    function stopAuthenticating() { stopCount += 1; state = 0; }
    // A way stops working (PamAuthenticatorModel::markDefunct).
    function markDefunct(type) { ScreenLocker.AuthenticatorModel.setFunctional(type, false); }
}
