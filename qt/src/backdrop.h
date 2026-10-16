#pragma once

#include <QVariantList>

#include <memory>

// Flou de ce qu'il y a derriere une fenetre, dessine par Windows (moteur de
// composition, pinceau « host backdrop » de l'acrylique) dans une fenetre
// native juste sous elle, decoupe a la forme demandee.
class Backdrop
{
public:
    Backdrop();
    ~Backdrop();

    // formes {kind, x, y, w, h, r} en pixels logiques de `owner` (k : pixels
    // physiques par pixel logique) ; voir WinCtl::setBackdrop
    void setShapes(void *owner, const QVariantList &shapes, qreal k);
    // suit la position de `owner` et reste juste sous elle
    void place(void *owner, bool visible);
    void hide();

private:
    struct Impl;
    std::unique_ptr<Impl> d;
};
