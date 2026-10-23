import QtQuick
import QtQuick.Effects

// Bouton lecture / pause du lecteur : forme « cookie » festonnee (5 bosses
// en pause, 9 festons qui tournent en lecture) ou disque, selon Reglages >
// Apparence > Lecteur. Couleur du lecteur (Ilot.playerPal).
Btn {
    id: pb
    property real size: 40
    // onglet Media (maquette) : blanc, icone noire, lueur de la couleur du lecteur
    property bool white: false
    readonly property bool cookie: (Ilot.cfg.player_btn || "cookie") === "cookie"
    readonly property bool playing: Ilot.media.playing
    width: size
    height: size
    tip: playing ? "Pause" : "Lecture"
    scale: pressed ? 0.88 : 1
    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    onClicked: Ilot.mediaAction("toggle")
    onMiddleClicked: Ilot.mediaAction("toggle")

    // lueur sous le bouton blanc (presque rond : une ombre ronde suffit)
    RectangularShadow {
        visible: pb.white
        anchors.fill: parent
        anchors.margins: pb.size * 0.06
        radius: width / 2
        offset.y: 4
        blur: 14
        spread: 0
        color: Theme.alpha(Ilot.playerPal.primary, 0.7)
    }
    ShaderEffect {
        anchors.fill: parent
        fragmentShader: "qrc:/shaders/cookie.frag.qsb"
        readonly property color base: pb.white ? "#ffffff" : Ilot.playerPal.primary
        // survol : 88 % de la couleur + blanc (Theme.lift recoit "#ffffff" en
        // chaine et rend une couleur transparente)
        readonly property color c: pb.hovered ? (pb.white ? "#ececec" : Theme.mix(base, Qt.rgba(1, 1, 1, 1), 0.88)) : base
        property size size: Qt.size(Math.max(1, width), Math.max(1, height))
        property real m: pb.playing ? 1 : 0
        Behavior on m { NumberAnimation { duration: 450; easing.type: Easing.OutBack } }
        property real cookie: pb.cookie ? 1 : 0
        Behavior on cookie { NumberAnimation { duration: 300 } }
        property vector4d fill: Qt.vector4d(c.r * c.a, c.g * c.a, c.b * c.a, c.a)
        // rotation sur le thread de rendu, seulement quand elle se voit
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 14400
            loops: Animation.Infinite
            // a la reprise, repart de 0° : invisible, la forme a 9 festons se
            // repete tous les 40° (un Animator ne se met pas en pause proprement)
            running: pb.cookie && pb.playing && pb.visible && !Theme.reduced
        }
    }
    Ms {
        id: glyph
        anchors.centerIn: parent
        name: pb.playing ? "pause" : "play_arrow"
        size: Math.round(pb.size * 0.5)
        color: pb.white ? "#000000" : Ilot.playerPal.ink
    }
    // le glyphe saute a chaque changement (lecture <-> pause)
    onPlayingChanged: if (!Theme.reduced) pop.restart()
    NumberAnimation {
        id: pop
        target: glyph
        property: "scale"
        from: 0.55
        to: 1
        duration: 480
        easing.type: Easing.OutBack
    }
}
