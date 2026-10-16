#pragma once

#include <QObject>
#include <QTimer>

// CPU, memoire et disque C:, releves toutes les 2 s comme system.rs
class SysMon : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double cpu READ cpu NOTIFY changed)
    Q_PROPERTY(double memUsed READ memUsed NOTIFY changed)
    Q_PROPERTY(double memTotal READ memTotal NOTIFY changed)
    Q_PROPERTY(double diskUsed READ diskUsed NOTIFY changed)
    Q_PROPERTY(double diskTotal READ diskTotal NOTIFY changed)
    Q_PROPERTY(double uptime READ uptime NOTIFY changed)

public:
    explicit SysMon(QObject *parent = nullptr);
    double cpu() const { return m_cpu; }
    double memUsed() const { return m_memUsed; }
    double memTotal() const { return m_memTotal; }
    double diskUsed() const { return m_diskUsed; }
    double diskTotal() const { return m_diskTotal; }
    double uptime() const { return m_uptime; }

Q_SIGNALS:
    void changed();

private:
    void refresh();

    QTimer m_timer;
    unsigned long long m_idle = 0, m_total = 0;
    double m_cpu = 0, m_memUsed = 0, m_memTotal = 0, m_diskUsed = 0, m_diskTotal = 0, m_uptime = 0;
};
