// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.extras as PlasmaExtras
import org.kde.prison as Prison

import "components"
import "components/Icons.js" as Icons
import "../code/clipboard.js" as Clip

// The clipboard sheet (the clipboard button): Klipper's history, newest first, from
// Plasma's own clipboard model (services/Clipboard.qml), so stars and entries are the stock
// Clipboard widget's. Search (every word, as plain text), All / Starred as in the stock widget,
// text, images and copied files, star, edit, QR code, Klipper's actions, remove, and Clear all
// with Klipper's confirmation (starred entries stay). Choosing an entry puts it on the clipboard
// and closes the sheet.
//
// Keyboard: the list has the focus with the newest entry current; Up and Down move, Enter
// chooses, Delete removes, Menu or Right opens the entry's actions (Left and Right move between
// them, Enter presses one, Left on the first closes them), typing goes to the search field (Down
// goes back to the list), Escape closes the editor, the QR code or the actions, then clears the
// search, then leaves the sheet.
ColumnLayout {
    id: page

    required property var backend
    required property FusionPalette pal
    required property FusionMetrics metrics
    // The sheet's height on this screen (PopupContent): the list gets what the rest leaves, so the
    // sheet itself does not scroll around the list.
    property real maxHeight: 100000
    readonly property real chromeHeight: header.implicitHeight + search.Layout.preferredHeight
        + (tabs.visible ? tabs.implicitHeight + spacing : 0) + 1 + footer.implicitHeight + 4 * spacing
    readonly property real listMaxHeight: Math.max(metrics.px(120), Math.min(metrics.px(pal.tablet ? 460 : 400), maxHeight - chromeHeight))

    signal back()

    // The clipboard service (null until it is loaded).
    readonly property var service: backend.clipboard.service
    readonly property int count: service ? service.count : 0
    readonly property alias list: list
    readonly property alias searchField: search
    readonly property Item firstFocusItem: mode !== "list" ? modeFocus : (count > 0 ? list : search)
    // "list", "edit" (an entry's text in an editor) or "qr" (an entry as a QR code).
    property string mode: "list"
    property string modeUuid: ""
    property string modeText: ""
    property Item modeFocus: null
    // The entry whose actions are open, and the action the arrow keys are on.
    property string expandedUuid: ""
    property int actionIndex: 0
    // The current row was reached from the keyboard (its focus ring shows); a pointer on a row
    // makes it current without the ring.
    property bool keyboardMode: false

    spacing: metrics.px(10)

    Binding {
        target: page.service
        property: "query"
        value: search.text
        when: page.service !== null
    }
    Binding {
        target: page.service
        property: "imageWords"
        value: i18nc("@info:search words that find copied images", "image picture")
        when: page.service !== null
    }
    Binding {
        target: page.service
        property: "fileWords"
        value: i18nc("@info:search words that find copied files", "file")
        when: page.service !== null
    }

    function uuidAt(row: int): string {
        const item = list.itemAtIndex(row) as ClipboardEntry;
        return item ? String(item.model.uuid) : "";
    }
    function choose(row: int): void {
        const uuid = uuidAt(row);
        if (uuid !== "") {
            page.backend.clipboard.choose(uuid);
        }
    }
    function remove(row: int): void {
        const uuid = uuidAt(row);
        if (uuid !== "") {
            page.service.remove(uuid);
        }
    }
    function toggleStar(row: int): void {
        const item = list.itemAtIndex(row) as ClipboardEntry;
        if (item) {
            page.service.setStarred(String(item.model.uuid), !item.starred);
        }
    }
    function openMode(name: string, row: int): void {
        const item = list.itemAtIndex(row) as ClipboardEntry;
        if (!item) {
            return;
        }
        modeUuid = String(item.model.uuid);
        modeText = item.display;
        expandedUuid = "";
        // The list hides: it gives up the focus first, and the editor or the QR code takes it once
        // loaded (their Loaders, below).
        page.forceActiveFocus(Qt.TabFocusReason);
        mode = name;
    }
    function closeMode(): void {
        mode = "list";
        modeUuid = "";
        modeText = "";
        modeFocus = null;
        // After the editor or the QR code is gone (it had the focus).
        Qt.callLater(() => page.firstFocusItem.forceActiveFocus(Qt.TabFocusReason));
    }
    function focusList(): void {
        if (list.count === 0) {
            return;
        }
        if (list.currentIndex < 0 || list.currentIndex >= list.count) {
            list.currentIndex = 0;
        }
        list.forceActiveFocus(Qt.TabFocusReason);
    }
    // Typing on the list goes to the search field.
    function typeToSearch(text: string): void {
        search.text += text;
        search.forceActiveFocus(Qt.TabFocusReason);
        search.cursorPosition = search.text.length;
    }

    // Escape: the editor or QR code back to the list, then an open action row, then the search;
    // otherwise the sheet's own Escape (PopupContent: back to quick settings or close).
    Keys.onEscapePressed: event => {
        if (mode !== "list") {
            closeMode();
        } else if (expandedUuid !== "") {
            expandedUuid = "";
            focusList();
        } else if (search.text !== "") {
            search.text = "";
            focusList();
        } else {
            event.accepted = false;
            return;
        }
        event.accepted = true;
    }

    // ---------------------------------------------------------------- header
    PageHeader {
        id: header
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        title: page.mode === "edit" ? i18nc("@title", "Edit entry")
             : page.mode === "qr" ? i18nc("@title", "QR code")
             : i18nc("@title", "Clipboard")
        onBack: page.mode !== "list" ? page.closeMode() : page.back()

        TextButton {
            objectName: "clipboardClear"
            visible: page.mode === "list" && page.service !== null && page.service.sourceCount > page.service.starredCount
            pal: page.pal
            metrics: page.metrics
            radius: height / 2
            fill: page.pal.clearAllFill
            textColor: page.pal.controlText
            // 44 px targets in touch mode (ADAPTIVE 5.3), as the Notification Centre's Clear all.
            implicitHeight: page.pal.touch ? 44 : page.metrics.px(26)
            fontSize: 12
            text: i18nc("@action:button clipboard history", "Clear all")
            Accessible.name: i18nc("@action:button", "Clear clipboard history")
            onClicked: page.service.clearHistory()
        }
    }

    // ---------------------------------------------------------------- list
    PlasmaExtras.SearchField {
        id: search
        objectName: "clipboardSearch"
        Layout.fillWidth: true
        Layout.preferredHeight: page.pal.touch ? Math.max(44, implicitHeight) : implicitHeight
        visible: page.mode === "list"
        placeholderText: i18nc("@info:placeholder", "Search the clipboard")
        Accessible.name: i18nc("@label:textbox", "Search the clipboard")
        Keys.onDownPressed: event => {
            page.keyboardMode = true;
            page.focusList();
            event.accepted = true;
        }
        Keys.onReturnPressed: event => {
            page.choose(Math.max(0, list.currentIndex));
            event.accepted = true;
        }
        Keys.onEnterPressed: event => Keys.returnPressed(event)
        onTextChanged: list.currentIndex = 0
    }

    // The stock widget's tabs, shown once something is starred.
    QQC2.TabBar {
        id: tabs
        Layout.fillWidth: true
        visible: page.mode === "list" && page.service !== null && page.service.starredCount > 0
        currentIndex: page.service && page.service.starredOnly ? 1 : 0
        onCurrentIndexChanged: {
            if (page.service && page.service.starredOnly !== (currentIndex === 1)) {
                page.service.starredOnly = currentIndex === 1;
                list.currentIndex = 0;
            }
        }
        // The bar gives its buttons its content height: 44 px tabs in touch mode.
        contentHeight: page.pal.touch ? 44 : Math.max(allTab.implicitHeight, starredTab.implicitHeight)
        QQC2.TabButton {
            id: allTab
            text: i18nc("@title:tab clipboard history", "All")
        }
        QQC2.TabButton {
            id: starredTab
            text: i18nc("@title:tab clipboard history", "Starred")
        }
    }

    ListView {
        id: list
        objectName: "clipboardList"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.min(contentHeight, page.listMaxHeight)
        Layout.minimumHeight: count > 0 ? Math.min(contentHeight, page.metrics.px(120)) : 0
        visible: page.mode === "list" && count > 0
        clip: true
        spacing: page.metrics.px(2)
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        highlightFollowsCurrentItem: false
        keyNavigationEnabled: false
        activeFocusOnTab: true
        currentIndex: 0
        model: page.service ? page.service.model : null
        Accessible.role: Accessible.List
        Accessible.name: i18nc("@label", "Clipboard history")

        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        onCountChanged: {
            if (count > 0 && (currentIndex < 0 || currentIndex >= count)) {
                currentIndex = currentIndex < 0 ? 0 : count - 1;
            }
            if (count === 0 && activeFocus) {
                search.forceActiveFocus(Qt.TabFocusReason);
            }
        }

        Keys.onPressed: event => {
            page.keyboardMode = true;
            const current = list.itemAtIndex(list.currentIndex) as ClipboardEntry;
            switch (event.key) {
            case Qt.Key_Up:
            case Qt.Key_Down: {
                page.expandedUuid = "";
                const next = Clip.step(list.currentIndex, event.key === Qt.Key_Up ? -1 : 1, list.count);
                if (next < 0) {
                    search.forceActiveFocus(Qt.TabFocusReason);
                } else {
                    list.currentIndex = next;
                }
                event.accepted = true;
                return;
            }
            case Qt.Key_Home:
            case Qt.Key_End:
                list.currentIndex = event.key === Qt.Key_Home ? 0 : list.count - 1;
                event.accepted = true;
                return;
            case Qt.Key_PageUp:
            case Qt.Key_PageDown: {
                const rows = Math.max(1, Math.floor(list.height / page.metrics.px(52)));
                list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + (event.key === Qt.Key_PageUp ? -rows : rows)));
                event.accepted = true;
                return;
            }
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (current && current.expanded) {
                    current.pressAction(page.actionIndex);
                } else {
                    page.choose(list.currentIndex);
                }
                event.accepted = true;
                return;
            case Qt.Key_Delete:
                page.remove(list.currentIndex);
                event.accepted = true;
                return;
            case Qt.Key_Menu:
            case Qt.Key_Right:
                if (current && current.expanded) {
                    page.actionIndex = Math.min(page.actionIndex + 1, current.actionButtons.length - 1);
                } else if (current) {
                    page.expandedUuid = String(current.model.uuid);
                    page.actionIndex = 0;
                }
                event.accepted = true;
                return;
            case Qt.Key_Left:
                if (current && current.expanded) {
                    if (page.actionIndex > 0) {
                        page.actionIndex -= 1;
                    } else {
                        page.expandedUuid = "";
                    }
                    event.accepted = true;
                    return;
                }
                break;
            case Qt.Key_Space:
                if (current && current.expanded) {
                    current.pressAction(page.actionIndex);
                    event.accepted = true;
                    return;
                }
                break;
            case Qt.Key_Backspace:
                search.text = search.text.slice(0, -1);
                search.forceActiveFocus(Qt.TabFocusReason);
                event.accepted = true;
                return;
            case Qt.Key_F:
                if (event.modifiers & Qt.ControlModifier) {
                    search.forceActiveFocus(Qt.TabFocusReason);
                    search.selectAll();
                    event.accepted = true;
                    return;
                }
                break;
            }
            if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && Clip.typesText(event.text)) {
                page.typeToSearch(event.text);
                event.accepted = true;
                return;
            }
            // Tab, Escape and the rest go on (Keys accepts the event before this handler runs).
            event.accepted = false;
        }

        delegate: ClipboardEntry {
            id: entryItem
            pal: page.pal
            metrics: page.metrics
            current: entryItem.ListView.isCurrentItem
            keyboardFocus: list.activeFocus && page.keyboardMode
            expanded: page.expandedUuid !== "" && page.expandedUuid === String(entryItem.model.uuid)
            actionIndex: page.actionIndex
            onHovered: {
                page.keyboardMode = false;
                list.currentIndex = entryItem.index;
            }
            onChosen: page.choose(entryItem.index)
            onStarToggled: page.toggleStar(entryItem.index)
            onExpandToggled: {
                page.actionIndex = 0;
                list.currentIndex = entryItem.index;
                page.expandedUuid = entryItem.expanded ? "" : String(entryItem.model.uuid);
            }
            onEditRequested: page.openMode("edit", entryItem.index)
            onQrRequested: page.openMode("qr", entryItem.index)
            onActionsRequested: {
                page.service.invokeAction(String(entryItem.model.uuid));
                page.backend.closeRequested();
            }
            onRemoveRequested: page.remove(entryItem.index)
        }
    }

    FText {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: page.metrics.px(64)
        visible: page.mode === "list" && !list.visible
        pal: page.pal
        metrics: page.metrics
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: page.pal.secondary
        text: !page.service ? "" : search.text !== "" ? i18nc("@info clipboard search", "No matches")
            : page.service.starredOnly ? i18nc("@info", "No starred entries")
            : i18nc("@info", "Clipboard is empty")
    }

    // ---------------------------------------------------------------- editor
    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: page.metrics.px(200)
        active: page.mode === "edit"
        visible: active
        onLoaded: {
            page.modeFocus = item.textArea;
            Qt.callLater(() => page.modeFocus && page.modeFocus.forceActiveFocus(Qt.TabFocusReason));
        }
        sourceComponent: ColumnLayout {
            id: editView
            readonly property Item textArea: editor
            spacing: page.metrics.px(8)
            function save(): void {
                if (editor.text !== page.modeText) {
                    page.service.edit(page.modeUuid, editor.text);
                }
                page.closeMode();
            }
            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                QQC2.TextArea {
                    id: editor
                    objectName: "clipboardEditor"
                    text: page.modeText
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    Accessible.name: i18nc("@label:textbox", "Entry text")
                    Component.onCompleted: cursorPosition = text.length
                    // Enter saves as in the stock widget's editor; Shift+Enter starts a new line.
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                            editView.save();
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: page.metrics.px(8)
                Item {
                    Layout.fillWidth: true
                }
                TextButton {
                    pal: page.pal
                    metrics: page.metrics
                    implicitHeight: page.pal.touch ? 44 : page.metrics.px(32)
                    sidePadding: page.metrics.px(14)
                    text: i18nc("@action:button", "Cancel")
                    onClicked: page.closeMode()
                }
                TextButton {
                    objectName: "clipboardSave"
                    pal: page.pal
                    metrics: page.metrics
                    primary: true
                    implicitHeight: page.pal.touch ? 44 : page.metrics.px(32)
                    sidePadding: page.metrics.px(14)
                    text: i18nc("@action:button save the edited clipboard entry", "Save")
                    onClicked: editView.save()
                }
            }
        }
    }

    // ---------------------------------------------------------------- QR code
    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: page.metrics.px(280)
        active: page.mode === "qr"
        visible: active
        onLoaded: {
            page.modeFocus = item;
            Qt.callLater(() => page.modeFocus && page.modeFocus.forceActiveFocus(Qt.TabFocusReason));
        }
        sourceComponent: Item {
            id: qrView
            activeFocusOnTab: true
            Accessible.role: Accessible.Graphic
            Accessible.name: i18nc("@info QR code of a clipboard entry", "QR code")
            Accessible.description: page.modeText
            readonly property bool valid: barcode.implicitWidth > 0 && barcode.implicitHeight > 0
            readonly property bool fits: barcode.implicitWidth <= barcode.width && barcode.implicitHeight <= barcode.height
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height)
                height: width
                radius: 12
                // The code needs its light background in both styles to be read.
                color: "#ffffff"
                opacity: qrView.valid && qrView.fits ? 1 : 0
                Prison.Barcode {
                    id: barcode
                    anchors.fill: parent
                    anchors.margins: 12
                    barcodeType: Prison.Barcode.QRCode
                    content: page.modeText
                }
            }
            FText {
                anchors.fill: parent
                visible: !qrView.valid || !qrView.fits
                pal: page.pal
                metrics: page.metrics
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: page.pal.secondary
                text: qrView.valid ? i18nc("@info", "This entry is too long for a QR code here")
                                   : i18nc("@info", "Creating the QR code failed")
            }
        }
    }

    // ---------------------------------------------------------------- footer
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        visible: page.mode === "list"
        color: page.pal.overlay(0.08)
    }
    RowLayout {
        id: footer
        Layout.fillWidth: true
        visible: page.mode === "list"
        spacing: page.metrics.px(8)
        Item {
            Layout.fillWidth: true
        }
        TextButton {
            pal: page.pal
            metrics: page.metrics
            implicitHeight: page.pal.touch ? 44 : page.metrics.px(32)
            radius: height / 2
            sidePadding: page.metrics.px(14)
            fill: page.pal.overlay(0.08)
            fontSize: 12.5
            iconPath: Icons.settingsSmall
            text: i18nc("@action:button", "Clipboard settings")
            onClicked: {
                page.backend.closeRequested();
                page.service.configure();
            }
        }
    }
}
