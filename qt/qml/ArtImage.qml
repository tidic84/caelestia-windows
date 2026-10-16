import QtQuick

// Pochette du titre en cours (fondu a l'apparition)
RoundImage {
    source: Ilot.hasMedia ? Ilot.art : ""
    fade: true
}
