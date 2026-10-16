#pragma once

#include <QObject>
#include <QRectF>
#include <QTimer>

class QQuickWindow;

// Fenetre de l'ilot : seule la zone de l'ilot recoit la souris (masque de
// fenetre, les clics passent ailleurs), et elle se cache quand une appli est
// en plein ecran sur son ecran. Pas de sondage du curseur : c'est Windows
// qui route la souris vers la zone du masque.
class Island : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool fullscreen READ fullscreen NOTIFY fullscreenChanged)

public:
    explicit Island(QObject *parent = nullptr);
    void attach(QQuickWindow *win);
    bool fullscreen() const { return m_fullscreen; }

    // zone interactive, en pixels logiques de la fenetre
    Q_INVOKABLE void setHit(const QRectF &r);

Q_SIGNALS:
    void fullscreenChanged();

private:
    void checkFullscreen();

    QQuickWindow *m_win = nullptr;
    QTimer m_fsTimer;
    QRect m_hit;
    bool m_fullscreen = false;
};
