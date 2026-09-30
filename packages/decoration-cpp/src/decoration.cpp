/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasma Fusion window decoration. Every value comes from design/boards/Windows.dc.html (anatomy,
    states, buttons on the left, maximized and tiled), Main.dc.html / MainLight.dc.html (the same
    windows on the dark and light desktop) and Colors.dc.html; the board line is named next to it.
*/
#include "decoration.h"

#include "button.h"
#include "shadow.h"
#include "tabletmode.h"

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/DecorationSettings>
#include <KDecoration3/DecorationShadow>
#include <KDecoration3/ScaleHelpers>

#include <KPluginFactory>

#include <QGuiApplication>
#include <QHoverEvent>
#include <QLoggingCategory>
#include <QMetaProperty>
#include <QPainter>
#include <QPainterPath>
#include <QTimer>
#include <QVariantAnimation>

#include <cmath>
#include <functional>

K_PLUGIN_FACTORY_WITH_JSON(PlasmaFusionDecorationFactory, "plasmafusion.json", registerPlugin<PlasmaFusion::Decoration>();
                           registerPlugin<PlasmaFusion::Button>();)

Q_LOGGING_CATEGORY(PFDECO, "org.plasmafusion.decoration", QtWarningMsg)

namespace PlasmaFusion
{

using KDecoration3::DecorationButtonType;

namespace
{
int s_decorationCount = 0;
constexpr int s_activeDuration = 150; // title / icon fade between active and inactive
constexpr int s_buttonsDuration = 150; // ShowOnHover fade
constexpr qreal s_shortScreenHeight = 800; // ADAPTIVE.md 5.12: 40 px title bars below this height

QPainterPath roundedRect(const QRectF &r, qreal radius, bool tl, bool tr, bool br, bool bl)
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

QVariantAnimation *makeAnimation(QObject *parent, qreal *target, const std::function<void()> &changed)
{
    auto *animation = new QVariantAnimation(parent);
    animation->setEasingCurve(QEasingCurve::OutCubic);
    QObject::connect(animation, &QVariantAnimation::valueChanged, parent, [target, changed](const QVariant &value) {
        *target = value.toReal();
        changed();
    });
    return animation;
}
} // namespace

Decoration::Decoration(QObject *parent, const QVariantList &args)
    : KDecoration3::Decoration(parent, args)
{
    ++s_decorationCount;
}

Decoration::~Decoration()
{
    if (--s_decorationCount == 0) {
        clearShadowCache();
    }
}

int Decoration::animationDuration(int base) const
{
    return int(std::lround(base * FusionConfig::self().animationFactor));
}

qreal Decoration::devicePixel() const
{
    const qreal scale = window()->nextScale();
    return scale > 0 ? 1.0 / scale : 1.0;
}

qreal Decoration::snap(qreal value) const
{
    const qreal scale = window()->nextScale();
    return scale > 0 ? KDecoration3::snapToPixelGrid(value, scale) : value;
}

qreal Decoration::snapUp(qreal value) const
{
    const qreal scale = window()->nextScale();
    return scale > 0 ? std::ceil(value * scale - 1e-6) / scale : value;
}

QVariant Decoration::windowProperty(const char *name) const
{
    // KWin creates the decoration with the KWin::Window as its parent; its scripting properties
    // (utility, toolbar, normalWindow, ...) tell what KDecoration3 does not. Elsewhere (the settings
    // page preview) there is no such parent and the property is simply invalid.
    const QObject *owner = parent();
    return owner ? owner->property(name) : QVariant();
}

bool Decoration::isToolWindow() const
{
    // Windows.dc.html spec 7: 32 px title bar for tool windows (utility / toolbar window types)
    for (const char *name : {"utility", "toolbar"}) {
        const QVariant v = windowProperty(name);
        if (v.isValid() && v.toBool()) {
            return true;
        }
    }
    return false;
}

bool Decoration::isShortScreen() const
{
    return m_screenHeight > 0 && m_screenHeight < s_shortScreenHeight;
}

bool Decoration::snapHoldAllowed() const
{
    return FusionConfig::self().snapHold() && windowSnappable();
}

bool Decoration::snapHoverAllowed() const
{
    // Tablet mode: hold only (TABLET.md 4.9); a finger never hovers, and a pen resting over the
    // button must not open the flyout by itself.
    return FusionConfig::self().snapHover() && !m_tablet && windowSnappable();
}

QFont Decoration::titleFont() const
{
    // spec 2: the system window-title font (kdeglobals [WM] activeFont, Manrope 10.5 pt 800 =
    // 14 px); tablet mode 15 px (TABLET.md 4.9)
    QFont font = settings()->font();
    const qreal scale = m_metrics.fontScale;
    if (!qFuzzyCompare(scale, 1.0)) {
        if (font.pixelSize() > 0) {
            font.setPixelSize(int(std::lround(font.pixelSize() * scale)));
        } else if (font.pointSizeF() > 0) {
            font.setPointSizeF(font.pointSizeF() * scale);
        }
    }
    return font;
}

bool Decoration::windowSnappable() const
{
    const auto *w = window();
    // The script's flyout acts on the active, normal, movable and resizable window only.
    if (!w->isActive() || !w->isMaximizeable() || !w->isMoveable() || !w->isResizeable()) {
        return false;
    }
    const QVariant normal = windowProperty("normalWindow");
    if (normal.isValid() && !normal.toBool()) {
        return false;
    }
    const QVariant special = windowProperty("specialWindow");
    if (special.isValid() && special.toBool()) {
        return false;
    }
    return true;
}

bool Decoration::init()
{
    FusionConfig::reload();
    m_style = FusionConfig::self().buttonStyle;
    m_activeProgress = window()->isActive() ? 1 : 0;
    TabletMode *tabletMode = TabletMode::self();
    m_tablet = tabletMode->isTablet();
    connect(tabletMode, &TabletMode::tabletChanged, this, &Decoration::onTabletChanged);
    m_buttonsOpacity = (m_style == ButtonStyle::ShowOnHover && !m_tablet) ? 0 : 1;
    // The window's screen (KWin::Window.output, a KWin::LogicalOutput): short screens get 40 px
    // title bars. Only KWin has it; elsewhere (settings-page preview) the height stays unknown.
    updateOutput();
    if (const QObject *owner = parent()) {
        const QMetaObject *mo = owner->metaObject();
        const int property = mo->indexOfProperty("output");
        const int slot = metaObject()->indexOfSlot("updateOutput()");
        if (property >= 0 && slot >= 0 && mo->property(property).hasNotifySignal()) {
            connect(owner, mo->property(property).notifySignal(), this, metaObject()->method(slot));
        }
    }

    m_activeAnimation = makeAnimation(this, &m_activeProgress, [this] {
        update();
    });
    m_buttonsAnimation = makeAnimation(this, &m_buttonsOpacity, [this] {
        update(titleBar());
    });
    m_groupAnimation = makeAnimation(this, &m_groupHover, [this] {
        update(titleBar());
    });

    const auto *w = window();
    connect(w, &KDecoration3::DecoratedWindow::activeChanged, this, &Decoration::onActiveChanged);
    connect(w, &KDecoration3::DecoratedWindow::captionChanged, this, [this] {
        update(titleBar());
    });
    connect(w, &KDecoration3::DecoratedWindow::iconChanged, this, [this] {
        update(titleBar());
    });
    for (auto signal : {&KDecoration3::DecoratedWindow::maximizedChanged,
                        &KDecoration3::DecoratedWindow::maximizedHorizontallyChanged,
                        &KDecoration3::DecoratedWindow::maximizedVerticallyChanged,
                        &KDecoration3::DecoratedWindow::shadedChanged}) {
        connect(w, signal, this, [this] {
            updateState();
            updateShadow();
            layoutButtons();
        });
    }
    connect(w, &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, [this] {
        updateState();
        updateShadow();
        layoutButtons();
    });
    connect(w, &KDecoration3::DecoratedWindow::widthChanged, this, [this] {
        updateState();
        layoutButtons();
    });
    connect(w, &KDecoration3::DecoratedWindow::paletteChanged, this, [this] {
        updateColors();
        updateState();
        updateShadow();
        update();
    });
    connect(w, &KDecoration3::DecoratedWindow::nextScaleChanged, this, [this] {
        updateState();
        updateShadow();
        layoutButtons();
    });
    connect(w, &KDecoration3::DecoratedWindow::scaleChanged, this, [this] {
        update();
    });
    connect(this, &KDecoration3::Decoration::bordersChanged, this, &Decoration::layoutButtons);

    const auto s = settings();
    connect(s.get(), &KDecoration3::DecorationSettings::reconfigured, this, &Decoration::reconfigure);
    connect(s.get(), &KDecoration3::DecorationSettings::decorationButtonsLeftChanged, this, &Decoration::updateButtonsLater);
    connect(s.get(), &KDecoration3::DecorationSettings::decorationButtonsRightChanged, this, &Decoration::updateButtonsLater);
    connect(s.get(), &KDecoration3::DecorationSettings::fontChanged, this, [this] {
        update(titleBar());
    });

    updateColors();
    updateState();
    createButtons();
    updateShadow();
    qCDebug(PFDECO) << "decoration for" << (parent() ? parent()->metaObject()->className() : "no parent") << window()->caption() << "tool" << isToolWindow()
                    << "normal" << windowProperty("normalWindow") << "style" << int(m_style) << "snap hold" << FusionConfig::self().snapHold() << "hover"
                    << FusionConfig::self().snapHover() << "scale" << window()->nextScale() << "tablet" << m_tablet << "screen height" << m_screenHeight
                    << "title" << m_metrics.titleHeight;
    m_ready = true;
    return true;
}

void Decoration::onTabletChanged(bool tablet)
{
    if (tablet == m_tablet) {
        return;
    }
    m_tablet = tablet;
    updateButtonsVisibility(false);
    updateState(); // title bar height: KWin sends the window a configure
    updateShadow();
    layoutButtons();
    update();
}

void Decoration::updateOutput()
{
    QObject *output = windowProperty("output").value<QObject *>();
    if (output != m_output.data()) {
        disconnect(m_outputConnection);
        m_outputConnection = {};
        m_output = output;
        if (output) {
            const QMetaObject *mo = output->metaObject();
            const int property = mo->indexOfProperty("geometry");
            const int slot = metaObject()->indexOfSlot("updateOutputGeometry()");
            if (property >= 0 && slot >= 0 && mo->property(property).hasNotifySignal()) {
                m_outputConnection = connect(output, mo->property(property).notifySignal(), this, metaObject()->method(slot));
            }
        }
    }
    updateOutputGeometry();
}

void Decoration::updateOutputGeometry()
{
    const bool wasShort = isShortScreen();
    qreal height = 0;
    if (m_output) {
        // KWin::Rect; KWin's scripting registers its conversion to QRect at workspace start
        const QVariant geometry = m_output->property("geometry");
        if (geometry.canConvert<QRect>()) {
            height = geometry.value<QRect>().height();
        } else if (geometry.canConvert<QRectF>()) {
            height = geometry.value<QRectF>().height();
        }
    }
    m_screenHeight = height;
    if (isShortScreen() != wasShort && m_ready) {
        updateState();
        updateShadow();
        layoutButtons();
    }
}

void Decoration::reconfigure()
{
    FusionConfig::reload();
    const ButtonStyle style = FusionConfig::self().buttonStyle;
    if (style != m_style) {
        m_style = style;
        updateButtonsVisibility(false);
        m_groupAnimation->stop();
        m_groupHover = 0;
        m_groupHovered = false;
        createButtons();
    }
    updateColors();
    updateState();
    updateShadow();
    layoutButtons();
    update();
}

void Decoration::updateColors()
{
    m_colors = Colors::fromWindow(window());
}

bool Decoration::isMaximizedFully() const
{
    return window()->isMaximized();
}

bool Decoration::tiledEdges(Qt::Edges *edges) const
{
    const auto *w = window();
    Qt::Edges e = w->adjacentScreenEdges();
    bool tiled = bool(e);
    if (!tiled) {
        // KWin reports no adjacent edges for tiles with padding (Plasma Fusion uses 6 px gaps), so
        // read the window's tile (KWin scripting property) and its place in the layout directly.
        if (const QObject *tile = windowProperty("tile").value<QObject *>()) {
            const QVariant geometry = tile->property("relativeGeometry");
            const QRectF r = geometry.canConvert<QRectF>() ? geometry.value<QRectF>() : QRectF();
            if (r.isValid()) {
                tiled = true;
                if (qFuzzyIsNull(r.left())) {
                    e |= Qt::LeftEdge;
                }
                if (qFuzzyIsNull(r.top())) {
                    e |= Qt::TopEdge;
                }
                if (qFuzzyCompare(r.right(), 1.0)) {
                    e |= Qt::RightEdge;
                }
                if (qFuzzyCompare(r.bottom(), 1.0)) {
                    e |= Qt::BottomEdge;
                }
            }
        }
    }
    if (w->isMaximizedHorizontally()) {
        e |= Qt::LeftEdge | Qt::RightEdge;
        tiled = true;
    }
    if (w->isMaximizedVertically()) {
        e |= Qt::TopEdge | Qt::BottomEdge;
        tiled = true;
    }
    if (edges) {
        *edges = e;
    }
    return tiled;
}

void Decoration::cornerFlags(bool &tl, bool &tr, bool &br, bool &bl) const
{
    if (isMaximizedFully()) {
        // Windows.dc.html "Maximized and tiled": square corners when maximized
        tl = tr = br = bl = false;
        return;
    }
    Qt::Edges edges;
    if (!tiledEdges(&edges)) {
        tl = tr = br = bl = true;
        return;
    }
    // Tiled (quick tile, custom tile, maximized in one direction): the board's halves keep their
    // outer bottom corner round and square the rest (Windows.dc.html:148-149 border-radius
    // 0 0 0 6px / 0 0 6px 0): top corners sit under the top bar, inner corners face the neighbour.
    tl = tr = false;
    bl = edges.testFlag(Qt::LeftEdge) && edges.testFlag(Qt::BottomEdge) && !edges.testFlag(Qt::RightEdge);
    br = edges.testFlag(Qt::RightEdge) && edges.testFlag(Qt::BottomEdge) && !edges.testFlag(Qt::LeftEdge);
}

void Decoration::computeMetrics()
{
    Metrics m;
    const bool maximized = isMaximizedFully();
    if (m_tablet) {
        // TABLET.md 4.9 touch title bar: 52 px (44 maximized), 36 px circles 8 apart and 8 from
        // the edge, so every button's hit area is 44 px wide and at least 44 high; 28 px icon,
        // 15 px title, 16 px glyphs. Tool windows and short screens also get 44 (TABLET.md says
        // 40 for tool windows, which cannot hold a 44 px hit area).
        m.titleHeight = (maximized || isToolWindow() || isShortScreen()) ? 44 : 52;
        m.centerY = m.titleHeight / 2;
        m.circle = 36;
        m.gap = 8;
        m.sideMargin = 8;
        m.iconSize = 28;
        m.glyph = 16;
        m.dot = 36;
        m.dotGap = 8;
        m.dotMargin = 8;
        m.dotGlyph = 16;
        m.minHit = 44;
        m.fontScale = 15.0 / 14.0;
    } else if (isToolWindow()) {
        // spec 7: 32 px title bar for tool windows; buttons scaled down with it
        m.titleHeight = 32;
        m.centerY = 16;
        m.circle = 20;
        m.gap = 5;
        m.sideMargin = 6;
        m.iconSize = 16;
        m.iconMargin = 9;
        m.titleGap = 8;
        m.glyph = 10;
    } else if (maximized || isShortScreen()) {
        // spec 7: 40 px maximized; ADAPTIVE.md 5.12: 40 px on screens under 800 px high
        m.titleHeight = 40;
        m.centerY = 20;
    }
    // Tablet sizes are minimums (44 px hit areas): round up to the device grid, not to the nearest.
    m.titleHeight = m_tablet ? snapUp(m.titleHeight) : snap(m.titleHeight);
    m.radius = snap(13);
    // The 1 px light edge as a Plasma Fusion hairline (FusionMetrics): 1 device px up to 1.5, 2 from
    // 1.75. Rounding 1 px to the grid gave 2 device px at 1.5 (an edge a third heavier than the
    // shell's hairlines, and an outline outer radius of 14.67 instead of 14).
    const qreal scale = window()->nextScale();
    m.outline = scale > 0 ? std::max(1.0, std::floor(scale + 0.25)) / scale : 1.0;
    m_metrics = m;
}

void Decoration::updateState()
{
    computeMetrics();
    const Metrics &m = m_metrics;
    const auto *w = window();
    const bool maximized = isMaximizedFully();

    // No side or bottom borders (Windows.dc.html: "No visible border"); the title bar is the only
    // decoration.
    setBorders(QMarginsF(0, m.titleHeight, 0, 0));

    // spec 7: invisible 8 px resize band outside the window (KDecoration makes its corners
    // 2 x largeSpacing long, about 20 px)
    const qreal band = snap(8);
    const qreal sides = w->isMaximizedHorizontally() ? 0 : band;
    const qreal vertical = w->isMaximizedVertically() ? 0 : band;
    setResizeOnlyBorders(QMarginsF(sides, vertical, sides, vertical));

    bool tl, tr, br, bl;
    cornerFlags(tl, tr, br, bl);
    const qreal r = m.radius;
    // KWin clips the window (title bar and client) with this radius; the top corners are painted
    // round by paint() itself so the settings-page preview, which does not clip, looks the same.
    setBorderRadius(KDecoration3::BorderRadius(0, 0, br ? r : 0, bl ? r : 0));
    if (maximized) {
        setBorderOutline(KDecoration3::BorderOutline());
    } else {
        // spec 5: the 1 px light edge, drawn by KWin just outside the window
        setBorderOutline(
            KDecoration3::BorderOutline(m.outline, m_colors.edge(w->isActive()), KDecoration3::BorderRadius(tl ? r : 0, tr ? r : 0, br ? r : 0, bl ? r : 0)));
    }
    setTitleBar(QRectF(0, 0, w->width(), m.titleHeight));
    setOpaque(maximized);
}

void Decoration::updateShadow()
{
    if (isMaximizedFully()) {
        // "Square corners, no shadow" when maximized
        setShadow(nullptr);
        return;
    }
    const bool active = window()->isActive();
    ShadowParams p;
    // spec 6: active 0 34 90 px at 55 % black, inactive 0 24 60 px at 35 % (light: MainLight
    // rgba(20,24,39,0.22) / 0.14)
    p.color = m_colors.shadow;
    p.opacity = active ? m_colors.shadowActiveOpacity : m_colors.shadowInactiveOpacity;
    p.blur = active ? 90 : 60;
    p.dy = active ? 34 : 24;
    p.frameRadius = m_metrics.radius;
    p.outline = m_metrics.outline;
    cornerFlags(p.topLeft, p.topRight, p.bottomRight, p.bottomLeft);
    setShadow(shadowFor(p));
}

void Decoration::onActiveChanged()
{
    const qreal target = window()->isActive() ? 1 : 0;
    m_activeAnimation->stop();
    const int duration = animationDuration(s_activeDuration);
    if (duration <= 0) {
        m_activeProgress = target;
        update();
    } else {
        m_activeAnimation->setDuration(duration);
        m_activeAnimation->setStartValue(m_activeProgress);
        m_activeAnimation->setEndValue(target);
        m_activeAnimation->start();
    }
    updateState(); // edge colour
    updateShadow();
}

void Decoration::updateButtonsLater()
{
    if (m_layoutPending) {
        return;
    }
    m_layoutPending = true;
    QTimer::singleShot(0, this, [this] {
        m_layoutPending = false;
        createButtons();
    });
}

void Decoration::createButtons()
{
    // A hovered button that goes away never reports leaving: take its tooltip down with it.
    bool hovered = false;
    for (const auto &b : std::as_const(m_left) + std::as_const(m_right)) {
        hovered = hovered || (b && b->isHovered());
    }
    if (hovered) {
        requestHideToolTip();
    }
    for (const auto &b : std::as_const(m_left)) {
        delete b.data();
    }
    for (const auto &b : std::as_const(m_right)) {
        delete b.data();
    }
    m_left.clear();
    m_right.clear();

    auto make = [this](DecorationButtonType type) {
        auto *button = new Button(type, this, this);
        connect(button, &KDecoration3::DecorationButton::visibilityChanged, this, &Decoration::layoutButtons);
        return QPointer<Button>(button);
    };

    if (m_style == ButtonStyle::LeftCircles) {
        // Windows.dc.html:119-121: three circles on the left (close, minimize, maximize), title centred
        for (auto type : {DecorationButtonType::Close, DecorationButtonType::Minimize, DecorationButtonType::Maximize}) {
            m_left << make(type);
        }
    } else {
        const auto s = settings();
        const bool rtl = QGuiApplication::layoutDirection() == Qt::RightToLeft;
        const auto left = rtl ? s->decorationButtonsRight() : s->decorationButtonsLeft();
        const auto right = rtl ? s->decorationButtonsLeft() : s->decorationButtonsRight();
        for (auto type : left) {
            if (type != DecorationButtonType::Custom) {
                m_left << make(type);
            }
        }
        for (auto type : right) {
            if (type != DecorationButtonType::Custom) {
                m_right << make(type);
            }
        }
    }
    layoutButtons();
}

void Decoration::layoutButtons()
{
    const Metrics &m = m_metrics;
    const qreal width = size().width();
    const qreal height = m.titleHeight;
    const bool maximized = isMaximizedFully();

    if (m_style == ButtonStyle::LeftCircles) {
        qreal x = m.dotMargin;
        bool any = false;
        for (const auto &b : std::as_const(m_left)) {
            if (!b || !b->isVisible()) {
                continue;
            }
            const QRectF visual(x, m.centerY - m.dot / 2, m.dot, m.dot);
            const qreal hitWidth = std::max(m.dot + m.dotGap, m.minHit);
            QRectF hit(visual.center().x() - hitWidth / 2, 0, hitWidth, height);
            if (!any && maximized) {
                hit.setLeft(0);
            }
            b->setGeometry(hit);
            b->setVisualRect(visual);
            x += m.dot + m.dotGap;
            any = true;
        }
        m_captionLeft = any ? x - m.dotGap + m.titleGap : m.iconMargin;
        m_captionRight = width - m.sideMargin;
        logLayout();
        update(titleBar());
        return;
    }

    // Left group: app icon 26 px 16 px from the left (spec 1), circles 10 px from the edge.
    // Hit areas never overlap: KDecoration gives a press to the first hovered button, so in an
    // overlap the wrong one would act. A hit area widened beyond circle + gap (tablet mode: the
    // 28 px app icon's grows to 44) moves its neighbour over instead (laptop values are unchanged:
    // there every hit area is exactly circle + gap and they only touch).
    qreal x = 0;
    qreal hitEnd = 0;
    bool first = true;
    for (const auto &b : std::as_const(m_left)) {
        if (!b || !b->isVisible()) {
            continue;
        }
        const bool icon = b->type() == DecorationButtonType::Menu;
        const qreal size = icon ? m.iconSize : m.circle;
        const qreal hitWidth = std::max(size + m.gap, m.minHit);
        x = first ? (icon ? m.iconMargin : m.sideMargin) : std::max(x + m.gap, hitEnd + (hitWidth - size) / 2);
        const QRectF visual(x, m.centerY - size / 2, size, size);
        QRectF hit(visual.center().x() - hitWidth / 2, 0, hitWidth, height);
        if (first && maximized) {
            hit.setLeft(0); // Fitts: the screen corner hits the first button
        }
        b->setGeometry(hit);
        b->setVisualRect(visual);
        x += size;
        hitEnd = hit.right();
        first = false;
    }
    m_captionLeft = first ? m.iconMargin : x + m.titleGap;

    // Right group: 28 px circles 6 px apart, 10 px from the right (spec 3).
    qreal rx = width;
    qreal hitStart = width;
    first = true;
    for (auto it = m_right.crbegin(); it != m_right.crend(); ++it) {
        const auto &b = *it;
        if (!b || !b->isVisible()) {
            continue;
        }
        const bool icon = b->type() == DecorationButtonType::Menu;
        const qreal size = icon ? m.iconSize : m.circle;
        const qreal hitWidth = std::max(size + m.gap, m.minHit);
        rx = first ? width - m.sideMargin : std::min(rx - m.gap, hitStart - (hitWidth - size) / 2);
        const QRectF visual(rx - size, m.centerY - size / 2, size, size);
        QRectF hit(visual.center().x() - hitWidth / 2, 0, hitWidth, height);
        if (first && maximized) {
            hit.setRight(width);
        }
        b->setGeometry(hit);
        b->setVisualRect(visual);
        rx -= size;
        hitStart = hit.left();
        first = false;
    }
    m_captionRight = first ? width - m.iconMargin : rx - m.titleGap;
    logLayout();
    update(titleBar());
}

void Decoration::logLayout()
{
    // Debug output for the session tests (hit areas in tablet mode): one line per change.
    if (!PFDECO().isDebugEnabled()) {
        return;
    }
    QString line = QStringLiteral("tablet=%1 short=%2 title=%3").arg(int(m_tablet)).arg(int(isShortScreen())).arg(m_metrics.titleHeight);
    for (const auto &list : {std::cref(m_left), std::cref(m_right)}) {
        for (const auto &b : list.get()) {
            if (b && b->isVisible()) {
                const QRectF g = b->geometry();
                const QRectF v = b->visualRect();
                line += QStringLiteral(" %1:hit=%2,%3,%4x%5/vis=%6x%7")
                            .arg(int(b->type()))
                            .arg(g.x(), 0, 'f', 2)
                            .arg(g.y(), 0, 'f', 2)
                            .arg(g.width(), 0, 'f', 2)
                            .arg(g.height(), 0, 'f', 2)
                            .arg(v.width(), 0, 'f', 2)
                            .arg(v.height(), 0, 'f', 2);
            }
        }
    }
    if (line != m_lastLayoutLog) {
        m_lastLayoutLog = line;
        qCDebug(PFDECO).noquote() << "layout" << window()->caption() << line;
    }
}

void Decoration::buttonHoverChanged()
{
    if (m_style != ButtonStyle::LeftCircles) {
        return;
    }
    bool any = false;
    for (const auto &b : std::as_const(m_left)) {
        if (b && b->isHovered()) {
            any = true;
            break;
        }
    }
    if (any == m_groupHovered) {
        return;
    }
    m_groupHovered = any;
    m_groupAnimation->stop();
    const int duration = animationDuration(s_buttonsDuration);
    if (duration <= 0) {
        m_groupHover = any ? 1 : 0;
        update(titleBar());
        return;
    }
    m_groupAnimation->setDuration(duration);
    m_groupAnimation->setStartValue(m_groupHover);
    m_groupAnimation->setEndValue(any ? 1.0 : 0.0);
    m_groupAnimation->start();
}

void Decoration::setPointerOverTitle(bool over)
{
    if (over == m_pointerOverTitle) {
        return;
    }
    m_pointerOverTitle = over;
    updateButtonsVisibility(true);
}

void Decoration::updateButtonsVisibility(bool animate)
{
    // ShowOnHover: buttons fade in while the pointer is over the title bar; always visible in
    // tablet mode (TABLET.md 4.9: nothing may depend on hover alone).
    const qreal target = (m_style != ButtonStyle::ShowOnHover || m_tablet || m_pointerOverTitle) ? 1 : 0;
    m_buttonsAnimation->stop();
    const int duration = animate ? animationDuration(s_buttonsDuration) : 0;
    if (duration <= 0 || qFuzzyCompare(m_buttonsOpacity, target)) {
        m_buttonsOpacity = target;
        update(titleBar());
        return;
    }
    m_buttonsAnimation->setDuration(duration);
    m_buttonsAnimation->setStartValue(m_buttonsOpacity);
    m_buttonsAnimation->setEndValue(target);
    m_buttonsAnimation->start();
}

void Decoration::hoverEnterEvent(QHoverEvent *event)
{
    KDecoration3::Decoration::hoverEnterEvent(event);
    setPointerOverTitle(titleBar().contains(event->position()));
}

void Decoration::hoverMoveEvent(QHoverEvent *event)
{
    KDecoration3::Decoration::hoverMoveEvent(event);
    setPointerOverTitle(titleBar().contains(event->position()));
}

void Decoration::hoverLeaveEvent(QHoverEvent *event)
{
    KDecoration3::Decoration::hoverLeaveEvent(event);
    setPointerOverTitle(false);
    m_snapHoverFired = false;
}

void Decoration::paint(QPainter *painter, const QRectF &repaintArea)
{
    const qreal width = size().width();
    const qreal height = borderTop();
    if (width <= 0 || height <= 0) {
        return;
    }
    const QRectF bar(0, 0, width, height);
    if (bar.intersects(repaintArea)) {
        bool tl, tr, br, bl;
        cornerFlags(tl, tr, br, bl);
        const bool shaded = window()->isShaded();
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing);
        painter->setPen(Qt::NoPen);
        // Colors.dc.html: title bar #222840 active, #1f2536 inactive (the scheme's Header colours)
        painter->setBrush(mix(m_colors.titleInactive, m_colors.titleActive, m_activeProgress));
        painter->drawPath(roundedRect(bar, m_metrics.radius, tl, tr, shaded && br, shaded && bl));
        painter->restore();

        paintCaption(painter);
    }
    for (const auto &b : std::as_const(m_left)) {
        if (b) {
            b->paint(painter, repaintArea);
        }
    }
    for (const auto &b : std::as_const(m_right)) {
        if (b) {
            b->paint(painter, repaintArea);
        }
    }
}

void Decoration::paintCaption(QPainter *painter) const
{
    const QString caption = window()->caption();
    if (caption.isEmpty()) {
        return;
    }
    const Metrics &m = m_metrics;
    const qreal left = m_captionLeft;
    const qreal right = m_captionRight;
    if (right - left < 4) {
        return;
    }
    // spec 2: 14 px extra bold (the system window-title font, kdeglobals [WM] activeFont; 15 px in
    // tablet mode), left aligned, fading to the inactive colour (Colors.dc.html #8891aa) on
    // inactive windows.
    const QFont font = titleFont();
    const QFontMetricsF fm(font);
    painter->save();
    painter->setFont(font);
    painter->setPen(mix(m_colors.textInactive, m_colors.textActive, m_activeProgress));
    // Centred on the same line as the buttons (the board's 49 px row: 24.5).
    const qreal rowHeight = 2 * m.centerY;
    QRectF rect;
    QString text;
    if (m_style == ButtonStyle::LeftCircles) {
        // Windows.dc.html:121: centred on the whole title bar, but never under the circles
        const qreal textWidth = fm.horizontalAdvance(caption);
        qreal x = (size().width() - textWidth) / 2;
        x = std::max(x, left);
        const qreal available = right - x;
        text = textWidth > available ? fm.elidedText(caption, Qt::ElideRight, available) : caption;
        rect = QRectF(x, 0, std::min(textWidth, available), rowHeight);
        painter->drawText(rect, Qt::AlignLeft | Qt::AlignVCenter | Qt::TextSingleLine, text);
    } else {
        rect = QRectF(left, 0, right - left, rowHeight);
        text = fm.elidedText(caption, Qt::ElideRight, rect.width());
        painter->drawText(rect, Qt::AlignLeft | Qt::AlignVCenter | Qt::TextSingleLine, text);
    }
    painter->restore();
}

} // namespace PlasmaFusion

#include "decoration.moc"
