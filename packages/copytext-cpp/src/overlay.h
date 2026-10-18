// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "capture.h"

#include <QElapsedTimer>
#include <QHash>
#include <QImage>
#include <QList>
#include <QObject>
#include <QQmlEngine>
#include <QRectF>

class QQmlComponent;
class QQuickWindow;
class CaptureImages;

// The selection overlay (CopyText board), on the session bus as org.plasmafusion.CopyTextOverlay:
// Start() captures every screen through KWin and shows the still screens under the veil; the box
// drawn on one is cropped at native resolution and handed to plasma-fusion-copytext --image, which
// reads, copies and notifies. Esc, or a click without a drag, ends it without a word.
class Overlay : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.plasmafusion.CopyTextOverlay")
public:
    explicit Overlay(QObject *parent = nullptr);

public Q_SLOTS:
    Q_SCRIPTABLE void Start();

private Q_SLOTS:
    void chosen(const QString &screenName, const QRectF &area);
    void cancelled();

private:
    void showAll();
    void closeAll();
    void read(const QImage &area);
    void fallBack();
    QString helper() const;

    QQmlEngine m_engine;
    QQmlComponent *m_component = nullptr;
    CaptureImages *m_images = nullptr;
    ScreenCapture *m_capture = nullptr; // this Start()'s
    QHash<QString, QImage> m_pictures;
    QList<QQuickWindow *> m_windows;
    QElapsedTimer m_clock;
    int m_waiting = 0;
    int m_serial = 0;
    bool m_active = false;
    bool m_reading = false; // the helper reads the chosen area
};
