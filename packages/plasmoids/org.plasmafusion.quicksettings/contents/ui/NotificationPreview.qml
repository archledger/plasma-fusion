// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrolsaddons as KQCAddons
import plasma.applet.org.kde.plasma.notifications as Notifications

// KIO's preview of a file, made by the stock Notifications applet's Thumbnailer (the type its
// ThumbnailStrip uses; the applet is loaded in the same shell). Loaded by NotificationThumbnail,
// which falls back to a plain image when this file cannot load (another Plasma, no applet).
Item {
    id: preview

    property url url
    property size size

    Notifications.Thumbnailer {
        id: thumbnailer
        url: preview.url
        size: preview.size
    }
    KQCAddons.QPixmapItem {
        anchors.fill: parent
        pixmap: thumbnailer.pixmap
        fillMode: KQCAddons.QPixmapItem.PreserveAspectFit
        smooth: true
    }
    // A file without a preview: its type's icon.
    Kirigami.Icon {
        anchors.centerIn: parent
        width: Kirigami.Units.iconSizes.huge
        height: width
        visible: !thumbnailer.busy && !thumbnailer.hasPreview
        source: thumbnailer.iconName
    }
}
