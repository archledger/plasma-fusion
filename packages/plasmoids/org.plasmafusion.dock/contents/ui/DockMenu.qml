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

    // Testing: the entries as added ("> " a submenu, "  " its entries, "[x]" checked), and each
    // action with the text it was added with, for the dock's test hook pick:TEXT (MenuPick.find()).
    // The dock keeps the actions after the menu is gone: in a session no input has reached yet, Qt
    // cannot open a grabbing popup and closes the menu at once (qtbase 6.11
    // qwaylandxdgshellintegration.cpp), and the text an item shows is not the one it was added with
    // (the menu gets KAcceleratorManager, which puts an "&" into each item's text when it opens).
    property var entries: []
    property var actions: []
    // A task's menu: its window actions hold the task's model index from when it opened.
    property bool taskMenu: false

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
        actions.push({ text: text, run: callback, enabled: item.enabled !== false });
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
