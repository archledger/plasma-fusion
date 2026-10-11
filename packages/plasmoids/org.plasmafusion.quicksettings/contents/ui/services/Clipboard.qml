// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.clipboard as Private
import org.kde.plasma.workspace.dbus as DBus

import "../../code/clipboard.js" as Clip

// Klipper's clipboard history through Plasma's own QML module, the one the stock Clipboard widget
// and Klipper's pop-up use: its HistoryModel is a view of the history Klipper keeps in plasmashell
// (newest first), so the entries, their stars (Plasma 6.5) and the storage
// (~/.local/share/klipper/history3.sqlite) are the same everywhere. Without the module this file
// does not load and the clipboard button opens Klipper's own pop-up. tests/clipboard_sheet_test.py.
Item {
    id: service

    // What the search field holds; `model` lists the entries that match it (clipboard.js).
    property string query: ""
    // Only the starred entries (the stock widget's "Starred Only" tab). Klipper turns it off when
    // the last star goes.
    property alias starredOnly: history.starredOnly
    // Words an image or a file list is also found by.
    property string imageWords: ""
    property string fileWords: ""

    readonly property var model: filtered
    readonly property int count: filtered.count
    readonly property int sourceCount: history.sourceCount
    readonly property int starredCount: history.starredCount
    readonly property string currentText: history.currentText

    // Puts the entry on the clipboard (Klipper moves it to the top of the history).
    function choose(uuid: string): void {
        history.moveToTop(uuid);
    }
    // After choosing: Plasma's on-screen display says how to paste. Nothing can paste into the
    // window under the sheet without a new privilege (docs/parts/shell-quicksettings.md,
    // "Clipboard sheet").
    function showPasteHint(): void {
        DBus.SessionBus.asyncCall({
            "service": "org.kde.plasmashell",
            "path": "/org/kde/osdService",
            "iface": "org.kde.osdService",
            "member": "showText",
            "arguments": [new DBus.string("edit-paste"),
                          new DBus.string(i18nc("@info:osd after choosing a clipboard entry", "Copied, press Ctrl+V to paste"))],
            "signature": "(ss)"
        });
    }
    // Removes the entry; a starred one asks first (Klipper's own confirmation).
    // Both confirmations are modal dialogs that run an event loop of their own, in which the
    // sheet closes and its page goes away: called from the page's button, they would destroy the
    // button while its handler runs (plasmashell aborts). So they run from here, a moment later.
    function remove(uuid: string): void {
        Qt.callLater(() => history.remove(uuid));
    }
    // Clears the history except the starred entries, after Klipper's own confirmation ("Do you
    // really want to clear and delete the entire clipboard history?").
    function clearHistory(): void {
        Qt.callLater(() => history.clearHistory());
    }
    // Klipper's actions for the entry (its "Invoke action" menu at the pointer).
    function invokeAction(uuid: string): void {
        history.invokeAction(uuid);
    }
    function setStarred(uuid: string, starred: bool): void {
        const row = rowOf(uuid);
        if (row >= 0) {
            history.setData(history.index(row, 0), starred, history.starredRole);
        }
    }
    // Replaces a text entry and puts it on the clipboard, as the stock widget's editor saves.
    function edit(uuid: string, text: string): string {
        const row = rowOf(uuid);
        if (row < 0) {
            return "";
        }
        const index = history.index(row, 0);
        history.setData(index, text, Qt.DisplayRole);
        // Klipper gives the edited entry a new id (the hash of its text).
        const newUuid = String(history.data(history.index(row, 0), history.uuidRole) || "");
        if (newUuid !== "") {
            history.moveToTop(newUuid);
        }
        return newUuid;
    }
    // Klipper's settings dialog (the stock widget's "Configure Clipboard…").
    function configure(): void {
        if (!klipper) {
            klipper = klipperComponent.createObject(service);
        }
        if (klipper) {
            klipper.configure();
        }
    }

    function rowOf(uuid: string): int {
        for (let row = 0; row < history.rowCount(); ++row) {
            if (String(history.data(history.index(row, 0), history.uuidRole)) === uuid) {
                return row;
            }
        }
        return -1;
    }

    onQueryChanged: filtered.invalidateFilter()
    onImageWordsChanged: filtered.invalidateFilter()
    onFileWordsChanged: filtered.invalidateFilter()

    Private.HistoryModel {
        id: history
        objectName: "clipboardHistory"
        readonly property int uuidRole: KItemModels.KRoleNames.role("uuid")
        readonly property int typeRole: KItemModels.KRoleNames.role("type")
        readonly property int starredRole: KItemModels.KRoleNames.role("starred")
    }

    KItemModels.KSortFilterProxyModel {
        id: filtered
        objectName: "clipboardFiltered"
        sourceModel: history
        filterRowCallback: (row, parent) => {
            if (service.query.trim() === "") {
                return true;
            }
            const index = history.index(row, 0, parent);
            let text = String(history.data(index, Qt.DisplayRole) || "");
            const type = Number(history.data(index, history.typeRole));
            if (type === Clip.IMAGE) {
                text += " " + service.imageWords;
            } else if (type === Clip.URL) {
                text = Clip.fileNames(text).join(" ") + " " + text + " " + service.fileWords;
            }
            return Clip.matches(text, service.query);
        }
    }

    // Made on first use only: it keeps Klipper itself (its D-Bus service and shortcuts) alive,
    // which the stock Clipboard widget in the tray already does.
    property QtObject klipper: null
    Component {
        id: klipperComponent
        Private.KlipperInterface {}
    }
}
