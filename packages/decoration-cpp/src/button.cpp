/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "button.h"

#include "decoration.h"

#include <KDecoration3/DecoratedWindow>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QIcon>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QTimer>
#include <QVariantAnimation>

#include <cmath>

namespace PlasmaFusion
{

using KDecoration3::DecorationButtonType;

namespace
{
constexpr int s_hoverDuration = 150; // ms at AnimationDurationFactor 1
constexpr int s_pressDuration = 80;

QColor darker(const QColor &c, qreal amount)
{
    // the pressed look: the colour under 20 % black (Aurorae part: PRESS_DARKEN)
    return QColor::fromRgbF(c.redF() * (1 - amount), c.greenF() * (1 - amount), c.blueF() * (1 - amount), c.alphaF());
}

// Glyph strokes: 1.8 units of the 24 grid (Windows.dc.html svg.i), centred on a device pixel so a
// one-pixel stroke (the minimize dash) lands on one pixel row, as in the board raster.
void paintGlyph(QPainter *painter, Glyph glyph, const QPointF &center, qreal size, qreal strokeUnits, const QColor &color, qreal scale)
{
    if (glyph == Glyph::None || color.alpha() == 0) {
        return;
    }
    const QPointF c((std::floor(center.x() * scale) + 0.5) / scale, (std::floor(center.y() * scale) + 0.5) / scale);
    QTransform t;
    t.translate(c.x() - size / 2, c.y() - size / 2);
    t.scale(size / 24.0, size / 24.0);
    const QPainterPath path = t.map(glyphPath(glyph));
    QPen pen(color, strokeUnits * size / 24.0, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
    painter->setPen(pen);
    painter->setBrush(Qt::NoBrush);
    painter->drawPath(path);
}
} // namespace

Button::Button(DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent)
    : KDecoration3::DecorationButton(type, decoration, parent)
{
    init();
}

Button::Button(QObject *parent, const QVariantList &args)
    : Button(args.value(0).value<DecorationButtonType>(), args.value(1).value<KDecoration3::Decoration *>(), parent)
{
}

Button::~Button() = default;

void Button::init()
{
    m_hoverAnimation = new QVariantAnimation(this);
    m_hoverAnimation->setEasingCurve(QEasingCurve::OutCubic);
    connect(m_hoverAnimation, &QVariantAnimation::valueChanged, this, [this](const QVariant &v) {
        m_hover = v.toReal();
        update();
    });
    m_pressAnimation = new QVariantAnimation(this);
    m_pressAnimation->setEasingCurve(QEasingCurve::OutCubic);
    connect(m_pressAnimation, &QVariantAnimation::valueChanged, this, [this](const QVariant &v) {
        m_press = v.toReal();
        update();
    });

    connect(this, &KDecoration3::DecorationButton::hoveredChanged, this, &Button::onHoveredChanged);
    connect(this, &KDecoration3::DecorationButton::pressedChanged, this, [this](bool pressed) {
        animateTo(m_pressAnimation, m_press, pressed ? 1 : 0, s_pressDuration);
    });

    if (type() == DecorationButtonType::Maximize) {
        m_snapTimer = new QTimer(this);
        m_snapTimer->setSingleShot(true);
        m_snapTimer->setInterval(SnapDelay);
        connect(m_snapTimer, &QTimer::timeout, this, &Button::onSnapTimeout);
    }
    if (type() == DecorationButtonType::Menu) {
        if (auto *w = decoration() ? decoration()->window() : nullptr) {
            connect(w, &KDecoration3::DecoratedWindow::iconChanged, this, [this] {
                update();
            });
        }
    }
}

Decoration *Button::fusionDecoration() const
{
    return qobject_cast<Decoration *>(decoration());
}

void Button::setVisualRect(const QRectF &rect)
{
    if (m_visual != rect) {
        m_visual = rect;
        update();
    }
}

void Button::animateTo(QVariantAnimation *animation, qreal current, qreal target, int baseDuration)
{
    Decoration *deco = fusionDecoration();
    const int duration = deco ? deco->animationDuration(baseDuration) : baseDuration;
    animation->stop();
    if (duration <= 0 || qFuzzyCompare(current, target)) {
        if (animation == m_hoverAnimation) {
            m_hover = target;
        } else {
            m_press = target;
        }
        update();
        return;
    }
    animation->setDuration(int(duration * std::abs(target - current)) + 1);
    animation->setStartValue(current);
    animation->setEndValue(target);
    animation->start();
}

void Button::onHoveredChanged(bool hovered)
{
    animateTo(m_hoverAnimation, m_hover, hovered ? 1 : 0, s_hoverDuration);
    if (Decoration *deco = fusionDecoration()) {
        deco->buttonHoverChanged();
    }
    if (!m_snapTimer) {
        return;
    }
    if (hovered && !isPressed()) {
        // Hovering the maximize button of the active window for 600 ms opens the snap layouts.
        Decoration *deco = fusionDecoration();
        if (deco && deco->snapTriggerAllowed()) {
            m_snapMode = SnapMode::Hover;
            m_snapTimer->start();
        }
    } else if (!hovered && m_snapMode == SnapMode::Hover) {
        m_snapTimer->stop();
        m_snapMode = SnapMode::None;
    }
}

void Button::mousePressEvent(QMouseEvent *event)
{
    KDecoration3::DecorationButton::mousePressEvent(event);
    if (!m_snapTimer) {
        return;
    }
    // A press cancels the hover trigger; holding the left button starts the hold trigger.
    m_snapTimer->stop();
    m_snapMode = SnapMode::None;
    m_snapFiredOnHold = false;
    Decoration *deco = fusionDecoration();
    if (event->button() == Qt::LeftButton && isPressed() && deco && deco->snapTriggerAllowed()) {
        m_snapMode = SnapMode::Hold;
        m_snapTimer->start();
    }
}

void Button::mouseReleaseEvent(QMouseEvent *event)
{
    if (m_snapTimer) {
        m_snapTimer->stop();
        m_snapMode = SnapMode::None;
    }
    if (m_snapFiredOnHold && event->button() == Qt::LeftButton) {
        // The hold opened the snap layouts: release without toggling maximize (the base class
        // clicks only when the release is inside the button).
        m_snapFiredOnHold = false;
        QMouseEvent outside(event->type(),
                            QPointF(-1e6, -1e6),
                            event->globalPosition(),
                            event->button(),
                            event->buttons(),
                            event->modifiers(),
                            event->pointingDevice());
        KDecoration3::DecorationButton::mouseReleaseEvent(&outside);
        event->setAccepted(outside.isAccepted());
        return;
    }
    KDecoration3::DecorationButton::mouseReleaseEvent(event);
}

void Button::onSnapTimeout()
{
    Decoration *deco = fusionDecoration();
    const SnapMode mode = m_snapMode;
    m_snapMode = SnapMode::None;
    if (!deco || !deco->snapTriggerAllowed()) {
        return;
    }
    if (mode == SnapMode::Hover && isHovered() && !isPressed() && !deco->snapHoverFired()) {
        deco->setSnapHoverFired();
        invokeSnapLayouts();
    } else if (mode == SnapMode::Hold && isPressed()) {
        m_snapFiredOnHold = true;
        invokeSnapLayouts();
    }
}

void Button::invokeSnapLayouts()
{
    if (Decoration *deco = fusionDecoration()) {
        deco->requestHideToolTip();
    }
    // The KWin global shortcut registered by the plasmafusion-snap script, through kglobalaccel
    // (hosted by KWin itself): asynchronous, never wait for the reply inside the compositor.
    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"),
                                                          QStringLiteral("/component/kwin"),
                                                          QStringLiteral("org.kde.kglobalaccel.Component"),
                                                          QStringLiteral("invokeShortcut"));
    message << QStringLiteral("Plasma Fusion: Snap Layouts");
    QDBusConnection::sessionBus().asyncCall(message);
}

Glyph Button::glyph() const
{
    switch (type()) {
    case DecorationButtonType::Minimize:
        return Glyph::Minimize;
    case DecorationButtonType::Maximize:
        return isChecked() ? Glyph::Restore : Glyph::Maximize;
    case DecorationButtonType::Close:
        return Glyph::Close;
    case DecorationButtonType::KeepAbove:
        return Glyph::KeepAbove;
    case DecorationButtonType::KeepBelow:
        return Glyph::KeepBelow;
    case DecorationButtonType::OnAllDesktops:
        return Glyph::OnAllDesktops;
    case DecorationButtonType::Shade:
        return isChecked() ? Glyph::Unshade : Glyph::Shade;
    case DecorationButtonType::ContextHelp:
        return Glyph::ContextHelp;
    case DecorationButtonType::ApplicationMenu:
        return Glyph::ApplicationMenu;
    case DecorationButtonType::ExcludeFromCapture:
        return Glyph::ExcludeFromCapture;
    default:
        return Glyph::None;
    }
}

void Button::paint(QPainter *painter, const QRectF &repaintArea)
{
    Q_UNUSED(repaintArea)
    if (!isVisible() || type() == DecorationButtonType::Spacer) {
        return;
    }
    Decoration *deco = fusionDecoration();
    if (!deco) {
        return;
    }
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    if (type() == DecorationButtonType::Menu) {
        paintIcon(painter);
    } else if (deco->buttonStyle() == ButtonStyle::LeftCircles) {
        paintDot(painter);
    } else {
        paintCircle(painter);
    }
    painter->restore();
}

void Button::paintIcon(QPainter *painter) const
{
    const Decoration *deco = fusionDecoration();
    const auto *window = deco->window();
    QIcon icon = window ? window->icon() : QIcon();
    if (icon.isNull()) {
        icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
    }
    QRectF rect = m_visual.isEmpty() ? QRectF(geometry().center() - QPointF(13, 13), QSizeF(26, 26)) : m_visual;
    const qreal dpr = painter->device() ? painter->device()->devicePixelRatioF() : 1.0;
    // Snap the icon to device pixels so it is not resampled.
    rect =
        QRectF(std::round(rect.x() * dpr) / dpr, std::round(rect.y() * dpr) / dpr, std::round(rect.width() * dpr) / dpr, std::round(rect.height() * dpr) / dpr);
    const QPixmap pixmap = icon.pixmap(rect.size().toSize(), dpr);
    // Windows.dc.html:95 inactive windows show the icon at 60 %
    painter->setOpacity(painter->opacity() * (0.6 + 0.4 * deco->activeProgress()));
    painter->drawPixmap(rect, pixmap, QRectF(QPointF(0, 0), QSizeF(pixmap.size())));
}

void Button::paintCircle(QPainter *painter) const
{
    const Decoration *deco = fusionDecoration();
    const Colors &c = deco->colors();
    const Metrics &m = deco->metrics();
    const qreal opacity = deco->buttonsOpacity();
    if (opacity <= 0.001) {
        return;
    }
    painter->setOpacity(painter->opacity() * opacity);

    QRectF circle = m_visual;
    if (circle.isEmpty()) {
        const qreal s = std::min(geometry().width(), geometry().height()) * m.circle / (m.circle + m.gap);
        circle = QRectF(geometry().center() - QPointF(s / 2, s / 2), QSizeF(s, s));
    }
    const qreal t = deco->activeProgress();
    const bool close = type() == DecorationButtonType::Close;
    // Toggle buttons that are on (keep above, on all desktops, ...) keep the pressed accent look.
    const bool toggled = isCheckable() && isChecked() && type() != DecorationButtonType::Maximize && type() != DecorationButtonType::Shade;

    QColor fill;
    QColor glyphColor;
    qreal ring = 0;
    if (!isEnabled()) {
        fill = withAlpha(c.tint, c.fillDisabled);
        glyphColor = withAlpha(c.glyphActive, 0.30);
    } else {
        // Rest: Main.dc.html:94-96 (inactive) and 145-147 (active): tint 7 % / 10 %, close red only
        // on the active window (Windows.dc.html spec 3).
        const QColor restActive = close ? s_closeRed : withAlpha(c.tint, c.fillActive);
        const QColor restInactive = withAlpha(c.tint, c.fillInactive);
        fill = mix(restInactive, restActive, t);
        glyphColor = mix(c.glyphInactive, close ? QColor(Qt::white) : c.glyphActive, t);
        // Hover (Windows.dc.html:108): accent fill (close: red), white glyph, 3 px ring.
        const qreal hot = std::max(m_hover, toggled ? 1.0 : 0.0);
        const QColor hotFill = close ? s_closeRed : c.accent;
        fill = mix(fill, hotFill, hot);
        glyphColor = mix(glyphColor, Qt::white, hot);
        ring = m_hover;
        // Pressed (and toggled on): the hover look under 20 % black.
        const qreal press = std::max(m_press * m_hover, toggled ? 1.0 : 0.0);
        if (press > 0) {
            fill = darker(fill, 0.20 * press);
        }
    }

    painter->setPen(Qt::NoPen);
    if (ring > 0.001) {
        const QColor ringColor = close ? withAlpha(s_closeRed, 0.30) : c.accentRing;
        const qreal grow = 3.0 * circle.width() / 28.0;
        painter->setBrush(withAlpha(ringColor, ring));
        painter->drawEllipse(circle.adjusted(-grow, -grow, grow, grow));
    }
    painter->setBrush(fill);
    painter->drawEllipse(circle);
    paintGlyph(painter, glyph(), circle.center(), m.glyph * circle.width() / m.circle, 1.8, glyphColor, 1.0 / deco->devicePixel());
}

void Button::paintDot(QPainter *painter) const
{
    // Windows.dc.html:116-125: plain 13 px circles at rest (#8891aa); hovering any of them shows all
    // in colour with glyphs, close red, the others the accent (the Aurorae -Left themes' group hover).
    const Decoration *deco = fusionDecoration();
    const Colors &c = deco->colors();
    const Metrics &m = deco->metrics();
    QRectF dot = m_visual;
    if (dot.isEmpty()) {
        dot = QRectF(geometry().center() - QPointF(m.dot / 2, m.dot / 2), QSizeF(m.dot, m.dot));
    }
    const qreal t = deco->activeProgress();
    const qreal group = deco->groupHoverProgress();
    const bool close = type() == DecorationButtonType::Close;
    QColor fill = withAlpha(c.dot, c.dotInactiveOpacity + (1 - c.dotInactiveOpacity) * t);
    QColor glyphColor = withAlpha(QColor(Qt::white), group);
    if (!isEnabled()) {
        fill = withAlpha(c.dot, 0.30);
        glyphColor = withAlpha(QColor(Qt::white), 0.5 * group);
    } else {
        fill = mix(fill, close ? s_closeRed : c.accent, group);
        const bool toggled = isCheckable() && isChecked() && type() != DecorationButtonType::Maximize;
        const qreal press = std::max(m_press * m_hover, toggled ? 1.0 : 0.0);
        if (press > 0) {
            fill = darker(fill, 0.20 * press);
        }
    }
    painter->setPen(Qt::NoPen);
    painter->setBrush(fill);
    painter->drawEllipse(dot);
    paintGlyph(painter, glyph(), dot.center(), m.dotGlyph * dot.width() / m.dot, 2.4, glyphColor, 1.0 / deco->devicePixel());
}

} // namespace PlasmaFusion

#include "moc_button.cpp"
