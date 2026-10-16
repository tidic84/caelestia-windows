import QtQuick

// .icon-btn : rond 36 px, plein (couleur primaire) ou petit (26 px)
Btn {
    id: b
    property alias icon: ms.name
    // .icon-btn.small garde des icones de 20 px (la taille de .ms l'emporte)
    property real iconSize: big ? 26 : 20
    property bool filled: false
    property bool small: false
    property bool big: false
    // .on (outils du panneau) et .armed (second clic pour confirmer)
    property bool on: false
    property bool armed: false
    property color fg: filled ? Theme.inkPrimary : on ? Theme.inkSecondaryContainer : armed ? Theme.inkError : Theme.ink
    width: small ? 26 : big ? 46 : 36
    height: small ? 26 : big ? 46 : 36
    radius: filled ? (hovered ? 18 : 12) : (on || armed) ? 12 : height / 2
    color: filled ? (hovered ? Theme.lift(Theme.primary) : Theme.primary)
        : armed ? Theme.error
        : on ? Theme.secondaryContainer
        : hovered ? Theme.alpha(Theme.ink, 0.1) : "transparent"
    Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    scale: pressed ? 0.9 : 1
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }

    Ms {
        id: ms
        anchors.centerIn: parent
        size: b.iconSize
        color: b.fg
    }
}
