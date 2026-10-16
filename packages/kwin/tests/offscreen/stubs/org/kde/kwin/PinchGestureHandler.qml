// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

// KWin 6.7.5's enums (src/scripting/gesturehandler.h), in its order.
QtObject {
    enum Direction { Expanding, Contracting }
    enum Device { Touchpad }
    property int direction
    property int fingerCount
    signal activated()
}
