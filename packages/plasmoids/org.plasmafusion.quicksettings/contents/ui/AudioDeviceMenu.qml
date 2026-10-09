// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.private.volume

// The stock Audio Volume widget's device menu (plasma-pa's ListItemMenu): the device's ports
// (speakers, headphones) and its card's profiles (HDMI, analog, Pro Audio, off). AudioPage.qml
// loads this file with a Loader, so a system without plasma-pa's QML module keeps the page
// (the services' Audio.qml stays out there too) and has no menu.
ListItemMenu {
    // The input (source) list is shown, else the output (sink) list.
    property bool input: false

    itemType: input ? ListItemMenu.Source : ListItemMenu.Sink
}
