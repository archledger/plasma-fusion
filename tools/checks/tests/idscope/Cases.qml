// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Fixture for tools/checks/id-scope-lint.py: "expect: RULE" marks each line the lint must report;
// every other line must stay silent. Not a working component.
import QtQuick

Item {
    id: root

    // The desktop's bug (2026-10-11): an id inside the full representation read from the root.
    readonly property bool editing: (homeLoader.item ? homeLoader.item.editing : false) // expect: id-scope
    readonly property bool shown: full.visible // expect: id-scope
    readonly property bool deepShown: deep.visible // expect: id-scope
    // Reached through the instance, or through the Component's own id: fine.
    readonly property bool loaded: pageLoader.item !== null && comp !== null && holder !== null
    // A member read is not a name lookup.
    readonly property bool member: pageLoader.item ? pageLoader.item.inner === null : false
    readonly property int count: list.count

    property Component fullRepresentation: Item {
        id: full
        // ids of the enclosing scope stay visible inside a component
        width: root.width
        Loader {
            id: homeLoader
            sourceComponent: Item {
                id: page
                property bool editing: false
                height: homeLoader.height + full.height + root.height
            }
        }
        // the representation's own ids are visible to its own bindings
        opacity: homeLoader.item ? 1 : 0
    }

    Loader {
        id: pageLoader
        sourceComponent: Rectangle {
            id: inner
        }
    }

    Component {
        id: comp
        Item {
            id: deep
            // an id read by a binding of the same component
            opacity: deep.visible ? 1 : 0
        }
    }
    readonly property Component holder: Component {
        id: holderComponent
        Item {}
    }
    readonly property bool hasHolder: holderComponent !== null

    ListView {
        id: list
        delegate: Text {
            id: label
            // `text` is also an id below: here it is the delegate's own property
            Accessible.name: text
            text: "row"
            width: list.width
        }
    }
    Text {
        id: text
        // The delegate's id from outside the delegate.
        visible: label.visible // expect: id-scope
    }

    component Badge: Item {
        id: badgeRoot
        function grow(by: real): void {
            badgeRoot.width += by;
        }
    }
    readonly property real badgeWidth: badgeRoot.width // expect: id-scope

    function pick(index: int, comp2: var): Item {
        const items = [inner]; // expect: id-scope
        return items.find((item, at) => at === index && item !== comp2);
    }
}
