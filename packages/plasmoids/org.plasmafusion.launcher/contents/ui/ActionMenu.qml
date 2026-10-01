/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.extras as PlasmaExtras

// Context menu for tiles, recent files and search results: pin/unpin plus the model's own
// actions (jump list, "Open Containing Folder", "Edit Application…", "Hide Application"…).
Item {
    id: actionMenu

    property var launcher
    property var actionList: null
    property var targetModel: null
    property int targetIndex: -1
    property string favoriteId: ""

    visible: false

    readonly property PlasmaExtras.Menu menu: PlasmaExtras.Menu {
        visualParent: null
        placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
        onStatusChanged: {
            if (status === PlasmaExtras.Menu.Closed) {
                actionMenu.actionList = null;
            }
        }
    }

    Instantiator {
        active: actionMenu.actionList !== null
        model: actionMenu.actionList
        delegate: PlasmaExtras.MenuItem {
            required property var modelData

            text: modelData.text ?? ""
            icon: modelData.icon ?? null
            separator: modelData.type === "separator"
            section: modelData.type === "title"
            enabled: modelData.type !== "title" && (modelData.enabled ?? true)
            checkable: modelData.checkable ?? false
            checked: modelData.checked ?? false
            onClicked: actionMenu.trigger(modelData)
        }
        onObjectAdded: (index, object) => actionMenu.menu.addMenuItem(object)
        onObjectRemoved: (index, object) => actionMenu.menu.removeMenuItem(object)
    }

    function openFor(model, index, entry, item, x, y) {
        const favorites = launcher.favoritesModel;
        const id = entry && entry.favoriteId ? String(entry.favoriteId) : "";
        const actions = [];

        // Split (SPLIT.md item 2; Android: long press > Split), tablet posture: the dock opens the
        // app in that half and moves the app under the sheet to the other one.
        const splitId = launcher.tablet && entry && entry.favoriteId ? launcher.splitAppId(String(entry.favoriteId)) : "";
        if (splitId !== "") {
            actions.push({ text: i18nc("@action:inmenu open the app in the left half", "Split Left"), icon: "view-split-left-right",
                           actionId: "_fusion_split_left", actionArgument: splitId });
            actions.push({ text: i18nc("@action:inmenu open the app in the right half", "Split Right"), icon: "view-split-left-right",
                           actionId: "_fusion_split_right", actionArgument: splitId });
            actions.push({ type: "separator" });
        }

        if (id.length > 0 && favorites) {
            const pinned = favorites.isFavorite(id);
            actions.push({
                text: pinned ? i18nc("@action:inmenu", "Unpin from Launcher") : i18nc("@action:inmenu", "Pin to Launcher"),
                icon: pinned ? "window-unpin" : "window-pin",
                actionId: pinned ? "_fusion_unpin" : "_fusion_pin",
            });
        }

        if (entry && entry.hasActionList && entry.actionList) {
            const extra = Array.from(entry.actionList);
            if (extra.length > 0) {
                if (actions.length > 0) {
                    actions.push({ type: "separator" });
                }
                for (const a of extra) {
                    // Recent files (BACKLOG M8): "Hide" and "Clear" instead of Kicker's "Forget".
                    if (a.actionId === "forget") {
                        actions.push(Object.assign({}, a, { "text": i18nc("@action:inmenu recent file", "Hide from Recent Files") }));
                    } else if (a.actionId === "forgetAll") {
                        actions.push(Object.assign({}, a, { "text": i18nc("@action:inmenu recent files", "Clear Recent Files") }));
                    } else {
                        actions.push(a);
                    }
                }
            }
        }

        if (actions.length === 0) {
            return;
        }

        targetModel = model;
        targetIndex = index;
        favoriteId = id;
        actionList = actions;
        menu.visualParent = item;
        menu.open(x, y);
    }

    function trigger(action) {
        const favorites = launcher.favoritesModel;
        const actionId = String(action.actionId || "");

        if (actionId === "_fusion_split_left" || actionId === "_fusion_split_right") {
            launcher.requestSplit(actionId === "_fusion_split_left" ? "left" : "right", String(action.actionArgument || ""));
            return;
        }
        if (actionId === "_fusion_pin") {
            favorites.addFavorite(favoriteId);
            return;
        }
        if (actionId === "_fusion_unpin") {
            favorites.removeFavorite(favoriteId);
            return;
        }
        if (actionId.indexOf("_kicker_favorite_") === 0) {
            const arg = action.actionArgument || {};
            if (actionId === "_kicker_favorite_remove") {
                favorites.removeFavorite(arg.favoriteId);
            } else if (actionId === "_kicker_favorite_add") {
                favorites.addFavorite(arg.favoriteId);
            }
            return;
        }
        if (targetModel && targetModel.trigger(targetIndex, actionId, action.actionArgument)) {
            launcher.close();
        }
    }
}
