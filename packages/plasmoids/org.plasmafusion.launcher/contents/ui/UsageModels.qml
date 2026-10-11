/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.kicker as Kicker

// The launcher's lists for the "Recent" and "Places" chips. Recent: apps by last use and by use
// count, from the activity history that Kicker's "Recent Applications" and "Often Used" read (15
// apps each, the current activity). Places: Kickoff's Computer list (the file manager's places and
// the removable drives, Kicker's ComputerModel) and the folders used last (Kicker's OnlyFolders
// history). System Settings > Activities > Privacy can turn the history off; those lists are empty
// then. A separate object so that the offscreen tests load the same declarations.
QtObject {
    id: usage

    property var favoritesModel: null
    property var appletInterface: null

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

    // Kickoff's "Computer" without its apps: no system apps, and without the "Show KRunner" row
    // that ComputerModel puts first (the search has its own hand-off to KRunner). Rows are mapped
    // back to the ComputerModel to start them (NavGrid.sourceOf).
    readonly property Kicker.ComputerModel computer: Kicker.ComputerModel {
        appletInterface: usage.appletInterface
        favoritesModel: usage.favoritesModel
        systemApplications: []
    }
    readonly property KItemModels.KSortFilterProxyModel places: KItemModels.KSortFilterProxyModel {
        sourceModel: usage.computer
        filterRowCallback: (row, parent) => {
            const index = usage.computer.index(row, 0, parent);
            return String(usage.computer.data(index, Qt.DecorationRole) || "") !== "plasma-search";
        }
    }
    readonly property Kicker.RecentUsageModel recentFolders: Kicker.RecentUsageModel {
        favoritesModel: usage.favoritesModel
        shownItems: Kicker.RecentUsageModel.OnlyFolders
        ordering: Kicker.RecentUsageModel.Recent
    }
}
