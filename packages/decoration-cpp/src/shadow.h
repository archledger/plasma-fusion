/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QColor>
#include <QImage>
#include <QMarginsF>

#include <memory>

namespace KDecoration3
{
class DecorationShadow;
}

namespace PlasmaFusion
{

// A CSS box-shadow "0 <dy> <blur> <color at opacity>" of the window shape: the frame grown by the
// outline, corners rounded where the window is rounded.
struct ShadowParams {
    QColor color = Qt::black;
    qreal opacity = 0.55;
    int blur = 90; // CSS blur radius: Gaussian sigma = blur / 2
    int dy = 34;
    qreal frameRadius = 13; // corner radius of the frame (the outline adds its thickness outside)
    qreal outline = 1;
    bool topLeft = true, topRight = true, bottomRight = true, bottomLeft = true;

    QString key() const;
};

struct ShadowImage {
    QImage image;
    QMarginsF padding; // image area outside the frame
    QRectF innerRect; // the stretched centre
};

// Renders the shadow (three box blurs = Gaussian, like browsers do); the frame itself is cut out
// so translucent windows do not show it.
ShadowImage renderShadow(const ShadowParams &params);

// Shared, cached DecorationShadow objects (one per parameter set; cleared with clearShadowCache()).
std::shared_ptr<KDecoration3::DecorationShadow> shadowFor(const ShadowParams &params);
void clearShadowCache();

} // namespace PlasmaFusion
