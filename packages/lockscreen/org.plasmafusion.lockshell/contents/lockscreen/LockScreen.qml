/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Plasma Fusion lock screen, loaded by kscreenlocker_greet as the shell package's
// "lockscreenmainscript". The root keeps the interface of the Plasma lock screen.
Item {
    id: root
    property bool debug: false
    property string notification
    signal clearPassword()
    signal notificationRepeated()

    // These are magical properties that kscreenlocker looks for
    property bool viewVisible: false

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    implicitWidth: 800
    implicitHeight: 600

    // This screen's wallpaper. The greeter makes each screen's wallpaper item a child of that
    // screen's root at z -1000 (kscreenlocker greeterapp.cpp, Plasma 6.7 and 6.8) and also names it
    // in the context property "wallpaper". From Plasma 6.8 every screen's view shares the engine's
    // root context, so "wallpaper" ends up naming the last screen's item on every screen; drawing
    // another window's item ("QQuickItem: Cannot use same item on different windows") left one
    // screen black and crashed the greeter when it closed after an unlock with two screens, which
    // made KWin lock again. So the root's own wallpaper child is used, and the context property
    // only while it is this root's child.
    readonly property Item wallpaperItem: {
        for (let i = 0; i < children.length; ++i) {
            const child = children[i];
            if (child.z === -1000 && child !== ui) {
                return child;
            }
        }
        // qmllint disable unqualified
        return typeof wallpaper !== "undefined" && wallpaper && wallpaper.parent === root ? wallpaper : null;
        // qmllint enable unqualified
    }

    LockScreenUi {
        id: ui
        anchors.fill: parent
        lockRoot: root
    }
}
