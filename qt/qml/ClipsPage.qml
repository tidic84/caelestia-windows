import QtQuick

// Presse-papiers : historique (texte et images) et bloc-notes
// (%LOCALAPPDATA%\Ilot\notes.json)
Item {
    id: page
    // "hist" | "notes"
    property string view: "hist"
    property string status: ""
    readonly property int n: Ilot.clips.length
    readonly property string count: n ? n + " élément" + (n > 1 ? "s" : "") : "Historique vide"
    function noteStatus() {
        const c = notes.text.length
        return c ? c + " caractère" + (c > 1 ? "s" : "") : "Bloc-notes vide"
    }
    function flash(msg, ms) {
        status = msg
        statusTimer.interval = ms
        statusTimer.restart()
    }
    Timer {
        id: statusTimer
        onTriggered: page.status = ""
    }
    Timer {
        id: saveTimer
        interval: 400
        onTriggered: Api.invoke("store_set", { key: "notes", value: { text: notes.text } }).then(ok => page.flash(ok ? "Enregistré" : "Erreur d’enregistrement", 1500))
    }
    function saveNotes() {
        Ilot.notes = notes.text
        saveTimer.restart()
    }
    function addToNotes(t) {
        const v = notes.text.replace(/\s+$/, "")
        notes.text = (v ? v + "\n\n" : "") + t
        saveNotes()
    }

    Item {
        id: head
        width: parent.width
        height: 32
        Seg {
            id: seg
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            model: [{ id: "hist", label: "Historique" }, { id: "notes", label: "Bloc-notes" }]
            current: page.view
            onPicked: id => {
                page.view = id
                if (id === "notes")
                    notes.edit.forceActiveFocus()
            }
        }
        Txt {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: (seg.width - buttons.width) / 2
            text: page.view === "notes" ? (page.status || (notes.text, page.noteStatus())) : page.count
            color: Theme.inkVariant
        }
        Row {
            id: buttons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            TextBtn {
                visible: page.view === "hist"
                icon: "delete"
                text: "Effacer"
                onClicked: Api.invoke("clips_clear")
            }
            TextBtn {
                visible: page.view === "notes"
                icon: "content_copy"
                text: "Copier"
                onClicked: {
                    Api.invoke("clip_text", { text: notes.text })
                    page.flash("Copié", 1200)
                }
            }
        }
    }

    Flickable {
        id: flick
        visible: page.view === "hist"
        y: head.height + 10
        width: parent.width - 4
        height: parent.height - y
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            spacing: 6
            Empty {
                visible: page.n === 0
                width: parent.width
                text: "Copiez du texte ou une image : ils apparaîtront ici."
            }
            Repeater {
                model: Ilot.clips
                Btn {
                    id: clip
                    required property var modelData
                    readonly property bool isText: modelData.text !== null && modelData.text !== undefined
                    property bool done: false
                    width: col.width
                    height: isText ? Math.max(42, txt.implicitHeight + 22) : Math.min(120, imgBox.h) + 16
                    radius: 16
                    color: hovered ? Theme.surfaceHigh : Theme.surfaceC
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Timer {
                        id: doneTimer
                        interval: 1200
                        onTriggered: clip.done = false
                    }
                    onClicked: {
                        Api.invoke("clip_copy", { id: modelData.id })
                        done = true
                        doneTimer.restart()
                    }
                    Txt {
                        id: txt
                        visible: clip.isText
                        x: 14
                        width: parent.width - 14 - 14 - 12 - 20 - 12 - 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: clip.isText ? (clip.modelData.text.length > 600 ? clip.modelData.text.slice(0, 600) + "…" : clip.modelData.text) : ""
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        lineHeight: 1.35
                        textFormat: Text.PlainText
                    }
                    // image : damier sous la transparence
                    Item {
                        id: imgBox
                        visible: !clip.isText
                        x: 8
                        y: 8
                        readonly property real w: clip.modelData.w || 1
                        readonly property real h: clip.modelData.h || 1
                        readonly property real k: Math.min(120 / h, (clip.width * 0.7) / w, 1)
                        width: w * k
                        height: Math.min(120, h * k)
                        Canvas {
                            anchors.fill: parent
                            visible: imgBox.visible
                            readonly property color a: Theme.surfaceHigh
                            readonly property color b: Theme.surfaceHighest
                            onAChanged: requestPaint()
                            onPaint: {
                                const g = getContext("2d")
                                g.fillStyle = a
                                g.fillRect(0, 0, width, height)
                                g.fillStyle = b
                                for (let y = 0; y < height; y += 7)
                                    for (let x = ((y / 7) % 2) * 7; x < width; x += 14)
                                        g.fillRect(x, y, 7, 7)
                            }
                        }
                        RoundImage {
                            anchors.fill: parent
                            radius: 10
                            cover: false
                            source: clip.isText ? "" : clip.modelData.thumb || ""
                        }
                    }
                    Txt {
                        visible: !clip.isText
                        x: imgBox.x + imgBox.width + 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: (clip.modelData.w || 0) + " × " + (clip.modelData.h || 0)
                        px: 12
                        color: Theme.inkVariant
                    }
                    // ajouter au bloc-notes
                    Btn {
                        visible: clip.isText
                        anchors.right: check.left
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        radius: 14
                        opacity: clip.hovered || hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        color: hovered ? Theme.surfaceHighest : "transparent"
                        tip: "Ajouter au bloc-notes"
                        onClicked: {
                            page.addToNotes(clip.modelData.text)
                            clip.done = true
                            doneTimer.restart()
                        }
                        Ms {
                            anchors.centerIn: parent
                            name: "note_add"
                            size: 18
                            color: parent.hovered ? Theme.ink : Theme.inkVariant
                        }
                    }
                    Ms {
                        id: check
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check"
                        color: Theme.primary
                        opacity: clip.done ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }
            }
        }
    }
    Scroller { flick: flick }

    Area {
        id: notes
        visible: page.view === "notes"
        y: head.height + 10
        width: parent.width
        height: parent.height - y
        radius: 18
        color: Theme.surfaceC
        fontSize: 14
        padX: 16
        padY: 14
        placeholder: "Écrivez vos notes ici… Elles sont enregistrées automatiquement."
        text: Ilot.notes
        // on ecrit : l'ilot reste ouvert meme si la souris sort
        onFocused: Ilot.pinned = true
        onEdited: page.saveNotes()
    }
}
