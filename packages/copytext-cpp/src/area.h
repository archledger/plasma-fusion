// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QRect>
#include <QRectF>

// The box drawn in a window's logical pixels as the native pixels of that screen's picture (scale
// DPR, the picture's device pixel ratio): every pixel the box touches, inside the picture.
inline QRect nativeArea(const QRectF &box, qreal dpr, const QRect &picture)
{
    const QRectF native(box.x() * dpr, box.y() * dpr, box.width() * dpr, box.height() * dpr);
    return native.toAlignedRect().intersected(picture);
}
