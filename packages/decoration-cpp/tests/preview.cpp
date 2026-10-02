/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    pfdeco-preview: offline test tool for the Plasma Fusion decoration (not installed).

    Loads the built plugin through its plugin factory with a mock KDecoration3 bridge (the same
    private interface KWin and the Window Decorations settings page implement), drives it through
    window states, hover and press events, and composites what KWin would show (shadow nine-patch,
    client area clipped with the border radius, decoration image, outline) into PNG files at the
    given scales. It also checks the snap-layouts trigger against a fake kglobalaccel D-Bus service
    and the tablet-mode title bars against a fake org.kde.KWin.TabletModeManager when a session bus
    is available (run it under dbus-run-session), the 40 px title bar on short screens through a
    fake KWin output, and the shadow at 200 % against an exact Gaussian rendered at 2x.

      pfdeco-preview --out DIR --scheme FILE.colors --name dark [--fonts DIR] [--backdrop PNG]
                     [--frame X,Y,W,H] [--scales 1,1.3333333]

    With --fuzz it runs random scenes instead (runFuzz below: random configuration, button lists,
    fonts, window states, screens, input events), --scenes of them from the generator seeded with
    --seed; PF_FUZZ_COUNT and PF_FUZZ_SEED give the defaults.

    The caller sets XDG_CONFIG_HOME to a scratch directory; the tool writes plasmafusionrc and
    kwinrc there for each scene (kdeglobals should be the colour scheme, for the accent ring).
*/

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationButton>
#include <KDecoration3/DecorationSettings>
#include <KDecoration3/DecorationShadow>
#include <KDecoration3/Private/DecoratedWindowPrivate>
#include <KDecoration3/Private/DecorationBridge>
#include <KDecoration3/Private/DecorationSettingsPrivate>

#include <KColorScheme>
#include <KConfig>
#include <KConfigGroup>
#include <KPluginFactory>
#include <KPluginMetaData>
#include <KSharedConfig>

#include <QCommandLineParser>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QEventLoop>
#include <QFileInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QHoverEvent>
#include <QIcon>
#include <QImage>
#include <QJsonObject>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QPluginLoader>
#include <QRandomGenerator>
#include <QTextStream>
#include <QTimer>
#include <QWheelEvent>

#include <algorithm>
#include <cmath>
#include <functional>
#include <memory>

using namespace KDecoration3;

namespace
{

QTextStream &out()
{
    static QTextStream s(stdout);
    return s;
}

void wait(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

struct WindowState {
    bool active = true;
    QString caption = QStringLiteral("Appearance");
    bool maximized = false;
    bool maximizedH = false;
    bool maximizedV = false;
    qreal width = 650;
    qreal height = 504;
    Qt::Edges edges;
    qreal scale = 1;
    bool shaded = false;
    bool keepAbove = false;
    bool keepBelow = false;
    bool onAllDesktops = false;
    bool maximizeable = true;
    bool closeable = true;
    bool minimizeable = true;
    bool contextHelp = false;
    bool shadeable = false;
    bool moveable = true;
    bool resizeable = true;
    bool modal = false;
    QIcon icon;
    KSharedConfig::Ptr scheme;
    // what the decoration requested
    int toggleMaximize = 0;
    int close = 0;
    int minimize = 0;
    int menu = 0;
    QString toolTip;
};

class MockWindow : public DecoratedWindowPrivateV4
{
public:
    MockWindow(DecoratedWindow *client, Decoration *decoration, WindowState *state)
        : DecoratedWindowPrivateV4(client, decoration)
        , st(state)
    {
    }

    WindowState *st;

    DecoratedWindow *w()
    {
        return window();
    }

    bool isActive() const override
    {
        return st->active;
    }
    QString caption() const override
    {
        return st->caption;
    }
    bool isOnAllDesktops() const override
    {
        return st->onAllDesktops;
    }
    bool isShaded() const override
    {
        return st->shaded;
    }
    QIcon icon() const override
    {
        return st->icon;
    }
    bool isMaximized() const override
    {
        return st->maximized;
    }
    bool isMaximizedHorizontally() const override
    {
        return st->maximized || st->maximizedH;
    }
    bool isMaximizedVertically() const override
    {
        return st->maximized || st->maximizedV;
    }
    bool isKeepAbove() const override
    {
        return st->keepAbove;
    }
    bool isKeepBelow() const override
    {
        return st->keepBelow;
    }
    bool isCloseable() const override
    {
        return st->closeable;
    }
    bool isMaximizeable() const override
    {
        return st->maximizeable;
    }
    bool isMinimizeable() const override
    {
        return st->minimizeable;
    }
    bool providesContextHelp() const override
    {
        return st->contextHelp;
    }
    bool isModal() const override
    {
        return st->modal;
    }
    bool isShadeable() const override
    {
        return st->shadeable;
    }
    bool isMoveable() const override
    {
        return st->moveable;
    }
    bool isResizeable() const override
    {
        return st->resizeable;
    }
    qreal width() const override
    {
        return st->width;
    }
    qreal height() const override
    {
        return st->shaded ? 0 : st->height;
    }
    QSizeF size() const override
    {
        return QSizeF(width(), height());
    }
    QPalette palette() const override
    {
        return KColorScheme::createApplicationPalette(st->scheme);
    }
    Qt::Edges adjacentScreenEdges() const override
    {
        return st->edges;
    }
    qreal scale() const override
    {
        return st->scale;
    }
    qreal nextScale() const override
    {
        return st->scale;
    }
    void requestShowToolTip(const QString &text) override
    {
        st->toolTip = text;
    }
    void requestHideToolTip() override
    {
    }
    void requestClose() override
    {
        ++st->close;
    }
    void requestToggleMaximization(Qt::MouseButtons) override
    {
        ++st->toggleMaximize;
    }
    void requestMinimize() override
    {
        ++st->minimize;
    }
    void requestContextHelp() override
    {
    }
    void requestToggleOnAllDesktops() override
    {
    }
    void requestToggleShade() override
    {
    }
    void requestToggleKeepAbove() override
    {
    }
    void requestToggleKeepBelow() override
    {
    }
    void requestShowWindowMenu(const QRect &) override
    {
        ++st->menu;
    }
    QString windowClass() const override
    {
        return QStringLiteral("pfdeco-preview");
    }
    bool hasApplicationMenu() const override
    {
        return false;
    }
    bool isApplicationMenuActive() const override
    {
        return false;
    }
    void showApplicationMenu(int) override
    {
    }
    void requestShowApplicationMenu(const QRect &, int) override
    {
    }
    QString applicationMenuServiceName() const override
    {
        return QString();
    }
    QString applicationMenuObjectPath() const override
    {
        return QString();
    }
    void popup(const Positioner &, QMenu *) override
    {
    }
    bool isExcludedFromCapture() const override
    {
        return false;
    }
    void requestToggleExcludeFromCapture() override
    {
    }

    QColor color(ColorGroup group, ColorRole role) const override
    {
        // as KWin's DecorationPalette: the Header colour set
        const KColorScheme header(group == ColorGroup::Active ? QPalette::Active : QPalette::Inactive, KColorScheme::Header, st->scheme);
        switch (role) {
        case ColorRole::Frame:
        case ColorRole::TitleBar:
            return header.background().color();
        case ColorRole::Foreground:
            return header.foreground().color();
        }
        return QColor();
    }
};

QList<DecorationButtonType> s_left{DecorationButtonType::Menu};
QList<DecorationButtonType> s_right{DecorationButtonType::Minimize, DecorationButtonType::Maximize, DecorationButtonType::Close};
QFont s_font;

class MockSettings : public DecorationSettingsPrivateV2
{
public:
    explicit MockSettings(DecorationSettings *parent)
        : DecorationSettingsPrivateV2(parent)
    {
    }
    bool isOnAllDesktopsAvailable() const override
    {
        return true;
    }
    bool isAlphaChannelSupported() const override
    {
        return true;
    }
    bool isCloseOnDoubleClickOnMenu() const override
    {
        return false;
    }
    QList<DecorationButtonType> decorationButtonsLeft() const override
    {
        return s_left;
    }
    QList<DecorationButtonType> decorationButtonsRight() const override
    {
        return s_right;
    }
    BorderSize borderSize() const override
    {
        return BorderSize::None;
    }
    QFont font() const override
    {
        return s_font;
    }
    QFontMetricsF fontMetrics() const override
    {
        return QFontMetricsF(s_font);
    }
    bool isAlwaysShowExcludeFromCapture() const override
    {
        return false;
    }
};

class MockBridge : public DecorationBridge
{
public:
    WindowState *next = nullptr;
    MockWindow *last = nullptr;

    std::unique_ptr<DecoratedWindowPrivate> createClient(DecoratedWindow *client, Decoration *decoration) override
    {
        auto window = std::make_unique<MockWindow>(client, decoration, next);
        last = window.get();
        return window;
    }
    std::unique_ptr<DecorationSettingsPrivate> settings(DecorationSettings *parent) override
    {
        return std::make_unique<MockSettings>(parent);
    }
};

} // namespace

// KWin's TabletModeManager stand-in on /org/kde/KWin (service org.kde.KWin): a property the
// decoration reads with an asynchronous Properties.Get and a signal it follows.
class FakeTabletMode : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.KWin.TabletModeManager")
    Q_PROPERTY(bool tabletMode READ tabletMode NOTIFY tabletModeChanged)
public:
    bool mode = false;
    bool tabletMode() const
    {
        return mode;
    }
    void set(bool tablet)
    {
        mode = tablet;
        Q_EMIT tabletModeChanged(tablet);
    }
Q_SIGNALS:
    void tabletModeChanged(bool tabletMode);
};

// KWin::LogicalOutput stand-in: the window's screen (window.output.geometry, logical px).
class FakeOutput : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QRect geometry READ geometry NOTIFY geometryChanged)
public:
    QRect rect;
    QRect geometry() const
    {
        return rect;
    }
    void setGeometry(const QRect &r)
    {
        rect = r;
        Q_EMIT geometryChanged();
    }
Q_SIGNALS:
    void geometryChanged();
};

// kglobalaccel stand-in: counts invokeShortcut calls on /component/kwin.
class FakeAccel : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kglobalaccel.Component")
public:
    int count = 0;
    QStringList names;
public Q_SLOTS:
    Q_SCRIPTABLE void invokeShortcut(const QString &name)
    {
        ++count;
        names << name;
    }
};

namespace
{

QIcon makeAppIcon()
{
    // A stand-in for the board's AppIcon "settings" tile (blue rounded square with a light disc).
    QIcon icon;
    for (int size : {16, 22, 26, 32, 35, 48, 64}) {
        QImage img(size, size, QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::transparent);
        QPainter p(&img);
        p.setRenderHint(QPainter::Antialiasing);
        QLinearGradient g(0, 0, 0, size);
        g.setColorAt(0, QColor(96, 110, 140));
        g.setColorAt(1, QColor(58, 66, 90));
        p.setPen(Qt::NoPen);
        p.setBrush(g);
        p.drawRoundedRect(QRectF(0, 0, size, size), size * 0.25, size * 0.25);
        p.setBrush(QColor(236, 239, 246));
        p.drawEllipse(QRectF(size * 0.3, size * 0.3, size * 0.4, size * 0.4));
        p.end();
        icon.addPixmap(QPixmap::fromImage(img));
    }
    return icon;
}

QPainterPath roundedPath(const QRectF &r, const BorderRadius &radius)
{
    QPainterPath p;
    const qreal tl = radius.topLeft(), tr = radius.topRight(), br = radius.bottomRight(), bl = radius.bottomLeft();
    p.moveTo(r.left() + tl, r.top());
    p.lineTo(r.right() - tr, r.top());
    if (tr > 0) {
        p.arcTo(QRectF(r.right() - 2 * tr, r.top(), 2 * tr, 2 * tr), 90, -90);
    }
    p.lineTo(r.right(), r.bottom() - br);
    if (br > 0) {
        p.arcTo(QRectF(r.right() - 2 * br, r.bottom() - 2 * br, 2 * br, 2 * br), 0, -90);
    }
    p.lineTo(r.left() + bl, r.bottom());
    if (bl > 0) {
        p.arcTo(QRectF(r.left(), r.bottom() - 2 * bl, 2 * bl, 2 * bl), 270, -90);
    }
    p.lineTo(r.left(), r.top() + tl);
    if (tl > 0) {
        p.arcTo(QRectF(r.left(), r.top(), 2 * tl, 2 * tl), 180, -90);
    }
    p.closeSubpath();
    return p;
}

// What KWin draws for one window: shadow tiles, client (clipped), decoration, outline.
void composite(QPainter &p, Decoration *deco, const QPointF &pos, const QColor &clientColor)
{
    const QRectF frame(pos, deco->size());
    // shadow nine-patch (the centre is not drawn, as in KWin)
    if (const auto shadow = deco->shadow()) {
        const QImage img = shadow->shadow();
        const QMarginsF pad = shadow->padding();
        const QRectF outer = frame.marginsAdded(pad);
        const QRectF tl = shadow->topLeftGeometry(), t = shadow->topGeometry(), tr = shadow->topRightGeometry();
        const QRectF r = shadow->rightGeometry(), br = shadow->bottomRightGeometry(), b = shadow->bottomGeometry();
        const QRectF bl = shadow->bottomLeftGeometry(), l = shadow->leftGeometry();
        p.drawImage(QRectF(outer.topLeft(), tl.size()), img, tl);
        p.drawImage(QRectF(QPointF(outer.right() - tr.width(), outer.top()), tr.size()), img, tr);
        p.drawImage(QRectF(QPointF(outer.right() - br.width(), outer.bottom() - br.height()), br.size()), img, br);
        p.drawImage(QRectF(QPointF(outer.left(), outer.bottom() - bl.height()), bl.size()), img, bl);
        p.drawImage(QRectF(outer.left() + tl.width(), outer.top(), outer.width() - tl.width() - tr.width(), t.height()), img, t);
        p.drawImage(QRectF(outer.left() + bl.width(), outer.bottom() - b.height(), outer.width() - bl.width() - br.width(), b.height()), img, b);
        p.drawImage(QRectF(outer.left(), outer.top() + tl.height(), l.width(), outer.height() - tl.height() - bl.height()), img, l);
        p.drawImage(QRectF(outer.right() - r.width(), outer.top() + tr.height(), r.width(), outer.height() - tr.height() - br.height()), img, r);
    }
    const qreal dpr = p.device()->devicePixelRatioF();
    // decoration image
    QImage decoImage((deco->size() * dpr).toSize(), QImage::Format_ARGB32_Premultiplied);
    decoImage.setDevicePixelRatio(dpr);
    decoImage.fill(Qt::transparent);
    {
        QPainter dp(&decoImage);
        deco->paint(&dp, QRectF(QPointF(0, 0), deco->size()));
    }
    p.save();
    p.setRenderHint(QPainter::Antialiasing);
    p.setClipPath(roundedPath(frame, deco->borderRadius()));
    p.fillRect(QRectF(frame.left(), frame.top() + deco->borderTop(), frame.width(), frame.height() - deco->borderTop()), clientColor);
    p.drawImage(frame.topLeft(), decoImage);
    p.restore();
    const BorderOutline outline = deco->borderOutline();
    if (!outline.isNull()) {
        const qreal t = outline.thickness();
        const BorderRadius ri = outline.radius();
        const BorderRadius ro(ri.topLeft() > 0 ? ri.topLeft() + t : 0,
                              ri.topRight() > 0 ? ri.topRight() + t : 0,
                              ri.bottomRight() > 0 ? ri.bottomRight() + t : 0,
                              ri.bottomLeft() > 0 ? ri.bottomLeft() + t : 0);
        QPainterPath ring = roundedPath(frame.adjusted(-t, -t, t, t), ro);
        ring.addPath(roundedPath(frame, ri));
        ring.setFillRule(Qt::OddEvenFill);
        p.save();
        p.setRenderHint(QPainter::Antialiasing);
        p.setPen(Qt::NoPen);
        p.setBrush(outline.color());
        p.drawPath(ring);
        p.restore();
    }
}

// snapOnHover: 1 / 0 writes true / false, -1 leaves the key out (the contract's default)
void writeConfig(const QString &style, int snapOnHover, bool snapScript)
{
    KConfig fusion(QStringLiteral("plasmafusionrc"), KConfig::NoGlobals);
    KConfigGroup deco(&fusion, QStringLiteral("Decoration"));
    deco.writeEntry("ButtonStyle", style);
    if (snapOnHover < 0) {
        deco.deleteEntry("SnapLayoutsOnHover");
    } else {
        deco.writeEntry("SnapLayoutsOnHover", snapOnHover == 1);
    }
    fusion.sync();
    KConfig kwin(QStringLiteral("kwinrc"), KConfig::NoGlobals);
    KConfigGroup plugins(&kwin, QStringLiteral("Plugins"));
    plugins.writeEntry("plasmafusion-snapEnabled", snapScript);
    kwin.sync();
}

// --- the shadow at 200 % -------------------------------------------------------------------

bool insideRoundedRect(qreal x, qreal y, const QRectF &r, qreal radius)
{
    if (!r.contains(x, y)) {
        return false;
    }
    const qreal cx = std::clamp(x, r.left() + radius, r.right() - radius);
    const qreal cy = std::clamp(y, r.top() + radius, r.bottom() - radius);
    return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius;
}

// Exact CSS box-shadow alpha at `scale` device px per image px: the rounded shape (antialiased),
// blurred with a true Gaussian of sigma * scale (separable, 4 sigma reach), times the opacity.
std::vector<float> exactShadow(int w, int h, const QRectF &shape, qreal radius, qreal sigma, qreal opacity)
{
    QImage mask(w, h, QImage::Format_Alpha8);
    mask.fill(0);
    {
        QPainter p(&mask);
        p.setRenderHint(QPainter::Antialiasing);
        p.setPen(Qt::NoPen);
        p.setBrush(Qt::black);
        QPainterPath path;
        path.addRoundedRect(shape, radius, radius);
        p.drawPath(path);
    }
    const int reach = int(std::ceil(4 * sigma));
    std::vector<float> kernel(2 * reach + 1);
    double sum = 0;
    for (int i = -reach; i <= reach; ++i) {
        kernel[i + reach] = float(std::exp(-0.5 * (i / sigma) * (i / sigma)));
        sum += kernel[i + reach];
    }
    for (auto &k : kernel) {
        k = float(k / sum);
    }
    std::vector<float> a(size_t(w) * h), b(size_t(w) * h, 0.f);
    for (int y = 0; y < h; ++y) {
        const uchar *line = mask.constScanLine(y);
        for (int x = 0; x < w; ++x) {
            a[size_t(y) * w + x] = line[x] / 255.f;
        }
    }
    for (int y = 0; y < h; ++y) {
        const float *src = a.data() + size_t(y) * w;
        float *dst = b.data() + size_t(y) * w;
        for (int x = 0; x < w; ++x) {
            float acc = 0;
            const int lo = std::max(0, x - reach), hi = std::min(w - 1, x + reach);
            for (int i = lo; i <= hi; ++i) {
                acc += src[i] * kernel[i - x + reach];
            }
            dst[x] = acc;
        }
    }
    std::vector<float> col(h);
    for (int x = 0; x < w; ++x) {
        for (int y = 0; y < h; ++y) {
            col[y] = b[size_t(y) * w + x];
        }
        for (int y = 0; y < h; ++y) {
            float acc = 0;
            const int lo = std::max(0, y - reach), hi = std::min(h - 1, y + reach);
            for (int i = lo; i <= hi; ++i) {
                acc += col[i] * kernel[i - y + reach];
            }
            a[size_t(y) * w + x] = float(acc * opacity);
        }
    }
    return a;
}

// KWin's GL_LINEAR sampling of a 1x image at `scale` device px per image px (texel centres).
float sampleLinear(const std::vector<float> &img, int w, int h, qreal dx, qreal dy, qreal scale)
{
    const qreal u = std::clamp((dx + 0.5) / scale - 0.5, 0.0, qreal(w - 1));
    const qreal v = std::clamp((dy + 0.5) / scale - 0.5, 0.0, qreal(h - 1));
    const int x0 = int(std::floor(u)), y0 = int(std::floor(v));
    const int x1 = std::min(x0 + 1, w - 1), y1 = std::min(y0 + 1, h - 1);
    const qreal fx = u - x0, fy = v - y0;
    auto at = [&](int x, int y) {
        return qreal(img[size_t(y) * w + x]);
    };
    return float((at(x0, y0) * (1 - fx) + at(x1, y0) * fx) * (1 - fy) + (at(x0, y1) * (1 - fx) + at(x1, y1) * fx) * fy);
}

struct ShadowCheck {
    qreal at1x = 1; // plugin image vs exact, at 1x
    qreal upscale = 1; // exact 1x sampled at 2x vs exact 2x: what the missing @2x image costs
    qreal total = 1; // plugin image sampled at 2x vs exact 2x: what a 200 % screen shows
};

ShadowCheck checkShadowAt2x(const QImage &plugin, const QMarginsF &pad, qreal opacity, const QString &prefix)
{
    // Geometry of the plugin's image (shadow.cpp): frame box x box at (ext, ext - dy), shape =
    // frame grown by the 1 px outline (outer radius 14), moved down by dy; sigma = 90 / 2.
    const int w = plugin.width(), h = plugin.height();
    const qreal ext = pad.left();
    const qreal dy = pad.bottom() - pad.left();
    const qreal box = w - 2 * ext;
    const QRectF frame(ext, ext - dy, box, box);
    const QRectF grown = frame.adjusted(-1, -1, 1, 1);
    const qreal radius = 14, sigma = 45;
    std::vector<float> pluginAlpha(size_t(w) * h);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            pluginAlpha[size_t(y) * w + x] = qAlpha(plugin.pixel(x, y)) / 255.f;
        }
    }
    ShadowCheck r;
    const std::vector<float> ref1 = exactShadow(w, h, grown.translated(0, dy), radius, sigma, opacity);
    r.at1x = 0;
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            if (!insideRoundedRect(x + 0.5, y + 0.5, grown, radius)) {
                r.at1x = std::max(r.at1x, qreal(std::abs(pluginAlpha[size_t(y) * w + x] - ref1[size_t(y) * w + x])));
            }
        }
    }
    const qreal k = 2;
    const int W = int(w * k), H = int(h * k);
    const QRectF grown2(grown.x() * k, grown.y() * k, grown.width() * k, grown.height() * k);
    const std::vector<float> ref2 = exactShadow(W, H, grown2.translated(0, dy * k), radius * k, sigma * k, opacity);
    r.upscale = 0;
    r.total = 0;
    // evidence: the bottom-left corner at 200 %, 2x zoom: KWin's sampling of the plugin image,
    // the exact 2x Gaussian, and their difference x 50
    const QRect crop(0, int((frame.bottom() - 60) * k), int((ext + 80) * k), int((h - frame.bottom() + 60) * k));
    QImage sheet(crop.width() * 3, crop.height(), QImage::Format_RGB32);
    sheet.fill(Qt::white);
    for (int Y = 0; Y < H; ++Y) {
        for (int X = 0; X < W; ++X) {
            const bool outside = !insideRoundedRect((X + 0.5) / k, (Y + 0.5) / k, grown, radius);
            const float exact = ref2[size_t(Y) * W + X];
            const float kwin = sampleLinear(pluginAlpha, w, h, X, Y, k);
            if (outside) {
                r.upscale = std::max(r.upscale, qreal(std::abs(sampleLinear(ref1, w, h, X, Y, k) - exact)));
                r.total = std::max(r.total, qreal(std::abs(kwin - exact)));
            }
            if (crop.contains(X, Y)) {
                const int cx = X - crop.x(), cy = Y - crop.y();
                auto grey = [](float a) {
                    const int v = std::clamp(int(std::lround(255 * (1 - a))), 0, 255);
                    return qRgb(v, v, v);
                };
                sheet.setPixel(cx, cy, outside ? grey(kwin) : qRgb(40, 60, 120));
                sheet.setPixel(cx + crop.width(), cy, outside ? grey(exact) : qRgb(40, 60, 120));
                sheet.setPixel(cx + 2 * crop.width(), cy, outside ? grey(std::min(1.f, 50 * std::abs(kwin - exact))) : qRgb(40, 60, 120));
            }
        }
    }
    sheet.scaled(sheet.size() * 2, Qt::IgnoreAspectRatio, Qt::FastTransformation).save(prefix + QStringLiteral("-shadow-200pct-corner-2x.png"));
    return r;
}

struct Harness {
    KPluginFactory *factory = nullptr;
    MockBridge bridge;
    std::shared_ptr<DecorationSettings> settings;
    KSharedConfig::Ptr scheme;
    KSharedConfig::Ptr otherScheme; // for the palette-change check
    QString outDir;
    QString name;
    QImage backdrop;
    QRectF frame;
    QColor clientColor;
    int failures = 0;

    struct Instance {
        std::unique_ptr<QObject> owner;
        Decoration *deco = nullptr;
        MockWindow *window = nullptr;
        std::unique_ptr<WindowState> state;
    };

    Instance create(std::unique_ptr<WindowState> state, bool tool = false, const QRectF &tile = QRectF(), QObject *output = nullptr)
    {
        Instance in;
        in.state = std::move(state);
        in.state->scheme = scheme;
        if (in.state->icon.isNull()) {
            in.state->icon = makeAppIcon();
        }
        in.owner = std::make_unique<QObject>();
        in.owner->setProperty("utility", tool);
        in.owner->setProperty("toolbar", false);
        in.owner->setProperty("normalWindow", !tool);
        in.owner->setProperty("specialWindow", false);
        if (tile.isValid()) {
            // KWin's window.tile (a KWin::Tile with relativeGeometry), for tiles with padding
            auto *t = new QObject(in.owner.get());
            t->setProperty("relativeGeometry", tile);
            in.owner->setProperty("tile", QVariant::fromValue<QObject *>(t));
        }
        if (output) {
            // KWin's window.output (a KWin::LogicalOutput with a geometry property)
            in.owner->setProperty("output", QVariant::fromValue<QObject *>(output));
        }
        bridge.next = in.state.get();
        const QVariantMap args{{QStringLiteral("bridge"), QVariant::fromValue(static_cast<DecorationBridge *>(&bridge))}};
        in.deco = factory->create<Decoration>(in.owner.get(), QVariantList{args});
        if (!in.deco) {
            out() << "FAIL cannot create the decoration\n";
            ++failures;
            return in;
        }
        in.window = bridge.last;
        in.deco->setSettings(settings);
        in.deco->create();
        QObject::connect(in.deco, &Decoration::nextStateChanged, in.deco, [deco = in.deco](auto state) {
            deco->apply(state->clone());
        });
        in.deco->init();
        in.deco->apply(in.deco->nextState()->clone());
        return in;
    }

    void destroy(Instance &in)
    {
        // the decoration is a child of the owner
        in.owner.reset();
        in.deco = nullptr;
        in.window = nullptr;
    }

    void hover(Decoration *deco, const QPointF &pos)
    {
        QHoverEvent enter(QEvent::HoverEnter, pos, pos, QPointF(-1, -1));
        QCoreApplication::sendEvent(deco, &enter);
        QHoverEvent move(QEvent::HoverMove, pos, pos, pos);
        QCoreApplication::sendEvent(deco, &move);
    }
    void leave(Decoration *deco)
    {
        QHoverEvent e(QEvent::HoverLeave, QPointF(-1, -1), QPointF(-1, -1), QPointF(-1, -1));
        QCoreApplication::sendEvent(deco, &e);
    }
    void press(Decoration *deco, const QPointF &pos, Qt::MouseButton button = Qt::LeftButton)
    {
        QMouseEvent e(QEvent::MouseButtonPress, pos, pos, button, button, Qt::NoModifier);
        QCoreApplication::sendEvent(deco, &e);
    }
    void release(Decoration *deco, const QPointF &pos, Qt::MouseButton button = Qt::LeftButton)
    {
        QMouseEvent e(QEvent::MouseButtonRelease, pos, pos, button, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(deco, &e);
    }

    QPointF buttonCenter(Decoration *deco, DecorationButtonType type)
    {
        const auto buttons = deco->findChildren<DecorationButton *>();
        for (auto *b : buttons) {
            if (b->type() == type && b->isVisible()) {
                return b->geometry().center();
            }
        }
        return QPointF(-100, -100);
    }

    void render(Decoration *deco, const QString &scene, qreal scale, const QRectF &where)
    {
        const QSize logical = backdrop.isNull() ? QSize(1440, 900) : backdrop.size();
        QImage canvas((QSizeF(logical) * scale).toSize(), QImage::Format_ARGB32_Premultiplied);
        canvas.setDevicePixelRatio(scale);
        QPainter p(&canvas);
        p.setRenderHint(QPainter::SmoothPixmapTransform);
        if (!backdrop.isNull()) {
            p.drawImage(QRectF(QPointF(0, 0), QSizeF(logical)), backdrop);
        } else {
            p.fillRect(QRectF(QPointF(0, 0), QSizeF(logical)), QColor(16, 20, 42));
        }
        composite(p, deco, where.topLeft(), clientColor);
        p.end();
        const QString file = QStringLiteral("%1/%2-%3-s%4.png").arg(outDir, name, scene, scaleLabel(scale));
        canvas.save(file);
    }

    static QString scaleLabel(qreal scale)
    {
        if (qFuzzyCompare(scale, 1.0)) {
            return QStringLiteral("1");
        }
        if (std::abs(scale - 4.0 / 3.0) < 0.001) {
            return QStringLiteral("4-3");
        }
        return QString::number(scale).replace(QLatin1Char('.'), QLatin1Char('_'));
    }

    // The visible buttons: hit areas (geometry) by type.
    QList<DecorationButton *> visibleButtons(Decoration *deco)
    {
        QList<DecorationButton *> list;
        for (auto *b : deco->findChildren<DecorationButton *>()) {
            if (b->isVisible() && b->type() != DecorationButtonType::Spacer) {
                list << b;
            }
        }
        return list;
    }
    QRectF hitOf(Decoration *deco, DecorationButtonType type)
    {
        for (auto *b : visibleButtons(deco)) {
            if (b->type() == type) {
                return b->geometry();
            }
        }
        return QRectF();
    }
    qreal smallestHit(Decoration *deco, bool height)
    {
        qreal smallest = 1e9;
        for (auto *b : visibleButtons(deco)) {
            smallest = std::min(smallest, height ? b->geometry().height() : b->geometry().width());
        }
        return smallest;
    }
    QImage paintTitle(Decoration *deco, qreal scale = 1)
    {
        const QSizeF size(deco->size().width(), deco->borderTop());
        QImage img((size * scale).toSize(), QImage::Format_ARGB32_Premultiplied);
        img.setDevicePixelRatio(scale);
        img.fill(Qt::transparent);
        QPainter p(&img);
        deco->paint(&p, QRectF(QPointF(0, 0), size));
        return img;
    }

    void check(bool ok, const QString &what)
    {
        out() << (ok ? "PASS " : "FAIL ") << name << ": " << what << "\n";
        out().flush();
        if (!ok) {
            ++failures;
        }
    }
};

// --- random scenes (--fuzz) ------------------------------------------------------------------

// One of `valid`, or (one time in three) an odd value: empty, blank, unknown, out of range, not a
// number, right-to-left text, very long.
QString randomValue(QRandomGenerator &rng, const QStringList &valid)
{
    static const QStringList odd{QString(),
                                 QStringLiteral(" "),
                                 QStringLiteral("Unknown"),
                                 QStringLiteral("-1"),
                                 QStringLiteral("2147483648"),
                                 QStringLiteral("nan"),
                                 QStringLiteral("1e308"),
                                 QStringLiteral("[Decoration]"),
                                 QStringLiteral("\u202e\u0645\u062b\u0627\u0644\u202c"),
                                 QString(400, QLatin1Char('x'))};
    if (rng.bounded(3) == 0) {
        return odd.at(rng.bounded(int(odd.size())));
    }
    return valid.at(rng.bounded(int(valid.size())));
}

// The keys the decoration reads (fusionconfig.cpp), each with a random value or left out.
void writeRandomConfig(QRandomGenerator &rng)
{
    const QStringList booleans{QStringLiteral("true"), QStringLiteral("false"), QStringLiteral("1"), QStringLiteral("0")};
    auto entry = [&rng](KConfigGroup &group, const char *key, const QStringList &valid) {
        if (rng.bounded(5) == 0) {
            group.deleteEntry(key);
        } else {
            group.writeEntry(key, randomValue(rng, valid));
        }
    };
    KConfig fusion(QStringLiteral("plasmafusionrc"), KConfig::NoGlobals);
    KConfigGroup deco(&fusion, QStringLiteral("Decoration"));
    entry(deco, "ButtonStyle", {QStringLiteral("RightGlyphs"), QStringLiteral("LeftCircles"), QStringLiteral("ShowOnHover"), QStringLiteral(" leftcircles ")});
    entry(deco, "SnapLayoutsOnHover", booleans);
    fusion.sync();
    KConfig kwin(QStringLiteral("kwinrc"), KConfig::NoGlobals);
    KConfigGroup plugins(&kwin, QStringLiteral("Plugins"));
    entry(plugins, "plasmafusion-snapEnabled", booleans);
    kwin.sync();
    KConfig globals(QStringLiteral("kdeglobals"), KConfig::NoGlobals);
    KConfigGroup kde(&globals, QStringLiteral("KDE"));
    entry(kde, "AnimationDurationFactor", {QStringLiteral("0"), QStringLiteral("0.5"), QStringLiteral("1"), QStringLiteral("20")});
    globals.sync();
}

QList<DecorationButtonType> randomButtons(QRandomGenerator &rng)
{
    static const QList<DecorationButtonType> types{DecorationButtonType::Menu,
                                                   DecorationButtonType::ApplicationMenu,
                                                   DecorationButtonType::OnAllDesktops,
                                                   DecorationButtonType::Minimize,
                                                   DecorationButtonType::Maximize,
                                                   DecorationButtonType::Close,
                                                   DecorationButtonType::ContextHelp,
                                                   DecorationButtonType::Shade,
                                                   DecorationButtonType::KeepBelow,
                                                   DecorationButtonType::KeepAbove,
                                                   DecorationButtonType::Custom,
                                                   DecorationButtonType::Spacer,
                                                   DecorationButtonType::ExcludeFromCapture};
    QList<DecorationButtonType> list;
    const int count = rng.bounded(8);
    for (int i = 0; i < count; ++i) {
        list << types.at(rng.bounded(int(types.size())));
    }
    return list;
}

qreal randomLength(QRandomGenerator &rng)
{
    static const QList<qreal> lengths{0, 1, 7, 40, 99.5, 320, 650, 1366, 2560, 7680};
    return rng.bounded(3) == 0 ? lengths.at(rng.bounded(int(lengths.size()))) : rng.bounded(3000.0);
}

qreal randomScale(QRandomGenerator &rng)
{
    static const QList<qreal> scales{0.5, 1, 1.25, 4.0 / 3.0, 1.5, 1.75, 2, 3};
    return scales.at(rng.bounded(int(scales.size())));
}

QString randomCaption(QRandomGenerator &rng)
{
    static const QStringList captions{QString(),
                                      QStringLiteral("Appearance"),
                                      QStringLiteral("A very long document title that does not fit into the title bar of this window at all — Kate"),
                                      QStringLiteral("\u0645\u0633\u062a\u0646\u062f \u062c\u062f\u064a\u062f \u2014 Kate"),
                                      QStringLiteral("tab\there, new\nline, zero\u200bwidth, e\u0301"),
                                      QStringLiteral("\U0001F600 \U0001F680"),
                                      QString(3000, QLatin1Char('W'))};
    return captions.at(rng.bounded(int(captions.size())));
}

QRect randomScreen(QRandomGenerator &rng)
{
    static const QList<QSize> sizes{QSize(1440, 900), QSize(1280, 799), QSize(1280, 800), QSize(1366, 768), QSize(768, 1366), QSize(3840, 2160), QSize(0, 0)};
    if (rng.bounded(8) == 0) {
        return QRect();
    }
    return QRect(QPoint(0, 0), sizes.at(rng.bounded(int(sizes.size()))));
}

// The decoration painted into an image of at most 1600 x 400 logical px (enough for the title bar
// and two corners of any window).
void paintCapped(Decoration *deco, qreal scale)
{
    const QSizeF logical(std::clamp(deco->size().width(), 1.0, 1600.0), std::clamp(deco->size().height(), 1.0, 400.0));
    QImage img((logical * scale).toSize().expandedTo(QSize(1, 1)), QImage::Format_ARGB32_Premultiplied);
    img.setDevicePixelRatio(scale);
    img.fill(Qt::transparent);
    QPainter p(&img);
    deco->paint(&p, QRectF(QPointF(0, 0), deco->size()));
}

// One random change or input event for a live decoration.
void randomStep(Harness &h, Harness::Instance &in, QRandomGenerator &rng, FakeTabletMode *tablet, FakeOutput *screen)
{
    Decoration *d = in.deco;
    WindowState &st = *in.state;
    DecoratedWindow *dw = in.window->w();
    auto flip = [&rng] {
        return rng.bounded(2) == 1;
    };
    // Anywhere over the title bar and a little around it, or the centre of a visible button.
    auto point = [&] {
        const auto buttons = h.visibleButtons(d);
        if (!buttons.isEmpty() && flip()) {
            return buttons.at(rng.bounded(int(buttons.size())))->geometry().center();
        }
        return QPointF(rng.bounded(d->size().width() + 80) - 40, rng.bounded(d->borderTop() + 80) - 40);
    };
    auto mouseButton = [&rng] {
        static const QList<Qt::MouseButton> buttons{Qt::LeftButton, Qt::LeftButton, Qt::RightButton, Qt::MiddleButton};
        return buttons.at(rng.bounded(int(buttons.size())));
    };
    switch (rng.bounded(26)) {
    case 0:
    case 1:
        h.hover(d, point());
        break;
    case 2:
        h.leave(d);
        break;
    case 3:
    case 4:
        h.press(d, point(), mouseButton());
        break;
    case 5:
    case 6:
        h.release(d, point(), mouseButton());
        break;
    case 7: {
        const QPointF p = point();
        QMouseEvent e(QEvent::MouseButtonDblClick, p, p, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(d, &e);
        break;
    }
    case 8: {
        const QPointF p = point();
        QWheelEvent e(p, p, QPoint(), QPoint(0, flip() ? 120 : -120), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
        QCoreApplication::sendEvent(d, &e);
        break;
    }
    case 9:
        st.active = !st.active;
        Q_EMIT dw->activeChanged(st.active);
        break;
    case 10:
        st.maximized = !st.maximized;
        Q_EMIT dw->maximizedChanged(st.maximized);
        break;
    case 11:
        st.maximizedH = flip();
        st.maximizedV = flip();
        Q_EMIT dw->maximizedHorizontallyChanged(st.maximizedH);
        Q_EMIT dw->maximizedVerticallyChanged(st.maximizedV);
        break;
    case 12:
        st.shaded = !st.shaded;
        Q_EMIT dw->shadedChanged(st.shaded);
        break;
    case 13:
        st.width = randomLength(rng);
        st.height = randomLength(rng);
        Q_EMIT dw->widthChanged(st.width);
        Q_EMIT dw->heightChanged(st.height);
        Q_EMIT dw->sizeChanged(QSizeF(st.width, st.height));
        break;
    case 14:
        st.caption = randomCaption(rng);
        Q_EMIT dw->captionChanged(st.caption);
        break;
    case 15:
        st.edges = Qt::Edges::fromInt(rng.bounded(16));
        Q_EMIT dw->adjacentScreenEdgesChanged(st.edges);
        break;
    case 16:
        if (h.otherScheme) {
            st.scheme = st.scheme == h.scheme ? h.otherScheme : h.scheme;
        }
        Q_EMIT dw->paletteChanged(in.window->palette());
        break;
    case 17:
        st.scale = randomScale(rng);
        Q_EMIT dw->nextScaleChanged();
        Q_EMIT dw->scaleChanged();
        break;
    case 18:
        writeRandomConfig(rng);
        wait(1); // the configuration is read again in the next event-loop pass
        Q_EMIT h.settings->reconfigured();
        break;
    case 19:
        s_left = randomButtons(rng);
        s_right = randomButtons(rng);
        QGuiApplication::setLayoutDirection(rng.bounded(4) == 0 ? Qt::RightToLeft : Qt::LeftToRight);
        Q_EMIT h.settings->decorationButtonsLeftChanged(s_left);
        Q_EMIT h.settings->decorationButtonsRightChanged(s_right);
        break;
    case 20:
        s_font.setPixelSize(1 + rng.bounded(64));
        Q_EMIT h.settings->fontChanged(s_font);
        break;
    case 21:
        if (tablet) {
            tablet->set(flip());
        }
        break;
    case 22:
        if (screen) {
            screen->setGeometry(randomScreen(rng));
        }
        break;
    case 23:
        switch (rng.bounded(8)) {
        case 0:
            st.closeable = !st.closeable;
            Q_EMIT dw->closeableChanged(st.closeable);
            break;
        case 1:
            st.maximizeable = !st.maximizeable;
            Q_EMIT dw->maximizeableChanged(st.maximizeable);
            break;
        case 2:
            st.minimizeable = !st.minimizeable;
            Q_EMIT dw->minimizeableChanged(st.minimizeable);
            break;
        case 3:
            st.keepAbove = !st.keepAbove;
            Q_EMIT dw->keepAboveChanged(st.keepAbove);
            break;
        case 4:
            st.keepBelow = !st.keepBelow;
            Q_EMIT dw->keepBelowChanged(st.keepBelow);
            break;
        case 5:
            st.onAllDesktops = !st.onAllDesktops;
            Q_EMIT dw->onAllDesktopsChanged(st.onAllDesktops);
            break;
        case 6:
            st.contextHelp = !st.contextHelp;
            Q_EMIT dw->providesContextHelpChanged(st.contextHelp);
            break;
        default:
            st.shadeable = !st.shadeable;
            Q_EMIT dw->shadeableChanged(st.shadeable);
            break;
        }
        break;
    case 24:
        st.icon = flip() ? QIcon() : makeAppIcon();
        Q_EMIT dw->iconChanged(st.icon);
        break;
    default:
        // Mostly short, sometimes long enough for the snap-layouts timer (600 ms) and the animations.
        wait(rng.bounded(50) == 0 ? 650 : rng.bounded(30));
        break;
    }
}

// --fuzz: `scenes` random scenes from a generator seeded with `seed` (the same seed repeats the
// same scenes). Each one writes a random configuration, picks the button lists, title font, layout
// direction, tablet mode, window state, tile and screen, creates the decoration, runs up to 24
// random changes and input events on it, paints it and destroys it. Meant for the sanitizer build
// (tools/sanitizers/run.sh), where a memory error or undefined behaviour stops the process; the
// checks here are only that the borders stay finite and not negative.
void runFuzz(Harness &h, FakeTabletMode *tablet, int scenes, quint32 seed)
{
    QRandomGenerator rng(seed);
    const QFont font = s_font;
    const auto left = s_left;
    const auto right = s_right;
    FakeOutput screen;
    int checked = 0;
    for (int i = 0; i < scenes; ++i) {
        writeRandomConfig(rng);
        s_left = randomButtons(rng);
        s_right = randomButtons(rng);
        s_font = font;
        s_font.setPixelSize(1 + rng.bounded(40));
        QGuiApplication::setLayoutDirection(rng.bounded(6) == 0 ? Qt::RightToLeft : Qt::LeftToRight);
        if (tablet && rng.bounded(4) == 0) {
            tablet->set(rng.bounded(2) == 1);
        }
        wait(1); // the configuration is read again in the next event-loop pass

        auto state = std::make_unique<WindowState>();
        state->active = rng.bounded(4) != 0;
        state->caption = randomCaption(rng);
        state->maximized = rng.bounded(4) == 0;
        state->maximizedH = rng.bounded(8) == 0;
        state->maximizedV = rng.bounded(8) == 0;
        state->width = randomLength(rng);
        state->height = randomLength(rng);
        state->edges = Qt::Edges::fromInt(rng.bounded(4) == 0 ? rng.bounded(16) : 0);
        state->scale = randomScale(rng);
        state->shaded = rng.bounded(10) == 0;
        state->keepAbove = rng.bounded(6) == 0;
        state->onAllDesktops = rng.bounded(6) == 0;
        state->maximizeable = rng.bounded(6) != 0;
        state->closeable = rng.bounded(8) != 0;
        state->minimizeable = rng.bounded(6) != 0;
        state->contextHelp = rng.bounded(6) == 0;
        state->shadeable = rng.bounded(6) == 0;
        state->modal = rng.bounded(8) == 0;
        // create() gives every window the app icon; some lose it again once created.
        const bool noIcon = rng.bounded(6) == 0;
        const bool tool = rng.bounded(5) == 0;
        QRectF tile;
        if (rng.bounded(4) == 0) {
            tile = QRectF(rng.bounded(1.5) - 0.25, rng.bounded(1.5) - 0.25, rng.bounded(1.25), rng.bounded(1.25));
        }
        const bool onScreen = rng.bounded(2) == 1;
        screen.rect = randomScreen(rng);
        const int steps = rng.bounded(25);
        out() << "fuzz scene " << i << ": " << state->width << " x " << state->height << " at " << state->scale << ", " << s_left.size() << " + "
              << s_right.size() << " buttons, tool " << tool << ", tile " << tile.isValid() << ", screen " << (onScreen ? screen.rect.height() : -1) << ", "
              << steps << " steps\n";
        out().flush();

        auto in = h.create(std::move(state), tool, tile, onScreen ? &screen : nullptr);
        if (!in.deco) {
            continue; // create() counted the failure
        }
        if (noIcon) {
            in.state->icon = QIcon();
            Q_EMIT in.window->w()->iconChanged(QIcon());
        }
        for (int s = 0; s < steps; ++s) {
            randomStep(h, in, rng, tablet, onScreen ? &screen : nullptr);
        }
        wait(rng.bounded(20));
        paintCapped(in.deco, in.state->scale);
        const qreal borders[] = {in.deco->borderLeft(), in.deco->borderTop(), in.deco->borderRight(), in.deco->borderBottom()};
        for (const qreal b : borders) {
            if (!std::isfinite(b) || b < 0) {
                h.check(false,
                        QStringLiteral("scene %1: border %2 (left, top, right, bottom: %3 %4 %5 %6)")
                            .arg(i)
                            .arg(b)
                            .arg(borders[0])
                            .arg(borders[1])
                            .arg(borders[2])
                            .arg(borders[3]));
                break;
            }
        }
        if (const auto shadow = in.deco->shadow()) {
            const QMarginsF pad = shadow->padding();
            if (!std::isfinite(pad.left() + pad.top() + pad.right() + pad.bottom()) || shadow->shadow().isNull()) {
                h.check(false, QStringLiteral("scene %1: shadow image or padding invalid").arg(i));
            }
        }
        h.destroy(in);
        ++checked;
    }
    s_font = font;
    s_left = left;
    s_right = right;
    QGuiApplication::setLayoutDirection(Qt::LeftToRight);
    h.check(h.failures == 0, QStringLiteral("%1 random scenes (seed %2), %3 decorations created, painted and destroyed").arg(scenes).arg(seed).arg(checked));
}

} // namespace

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addOption({QStringLiteral("out"), QStringLiteral("output directory"), QStringLiteral("dir")});
    parser.addOption({QStringLiteral("scheme"), QStringLiteral("colour scheme file"), QStringLiteral("file")});
    parser.addOption({QStringLiteral("other-scheme"), QStringLiteral("second colour scheme (palette-change check)"), QStringLiteral("file")});
    parser.addOption({QStringLiteral("name"), QStringLiteral("file name prefix"), QStringLiteral("name"), QStringLiteral("dark")});
    parser.addOption({QStringLiteral("fonts"), QStringLiteral("directory with .ttf files to load"), QStringLiteral("dir")});
    parser.addOption({QStringLiteral("backdrop"), QStringLiteral("1440x900 background image"), QStringLiteral("png")});
    parser.addOption({QStringLiteral("frame"), QStringLiteral("window frame X,Y,W,H"), QStringLiteral("rect"), QStringLiteral("549,263,650,504")});
    parser.addOption({QStringLiteral("client"), QStringLiteral("client colour"), QStringLiteral("color"), QStringLiteral("#1b2031")});
    parser.addOption({QStringLiteral("scales"), QStringLiteral("comma separated"), QStringLiteral("list"), QStringLiteral("1,1.3333333")});
    parser.addOption({QStringLiteral("decoration-plugin"), QStringLiteral("plugin file"), QStringLiteral("file"), QStringLiteral(PFDECO_PLUGIN)});
    parser.addOption({QStringLiteral("font"),
                      QStringLiteral("title font (QFont string)"),
                      QStringLiteral("font"),
                      QStringLiteral("Manrope,10.5,-1,5,800,0,0,0,0,0,0,0,0,0,0,1,,0,0")});
    parser.addOption({QStringLiteral("fuzz"), QStringLiteral("run random scenes instead of the checks (--scenes, --seed)")});
    parser.addOption({QStringLiteral("scenes"), QStringLiteral("number of random scenes (default: PF_FUZZ_COUNT, else 200)"), QStringLiteral("n")});
    parser.addOption({QStringLiteral("seed"), QStringLiteral("seed of the random scenes (default: PF_FUZZ_SEED, else 1)"), QStringLiteral("n")});
    parser.process(app);

    if (parser.isSet(QStringLiteral("fonts"))) {
        QDir dir(parser.value(QStringLiteral("fonts")));
        for (const QString &f : dir.entryList({QStringLiteral("*.ttf")}, QDir::Files)) {
            QFontDatabase::addApplicationFont(dir.filePath(f));
        }
    }
    s_font.fromString(parser.value(QStringLiteral("font")));
    if (s_font.pointSizeF() > 0) {
        // KWin on Wayland: 96 dpi logical, so 10.5 pt = 14 px (the offscreen platform uses another dpi)
        s_font.setPixelSize(int(std::lround(s_font.pointSizeF() * 96.0 / 72.0)));
    }
    out() << "title font: " << s_font.toString() << " resolved family " << QFontInfo(s_font).family() << " style " << QFontInfo(s_font).styleName() << " px "
          << QFontInfo(s_font).pixelSize() << "\n";

    const QString pluginPath = QFileInfo(parser.value(QStringLiteral("decoration-plugin"))).absoluteFilePath();
    QPluginLoader loader(pluginPath);
    auto *factory = qobject_cast<KPluginFactory *>(loader.instance());
    if (!factory) {
        out() << "FAIL cannot load plugin " << pluginPath << ": " << loader.errorString() << "\n";
        return 2;
    }
    // KWin takes the plugin id from the file name (the embedded metadata has no explicit Id).
    const KPluginMetaData meta(loader);
    out() << "plugin id: " << meta.pluginId() << " (" << meta.name() << ")\n";

    Harness h;
    h.factory = factory;
    h.settings = std::make_shared<DecorationSettings>(&h.bridge);
    h.scheme = KSharedConfig::openConfig(parser.value(QStringLiteral("scheme")), KConfig::SimpleConfig);
    if (parser.isSet(QStringLiteral("other-scheme"))) {
        h.otherScheme = KSharedConfig::openConfig(parser.value(QStringLiteral("other-scheme")), KConfig::SimpleConfig);
    }
    h.outDir = parser.value(QStringLiteral("out"));
    h.name = parser.value(QStringLiteral("name"));
    QDir().mkpath(h.outDir);
    if (parser.isSet(QStringLiteral("backdrop"))) {
        h.backdrop = QImage(parser.value(QStringLiteral("backdrop"))).convertToFormat(QImage::Format_ARGB32_Premultiplied);
    }
    const QStringList fr = parser.value(QStringLiteral("frame")).split(QLatin1Char(','));
    h.frame = QRectF(fr.value(0).toDouble(), fr.value(1).toDouble(), fr.value(2).toDouble(), fr.value(3).toDouble());
    h.clientColor = QColor(parser.value(QStringLiteral("client")));

    FakeAccel accel;
    bool dbus = false;
    {
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (bus.isConnected() && bus.registerService(QStringLiteral("org.kde.kglobalaccel"))
            && bus.registerObject(QStringLiteral("/component/kwin"), &accel, QDBusConnection::ExportScriptableSlots)) {
            dbus = true;
        }
    }
    out() << "fake kglobalaccel on the session bus: " << (dbus ? "yes" : "no (snap checks skipped)") << "\n";
    FakeTabletMode fakeTablet;
    bool tabletDbus = false;
    {
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (bus.isConnected() && bus.registerService(QStringLiteral("org.kde.KWin"))
            && bus.registerObject(QStringLiteral("/org/kde/KWin"),
                                  &fakeTablet,
                                  QDBusConnection::ExportAllProperties | QDBusConnection::ExportAllSignals | QDBusConnection::ExportAllSlots)) {
            tabletDbus = true;
        }
    }
    out() << "fake KWin TabletModeManager on the session bus: " << (tabletDbus ? "yes" : "no (tablet checks skipped)") << "\n";

    if (parser.isSet(QStringLiteral("fuzz"))) {
        // An option, else the environment variable, else the default.
        auto number = [&parser](const QString &option, const char *variable, uint fallback) {
            const QString text = parser.isSet(option) ? parser.value(option) : qEnvironmentVariable(variable);
            bool ok = false;
            const uint value = text.toUInt(&ok);
            return ok ? value : fallback;
        };
        const int scenes = int(std::min(number(QStringLiteral("scenes"), "PF_FUZZ_COUNT", 200), 100000u));
        const quint32 seed = number(QStringLiteral("seed"), "PF_FUZZ_SEED", 1);
        out() << "random scenes: " << scenes << ", seed " << seed << " (repeat with --fuzz --scenes " << scenes << " --seed " << seed << ")\n";
        runFuzz(h, tabletDbus ? &fakeTablet : nullptr, scenes, seed);
        out() << (h.failures == 0 ? "ALL PASS" : "FAILURES: ") << (h.failures ? QString::number(h.failures) : QString()) << "\n";
        return h.failures == 0 ? 0 : 1;
    }

    QList<qreal> scales;
    for (const QString &s : parser.value(QStringLiteral("scales")).split(QLatin1Char(','))) {
        scales << s.toDouble();
    }

    auto base = [&h](qreal scale) {
        auto st = std::make_unique<WindowState>();
        st->width = h.frame.width();
        st->height = h.frame.height() - 50;
        st->scale = scale;
        return st;
    };

    // Tablet mode at start (the first decoration of the process creates the watcher): the value
    // comes from an asynchronous Properties.Get, so KWin started in tablet mode is not missed
    // (TABLET.md F3); later changes come from the signal.
    if (tabletDbus) {
        writeConfig(QStringLiteral("RightGlyphs"), -1, true);
        wait(5);
        fakeTablet.mode = true; // no signal: only the Get can see it
        auto in = h.create(base(1));
        if (in.deco) {
            const qreal before = in.deco->borderTop();
            wait(400);
            const qreal after = in.deco->borderTop();
            h.check(std::abs(after - 52) <= 0.01,
                    QStringLiteral("tablet mode at start read with an asynchronous Properties.Get: title bar %1 -> %2 (52)").arg(before).arg(after));
            fakeTablet.set(false);
            wait(200);
            h.check(std::abs(in.deco->borderTop() - 50) <= 0.01,
                    QStringLiteral("tabletModeChanged(false) signal: title bar back to %1").arg(in.deco->borderTop()));
            h.destroy(in);
        }
    }

    for (qreal scale : scales) {
        using Setup = std::function<void(WindowState &)>;
        using Action = std::function<void(Harness &, Decoration *)>;
        struct Scene {
            QString name;
            QString style;
            bool tool;
            Setup setup;
            Action action;
            QRectF tile = QRectF();
        };
        const QList<Scene> scenes{
            {QStringLiteral("01-active"), QStringLiteral("RightGlyphs"), false, nullptr, nullptr},
            {QStringLiteral("02-inactive"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.active = false;
             },
             nullptr},
            {QStringLiteral("03-hover-maximize"),
             QStringLiteral("RightGlyphs"),
             false,
             nullptr,
             [](Harness &h, Decoration *d) {
                 h.hover(d, h.buttonCenter(d, DecorationButtonType::Maximize));
             }},
            {QStringLiteral("04-hover-close"),
             QStringLiteral("RightGlyphs"),
             false,
             nullptr,
             [](Harness &h, Decoration *d) {
                 h.hover(d, h.buttonCenter(d, DecorationButtonType::Close));
             }},
            {QStringLiteral("05-pressed-minimize"),
             QStringLiteral("RightGlyphs"),
             false,
             nullptr,
             [](Harness &h, Decoration *d) {
                 const QPointF c = h.buttonCenter(d, DecorationButtonType::Minimize);
                 h.hover(d, c);
                 h.press(d, c);
             }},
            {QStringLiteral("06-inactive-hover-close"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.active = false;
             },
             [](Harness &h, Decoration *d) {
                 h.hover(d, h.buttonCenter(d, DecorationButtonType::Close));
             }},
            {QStringLiteral("07-maximized"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.maximized = true;
             },
             nullptr},
            {QStringLiteral("08-tiled-left"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.edges = Qt::LeftEdge | Qt::TopEdge | Qt::BottomEdge;
             },
             nullptr},
            {QStringLiteral("09-tiled-right"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.edges = Qt::RightEdge | Qt::TopEdge | Qt::BottomEdge;
             },
             nullptr},
            {QStringLiteral("09b-tiled-left-gaps"), QStringLiteral("RightGlyphs"), false, nullptr, nullptr, QRectF(0, 0, 0.5, 1)},
            {QStringLiteral("09c-tiled-quarter-gaps"), QStringLiteral("RightGlyphs"), false, nullptr, nullptr, QRectF(0.5, 0.5, 0.5, 0.5)},
            {QStringLiteral("10-tool"),
             QStringLiteral("RightGlyphs"),
             true,
             [](WindowState &s) {
                 s.caption = QStringLiteral("Layers");
             },
             nullptr},
            {QStringLiteral("11-left"), QStringLiteral("LeftCircles"), false, nullptr, nullptr},
            {QStringLiteral("12-left-hover"),
             QStringLiteral("LeftCircles"),
             false,
             nullptr,
             [](Harness &h, Decoration *d) {
                 h.hover(d, h.buttonCenter(d, DecorationButtonType::Minimize));
             }},
            {QStringLiteral("13-left-inactive"),
             QStringLiteral("LeftCircles"),
             false,
             [](WindowState &s) {
                 s.active = false;
             },
             nullptr},
            {QStringLiteral("14-showonhover-away"), QStringLiteral("ShowOnHover"), false, nullptr, nullptr},
            {QStringLiteral("15-showonhover-over"),
             QStringLiteral("ShowOnHover"),
             false,
             nullptr,
             [](Harness &h, Decoration *d) {
                 h.hover(d, QPointF(300, 20));
             }},
            {QStringLiteral("16-long-title"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.caption = QStringLiteral("A very long document title that does not fit into the title bar of this window at all — Kate");
             },
             nullptr},
            {QStringLiteral("17-disabled"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.maximizeable = false;
                 s.minimizeable = false;
             },
             nullptr},
            {QStringLiteral("18-shaded"),
             QStringLiteral("RightGlyphs"),
             false,
             [](WindowState &s) {
                 s.shaded = true;
             },
             nullptr},
            {QStringLiteral("19-maximized-left"),
             QStringLiteral("LeftCircles"),
             false,
             [](WindowState &s) {
                 s.maximized = true;
             },
             nullptr},
        };

        for (const Scene &scene : scenes) {
            writeConfig(scene.style, true, true);
            wait(5); // lets the per-pass config throttle expire
            auto st = base(scale);
            if (scene.setup) {
                scene.setup(*st);
            }
            const bool maximized = st->maximized;
            QRectF where = h.frame;
            if (maximized) {
                where = QRectF(0, 34, h.backdrop.isNull() ? 1440 : h.backdrop.width(), 600);
                st->width = where.width();
                st->height = where.height() - 40;
            }
            auto in = h.create(std::move(st), scene.tool, scene.tile);
            if (!in.deco) {
                continue;
            }
            if (scene.action) {
                scene.action(h, in.deco);
            }
            wait(350);
            h.render(in.deco, scene.name, scale, where);
            h.destroy(in);
        }

        // Extra buttons in the same style, a toggled keep-above and context help.
        {
            s_left = {DecorationButtonType::Menu, DecorationButtonType::OnAllDesktops};
            s_right = {DecorationButtonType::ContextHelp,
                       DecorationButtonType::KeepAbove,
                       DecorationButtonType::KeepBelow,
                       DecorationButtonType::Shade,
                       DecorationButtonType::ApplicationMenu,
                       DecorationButtonType::Spacer,
                       DecorationButtonType::Minimize,
                       DecorationButtonType::Maximize,
                       DecorationButtonType::Close};
            writeConfig(QStringLiteral("RightGlyphs"), true, true);
            wait(5);
            auto st = base(scale);
            st->keepAbove = true;
            st->contextHelp = true;
            st->shadeable = true;
            auto in = h.create(std::move(st));
            if (in.deco) {
                h.hover(in.deco, h.buttonCenter(in.deco, DecorationButtonType::KeepBelow));
                wait(350);
                h.render(in.deco, QStringLiteral("20-extra-buttons"), scale, h.frame);
                h.destroy(in);
            }
            s_left = {DecorationButtonType::Menu};
            s_right = {DecorationButtonType::Minimize, DecorationButtonType::Maximize, DecorationButtonType::Close};
        }

        // Geometry checks against the board (Windows.dc.html anatomy), at this scale.
        {
            writeConfig(QStringLiteral("RightGlyphs"), true, true);
            wait(5);
            auto in = h.create(base(scale));
            if (in.deco) {
                const qreal w = in.deco->size().width();
                auto *deco = in.deco;
                const auto buttons = deco->findChildren<DecorationButton *>();
                QRectF close, maximize, minimize, menu;
                // hit areas are the circle plus half the gap on each side: same centre as the circle
                for (auto *b : buttons) {
                    const QRectF g = b->geometry();
                    switch (b->type()) {
                    case DecorationButtonType::Close:
                        close = g;
                        break;
                    case DecorationButtonType::Maximize:
                        maximize = g;
                        break;
                    case DecorationButtonType::Minimize:
                        minimize = g;
                        break;
                    case DecorationButtonType::Menu:
                        menu = g;
                        break;
                    default:
                        break;
                    }
                }
                const qreal tol = 1.0 / scale + 0.01;
                h.check(std::abs(in.deco->borderTop() - 50) <= tol,
                        QStringLiteral("title bar %1 px (board 50) at scale %2").arg(in.deco->borderTop()).arg(scale));
                h.check(std::abs((w - close.center().x()) - 24) <= 0.01,
                        QStringLiteral("close centre %1 px from the right (board 10 + 14 = 24)").arg(w - close.center().x()));
                h.check(std::abs(close.center().x() - maximize.center().x() - 34) <= 0.01,
                        QStringLiteral("circle pitch %1 (board 28 + 6 = 34)").arg(close.center().x() - maximize.center().x()));
                h.check(std::abs((w - maximize.center().x()) - 58) <= 0.01,
                        QStringLiteral("maximize centre %1 px from the right (snap flyout expects 58)").arg(w - maximize.center().x()));
                h.check(std::abs(menu.center().x() - (16 + 13)) <= 0.01, QStringLiteral("icon centre x %1 (board 16 + 13 = 29)").arg(menu.center().x()));
                h.check(in.deco->borderLeft() == 0 && in.deco->borderRight() == 0 && in.deco->borderBottom() == 0, QStringLiteral("no side/bottom borders"));
                const BorderRadius r = in.deco->borderRadius();
                h.check(r.bottomLeft() > 12 && r.bottomRight() > 12, QStringLiteral("bottom clip radius %1").arg(r.bottomLeft()));
                const BorderOutline o = in.deco->borderOutline();
                h.check(!o.isNull() && o.radius().topLeft() + o.thickness() > 13.5 && o.radius().topLeft() + o.thickness() < 14.5,
                        QStringLiteral("outline outer radius %1 (board 14)").arg(o.radius().topLeft() + o.thickness()));
                h.check(in.deco->resizeOnlyBorders().left() >= 7.5 && in.deco->resizeOnlyBorders().bottom() >= 7.5,
                        QStringLiteral("resize band %1 px (board 8)").arg(in.deco->resizeOnlyBorders().left()));
                h.check(bool(in.deco->shadow()), QStringLiteral("active shadow present"));
                if (const auto shadow = in.deco->shadow()) {
                    // The bottom profile under the middle of the window against the CSS model
                    // (Gaussian, sigma = blur / 2, shape = frame + 1 px outline moved down by dy).
                    const QImage img = shadow->shadow();
                    const QMarginsF pad = shadow->padding();
                    const int col = int(shadow->innerShadowRect().x());
                    const qreal frameBottom = img.height() - pad.bottom();
                    const bool dark = in.window->palette().color(QPalette::Window).lightness() < 128;
                    const qreal opacity = dark ? 0.55 : 0.22;
                    const qreal sigma = 45;
                    const qreal shapeBottom = frameBottom + 1 + 34;
                    qreal worst = 0;
                    for (int row = int(frameBottom); row < img.height(); ++row) {
                        const qreal y = row + 0.5;
                        const qreal model = opacity * 0.5 * std::erfc((y - shapeBottom) / (sigma * std::sqrt(2.0)));
                        const qreal got = qAlpha(img.pixel(col, row)) / 255.0;
                        worst = std::max(worst, std::abs(got - model));
                    }
                    h.check(worst < 0.02, QStringLiteral("shadow below the window within %1 alpha of the CSS Gaussian").arg(worst, 0, 'f', 4));
                }
                h.destroy(in);
            }
            auto st = base(scale);
            st->maximized = true;
            auto mx = h.create(std::move(st));
            if (mx.deco) {
                h.check(std::abs(mx.deco->borderTop() - 40) <= 1.0 / scale + 0.01,
                        QStringLiteral("maximized title bar %1 (board 40)").arg(mx.deco->borderTop()));
                h.check(!mx.deco->shadow() && mx.deco->borderOutline().isNull() && mx.deco->borderRadius().bottomLeft() == 0,
                        QStringLiteral("maximized: no shadow, no outline, square"));
                h.destroy(mx);
            }
            auto padded = h.create(base(scale), false, QRectF(0, 0, 0.5, 1));
            if (padded.deco) {
                const BorderRadius r = padded.deco->borderRadius();
                const BorderRadius o = padded.deco->borderOutline().radius();
                h.check(r.bottomLeft() > 12 && r.bottomRight() == 0 && o.topLeft() == 0 && o.topRight() == 0 && o.bottomLeft() > 12 && o.bottomRight() == 0,
                        QStringLiteral("left tile with gaps: only the outer bottom corner is round"));
                h.destroy(padded);
            }
            auto tool = h.create(base(scale), true);
            if (tool.deco) {
                h.check(std::abs(tool.deco->borderTop() - 32) <= 1.0 / scale + 0.01,
                        QStringLiteral("tool window title bar %1 (board 32)").arg(tool.deco->borderTop()));
                h.destroy(tool);
            }
        }

        // State changes on a live decoration: no crash, borders follow.
        {
            writeConfig(QStringLiteral("RightGlyphs"), true, true);
            wait(5);
            auto in = h.create(base(scale));
            if (in.deco) {
                auto *win = in.window;
                auto *dw = win->w();
                for (int i = 0; i < 3; ++i) {
                    in.state->maximized = true;
                    Q_EMIT dw->maximizedChanged(true);
                    in.state->active = false;
                    Q_EMIT dw->activeChanged(false);
                    in.state->edges = Qt::LeftEdge | Qt::TopEdge | Qt::BottomEdge;
                    Q_EMIT dw->adjacentScreenEdgesChanged(in.state->edges);
                    in.state->maximized = false;
                    Q_EMIT dw->maximizedChanged(false);
                    in.state->width = 200 + 50 * i;
                    Q_EMIT dw->widthChanged(in.state->width);
                    Q_EMIT dw->sizeChanged(QSizeF(in.state->width, in.state->height));
                    in.state->active = true;
                    Q_EMIT dw->activeChanged(true);
                    in.state->caption = QString();
                    Q_EMIT dw->captionChanged(QString());
                    in.state->edges = {};
                    Q_EMIT dw->adjacentScreenEdgesChanged({});
                    in.state->width = 40; // narrower than the buttons
                    Q_EMIT dw->widthChanged(in.state->width);
                    in.state->shaded = true;
                    Q_EMIT dw->shadedChanged(true);
                    in.state->shaded = false;
                    Q_EMIT dw->shadedChanged(false);
                    Q_EMIT dw->paletteChanged(win->palette());
                    Q_EMIT h.settings->reconfigured();
                    wait(30);
                    QImage img(QSize(260, 60), QImage::Format_ARGB32_Premultiplied);
                    img.fill(Qt::transparent);
                    QPainter p(&img);
                    in.deco->paint(&p, QRectF(0, 0, 260, 60));
                }
                h.check(std::abs(in.deco->borderTop() - 50) <= 1.0 / scale + 0.01,
                        QStringLiteral("state churn survived, title bar back to %1").arg(in.deco->borderTop()));
                // A window that switches to another colour scheme (per-window schemes, or the global
                // Dark <-> Light switch): the title bar follows the new Header colour.
                if (h.otherScheme) {
                    in.state->width = 650;
                    Q_EMIT dw->widthChanged(in.state->width);
                    const KSharedConfig::Ptr previous = in.state->scheme;
                    in.state->scheme = h.otherScheme;
                    Q_EMIT dw->paletteChanged(win->palette());
                    wait(250);
                    QImage img(QSize(650, 60), QImage::Format_ARGB32_Premultiplied);
                    img.fill(Qt::transparent);
                    {
                        QPainter p(&img);
                        in.deco->paint(&p, QRectF(0, 0, 650, 60));
                    }
                    const QColor expected = KColorScheme(QPalette::Active, KColorScheme::Header, h.otherScheme).background().color();
                    const QColor got = img.pixelColor(300, 5);
                    h.check(std::abs(got.red() - expected.red()) <= 1 && std::abs(got.blue() - expected.blue()) <= 1,
                            QStringLiteral("palette change: title bar %1 follows the new scheme %2").arg(got.name(), expected.name()));
                    in.state->scheme = previous;
                }
                h.destroy(in);
            }
        }

        // Snap-layouts trigger (contract: hover or hold maximize 600 ms -> invokeShortcut).
        if (dbus) {
            writeConfig(QStringLiteral("RightGlyphs"), true, true);
            wait(5);
            auto in = h.create(base(scale));
            if (in.deco) {
                const QPointF c = h.buttonCenter(in.deco, DecorationButtonType::Maximize);
                accel.count = 0;
                h.hover(in.deco, c);
                wait(450);
                h.check(accel.count == 0, QStringLiteral("hover: nothing before 600 ms"));
                wait(400);
                h.check(accel.count == 1 && accel.names.value(0) == QStringLiteral("Plasma Fusion: Snap Layouts"),
                        QStringLiteral("hover 600 ms invokes 'Plasma Fusion: Snap Layouts' (%1 calls)").arg(accel.count));
                wait(700);
                h.check(accel.count == 1, QStringLiteral("hover: fires once per hover"));
                // off the button onto the title and back, without leaving the decoration: the
                // flyout's shortcut toggles, so no second trigger
                QHoverEvent away(QEvent::HoverMove, QPointF(200, 20), QPointF(200, 20), c);
                QCoreApplication::sendEvent(in.deco, &away);
                wait(50);
                QHoverEvent back(QEvent::HoverMove, c, c, QPointF(200, 20));
                QCoreApplication::sendEvent(in.deco, &back);
                wait(800);
                h.check(accel.count == 1, QStringLiteral("hover: no second trigger until the pointer leaves the title bar"));
                h.leave(in.deco);
                wait(50);
                h.hover(in.deco, c);
                wait(800);
                h.check(accel.count == 2, QStringLiteral("hover: fires again after leaving (%1 calls)").arg(accel.count));
                h.leave(in.deco);
                wait(50);
                // hold
                accel.count = 0;
                const int before = in.state->toggleMaximize;
                h.hover(in.deco, c);
                wait(100);
                h.press(in.deco, c);
                wait(750);
                h.check(accel.count == 1, QStringLiteral("hold 600 ms invokes the shortcut (%1 calls)").arg(accel.count));
                h.release(in.deco, c);
                wait(100);
                h.check(in.state->toggleMaximize == before, QStringLiteral("release after the hold does not toggle maximize"));
                // a quick click still maximizes, and does not fire
                accel.count = 0;
                h.press(in.deco, c);
                wait(80);
                h.release(in.deco, c);
                wait(100);
                h.check(in.state->toggleMaximize == before + 1 && accel.count == 0, QStringLiteral("a click maximizes without the flyout"));
                h.leave(in.deco);
                h.destroy(in);
            }
            // inactive window: no trigger
            {
                auto st = base(scale);
                st->active = false;
                auto inactive = h.create(std::move(st));
                if (inactive.deco) {
                    accel.count = 0;
                    h.hover(inactive.deco, h.buttonCenter(inactive.deco, DecorationButtonType::Maximize));
                    wait(800);
                    h.check(accel.count == 0, QStringLiteral("inactive window: no trigger"));
                    h.destroy(inactive);
                }
            }
            // The script disabled: no flyout at all, so hold and release maximize as usual.
            for (int hoverKey : {1, 0, -1}) {
                writeConfig(QStringLiteral("RightGlyphs"), hoverKey, false);
                wait(5);
                auto off = h.create(base(scale));
                if (off.deco) {
                    const QPointF c = h.buttonCenter(off.deco, DecorationButtonType::Maximize);
                    accel.count = 0;
                    h.hover(off.deco, c);
                    h.press(off.deco, c);
                    wait(800);
                    h.release(off.deco, c);
                    wait(100);
                    h.check(accel.count == 0 && off.state->toggleMaximize == 1 && !off.state->toolTip.contains(QLatin1String("hold")),
                            QStringLiteral("script off (SnapLayoutsOnHover=%1): hold does nothing special, release maximizes, plain tooltip '%2'")
                                .arg(hoverKey)
                                .arg(off.state->toolTip));
                    h.destroy(off);
                }
            }
            // Contract default (owner decision 4, hold): SnapLayoutsOnHover absent or false.
            for (int hoverKey : {-1, 0}) {
                writeConfig(QStringLiteral("RightGlyphs"), hoverKey, true);
                wait(5);
                auto hold = h.create(base(scale));
                if (hold.deco) {
                    const QString label = hoverKey < 0 ? QStringLiteral("default (key absent)") : QStringLiteral("SnapLayoutsOnHover=false");
                    const QPointF c = h.buttonCenter(hold.deco, DecorationButtonType::Maximize);
                    accel.count = 0;
                    h.hover(hold.deco, c);
                    wait(900);
                    h.check(accel.count == 0, QStringLiteral("%1: resting 900 ms on maximize opens nothing").arg(label));
                    h.check(hold.state->toolTip == QStringLiteral("Maximize \u00b7 hold for snap layouts"),
                            QStringLiteral("%1: tooltip '%2'").arg(label, hold.state->toolTip));
                    h.press(hold.deco, c);
                    wait(80);
                    h.release(hold.deco, c);
                    wait(100);
                    h.check(hold.state->toggleMaximize == 1 && accel.count == 0, QStringLiteral("%1: after the rest, the first click maximizes").arg(label));
                    h.press(hold.deco, c);
                    wait(750);
                    h.check(accel.count == 1, QStringLiteral("%1: holding 600 ms opens the snap layouts (%2 calls)").arg(label).arg(accel.count));
                    h.release(hold.deco, c);
                    wait(100);
                    h.check(hold.state->toggleMaximize == 1, QStringLiteral("%1: the release after the hold does not toggle maximize").arg(label));
                    h.leave(hold.deco);
                    h.destroy(hold);
                }
            }
            // A press that slides off maximize cancels its click, and the hold with it (review).
            {
                writeConfig(QStringLiteral("RightGlyphs"), -1, true);
                wait(5);
                auto slide = h.create(base(scale));
                if (slide.deco) {
                    const QPointF c = h.buttonCenter(slide.deco, DecorationButtonType::Maximize);
                    const QPointF away(slide.deco->size().width() / 2, c.y());
                    accel.count = 0;
                    h.hover(slide.deco, c);
                    h.press(slide.deco, c);
                    wait(100);
                    h.hover(slide.deco, away);
                    wait(750);
                    h.check(accel.count == 0,
                            QStringLiteral("hold: a press that slides off maximize does not open the snap layouts (%1 calls)").arg(accel.count));
                    h.release(slide.deco, away);
                    wait(100);
                    h.check(slide.state->toggleMaximize == 0, QStringLiteral("hold: the release off the button does not maximize"));
                    h.hover(slide.deco, c);
                    h.press(slide.deco, c);
                    wait(750);
                    h.check(accel.count == 1, QStringLiteral("hold: the next hold on maximize still opens the snap layouts"));
                    h.release(slide.deco, c);
                    wait(100);
                    h.leave(slide.deco);
                    h.destroy(slide);
                }
            }
            // reconfigure switches the style live
            writeConfig(QStringLiteral("RightGlyphs"), true, true);
            wait(5);
            auto live = h.create(base(scale));
            if (live.deco) {
                writeConfig(QStringLiteral("LeftCircles"), true, true);
                wait(5);
                Q_EMIT h.settings->reconfigured();
                wait(50);
                const QPointF close = h.buttonCenter(live.deco, DecorationButtonType::Close);
                h.check(close.x() < 40, QStringLiteral("reconfigure: LeftCircles moves close to the left (x %1)").arg(close.x()));
                writeConfig(QStringLiteral("RightGlyphs"), true, true);
                wait(5);
                Q_EMIT h.settings->reconfigured();
                wait(50);
                h.check(h.buttonCenter(live.deco, DecorationButtonType::Close).x() > live.deco->size().width() - 40,
                        QStringLiteral("reconfigure: back to RightGlyphs"));
                h.destroy(live);
            }
        }

        // Short screens (ADAPTIVE.md 5.12): 40 px title bars under 800 logical px, following the
        // output's geometry (rotation to portrait gives 50 again).
        {
            writeConfig(QStringLiteral("RightGlyphs"), -1, true);
            wait(5);
            FakeOutput screen;
            screen.rect = QRect(0, 0, 1366, 768);
            const qreal tol = 1.0 / scale + 0.01;
            auto in = h.create(base(scale), false, QRectF(), &screen);
            if (in.deco) {
                h.check(std::abs(in.deco->borderTop() - 40) <= tol, QStringLiteral("1366x768 screen: title bar %1 (40)").arg(in.deco->borderTop()));
                h.check(std::abs((in.deco->size().width() - h.buttonCenter(in.deco, DecorationButtonType::Maximize).x()) - 58) <= 0.01,
                        QStringLiteral("1366x768 screen: maximize centre still 58 px from the right"));
                h.render(in.deco, QStringLiteral("23-short-screen"), scale, h.frame);
                screen.setGeometry(QRect(0, 0, 768, 1366));
                wait(10);
                h.check(std::abs(in.deco->borderTop() - 50) <= tol, QStringLiteral("rotated to 768x1366: title bar %1 (50)").arg(in.deco->borderTop()));
                screen.setGeometry(QRect(0, 0, 1280, 799));
                wait(10);
                h.check(std::abs(in.deco->borderTop() - 40) <= tol, QStringLiteral("1280x799: title bar %1 (40)").arg(in.deco->borderTop()));
                screen.setGeometry(QRect(0, 0, 1440, 900));
                wait(10);
                h.check(std::abs(in.deco->borderTop() - 50) <= tol, QStringLiteral("1440x900: title bar %1 (50)").arg(in.deco->borderTop()));
                h.destroy(in);
            }
            screen.rect = QRect(0, 0, 1366, 768);
            auto tool = h.create(base(scale), true, QRectF(), &screen);
            if (tool.deco) {
                h.check(std::abs(tool.deco->borderTop() - 32) <= tol, QStringLiteral("1366x768 screen: tool window keeps %1 (32)").arg(tool.deco->borderTop()));
                h.destroy(tool);
            }
        }

        // Tablet mode (TABLET.md 4.9): touch title bars while KWin reports tablet mode, live.
        if (tabletDbus && dbus) {
            const qreal tol = 1.0 / scale + 0.01;
            writeConfig(QStringLiteral("RightGlyphs"), 1, true); // hover on: tablet mode must still ignore it
            wait(5);
            auto in = h.create(base(scale));
            if (in.deco) {
                h.check(std::abs(in.deco->borderTop() - 50) <= tol, QStringLiteral("laptop: title bar %1 (50)").arg(in.deco->borderTop()));
                fakeTablet.set(true);
                wait(200);
                const qreal w = in.deco->size().width();
                h.check(std::abs(in.deco->borderTop() - 52) <= tol, QStringLiteral("tablet: title bar %1 (52)").arg(in.deco->borderTop()));
                h.check(h.smallestHit(in.deco, false) >= 44 - 0.01 && h.smallestHit(in.deco, true) >= 44 - 0.01,
                        QStringLiteral("tablet: every hit area at least 44 x 44 (smallest %1 x %2)")
                            .arg(h.smallestHit(in.deco, false))
                            .arg(h.smallestHit(in.deco, true)));
                h.check(std::abs((w - h.buttonCenter(in.deco, DecorationButtonType::Close).x()) - 26) <= 0.01
                            && std::abs((w - h.buttonCenter(in.deco, DecorationButtonType::Maximize).x()) - 70) <= 0.01,
                        QStringLiteral("tablet: close centre %1, maximize centre %2 px from the right (26, 70)")
                            .arg(w - h.buttonCenter(in.deco, DecorationButtonType::Close).x())
                            .arg(w - h.buttonCenter(in.deco, DecorationButtonType::Maximize).x()));
                h.render(in.deco, QStringLiteral("21-tablet"), scale, h.frame);
                const QPointF c = h.buttonCenter(in.deco, DecorationButtonType::Maximize);
                accel.count = 0;
                h.hover(in.deco, c);
                wait(900);
                h.check(accel.count == 0, QStringLiteral("tablet: resting on maximize opens nothing even with SnapLayoutsOnHover=true"));
                h.render(in.deco, QStringLiteral("22-tablet-hover-maximize"), scale, h.frame);
                const int toggles = in.state->toggleMaximize;
                h.press(in.deco, c);
                wait(750);
                h.check(accel.count == 1, QStringLiteral("tablet: holding 600 ms (touch long press) opens the snap layouts"));
                h.release(in.deco, c);
                wait(100);
                h.check(in.state->toggleMaximize == toggles, QStringLiteral("tablet: no maximize after the hold"));
                h.press(in.deco, c);
                wait(80);
                h.release(in.deco, c);
                wait(100);
                h.check(in.state->toggleMaximize == toggles + 1, QStringLiteral("tablet: a tap maximizes"));
                h.leave(in.deco);
                fakeTablet.set(false);
                wait(200);
                const qreal closeHit = h.hitOf(in.deco, DecorationButtonType::Close).width();
                h.check(std::abs(in.deco->borderTop() - 50) <= tol && std::abs(closeHit - 34) <= 0.01,
                        QStringLiteral("back to laptop: title bar %1, close hit width %2 (50, 34)").arg(in.deco->borderTop()).arg(closeHit));
                h.destroy(in);
            }
            fakeTablet.set(true);
            wait(50);
            // maximized, tool window, short screen: 44 px bars
            {
                auto st = base(scale);
                st->maximized = true;
                auto mx = h.create(std::move(st));
                if (mx.deco) {
                    h.check(std::abs(mx.deco->borderTop() - 44) <= tol && h.smallestHit(mx.deco, true) >= 44 - 0.01,
                            QStringLiteral("tablet maximized: title bar %1 (44), hit height %2").arg(mx.deco->borderTop()).arg(h.smallestHit(mx.deco, true)));
                    h.destroy(mx);
                }
                auto tool = h.create(base(scale), true);
                if (tool.deco) {
                    h.check(
                        std::abs(tool.deco->borderTop() - 44) <= tol && h.smallestHit(tool.deco, false) >= 44 - 0.01,
                        QStringLiteral("tablet tool window: title bar %1 (44), hit width %2").arg(tool.deco->borderTop()).arg(h.smallestHit(tool.deco, false)));
                    h.destroy(tool);
                }
                FakeOutput screen;
                screen.rect = QRect(0, 0, 1366, 768);
                auto shortScreen = h.create(base(scale), false, QRectF(), &screen);
                if (shortScreen.deco) {
                    h.check(std::abs(shortScreen.deco->borderTop() - 44) <= tol,
                            QStringLiteral("tablet on a 1366x768 screen: title bar %1 (44)").arg(shortScreen.deco->borderTop()));
                    h.destroy(shortScreen);
                }
            }
            // Every KWin button with the app icon next to another button (review): no two hit
            // areas overlap (KDecoration gives a press to the first hovered button), each >= 44.
            {
                s_left = {DecorationButtonType::Menu, DecorationButtonType::OnAllDesktops};
                s_right = {DecorationButtonType::ContextHelp,
                           DecorationButtonType::KeepAbove,
                           DecorationButtonType::KeepBelow,
                           DecorationButtonType::Minimize,
                           DecorationButtonType::Maximize,
                           DecorationButtonType::Menu,
                           DecorationButtonType::Close};
                writeConfig(QStringLiteral("RightGlyphs"), -1, true);
                wait(5);
                auto st = base(scale);
                st->contextHelp = true;
                st->width = 900;
                auto many = h.create(std::move(st));
                if (many.deco) {
                    QList<QRectF> hits;
                    for (auto *b : h.visibleButtons(many.deco)) {
                        hits << b->geometry();
                    }
                    std::sort(hits.begin(), hits.end(), [](const QRectF &a, const QRectF &b) {
                        return a.left() < b.left();
                    });
                    qreal overlap = 0;
                    for (int i = 1; i < hits.size(); ++i) {
                        overlap = std::max(overlap, hits[i - 1].right() - hits[i].left());
                    }
                    h.check(hits.size() == 9 && overlap <= 1e-6 && h.smallestHit(many.deco, false) >= 44 - 0.01,
                            QStringLiteral("tablet, app icon next to other buttons on both sides: %1 hit areas, largest overlap %2, smallest width %3")
                                .arg(hits.size())
                                .arg(overlap)
                                .arg(h.smallestHit(many.deco, false)));
                    h.render(many.deco, QStringLiteral("26-tablet-many-buttons"), scale, h.frame);
                    h.destroy(many);
                }
                s_left = {DecorationButtonType::Menu};
                s_right = {DecorationButtonType::Minimize, DecorationButtonType::Maximize, DecorationButtonType::Close};
            }
            // LeftCircles: 36 px circles with glyphs, hit areas 44
            writeConfig(QStringLiteral("LeftCircles"), -1, true);
            wait(5);
            auto left = h.create(base(scale));
            if (left.deco) {
                h.check(
                    h.smallestHit(left.deco, false) >= 44 - 0.01 && h.smallestHit(left.deco, true) >= 44 - 0.01,
                    QStringLiteral("tablet LeftCircles: smallest hit area %1 x %2").arg(h.smallestHit(left.deco, false)).arg(h.smallestHit(left.deco, true)));
                h.render(left.deco, QStringLiteral("24-tablet-left"), scale, h.frame);
                h.destroy(left);
            }
            // ShowOnHover: always visible in tablet mode (the close circle is red without hover)
            writeConfig(QStringLiteral("ShowOnHover"), -1, true);
            wait(5);
            auto soh = h.create(base(scale));
            if (soh.deco) {
                // below the glyph, inside the circle (36 px in tablet mode)
                const QPointF close = h.buttonCenter(soh.deco, DecorationButtonType::Close) + QPointF(0, 10);
                wait(50);
                const QImage tabletImage = h.paintTitle(soh.deco);
                const QColor tabletColor = tabletImage.pixelColor(close.toPoint());
                h.render(soh.deco, QStringLiteral("25-tablet-showonhover"), scale, h.frame);
                fakeTablet.set(false);
                wait(300);
                const QImage laptopImage = h.paintTitle(soh.deco);
                const QColor laptopColor = laptopImage.pixelColor(close.toPoint());
                const QColor bar = laptopImage.pixelColor(QPoint(300, 10));
                auto near = [](const QColor &a, const QColor &b) {
                    return std::abs(a.red() - b.red()) <= 3 && std::abs(a.green() - b.green()) <= 3 && std::abs(a.blue() - b.blue()) <= 3;
                };
                h.check(near(tabletColor, QColor(217, 67, 75)) && near(laptopColor, bar),
                        QStringLiteral("ShowOnHover: close visible in tablet mode (%1), hidden away from the pointer in laptop mode (%2, bar %3)")
                            .arg(tabletColor.name(), laptopColor.name(), bar.name()));
                h.destroy(soh);
            }
            fakeTablet.set(false);
            wait(50);
        }
    }

    // The shadow on a 200 % screen. KWin 6.7.5 draws a decoration shadow image at one image pixel
    // per logical pixel (Shadow::elementSize, GL_LINEAR nine-patch; no device-pixel-ratio path), so
    // at 200 % it samples the 1x image. Compare that with an exact Gaussian rendered at 2x.
    {
        writeConfig(QStringLiteral("RightGlyphs"), -1, true);
        wait(5);
        auto in = h.create(base(1));
        if (in.deco && in.deco->shadow()) {
            const bool dark = in.window->palette().color(QPalette::Window).lightness() < 128;
            const qreal opacity = dark ? 0.55 : 0.22;
            const QImage plugin = in.deco->shadow()->shadow();
            const QMarginsF pad = in.deco->shadow()->padding();
            const ShadowCheck result = checkShadowAt2x(plugin, pad, opacity, h.outDir + QStringLiteral("/") + h.name);
            h.check(result.upscale < 0.004,
                    QStringLiteral("200 %: upscaling alone (exact 1x shadow sampled like KWin vs exact 2x) differs by at most %1 alpha (%2/255)")
                        .arg(result.upscale, 0, 'f', 4)
                        .arg(result.upscale * 255, 0, 'f', 2));
            h.check(result.total < 0.02,
                    QStringLiteral("200 %: the plugin's shadow as KWin draws it vs an exact 2x Gaussian: at most %1 alpha (at 1x: %2)")
                        .arg(result.total, 0, 'f', 4)
                        .arg(result.at1x, 0, 'f', 4));
            h.destroy(in);
        }
    }

    out() << (h.failures == 0 ? "ALL PASS" : "FAILURES: ") << (h.failures ? QString::number(h.failures) : QString()) << "\n";
    return h.failures == 0 ? 0 : 1;
}

#include "preview.moc"
