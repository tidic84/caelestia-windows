import QtQuick

// .slider : piste pleine jusqu'a la valeur, curseur vertical (Material 3)
Item {
    id: sl
    property real from: 0
    property real to: 100
    property real value: 0
    // part pleine affichee (0..1) : 0 quand le son est coupe
    property real fill: (value - from) / Math.max(1e-9, to - from)
    property real trackH: 14
    property real thumbH: 24
    property color ringColor: Theme.surfaceC
    // couleurs de la piste et de la partie pleine (curseur blanc du lecteur)
    property color accent: Theme.primary
    property color trackColor: Theme.surfaceHighest
    property bool disabled: false
    // pas de la molette (0 : la molette passe au parent)
    property real wheelStep: 0
    readonly property bool dragging: ma.pressed
    // pendant le glisser (input) puis au relachement (change)
    signal moved(real value)
    signal released(real value)
    implicitHeight: Math.max(18, thumbH)
    opacity: disabled ? 0.4 : 1

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: sl.trackH
        radius: height / 2
        color: sl.trackColor
        Rectangle {
            width: Math.max(0, Math.min(1, sl.fill)) * parent.width
            height: parent.height
            radius: parent.radius
            color: sl.accent
            // pas d'arrondi a droite de la partie pleine
            Rectangle {
                visible: parent.width > parent.radius && parent.width < sl.width - parent.radius
                anchors.right: parent.right
                width: Math.min(parent.radius, parent.width)
                height: parent.height
                color: sl.accent
            }
        }
    }
    // anneau de la couleur du fond autour du curseur (box-shadow 0 0 0 3px)
    Rectangle {
        width: 10
        height: sl.thumbH + 6
        radius: 5
        color: sl.ringColor
        x: Math.max(0, Math.min(1, (sl.value - sl.from) / Math.max(1e-9, sl.to - sl.from))) * (sl.width - 4) - 3
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            anchors.centerIn: parent
            width: 4
            height: sl.thumbH
            radius: 2
            color: sl.accent
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.topMargin: -3
        anchors.bottomMargin: -3
        enabled: !sl.disabled
        cursorShape: sl.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        preventStealing: true
        function at(x) {
            const f = Math.max(0, Math.min(1, x / sl.width))
            return Math.round(sl.from + f * (sl.to - sl.from))
        }
        onPressed: m => {
            sl.value = at(m.x)
            sl.moved(sl.value)
        }
        onPositionChanged: m => {
            if (!pressed)
                return
            const v = at(m.x)
            if (v !== sl.value) {
                sl.value = v
                sl.moved(v)
            }
        }
        onReleased: sl.released(sl.value)
        onWheel: w => {
            if (sl.wheelStep <= 0) {
                w.accepted = false
                return
            }
            const v = Math.max(sl.from, Math.min(sl.to, sl.value + Math.sign(w.angleDelta.y) * sl.wheelStep))
            sl.value = v
            sl.moved(v)
            sl.released(v)
        }
    }
}
