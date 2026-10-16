import QtQuick

// Bandeau des sous-titres en direct, en bas de l'ecran de l'ilot : texte
// reconnu par Live Captions (src/captions.rs), traduit en francais. La fenetre
// laisse passer la souris.
Window {
    id: w
    // ecran de l'ilot (donne par Main)
    property var host
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    color: "transparent"
    title: "Ilot sous-titres"
    visible: Watch.capOn
    readonly property var scr: host ? host.screen : null
    width: scr ? Math.round(scr.width * 0.62) : 900
    height: 170
    x: scr ? scr.virtualX + (scr.width - width) / 2 : 0
    y: scr ? scr.virtualY + scr.height - height - 90 : 0

    property string to: "fr"
    property string tr: ""
    property string src: ""
    property string hint: ""
    property bool shown: false
    property string pending: ""
    property bool busy: false
    property string last: ""

    Timer {
        id: hideTimer
        // plus personne ne parle : le bandeau s'efface
        interval: 6000
        onTriggered: w.shown = false
    }
    function show() {
        shown = true
        hideTimer.restart()
    }
    Timer {
        id: gap
        // une traduction toutes les 0,6 s au plus : le texte change en continu
        interval: 600
        onTriggered: {
            w.busy = false
            w.translate()
        }
    }
    function translate() {
        if (busy || !pending)
            return
        busy = true
        const text = pending
        pending = ""
        Api.invoke("translate", { text: text, from: "", to: to }).then(r => {
            // deja en francais : pas de doublon
            if (r.detected === w.to) {
                w.tr = text
                w.src = ""
            } else {
                w.tr = r.text
                w.src = text.split("\n").pop()
            }
            w.hint = ""
            w.show()
            gap.restart()
        }, () => {
            w.tr = text
            w.src = ""
            gap.restart()
        })
    }
    Connections {
        target: Watch
        function onCaptionChanged() {
            const c = Watch.caption
            if (c.status === "starting" && !c.text) {
                w.tr = "Sous-titres en direct…"
                w.hint = "1re fois : accepte le téléchargement de la langue dans la fenêtre Live Captions"
                return w.show()
            }
            if (c.status === "missing") {
                w.tr = "Live Captions introuvable sur ce PC"
                w.hint = ""
                return w.show()
            }
            if (c.status === "docked" && !c.text) {
                w.tr = "Live Captions est ancré en haut de l’écran"
                w.hint = "Dans Live Captions ⚙️ › Position › Flottante"
                return w.show()
            }
            if (!c.text || c.text === w.last)
                return
            w.last = c.text
            w.pending = c.text
            w.translate()
        }
        function onCapOnChanged() {
            if (!Watch.capOn) {
                w.shown = false
                w.last = ""
            }
        }
    }

    Rectangle {
        id: box
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: Math.min(parent.width - 20, Math.max(trText.implicitWidth, srcText.implicitWidth) + 44)
        height: col.height + 22
        radius: 18
        color: Qt.rgba(10 / 255, 10 / 255, 14 / 255, 0.78)
        opacity: w.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
        Column {
            id: col
            anchors.centerIn: parent
            width: box.width - 44
            spacing: 4
            Txt {
                id: trText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideLeft
                text: w.tr
                px: 22
                weight: Font.Medium
                color: "white"
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.6)
            }
            Txt {
                id: srcText
                visible: text !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideLeft
                text: w.hint || w.src
                px: w.hint ? 14 : 13
                color: w.hint ? "#ffd27a" : Qt.rgba(1, 1, 1, 0.6)
            }
        }
    }
}
