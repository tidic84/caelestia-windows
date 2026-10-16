#include "sysmon.h"

#include <windows.h>

static unsigned long long ft(const FILETIME &f)
{
    return (static_cast<unsigned long long>(f.dwHighDateTime) << 32) | f.dwLowDateTime;
}

SysMon::SysMon(QObject *parent) : QObject(parent)
{
    m_timer.setInterval(2000);
    connect(&m_timer, &QTimer::timeout, this, &SysMon::refresh);
    m_timer.start();
    refresh();
}

void SysMon::refresh()
{
    FILETIME idle, kernel, user;
    if (GetSystemTimes(&idle, &kernel, &user)) {
        unsigned long long i = ft(idle), t = ft(kernel) + ft(user);
        if (m_total && t > m_total)
            m_cpu = 100.0 * (1.0 - double(i - m_idle) / double(t - m_total));
        m_idle = i;
        m_total = t;
    }
    MEMORYSTATUSEX ms{sizeof(ms)};
    if (GlobalMemoryStatusEx(&ms)) {
        m_memTotal = double(ms.ullTotalPhys);
        m_memUsed = double(ms.ullTotalPhys - ms.ullAvailPhys);
    }
    ULARGE_INTEGER avail, total;
    if (GetDiskFreeSpaceExW(L"C:\\", &avail, &total, nullptr)) {
        m_diskTotal = double(total.QuadPart);
        m_diskUsed = double(total.QuadPart - avail.QuadPart);
    }
    m_uptime = double(GetTickCount64()) / 1000.0;
    Q_EMIT changed();
}
