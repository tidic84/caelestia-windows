import QtQuick
import Ilot

// Barre d'un ecran sans ilot (une fenetre par ecran, creee par Shell) : les
// memes modules que la barre de l'ilot, dont les boutons ouvrent l'ilot sur
// son ecran. L'heure prend la place de l'ilot.
Window {
    id: w
    property string label: "bar"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.NoDropShadowWindowHint
    color: "transparent"
    title: "Ilot"
    visible: false

    // barre affichee (masquage automatique) et souris dans la bande du haut
    property bool peek: false
    property bool atTop: false
    readonly property bool autohide: !!Ilot.cfg.bar_autohide
    onAutohideChanged: if (!autohide) peek = false

    WinCtl {
        id: ctl
        window: w
        label: w.label
        topBand: w.autohide && !fullscreen ? (w.peek ? Ilot.barH + 8 : 2) : 0
        onTopHoverChanged: {
            w.atTop = topHover
            if (topHover) {
                hideTimer.stop()
                w.peek = true
            } else {
                w.hideLater()
            }
        }
    }
    Timer {
        id: hideTimer
        interval: 500
        onTriggered: if (!w.atTop && !bar.previewOpen) w.peek = false
    }
    function hideLater() {
        hideTimer.stop()
        if (peek)
            hideTimer.start()
    }

    BarContent {
        id: bar
        width: parent.width
        label: w.label
        hasIsland: false
        shown: !ctl.fullscreen && (!w.autohide || w.peek)
        onLayoutChanged: Qt.callLater(w.updateHit)
        onPreviewOpenChanged: if (!previewOpen && !w.atTop) w.hideLater()
    }

    function updateHit() {
        ctl.setHit(bar.hitRects())
    }
    onWidthChanged: Qt.callLater(updateHit)
    Component.onCompleted: Qt.callLater(updateHit)
}
