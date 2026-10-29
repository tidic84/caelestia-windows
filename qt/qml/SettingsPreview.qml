import QtQuick

// Reglages : apercu anime en haut des onglets Theme, Ilot et pilule, Lecteur
// et Alertes. Il montre le brouillon (cfg, et pal : palette calculee par
// SettingsPage), pas le theme applique a l'ilot. Les animations s'arretent
// hors de l'ecran et en mouvements reduits
Rectangle {
    id: pv
    // theme, island, player, alerts
    property string kind
    property var cfg: ({})
    property var pal: null
    // couleur d'un role du brouillon (Theme.<role> tant que pal manque)
    function c(role) {
        return pal && pal[role] ? Qt.color(pal[role]) : Theme[role]
    }
    readonly property bool live: visible && !Theme.reduced
    radius: 18
    color: Theme.surfaceHigh
    clip: true

    // fond d'ecran : degrade aux couleurs du brouillon
    Rectangle {
        anchors.fill: parent
        anchors.margins: 5
        radius: 14
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: pv.c("primaryContainer") }
            GradientStop { position: 1; color: pv.c("tertiaryContainer") }
        }
    }

    // ------------------------------------------------ matiere de l'ilot
    readonly property string bg: cfg.island_bg || "solid"
    readonly property color surf: bg === "black" ? "#000000" : c("surface")
    readonly property color fill: Theme.alpha(surf, ({ glass: 0.8, clear: 0.55, wall: 0.5 })[bg] || 1)
    readonly property string shape: cfg.shape || "round"
    readonly property string edge: cfg.border || "none"
    readonly property color ink: c("ink")
    property real hue
    NumberAnimation on hue {
        running: pv.live && pv.edge === "rgb"
        from: 0
        to: 1
        duration: 3000
        loops: Animation.Infinite
    }
    property real pulse
    SequentialAnimation on pulse {
        running: pv.live && pv.edge === "pulse"
        loops: Animation.Infinite
        NumberAnimation { to: 0.2; duration: 700; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutQuad }
    }

    // ouverture de l'ilot : 0 pilule, 1 panneau ; en boucle dans « Ilot »
    property real t: kind === "island" || kind === "alerts" ? 0 : 1
    readonly property var speeds: ({ fast: 0.4, soft: 1.7, off: 0 })
    readonly property real k: speeds[cfg.anim] !== undefined ? speeds[cfg.anim] : 1
    SequentialAnimation {
        running: pv.kind === "island" && pv.live
        loops: Animation.Infinite
        PauseAnimation { duration: 900 }
        NumberAnimation {
            target: pv
            property: "t"
            to: 1
            duration: 520 * pv.k
            easing.type: Easing.BezierSpline
            easing.bezierCurve: pv.cfg.anim === "calm" ? Theme.std : Theme.spring
        }
        PauseAnimation { duration: 1600 }
        NumberAnimation {
            target: pv
            property: "t"
            to: 0
            duration: 420 * pv.k
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.emph
        }
    }

    // Alertes : la pilule s'allonge pour chaque alerte active, a tour de role
    readonly property var alerts: {
        const l = []
        if (cfg.notif_popups)
            l.push({ icon: "chat", text: "Discord · Nouveau message" })
        if (cfg.osd)
            l.push({ icon: "volume_up", bar: 0.6 })
        if (cfg.activity)
            l.push({ icon: "sports_esports", text: "Steam · 42 %" })
        if (cfg.dc_pill)
            l.push({ icon: "mic", text: "Vocal · micro ouvert" })
        if (cfg.privacy)
            l.push({ icon: "videocam", text: "Caméra et micro", dots: true })
        if (cfg.wxfx)
            l.push({ icon: "partly_cloudy_day", text: "Météo animée" })
        return l
    }
    property int alertIdx: -1
    readonly property var alert: alertIdx >= 0 && alertIdx < alerts.length ? alerts[alertIdx] : null
    onAlertsChanged: alertIdx = -1
    Timer {
        running: pv.kind === "alerts" && pv.live && pv.alerts.length > 0
        interval: 2000
        repeat: true
        // une alerte, puis la pilule seule, puis l'alerte suivante
        property int step: 0
        onTriggered: {
            step++
            pv.alertIdx = step % 2 ? Math.floor(step / 2) % pv.alerts.length : -1
        }
    }
    property real grow: alert ? alertRow.implicitWidth + 16 : 0
    Behavior on grow { NumberAnimation { duration: 450 * Math.max(pv.k, 0.01); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }

    Item {
        id: isl
        width: 104 + pv.t * 150 + pv.grow
        height: 26 + pv.t * 58
        anchors.horizontalCenter: parent.horizontalCenter
        y: 13
        // lueur
        Rectangle {
            visible: pv.edge === "glow"
            anchors.fill: parent
            anchors.margins: -4
            radius: island.radius + 4
            color: "transparent"
            border.width: 4
            border.color: Theme.alpha(pv.c("primary"), 0.35)
        }
        Rectangle {
            id: island
            anchors.fill: parent
            radius: pv.shape === "square" ? 6 : pv.shape === "pill" ? height / 2 : Math.min(height / 2, 12 + 8 * pv.t)
            color: pv.fill
            border.width: pv.edge === "line" ? 1 : pv.edge === "rgb" || pv.edge === "pulse" ? 2 : 0
            border.color: pv.edge === "rgb" ? Qt.hsla(pv.hue, 0.8, 0.6, 1)
                : pv.edge === "pulse" ? Theme.alpha(pv.c("primary"), pv.live ? Math.max(0.2, pv.pulse) : 1) : pv.c("outlineVariant")
            clip: true
            // aurore boreale
            Rectangle {
                visible: pv.bg === "aurora"
                anchors.fill: parent
                radius: parent.radius
                opacity: 0.45
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#2bd99f" }
                    GradientStop { position: 0.5; color: "#3a7bd5" }
                    GradientStop { position: 1; color: "#a35bd6" }
                }
            }

            // ---------------------------------- pilule : horloge
            Item {
                id: clockBox
                visible: opacity > 0
                opacity: Math.max(0, 1 - pv.t * 2)
                width: 104
                height: 26
                x: pv.kind === "alerts" ? 0 : (parent.width - width) / 2
                readonly property string style: pv.cfg.clock || "digital"
                Txt {
                    visible: clockBox.style !== "analog" && clockBox.style !== "flip"
                    anchors.centerIn: parent
                    text: "12:34"
                    px: 13
                    tnum: true
                    weight: clockBox.style === "neon" || clockBox.style === "pixel" ? Font.Bold : Font.Medium
                    font.family: clockBox.style === "pixel" ? "Consolas" : Theme.font
                    color: clockBox.style === "neon" ? pv.c("primary") : pv.ink
                    style: clockBox.style === "neon" ? Text.Outline : Text.Normal
                    styleColor: Theme.alpha(pv.c("primary"), 0.45)
                }
                Row {
                    visible: clockBox.style === "flip"
                    anchors.centerIn: parent
                    spacing: 2
                    Repeater {
                        model: ["1", "2", ":", "3", "4"]
                        Rectangle {
                            required property string modelData
                            width: modelData === ":" ? 4 : 11
                            height: 17
                            radius: 3
                            color: modelData === ":" ? "transparent" : pv.c("surfaceHighest")
                            Txt {
                                anchors.centerIn: parent
                                text: parent.modelData
                                px: 11
                                weight: Font.Medium
                                color: pv.ink
                            }
                        }
                    }
                }
                Rectangle {
                    visible: clockBox.style === "analog"
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    radius: 9
                    color: "transparent"
                    border.width: 1.5
                    border.color: pv.ink
                    Rectangle {
                        x: parent.width / 2 - 0.75
                        y: 4
                        width: 1.5
                        height: 5
                        color: pv.ink
                    }
                    Rectangle {
                        x: parent.width / 2
                        y: parent.height / 2 - 0.75
                        width: 5
                        height: 1.5
                        color: pv.ink
                    }
                }
            }
            // Alertes : contenu de l'alerte, a droite de l'horloge
            Row {
                id: alertRow
                visible: pv.kind === "alerts" && !!pv.alert
                opacity: pv.grow > 0 ? 1 : 0
                x: 104
                anchors.verticalCenter: clockBox.verticalCenter
                spacing: 6
                Ms {
                    anchors.verticalCenter: parent.verticalCenter
                    name: pv.alert ? pv.alert.icon : ""
                    size: 16
                    color: pv.c("primary")
                }
                Txt {
                    visible: !!(pv.alert && pv.alert.text)
                    anchors.verticalCenter: parent.verticalCenter
                    text: pv.alert && pv.alert.text ? pv.alert.text : ""
                    px: 11.5
                    color: pv.ink
                }
                Rectangle {
                    visible: !!(pv.alert && pv.alert.bar)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110
                    height: 5
                    radius: 2.5
                    color: Theme.alpha(pv.ink, 0.2)
                    Rectangle {
                        width: parent.width * 0.6
                        height: parent.height
                        radius: 2.5
                        color: pv.c("primary")
                    }
                }
            }

            // ---------------------------------- panneau ouvert
            Item {
                visible: opacity > 0
                opacity: Math.max(0, pv.t * 2 - 1)
                anchors.fill: parent
                anchors.margins: 8
                // Theme, Ilot : onglets et cartes aux couleurs du brouillon
                Row {
                    visible: pv.kind !== "player"
                    spacing: 6
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            width: (isl.width - 16 - 12) / 3
                            height: isl.height - 16
                            radius: Math.min(10, island.radius)
                            color: pv.c("surfaceC")
                            Rectangle {
                                x: 6
                                y: 6
                                width: 14
                                height: 14
                                radius: 7
                                color: [pv.c("primary"), pv.c("secondary"), pv.c("tertiary")][parent.index]
                            }
                            Rectangle {
                                x: 6
                                y: 26
                                width: parent.width - 18
                                height: 4
                                radius: 2
                                color: pv.ink
                                opacity: 0.8
                            }
                            Rectangle {
                                x: 6
                                y: 34
                                width: parent.width - 30
                                height: 4
                                radius: 2
                                color: pv.c("inkVariant")
                                opacity: 0.6
                            }
                            // interrupteur
                            Rectangle {
                                visible: parent.index === 1
                                x: parent.width - width - 6
                                y: 6
                                width: 22
                                height: 13
                                radius: 6.5
                                color: pv.c("primary")
                                Rectangle {
                                    x: parent.width - width - 2
                                    y: 2
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    color: pv.c("inkPrimary")
                                }
                            }
                        }
                    }
                }
                // Lecteur
                Loader {
                    active: pv.kind === "player"
                    anchors.fill: parent
                    sourceComponent: playerPv
                }
            }
        }
    }

    // ------------------------------------------------ lecteur
    Component {
        id: playerPv
        Item {
            id: pl
            readonly property var cfg: pv.cfg
            readonly property color tone: cfg.player_color === "theme" ? pv.c("primary")
                : /^#[0-9a-fA-F]{6}$/.test(cfg.player_color || "") ? cfg.player_color : "#e0785a"
            readonly property string btnColor: cfg.player_btn_color || "auto"
            readonly property color btnFill: btnColor === "white" || btnColor === "auto" ? "#ffffff"
                : btnColor === "player" ? tone : btnColor
            readonly property color btnInk: cfg.player_btn_ink === "white" ? "#ffffff" : cfg.player_btn_ink === "black" ? "#000000"
                : btnFill.hslLightness > 0.6 ? "#1b1b1f" : "#ffffff"
            property bool playing: true
            Timer {
                running: pv.live
                interval: 2400
                repeat: true
                onTriggered: pl.playing = !pl.playing
            }
            // pochette
            Rectangle {
                id: art
                readonly property string form: pl.cfg.player_art || "scallop"
                width: 50
                height: 50
                anchors.verticalCenter: parent.verticalCenter
                radius: form === "disc" ? 25 : form === "scallop" ? 16 : 10
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(pl.tone, 1.3) }
                    GradientStop { position: 1; color: Qt.darker(pl.tone, 1.6) }
                }
                RotationAnimation on rotation {
                    running: pv.live && art.form === "disc" && pl.playing
                    from: 0
                    to: 360
                    duration: 6000
                    loops: Animation.Infinite
                }
            }
            Column {
                x: art.width + 12
                y: 6
                width: parent.width - x - btn.width - 12
                spacing: 4
                Txt {
                    text: "Morceau en cours"
                    px: 12
                    weight: Font.Medium
                    color: pv.ink
                }
                Txt {
                    text: "Artiste"
                    px: 10.5
                    color: pv.c("inkVariant")
                }
                // barre de progression : ondulee ou plate, epaisseur, amplitude
                Canvas {
                    id: bar
                    readonly property real thick: ({ thin: 2, thick: 6 })[pl.cfg.player_bar_size] || 4
                    readonly property real amp: pl.cfg.player_bar === "flat" ? 0 : ({ low: 1.5, high: 4.5 })[pl.cfg.player_bar_amp] || 3
                    property real phase
                    width: parent.width
                    height: 14
                    NumberAnimation on phase {
                        running: pv.live && pl.playing && bar.amp > 0
                        from: 0
                        to: Math.PI * 2
                        duration: 1600
                        loops: Animation.Infinite
                    }
                    onPhaseChanged: requestPaint()
                    onThickChanged: requestPaint()
                    onAmpChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.lineCap = "round"
                        ctx.lineWidth = thick
                        const mid = height / 2
                        const done = width * 0.55
                        ctx.strokeStyle = String(pl.tone)
                        ctx.beginPath()
                        for (let x = thick / 2; x <= done; x += 2) {
                            const y = mid + amp * Math.sin(x / 5 + phase)
                            if (x <= thick / 2)
                                ctx.moveTo(x, y)
                            else
                                ctx.lineTo(x, y)
                        }
                        ctx.stroke()
                        ctx.strokeStyle = String(Theme.alpha(pv.ink, 0.25))
                        ctx.beginPath()
                        ctx.moveTo(done + 6, mid)
                        ctx.lineTo(width - thick / 2, mid)
                        ctx.stroke()
                    }
                }
            }
            // bouton lecture : forme, couleur, rotation
            Item {
                id: btn
                readonly property string form: pl.cfg.player_btn || "cookie"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                height: 38
                // ombre coloree sous un bouton blanc
                Rectangle {
                    visible: btn.form !== "none" && pl.cfg.player_btn_glow !== false && pl.btnFill.hslLightness > 0.9
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: width
                    radius: width / 2
                    color: Theme.alpha(pl.tone, 0.35)
                }
                Rectangle {
                    visible: btn.form !== "none"
                    anchors.fill: parent
                    radius: btn.form === "round" || (pl.playing && pl.cfg.player_btn_morph !== false) ? width / 2 : 12
                    Behavior on radius { NumberAnimation { duration: 300 } }
                    color: pl.btnFill
                    RotationAnimation on rotation {
                        running: pv.live && btn.form === "cookie" && pl.playing && pl.cfg.player_btn_spin !== false
                        from: 0
                        to: 360
                        duration: 5000
                        loops: Animation.Infinite
                    }
                }
                Ms {
                    anchors.centerIn: parent
                    name: pl.playing ? "pause" : "play_arrow"
                    size: 22
                    color: btn.form === "none" ? pl.tone : pl.btnInk
                }
            }
        }
    }
}
