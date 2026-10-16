#include "island.h"

#include <QQuickWindow>
#include <QRegion>
#include <windows.h>

Island::Island(QObject *parent) : QObject(parent)
{
    // meme frequence que l'ilot Tauri ; GetForegroundWindow et GetWindowRect
    // ne coutent presque rien
    m_fsTimer.setInterval(500);
    connect(&m_fsTimer, &QTimer::timeout, this, &Island::checkFullscreen);
}

void Island::attach(QQuickWindow *win)
{
    m_win = win;
    m_fsTimer.start();
}

void Island::setHit(const QRectF &r)
{
    if (!m_win)
        return;
    // pixels logiques : Qt les convertit pour la fenetre Windows
    QRect hit = r.toAlignedRect();
    if (hit == m_hit)
        return;
    m_hit = hit;
    m_win->setMask(QRegion(hit));
}

// Meme regle que fullscreen_foreground (main.rs) : fenetre au premier plan
// couvrant tout l'ecran de l'ilot, sans etre simplement maximisee.
void Island::checkFullscreen()
{
    if (!m_win)
        return;
    HWND own = reinterpret_cast<HWND>(m_win->winId());
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
    if (fs != m_fullscreen) {
        m_fullscreen = fs;
        Q_EMIT fullscreenChanged();
    }
}
