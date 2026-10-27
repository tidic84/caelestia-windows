#include "winctl.h"
#include "backdrop.h"
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
    // mode "auto" : suit la souris pendant que la fenetre est masquee
    m_peekTimer.setInterval(50);
    connect(&m_peekTimer, &QTimer::timeout, this, &WinCtl::pollPeek);
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

void WinCtl::setFsMode(const QString &m)
{
    if (m == m_fsMode)
        return;
    m_fsMode = m;
    // apres la liaison QML en cours (fullscreenChanged y relancerait du QML)
    QTimer::singleShot(0, this, &WinCtl::checkFullscreen);
    Q_EMIT fsModeChanged();
}

void WinCtl::setFsApps(const QStringList &l)
{
    if (l == m_fsApps)
        return;
    m_fsApps = l;
    QTimer::singleShot(0, this, &WinCtl::checkFullscreen);
    Q_EMIT fsAppsChanged();
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

void WinCtl::setBackdrop(const QVariantList &shapes)
{
    if (!m_win || shapes == m_shapes)
        return;
    m_shapes = shapes;
    if (shapes.isEmpty()) {
        if (m_backdrop)
            m_backdrop->hide();
        return;
    }
    if (!m_backdrop)
        m_backdrop = std::make_unique<Backdrop>();
    m_backdrop->setShapes(reinterpret_cast<void *>(m_win->winId()), shapes, m_win->devicePixelRatio());
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

// Nom de l'executable d'un processus, en minuscules (« rocketleague.exe »)
static QString exeOf(DWORD pid)
{
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!p)
        return {};
    wchar_t buf[1024];
    DWORD n = DWORD(sizeof(buf) / sizeof(buf[0]));
    QString name;
    if (QueryFullProcessImageNameW(p, 0, buf, &n))
        name = QString::fromWCharArray(buf, int(n)).section(QLatin1Char('\\'), -1).toLower();
    CloseHandle(p);
    return name;
}

// Meme regle que l'ilot Tauri : fenetre au premier plan couvrant tout
// l'ecran de la fenetre, sans etre simplement maximisee. fsMode decide
// ensuite si la fenetre se masque.
void WinCtl::checkFullscreen()
{
    if (!m_win)
        return;
    HWND own = HWND(m_win->winId());
    // la fenetre a pu bouger, ou passer devant le flou
    if (m_backdrop)
        m_backdrop->place(own, m_win->isVisible());
    HWND fg = GetForegroundWindow();
    bool fs = false, zoomed = false;
    if (fg && fg != own) {
        wchar_t cls[64] = {};
        GetClassNameW(fg, cls, 64);
        bool shell = !wcscmp(cls, L"Progman") || !wcscmp(cls, L"WorkerW") || !wcscmp(cls, L"Shell_TrayWnd");
        HMONITOR mon = MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST);
        if (!shell && mon == MonitorFromWindow(own, MONITOR_DEFAULTTONEAREST)) {
            zoomed = IsZoomed(fg) != FALSE;
            RECT r;
            MONITORINFO mi{sizeof(mi)};
            if (!zoomed && GetWindowRect(fg, &r) && GetMonitorInfoW(mon, &mi)) {
                const RECT &m = mi.rcMonitor;
                fs = r.left <= m.left && r.top <= m.top && r.right >= m.right && r.bottom >= m.bottom;
            }
        }
    }
    const bool custom = m_fsMode == QLatin1String("custom");
    // executable : en plein ecran (Reglages > Jeu et absence le propose), et pour
    // une fenetre maximisee en mode "custom" (jeux en fenetre sans bordure)
    QString exe;
    if (fs || (zoomed && custom)) {
        DWORD pid = 0;
        GetWindowThreadProcessId(fg, &pid);
        if (pid != m_fgPid) {
            m_fgPid = pid;
            m_fgExe = exeOf(pid);
        }
        exe = m_fgExe;
    }
    if (fs && !exe.isEmpty() && exe != m_fsExe) {
        m_fsExe = exe;
        Q_EMIT fsExeChanged();
    }
    bool hide = fs;
    if (m_fsMode == QLatin1String("show"))
        hide = false;
    else if (custom)
        hide = (fs || zoomed) && !exe.isEmpty() && m_fsApps.contains(exe);
    // une fenetre agrandie choisie en mode "custom" compte aussi
    if ((fs || hide) != m_covered) {
        m_covered = fs || hide;
        Q_EMIT coveredChanged();
    }
    m_hideWanted = hide;
    if (hide && m_fsMode == QLatin1String("auto")) {
        if (!m_peekTimer.isActive())
            m_peekTimer.start();
    } else {
        m_peekTimer.stop();
        m_peek = false;
        m_peekOut = 0;
    }
    setHidden(hide && !m_peek);
}

void WinCtl::setHidden(bool fs)
{
    if (fs == m_fullscreen)
        return;
    m_fullscreen = fs;
    HWND own = HWND(m_win->winId());
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
        if (m_backdrop)
            m_backdrop->place(own, true);
        if (m_topBand > 0)
            m_topTimer.start();
    }
    Q_EMIT fullscreenChanged();
}

// Mode "auto" : la fenetre est masquee devant l'appli en plein ecran. La
// souris tout en haut de l'ecran, vers le milieu (au-dessus de l'ilot), la
// fait revenir ; elle reste tant que la souris est sur l'ilot ou le panneau,
// puis se masque de nouveau 0,6 s apres son depart.
void WinCtl::pollPeek()
{
    if (!m_win || !m_hideWanted)
        return;
    const QPoint p = QCursor::pos();
    const QRect g = m_win->geometry();
    const bool top = p.y() >= g.top() && p.y() <= g.top() + 1 && p.x() >= g.left() + g.width() / 3 && p.x() <= g.right() - g.width() / 3;
    bool in = top;
    if (m_peek && !in)
        in = m_mask.boundingRect().translated(g.topLeft()).adjusted(-24, 0, 24, 24).contains(p);
    if (in)
        m_peekOut = 0;
    else if (m_peek && ++m_peekOut < 12)
        in = true;
    if (in == m_peek)
        return;
    m_peek = in;
    m_peekOut = 0;
    setHidden(!in);
}
