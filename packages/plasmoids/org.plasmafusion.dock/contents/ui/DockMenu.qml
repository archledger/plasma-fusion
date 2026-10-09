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

    // Testing: the entries as added ("> " a submenu, "  " its entries, "[x]" checked).
    property var entries: []

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
        entries.push((item.checked ? "[x] " : "") + text);
        return item;
    }

    function addSeparator(): void {
        const item = Qt.createQmlObject("import org.kde.plasma.extras as PlasmaExtras; PlasmaExtras.MenuItem { separator: true }", menu) as PlasmaExtras.MenuItem;
        menu.addMenuItem(item);
    }

    // A submenu under a new item of this menu (as the stock task manager's "Move to Desktop":
    // a Menu whose visualParent is the item's action). Fill it with addSubAction/addSubSeparator.
    function addSubMenu(text: string, iconName: string): PlasmaExtras.Menu {
        const item = addAction(text, iconName, null, null);
        const sub = Qt.createQmlObject("import org.kde.plasma.extras as PlasmaExtras; PlasmaExtras.Menu {}", menu) as PlasmaExtras.Menu;
        sub.visualParent = item.action;
        entries[entries.length - 1] = "> " + text;
        return sub;
    }

    // A MenuItem created as the submenu's child joins it (the stock task manager's newMenuItem).
    function addSubAction(sub: PlasmaExtras.Menu, text: string, iconName: string, callback: var, properties: var): PlasmaExtras.MenuItem {
        const item = Qt.createQmlObject("import org.kde.plasma.extras as PlasmaExtras; PlasmaExtras.MenuItem {}", sub) as PlasmaExtras.MenuItem;
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
        entries.push("  " + (item.checked ? "[x] " : "") + text + (item.enabled === false ? " (disabled)" : ""));
        return item;
    }

    function addSubSeparator(sub: PlasmaExtras.Menu): void {
        Qt.createQmlObject("import org.kde.plasma.extras as PlasmaExtras; PlasmaExtras.MenuItem { separator: true }", sub);
    }

    function addHeader(text: string): void {
        menu.addSection(text);
    }
}
