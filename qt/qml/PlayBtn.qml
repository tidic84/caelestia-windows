import QtQuick
import QtQuick.Effects

// Bouton lecture / pause du lecteur : forme « cookie » festonnee (5 bosses
// en pause, 9 festons qui tournent en lecture), disque ou icone seule, selon
// Reglages > Apparence > Lecteur. Couleur du lecteur (Ilot.playerPal), blanche
// ou fixe (player_btn_color).
Btn {
    id: pb
    property real size: 40
    // onglet Media (maquette) : blanc, icone noire, lueur de la couleur du lecteur.
    // C'est le choix « auto » de player_btn_color ; les autres choix l'ignorent.
    property bool white: false
    readonly property string shape: Ilot.cfg.player_btn || "cookie"
    readonly property bool cookie: shape === "cookie"
    // "none" : pas de fond, icone seule plus grande, de la couleur du bouton
    readonly property bool bare: shape === "none"
    readonly property bool playing: Ilot.media.playing
    // couleur : "auto" | "player" | "white" | "#rrggbb"
    readonly property string colorMode: Ilot.cfg.player_btn_color || "auto"
    readonly property bool fixed: /^#[0-9a-fA-F]{6}$/.test(colorMode)
    readonly property bool fillWhite: colorMode === "white" || (colorMode === "auto" && white)
        || (fixed && colorMode.toLowerCase() === "#ffffff")
    readonly property color fill: fillWhite ? "#ffffff" : fixed ? colorMode : Ilot.playerPal.primary
    // survol : 88 % de la couleur + blanc ; le blanc fonce un peu
    readonly property color fillHover: hovered ? (fillWhite ? "#ececec" : Theme.lift(fill)) : fill
    // icone : "auto" | "white" | "black" ; en auto, noire sur blanc, encre du
    // lecteur sur sa couleur, noire ou blanche selon la luminance sinon
    readonly property string inkMode: Ilot.cfg.player_btn_ink || "auto"
    readonly property color ink: inkMode === "white" ? "#ffffff" : inkMode === "black" ? "#000000"
        : fillWhite ? "#000000"
        : fixed ? (0.299 * fill.r + 0.587 * fill.g + 0.114 * fill.b > 0.6 ? "#000000" : "#ffffff")
        : Ilot.playerPal.ink
    width: size
    height: size
    tip: playing ? "Pause" : "Lecture"
    scale: pressed ? 0.88 : 1
    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    onClicked: Ilot.mediaAction("toggle")
    onMiddleClicked: Ilot.mediaAction("toggle")

    // lueur sous le bouton blanc (presque rond : une ombre ronde suffit)
    RectangularShadow {
        visible: pb.fillWhite && !pb.bare && Ilot.cfg.player_btn_glow !== false
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
        visible: !pb.bare
        fragmentShader: "qrc:/shaders/cookie.frag.qsb"
        readonly property color c: pb.fillHover
        property size size: Qt.size(Math.max(1, width), Math.max(1, height))
        // sans morphose, reste en forme pause (5 bosses)
        property real m: pb.playing && Ilot.cfg.player_btn_morph !== false ? 1 : 0
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
            // sans morphose la forme garde 5 bosses (72°) : le retour a 0° se
            // verrait, donc pas de rotation
            running: pb.cookie && pb.playing && pb.visible && !Theme.reduced
                && Ilot.cfg.player_btn_spin !== false && Ilot.cfg.player_btn_morph !== false
        }
    }
    Ms {
        id: glyph
        anchors.centerIn: parent
        name: pb.playing ? "pause" : "play_arrow"
        size: Math.round(pb.size * (pb.bare ? 0.72 : 0.5))
        // icone seule blanche hors de l'onglet Media en theme clair : illisible,
        // on prend l'encre du theme
        color: !pb.bare ? pb.ink : pb.fillWhite && Theme.light && !pb.white ? Theme.ink : pb.fillHover
    }
    // le glyphe saute a chaque changement (lecture <-> pause)
    onPlayingChanged: if (!Theme.reduced && Ilot.cfg.player_btn_pop !== false) pop.restart()
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
