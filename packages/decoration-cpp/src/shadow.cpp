/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "shadow.h"

#include <KDecoration3/DecorationShadow>

#include <QHash>
#include <QPainter>
#include <QPainterPath>

#include <cmath>
#include <vector>

namespace PlasmaFusion
{

namespace
{

QHash<QString, std::shared_ptr<KDecoration3::DecorationShadow>> s_cache;

QPainterPath roundedPath(const QRectF &r, qreal radius, bool tl, bool tr, bool br, bool bl)
{
    QPainterPath p;
    radius = std::max<qreal>(0, std::min(radius, std::min(r.width(), r.height()) / 2));
    const qreal rtl = tl ? radius : 0;
    const qreal rtr = tr ? radius : 0;
    const qreal rbr = br ? radius : 0;
    const qreal rbl = bl ? radius : 0;
    p.moveTo(r.left() + rtl, r.top());
    p.lineTo(r.right() - rtr, r.top());
    if (rtr > 0) {
        p.arcTo(QRectF(r.right() - 2 * rtr, r.top(), 2 * rtr, 2 * rtr), 90, -90);
    }
    p.lineTo(r.right(), r.bottom() - rbr);
    if (rbr > 0) {
        p.arcTo(QRectF(r.right() - 2 * rbr, r.bottom() - 2 * rbr, 2 * rbr, 2 * rbr), 0, -90);
    }
    p.lineTo(r.left() + rbl, r.bottom());
    if (rbl > 0) {
        p.arcTo(QRectF(r.left(), r.bottom() - 2 * rbl, 2 * rbl, 2 * rbl), 270, -90);
    }
    p.lineTo(r.left(), r.top() + rtl);
    if (rtl > 0) {
        p.arcTo(QRectF(r.left(), r.top(), 2 * rtl, 2 * rtl), 180, -90);
    }
    p.closeSubpath();
    return p;
}

// Box sizes whose triple convolution approximates a Gaussian of the given sigma.
std::vector<int> boxesForGauss(qreal sigma, int n)
{
    const qreal wIdeal = std::sqrt((12 * sigma * sigma / n) + 1);
    int wl = int(std::floor(wIdeal));
    if (wl % 2 == 0) {
        wl--;
    }
    const int wu = wl + 2;
    const qreal mIdeal = (12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4.0 * wl - 4);
    const int m = int(std::round(mIdeal));
    std::vector<int> sizes;
    for (int i = 0; i < n; ++i) {
        sizes.push_back(i < m ? wl : wu);
    }
    return sizes;
}

// One box blur pass along a line of `count` samples spaced `stride` apart (zeros outside).
void boxLine(const float *src, float *dst, int count, int stride, int radius)
{
    const float scale = 1.0f / float(2 * radius + 1);
    float acc = 0;
    for (int i = 0; i <= radius && i < count; ++i) {
        acc += src[i * stride];
    }
    for (int i = 0; i < count; ++i) {
        dst[i * stride] = acc * scale;
        const int add = i + radius + 1;
        const int sub = i - radius;
        if (add < count) {
            acc += src[add * stride];
        }
        if (sub >= 0) {
            acc -= src[sub * stride];
        }
    }
}

void gaussianBlur(std::vector<float> &buf, int w, int h, qreal sigma)
{
    if (sigma <= 0) {
        return;
    }
    std::vector<float> tmp(buf.size());
    for (int size : boxesForGauss(sigma, 3)) {
        const int radius = (size - 1) / 2;
        for (int y = 0; y < h; ++y) {
            boxLine(buf.data() + y * w, tmp.data() + y * w, w, 1, radius);
        }
        for (int x = 0; x < w; ++x) {
            boxLine(tmp.data() + x, buf.data() + x, h, w, radius);
        }
    }
}

} // namespace

QString ShadowParams::key() const
{
    return QStringLiteral("%1/%2/%3/%4/%5/%6/%7%8%9%10")
        .arg(color.name(QColor::HexRgb))
        .arg(opacity, 0, 'f', 4)
        .arg(blur)
        .arg(dy)
        .arg(frameRadius, 0, 'f', 3)
        .arg(outline, 0, 'f', 3)
        .arg(int(topLeft))
        .arg(int(topRight))
        .arg(int(bottomRight))
        .arg(int(bottomLeft));
}

ShadowImage renderShadow(const ShadowParams &p)
{
    const qreal sigma = p.blur / 2.0;
    const int ext = int(std::ceil(3 * sigma)); // reach of the blur: beyond it the shadow is < 0.2 %
    const qreal outerRadius = p.frameRadius + p.outline;
    // The frame in the image: large enough that the middle of each side is past every corner's
    // influence, so KWin can stretch the centre row / column.
    const int box = 2 * (ext + int(std::ceil(outerRadius)) + 2) + 1;
    const int dy = std::clamp(p.dy, -ext + 1, ext - 1);
    const int w = 2 * ext + box;
    const int h = 2 * ext + box;
    const QRectF frame(ext, ext - dy, box, box);

    // Shape: frame + outline, moved down by dy.
    QImage mask(w, h, QImage::Format_Alpha8);
    mask.fill(0);
    {
        QPainter painter(&mask);
        painter.setRenderHint(QPainter::Antialiasing);
        painter.setPen(Qt::NoPen);
        painter.setBrush(Qt::black);
        const QRectF shape = frame.adjusted(-p.outline, -p.outline, p.outline, p.outline).translated(0, dy);
        painter.drawPath(roundedPath(shape, outerRadius, p.topLeft, p.topRight, p.bottomRight, p.bottomLeft));
    }

    std::vector<float> buf(size_t(w) * size_t(h));
    for (int y = 0; y < h; ++y) {
        const uchar *line = mask.constScanLine(y);
        for (int x = 0; x < w; ++x) {
            buf[size_t(y) * w + x] = line[x] / 255.0f;
        }
    }
    gaussianBlur(buf, w, h, sigma);

    QImage image(w, h, QImage::Format_ARGB32_Premultiplied);
    const qreal r = p.color.redF();
    const qreal g = p.color.greenF();
    const qreal b = p.color.blueF();
    const qreal opacity = std::clamp<qreal>(p.opacity * p.color.alphaF(), 0, 1);
    for (int y = 0; y < h; ++y) {
        auto *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < w; ++x) {
            const qreal a = std::clamp<qreal>(buf[size_t(y) * w + x] * opacity, 0, 1);
            line[x] = qRgba(int(std::lround(r * a * 255)), int(std::lround(g * a * 255)), int(std::lround(b * a * 255)), int(std::lround(a * 255)));
        }
    }

    // Cut out the frame (1 px inside it, so no seam shows at fractional scales).
    {
        QPainter painter(&image);
        painter.setRenderHint(QPainter::Antialiasing);
        painter.setPen(Qt::NoPen);
        painter.setBrush(Qt::black);
        painter.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        painter.drawPath(roundedPath(frame.adjusted(1, 1, -1, -1), std::max<qreal>(0, p.frameRadius - 1), p.topLeft, p.topRight, p.bottomRight, p.bottomLeft));
    }

    ShadowImage result;
    result.image = image;
    result.padding = QMarginsF(ext, ext - dy, ext, ext + dy);
    result.innerRect = QRectF(ext + box / 2, ext - dy + box / 2, 1, 1);
    return result;
}

std::shared_ptr<KDecoration3::DecorationShadow> shadowFor(const ShadowParams &params)
{
    const QString key = params.key();
    auto it = s_cache.constFind(key);
    if (it != s_cache.constEnd()) {
        return *it;
    }
    const ShadowImage rendered = renderShadow(params);
    auto shadow = std::make_shared<KDecoration3::DecorationShadow>();
    shadow->setPadding(rendered.padding);
    shadow->setInnerShadowRect(rendered.innerRect);
    shadow->setShadow(rendered.image);
    s_cache.insert(key, shadow);
    return shadow;
}

void clearShadowCache()
{
    s_cache.clear();
}

} // namespace PlasmaFusion
