/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * The circular cut of CircularImage.qml: MultiEffect (QtQuick.Effects) draws the photo through a
 * disc. CircularImage creates this file itself, so a greeter without QtQuick.Effects only gets an
 * error status (and keeps the initial) instead of a theme that does not load.
 */

import QtQuick 2.15
import QtQuick.Effects

Item {
    id: root
    // The photo (an Image, hidden by CircularImage: only this effect draws it)
    property Item photo: null

    MultiEffect {
        anchors.fill: parent
        source: root.photo
        maskEnabled: true
        maskSource: disc
        // Soft by one step at the threshold, so the disc's edge is antialiased
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
    Rectangle {
        id: disc
        anchors.fill: parent
        radius: Math.min(width, height) / 2
        visible: false
        layer.enabled: true
        layer.smooth: true
    }
}
