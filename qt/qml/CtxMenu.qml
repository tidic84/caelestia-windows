import QtQuick
import QtQuick.Effects

// Menu contextuel (clic droit) : entrees { type: "title" | "item" | "sep" |
// "input", icon, label, danger, on, run(entree), value, placeholder, done(texte) }.
// Une entree `danger` demande un second clic (son libelle devient `confirm`).
Rectangle {
    id: m
    property var entries: []
    // zone dans laquelle le menu reste (la page)
    property Item area: parent
    visible: false
    z: 10
    width: Math.max(200, Math.min(280, col.implicitWidth + 12))
    height: Math.min(area ? area.height : 400, col.height + 12)
    radius: 16
    color: Theme.surfaceHighest
    property string armed: ""

    RectangularShadow {
        z: -1
        anchors.fill: parent
        radius: parent.radius
        offset.y: 8
        blur: 28
        color: Qt.rgba(0, 0, 0, 0.45)
    }

    function show(x, y, list) {
        armed = ""
        entries = list
        visible = true
        opacity = 0
        fade.restart()
        // dans la page, sans en sortir
        Qt.callLater(() => {
            m.x = Math.max(0, Math.min(x, m.area.width - m.width - 4))
            m.y = Math.max(0, Math.min(y, m.area.height - m.height - 4))
            for (let i = 0; i < col.children.length; i++) {
                if (col.children[i].isInput) {
                    col.children[i].focusInput()
                    break
                }
            }
        })
    }
    function hide() {
        visible = false
        entries = []
    }
    NumberAnimation {
        id: fade
        target: m
        property: "opacity"
        from: 0
        to: 1
        duration: 120
    }

    // le fond du menu garde clics et survol (titres, separateurs, marges)
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
    }
    Flickable {
        anchors.fill: parent
        anchors.margins: 6
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            Repeater {
                model: m.entries
                Item {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property string type: modelData.type || "item"
                    readonly property bool isInput: type === "input"
                    function focusInput() {
                        field.input.forceActiveFocus()
                        field.input.selectAll()
                    }
                    width: col.width
                    implicitWidth: type === "item" ? itemLabel.implicitWidth + 50 : type === "title" ? titleText.implicitWidth + 20 : 0
                    height: type === "title" ? 28 : type === "sep" ? 9 : type === "input" ? 44 : 36

                    Txt {
                        id: titleText
                        visible: entry.type === "title"
                        x: 10
                        width: parent.width - 20
                        height: parent.height
                        text: entry.modelData.label || ""
                        px: 11.5
                        color: Theme.inkVariant
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: entry.type === "sep"
                        x: 6
                        width: parent.width - 12
                        height: 1
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.outlineVariant
                    }
                    Field {
                        id: field
                        visible: entry.isInput
                        x: 4
                        y: 2
                        width: parent.width - 8
                        height: 38
                        radius: 10
                        pad: 10
                        bg: Theme.surfaceC
                        focusRing: true
                        text: entry.modelData.value || ""
                        placeholder: entry.modelData.placeholder || "Nom du dossier"
                        onAccepted: {
                            if (text.trim()) {
                                const done = entry.modelData.done
                                const v = text.trim()
                                m.hide()
                                done(v)
                            }
                        }
                        Keys.onEscapePressed: e => {
                            m.hide()
                            e.accepted = true
                        }
                    }
                    Btn {
                        id: itemBtn
                        visible: entry.type === "item"
                        anchors.fill: parent
                        radius: 10
                        readonly property bool armed: m.armed !== "" && m.armed === String(entry.index)
                        readonly property bool red: armed || (!!entry.modelData.danger && hovered)
                        color: red ? Theme.error : hovered ? Theme.alpha(Theme.ink, 0.1) : "transparent"
                        readonly property color fg: red ? Theme.inkError : entry.modelData.on ? Theme.primary : Theme.ink
                        onClicked: {
                            const e = entry.modelData
                            if (e.danger && !armed) {
                                m.armed = String(entry.index)
                                return
                            }
                            e.run(e)
                        }
                        Row {
                            x: 10
                            spacing: 10
                            anchors.verticalCenter: parent.verticalCenter
                            Ms {
                                name: entry.modelData.icon || ""
                                size: 18
                                color: itemBtn.red ? Theme.inkError : entry.modelData.on ? Theme.primary : Theme.inkVariant
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Txt {
                                id: itemLabel
                                width: Math.min(implicitWidth, col.width - 48)
                                text: itemBtn.armed ? (entry.modelData.confirm || "Confirmer") : (entry.modelData.label || "")
                                color: itemBtn.fg
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
