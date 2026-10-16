#pragma once

#include <QImage>
#include <QMutex>
#include <QObject>
#include <QQuickImageProvider>

#include <condition_variable>
#include <mutex>
#include <thread>

// Lecteur multimedia via GSMTC, comme media.rs : un thread COM ecoute les
// evenements de la session courante et publie l'etat dans le thread Qt.
class Media : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool has READ has NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString artist READ artist NOTIFY changed)
    Q_PROPERTY(QString album READ album NOTIFY changed)
    Q_PROPERTY(QString app READ app NOTIFY changed)
    Q_PROPERTY(bool playing READ playing NOTIFY changed)
    // secondes, au moment de `stamp` (ms depuis l'epoque) : QML extrapole
    Q_PROPERTY(double position READ position NOTIFY changed)
    Q_PROPERTY(double stamp READ stamp NOTIFY changed)
    Q_PROPERTY(double duration READ duration NOTIFY changed)
    // change a chaque pochette : image://art/<artSerial>
    Q_PROPERTY(int artSerial READ artSerial NOTIFY artChanged)
    Q_PROPERTY(bool hasArt READ hasArt NOTIFY artChanged)

public:
    explicit Media(QObject *parent = nullptr);
    ~Media() override;

    bool has() const { return m_has; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString album() const { return m_album; }
    QString app() const { return m_app; }
    bool playing() const { return m_playing; }
    double position() const { return m_position; }
    double stamp() const { return m_stamp; }
    double duration() const { return m_duration; }
    int artSerial() const { return m_artSerial; }
    bool hasArt() const { return m_hasArt; }
    QImage art() const;

    Q_INVOKABLE void action(const QString &what);

Q_SIGNALS:
    void changed();
    void artChanged();

private:
    void run();
    void wake();

    bool m_has = false, m_playing = false;
    QString m_title, m_artist, m_album, m_app;
    double m_position = 0, m_stamp = 0, m_duration = 0;
    int m_artSerial = 0;
    bool m_hasArt = false;
    mutable QMutex m_artLock;
    QImage m_art;

    std::thread m_thread;
    std::mutex m_lock;
    std::condition_variable m_cv;
    int m_events = 0;
    QString m_pending; // action demandee par l'interface
    bool m_quit = false;
};

class ArtProvider : public QQuickImageProvider
{
public:
    explicit ArtProvider(Media *m) : QQuickImageProvider(QQuickImageProvider::Image), m_media(m) {}
    QImage requestImage(const QString &, QSize *size, const QSize &) override
    {
        QImage img = m_media->art();
        if (size)
            *size = img.size();
        return img;
    }

private:
    Media *m_media;
};
