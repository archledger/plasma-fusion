// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Pdf

// A PDF's pages, one under the other, as wide as the window (Qt PDF, the PDFium engine).
Item {
    id: viewer
    objectName: "pdfViewer"

    // QuickLookItem (quicklook.h).
    required property var item
    readonly property bool ready: document.status === PdfDocument.Ready || document.status === PdfDocument.Error
    readonly property var report: ({
        status: document.status === PdfDocument.Ready ? "ready" : "error",
        pages: document.pageCount,
        title: document.title
    })
    readonly property string extra: document.pageCount > 0 ? i18ncp("@info pages of a document", "%1 page", "%1 pages", document.pageCount) : ""

    PdfDocument {
        id: document
        source: viewer.item.url
        onStatusChanged: {
            if (status === PdfDocument.Ready) {
                pages.scaleToWidth(viewer.width, viewer.height);
            }
        }
    }
    PdfMultiPageView {
        id: pages
        anchors.fill: parent
        document: document
    }
}
