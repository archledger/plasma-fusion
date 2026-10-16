// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen test stand-in (test use only).
import QtQuick

QtObject {
    property string service
    property string path
    property string dbusInterface
    property string method
    property var arguments: []
    signal finished(var returnValue)
    signal failed()
    // How often the script called it (the harness reads it).
    property int calls: 0
    function call() { calls++; }
}
