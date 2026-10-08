// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

QtObject {
    enum Direction { Up, Down }
    enum Device { Touchpad }
    property int direction
    property int fingerCount
    property int deviceType
    signal activated()
}
