// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QImage>
#include <QQuickImageProvider>
#include <QString>

// The thumbnails KIO made, by id, for image://quicklook-thumbnail/<id>. QML may read them from its
// image loading thread, hence the lock.
namespace Thumbnails
{
QString add(const QImage &image);
QImage get(const QString &id);
}

class ThumbnailProvider : public QQuickImageProvider
{
public:
    ThumbnailProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
