pragma Singleton
import QtQuick

// Palette Material You par defaut de l'ilot (style.css, :root)
// (« ink » = les couleurs on-* : un nom en on + majuscule serait pris pour un
// gestionnaire de signal)
QtObject {
    readonly property color primary: "#cfbdfe"
    readonly property color inkPrimary: "#36265d"
    readonly property color primaryContainer: "#4d3d75"
    readonly property color inkPrimaryContainer: "#e9ddff"
    readonly property color secondaryContainer: "#4a4458"
    readonly property color tertiary: "#efb8c8"
    readonly property color surface: "#141218"
    readonly property color surfaceLow: "#1d1b20"
    readonly property color surfaceC: "#211f26"
    readonly property color surfaceHigh: "#2b2930"
    readonly property color surfaceHighest: "#36343b"
    readonly property color ink: "#e6e0e9"
    readonly property color inkVariant: "#cac4d0"
    readonly property color outlineVariant: "#49454f"

    readonly property var locale: Qt.locale("fr_FR")

    readonly property string font: "Segoe UI Variable Text"
    // icones : police systeme de Windows 11
    readonly property string icons: "Segoe Fluent Icons"

    // courbes de style.css
    readonly property var spring: [0.34, 1.36, 0.5, 1, 1, 1]
    readonly property var emph: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var std: [0.2, 0, 0, 1, 1, 1]

    function time(s) {
        s = Math.max(0, Math.floor(s))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
}
