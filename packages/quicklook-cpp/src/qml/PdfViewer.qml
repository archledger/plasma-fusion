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
        title: document.title,
        scale: pages.renderScale,
        // The first page's width on screen and the viewer's (the pages fit the window's width).
        pageWidth: document.status === PdfDocument.Ready ? document.pagePointSize(0).width * pages.renderScale : 0,
        width: viewer.width
    })
    readonly property string extra: document.pageCount > 0 ? i18ncp("@info pages of a document", "%1 page", "%1 pages", document.pageCount) : ""

    // The scale the pages were last fitted at. While it is still the one shown (no zoom since), a
    // resized window fits them again.
    property real fittedScale: -1

    function fit() {
        if (document.status === PdfDocument.Ready && width > 0) {
            pages.scaleToWidth(width, height);
            fittedScale = pages.renderScale;
        }
    }

    onWidthChanged: {
        if (pages.renderScale === fittedScale) {
            fit();
        }
    }
    // Tests: a zoom, as the page view's pinch makes it.
    function testZoom() {
        pages.renderScale = pages.renderScale * 1.5;
    }

    PdfDocument {
        id: document
        source: viewer.item.url
        // Later: the page view sets its scale back to 1 when the document changes, after this.
        onStatusChanged: Qt.callLater(viewer.fit)
    }
    PdfMultiPageView {
        id: pages
        anchors.fill: parent
        document: document
    }
}
