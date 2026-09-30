/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "glyphs.h"

#include <QHash>
#include <QtMath>

#include <cmath>

namespace PlasmaFusion
{

namespace
{

// SVG 1.1 F.6.5: endpoint to centre parameterisation (x-axis rotation 0, as in every glyph).
void svgArcTo(QPainterPath &path, const QPointF &p0, qreal rx, qreal ry, bool largeArc, bool sweep, const QPointF &p1)
{
    if (p0 == p1) {
        return;
    }
    rx = std::abs(rx);
    ry = std::abs(ry);
    if (rx == 0 || ry == 0) {
        path.lineTo(p1);
        return;
    }
    const qreal x1 = (p0.x() - p1.x()) / 2;
    const qreal y1 = (p0.y() - p1.y()) / 2;
    const qreal lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry);
    if (lambda > 1) {
        const qreal s = std::sqrt(lambda);
        rx *= s;
        ry *= s;
    }
    const qreal num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1;
    const qreal den = rx * rx * y1 * y1 + ry * ry * x1 * x1;
    qreal coef = den == 0 ? 0 : std::sqrt(std::max<qreal>(0, num / den));
    if (largeArc == sweep) {
        coef = -coef;
    }
    const qreal cxp = coef * (rx * y1 / ry);
    const qreal cyp = coef * -(ry * x1 / rx);
    const qreal cx = cxp + (p0.x() + p1.x()) / 2;
    const qreal cy = cyp + (p0.y() + p1.y()) / 2;
    auto angle = [](qreal ux, qreal uy, qreal vx, qreal vy) {
        return std::atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    };
    const qreal theta1 = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry);
    qreal delta = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry);
    if (!sweep && delta > 0) {
        delta -= 2 * M_PI;
    } else if (sweep && delta < 0) {
        delta += 2 * M_PI;
    }
    // Qt angles grow counter-clockwise on screen, SVG angles clockwise (y points down).
    path.arcTo(QRectF(cx - rx, cy - ry, 2 * rx, 2 * ry), -qRadiansToDegrees(theta1), -qRadiansToDegrees(delta));
}

} // namespace

QPainterPath parseSvgPath(const QString &d)
{
    QPainterPath path;
    const int n = d.size();
    int i = 0;
    QChar cmd;
    QPointF cur;
    QPointF start;

    auto skipSeparators = [&] {
        while (i < n && (d[i].isSpace() || d[i] == QLatin1Char(','))) {
            ++i;
        }
    };
    auto number = [&](bool *ok) -> qreal {
        skipSeparators();
        const int begin = i;
        if (i < n && (d[i] == QLatin1Char('-') || d[i] == QLatin1Char('+'))) {
            ++i;
        }
        bool dot = false;
        bool exp = false;
        while (i < n) {
            const QChar c = d[i];
            if (c.isDigit()) {
                ++i;
            } else if (c == QLatin1Char('.') && !dot && !exp) {
                dot = true;
                ++i;
            } else if ((c == QLatin1Char('e') || c == QLatin1Char('E')) && !exp) {
                exp = true;
                ++i;
                if (i < n && (d[i] == QLatin1Char('-') || d[i] == QLatin1Char('+'))) {
                    ++i;
                }
            } else {
                break;
            }
        }
        *ok = i > begin;
        return QStringView(d).mid(begin, i - begin).toDouble();
    };
    auto flag = [&](bool *ok) -> bool {
        skipSeparators();
        if (i < n && (d[i] == QLatin1Char('0') || d[i] == QLatin1Char('1'))) {
            *ok = true;
            return d[i++] == QLatin1Char('1');
        }
        *ok = false;
        return false;
    };

    while (true) {
        skipSeparators();
        if (i >= n) {
            break;
        }
        if (d[i].isLetter()) {
            cmd = d[i++];
        } else if (cmd.isNull()) {
            break; // garbage
        }
        const bool rel = cmd.isLower();
        const QPointF base = rel ? cur : QPointF();
        bool ok = true;
        switch (cmd.toLower().unicode()) {
        case 'm': {
            const qreal x = number(&ok);
            const qreal y = number(&ok);
            if (!ok) {
                return path;
            }
            cur = base + QPointF(x, y);
            start = cur;
            path.moveTo(cur);
            cmd = rel ? QLatin1Char('l') : QLatin1Char('L'); // further pairs are line-tos
            break;
        }
        case 'l': {
            const qreal x = number(&ok);
            const qreal y = number(&ok);
            if (!ok) {
                return path;
            }
            cur = base + QPointF(x, y);
            path.lineTo(cur);
            break;
        }
        case 'h': {
            const qreal x = number(&ok);
            if (!ok) {
                return path;
            }
            cur = QPointF(rel ? cur.x() + x : x, cur.y());
            path.lineTo(cur);
            break;
        }
        case 'v': {
            const qreal y = number(&ok);
            if (!ok) {
                return path;
            }
            cur = QPointF(cur.x(), rel ? cur.y() + y : y);
            path.lineTo(cur);
            break;
        }
        case 'c': {
            qreal v[6];
            for (qreal &value : v) {
                value = number(&ok);
            }
            if (!ok) {
                return path;
            }
            const QPointF c1 = base + QPointF(v[0], v[1]);
            const QPointF c2 = base + QPointF(v[2], v[3]);
            cur = base + QPointF(v[4], v[5]);
            path.cubicTo(c1, c2, cur);
            break;
        }
        case 'a': {
            const qreal rx = number(&ok);
            const qreal ry = number(&ok);
            number(&ok); // x-axis rotation: always 0 in the glyphs
            const bool large = flag(&ok);
            const bool sweep = flag(&ok);
            const qreal x = number(&ok);
            const qreal y = number(&ok);
            if (!ok) {
                return path;
            }
            const QPointF end = base + QPointF(x, y);
            svgArcTo(path, cur, rx, ry, large, sweep, end);
            cur = end;
            break;
        }
        case 'z':
            path.closeSubpath();
            cur = start;
            cmd = QChar();
            break;
        default:
            return path; // unsupported command
        }
    }
    return path;
}

const QPainterPath &glyphPath(Glyph glyph)
{
    static QHash<int, QPainterPath> cache;
    auto it = cache.constFind(int(glyph));
    if (it != cache.constEnd()) {
        return *it;
    }
    QString data;
    switch (glyph) {
    // Windows.dc.html:40-42 (and the Aurorae part's extra buttons, drawn in the same style)
    case Glyph::Minimize:
        data = QStringLiteral("M6 12h12");
        break;
    case Glyph::Maximize:
        data = QStringLiteral("M8 6h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z");
        break;
    case Glyph::Restore:
        data = QStringLiteral(
            "M8 10h5a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2z"
            "M10 7a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2");
        break;
    case Glyph::Close:
        data = QStringLiteral("M7 7l10 10M17 7L7 17");
        break;
    case Glyph::KeepAbove:
        data = QStringLiteral("M6 5h12M12 20V9M7.5 13.5L12 9l4.5 4.5");
        break;
    case Glyph::KeepBelow:
        data = QStringLiteral("M6 19h12M12 4v11M7.5 10.5L12 15l4.5-4.5");
        break;
    case Glyph::OnAllDesktops:
        data = QStringLiteral("M9 4h6M10 4v5l-3 4h10l-3-4V4M12 13v7");
        break;
    case Glyph::Shade:
        data = QStringLiteral("M5 6h14M7.5 15.5L12 11l4.5 4.5");
        break;
    case Glyph::Unshade:
        data = QStringLiteral("M5 6h14M7.5 11L12 15.5l4.5-4.5");
        break;
    case Glyph::ContextHelp:
        data = QStringLiteral("M9.5 9a2.5 2.5 0 1 1 3.6 2.25c-.66.32-1.1.98-1.1 1.72V14M12 18h.01");
        break;
    case Glyph::ApplicationMenu:
        data = QStringLiteral("M5 7h14M5 12h14M5 17h14");
        break;
    case Glyph::ExcludeFromCapture:
        data = QStringLiteral("M4 9V7a2 2 0 0 1 2-2h2M16 5h2a2 2 0 0 1 2 2v2M20 15v2a2 2 0 0 1-2 2h-2M8 19H6a2 2 0 0 1-2-2v-2M5 5l14 14");
        break;
    case Glyph::None:
        break;
    }
    return *cache.insert(int(glyph), parseSvgPath(data));
}

} // namespace PlasmaFusion
