// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QImage>
#include <QObject>
#include <QString>
#include <QVariantMap>

// KWin's raw picture from the pipe FD (closed after), as its answer META describes it ("type" raw,
// "width", "height", "stride", "format" as QImage::Format, "scale" the screen's device pixel ratio):
// a null image on any doubt (a short read, a format Qt does not have, a stride under the row).
QImage readRawImage(int fd, const QVariantMap &meta);

// One screen's picture from KWin (org.kde.KWin.ScreenShot2 CaptureScreen, KWin 6.7.5): KWin writes
// the raw image into a pipe passed with the call and answers with its size and format, so the
// picture is read from the pipe once the answer is in, off the main thread (several MB).
class ScreenCapture : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    // The screen by its name (QScreen::name(), KWin's output name), at its native resolution so
    // Tesseract reads the text at its real size.
    void capture(const QString &screenName);

Q_SIGNALS:
    void captured(const QString &screenName, const QImage &image);
    void failed(const QString &screenName, const QString &reason);
};
