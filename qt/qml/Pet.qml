import QtQuick
import QtQuick.Shapes

// Compagnon (Reglages > Compagnon) : dix especes dessinees en formes
// vectorielles (blob, chat, fantome, lapin, grenouille, pingouin, poussin,
// robot, axolotl, champignon), avec leurs expressions, leurs tours (saut,
// salto, pirouette, coucou, baillement, eternuement, danse...) et leurs
// accessoires (couleur, yeux, chapeau, visage, cou). Dans la pilule, son
// humeur vient de Watch (musique, jeu, chaleur, sommeil, fete...) ; il sert
// aussi a la promenade (PetWindow) et a l'apercu des reglages. Avec
// `interactive`, il se laisse toucher : clic, double clic, appui long
// (caresse), et il suit la souris des yeux.
Item {
    id: pet
    // ------------------------------------------- apparence (les reglages)
    property string species: Watch.petSpecies
    property string hat: Ilot.cfg.pet_hat || "none"
    property string faceAcc: Ilot.cfg.pet_face || "none"
    property string neck: Ilot.cfg.pet_neck || "none"
    property string eyeStyle: Ilot.cfg.pet_eyes || "dot"
    property string tint: Ilot.cfg.pet_color || "nature"
    // ------------------------------------------------------------ etat
    property string mood: Watch.mood
    property bool walking: false
    // regard (-1.5..1.5) : de cote, et vers le haut / le bas
    property real look: Watch.petLook
    property real lookY: 0
    property real k: 1
    // reagit aux signaux de Watch (compagnon de la pilule) ; sinon il cligne
    // des yeux et regarde autour de lui tout seul
    property bool listen: true
    property bool interactive: false
    property string tip: ""
    // expression imposee par une scene (happy, closed, wide, heart, dizzy,
    // wink, squint, star, sad, focus), accessoires de passage (bonnet de
    // nuit, lunettes de lecture), bouche ouverte (0..1), joues roses (0..1)
    property string face: ""
    property string tempHat: ""
    property string tempFace: ""
    property real mouthOpen: 0
    property real blush: 0
    // langue tiree (en pixels) et son angle (degres, 0 : vers la droite)
    property real tongue: 0
    property real tongueAngle: -30
    // dodelinement sur les basses (0..1)
    property real bop: mood === "music" ? (Ilot.shown.slice(0, 4).reduce((a, b) => a + b, 0) / 4) : 0
    // grand format (promenade, apercu) : details animes en plus
    readonly property bool rich: k >= 1.4
    readonly property size us: Qt.size(k, k)

    signal poked()
    signal caressed()

    width: 20 * k
    height: 18 * k

    // --------------------------------------------------------- couleurs
    function mixc(a, b, p) {
        a = Qt.lighter(a, 1)
        b = Qt.lighter(b, 1)
        return Qt.rgba(a.r * p + b.r * (1 - p), a.g * p + b.g * (1 - p), a.b * p + b.b * (1 - p), 1)
    }
    function luma(v) {
        v = Qt.lighter(v, 1)
        return 0.2126 * v.r + 0.7152 * v.g + 0.0722 * v.b
    }
    // couleurs naturelles : corps, ventre (ou museau, ecran...), yeux, details
    readonly property var natural: ({
        blob: { main: Theme.primary, belly: mixc(Theme.primary, "#ffffff", 0.55), ink: Theme.inkPrimary, detail: Qt.darker(Theme.primary, 1.25) },
        cat: { main: "#f4a259", belly: "#fde6cc", ink: "#2b211c", detail: "#d47634", inner: "#ff9fb4" },
        ghost: { main: "#f3f0fa", belly: "#ffffff", ink: "#2a2438", detail: "#c9bdf0" },
        bunny: { main: "#f1ebe3", belly: "#fffaf3", ink: "#2b2622", detail: "#dccfbf", inner: "#ffb1c6" },
        frog: { main: "#7cc65b", belly: "#dcf3b8", ink: "#1f2a17", detail: "#5a9e40" },
        penguin: { main: "#3c4363", belly: "#f7f6f1", ink: "#1a1c26", detail: "#2c3150", beak: "#ffa53a", rim: "#6d759e" },
        chick: { main: "#ffd447", belly: "#fff1b8", ink: "#3a2c10", detail: "#f0b01c", beak: "#ff9433" },
        robot: { main: "#bfc9d9", belly: "#1f2532", ink: "#6ff2ff", detail: "#8893aa" },
        axolotl: { main: "#f8b2c9", belly: "#ffe1ea", ink: "#3a1d29", detail: "#e2609a" },
        mush: { main: "#e4544b", belly: "#f6ead6", ink: "#3b2a22", detail: "#fff7ee" }
    })
    // especes dont les yeux sont poses sur le corps (sinon : ventre, ecran...)
    readonly property bool eyesOnMain: ["blob", "cat", "ghost", "bunny", "chick", "axolotl", "frog"].indexOf(species) >= 0
    readonly property var pal: {
        const n = natural[species] || natural.blob
        if (tint !== "theme" && !/^#[0-9a-f]{6}$/i.test(tint))
            return n
        const m = tint === "theme" ? Theme.primary : tint
        const p = Object.assign({}, n, { main: m, detail: Qt.darker(m, 1.3) })
        if (species !== "penguin" && species !== "robot" && species !== "mush")
            p.belly = mixc(m, "#ffffff", 0.5)
        if (eyesOnMain && species !== "frog")
            p.ink = tint === "theme" ? Theme.inkPrimary : luma(m) < 0.42 ? "#f6f2fb" : "#211b26"
        if (species === "penguin")
            p.rim = Qt.lighter(m, 1.6)
        return p
    }

    // ------------------------------------------------------- geometrie
    // en unites (boite de 20 x 18) : yeux [gauche, droite, hauteur], taille
    // des yeux, bouche, joues, chapeau [centre, haut, largeur], cou
    // [centre, hauteur, largeur], patte qui fait coucou
    readonly property var geos: ({
        blob: { eyes: [6.7, 13.3, 9.2], es: 1, mouth: [10, 12.1], cheeks: [4.5, 15.5, 11.6], hat: [10, 2.0, 9.5], neck: [10, 15.6, 13], paw: [17.6, 12.6] },
        cat: { eyes: [7.1, 12.9, 7.4], es: 0.95, mouth: [10, 9.9], cheeks: [5.2, 14.8, 9.6], hat: [10, 2.6, 8.5], neck: [10, 12.6, 8.5], paw: [15.4, 14.4], mk: "cat" },
        ghost: { eyes: [7.3, 12.7, 8.0], es: 1.05, mouth: [10, 11.4], cheeks: [5.3, 14.7, 10.6], hat: [10, 1.7, 9.5], neck: [10, 13.0, 13], paw: [18.2, 11.2] },
        bunny: { eyes: [6.9, 13.1, 9.0], es: 1, mouth: [10, 11.3], cheeks: [4.9, 15.1, 11.2], hat: [10, 4.3, 8.5], neck: [10, 13.4, 12], paw: [17.2, 13.6] },
        frog: { eyes: [5.6, 14.4, 6.8], es: 0.95, mouth: [10, 11.0], cheeks: [3.8, 16.2, 12.2], hat: [10, 4.0, 11], neck: [10, 14.4, 15], paw: [18.4, 14.2], mk: "wide" },
        penguin: { eyes: [7.7, 12.3, 7.6], es: 0.9, mouth: [10, 9.9], cheeks: [6.2, 13.8, 10.4], hat: [10, 1.6, 9], neck: [10, 12.2, 10], paw: [17.6, 11.6], beak: true },
        chick: { eyes: [7.4, 12.6, 8.8], es: 0.95, mouth: [10, 10.4], cheeks: [5.4, 14.6, 11.4], hat: [10, 4.4, 9], neck: [10, 14.4, 11], paw: [16.8, 12.8], beak: true },
        robot: { eyes: [7.5, 12.5, 8.4], es: 1, mouth: [10, 11.4], cheeks: [5.6, 14.4, 11.6], hat: [10, 3.8, 11], neck: [10, 16.2, 13], paw: [18.6, 10.8], mk: "led" },
        axolotl: { eyes: [5.8, 14.2, 8.4], es: 0.9, mouth: [10, 10.8], cheeks: [4.4, 15.6, 10.8], hat: [10, 3.8, 9.5], neck: [10, 13.4, 9.5], paw: [15.6, 15.4] },
        mush: { eyes: [8.2, 11.8, 13.6], es: 0.8, mouth: [10, 15.6], cheeks: [6.9, 13.1, 15.1], hat: [10, 1.0, 9.5], neck: [10, 17.2, 9.5], paw: [15.4, 14.8] }
    })
    readonly property var geo: geos[species] || geos.blob
    function circ(cx, cy, r) {
        return `M${cx - r} ${cy} A${r} ${r} 0 1 1 ${cx + r} ${cy} A${r} ${r} 0 1 1 ${cx - r} ${cy} Z`
    }

    // ------------------------------------------------------ expression
    property string trickFace: ""
    property real trickMouth: 0
    property real trickBlush: 0
    property real trickLook: 0
    property bool dizzy: false
    property bool petting: false
    property real eyeOpen: 1
    readonly property string moodFace: ({ party: "happy", surprise: "wide", sleep: "closed", hot: "squint", love: "heart", cold: "sad", game: "focus" })[mood] || ""
    readonly property string expr: trickFace !== "" ? trickFace : face !== "" ? face : moodFace
    readonly property real mouthAmt: Math.max(trickMouth, mouthOpen, mood === "music" ? Math.min(1, bop * 1.5) : 0,
        expr === "wide" ? 0.7 : 0, mood === "hot" && trickFace === "" ? 0.35 : 0)
    readonly property string mouthKind: geo.beak ? "beak" : geo.mk === "led" ? "led" : mouthAmt > 0.08 ? "open"
        : expr === "happy" || expr === "heart" || expr === "star" ? "grin" : expr === "sad" ? "frown"
        : expr === "focus" || expr === "closed" ? "flat" : geo.mk || "smile"
    readonly property real eyeX: Math.max(-1.6, Math.min(1.6, touch.containsMouse ? touch.lx : look + trickLook))
    readonly property real eyeY: touch.containsMouse ? touch.ly : lookY
    readonly property string hatShown: tempHat !== "" ? tempHat : hat !== "none" ? hat
        : mood === "game" || mood === "hot" ? "headset" : mood === "sleep" ? "nightcap" : ""
    readonly property string faceShown: tempFace !== "" ? tempFace : faceAcc

    // ------------------------------------------------------ signaux
    Connections {
        target: Watch
        enabled: pet.listen
        function onPetFx(sym) { pet.fx(sym) }
        function onPetBlink() { pet.doBlink() }
        function onPetHop() { pet.trick("hop") }
        function onPetTrick(name) { pet.trick(name) }
    }
    // tout seul : clignement, coup d'oeil, oreille qui bouge
    property real idleLook: 0
    Timer {
        running: pet.visible && !pet.listen && !Theme.reduced
        repeat: true
        interval: 2600
        onTriggered: {
            interval = 1800 + Math.random() * 3200
            if (Math.random() < 0.7)
                pet.doBlink()
            if (Math.random() < 0.3)
                twitchAnim.restart()
        }
    }

    // --------------------------------------------------------- ombre
    Rectangle {
        visible: pet.rich
        readonly property real up: Math.max(0, -body.hopY / pet.k - pet.floatY)
        width: 13 * pet.k * Math.max(0.4, 1 - up / 30)
        height: 2.2 * pet.k
        radius: height / 2
        x: (pet.width - width) / 2
        y: pet.height - height / 2
        color: "#000000"
        opacity: 0.16 * Math.max(0.3, 1 - up / 30)
    }
    // le fantome flotte
    readonly property real floatY: species === "ghost" ? -1.4 + (rich ? Math.sin(body.phase) : body.breathe * 2 - 1) * 1.1 : 0

    // ---------------------------------------------------------- corps
    Item {
        id: body
        width: pet.width
        height: pet.height
        transformOrigin: Item.Bottom
        // respiration, phase des details animes (queue, oreilles...),
        // dandinement en marchant, et les valeurs des tours
        property real breathe: 0
        property real phase: 0
        property real hopY: 0
        property real wad: 0
        property real sx: 1
        property real sy: 1
        property real rot: 0
        property real lean: 0
        property real spin: 1
        property real shake: 0
        property real jig: 0
        property real twitch: 0
        property bool waving: false
        property real pawRot: 0
        SequentialAnimation on breathe {
            running: pet.visible && !Theme.reduced
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: pet.mood === "sleep" ? 2500 : 1600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: pet.mood === "sleep" ? 2500 : 1600; easing.type: Easing.InOutSine }
        }
        NumberAnimation on phase {
            running: pet.visible && pet.rich && !Theme.reduced
            from: 0
            to: Math.PI * 2
            duration: 2400
            loops: Animation.Infinite
        }
        SequentialAnimation on wad {
            running: pet.walking || pet.mood === "party"
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 200; easing.type: Easing.InOutSine }
            NumberAnimation { to: -1; duration: 400; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 200; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) body.wad = 0
        }
        rotation: wad * 7 + lean
        transform: [
            Scale {
                origin.x: body.width / 2
                origin.y: body.height
                xScale: (1 + body.breathe * 0.04 + pet.bop * 0.08) * body.sx
                yScale: (1 - body.breathe * 0.04 - pet.bop * 0.12) * body.sy
            },
            Scale {
                origin.x: body.width / 2
                xScale: body.spin
            },
            Rotation {
                origin.x: body.width / 2
                origin.y: body.height / 2
                angle: body.rot
            },
            Translate {
                x: body.shake * pet.k
                y: body.hopY + pet.floatY * pet.k - Math.abs(body.wad) * 2 * pet.k
            }
        ]

        // l'espece
        Loader {
            anchors.fill: parent
            sourceComponent: ({ blob: blobC, cat: catC, ghost: ghostC, bunny: bunnyC, frog: frogC, penguin: penguinC,
                chick: chickC, robot: robotC, axolotl: axolotlC, mush: mushC })[pet.species] || blobC
        }

        // joues roses (et taches de rousseur)
        Repeater {
            model: 2
            Rectangle {
                required property int index
                readonly property real a: Math.max(pet.blush, pet.trickBlush, pet.faceShown === "blush" ? 0.55 : 0,
                    pet.mood === "party" || pet.mood === "love" ? 0.5 : 0, pet.mood === "hot" ? 0.7 : 0, pet.species === "axolotl" ? 0.3 : 0)
                visible: a > 0.01
                width: 2.8 * pet.k
                height: 1.6 * pet.k
                radius: height / 2
                x: (pet.geo.cheeks[index] - 1.4) * pet.k
                y: (pet.geo.cheeks[2] - 0.8) * pet.k
                color: "#ff6f91"
                opacity: a * 0.75
            }
        }
        // loup (sous les yeux)
        Loader {
            anchors.fill: parent
            active: pet.faceShown === "mask"
            sourceComponent: faMask
        }
        // yeux
        Repeater {
            model: 2
            Eye {
                required property int index
                u: pet.k * pet.geo.es
                style: pet.eyeStyle
                expr: pet.expr === "wink" ? (index === 1 ? "happy" : "") : pet.expr
                flip: index === 1
                ink: pet.pal.ink
                lid: pet.eyesOnMain ? pet.pal.main : pet.pal.belly
                open: pet.eyeOpen
                x: pet.geo.eyes[index] * pet.k - width / 2 + pet.eyeX * 0.8 * pet.k
                y: pet.geo.eyes[2] * pet.k - height / 2 + pet.eyeY * 0.6 * pet.k
            }
        }
        // bouche
        Item {
            id: mouth
            visible: pet.mouthKind !== "beak" && pet.mouthKind !== "led"
            x: (pet.geo.mouth[0] - 2) * pet.k
            y: (pet.geo.mouth[1] - 1) * pet.k
            width: 4 * pet.k
            height: 3 * pet.k
            readonly property var paths: ({
                smile: "M1.2 0.8 Q2 1.7 2.8 0.8",
                flat: "M1.3 1.1 L2.7 1.1",
                frown: "M1.2 1.5 Q2 0.7 2.8 1.5",
                cat: "M0.9 0.7 Q1.45 1.5 2 0.7 Q2.55 1.5 3.1 0.7",
                wide: "M-1.6 0.4 Q2 2.6 5.6 0.4"
            })
            Shape {
                anchors.fill: parent
                visible: !!mouth.paths[pet.mouthKind]
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    scale: pet.us
                    fillColor: "transparent"
                    strokeColor: pet.pal.ink
                    strokeWidth: 0.55 * pet.k
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: mouth.paths[pet.mouthKind] || "M0 0" }
                }
            }
            // sourire ouvert
            Shape {
                anchors.fill: parent
                visible: pet.mouthKind === "grin"
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: "#3a1a26"
                    PathSvg { path: "M1 0.6 L3 0.6 Q3 2.3 2 2.3 Q1 2.3 1 0.6 Z" }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: "#ff7a95"
                    PathSvg { path: "M1.45 1.85 Q2 1.35 2.55 1.85 Q2 2.25 1.45 1.85 Z" }
                }
            }
            // bouche ouverte (chant, baillement, surprise)
            Rectangle {
                visible: pet.mouthKind === "open"
                width: (1.3 + 0.7 * pet.mouthAmt) * pet.k
                height: (0.5 + 1.9 * pet.mouthAmt) * pet.k
                radius: Math.min(width, height) / 2
                x: (parent.width - width) / 2
                y: 0.5 * pet.k
                color: "#3a1a26"
                clip: true
                Rectangle {
                    width: parent.width * 0.8
                    height: parent.height * 0.6
                    radius: height / 2
                    x: (parent.width - width) / 2
                    y: parent.height * 0.55
                    color: "#ff7a95"
                }
            }
        }
        // langue tiree (grenouille qui attrape une mouche, « blep »)
        Rectangle {
            visible: pet.tongue > 0.5
            x: pet.geo.mouth[0] * pet.k
            y: (pet.geo.mouth[1] + 0.6) * pet.k - height / 2
            width: pet.tongue
            height: 1.1 * pet.k
            radius: height / 2
            color: "#ff6f8e"
            transformOrigin: Item.Left
            rotation: pet.tongueAngle
            Rectangle {
                width: 2 * pet.k
                height: width
                radius: width / 2
                x: parent.width - width * 0.7
                y: (parent.height - height) / 2
                color: "#ff6f8e"
            }
        }
        // accessoires : visage, cou, chapeau
        Loader {
            anchors.fill: parent
            sourceComponent: ({ glasses: faGlasses, sun: faSun, monocle: faMonocle, freckles: faFreckles })[pet.faceShown] || null
        }
        Loader {
            anchors.fill: parent
            sourceComponent: ({ bowtie: nkBowtie, scarf: nkScarf, bell: nkBell, bandana: nkBandana })[pet.neck] || null
        }
        Item {
            id: hatBox
            readonly property real s: pet.geo.hat[2] / 10
            readonly property size hs: Qt.size(pet.k * s, pet.k * s)
            x: (pet.geo.hat[0] - 5 * s) * pet.k
            y: (pet.geo.hat[1] - 7.2 * s) * pet.k
            width: 10 * s * pet.k
            height: 8 * s * pet.k
            Loader {
                anchors.fill: parent
                sourceComponent: ({ party: hatParty, crown: hatCrown, cap: hatCap, beanie: hatBeanie, top: hatTop, wizard: hatWizard,
                    flower: hatFlower, bow: hatBow, halo: hatHalo, horns: hatHorns, headset: hatHeadset, headphones: hatHeadset,
                    nightcap: hatNightcap, chef: hatChef })[pet.hatShown] || null
            }
        }
        // patte qui fait coucou
        Rectangle {
            visible: body.waving
            width: 3 * pet.k
            height: 4.4 * pet.k
            radius: width / 2
            x: (pet.geo.paw[0] - 1.5) * pet.k
            y: (pet.geo.paw[1] - 4.4) * pet.k
            color: pet.pal.main
            border.width: 0.4 * pet.k
            border.color: pet.pal.detail
            transformOrigin: Item.Bottom
            rotation: 15 + body.pawRot
        }
        // etoiles qui tournent (etourdi)
        Item {
            id: orbit
            visible: pet.dizzy
            x: pet.geo.hat[0] * pet.k
            y: (pet.geo.hat[1] - 1.5) * pet.k
            property real a: 0
            NumberAnimation on a {
                running: orbit.visible
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
            }
            Repeater {
                model: 3
                Txt {
                    required property int index
                    readonly property real t: (orbit.a + index * 120) * Math.PI / 180
                    text: "✦"
                    px: 5 * pet.k
                    color: "#ffd84a"
                    x: Math.cos(t) * 6 * pet.k - width / 2
                    y: Math.sin(t) * 1.8 * pet.k - height / 2
                    opacity: 0.55 + 0.45 * Math.sin(t)
                }
            }
        }
    }

    // ---------------------------------------------------- toucher
    MouseArea {
        id: touch
        enabled: pet.interactive
        visible: enabled
        anchors.fill: parent
        anchors.margins: -3 * pet.k
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        pressAndHoldInterval: 450
        cursorShape: pet.petting ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        // regard vers la souris
        property real lx: 0
        property real ly: 0
        onPositionChanged: m => {
            lx = Math.max(-1.6, Math.min(1.6, (m.x - width / 2) / (width / 2) * 2))
            ly = Math.max(-1, Math.min(1, (m.y - height / 2) / (height / 2) * 1.5))
        }
        onClicked: pet.poke()
        onDoubleClicked: pet.trick("flip")
        onPressAndHold: pet.caress(true)
        onReleased: if (pet.petting) pet.caress(false)
        onCanceled: if (pet.petting) pet.caress(false)
    }
    Tip {
        text: pet.tip
        shown: pet.interactive && touch.containsMouse && !touch.pressed
    }
    property int pokes: 0
    property real lastPoke: 0
    function poke() {
        const now = Date.now()
        pokes = now - lastPoke < 900 ? pokes + 1 : 1
        lastPoke = now
        poked()
        // trop de clics d'affilee : la tete lui tourne
        if (pokes >= 5) {
            pokes = 0
            fx("!")
            return trick("dizzy")
        }
        const list = ["hop", "giggle", "spin", "surprise", "love", "wave", "jump", "nod", "dance"]
        if (species === "ghost")
            list.push("boo")
        if (species === "blob" || species === "ghost")
            list.push("melt")
        trick(list[Math.floor(Math.random() * list.length)])
    }
    // caresse : il ronronne, se balance et rougit
    property int purrs: 0
    function caress(on) {
        if (on) {
            stopTricks()
            petting = true
            trickFace = "happy"
            trickBlush = 0.9
            purrs = 0
            caressed()
        } else {
            petting = false
            trickFace = ""
            trickBlush = 0
            body.lean = 0
            fx("♥", { color: "#ff5d8f" })
        }
    }
    Timer {
        interval: 650
        repeat: true
        running: pet.petting
        onTriggered: {
            pet.fx(Math.random() < 0.75 ? "♥" : "♪", { color: "#ff5d8f", dx: Math.random() * 6 - 3, x: 8 + Math.random() * 6 })
            if (++pet.purrs % 3 === 0)
                pet.caressed()
        }
    }
    SequentialAnimation {
        running: pet.petting
        loops: Animation.Infinite
        NumberAnimation { target: body; property: "lean"; to: -5; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { target: body; property: "lean"; to: 5; duration: 500; easing.type: Easing.InOutSine }
    }

    // ------------------------------------------------------ effets
    // notes, z, coeurs, gouttes... qui s'envolent (12 au plus a la fois)
    property int fxLive: 0
    function fx(sym, o) {
        if (fxLive >= 12 || !visible)
            return
        o = o || {}
        const x0 = (o.x !== undefined ? o.x : 16 + Math.random() * 2) * k
        const y0 = (o.y !== undefined ? o.y : -2) * k
        const hearts = sym === "♥"
        fxComp.createObject(pet, {
            text: sym, x: x0, y: y0, x1: x0 + (o.dx !== undefined ? o.dx : Math.random() * 4 - 1) * k,
            y1: y0 - (o.rise !== undefined ? o.rise : 14) * k, life: o.life || 1600,
            color: o.color || (hearts ? "#ff5d8f" : Theme.primary), px: (o.size || 9) * k
        })
    }
    function burst(sym, n, o) {
        for (let i = 0; i < n; i++)
            fx(sym, Object.assign({ x: 4 + Math.random() * 12, dx: (Math.random() - 0.5) * 12, rise: 10 + Math.random() * 10, life: 1300 + Math.random() * 700 }, o || {}))
    }
    Component {
        id: fxComp
        Txt {
            id: p
            property real x1
            property real y1
            property int life: 1600
            weight: Font.DemiBold
            opacity: 0
            z: 10
            Component.onCompleted: {
                pet.fxLive++
                fxAnim.start()
            }
            Component.onDestruction: pet.fxLive--
            ParallelAnimation {
                id: fxAnim
                SequentialAnimation {
                    NumberAnimation { target: p; property: "opacity"; to: 1; duration: p.life * 0.18 }
                    NumberAnimation { target: p; property: "opacity"; to: 0; duration: p.life * 0.82; easing.type: Easing.InQuad }
                }
                NumberAnimation { target: p; property: "y"; to: p.y1; duration: p.life; easing.type: Easing.OutQuad }
                NumberAnimation { target: p; property: "x"; to: p.x1; duration: p.life; easing.type: Easing.OutSine }
                onFinished: p.destroy()
            }
        }
    }

    // ---------------------------------------------------- clignement
    function doBlink() {
        blinkAnim.restart()
        if (Math.random() < 0.2)
            twitchAnim.restart()
    }
    function hop() {
        trick("hop")
    }
    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: pet; property: "eyeOpen"; to: 0.1; duration: 70 }
        NumberAnimation { target: pet; property: "eyeOpen"; to: 1; duration: 110 }
    }
    SequentialAnimation {
        id: twitchAnim
        NumberAnimation { target: body; property: "twitch"; to: 1; duration: 80 }
        NumberAnimation { target: body; property: "twitch"; to: 0; duration: 260; easing.type: Easing.OutBack }
    }
    // gelee qui tremblote a l'atterrissage
    function wobble() {
        jigAnim.restart()
    }
    SequentialAnimation {
        id: jigAnim
        NumberAnimation { target: body; property: "jig"; to: 1; duration: 90 }
        NumberAnimation { target: body; property: "jig"; to: -0.6; duration: 140 }
        NumberAnimation { target: body; property: "jig"; to: 0.3; duration: 140 }
        NumberAnimation { target: body; property: "jig"; to: 0; duration: 160 }
    }

    // -------------------------------------------------------- tours
    // trick(nom) lance un tour et rend sa duree (ms)
    readonly property var trickAnims: ({
        hop: tHop, jump: tJump, flip: tFlip, spin: tSpin, wave: tWave, stretch: tStretch, yawn: tYawn, sneeze: tSneeze,
        shake: tShake, dance: tDance, love: tLove, dizzy: tDizzy, giggle: tGiggle, nod: tNod, eat: tEat, melt: tMelt,
        surprise: tSurprise, kick: tKick, land: tLand, peck: tPeck, sad: tSad, shiver: tShiver, look: tLook, boo: tBoo,
        crouch: tCrouch, blep: tBlep
    })
    readonly property var trickMs: ({
        hop: 500, jump: 1000, flip: 1300, spin: 800, wave: 1500, stretch: 1700, yawn: 2000, sneeze: 1300, shake: 800,
        dance: 2600, love: 2000, dizzy: 2600, giggle: 900, nod: 700, eat: 1700, melt: 2400, surprise: 900, kick: 450,
        land: 400, peck: 550, sad: 1800, shiver: 1300, look: 2400, boo: 1400, crouch: 900, blep: 1600
    })
    function trick(name) {
        const a = trickAnims[name]
        if (!a || petting)
            return 0
        stopTricks()
        a.start()
        return trickMs[name]
    }
    function stopTricks() {
        for (const n in trickAnims)
            trickAnims[n].stop()
        body.hopY = 0
        body.sx = 1
        body.sy = 1
        body.rot = 0
        body.lean = 0
        body.spin = 1
        body.shake = 0
        body.waving = false
        body.pawRot = 0
        trickFace = ""
        trickMouth = 0
        trickBlush = 0
        trickLook = 0
        dizzy = false
        if (!petting)
            tongue = 0
    }

    SequentialAnimation {
        id: tHop
        NumberAnimation { target: body; property: "hopY"; to: -6 * pet.k; duration: 200; easing.type: Easing.OutQuad }
        NumberAnimation { target: body; property: "hopY"; to: 0; duration: 300; easing.type: Easing.OutBounce }
    }
    SequentialAnimation {
        id: tJump
        Squash { t: body; w: 1.15; h: 0.8; ms: 130 }
        ParallelAnimation {
            NumberAnimation { target: body; property: "hopY"; to: -13 * pet.k; duration: 280; easing.type: Easing.OutQuad }
            Squash { t: body; w: 0.9; h: 1.12; ms: 160 }
        }
        ParallelAnimation {
            NumberAnimation { target: body; property: "hopY"; to: 0; duration: 260; easing.type: Easing.InQuad }
            Squash { t: body; w: 1; h: 1; ms: 200 }
        }
        Squash { t: body; w: 1.2; h: 0.8; ms: 80 }
        Squash { t: body; w: 1; h: 1; ms: 250; ease: Easing.OutBack }
        ScriptAction { script: pet.wobble() }
    }
    SequentialAnimation {
        id: tFlip
        Squash { t: body; w: 1.15; h: 0.8; ms: 130 }
        PropertyAction { target: pet; property: "trickFace"; value: "happy" }
        ParallelAnimation {
            Squash { t: body; w: 1; h: 1; ms: 200 }
            SequentialAnimation {
                NumberAnimation { target: body; property: "hopY"; to: -17 * pet.k; duration: 380; easing.type: Easing.OutQuad }
                NumberAnimation { target: body; property: "hopY"; to: 0; duration: 340; easing.type: Easing.InQuad }
            }
            NumberAnimation { target: body; property: "rot"; from: 0; to: 360; duration: 700; easing.type: Easing.InOutQuad }
        }
        PropertyAction { target: body; property: "rot"; value: 0 }
        Squash { t: body; w: 1.2; h: 0.78; ms: 80 }
        Squash { t: body; w: 1; h: 1; ms: 280; ease: Easing.OutBack }
        ScriptAction { script: { pet.wobble(); pet.fx("✦", { color: "#ffd84a" }) } }
        PauseAnimation { duration: 200 }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tSpin
        PropertyAction { target: pet; property: "trickFace"; value: "happy" }
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: body; property: "hopY"; to: -4 * pet.k; duration: 300; easing.type: Easing.OutQuad }
                NumberAnimation { target: body; property: "hopY"; to: 0; duration: 380; easing.type: Easing.OutBounce }
            }
            SequentialAnimation {
                loops: 2
                NumberAnimation { target: body; property: "spin"; to: -1; duration: 170; easing.type: Easing.InOutSine }
                NumberAnimation { target: body; property: "spin"; to: 1; duration: 170; easing.type: Easing.InOutSine }
            }
        }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tWave
        PropertyAction { target: body; property: "waving"; value: true }
        PropertyAction { target: pet; property: "trickFace"; value: "happy" }
        NumberAnimation { target: body; property: "lean"; to: -6; duration: 150 }
        SequentialAnimation {
            loops: 3
            NumberAnimation { target: body; property: "pawRot"; to: 25; duration: 170; easing.type: Easing.InOutSine }
            NumberAnimation { target: body; property: "pawRot"; to: -15; duration: 170; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
            NumberAnimation { target: body; property: "lean"; to: 0; duration: 200 }
            NumberAnimation { target: body; property: "pawRot"; to: 0; duration: 200 }
        }
        PropertyAction { target: body; property: "waving"; value: false }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tStretch
        PropertyAction { target: pet; property: "trickFace"; value: "closed" }
        Squash { t: body; w: 0.86; h: 1.25; ms: 550 }
        PauseAnimation { duration: 450 }
        Squash { t: body; w: 1.15; h: 0.84; ms: 140 }
        Squash { t: body; w: 1; h: 1; ms: 350; ease: Easing.OutBack }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
        ScriptAction { script: pet.fx("✧") }
    }
    SequentialAnimation {
        id: tYawn
        PropertyAction { target: pet; property: "trickFace"; value: "closed" }
        ParallelAnimation {
            NumberAnimation { target: pet; property: "trickMouth"; to: 1; duration: 600; easing.type: Easing.OutQuad }
            Squash { t: body; w: 0.95; h: 1.08; ms: 600 }
        }
        PauseAnimation { duration: 600 }
        ParallelAnimation {
            NumberAnimation { target: pet; property: "trickMouth"; to: 0; duration: 400 }
            Squash { t: body; w: 1; h: 1; ms: 400 }
        }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
        ScriptAction { script: pet.doBlink() }
    }
    SequentialAnimation {
        id: tSneeze
        ParallelAnimation {
            Squash { t: body; w: 0.92; h: 1.12; ms: 450 }
            NumberAnimation { target: pet; property: "trickMouth"; to: 0.5; duration: 450 }
        }
        PropertyAction { target: pet; property: "trickFace"; value: "squint" }
        PauseAnimation { duration: 150 }
        ParallelAnimation {
            Squash { t: body; w: 1.2; h: 0.78; ms: 80 }
            NumberAnimation { target: pet; property: "trickMouth"; to: 1; duration: 80 }
        }
        ScriptAction { script: pet.fx("💨", { x: 15, y: 8, dx: 8, rise: 2, life: 900 }) }
        SequentialAnimation {
            loops: 3
            NumberAnimation { target: body; property: "shake"; to: 0.8; duration: 40 }
            NumberAnimation { target: body; property: "shake"; to: -0.8; duration: 40 }
        }
        ParallelAnimation {
            Squash { t: body; w: 1; h: 1; ms: 300; ease: Easing.OutBack }
            NumberAnimation { target: pet; property: "trickMouth"; to: 0; duration: 200 }
            NumberAnimation { target: body; property: "shake"; to: 0; duration: 80 }
        }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tShake
        PropertyAction { target: pet; property: "trickFace"; value: "squint" }
        SequentialAnimation {
            loops: 5
            NumberAnimation { target: body; property: "lean"; to: 9; duration: 55 }
            NumberAnimation { target: body; property: "lean"; to: -9; duration: 55 }
        }
        NumberAnimation { target: body; property: "lean"; to: 0; duration: 80 }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tDance
        PropertyAction { target: pet; property: "trickFace"; value: "happy" }
        SequentialAnimation {
            loops: 2
            NumberAnimation { target: body; property: "lean"; to: -14; duration: 220; easing.type: Easing.InOutSine }
            ParallelAnimation {
                NumberAnimation { target: body; property: "lean"; to: 14; duration: 300; easing.type: Easing.InOutSine }
                SequentialAnimation {
                    NumberAnimation { target: body; property: "hopY"; to: -4 * pet.k; duration: 150; easing.type: Easing.OutQuad }
                    NumberAnimation { target: body; property: "hopY"; to: 0; duration: 150; easing.type: Easing.InQuad }
                }
            }
            NumberAnimation { target: body; property: "lean"; to: 0; duration: 160 }
        }
        ScriptAction { script: pet.fx("♪") }
        NumberAnimation { target: body; property: "spin"; to: -1; duration: 160; easing.type: Easing.InOutSine }
        NumberAnimation { target: body; property: "spin"; to: 1; duration: 160; easing.type: Easing.InOutSine }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tLove
        PropertyAction { target: pet; property: "trickFace"; value: "heart" }
        NumberAnimation { target: pet; property: "trickBlush"; to: 1; duration: 300 }
        ScriptAction { script: pet.burst("♥", 3) }
        SequentialAnimation {
            loops: 2
            NumberAnimation { target: body; property: "lean"; to: -5; duration: 300; easing.type: Easing.InOutSine }
            NumberAnimation { target: body; property: "lean"; to: 5; duration: 300; easing.type: Easing.InOutSine }
        }
        NumberAnimation { target: body; property: "lean"; to: 0; duration: 200 }
        NumberAnimation { target: pet; property: "trickBlush"; to: 0; duration: 300 }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tDizzy
        PropertyAction { target: pet; property: "trickFace"; value: "dizzy" }
        PropertyAction { target: pet; property: "dizzy"; value: true }
        NumberAnimation { target: body; property: "lean"; to: -12; duration: 220; easing.type: Easing.InOutSine }
        NumberAnimation { target: body; property: "lean"; to: 10; duration: 280; easing.type: Easing.InOutSine }
        NumberAnimation { target: body; property: "lean"; to: -7; duration: 320; easing.type: Easing.InOutSine }
        NumberAnimation { target: body; property: "lean"; to: 5; duration: 360; easing.type: Easing.InOutSine }
        NumberAnimation { target: body; property: "lean"; to: -2; duration: 400; easing.type: Easing.InOutSine }
        NumberAnimation { target: body; property: "lean"; to: 0; duration: 400; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 300 }
        PropertyAction { target: pet; property: "dizzy"; value: false }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tGiggle
        PropertyAction { target: pet; property: "trickFace"; value: "happy" }
        PropertyAction { target: pet; property: "trickMouth"; value: 0.4 }
        SequentialAnimation {
            loops: 4
            NumberAnimation { target: body; property: "hopY"; to: -1.6 * pet.k; duration: 90 }
            NumberAnimation { target: body; property: "hopY"; to: 0; duration: 90 }
        }
        ScriptAction { script: pet.fx("hi hi", { size: 6, color: Theme.tertiary }) }
        PropertyAction { target: pet; property: "trickMouth"; value: 0 }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tNod
        loops: 2
        Squash { t: body; w: 1.05; h: 0.9; ms: 160 }
        Squash { t: body; w: 1; h: 1; ms: 160 }
    }
    SequentialAnimation {
        id: tEat
        SequentialAnimation {
            loops: 3
            NumberAnimation { target: pet; property: "trickMouth"; to: 1; duration: 140 }
            ParallelAnimation {
                NumberAnimation { target: pet; property: "trickMouth"; to: 0; duration: 160 }
                Squash { t: body; w: 1.08; h: 0.94; ms: 160 }
            }
            ScriptAction { script: pet.fx("·", { x: 9 + Math.random() * 3, y: 12, dx: Math.random() * 6 - 3, rise: -5, life: 700, color: "#c8925a", size: 10 }) }
        }
        Squash { t: body; w: 1; h: 1; ms: 150 }
        PropertyAction { target: pet; property: "trickFace"; value: "happy" }
        ScriptAction { script: pet.fx("♥") }
        PauseAnimation { duration: 400 }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tMelt
        PropertyAction { target: pet; property: "trickFace"; value: "closed" }
        Squash { t: body; w: 1.5; h: 0.45; ms: 800; ease: Easing.InOutQuad }
        PauseAnimation { duration: 500 }
        Squash { t: body; w: 0.9; h: 1.15; ms: 350 }
        Squash { t: body; w: 1; h: 1; ms: 600; ease: Easing.OutElastic }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tSurprise
        PropertyAction { target: pet; property: "trickFace"; value: "wide" }
        ScriptAction { script: pet.fx("!", { color: Theme.tertiary }) }
        NumberAnimation { target: body; property: "hopY"; to: -5 * pet.k; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: body; property: "hopY"; to: 0; duration: 260; easing.type: Easing.OutBounce }
        PauseAnimation { duration: 400 }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tKick
        ParallelAnimation {
            NumberAnimation { target: body; property: "lean"; to: 16; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: body; property: "hopY"; to: -3 * pet.k; duration: 110 }
        }
        ParallelAnimation {
            NumberAnimation { target: body; property: "lean"; to: 0; duration: 280; easing.type: Easing.OutBack }
            NumberAnimation { target: body; property: "hopY"; to: 0; duration: 200; easing.type: Easing.InQuad }
        }
    }
    SequentialAnimation {
        id: tLand
        Squash { t: body; w: 1.22; h: 0.76; ms: 80 }
        Squash { t: body; w: 1; h: 1; ms: 300; ease: Easing.OutBack }
        ScriptAction { script: pet.wobble() }
    }
    SequentialAnimation {
        id: tPeck
        loops: 2
        NumberAnimation { target: body; property: "lean"; to: 28; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: body; property: "lean"; to: 0; duration: 140; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
        id: tSad
        PropertyAction { target: pet; property: "trickFace"; value: "sad" }
        Squash { t: body; w: 1.04; h: 0.92; ms: 400 }
        ScriptAction { script: pet.fx("…", { color: Theme.inkVariant }) }
        PauseAnimation { duration: 900 }
        Squash { t: body; w: 1; h: 1; ms: 400 }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tShiver
        PropertyAction { target: pet; property: "trickFace"; value: "sad" }
        ScriptAction { script: pet.fx("❄", { color: "#9fd8ff" }) }
        SequentialAnimation {
            loops: 8
            NumberAnimation { target: body; property: "shake"; to: 0.6; duration: 35 }
            NumberAnimation { target: body; property: "shake"; to: -0.6; duration: 35 }
        }
        NumberAnimation { target: body; property: "shake"; to: 0; duration: 40 }
        PauseAnimation { duration: 500 }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tLook
        NumberAnimation { target: pet; property: "trickLook"; to: -1.6; duration: 300; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 500 }
        NumberAnimation { target: pet; property: "trickLook"; to: 1.6; duration: 500; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 500 }
        NumberAnimation { target: pet; property: "trickLook"; to: 0; duration: 300; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        id: tBoo
        PropertyAction { target: pet; property: "trickFace"; value: "wide" }
        ParallelAnimation {
            Squash { t: body; w: 1.4; h: 1.4; ms: 220; ease: Easing.OutBack }
            NumberAnimation { target: pet; property: "trickMouth"; to: 1; duration: 220 }
        }
        ScriptAction { script: pet.fx("BOU !", { size: 7, x: 13, color: Theme.tertiary }) }
        PauseAnimation { duration: 500 }
        ParallelAnimation {
            Squash { t: body; w: 1; h: 1; ms: 350 }
            NumberAnimation { target: pet; property: "trickMouth"; to: 0; duration: 300 }
        }
        PropertyAction { target: pet; property: "trickFace"; value: "happy" }
        PauseAnimation { duration: 300 }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }
    SequentialAnimation {
        id: tCrouch
        Squash { t: body; w: 1.12; h: 0.82; ms: 250 }
        SequentialAnimation {
            loops: 3
            NumberAnimation { target: body; property: "lean"; to: -4; duration: 80 }
            NumberAnimation { target: body; property: "lean"; to: 4; duration: 80 }
        }
        NumberAnimation { target: body; property: "lean"; to: 0; duration: 60 }
        Squash { t: body; w: 1; h: 1; ms: 120 }
    }
    SequentialAnimation {
        id: tBlep
        PropertyAction { target: pet; property: "tongueAngle"; value: 75 }
        NumberAnimation { target: pet; property: "tongue"; to: 2.4 * pet.k; duration: 200; easing.type: Easing.OutBack }
        PropertyAction { target: pet; property: "trickFace"; value: "wink" }
        PauseAnimation { duration: 1000 }
        NumberAnimation { target: pet; property: "tongue"; to: 0; duration: 200 }
        PropertyAction { target: pet; property: "trickFace"; value: "" }
    }

    // ------------------------------------------------------ especes
    // chaque espece dessine son corps ; les yeux, la bouche, les joues et
    // les accessoires viennent par-dessus (geometrie : `geos`)
    Component {
        id: blobC
        Shape {
            id: bl
            preferredRendererType: Shape.CurveRenderer
            readonly property real j: body.jig
            ShapePath {
                scale: pet.us
                strokeWidth: -1
                fillColor: pet.pal.main
                PathSvg {
                    path: `M1.5 14 C1.5 ${5.5 - bl.j} ${5 - bl.j * 0.6} ${1.8 - bl.j * 1.2} 10 ${1.8 - bl.j * 1.2}`
                        + ` C${15 + bl.j * 0.6} ${1.8 - bl.j * 1.2} 18.5 ${5.5 - bl.j} 18.5 14 C18.5 16.8 16.4 18 10 18 C3.6 18 1.5 16.8 1.5 14 Z`
                }
            }
            // reflet
            ShapePath {
                scale: pet.us
                strokeWidth: -1
                fillColor: Qt.rgba(1, 1, 1, 0.35)
                PathSvg { path: "M3.9 7.6 C4 5.8 5.2 4.4 6.9 4 C6 4.9 5.3 6.1 5.1 7.7 C4.9 8.5 3.9 8.4 3.9 7.6 Z" }
            }
        }
    }
    Component {
        id: catC
        Item {
            // queue, derriere le corps
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                transform: Rotation {
                    origin.x: 14.6 * pet.k
                    origin.y: 16.6 * pet.k
                    angle: (pet.rich ? Math.sin(body.phase) * 10 : 0) + (pet.walking ? 8 : 0) - body.twitch * 8
                }
                ShapePath {
                    scale: pet.us
                    fillColor: "transparent"
                    strokeColor: pet.pal.main
                    strokeWidth: 2.2 * pet.k
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: "M14.6 16.6 C18.8 17 19.6 13 18.4 9.6" }
                }
                ShapePath {
                    scale: pet.us
                    fillColor: "transparent"
                    strokeColor: pet.pal.detail
                    strokeWidth: 2.2 * pet.k
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: "M18.85 11.1 C18.8 10.6 18.6 10.1 18.4 9.6" }
                }
            }
            // oreilles (la droite bouge de temps en temps)
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    scale: pet.us
                    fillColor: pet.pal.main
                    strokeColor: pet.pal.main
                    strokeWidth: 0.9 * pet.k
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M3.4 6.2 L3.7 0.9 L8 3.4 Z" }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.inner || "#ff9fb4"
                    PathSvg { path: "M4.4 4.8 L4.6 2.3 L6.6 3.5 Z" }
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                transform: Rotation { origin.x: 14 * pet.k; origin.y: 4.4 * pet.k; angle: body.twitch * 14 }
                ShapePath {
                    scale: pet.us
                    fillColor: pet.pal.main
                    strokeColor: pet.pal.main
                    strokeWidth: 0.9 * pet.k
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M16.6 6.2 L16.3 0.9 L12 3.4 Z" }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.inner || "#ff9fb4"
                    PathSvg { path: "M15.6 4.8 L15.4 2.3 L13.4 3.5 Z" }
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                // corps, tete
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.main
                    PathSvg { path: "M5 18 C4.4 14.6 5.8 11.6 10 11.6 C14.2 11.6 15.6 14.6 15 18 Z M2.8 8 C2.8 4.6 6 2.4 10 2.4 C14 2.4 17.2 4.6 17.2 8 C17.2 11.4 14 13.4 10 13.4 C6 13.4 2.8 11.4 2.8 8 Z" }
                }
                // museau, pattes
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.belly
                    PathSvg { path: "M7.4 10.5 C7.4 9.4 8.6 8.9 10 8.9 C11.4 8.9 12.6 9.4 12.6 10.5 C12.6 11.6 11.4 12.2 10 12.2 C8.6 12.2 7.4 11.6 7.4 10.5 Z M6.3 18 C6.3 16.8 7.2 16.3 8 16.3 C8.8 16.3 9.6 16.8 9.6 18 Z M10.4 18 C10.4 16.8 11.2 16.3 12 16.3 C12.8 16.3 13.7 16.8 13.7 18 Z" }
                }
                // rayures du front
                ShapePath {
                    scale: pet.us
                    fillColor: "transparent"
                    strokeColor: pet.pal.detail
                    strokeWidth: 0.7 * pet.k
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: "M10 2.8 L10 4.4 M8.3 3.1 L8.6 4.4 M11.7 3.1 L11.4 4.4" }
                }
                // nez
                ShapePath {
                    scale: pet.us
                    fillColor: "#ff8fa3"
                    strokeColor: "#ff8fa3"
                    strokeWidth: 0.4 * pet.k
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "M9.3 8.9 L10.7 8.9 L10 9.7 Z" }
                }
                // moustaches
                ShapePath {
                    scale: pet.us
                    fillColor: "transparent"
                    strokeColor: Qt.rgba(pet.pal.ink.r, pet.pal.ink.g, pet.pal.ink.b, 0.5)
                    strokeWidth: 0.3 * pet.k
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: "M6.8 9.9 L2.6 9.2 M6.8 10.6 L2.8 11 M13.2 9.9 L17.4 9.2 M13.2 10.6 L17.2 11" }
                }
            }
        }
    }
    Component {
        id: ghostC
        Item {
            id: gh
            // jupe ondulee (la phase anime les festons en grand format)
            readonly property real w: pet.rich ? body.phase : 0
            function b(i) {
                return (19.2 + 0.9 * Math.sin(w * 2 + i * 1.6) + body.jig).toFixed(2)
            }
            readonly property string shape: `M2 10 C2 4.6 5.6 1.6 10 1.6 C14.4 1.6 18 4.6 18 10 L18 16.4 Q16 ${b(0)} 14 16.4 Q12 ${b(1)} 10 16.4 Q8 ${b(2)} 6 16.4 Q4 ${b(3)} 2 16.4 Z`
            // bras
            Repeater {
                model: 2
                Shape {
                    id: arm
                    required property int index
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    transform: Rotation {
                        origin.x: (arm.index ? 17.6 : 2.4) * pet.k
                        origin.y: 10 * pet.k
                        angle: (arm.index ? -1 : 1) * ((pet.rich ? Math.sin(body.phase * 2) * 14 : 0) + (body.waving && arm.index ? -60 : 0))
                    }
                    ShapePath {
                        scale: pet.us
                        strokeWidth: -1
                        fillColor: pet.pal.main
                        PathSvg {
                            path: arm.index ? "M17.6 9.6 C19.4 10.2 19.6 12.4 18.4 12.8 C17.8 13 17.4 12.4 17.4 11.6 Z"
                                : "M2.4 9.6 C0.6 10.2 0.4 12.4 1.6 12.8 C2.2 13 2.6 12.4 2.6 11.6 Z"
                        }
                    }
                }
            }
            Shape {
                anchors.fill: parent
                opacity: 0.94
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.main
                    PathSvg { path: gh.shape }
                }
                // reflet
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: Qt.rgba(1, 1, 1, 0.5)
                    PathSvg { path: "M4.2 7.4 C4.4 5.4 5.6 4 7.2 3.6 C6.2 4.6 5.6 5.8 5.4 7.4 C5.2 8.2 4.2 8.2 4.2 7.4 Z" }
                }
            }
        }
    }
    Component {
        id: bunnyC
        Item {
            // oreilles (la droite retombe et frissonne)
            Repeater {
                model: 2
                Item {
                    required property int index
                    x: (index ? 11.4 : 5.2) * pet.k
                    y: -5.6 * pet.k
                    width: 3.4 * pet.k
                    height: 11 * pet.k
                    transformOrigin: Item.Bottom
                    rotation: index ? 24 - body.twitch * 20 + (pet.rich ? Math.sin(body.phase + 1) * 3 : 0)
                                    : -8 + (pet.rich ? Math.sin(body.phase) * 3 : 0)
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: pet.pal.main
                        Rectangle {
                            x: 0.9 * pet.k
                            y: 1.2 * pet.k
                            width: 1.6 * pet.k
                            height: 7.4 * pet.k
                            radius: width / 2
                            color: pet.pal.inner || "#ffb1c6"
                        }
                    }
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.main
                    PathSvg { path: "M2.2 13 C2.2 6.8 5.6 4.2 10 4.2 C14.4 4.2 17.8 6.8 17.8 13 C17.8 16.6 15.4 18 10 18 C4.6 18 2.2 16.6 2.2 13 Z" }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.belly
                    PathSvg { path: "M6.2 15.2 C6.2 13.2 7.8 12.4 10 12.4 C12.2 12.4 13.8 13.2 13.8 15.2 C13.8 17 12.2 17.8 10 17.8 C7.8 17.8 6.2 17 6.2 15.2 Z M4.4 18 C4.4 16.9 5.6 16.5 6.6 16.5 C7.6 16.5 8.6 16.9 8.6 18 Z M11.4 18 C11.4 16.9 12.4 16.5 13.4 16.5 C14.4 16.5 15.6 16.9 15.6 18 Z" }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.inner || "#ffb1c6"
                    PathSvg { path: "M9.3 10.2 C9.3 9.8 10.7 9.8 10.7 10.2 C10.7 10.6 10.2 10.9 10 10.9 C9.8 10.9 9.3 10.6 9.3 10.2 Z" }
                }
            }
        }
    }
    Component {
        id: frogC
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: pet.us
                strokeWidth: -1
                fillColor: pet.pal.main
                PathSvg { path: "M1 14.6 C1 9.6 4.6 7.6 10 7.6 C15.4 7.6 19 9.6 19 14.6 C19 17 16.6 18 10 18 C3.4 18 1 17 1 14.6 Z " + pet.circ(5.6, 6.8, 3.4) + " " + pet.circ(14.4, 6.8, 3.4) }
            }
            // blanc des yeux
            ShapePath {
                scale: pet.us
                strokeWidth: -1
                fillColor: "#ffffff"
                PathSvg { path: pet.circ(5.6, 6.8, 2.5) + " " + pet.circ(14.4, 6.8, 2.5) }
            }
            ShapePath {
                scale: pet.us
                strokeWidth: -1
                fillColor: pet.pal.belly
                PathSvg { path: "M5 15.6 C5 13.6 7.2 12.8 10 12.8 C12.8 12.8 15 13.6 15 15.6 C15 17.2 12.8 17.9 10 17.9 C7.2 17.9 5 17.2 5 15.6 Z" }
            }
            // taches et pattes
            ShapePath {
                scale: pet.us
                strokeWidth: -1
                fillColor: pet.pal.detail
                PathSvg { path: pet.circ(3.9, 11.6, 0.7) + " " + pet.circ(16.2, 12.4, 0.6) + " " + pet.circ(16.8, 10.4, 0.4)
                    + " M1.6 18 C1.6 16.8 3 16.4 4.2 16.4 C5.4 16.4 6.6 16.8 6.6 18 Z M13.4 18 C13.4 16.8 14.6 16.4 15.8 16.4 C17 16.4 18.4 16.8 18.4 18 Z" }
            }
        }
    }
    Component {
        id: penguinC
        Item {
            id: pg
            readonly property real flap: (pet.walking ? Math.sin(body.phase * 4) * 18 : pet.rich ? Math.sin(body.phase) * 4 : 0)
                + (pet.mood === "party" || body.waving ? 24 : 0)
            // ailerons
            Repeater {
                model: 2
                Shape {
                    id: fl
                    required property int index
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    transform: Rotation {
                        origin.x: (fl.index ? 16.4 : 3.6) * pet.k
                        origin.y: 9 * pet.k
                        angle: (fl.index ? -1 : 1) * pg.flap
                    }
                    ShapePath {
                        scale: pet.us
                        strokeWidth: -1
                        fillColor: pet.pal.detail
                        PathSvg {
                            path: fl.index ? "M16.6 8.6 C18.8 10 19.4 13.4 18.8 14.6 C17.8 14.4 16.4 12.6 15.8 10.4 Z"
                                : "M3.4 8.6 C1.2 10 0.6 13.4 1.2 14.6 C2.2 14.4 3.6 12.6 4.2 10.4 Z"
                        }
                    }
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    scale: pet.us
                    fillColor: pet.pal.main
                    strokeColor: pet.pal.rim || pet.pal.detail
                    strokeWidth: 0.5 * pet.k
                    PathSvg { path: "M10 1.4 C15.2 1.4 17.6 7.4 17.6 12.4 C17.6 16.4 14.6 18 10 18 C5.4 18 2.4 16.4 2.4 12.4 C2.4 7.4 4.8 1.4 10 1.4 Z" }
                }
                // masque blanc
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.belly
                    PathSvg { path: "M10 4.6 C8.8 4.6 7.8 5.1 7.2 5.9 C6.1 5.1 4.7 5.7 4.7 7.4 C4.7 9 5.3 10 5.3 11.6 C5.3 13 4.5 13.8 4.5 14.8 C4.5 16.6 6.7 17.6 10 17.6 C13.3 17.6 15.5 16.6 15.5 14.8 C15.5 13.8 14.7 13 14.7 11.6 C14.7 10 15.3 9 15.3 7.4 C15.3 5.7 13.9 5.1 12.8 5.9 C12.2 5.1 11.2 4.6 10 4.6 Z" }
                }
                // pattes
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.beak
                    PathSvg { path: "M5.6 18 C5.6 17.1 6.6 16.8 7.4 16.8 C8.2 16.8 9 17.2 9 18 Z M11 18 C11 17.2 11.8 16.8 12.6 16.8 C13.4 16.8 14.4 17.1 14.4 18 Z" }
                }
            }
            Beak {
                anchors.fill: parent
                color: pet.pal.beak
                at: 9.3
                u: pet.k
                open: pet.mouthAmt
            }
        }
    }
    Component {
        id: chickC
        Item {
            id: ck
            readonly property real flap: pet.walking || pet.mood === "party" || pet.expr === "happy" || body.waving ? Math.sin((pet.rich ? body.phase : body.breathe * 3) * 5) * 22 + 10 : 0
            // ailes
            Repeater {
                model: 2
                Shape {
                    id: wg
                    required property int index
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    transform: Rotation {
                        origin.x: (wg.index ? 16.4 : 3.6) * pet.k
                        origin.y: 11 * pet.k
                        angle: (wg.index ? -1 : 1) * ck.flap
                    }
                    ShapePath {
                        scale: pet.us
                        strokeWidth: -1
                        fillColor: pet.pal.detail
                        PathSvg {
                            path: wg.index ? "M16.6 10.6 C18.4 11 18.8 13.4 17.8 14.4 C16.8 14.4 16 13.2 15.8 11.8 Z"
                                : "M3.4 10.6 C1.6 11 1.2 13.4 2.2 14.4 C3.2 14.4 4 13.2 4.2 11.8 Z"
                        }
                    }
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                // houppette
                ShapePath {
                    scale: pet.us
                    fillColor: "transparent"
                    strokeColor: pet.pal.detail
                    strokeWidth: 0.9 * pet.k
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: "M10 4.8 Q9 2.6 10.3 1.6 M10 4.8 Q11.4 2.8 12.6 3.1 M10 4.8 Q8.4 3.4 7.4 3.8" }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.main
                    PathSvg { path: pet.circ(10, 11.1, 6.9) }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.belly
                    PathSvg { path: "M6.4 14.4 C6.4 12.6 8 11.8 10 11.8 C12 11.8 13.6 12.6 13.6 14.4 C13.6 16.4 12 17.6 10 17.6 C8 17.6 6.4 16.4 6.4 14.4 Z" }
                }
                // pattes
                ShapePath {
                    scale: pet.us
                    fillColor: "transparent"
                    strokeColor: pet.pal.beak
                    strokeWidth: 0.55 * pet.k
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: "M8.2 17.4 L7.5 18.3 M8.2 17.4 L8.2 18.4 M8.2 17.4 L8.9 18.3 M11.8 17.4 L11.1 18.3 M11.8 17.4 L11.8 18.4 M11.8 17.4 L12.5 18.3" }
                }
            }
            Beak {
                anchors.fill: parent
                color: pet.pal.beak
                at: 10
                u: pet.k
                open: pet.mouthAmt
            }
        }
    }
    Component {
        id: robotC
        Item {
            id: rb
            // voyant de l'antenne : rouge s'il chauffe, au rythme de la musique
            readonly property color led: pet.mood === "hot" ? "#ff4d4d" : pet.mood === "music" ? Theme.tertiary
                : pet.mood === "game" ? "#4dff88" : "#ff5d7a"
            Item {
                anchors.fill: parent
                transform: Rotation { origin.x: 10 * pet.k; origin.y: 3.8 * pet.k; angle: (pet.rich ? Math.sin(body.phase) * 6 : 0) + body.twitch * 10 }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        scale: pet.us
                        fillColor: "transparent"
                        strokeColor: pet.pal.detail
                        strokeWidth: 0.6 * pet.k
                        PathSvg { path: "M10 3.8 L10 1.6" }
                    }
                }
                Rectangle {
                    width: 2.6 * pet.k
                    height: width
                    radius: width / 2
                    x: 10 * pet.k - width / 2
                    y: 1.1 * pet.k - height / 2
                    color: rb.led
                    opacity: 0.3 + 0.3 * body.breathe + pet.bop * 0.4
                }
                Rectangle {
                    width: 1.6 * pet.k
                    height: width
                    radius: width / 2
                    x: 10 * pet.k - width / 2
                    y: 1.1 * pet.k - height / 2
                    color: rb.led
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                // oreilles, pieds
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.detail
                    PathRectangle { x: 0.8; y: 8; width: 1.8; height: 4; radius: 0.6 }
                    PathRectangle { x: 17.4; y: 8; width: 1.8; height: 4; radius: 0.6 }
                    PathRectangle { x: 4.8; y: 15.8; width: 3.6; height: 2.2; radius: 0.8 }
                    PathRectangle { x: 11.6; y: 15.8; width: 3.6; height: 2.2; radius: 0.8 }
                }
                ShapePath {
                    scale: pet.us
                    fillColor: pet.pal.main
                    strokeColor: pet.pal.detail
                    strokeWidth: 0.4 * pet.k
                    PathRectangle { x: 2; y: 3.6; width: 16; height: 12.8; radius: 3.6 }
                }
                // ecran
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.belly
                    PathRectangle { x: 4; y: 5.3; width: 12; height: 7.8; radius: 2.2 }
                }
                // reflet de l'ecran, boulons
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: Qt.rgba(1, 1, 1, 0.1)
                    PathSvg { path: "M5 6.6 C5 6 5.4 5.9 6 5.9 L9 5.9 L5 9.6 Z" }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.detail
                    PathSvg { path: pet.circ(4, 14.8, 0.45) + " " + pet.circ(16, 14.8, 0.45) }
                }
            }
            // bouche en diodes (egaliseur avec la musique)
            Row {
                id: leds
                x: 7.5 * pet.k
                y: 11.4 * pet.k
                spacing: 0.3 * pet.k
                readonly property bool smile: pet.expr === "happy" || pet.expr === "heart" || pet.expr === "star"
                Repeater {
                    model: 5
                    Rectangle {
                        required property int index
                        readonly property real lv: pet.mood === "music" ? (Ilot.shown[index * 4] || 0) : 0
                        width: 0.7 * pet.k
                        height: (0.55 + pet.mouthAmt * 1.4 + lv * 1.8) * pet.k
                        radius: width / 2
                        y: -height / 2 + (leds.smile ? [0, 0.35, 0.5, 0.35, 0][index] * pet.k : 0)
                        color: pet.pal.ink
                    }
                }
            }
        }
    }
    Component {
        id: axolotlC
        Item {
            // branchies
            Repeater {
                model: 2
                Shape {
                    id: gl
                    required property int index
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    transform: Rotation {
                        origin.x: (gl.index ? 16 : 4) * pet.k
                        origin.y: 7.6 * pet.k
                        angle: (gl.index ? -1 : 1) * ((pet.rich ? Math.sin(body.phase * (pet.walking ? 3 : 1)) * 8 : 0) + body.twitch * 8)
                    }
                    ShapePath {
                        scale: pet.us
                        fillColor: "transparent"
                        strokeColor: pet.pal.detail
                        strokeWidth: 1.3 * pet.k
                        capStyle: ShapePath.RoundCap
                        PathSvg {
                            path: gl.index ? "M15.6 6.2 Q17.8 4 19.2 4.4 M16.1 7.6 Q18.4 7.2 19.8 8 M15.8 9 Q17.6 10.4 18.8 11.4"
                                : "M4.4 6.2 Q2.2 4 0.8 4.4 M3.9 7.6 Q1.6 7.2 0.2 8 M4.2 9 Q2.4 10.4 1.2 11.4"
                        }
                    }
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                // queue
                ShapePath {
                    scale: pet.us
                    fillColor: "transparent"
                    strokeColor: pet.pal.main
                    strokeWidth: 1.8 * pet.k
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: "M13.6 16 Q18.4 16.4 19.2 13" }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.main
                    PathSvg { path: "M5.2 12.6 C5 16.6 6.8 18 10 18 C13.2 18 15 16.6 14.8 12.6 Z M2.6 9.8 C2.6 5.6 6 3.6 10 3.6 C14 3.6 17.4 5.6 17.4 9.8 C17.4 12.4 15.2 13.6 10 13.6 C4.8 13.6 2.6 12.4 2.6 9.8 Z" }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.belly
                    PathSvg { path: "M7.6 15.8 C7.6 14.7 8.7 14.2 10 14.2 C11.3 14.2 12.4 14.7 12.4 15.8 C12.4 16.9 11.3 17.6 10 17.6 C8.7 17.6 7.6 16.9 7.6 15.8 Z" }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.detail
                    PathSvg { path: "M5.4 18 C5.4 17 6.2 16.6 6.8 16.6 C7.4 16.6 8 17 8 18 Z M12 18 C12 17 12.6 16.6 13.2 16.6 C13.8 16.6 14.6 17 14.6 18 Z" }
                }
            }
        }
    }
    Component {
        id: mushC
        Item {
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.belly
                    PathSvg { path: "M5 9.6 C4.4 14 5 18 10 18 C15 18 15.6 14 15 9.6 Z" }
                }
            }
            // chapeau, qui penche un peu
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                transform: Rotation { origin.x: 10 * pet.k; origin.y: 11 * pet.k; angle: (pet.rich ? Math.sin(body.phase) * 2.5 : 0) + body.twitch * 4 }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.main
                    PathSvg { path: "M0.8 10 C0.8 4 5 0.8 10 0.8 C15 0.8 19.2 4 19.2 10 C19.2 11.6 17.4 11.6 10 11.6 C2.6 11.6 0.8 11.6 0.8 10 Z" }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: pet.pal.detail
                    PathSvg { path: [pet.circ(4.6, 5.6, 1.5), pet.circ(10.6, 3.2, 1.2), pet.circ(15, 6.6, 1.6), pet.circ(8.4, 8, 0.9), pet.circ(12.8, 9.4, 0.7)].join(" ") }
                }
                ShapePath {
                    scale: pet.us
                    fillColor: "transparent"
                    strokeColor: Qt.darker(pet.pal.main, 1.25)
                    strokeWidth: 0.5 * pet.k
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: "M2 10.9 Q10 12.2 18 10.9" }
                }
            }
        }
    }

    // ------------------------------------------------------ chapeaux
    // dessines dans une boite de 10 x 8, posee sur la tete (hatBox)
    Component {
        id: hatParty
        Shape {
            preferredRendererType: Shape.CurveRenderer
            transform: Rotation { origin.x: hatBox.width / 2; origin.y: hatBox.height; angle: 12 }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#ff6fa0"
                PathSvg { path: "M2.2 8 L5 0.9 L7.8 8 Q5 8.7 2.2 8 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#ffd166"
                PathSvg { path: "M3.94 3.6 L6.06 3.6 L6.54 4.8 L3.46 4.8 Z M2.91 6.2 L7.09 6.2 L7.48 7.2 L2.52 7.2 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#fff8e7"
                PathSvg { path: pet.circ(5, 1, 1.1) }
            }
        }
    }
    Component {
        id: hatCrown
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: hatBox.hs
                fillColor: "#ffcc33"
                strokeColor: "#d99a00"
                strokeWidth: 0.35 * hatBox.hs.width
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M1.6 8 L1.6 3.4 L3.4 5.4 L5 2.2 L6.6 5.4 L8.4 3.4 L8.4 8 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#ff4d6d"
                PathSvg { path: pet.circ(5, 6.4, 0.75) }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#4dc3ff"
                PathSvg { path: pet.circ(3.1, 6.6, 0.5) + " " + pet.circ(6.9, 6.6, 0.5) }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#fff1a8"
                PathSvg { path: pet.circ(1.6, 3.4, 0.45) + " " + pet.circ(5, 2.2, 0.45) + " " + pet.circ(8.4, 3.4, 0.45) }
            }
        }
    }
    Component {
        id: hatCap
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#3d7bff"
                PathSvg { path: "M1.4 8 C1.4 4.2 3.2 2.8 5.2 2.8 C7.4 2.8 8.8 4.4 8.8 8 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#2a5bd1"
                PathSvg { path: "M6.2 7 Q10.6 6.6 11.6 7.8 Q11.4 8.6 10.6 8.6 L6.2 8.6 Z " + pet.circ(5.2, 2.9, 0.55) }
            }
            ShapePath {
                scale: hatBox.hs
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.55)
                strokeWidth: 0.35 * hatBox.hs.width
                capStyle: ShapePath.RoundCap
                PathSvg { path: "M3 6.2 Q5 4.8 7 5.6" }
            }
        }
    }
    Component {
        id: hatBeanie
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#e9566f"
                PathSvg { path: "M1.2 8 C1.2 3.6 3 1.8 5 1.8 C7 1.8 8.8 3.6 8.8 8 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#c93f58"
                PathRectangle { x: 0.8; y: 6.2; width: 8.4; height: 2; radius: 1 }
            }
            ShapePath {
                scale: hatBox.hs
                fillColor: "transparent"
                strokeColor: "#a8304a"
                strokeWidth: 0.3 * hatBox.hs.width
                PathSvg { path: "M2.4 6.6 L2.4 7.8 M3.8 6.6 L3.8 7.8 M5.2 6.6 L5.2 7.8 M6.6 6.6 L6.6 7.8 M8 6.6 L8 7.8" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#fff5f7"
                PathSvg { path: pet.circ(5, 1.4, 1.3) }
            }
        }
    }
    Component {
        id: hatTop
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#26262e"
                PathRectangle { x: 0.4; y: 6.8; width: 9.2; height: 1.4; radius: 0.7 }
                PathRectangle { x: 2.1; y: 0.4; width: 5.8; height: 6.8; radius: 0.6 }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#e2453c"
                PathRectangle { x: 2.1; y: 4.8; width: 5.8; height: 1.2 }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: Qt.rgba(1, 1, 1, 0.15)
                PathRectangle { x: 2.7; y: 1; width: 0.7; height: 3.4; radius: 0.3 }
            }
        }
    }
    Component {
        id: hatWizard
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#5b4bd1"
                PathSvg { path: "M1.4 7.6 L8.6 7.6 L6.2 3.2 Q5.6 1 8.4 -0.4 Q4.6 0.2 3.8 3.2 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#4636b0"
                PathSvg { path: "M0 7.7 C0 7 2.2 6.6 5 6.6 C7.8 6.6 10 7 10 7.7 C10 8.4 7.8 8.8 5 8.8 C2.2 8.8 0 8.4 0 7.7 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#ffd84a"
                PathSvg { path: "M4.4 4.6 Q4.6 5.4 5.4 5.6 Q4.6 5.8 4.4 6.6 Q4.2 5.8 3.4 5.6 Q4.2 5.4 4.4 4.6 Z M6.2 2.8 Q6.3 3.3 6.8 3.4 Q6.3 3.5 6.2 4 Q6.1 3.5 5.6 3.4 Q6.1 3.3 6.2 2.8 Z" }
            }
        }
    }
    Component {
        id: hatFlower
        Shape {
            id: fw
            preferredRendererType: Shape.CurveRenderer
            readonly property var petals: [0, 1, 2, 3, 4].map(i => pet.circ(2.4 + 1.3 * Math.cos((i * 72 - 90) * Math.PI / 180), 5.4 + 1.3 * Math.sin((i * 72 - 90) * Math.PI / 180), 1.15)).join(" ")
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#6cc56b"
                PathSvg { path: "M3.4 6.6 C4.4 5.6 6 5.8 6.4 6.6 C5.6 7.4 4.4 7.6 3.4 6.6 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#ff8fb8"
                PathSvg { path: fw.petals }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#ffd84a"
                PathSvg { path: pet.circ(2.4, 5.4, 0.85) }
            }
        }
    }
    Component {
        id: hatBow
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#ff5d8f"
                PathSvg { path: "M5 6 L2 4 Q1.4 6 2 8 Z M5 6 L8 4 Q8.6 6 8 8 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#e4407a"
                PathSvg { path: pet.circ(5, 6, 1) }
            }
        }
    }
    Component {
        id: hatHalo
        Shape {
            preferredRendererType: Shape.CurveRenderer
            transform: Translate { y: (-1.6 + (pet.rich ? Math.sin(body.phase * 2) * 0.5 : body.breathe * 0.4)) * pet.k }
            ShapePath {
                scale: hatBox.hs
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 0.85, 0.3, 0.3)
                strokeWidth: 1.8 * hatBox.hs.width
                PathSvg { path: "M1.4 3 C1.4 2.3 3 1.8 5 1.8 C7 1.8 8.6 2.3 8.6 3 C8.6 3.7 7 4.2 5 4.2 C3 4.2 1.4 3.7 1.4 3 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                fillColor: "transparent"
                strokeColor: "#ffd84a"
                strokeWidth: 0.7 * hatBox.hs.width
                PathSvg { path: "M1.4 3 C1.4 2.3 3 1.8 5 1.8 C7 1.8 8.6 2.3 8.6 3 C8.6 3.7 7 4.2 5 4.2 C3 4.2 1.4 3.7 1.4 3 Z" }
            }
        }
    }
    Component {
        id: hatHorns
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#ff5a5a"
                PathSvg { path: "M1.8 8 Q0.6 4.6 1.8 2.4 Q2.6 5.2 4.2 7.4 Z M8.2 8 Q9.4 4.6 8.2 2.4 Q7.4 5.2 5.8 7.4 Z" }
            }
        }
    }
    Component {
        id: hatHeadset
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: hatBox.hs
                fillColor: "transparent"
                strokeColor: "#2b2b33"
                strokeWidth: 0.9 * hatBox.hs.width
                capStyle: ShapePath.RoundCap
                PathSvg { path: "M0.8 7.6 C0.8 1.6 9.2 1.6 9.2 7.6" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: Theme.tertiary
                PathRectangle { x: -0.6; y: 5.6; width: 2.2; height: 4; radius: 1 }
                PathRectangle { x: 8.4; y: 5.6; width: 2.2; height: 4; radius: 1 }
            }
            // micro (casque de jeu)
            ShapePath {
                scale: hatBox.hs
                fillColor: "transparent"
                strokeColor: pet.hatShown === "headset" ? "#2b2b33" : "transparent"
                strokeWidth: 0.45 * hatBox.hs.width
                capStyle: ShapePath.RoundCap
                PathSvg { path: "M0.4 9 Q1.2 11.4 3.4 11.2" }
            }
        }
    }
    Component {
        id: hatNightcap
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#6d8cff"
                PathSvg { path: "M1.2 8 Q1.6 2.2 6.4 2 Q10.6 2.2 11.2 7.2 L10.4 7.4 Q9.8 4.6 7.6 4.4 Q8.8 6 8.8 8 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#ffffff"
                PathRectangle { x: 0.8; y: 6.8; width: 8.4; height: 1.5; radius: 0.75 }
            }
            ShapePath {
                scale: hatBox.hs
                strokeWidth: -1
                fillColor: "#ffffff"
                PathSvg { path: pet.circ(10.9, 7.8, 0.9) }
            }
        }
    }
    Component {
        id: hatChef
        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: hatBox.hs
                fillColor: "#ffffff"
                strokeColor: "#dcdce4"
                strokeWidth: 0.3 * hatBox.hs.width
                PathSvg { path: "M2.4 8 L2.4 4.8 C0.6 4.6 0.6 1.8 2.6 2 C2.8 0.2 5 0 5.6 1.2 C6.6 0 8.8 0.6 8.4 2.4 C10 2.8 9.6 5 7.6 4.8 L7.6 8 Z" }
            }
            ShapePath {
                scale: hatBox.hs
                fillColor: "transparent"
                strokeColor: "#dcdce4"
                strokeWidth: 0.3 * hatBox.hs.width
                PathSvg { path: "M2.4 6.6 L7.6 6.6" }
            }
        }
    }

    // ----------------------------------------------- visage, cou
    Component {
        id: faGlasses
        Shape {
            id: ac
            preferredRendererType: Shape.CurveRenderer
            readonly property var g: pet.geo
            readonly property real r: 2.1 * g.es
            ShapePath {
                scale: pet.us
                fillColor: Qt.rgba(1, 1, 1, 0.14)
                strokeColor: "#2b2b33"
                strokeWidth: 0.5 * pet.k
                PathSvg { path: pet.circ(ac.g.eyes[0], ac.g.eyes[2], ac.r) + " " + pet.circ(ac.g.eyes[1], ac.g.eyes[2], ac.r) }
            }
            ShapePath {
                scale: pet.us
                fillColor: "transparent"
                strokeColor: "#2b2b33"
                strokeWidth: 0.5 * pet.k
                PathSvg { path: `M${ac.g.eyes[0] + ac.r} ${ac.g.eyes[2]} Q10 ${ac.g.eyes[2] - 1} ${ac.g.eyes[1] - ac.r} ${ac.g.eyes[2]}` }
            }
        }
    }
    Component {
        id: faSun
        Shape {
            id: ac
            preferredRendererType: Shape.CurveRenderer
            readonly property var g: pet.geo
            readonly property real hw: 2.3 * g.es
            ShapePath {
                scale: pet.us
                strokeWidth: -1
                fillColor: "#1b1b22"
                PathRectangle { x: ac.g.eyes[0] - ac.hw; y: ac.g.eyes[2] - 1.5 * ac.g.es; width: 2 * ac.hw; height: 3 * ac.g.es; radius: 1.3 * ac.g.es }
                PathRectangle { x: ac.g.eyes[1] - ac.hw; y: ac.g.eyes[2] - 1.5 * ac.g.es; width: 2 * ac.hw; height: 3 * ac.g.es; radius: 1.3 * ac.g.es }
            }
            ShapePath {
                scale: pet.us
                fillColor: "transparent"
                strokeColor: "#1b1b22"
                strokeWidth: 0.5 * pet.k
                PathSvg { path: `M${ac.g.eyes[0] + ac.hw} ${ac.g.eyes[2] - 0.6} L${ac.g.eyes[1] - ac.hw} ${ac.g.eyes[2] - 0.6}` }
            }
            ShapePath {
                scale: pet.us
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.45)
                strokeWidth: 0.35 * pet.k
                capStyle: ShapePath.RoundCap
                PathSvg { path: `M${ac.g.eyes[0] - 1} ${ac.g.eyes[2] + 0.4} L${ac.g.eyes[0] + 0.2} ${ac.g.eyes[2] - 0.8} M${ac.g.eyes[1] - 1} ${ac.g.eyes[2] + 0.4} L${ac.g.eyes[1] + 0.2} ${ac.g.eyes[2] - 0.8}` }
            }
        }
    }
    Component {
        id: faMonocle
        Shape {
            id: ac
            preferredRendererType: Shape.CurveRenderer
            readonly property var g: pet.geo
            ShapePath {
                scale: pet.us
                fillColor: Qt.rgba(1, 1, 1, 0.12)
                strokeColor: "#d9a521"
                strokeWidth: 0.45 * pet.k
                PathSvg { path: pet.circ(ac.g.eyes[1], ac.g.eyes[2], 2.2 * ac.g.es) }
            }
            ShapePath {
                scale: pet.us
                fillColor: "transparent"
                strokeColor: "#d9a521"
                strokeWidth: 0.25 * pet.k
                PathSvg { path: `M${ac.g.eyes[1] + 1.6} ${ac.g.eyes[2] + 1.6} Q${ac.g.eyes[1] + 2.8} ${ac.g.eyes[2] + 4} ${ac.g.eyes[1] + 1} ${ac.g.eyes[2] + 5.6}` }
            }
        }
    }
    Component {
        id: faMask
        Shape {
            id: ac
            preferredRendererType: Shape.CurveRenderer
            readonly property var g: pet.geo
            ShapePath {
                scale: pet.us
                strokeWidth: -1
                fillColor: "#2a2233"
                fillRule: ShapePath.OddEvenFill
                PathSvg {
                    path: `M${ac.g.eyes[0] - 3} ${ac.g.eyes[2] - 1.2} Q10 ${ac.g.eyes[2] - 2.8} ${ac.g.eyes[1] + 3} ${ac.g.eyes[2] - 1.2}`
                        + ` L${ac.g.eyes[1] + 3.2} ${ac.g.eyes[2] + 1.2} Q10 ${ac.g.eyes[2] + 2.8} ${ac.g.eyes[0] - 3.2} ${ac.g.eyes[2] + 1.2} Z `
                        + pet.circ(ac.g.eyes[0], ac.g.eyes[2], 1.4) + " " + pet.circ(ac.g.eyes[1], ac.g.eyes[2], 1.4)
                }
            }
        }
    }
    Component {
        id: faFreckles
        Shape {
            id: ac
            preferredRendererType: Shape.CurveRenderer
            readonly property var c: pet.geo.cheeks
            ShapePath {
                scale: pet.us
                strokeWidth: -1
                fillColor: Qt.rgba(0.55, 0.3, 0.2, 0.55)
                PathSvg {
                    path: [[-0.9, -0.3], [0.2, 0.3], [0.9, -0.4]].map(d => pet.circ(ac.c[0] + d[0], ac.c[2] + d[1], 0.28) + " " + pet.circ(ac.c[1] - d[0], ac.c[2] + d[1], 0.28)).join(" ")
                }
            }
        }
    }
    Component {
        id: nkBowtie
        Shape {
            id: ac
            preferredRendererType: Shape.CurveRenderer
            readonly property var n: pet.geo.neck
            ShapePath {
                scale: pet.us
                fillColor: "#e2453c"
                strokeColor: "#e2453c"
                strokeWidth: 0.4 * pet.k
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: `M${ac.n[0]} ${ac.n[1]} L${ac.n[0] - 2.6} ${ac.n[1] - 1.4} L${ac.n[0] - 2.6} ${ac.n[1] + 1.4} Z M${ac.n[0]} ${ac.n[1]} L${ac.n[0] + 2.6} ${ac.n[1] - 1.4} L${ac.n[0] + 2.6} ${ac.n[1] + 1.4} Z` }
            }
            ShapePath {
                scale: pet.us
                strokeWidth: -1
                fillColor: "#b8322b"
                PathRectangle { x: ac.n[0] - 0.7; y: ac.n[1] - 0.8; width: 1.4; height: 1.6; radius: 0.4 }
            }
        }
    }
    Component {
        id: nkScarf
        Item {
            id: ac
            readonly property var n: pet.geo.neck
            // pan qui flotte
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                transform: Rotation {
                    origin.x: (ac.n[0] + ac.n[2] * 0.22) * pet.k
                    origin.y: ac.n[1] * pet.k
                    angle: (pet.rich ? Math.sin(body.phase * 2) * 10 : 0) + (pet.walking ? -25 : 0)
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: "#2f9e92"
                    PathRectangle { x: ac.n[0] + ac.n[2] * 0.22 - 0.8; y: ac.n[1]; width: 1.7; height: 4.2; radius: 0.6 }
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: "#3fb6a8"
                    PathRectangle { x: ac.n[0] - ac.n[2] / 2; y: ac.n[1] - 0.95; width: ac.n[2]; height: 1.9; radius: 0.95 }
                }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: Qt.rgba(1, 1, 1, 0.6)
                    PathRectangle { x: ac.n[0] - ac.n[2] * 0.25; y: ac.n[1] - 0.95; width: 0.8; height: 1.9 }
                    PathRectangle { x: ac.n[0] + ac.n[2] * 0.08; y: ac.n[1] - 0.95; width: 0.8; height: 1.9 }
                }
            }
        }
    }
    Component {
        id: nkBell
        Item {
            id: ac
            readonly property var n: pet.geo.neck
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: "#e2453c"
                    PathRectangle { x: ac.n[0] - ac.n[2] / 2; y: ac.n[1] - 0.5; width: ac.n[2]; height: 1; radius: 0.5 }
                }
            }
            // grelot : il tinte quand il saute
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                transform: Rotation { origin.x: ac.n[0] * pet.k; origin.y: ac.n[1] * pet.k; angle: Math.max(-30, Math.min(30, body.hopY / pet.k * 4 + body.lean)) }
                ShapePath {
                    scale: pet.us
                    strokeWidth: -1
                    fillColor: "#ffcc33"
                    PathSvg { path: pet.circ(ac.n[0], ac.n[1] + 1.2, 1.15) }
                }
                ShapePath {
                    scale: pet.us
                    fillColor: "transparent"
                    strokeColor: "#a87400"
                    strokeWidth: 0.3 * pet.k
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: `M${ac.n[0]} ${ac.n[1] + 1.5} L${ac.n[0]} ${ac.n[1] + 2.2}` }
                }
            }
        }
    }
    Component {
        id: nkBandana
        Shape {
            id: ac
            preferredRendererType: Shape.CurveRenderer
            readonly property var n: pet.geo.neck
            ShapePath {
                scale: pet.us
                fillColor: "#e2453c"
                strokeColor: "#e2453c"
                strokeWidth: 0.6 * pet.k
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: `M${ac.n[0] - ac.n[2] / 2} ${ac.n[1] - 0.6} L${ac.n[0] + ac.n[2] / 2} ${ac.n[1] - 0.6} L${ac.n[0]} ${ac.n[1] + 3.2} Z` }
            }
            ShapePath {
                scale: pet.us
                strokeWidth: -1
                fillColor: "#ffffff"
                PathSvg { path: pet.circ(ac.n[0] - 1.3, ac.n[1] + 0.2, 0.3) + " " + pet.circ(ac.n[0] + 1.3, ac.n[1] + 0.2, 0.3) + " " + pet.circ(ac.n[0], ac.n[1] + 1.6, 0.3) }
            }
        }
    }

    // ----------------------------------------------------- composants
    // tour : ecrasement / etirement du corps
    component Squash: ParallelAnimation {
        id: sq
        property Item t
        property real w: 1
        property real h: 1
        property int ms: 120
        property int ease: Easing.OutQuad
        NumberAnimation { target: sq.t; property: "sx"; to: sq.w; duration: sq.ms; easing.type: sq.ease }
        NumberAnimation { target: sq.t; property: "sy"; to: sq.h; duration: sq.ms; easing.type: sq.ease }
    }

    // bec qui s'ouvre (pingouin, poussin) : `top` = haut du bec, en unites
    component Beak: Shape {
        id: bk
        property color color: "orange"
        property real at: 9.3
        property real u: 1
        property real open: 0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            scale: Qt.size(bk.u, bk.u)
            fillColor: Qt.darker(bk.color, 1.15)
            strokeColor: Qt.darker(bk.color, 1.15)
            strokeWidth: 0.4 * bk.u
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: `M9.2 ${bk.at + 0.8 + bk.open * 0.5} L10.8 ${bk.at + 0.8 + bk.open * 0.5} L10 ${bk.at + 1.8 + bk.open * 1.2} Z` }
        }
        ShapePath {
            scale: Qt.size(bk.u, bk.u)
            fillColor: bk.color
            strokeColor: bk.color
            strokeWidth: 0.4 * bk.u
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: `M8.8 ${bk.at} L11.2 ${bk.at} L10 ${bk.at + 1.2} Z` }
        }
    }

    // oeil : forme ouverte selon le style (points, brillants, grands, cils,
    // endormis, carres), ou expression (heureux, ferme, plisse, etourdi,
    // coeur, etoile) ; sourcils tristes ou decides
    component Eye: Item {
        id: e
        property real u: 1
        property string style: "dot"
        property string expr: ""
        property bool flip: false
        property color ink: "black"
        property color lid: "white"
        property real open: 1
        width: 4 * u
        height: 4 * u
        readonly property var dims: ({ dot: [2.3, 3.1], shine: [2.7, 3.3], big: [3.2, 3.8], lash: [2.3, 3.1], sleepy: [2.6, 3.0], square: [2.5, 2.5] })[style] || [2.3, 3.1]
        readonly property bool plain: expr === "" || expr === "wide" || expr === "focus" || expr === "sad"
        readonly property real grow: expr === "wide" ? 1.2 : 1
        Rectangle {
            visible: e.plain
            readonly property real fullH: e.dims[1] * e.grow * e.u
            width: e.dims[0] * e.grow * e.u
            height: Math.max(0.45 * e.u, fullH * (e.expr === "wide" ? 1 : e.open))
            radius: e.style === "square" ? 0.6 * e.u : Math.min(width, height) / 2
            x: (e.width - width) / 2
            y: (e.height - fullH) / 2 + (fullH - height) * 0.6
            color: e.ink
            // reflets
            Rectangle {
                visible: (e.style === "shine" || e.style === "big" || e.expr === "wide") && e.open > 0.6
                width: parent.width * 0.42
                height: width
                radius: width / 2
                x: parent.width * 0.14
                y: parent.height * 0.12
                color: "white"
                opacity: 0.9
            }
            Rectangle {
                visible: e.style === "shine" && e.open > 0.6
                width: parent.width * 0.22
                height: width
                radius: width / 2
                x: parent.width * 0.6
                y: parent.height * 0.62
                color: "white"
                opacity: 0.8
            }
            // paupiere (yeux endormis)
            Rectangle {
                visible: e.style === "sleepy" && e.open > 0.6 && e.expr === ""
                width: parent.width + 0.4 * e.u
                height: parent.height * 0.46
                x: -0.2 * e.u
                y: -0.2 * e.u
                color: e.lid
            }
        }
        // cils, sourcils (dessines pour l'oeil gauche, retournes pour le droit)
        Shape {
            anchors.fill: parent
            visible: (e.style === "lash" && e.plain) || e.expr === "sad" || e.expr === "focus"
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { origin.x: e.width / 2; xScale: e.flip ? -1 : 1 }
            ShapePath {
                scale: Qt.size(e.u, e.u)
                fillColor: "transparent"
                strokeColor: e.ink
                strokeWidth: 0.5 * e.u
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: (e.style === "lash" && e.plain ? "M1 0.9 L0.1 0.3 M1.6 0.5 L1.2 -0.3 " : "")
                        + (e.expr === "sad" ? "M0.8 -0.2 L3.2 -1" : e.expr === "focus" ? "M0.8 -1 L3.2 -0.1" : "")
                }
            }
        }
        // expressions
        Shape {
            anchors.fill: parent
            visible: !e.plain && e.expr !== "heart" && e.expr !== "star"
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: Qt.size(e.u, e.u)
                fillColor: "transparent"
                strokeColor: e.ink
                strokeWidth: 0.75 * e.u
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg {
                    path: ({
                        happy: "M0.6 2.8 Q2 0.6 3.4 2.8",
                        closed: "M0.6 1.8 Q2 3.4 3.4 1.8",
                        squint: e.flip ? "M3.1 0.9 L1 2 L3.1 3.1" : "M0.9 0.9 L3 2 L0.9 3.1",
                        dizzy: "M0.9 0.9 L3.1 3.1 M3.1 0.9 L0.9 3.1"
                    })[e.expr] || "M2 2"
                }
            }
        }
        Shape {
            anchors.fill: parent
            visible: e.expr === "heart" || e.expr === "star"
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: Qt.size(e.u, e.u)
                strokeWidth: -1
                fillColor: e.expr === "heart" ? "#ff4d7d" : "#ffd84a"
                PathSvg {
                    path: e.expr === "heart" ? "M2 3.7 C-0.2 2.3 0 0.3 1.2 0.3 C1.7 0.3 2 0.7 2 1.1 C2 0.7 2.3 0.3 2.8 0.3 C4 0.3 4.2 2.3 2 3.7 Z"
                        : "M2 0 Q2.3 1.7 4 2 Q2.3 2.3 2 4 Q1.7 2.3 0 2 Q1.7 1.7 2 0 Z"
                }
            }
        }
    }
}
