// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen test stand-in (test use only).
import QtQuick

QtObject {
    id: dbusCall
    property string service
    property string path
    property string dbusInterface
    property string method
    property var arguments: []
    signal finished(var returnValue)
    signal failed()
    // How often the script called it, and with which arguments (the harness reads them).
    property int calls: 0
    property var callLog: []
    function call() {
        calls++;
        callLog = callLog.concat([[].concat(dbusCall.arguments)]);
    }
}
