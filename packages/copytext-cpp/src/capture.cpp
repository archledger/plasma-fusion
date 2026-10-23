// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "capture.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QFile>
#include <QFutureWatcher>
#include <QtConcurrentRun>

#include <fcntl.h>
#include <memory>
#include <unistd.h>
#include <utility>

using namespace Qt::StringLiterals;

namespace
{
// The pending callback may be disconnected before it runs; it must still close its pipe.
struct CaptureReadFd {
    explicit CaptureReadFd(int descriptor)
        : fd(descriptor)
    {
    }
    ~CaptureReadFd()
    {
        if (fd >= 0) {
            ::close(fd);
        }
    }
    CaptureReadFd(const CaptureReadFd &) = delete;
    CaptureReadFd &operator=(const CaptureReadFd &) = delete;
    int release()
    {
        return std::exchange(fd, -1);
    }
    int fd;
};
}

QImage readRawImage(int fd, const QVariantMap &meta)
{
    QFile pipe;
    if (!pipe.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) {
        ::close(fd);
        return {};
    }
    const int width = meta.value(u"width"_s).toInt();
    const int height = meta.value(u"height"_s).toInt();
    const qsizetype stride = meta.value(u"stride"_s).toLongLong();
    const uint format = meta.value(u"format"_s).toUInt();
    if (meta.value(u"type"_s).toString() != u"raw"_s || width <= 0 || height <= 0 || format <= QImage::Format_Invalid || format >= QImage::NImageFormats) {
        return {};
    }
    QImage image(width, height, static_cast<QImage::Format>(format));
    if (image.isNull() || stride < image.bytesPerLine()) {
        return {};
    }
    QByteArray row(stride, Qt::Uninitialized);
    for (int y = 0; y < height; ++y) {
        if (pipe.read(row.data(), stride) != stride) {
            return {};
        }
        memcpy(image.scanLine(y), row.constData(), image.bytesPerLine());
    }
    bool ok = false;
    const qreal scale = meta.value(u"scale"_s).toReal(&ok);
    image.setDevicePixelRatio(ok && scale > 0 ? scale : 1.0);
    return image;
}

void ScreenCapture::capture(const QString &screenName)
{
    int fds[2] = {-1, -1};
    if (pipe2(fds, O_CLOEXEC) == -1) {
        Q_EMIT failed(screenName, u"pipe2() failed"_s);
        return;
    }
    QDBusMessage message =
        QDBusMessage::createMethodCall(u"org.kde.KWin.ScreenShot2"_s, u"/org/kde/KWin/ScreenShot2"_s, u"org.kde.KWin.ScreenShot2"_s, u"CaptureScreen"_s);
    const QVariantMap options{{u"native-resolution"_s, true}, {u"include-cursor"_s, false}};
    message.setArguments({screenName, options, QVariant::fromValue(QDBusUnixFileDescriptor(fds[1]))});
    const QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(message, 4000);
    // KWin holds its own copy of the write end; ours closed, the read end sees the end of the data.
    ::close(fds[1]);
    const auto readFd = std::make_shared<CaptureReadFd>(fds[0]);

    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, readFd, screenName] {
        watcher->deleteLater();
        const QDBusPendingReply<QVariantMap> reply = *watcher;
        if (reply.isError()) {
            Q_EMIT failed(screenName, reply.error().message());
            return;
        }
        auto *reader = new QFutureWatcher<QImage>(this);
        connect(reader, &QFutureWatcher<QImage>::finished, this, [this, reader, screenName] {
            reader->deleteLater();
            const QImage image = reader->result();
            if (image.isNull()) {
                Q_EMIT failed(screenName, u"KWin's picture could not be read"_s);
            } else {
                Q_EMIT captured(screenName, image);
            }
        });
        reader->setFuture(QtConcurrent::run(readRawImage, readFd->release(), reply.value()));
    });
}
