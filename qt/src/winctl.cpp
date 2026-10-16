#include "winctl.h"
#include "core.h"

#include <QCursor>
#include <QList>
#include <QRegion>

#include <windows.h>

static QList<WinCtl *> s_all;

WinCtl::WinCtl(QObject *parent) : QObject(parent)
{
    s_all.append(this);
    // GetForegroundWindow et GetWindowRect ne coutent presque rien
    m_fsTimer.setInterval(500);
    connect(&m_fsTimer, &QTimer::timeout, this, &WinCtl::checkFullscreen);
    // bande du haut : seulement quand la barre se masque automatiquement
    m_topTimer.setInterval(40);
    connect(&m_topTimer, &QTimer::timeout, this, &WinCtl::pollTop);
    // la fenetre est reellement masquee pour ne pas gener le jeu (apres
    // l'animation de sortie)
    m_hideTimer.setSingleShot(true);
    m_hideTimer.setInterval(400);
    connect(&m_hideTimer, &QTimer::timeout, this, [this] {
        if (m_win && m_fullscreen)
            m_win->hide();
    });
}

WinCtl::~WinCtl()
{
    s_all.removeAll(this);
    if (!m_label.isEmpty())
        ilot_unregister(m_label.toUtf8().constData());
}

WinCtl *WinCtl::find(const QString &label)
{
    for (WinCtl *c : s_all)
        if (c->m_label == label)
            return c;
    return nullptr;
}

void WinCtl::setWindow(QQuickWindow *w)
{
    if (w == m_win)
        return;
    m_win = w;
    declare();
    m_fsTimer.start();
    Q_EMIT windowChanged();
}

void WinCtl::setLabel(const QString &l)
{
    if (l == m_label)
        return;
    if (!m_label.isEmpty())
        ilot_unregister(m_label.toUtf8().constData());
    m_label = l;
    declare();
    Q_EMIT labelChanged();
}

// la fenetre native existe des winId() : le coeur Rust peut s'en servir
void WinCtl::declare()
{
    if (m_win && !m_label.isEmpty())
        ilot_register(m_label.toUtf8().constData(), intptr_t(m_win->winId()));
}

void WinCtl::setTopBand(qreal h)
{
    if (qFuzzyCompare(h + 1, m_topBand + 1))
        return;
    m_topBand = h;
    if (h > 0)
        m_topTimer.start();
    else {
        m_topTimer.stop();
        if (m_topHover) {
            m_topHover = false;
            Q_EMIT topHoverChanged();
        }
    }
    Q_EMIT topBandChanged();
}

void WinCtl::setHit(const QVariantList &rects)
{
    if (!m_win)
        return;
    QRegion r;
    for (const QVariant &v : rects) {
        const QVariantMap m = v.toMap();
        QRectF f(m.value("x").toReal(), m.value("y").toReal(), m.value("w").toReal(), m.value("h").toReal());
        if (f.width() > 0 && f.height() > 0)
            r += f.toAlignedRect();
    }
    // une region vide voudrait dire « pas de masque » (toute la fenetre) :
    // un pixel hors de la fenetre ne laisse rien
    if (r.isEmpty())
        r = QRegion(-2, -2, 1, 1);
    if (r == m_mask)
        return;
    m_mask = r;
    m_win->setMask(r);
}

// Windows ne laisse prendre le premier plan qu'a l'appli qui a recu la
// derniere saisie : sinon, un appui (vide) sur Alt l'autorise, comme le fait
// Tauri (tao)
static void forceForeground(HWND h)
{
    if (GetForegroundWindow() == h)
        return;
    if (SetForegroundWindow(h))
        return;
    INPUT in[2] = {};
    in[0].type = INPUT_KEYBOARD;
    in[0].ki.wVk = VK_MENU;
    in[1] = in[0];
    in[1].ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(2, in, sizeof(INPUT));
    SetForegroundWindow(h);
}

void WinCtl::grabFocus()
{
    if (!m_win)
        return;
    forceForeground(HWND(m_win->winId()));
    m_win->requestActivate();
}

void WinCtl::releaseFocus()
{
    if (!m_win)
        return;
    char *r = ilot_invoke(m_label.toUtf8().constData(), "release_focus", "{}");
    ilot_free(r);
}

void WinCtl::pollTop()
{
    if (!m_win || !m_win->isVisible())
        return;
    const QPoint p = QCursor::pos();
    const QRect g = m_win->geometry();
    bool on = p.x() >= g.left() && p.x() <= g.right() && p.y() >= g.top() && p.y() <= g.top() + m_topBand;
    if (on != m_topHover) {
        m_topHover = on;
        Q_EMIT topHoverChanged();
    }
}

// Meme regle que l'ilot Tauri : fenetre au premier plan couvrant tout
// l'ecran de la fenetre, sans etre simplement maximisee.
void WinCtl::checkFullscreen()
{
    if (!m_win)
        return;
    HWND own = HWND(m_win->winId());
    HWND fg = GetForegroundWindow();
    bool fs = false;
    if (fg && fg != own && !IsZoomed(fg)) {
        wchar_t cls[64] = {};
        GetClassNameW(fg, cls, 64);
        bool shell = !wcscmp(cls, L"Progman") || !wcscmp(cls, L"WorkerW") || !wcscmp(cls, L"Shell_TrayWnd");
        HMONITOR mon = MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST);
        RECT r;
        MONITORINFO mi{sizeof(mi)};
        if (!shell && mon == MonitorFromWindow(own, MONITOR_DEFAULTTONEAREST) && GetWindowRect(fg, &r)
            && GetMonitorInfoW(mon, &mi)) {
            const RECT &m = mi.rcMonitor;
            fs = r.left <= m.left && r.top <= m.top && r.right >= m.right && r.bottom >= m.bottom;
        }
    }
    if (fs == m_fullscreen)
        return;
    m_fullscreen = fs;
    if (fs) {
        m_hideTimer.start();
        m_topTimer.stop();
        if (m_topHover) {
            m_topHover = false;
            Q_EMIT topHoverChanged();
        }
    } else {
        m_hideTimer.stop();
        m_win->show();
        if (m_topBand > 0)
            m_topTimer.start();
    }
    Q_EMIT fullscreenChanged();
}
