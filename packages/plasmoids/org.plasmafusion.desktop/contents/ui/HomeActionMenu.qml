/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.extras as PlasmaExtras

// The home screen's long-press menu (TABLET2 H1), from the launcher's ActionMenu.qml: add to or
// remove from page 1 (the launcher's pinned list) plus the app's own actions (jump list, "Edit
// Application…", "Hide Application"…).
Item {
    id: actionMenu

    property var home
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
        const favorites = home.favoritesModel;
        const id = entry && entry.favoriteId ? String(entry.favoriteId) : "";
        const actions = [];

        // Split (SPLIT.md item 2; Android: long press > Split): the dock opens the app in that half
        // and moves the app in use to the other one (the "fill the other half" picker offers it).
        const appId = home.splitAppId(id);
        if (appId !== "") {
            actions.push({ text: i18nc("@action:inmenu open the app in the left half", "Split Left"), icon: "view-split-left-right",
                           actionId: "_fusion_split_left" });
            actions.push({ text: i18nc("@action:inmenu open the app in the right half", "Split Right"), icon: "view-split-left-right",
                           actionId: "_fusion_split_right" });
            actions.push({ type: "separator" });
        }

        if (id.length > 0 && favorites) {
            const pinned = favorites.isFavorite(id);
            actions.push({
                text: pinned ? i18nc("@action:inmenu", "Remove from Home Screen") : i18nc("@action:inmenu", "Add to Home Screen"),
                icon: pinned ? "list-remove" : "list-add",
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
                    actions.push(a);
                }
            }
        }

        if (actions.length > 0) {
            actions.push({ type: "separator" });
        }
        actions.push({
            text: i18nc("@action:inmenu", "Edit Home Screen"),
            icon: "edit-entry",
            actionId: "_fusion_edit_home",
        });

        targetModel = model;
        targetIndex = index;
        favoriteId = id;
        actionList = actions;
        menu.visualParent = item;
        menu.open(x, y);
    }

    function trigger(action) {
        const favorites = home.favoritesModel;
        const actionId = String(action.actionId || "");

        if (actionId === "_fusion_edit_home") {
            home.startEditing();
            return;
        }
        if (actionId === "_fusion_split_left" || actionId === "_fusion_split_right") {
            home.requestSplit(actionId === "_fusion_split_left" ? "left" : "right", home.splitAppId(favoriteId));
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
        if (targetModel) {
            targetModel.trigger(targetIndex, actionId, action.actionArgument);
        }
    }
}
