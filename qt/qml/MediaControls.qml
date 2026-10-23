import QtQuick

// Precedent, lecture / pause, suivant (.controls ; .controls.big sur l'onglet
// Media). Boutons grises si l'appli ne les accepte pas ; petit recul de
// l'icone au clic.
Row {
    id: mc
    property bool big: false
    // survol de la pilule : plus serre
    property bool compact: false
    spacing: big ? 22 : compact ? 2 : 8
    IconBtn {
        big: mc.big
        width: mc.compact ? 34 : height
        height: mc.compact ? 34 : big ? 44 : 36
        iconSize: mc.big ? 30 : 22
        icon: "skip_previous"
        readonly property bool can: !Ilot.hasMedia || Ilot.media.can_prev !== false
        opacity: can ? 1 : 0.35
        anchors.verticalCenter: parent.verticalCenter
        tip: "Précédent"
        // grise : le clic est pris quand meme (pas d'ouverture du panneau)
        onClicked: if (can) { Ilot.mediaAction("prev"); nudgePrev.restart() }
        onMiddleClicked: Ilot.mediaAction("toggle")
        transform: Translate { id: tp }
        SequentialAnimation {
            id: nudgePrev
            NumberAnimation { target: tp; property: "x"; to: -4; duration: 90 }
            NumberAnimation { target: tp; property: "x"; to: 0; duration: 350; easing.type: Easing.OutBack }
        }
    }
    PlayBtn {
        size: mc.big ? 58 : mc.compact ? 42 : 40
        white: mc.big && Ilot.cfg.player_bigbtn !== "accent"
        anchors.verticalCenter: parent.verticalCenter
    }
    IconBtn {
        big: mc.big
        width: mc.compact ? 34 : height
        height: mc.compact ? 34 : big ? 44 : 36
        iconSize: mc.big ? 30 : 22
        icon: "skip_next"
        readonly property bool can: !Ilot.hasMedia || Ilot.media.can_next !== false
        opacity: can ? 1 : 0.35
        anchors.verticalCenter: parent.verticalCenter
        tip: "Suivant"
        onClicked: if (can) { Ilot.mediaAction("next"); nudgeNext.restart() }
        onMiddleClicked: Ilot.mediaAction("toggle")
        transform: Translate { id: tn }
        SequentialAnimation {
            id: nudgeNext
            NumberAnimation { target: tn; property: "x"; to: 4; duration: 90 }
            NumberAnimation { target: tn; property: "x"; to: 0; duration: 350; easing.type: Easing.OutBack }
        }
    }
}
