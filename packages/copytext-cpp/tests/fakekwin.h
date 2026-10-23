// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMessage>
#include <QDBusUnixFileDescriptor>
#include <QFuture>
#include <QHash>
#include <QImage>
#include <QObject>
#include <QStringList>
#include <QtConcurrentRun>

#include <cerrno>
#include <unistd.h>
#include <utility>

// A stand-in for KWin's ScreenShot2 on the private bus (dbus-run-session): CaptureScreen writes the
// screen's picture into the pipe and answers with its description, as KWin 6.7.5 does. A screen
// without a picture of its own gets a small known one (40 x 30 at scale 1.75, red in the last
// pixel); a refused screen, or every screen with refuseAll, gets KWin's refusal.
class FakeKWin : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.KWin.ScreenShot2")
public:
    QHash<QString, QImage> pictures; // by screen name; the picture's device pixel ratio is its scale
    QStringList refused{QStringLiteral("refused")};
    bool refuseAll = false;
    bool deferReplies = false;
    QStringList asked; // the screens asked for, in order
    QVariantMap lastOptions;

    int deferredCount() const
    {
        return m_deferred.size();
    }

    void refuseDeferred()
    {
        for (const auto &[bus, request] : std::as_const(m_deferred)) {
            bus.send(request.createErrorReply(QStringLiteral("org.kde.KWin.ScreenShot2.Error.NoAuthorized"), QStringLiteral("Deferred test refusal")));
        }
        m_deferred.clear();
    }

    ~FakeKWin() override
    {
        for (QFuture<void> &write : m_writes) {
            write.waitForFinished();
        }
    }

    static QImage smallPicture()
    {
        QImage image(40, 30, QImage::Format_ARGB32);
        image.fill(QColor(0x5b, 0x9d, 0xff));
        image.setPixelColor(39, 29, Qt::red);
        image.setDevicePixelRatio(1.75);
        return image;
    }

public Q_SLOTS:
    QVariantMap CaptureScreen(const QString &name, const QVariantMap &options, const QDBusUnixFileDescriptor &pipe)
    {
        asked.append(name);
        lastOptions = options;
        if (deferReplies) {
            setDelayedReply(true);
            m_deferred.append({connection(), message()});
            return {};
        }
        if (refuseAll || refused.contains(name)) {
            sendErrorReply(QStringLiteral("org.kde.KWin.ScreenShot2.Error.NoAuthorized"), QStringLiteral("The process is not authorized to take a screenshot"));
            return {};
        }
        const QImage image = pictures.value(name, smallPicture());
        // From another thread, as KWin writes: a picture larger than the pipe's buffer would block
        // here, and the reader reads only after this answer.
        const int fd = dup(pipe.fileDescriptor());
        m_writes.append(QtConcurrent::run([fd, image] {
            const char *data = reinterpret_cast<const char *>(image.constBits());
            qsizetype left = image.sizeInBytes();
            while (left > 0) {
                const ssize_t written = ::write(fd, data, left);
                if (written < 0 && errno == EINTR) {
                    continue;
                }
                if (written <= 0) {
                    break;
                }
                data += written;
                left -= written;
            }
            ::close(fd);
        }));
        return {{QStringLiteral("type"), QStringLiteral("raw")},
                {QStringLiteral("width"), uint(image.width())},
                {QStringLiteral("height"), uint(image.height())},
                {QStringLiteral("stride"), uint(image.bytesPerLine())},
                {QStringLiteral("format"), uint(image.format())},
                {QStringLiteral("scale"), image.devicePixelRatio()},
                {QStringLiteral("screen"), name}};
    }

private:
    QList<QFuture<void>> m_writes;
    QList<std::pair<QDBusConnection, QDBusMessage>> m_deferred;
};
