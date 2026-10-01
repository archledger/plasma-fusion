// SPDX-FileCopyrightText: 2025 Devin Lin <devin@kde.org>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

// Plasma Fusion navigation (TABLET2.md 3.1): the bottom-edge gestures of the tablet posture, home,
// app switcher and previous app, derived from Plasma Mobile's task switcher (plasma-mobile v6.7.5).
// The gestures follow KWin's tablet mode; laptop posture keeps KWin's native edges.

import QtQuick

import org.kde.kwin

import org.plasmafusion.navigation.plugin as Nav

SceneEffect {
    id: root

    // Created per screen
    delegate: TaskSwitcher {
        id: taskSwitcher
        state: taskSwitcherState
    }

    ShortcutHandler {
        name: 'Plasma Fusion App Switcher'
        text: i18n("Toggle the Plasma Fusion App Switcher")
        // No default key: Plasma Fusion's laptop shortcuts own Meta+Tab and Alt+Tab.
        sequence: ''

        onActivated: taskSwitcherState.toggle()
    }

    Nav.FusionNavigationState {
        id: taskSwitcherState

        gestureEnabled: tabletMode

        Component.onCompleted: {
            // Initialize with effect
            taskSwitcherState.init(root);
        }
    }
}
