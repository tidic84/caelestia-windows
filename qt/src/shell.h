#pragma once

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QQmlApplicationEngine>
#include <QQuickWindow>

// Fenetres de l'application : l'ilot (Main.qml) sur l'ecran choisi, une
// barre (Bar.qml) sur chacun des autres ecrans, l'icone de la zone de
// notification et le raccourci Ctrl+Alt+Espace.
class Shell : public QObject
{
    Q_OBJECT

public:
    explicit Shell(QObject *parent = nullptr);
    ~Shell() override;
    bool start();

private:
    void place();
    void syncBars();
    void placeBar(QQuickWindow *w, QScreen *s);
    QScreen *screenNamed(const QString &name) const;
    QJsonObject nativeScreen(const QString &name) const;
    void reserve(const QString &label, QScreen *s, bool on);
    void createTray();
    void trayMenu();
    void restart();
    void shot();
    static intptr_t __stdcall wndProc(void *h, unsigned msg, uintptr_t wp, intptr_t lp);

    QQmlApplicationEngine m_engine;
    QPointer<QQuickWindow> m_island;
    QHash<QString, QPointer<QQuickWindow>> m_bars;
    QJsonObject m_cfg;
    qreal m_winW = 800, m_winH = 600;
    void *m_msgWnd = nullptr;
    bool m_placing = false;
};
