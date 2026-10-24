import QtQuick

// Barre de progression du lecteur (survol de la pilule, onglet Media,
// accueil) : trait fin qui s'epaissit au survol, partie jouee ondulee pendant
// la lecture (Reglages > Apparence > Lecteur), poignee et bulle de temps au
// survol. Clic : saut ; glisser : apercu, envoi au relachement. La molette
// et le clic molette passent au parent (volume, lecture / pause).
Item {
    id: sb
    // survol de la pilule : plus fine, temps plus petits
    property bool small: false
    // couleur du reste du morceau
    property color restColor: Theme.alpha(Theme.ink, 0.18)
    property color timeColor: Theme.inkVariant
    readonly property real dur: Ilot.media.duration || 0
    readonly property bool canSeek: Ilot.hasMedia && dur > 0 && Ilot.media.can_seek !== false
    readonly property bool dragging: ma.pressed && canSeek
    readonly property bool active: canSeek && (ma.containsMouse || ma.pressed)
    readonly property bool wave: (Ilot.cfg.player_bar || "wave") === "wave" && !Theme.reduced
    property real dragFrac: 0
    // appui en cours sur la barre (seekDrag a rendre au relachement, meme si
    // la piste change entre-temps) et titre au moment de l'appui
    property bool held: false
    property string heldTitle: ""
    property real hoverFrac: 0
    // position affichee : suit Ilot.pos (relu toutes les 500 ms) en douceur,
    // sans animation au relachement d'un glisser
    property bool snap: false
    property real shownFrac: dur ? Math.min(1, Ilot.pos / dur) : 0
    Behavior on shownFrac {
        enabled: !sb.dragging && !sb.snap
        NumberAnimation { duration: 500 }
    }
    readonly property real frac: dragging ? dragFrac : shownFrac
    // Reglages > Lecteur : epaisseur et amplitude de l'onde (1 : par defaut)
    readonly property real thK: ({ thin: 0.7, thick: 1.6 })[Ilot.cfg.player_bar_size] || 1
    readonly property real ampK: ({ low: 0.5, high: 1.7 })[Ilot.cfg.player_bar_amp] || 1
    implicitHeight: 20

    Txt {
        id: tl
        width: sb.small ? 30 : 34
        height: parent.height
        text: sb.dur ? Ilot.fmtTime(sb.dragging ? sb.dragFrac * sb.dur : Ilot.pos) : ""
        px: sb.small ? 10 : 11
        weight: Font.Medium
        tnum: true
        color: sb.timeColor
    }
    Txt {
        id: tr
        anchors.right: parent.right
        width: sb.small ? 34 : 38
        height: parent.height
        horizontalAlignment: Text.AlignRight
        text: !Ilot.hasMedia ? "" : sb.dur ? "-" + Ilot.fmtTime(sb.dur - (sb.dragging ? sb.dragFrac * sb.dur : Ilot.pos)) : "Direct"
        px: sb.small ? 10 : 11
        weight: Font.Medium
        tnum: true
        color: sb.timeColor
    }

    Item {
        id: track
        anchors.left: tl.right
        anchors.right: tr.left
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        height: parent.height
        opacity: sb.canSeek || !Ilot.hasMedia ? 1 : 0.45

        // epaisseur, ondulation et poignee : animees au survol
        property real th: (sb.active ? (sb.small ? 5.5 : 7) : (sb.small ? 3 : 4)) * sb.thK
        Behavior on th { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        property real amp: sb.wave && Ilot.media.playing && sb.dur > 0 ? (sb.active ? 2.4 : 1.6) * (sb.small ? 0.8 : 1) * sb.ampK : 0
        Behavior on amp { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        property real handleK: sb.active ? 1 : 0
        Behavior on handleK { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        ShaderEffect {
            id: line
            anchors.fill: parent
            // trait epais + forte onde : deborde verticalement au lieu d'etre
            // rogne (0 avec les reglages par defaut ; le milieu ne bouge pas)
            readonly property real pad: Math.max(0, Math.ceil(7 * sb.thK / 2 + 2.4 * sb.ampK + 1 - track.height / 2))
            anchors.topMargin: -pad
            anchors.bottomMargin: -pad
            fragmentShader: "qrc:/shaders/wave.frag.qsb"
            function pm(c) { return Qt.vector4d(c.r * c.a, c.g * c.a, c.b * c.a, c.a) }
            property size size: Qt.size(Math.max(1, width), Math.max(1, height))
            property real frac: sb.dur ? sb.frac : 0
            property real th: track.th
            property real amp: track.amp
            property real wl: sb.small ? 22 : 34
            property real phase: 0
            property real gap: 2 + track.handleK * 4
            property vector4d played: pm(Ilot.playerPal.primary)
            property vector4d rest: pm(sb.restColor)
            // ondulation animee seulement quand elle se voit
            NumberAnimation on phase {
                from: 0
                to: Math.PI * 2
                duration: 1250
                loops: Animation.Infinite
                running: sb.visible && track.amp > 0.01
            }
        }
        // poignee verticale au survol
        Rectangle {
            visible: track.handleK > 0.02 && sb.dur > 0
            width: 4
            height: parent.height * 0.85 * track.handleK
            radius: 2
            x: sb.frac * parent.width - 2
            anchors.verticalCenter: parent.verticalCenter
            color: Ilot.playerPal.primary
            opacity: track.handleK
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            anchors.topMargin: -2
            anchors.bottomMargin: -2
            hoverEnabled: true
            preventStealing: true
            acceptedButtons: Qt.LeftButton
            cursorShape: sb.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
            function at(x) {
                return Math.max(0, Math.min(1, x / width))
            }
            // relache dans l'ilot ? (sinon il se replie, voir Ilot.setSeekDrag)
            function inside(m) {
                const p = mapToItem(null, m.x, m.y)
                const k = Ilot.pillK
                const w = (Ilot.size.w + Ilot.ear * 2) * k
                return p.y >= 0 && p.y < (Ilot.size.h + 2) * k && Math.abs(p.x - Window.width / 2) < w / 2
            }
            onPositionChanged: m => {
                sb.hoverFrac = at(m.x)
                if (pressed && sb.canSeek)
                    sb.dragFrac = sb.hoverFrac
            }
            // l'appui est toujours pris : un clic sur la barre n'ouvre pas le panneau
            onPressed: m => {
                if (!sb.canSeek)
                    return
                sb.held = true
                sb.heldTitle = Ilot.media.title || ""
                sb.dragFrac = sb.hoverFrac = at(m.x)
                Ilot.setSeekDrag(true, true)
            }
            onReleased: m => {
                if (!sb.held)
                    return
                sb.held = false
                // piste changee pendant le glisser : pas de saut dans la suivante
                if (sb.canSeek && (Ilot.media.title || "") === sb.heldTitle) {
                    sb.snap = true
                    Ilot.seek(sb.dragFrac * sb.dur)
                    sb.snap = false
                }
                Ilot.setSeekDrag(false, inside(m))
            }
            onCanceled: {
                if (!sb.held)
                    return
                sb.held = false
                Ilot.setSeekDrag(false, true)
            }
        }
    }

    // bulle de temps au-dessus du curseur (reste dans l'ilot)
    Rectangle {
        id: bubble
        readonly property real fx: sb.dragging ? sb.dragFrac : sb.hoverFrac
        visible: opacity > 0
        opacity: sb.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        width: bt.implicitWidth + 14
        height: 18
        radius: 8
        y: -height + 1
        x: Math.max(0, Math.min(sb.width - width, track.x + fx * track.width - width / 2))
        color: Theme.surfaceHighest
        Txt {
            id: bt
            anchors.centerIn: parent
            text: Ilot.fmtTime(bubble.fx * sb.dur)
            px: 11
            tnum: true
        }
    }
}
