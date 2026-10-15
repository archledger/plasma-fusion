// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.syntaxhighlighting

// A text file in a fixed-width font, coloured by its language (KSyntaxHighlighting, the colours
// Kate uses). Long files: the first 512 KB (QuickLookItem::TextLimit). The keyboard stays with the
// window (Space closes, the arrow keys change the file); the mouse selects text to copy.
ColumnLayout {
    id: viewer
    objectName: "textViewer"

    // QuickLookItem (quicklook.h).
    required property var item
    readonly property bool ready: area.text.length === item.text.length
    // Lines of the file (a last line break ends a line, it does not start one).
    readonly property int lines: {
        const text = item.text;
        const breaks = (text.match(/\n/g) || []).length;
        return text.length === 0 ? 0 : breaks + (text.endsWith("\n") ? 0 : 1);
    }
    readonly property var report: ({
        length: area.text.length,
        lines: lines,
        truncated: item.textTruncated,
        definition: highlighter.definition ? highlighter.definition.name : ""
    })
    readonly property string extra: i18ncp("@info lines of a text file", "%1 line", "%1 lines", lines)

    spacing: 0

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: viewer.item.textTruncated
        type: Kirigami.MessageType.Information
        position: Kirigami.InlineMessage.Position.Header
        text: i18nc("@info", "This is the beginning of the file. Open it to see all of it.")
    }
    QQC2.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        QQC2.TextArea {
            id: area
            text: viewer.item.text
            textFormat: TextEdit.PlainText
            readOnly: true
            selectByMouse: true
            activeFocusOnPress: false
            activeFocusOnTab: false
            wrapMode: TextEdit.NoWrap
            font: Kirigami.Theme.fixedWidthFont
            background: null
            Accessible.name: viewer.item.name
        }
    }
    SyntaxHighlighter {
        id: highlighter
        textEdit: area
        definition: Repository.definitionForFileName(viewer.item.name)
        theme: Repository.defaultTheme(Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark
                                       ? Repository.DarkTheme : Repository.LightTheme)
    }
}
