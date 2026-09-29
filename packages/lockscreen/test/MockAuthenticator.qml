// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick

// Test stand-in for kscreenlocker's PamAuthenticators (same properties, signals and
// invokables); it never authenticates anything.
QtObject {
    property bool busy: false
    property string prompt: ""
    property string promptForSecret: ""
    property string infoMessage: ""
    property string errorMessage: ""
    property bool unlocked: false
    property int authenticatorTypes: 1
    property int state: 0
    property bool hadPrompt: true
    property int startCount: 0
    property var responses: []
    // Test hooks: setting these makes the mock fingerprint authenticator send an info or
    // error message, as pam_fprintd does through kscreenlocker's noninteractive authenticator.
    property string fingerprintInfo: ""
    property string fingerprintError: ""
    readonly property QtObject fingerprintAuthenticator: QtObject {
        property string infoMessage: ""
        property string errorMessage: ""
    }
    onFingerprintInfoChanged: {
        fingerprintAuthenticator.infoMessage = fingerprintInfo;
        noninteractiveInfo(1, fingerprintAuthenticator);
    }
    onFingerprintErrorChanged: {
        fingerprintAuthenticator.errorMessage = fingerprintError;
        noninteractiveError(1, fingerprintAuthenticator);
    }

    signal succeeded()
    signal failed(int kind, QtObject authenticator)
    signal noninteractiveError(int kind, QtObject authenticator)
    signal noninteractiveInfo(int kind, QtObject authenticator)
    signal loginFailedDelayStarted(int kind, QtObject authenticator, int uSecDelay)

    function startAuthenticating() { startCount += 1; state = 1; }
    function stopAuthenticating() { state = 0; }
    function respond(password) { responses = responses.concat(["<" + password.length + " chars>"]); }
    function cancel() { }
}
