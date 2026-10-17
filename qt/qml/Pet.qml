import QtQuick

// Compagnon de la pilule (Apparence > Compagnon : Blob, Chat, Fantome) :
// humeur donnee par Watch (musique, jeu, chaleur, sommeil, fete...). Aussi
// utilise par la fenetre de promenade (PetWindow).
Item {
    id: pet
    property string species: Ilot.cfg.pet || "blob"
    property string mood: Watch.mood
    // dodelinement sur les basses (0..1)
    property real bop: mood === "music" ? (Ilot.shown.slice(0, 4).reduce((a, b) => a + b, 0) / 4) : 0
    property real look: Watch.petLook
    property bool walking: false
    property bool blink: false
    property real k: 1
    // respiration : horloge d'ambiance (Ilot.amb), a l'arret quand personne
    // ne regarde, sauf pendant la promenade
    property bool animate: true
    readonly property bool breathing: visible && animate && !Theme.reduced && (Ilot.ambient || Watch.petOut)
    width: 20 * k
    height: 18 * k

    readonly property color bodyColor: species === "ghost" ? Theme.ink : Theme.primary
    readonly property color eyeColor: species === "ghost" ? Theme.surface : Theme.inkPrimary
    readonly property bool sleeping: mood === "sleep"

    function fx(sym) {
        fxText.text = sym
        fxAnim.restart()
    }
    function hop() {
        hopAnim.restart()
    }
    function doBlink() {
        blink = true
        blinkTimer.restart()
    }
    Timer {
        id: blinkTimer
        interval: 140
        onTriggered: pet.blink = false
    }
    Connections {
        target: Watch
        function onPetFx(sym) { pet.fx(sym) }
        function onPetBlink() { pet.doBlink() }
        function onPetHop() { pet.hop() }
    }

    Item {
        id: body
        anchors.fill: parent
        transformOrigin: Item.Bottom
        // respiration, dandinement en marchant, saut, danse
        property real breathe: 0
        Binding on breathe {
            when: pet.breathing
            value: Ilot.wave(Ilot.amb, pet.sleeping ? 5000 : 3200)
            restoreMode: Binding.RestoreNone
        }
        property real hopY: 0
        property real wad: 0
        SequentialAnimation on wad {
            running: pet.walking || pet.mood === "party"
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 200; easing.type: Easing.InOutSine }
            NumberAnimation { to: -1; duration: 400; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 200; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) body.wad = 0
        }
        rotation: wad * 7
        transform: [
            Scale {
                origin.x: body.width / 2
                origin.y: body.height
                xScale: 1 + body.breathe * 0.04 + pet.bop * 0.08
                yScale: 1 - body.breathe * 0.04 - pet.bop * 0.12
            },
            Translate { y: body.hopY - Math.abs(body.wad) * 2 }
        ]

        // oreilles du chat
        Repeater {
            model: pet.species === "cat" ? 2 : 0
            Rectangle {
                required property int index
                width: 6 * pet.k
                height: 6 * pet.k
                rotation: 45
                color: pet.bodyColor
                x: index === 0 ? 2.5 * pet.k : pet.width - 8.5 * pet.k
                y: 1 * pet.k
            }
        }
        Rectangle {
            id: blob
            x: 1 * pet.k
            width: pet.width - 2 * pet.k
            y: pet.species === "cat" ? 3.5 * pet.k : 2 * pet.k
            height: pet.height - y
            color: pet.bodyColor
            opacity: pet.species === "ghost" ? 0.85 : 1
            topLeftRadius: width / 2
            topRightRadius: width / 2
            bottomLeftRadius: pet.species === "ghost" ? 2 * pet.k : width * 0.42
            bottomRightRadius: pet.species === "ghost" ? 2 * pet.k : width * 0.42
            // chaleur : il rougit
            Rectangle {
                anchors.fill: parent
                radius: parent.topLeftRadius
                color: "#ff5a3c"
                opacity: pet.mood === "hot" ? 0.35 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
            // yeux
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    readonly property bool closed: pet.blink || pet.sleeping
                    width: 2.6 * pet.k
                    height: closed ? 1 * pet.k : (pet.mood === "surprise" || pet.mood === "party" ? 4.2 : 3.6) * pet.k
                    radius: width / 2
                    color: pet.eyeColor
                    x: (index === 0 ? 4.2 : blob.width / pet.k - 6.8) * pet.k + pet.look * pet.k
                    y: (closed ? 6.5 : 5) * pet.k
                }
            }
            // casque de jeu
            Rectangle {
                visible: pet.mood === "game" || pet.mood === "hot"
                x: -1 * pet.k
                y: -1.5 * pet.k
                width: parent.width + 2 * pet.k
                height: parent.height * 0.6
                color: "transparent"
                radius: width / 2
                border.width: 1.4 * pet.k
                border.color: Theme.tertiary
            }
        }
    }
    SequentialAnimation {
        id: hopAnim
        NumberAnimation { target: body; property: "hopY"; to: -6 * pet.k; duration: 200; easing.type: Easing.OutQuad }
        NumberAnimation { target: body; property: "hopY"; to: 0; duration: 300; easing.type: Easing.OutBounce }
    }

    // effet : notes, z, coeur, goutte...
    Txt {
        id: fxText
        x: pet.width - 2
        y: -4
        px: 9 * pet.k
        weight: Font.DemiBold
        color: Theme.primary
        opacity: 0
    }
    ParallelAnimation {
        id: fxAnim
        SequentialAnimation {
            NumberAnimation { target: fxText; property: "opacity"; from: 0; to: 1; duration: 300 }
            NumberAnimation { target: fxText; property: "opacity"; to: 0; duration: 1300 }
        }
        NumberAnimation { target: fxText; property: "y"; from: 0; to: -14 * pet.k; duration: 1600; easing.type: Easing.OutQuad }
    }
}
