import QtQuick
import QtQuick.Effects

// Media : fond (pochette floutee, couleur, degrade), grande pochette, titre,
// progression, commandes, volume de l'appli, visualiseur, paroles
// synchronisees ; playlists favorites dans un panneau lateral
Rectangle {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "media"
    readonly property string bg: Ilot.cfg.media_bg || "art"
    radius: 22
    // pochette floutee : fond presque noir sous les couleurs (maquette)
    color: bg === "color" ? Theme.primaryContainer : bg === "art" && !Theme.light && Ilot.hasMedia ? "#0b0a0f" : Theme.surfaceC
    clip: true
    gradient: bg === "gradient" ? grad : null
    Gradient {
        id: grad
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Theme.mix(Theme.primaryContainer, Theme.surfaceC, 0.85) }
        GradientStop { position: 1; color: Theme.mix(Theme.tertiaryContainer, Theme.surfaceC, 0.6) }
    }

    // ------------------------------------------------ volume de l'appli
    // session audio Windows de l'appli qui joue (Spotify, Chrome...)
    property var appVol: null
    property string volApp: ""
    function refreshAppVolume() {
        volApp = Ilot.hasMedia ? Ilot.media.app : ""
        if (!volApp) {
            appVol = null
            return
        }
        Api.invoke("app_volume_get", { app: volApp }).then(v => { page.appVol = v })
    }
    onShownChanged: if (shown) refreshAppVolume()
    Connections {
        target: Ilot
        function onMediaChanged() {
            if (page.shown && (Ilot.hasMedia ? Ilot.media.app : "") !== page.volApp)
                page.refreshAppVolume()
        }
    }

    // ------------------------------------------- paroles synchronisees
    // src/lyrics.rs (lrclib.net, puis NetEase) ; la ligne en cours suit la
    // position du lecteur. Affichees ou non : garde dans ui.json
    readonly property bool lyricsOn: Ilot.ui.lyrics !== false
    property var ly: ({ key: "", lines: [], state: "" })
    property string lyErr: ""
    readonly property string lyKey: (Ilot.media.artist || "") + "|" + (Ilot.media.title || "")
    function parseLrc(t) {
        const out = []
        for (const row of t.split(/\r?\n/)) {
            const re = /\[(\d+):(\d+(?:[.:]\d+)?)\]/g
            const tags = []
            let m
            while ((m = re.exec(row)) !== null)
                tags.push(m)
            if (!tags.length)
                continue
            const text = row.replace(/\[[^\]]*\]/g, "").trim()
            for (const g of tags)
                out.push({ t: Number(g[1]) * 60 + parseFloat(g[2].replace(":", ".")), text: text })
        }
        return out.sort((a, b) => a.t - b.t)
    }
    function loadLyrics() {
        const key = lyKey
        if (!Ilot.hasMedia || !Ilot.media.title) {
            ly = { key: key, lines: [], state: "none" }
            return
        }
        if (ly.key === key && ly.state !== "error")
            return
        ly = { key: key, lines: [], state: "loading" }
        Api.invoke("lyrics_get", { artist: Ilot.media.artist || "", title: Ilot.media.title, album: Ilot.media.album || "", duration: Ilot.media.duration || 0 }).then(r => {
            if (page.ly.key !== key)
                return
            const synced = r.synced ? page.parseLrc(r.synced) : []
            const lines = synced.length ? synced : r.plain.split(/\r?\n/).map(t => ({ t: -1, text: t }))
            page.ly = { key: key, lines: r.instrumental ? [] : lines, state: r.instrumental ? "instr" : synced.length ? "synced" : r.plain ? "plain" : "none" }
        }, () => {
            if (page.ly.key !== key)
                return
            // serveurs de paroles surcharges : nouvel essai tout seul dans 30 s
            page.ly = { key: key, lines: [], state: "error" }
            Ilot.later(30000, () => { if (page.ly.key === key && page.ly.state === "error") page.loadLyrics() })
        })
    }
    // ligne en cours (petite avance : la ligne s'allume avec la voix)
    readonly property int lyOn: {
        if (ly.state !== "synced")
            return -1
        const p = Ilot.pos + 0.25
        let i = -1
        while (i + 1 < ly.lines.length && ly.lines[i + 1].t <= p)
            i++
        return i
    }
    Timer {
        interval: 200
        repeat: true
        running: page.shown && page.lyricsOn
        onTriggered: {
            Ilot.pos = Ilot.position()
            if (page.lyKey !== page.ly.key)
                page.loadLyrics()
        }
    }

    // ------------------------------------------------- disposition
    // Reglages > Apparence > Lecteur : colonne centree (paroles a droite) ou
    // cote a cote (paroles en bandeau), pochette arrondie ou festonnee
    readonly property bool col: (Ilot.cfg.player_layout || "col") !== "side"
    // pochette : "scallop" (festonnee), "round" (arrondie) ou "disc" (ronde)
    readonly property string artKind: Ilot.cfg.player_art || "scallop"
    readonly property bool scallop: artKind === "scallop"
    // rayon des coins de la pochette arrondie / ronde (hors festonnee)
    readonly property real artRadius: artKind === "disc" ? main.artSize / 2 : 28
    // anneau de spectre : par defaut seulement avec la pochette festonnee
    readonly property bool spectrum: Ilot.cfg.player_spectrum === null || Ilot.cfg.player_spectrum === undefined
        ? scallop : !!Ilot.cfg.player_spectrum
    // reglages du fond « art » (1 : par defaut)
    readonly property real blurK: ({ low: 0.5, high: 1.6 })[Ilot.cfg.media_blur] || 1
    readonly property real dimA: ({ light: 0.30, strong: 0.70 })[Ilot.cfg.media_dim] || 0.47
    readonly property bool drift: Ilot.cfg.media_drift !== false
    readonly property bool playing: Ilot.hasMedia && Ilot.media.playing
    function pm(c) {
        return Qt.vector4d(c.r * c.a, c.g * c.a, c.b * c.a, c.a)
    }

    // pochette floutee : tres floue (decodee en 48 px), saturee, qui derive
    // lentement (le flou est calcule une fois, seul le deplacement bouge).
    // clip ne rogne pas les arrondis : le fond passe par un masque a la forme
    // de la page (layer seulement en mode « art », comme Island.qml)
    Item {
        id: bgClip
        anchors.fill: parent
        layer.enabled: bgFx.visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: bgMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        Item {
            id: bgSrc
            anchors.fill: parent
            anchors.margins: -60
            visible: false
            Image {
                anchors.fill: parent
                source: Ilot.hasMedia ? Ilot.art : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                sourceSize.width: 48
            }
        }
        MultiEffect {
            id: bgFx
            anchors.fill: bgSrc
            source: bgSrc
            visible: page.bg === "art" && Ilot.hasMedia && Ilot.art !== "" && page.visible
            blurEnabled: true
            // flou : 64 par defaut ; « fort » passe par blurMultiplier
            // (blurMax est plafonne a 64 par MultiEffect)
            blurMax: Math.min(64, Math.round(64 * page.blurK))
            blurMultiplier: Math.max(0, page.blurK - 1)
            blur: 1
            saturation: 0.8
            opacity: Theme.light ? 0.4 : 0.85
            scale: 1.15
            property real t: 0
            // derive desactivee : position neutre, animation arretee
            transform: Translate {
                x: page.drift ? 36 * Math.sin(bgFx.t * 0.7) : 0
                y: page.drift ? 28 * Math.cos(bgFx.t * 0.5) : 0
            }
            NumberAnimation on t {
                from: 0
                to: Math.PI * 20
                duration: 180000
                loops: Animation.Infinite
                // en pause (pas arretee) : la derive reprend la ou elle s'etait figee
                running: bgFx.visible && page.drift
                paused: running && !(page.shown && page.playing && !Theme.reduced)
            }
        }
    }
    // masque fixe (hors du scale/Translate de bgFx : les coins ne bougent pas)
    Rectangle {
        id: bgMask
        anchors.fill: parent
        radius: page.radius
        visible: false
        layer.enabled: bgClip.layer.enabled
    }
    // assombri vers le bas (lisibilite des commandes)
    Rectangle {
        anchors.fill: parent
        visible: page.bg === "art" && Ilot.hasMedia && !Theme.light
        radius: page.radius
        gradient: Gradient {
            GradientStop { position: 0.4; color: "transparent" }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, page.dimA) }
        }
    }

    Item {
        id: main
        anchors.fill: parent
        // colonne (maquette .mcol) : centree, ou a 24 px du bord gauche avec
        // les paroles (main prend alors juste la largeur de la colonne)
        anchors.leftMargin: page.col ? (page.lyricsOn ? 24 : 0) : 32
        anchors.rightMargin: page.col ? (page.lyricsOn ? page.width - 24 - colW : 0) : 32
        // cote a cote + paroles (.ly-on) : le bandeau prend le bas
        anchors.topMargin: page.col ? 0 : page.lyricsOn ? 14 : 24
        anchors.bottomMargin: page.col ? 0 : page.lyricsOn ? 96 : 24
        Behavior on anchors.leftMargin { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        Behavior on anchors.rightMargin { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        // cote a cote : ecart pochette / infos et place de l'anneau
        readonly property real gap: 28
        readonly property real ringPad: page.spectrum ? 30 : 0
        // colonne : marges au-dessus et au-dessous de la pochette (anneau de
        // spectre : 30 / 32 ; sans anneau : 12 / 16)
        readonly property real padTop: page.spectrum ? 30 : 12
        readonly property real padBot: page.spectrum ? 32 : 16
        // anneau autour de la pochette arrondie : il passe au-dela des coins,
        // ex = (racine 2 - 1) * (cote / 2 - 28) de plus de chaque cote
        readonly property real exK: page.spectrum && page.artKind === "round" ? Math.SQRT2 - 1 : 0
        readonly property real ex: exK * Math.max(0, artSize / 2 - 28)
        property real artMax: page.lyricsOn ? 190 : 260
        Behavior on artMax { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        // colonne : 156 (festonnee) ou 172 (arrondie) a 459 px de haut ; grandit
        // avec la hauteur (panneau agrandi), plafonnee a 300, sans deborder
        // (taille + 2 * ex compris : la borne est resolue pour la taille)
        readonly property real colArt: Math.round(Math.max(90, Math.min((page.scallop ? 156 : 172) + Math.max(0, page.height - 459) * 0.5, 300,
            (page.height - meta.height - padTop - padBot - 16 + 56 * exK) / (1 + exK))))
        readonly property real artSize: page.col
            ? colArt
            : Math.max(90, Math.min(artMax, (height - ringPad * 2 + 56 * exK) / (1 + exK), width * 0.42))
        // colonne de 340 (plus large si la pochette grandit)
        readonly property real colW: Math.min(page.width - 48, Math.max(340, artSize + 184))
        readonly property real stackH: artSize + padTop + padBot + ex * 2 + meta.height

        // grande pochette : halo de ses couleurs en lecture, reduite et
        // assombrie en pause, inclinee en 3D au survol
        Item {
            id: art
            width: main.artSize
            height: main.artSize
            x: page.col ? (main.width - width) / 2 : main.ringPad + main.ex
            y: page.col ? Math.max(0, (main.height - main.stackH) / 2) + main.padTop + main.ex : (main.height - height) / 2
            property real rx: 0
            property real ry: 0
            Behavior on rx { NumberAnimation { duration: 200 } }
            Behavior on ry { NumberAnimation { duration: 200 } }
            transform: [
                Rotation { origin.x: art.width / 2; origin.y: art.height / 2; axis { x: 1; y: 0; z: 0 } angle: art.rx },
                Rotation { origin.x: art.width / 2; origin.y: art.height / 2; axis { x: 0; y: 1; z: 0 } angle: art.ry }
            ]
            MouseArea {
                id: tilt
                anchors.fill: parent
                hoverEnabled: !Theme.reduced
                acceptedButtons: Qt.NoButton
                onPositionChanged: m => {
                    art.ry = (m.x / width - 0.5) * 22
                    art.rx = (0.5 - m.y / height) * 22
                }
                onContainsMouseChanged: if (!containsMouse) { art.rx = 0; art.ry = 0 }
            }

            // halo : la pochette tres floutee derriere elle (flou calcule une
            // fois par pochette, seuls l'opacite et l'echelle bougent)
            Item {
                id: haloSrc
                anchors.fill: parent
                visible: false
                Image {
                    anchors.fill: parent
                    source: Ilot.hasMedia ? Ilot.art : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 96
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: haloSrc
                visible: page.visible && Ilot.hasMedia && Ilot.art !== "" && opacity > 0
                blurEnabled: true
                blurMax: 48
                blur: 1
                saturation: 0.6
                opacity: page.playing ? (Theme.light ? 0.5 : 0.75) : 0
                scale: page.playing ? 1.12 : 1.05
                Behavior on opacity { NumberAnimation { duration: 600 } }
                Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
            }
            RectangularShadow {
                visible: !page.scallop
                anchors.fill: parent
                radius: page.artRadius
                offset.y: 12
                blur: 40
                color: Qt.rgba(0, 0, 0, Theme.light ? 0.18 : 0.35)
            }

            // anneau de spectre autour de la pochette (au-dela des coins de la
            // pochette arrondie : main.ex)
            ShaderEffect {
                readonly property bool on: page.spectrum && page.shown && Ilot.live
                visible: on
                anchors.centerIn: parent
                width: parent.width + 68 + main.ex * 2
                height: width
                fragmentShader: "qrc:/shaders/ring.frag.qsb"
                function lv(i) {
                    const s = Ilot.shown
                    return Qt.vector4d(s[i] || 0, s[i + 1] || 0, s[i + 2] || 0, s[i + 3] || 0)
                }
                property size size: Qt.size(Math.max(1, width), Math.max(1, height))
                property real r0: art.width / 2 + main.ex + 5
                property real maxLen: 22
                property vector4d l0: on ? lv(0) : Qt.vector4d(0, 0, 0, 0)
                property vector4d l1: on ? lv(4) : Qt.vector4d(0, 0, 0, 0)
                property vector4d l2: on ? lv(8) : Qt.vector4d(0, 0, 0, 0)
                property vector4d l3: on ? lv(12) : Qt.vector4d(0, 0, 0, 0)
                property vector4d l4: on ? lv(16) : Qt.vector4d(0, 0, 0, 0)
                property vector4d l5: on ? lv(20) : Qt.vector4d(0, 0, 0, 0)
                property vector4d color: page.pm(Ilot.playerPal.primary)
            }

            Item {
                id: cover
                anchors.fill: parent
                scale: page.playing || !Ilot.hasMedia ? 1 : 0.9
                Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                Rectangle {
                    anchors.fill: parent
                    visible: !page.scallop || !scImg.ok
                    radius: page.scallop ? width / 2 : page.artRadius
                    color: Theme.surfaceHighest
                    Ms {
                        anchors.centerIn: parent
                        name: "music_note"
                        size: 64
                        color: Theme.inkVariant
                    }
                }
                ArtImage {
                    visible: !page.scallop
                    anchors.fill: parent
                    radius: page.artRadius
                }
                // voile de pause (pochette arrondie)
                Rectangle {
                    visible: !page.scallop && opacity > 0
                    anchors.fill: parent
                    radius: page.artRadius
                    color: "black"
                    opacity: Ilot.hasMedia && !Ilot.media.playing ? 0.45 : 0
                    Behavior on opacity { NumberAnimation { duration: 400 } }
                }
                // pochette festonnee (shaders/scallop.frag), assombrie en pause
                Image {
                    id: scImg
                    visible: false
                    asynchronous: true
                    source: page.scallop && Ilot.hasMedia ? Ilot.art : ""
                    // taille fixe : suivre la taille animee rechargerait l'image a
                    // chaque trame (le DPI est deja applique par Qt)
                    sourceSize.width: 512
                    retainWhileLoading: true
                    // l'ancienne pochette reste affichee pendant le chargement
                    property bool ok: false
                    onStatusChanged: ok = status === Image.Ready || (status === Image.Loading && ok)
                }
                ShaderEffect {
                    anchors.fill: parent
                    visible: page.scallop && scImg.ok
                    fragmentShader: "qrc:/shaders/scallop.frag.qsb"
                    property var source: scImg
                    property size size: Qt.size(Math.max(1, width), Math.max(1, height))
                    property size imgSize: Qt.size(Math.max(1, scImg.implicitWidth), Math.max(1, scImg.implicitHeight))
                    property real dim: Ilot.hasMedia && !Ilot.media.playing ? 0.45 : 0
                    Behavior on dim { NumberAnimation { duration: 400 } }
                }
                // reflet qui suit la souris
                Glow {
                    visible: tilt.containsMouse && !page.scallop
                    width: parent.width * 1.2
                    height: width
                    x: tilt.mouseX - width / 2
                    y: tilt.mouseY - height / 2
                    core: 0
                    color: Qt.rgba(1, 1, 1, 0.18)
                }
            }
        }

        Column {
            id: meta
            x: page.col ? (main.width - width) / 2 : art.x + art.width + main.ringPad + main.ex + main.gap
            y: page.col ? art.y + art.height + main.padBot + main.ex : (main.height - height) / 2
            width: page.col ? main.colW : main.width - x
            // colonne : pas d'ecart, seulement les marges de la maquette
            spacing: page.col ? 0 : 4
            Chip {
                x: page.col ? (parent.width - width) / 2 : 0
                // colonne (.chip) : 19 px de haut, 9 px de marge de cote
                width: implicitWidth - (page.col ? 2 : 0)
                height: page.col ? 19 : implicitHeight
                text: Ilot.hasMedia ? Ilot.media.app || "" : ""
                color: Theme.alpha(Theme.ink, 0.08)
                fg: Theme.inkVariant
            }
            Item {
                width: 1
                height: 4
                visible: Ilot.hasMedia && !!Ilot.media.app
            }
            // titre : defile s'il est trop long
            Item {
                id: titleBox
                width: parent.width
                height: titleTxt.implicitHeight
                clip: true
                readonly property real over: titleTxt.implicitWidth - width
                property real shift: 0
                Txt {
                    id: titleTxt
                    x: (titleBox.over > 0 ? 0 : page.col ? -titleBox.over / 2 : 0) + (scroll.running ? titleBox.shift : 0)
                    text: Ilot.hasMedia ? Ilot.media.title || "Sans titre" : "Rien en lecture"
                    px: page.col ? 22 : 24
                    weight: Font.Bold
                }
                SequentialAnimation {
                    id: scroll
                    running: titleBox.over > 4 && page.shown && !Theme.reduced
                    loops: Animation.Infinite
                    onRunningChanged: titleBox.shift = 0
                    PauseAnimation { duration: 2500 }
                    NumberAnimation { target: titleBox; property: "shift"; from: 0; to: -titleBox.over; duration: Math.max(1500, titleBox.over * 30); easing.type: Easing.InOutSine }
                    PauseAnimation { duration: 1500 }
                    NumberAnimation { target: titleBox; property: "shift"; to: 0; duration: 600; easing.type: Easing.InOutCubic }
                }
            }
            Txt {
                width: parent.width
                visible: text !== ""
                horizontalAlignment: page.col ? Text.AlignHCenter : Text.AlignLeft
                text: Ilot.hasMedia ? Ilot.media.artist || "" : ""
                px: page.col ? 15 : 16
                weight: Font.Medium
                color: Ilot.playerPal.primary
                elide: Text.ElideRight
            }
            Txt {
                width: parent.width
                height: Math.max(15, implicitHeight)
                horizontalAlignment: page.col ? Text.AlignHCenter : Text.AlignLeft
                text: Ilot.hasMedia ? Ilot.media.album || "" : ""
                px: 12
                // colonne, theme sombre : blanc a 40 % (maquette)
                readonly property bool white: page.col && !Theme.light
                color: white ? Qt.rgba(1, 1, 1, 0.4) : Theme.inkVariant
                opacity: white ? 1 : 0.75
                elide: Text.ElideRight
            }
            Item {
                width: 1
                height: page.col ? 8 : page.lyricsOn ? 6 : 12
            }
            // progression (cliquer ou glisser pour se deplacer dans le titre)
            SeekBar {
                width: parent.width
                restColor: Theme.alpha(Theme.ink, 0.2)
            }
            Item {
                width: 1
                height: 6
            }
            MediaControls {
                big: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Item {
                width: 1
                height: 4
            }
            // volume de l'appli qui joue
            Row {
                visible: !!page.appVol
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 6
                // colonne (.vol) : icone 18 px, ecart 10, 250 px en tout
                spacing: page.col ? 10 : 8
                IconBtn {
                    small: true
                    width: page.col ? 20 : 26
                    height: width
                    iconSize: page.col ? 18 : 20
                    fg: page.col ? Theme.inkVariant : Theme.ink
                    readonly property int n: page.appVol ? Math.round(page.appVol.level * 100) : 0
                    icon: !page.appVol || page.appVol.muted || !n ? "volume_off" : n < 50 ? "volume_down" : "volume_up"
                    tip: "Couper le son de l'appli"
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        const m = !page.appVol.muted
                        page.appVol = { level: page.appVol.level, muted: m }
                        Api.invoke("app_volume_set", { app: page.volApp, muted: m })
                    }
                }
                M3Slider {
                    id: appSlider
                    width: 220
                    trackH: 8
                    thumbH: 20
                    accent: Theme.ink
                    trackColor: Theme.alpha(Theme.ink, 0.15)
                    ringColor: "transparent"
                    wheelStep: 5
                    anchors.verticalCenter: parent.verticalCenter
                    fill: page.appVol && page.appVol.muted ? 0 : value / 100
                    Binding on value {
                        when: !appSlider.dragging
                        value: page.appVol ? Math.round(page.appVol.level * 100) : 0
                    }
                    onMoved: v => {
                        page.appVol = { level: v / 100, muted: false }
                        Api.invoke("app_volume_set", { app: page.volApp, level: v / 100, muted: false })
                    }
                }
            }
        }
    }

    // paroles : colonne de droite (disposition en colonne, la ligne chantee
    // au centre, les autres estompees) ou bandeau en bas (cote a cote)
    Gradient {
        id: bandGrad
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 0.3; color: Theme.alpha(Theme.surface, 0.55) }
        GradientStop { position: 1; color: Theme.alpha(Theme.surface, 0.55) }
    }
    Rectangle {
        id: lyBox
        visible: page.lyricsOn
        x: page.col ? page.width / 2 : 0
        y: page.col ? 0 : page.height - height
        width: page.col ? page.width / 2 - 16 : page.width
        height: page.col ? page.height : 104
        bottomLeftRadius: page.col ? 0 : page.radius
        bottomRightRadius: page.radius
        color: "transparent"
        gradient: page.col ? null : bandGrad
        Txt {
            visible: page.ly.state !== "synced" && page.ly.state !== "plain"
            anchors.centerIn: parent
            width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            px: 12.5
            color: Theme.inkVariant
            text: ({ loading: "Recherche des paroles…", none: "Pas de paroles trouvées pour ce morceau.", instr: "♪ Morceau instrumental",
                error: "Serveurs de paroles occupés, nouvel essai dans 30 s…" })[page.ly.state] || ""
        }
        ListView {
            id: lyList
            readonly property bool synced: page.ly.state === "synced"
            anchors.fill: parent
            anchors.leftMargin: page.col ? 0 : 32
            anchors.rightMargin: page.col ? 8 : 32
            visible: synced || page.ly.state === "plain"
            clip: true
            model: page.ly.lines
            spacing: page.col ? 2 : 4
            topMargin: !synced ? 8 : page.col ? height / 2 - 20 : 36
            // colonne : les pastilles Paroles / Playlists couvrent le bas
            bottomMargin: !synced && page.col ? 54 : topMargin
            interactive: !synced
            boundsBehavior: Flickable.StopAtBounds
            highlightRangeMode: synced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
            preferredHighlightBegin: height / 2 - 12
            preferredHighlightEnd: height / 2 + 12
            highlightMoveDuration: 400
            currentIndex: Math.max(0, page.lyOn)
            delegate: Btn {
                id: line
                required property var modelData
                required property int index
                readonly property bool on: index === page.lyOn
                // fondu en haut et en bas (mask-image : transparent, 22 %, 78 %,
                // transparent en colonne ; 32 % / 68 % dans le bandeau)
                readonly property real mid: y - lyList.contentY + height / 2
                readonly property real edge: lyList.synced ? Math.max(0, Math.min(1, Math.min(mid, lyList.height - mid) / (lyList.height * (page.col ? 0.22 : 0.32)))) : 1
                width: lyList.width
                height: txt.implicitHeight
                active: lyList.synced && modelData.t >= 0
                radius: 16
                // colonne : la ligne chantee sur une pastille claire
                color: page.col && on ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                opacity: edge
                // clic sur une ligne : le lecteur y saute
                onClicked: Ilot.seek(modelData.t)
                Txt {
                    id: txt
                    width: parent.width
                    leftPadding: page.col ? 12 : 0
                    rightPadding: leftPadding
                    topPadding: page.col ? 6 : 0
                    bottomPadding: topPadding
                    horizontalAlignment: page.col ? Text.AlignLeft : Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeightMode: Text.FixedHeight
                    lineHeight: px * 1.3
                    text: line.modelData.text || "♪"
                    px: !lyList.synced ? 13 : page.col ? 18 : line.modelData.text ? 15 : 12
                    weight: page.col && lyList.synced ? Font.Bold : line.on ? Font.DemiBold : Font.Normal
                    color: page.col ? Theme.ink : line.on ? Ilot.playerPal.primary : Theme.inkVariant
                    opacity: line.on ? 1 : !lyList.synced ? 0.9 : line.hovered ? (page.col ? 0.5 : 0.85) : page.col ? 0.28 : 0.5
                    scale: page.col ? (line.on || !lyList.synced ? 1 : 0.96) : line.on ? 1.12 : 1
                    transformOrigin: page.col ? Item.Left : Item.Center
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Behavior on color { ColorAnimation { duration: 300 } }
                    Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                    // colonne : lueur de la couleur du lecteur sous la ligne
                    // chantee (text-shadow 0 0 18px) ; une seule couche a la fois
                    layer.enabled: line.on && page.col && lyList.synced && !Theme.reduced
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Ilot.playerPal.primary
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                        blurMax: 32
                        shadowBlur: 0.6
                    }
                }
            }
        }
    }
    onLyricsOnChanged: if (lyricsOn) { ly = { key: "", lines: [], state: "" }; loadLyrics() }
    Component.onCompleted: if (lyricsOn) loadLyrics()

    // paroles, playlists : pastilles en bas a droite (en haut a droite en
    // cote a cote : le bandeau des paroles prend le bas)
    component Pastille: Btn {
        id: pa
        property string icon
        property string label
        property bool on: false
        width: pr.implicitWidth + 24
        height: 32
        radius: 16
        color: on ? Qt.rgba(1, 1, 1, 0.92) : hovered ? Theme.alpha(Theme.ink, 0.16) : Theme.alpha(Theme.ink, 0.08)
        Row {
            id: pr
            anchors.centerIn: parent
            spacing: 6
            Ms {
                name: pa.icon
                size: 18
                color: pa.on ? "#141414" : Theme.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                text: pa.label
                px: 12
                weight: Font.Medium
                color: pa.on ? "#141414" : Theme.ink
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: page.col ? page.height - height - 14 : 10
        spacing: 6
        Pastille {
            icon: "lyrics"
            label: "Paroles"
            on: page.lyricsOn
            onClicked: Ilot.saveUi({ lyrics: !page.lyricsOn })
        }
        Pastille {
            icon: "queue_music"
            label: "Playlists"
            on: lists.visible
            onClicked: lists.visible = !lists.visible
        }
    }

    // ------------------------------------------- playlists favorites
    // %LOCALAPPDATA%\Ilot\playlists.json : [{ name, url }]
    Rectangle {
        id: lists
        visible: false
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        width: 300
        radius: 20
        color: Theme.surfaceHigh
        z: 3
        onVisibleChanged: if (visible) slideIn.restart()
        transform: Translate { id: slide; x: 0 }
        ParallelAnimation {
            id: slideIn
            NumberAnimation { target: slide; property: "x"; from: 24; to: 0; duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph }
            NumberAnimation { target: lists; property: "opacity"; from: 0; to: 1; duration: 250 }
        }
        RectangularShadow {
            z: -1
            anchors.fill: parent
            radius: parent.radius
            offset.y: 10
            blur: 34
            color: Qt.rgba(0, 0, 0, 0.45)
        }
        function plIcon(url) {
            return /spotify/.test(url) ? "music_note" : /deezer/.test(url) ? "graphic_eq" : /youtu/.test(url) ? "smart_display" : "queue_music"
        }
        // les liens open.spotify.com s'ouvrent directement dans l'appli Spotify
        function plTarget(url) {
            const m = url.match(/open\.spotify\.com\/(?:intl-\w+\/)?(playlist|album|artist|track)\/(\w+)/)
            return m ? "spotify:" + m[1] + ":" + m[2] : url
        }
        function save() {
            Api.invoke("store_set", { key: "playlists", value: Ilot.playlists })
        }

        Flickable {
            id: plFlick
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            contentHeight: plCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: plCol
                width: parent.width
                spacing: 8
                Item {
                    width: parent.width
                    height: 26
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Playlists"
                        px: 14
                        weight: Font.Bold
                    }
                    IconBtn {
                        anchors.right: parent.right
                        small: true
                        icon: "close"
                        tip: "Fermer"
                        onClicked: lists.visible = false
                    }
                }
                Txt {
                    visible: Ilot.playlists.length === 0
                    text: "Aucune playlist enregistrée."
                    px: 11.5
                    color: Theme.inkVariant
                }
                Column {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: Ilot.playlists
                        Row {
                            required property var modelData
                            required property int index
                            width: plCol.width
                            spacing: 4
                            Btn {
                                width: parent.width - 30
                                height: 38
                                radius: hovered ? 18 : 12
                                Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                                color: Theme.surfaceHighest
                                tip: modelData.url
                                onClicked: {
                                    Api.invoke("open_url", { url: lists.plTarget(modelData.url) })
                                    Ilot.setMode("collapsed")
                                }
                                Row {
                                    x: 10
                                    spacing: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    Ms {
                                        name: lists.plIcon(modelData.url)
                                        color: Theme.primary
                                    }
                                    Txt {
                                        width: parent.parent.width - 50
                                        text: modelData.name
                                        elide: Text.ElideRight
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                            IconBtn {
                                small: true
                                icon: "close"
                                tip: "Retirer"
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: {
                                    const l = Ilot.playlists.slice()
                                    l.splice(index, 1)
                                    Ilot.playlists = l
                                    lists.save()
                                }
                            }
                        }
                    }
                }
                // ajout
                Column {
                    width: parent.width
                    spacing: 6
                    topPadding: 4
                    Field {
                        id: plName
                        width: parent.width
                        height: 38
                        radius: 10
                        pad: 10
                        bg: Theme.surfaceC
                        focusRing: true
                        placeholder: "Nom (ex. Chill)"
                        onFocused: Ilot.pinned = true
                        onAccepted: plUrl.input.forceActiveFocus()
                    }
                    Field {
                        id: plUrl
                        width: parent.width
                        height: 38
                        radius: 10
                        pad: 10
                        bg: Theme.surfaceC
                        focusRing: true
                        placeholder: "Lien Spotify, Deezer, YouTube…"
                        onFocused: Ilot.pinned = true
                        onEdited: bad = false
                        onAccepted: plAdd.clicked(null)
                    }
                    TextBtn {
                        id: plAdd
                        anchors.right: parent.right
                        primary: true
                        icon: "add"
                        text: "Ajouter"
                        onClicked: {
                            const url = plUrl.text.trim()
                            const name = plName.text.trim()
                            if (!name) {
                                plName.input.forceActiveFocus()
                                return
                            }
                            if (!/^(https?:\/\/|spotify:|deezer:\/\/)/.test(url)) {
                                plUrl.bad = true
                                return
                            }
                            Ilot.playlists = Ilot.playlists.concat([{ name: name, url: url }])
                            lists.save()
                            plName.text = ""
                            plUrl.text = ""
                        }
                    }
                }
                Txt {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Dans Spotify : clic droit sur une playlist › Partager › Copier le lien."
                    px: 11.5
                    lineHeight: 1.2
                    color: Theme.inkVariant
                }
            }
        }
    }
}
