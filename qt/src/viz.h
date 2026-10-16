#pragma once

#include <QList>
#include <QObject>

#include <atomic>
#include <thread>

// Visualiseur : capture du son du PC (WASAPI loopback) et 24 bandes 0..1,
// ~30 trames/s, comme audio.rs. Ne tourne que quand `active` est vrai
// (lecture en cours et visualiseur visible). `--sim-viz` remplace la
// capture par des bandes aleatoires (mesures sans son).
class Viz : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QList<qreal> bands READ bands NOTIFY bandsChanged)
    // vrai tant que des trames arrivent (sinon l'interface anime l'egaliseur seule)
    Q_PROPERTY(bool live READ live NOTIFY liveChanged)

public:
    explicit Viz(bool simulate, QObject *parent = nullptr);
    ~Viz() override;

    bool active() const { return m_active; }
    void setActive(bool on);
    QList<qreal> bands() const { return m_bands; }
    bool live() const { return m_live; }

Q_SIGNALS:
    void activeChanged();
    void bandsChanged();
    void liveChanged();

private:
    void run();
    void capture();
    void simulate();
    void publish(const QList<qreal> &b);
    void setLive(bool on);

    bool m_simulate;
    bool m_active = false;
    bool m_live = false;
    QList<qreal> m_bands;
    std::atomic<bool> m_on{false};
    std::thread m_thread;
};
