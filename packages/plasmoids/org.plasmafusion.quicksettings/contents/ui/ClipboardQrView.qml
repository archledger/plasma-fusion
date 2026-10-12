// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.prison as Prison

import "components"

// A clipboard entry as a QR code (the clipboard sheet's "qr" mode). Apart from ClipboardPage.qml and
// loaded with a Loader: without KDE Frameworks' Prison QML module the sheet still loads and says
// that QR codes are not available (tools/tests/packages/qml-imports.sh).
Item {
    id: qrView

    property var pal
    property var metrics
    property string text

    activeFocusOnTab: true
    Accessible.role: Accessible.Graphic
    Accessible.name: i18nc("@info QR code of a clipboard entry", "QR code")
    Accessible.description: qrView.text
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
            content: qrView.text
        }
    }
    FText {
        anchors.fill: parent
        visible: !qrView.valid || !qrView.fits
        pal: qrView.pal
        metrics: qrView.metrics
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: qrView.pal.secondary
        text: qrView.valid ? i18nc("@info", "This entry is too long for a QR code here")
                           : i18nc("@info", "Creating the QR code failed")
    }
}
