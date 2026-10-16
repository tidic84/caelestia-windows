#pragma once

#include <QImage>
#include <QMutex>
#include <QObject>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <thread>

// Zone de notification de la barre (applications en arriere-plan) : une
// fenetre invisible de classe `Shell_TrayWnd`, placee devant celle de
// l'Explorateur, recoit les `Shell_NotifyIcon` des applis (WM_COPYDATA),
// comme le font les shells de remplacement. Chaque message est aussi
// transmis a l'Explorateur, qui garde ses icones et ses notifications ; les
// messages AppBar et le reste lui sont simplement relayes. La fenetre vit
// sur son propre thread : une interface occupee ne bloque pas les applis.
class Tray : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // [{id, tip, rev}] dans l'ordre d'arrivee, sans les icones masquees
    Q_PROPERTY(QVariantList icons READ icons NOTIFY iconsChanged)

public:
    explicit Tray(QObject *parent = nullptr);
    ~Tray() override;
    static Tray *instance();
    static Tray *create(QQmlEngine *, QJSEngine *);
    // hote actif seulement avec la barre
    void setEnabled(bool on);

    QVariantList icons() const { return m_list; }
    QImage image(int id) const;

    // button : "left", "right", "double", "hover" ; envoye a l'appli comme un
    // clic sur son icone (position : celle de la souris)
    Q_INVOKABLE void click(int id, const QString &button);

Q_SIGNALS:
    void iconsChanged();

private:
    struct Icon
    {
        int id = 0;
        QString key;
        quintptr hwnd = 0;
        quint32 uid = 0;
        quint32 msg = 0;
        quint32 version = 0;
        quint32 flags = 0;
        QString tip;
        QImage img;
        bool hidden = false;
        int rev = 0;
        long rect[4] = {0, 0, 0, 0};
    };

    void run();
    void stop();
    void broadcast();
    void changed();
    void refresh();
    qintptr notify(const void *data, quint32 size);
    qintptr iconRect(const void *data, quint32 size);
    void *explorerTray() const;
    void prune();
    static intptr_t __stdcall wndProc(void *h, unsigned msg, uintptr_t wp, intptr_t lp);

    mutable QMutex m_mutex;
    QList<Icon> m_icons;
    int m_nextId = 1;
    bool m_pending = false;
    QVariantList m_list;
    std::thread m_thread;
    void *m_wnd = nullptr;
    unsigned m_threadId = 0;
    quint64 m_broadcastAt = 0;
};

// image://tray/<id>-<rev>
class TrayImages : public QQuickImageProvider
{
public:
    TrayImages() : QQuickImageProvider(QQuickImageProvider::Image) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override;
};
