/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.private.kicker as Kicker

// The launcher's usage lists for the "Recent" chip: apps by last use and by use count, from the
// activity history that Kicker's "Recent Applications" and "Often Used" read (15 apps each, the
// current activity). System Settings > Activities > Privacy can turn that history off; the lists
// are empty then. A separate object so that the offscreen tests load the same declarations.
QtObject {
    id: usage

    property var favoritesModel: null

    readonly property Kicker.RecentUsageModel recentApps: Kicker.RecentUsageModel {
        favoritesModel: usage.favoritesModel
        shownItems: Kicker.RecentUsageModel.OnlyApps
        ordering: Kicker.RecentUsageModel.Recent
    }
    readonly property Kicker.RecentUsageModel frequentApps: Kicker.RecentUsageModel {
        favoritesModel: usage.favoritesModel
        shownItems: Kicker.RecentUsageModel.OnlyApps
        ordering: Kicker.RecentUsageModel.Popular
    }
}
