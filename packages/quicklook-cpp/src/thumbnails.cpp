// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "thumbnails.h"

#include <QHash>
#include <QMutex>

namespace
{
QMutex s_lock;
QHash<QString, QImage> s_images;
int s_next = 0;
}

QString Thumbnails::add(const QImage &image)
{
    QMutexLocker locker(&s_lock);
    const QString id = QString::number(++s_next);
    s_images.insert(id, image);
    return id;
}

QImage Thumbnails::get(const QString &id)
{
    QMutexLocker locker(&s_lock);
    return s_images.value(id);
}

ThumbnailProvider::ThumbnailProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

QImage ThumbnailProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    QImage image = Thumbnails::get(id);
    if (!image.isNull() && requestedSize.isValid() && (image.width() > requestedSize.width() || image.height() > requestedSize.height())) {
        image = image.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    if (size) {
        *size = image.size();
    }
    return image;
}
