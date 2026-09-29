/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.plasma.extras as PlasmaExtras

// A context menu that is filled from script and destroys itself when closed.
PlasmaExtras.Menu {
    id: menu

    placement: PlasmaExtras.Menu.TopPosedLeftAlignedPopup

    onStatusChanged: {
        if (status === PlasmaExtras.Menu.Closed) {
            Qt.callLater(menu.destroy);
        }
    }

    function addAction(text: string, iconName: string, callback: var, properties: var): PlasmaExtras.MenuItem {
        const item = Qt.createQmlObject("import org.kde.plasma.extras as PlasmaExtras; PlasmaExtras.MenuItem {}", menu) as PlasmaExtras.MenuItem;
        item.text = text;
        if (iconName) {
            item.icon = iconName;
        }
        if (properties) {
            for (const key in properties) {
                item[key] = properties[key];
            }
        }
        if (callback) {
            item.clicked.connect(callback);
        }
        menu.addMenuItem(item);
        return item;
    }

    function addSeparator(): void {
        const item = Qt.createQmlObject("import org.kde.plasma.extras as PlasmaExtras; PlasmaExtras.MenuItem { separator: true }", menu) as PlasmaExtras.MenuItem;
        menu.addMenuItem(item);
    }

    function addHeader(text: string): void {
        menu.addSection(text);
    }
}
