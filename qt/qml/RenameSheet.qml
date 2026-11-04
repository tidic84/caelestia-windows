import QtQuick

// Feuille « Renommer » du lanceur : nom affiché dans l'îlot et mots-clés de
// recherche d'une appli ou d'un jeu (maquette docs/dev/maquettes/renommer-apps.html).
// Rien n'est changé dans Windows : le nom d'origine reste cherchable.
Item {
    id: s
    visible: false
    z: 11
    property string appId: ""
    property string origName: ""
    property var keys: []
    property string startName: ""
    property var startKeys: []
    // fin de l'edition : nom ("" = nom d'origine), mots-cles
    signal saved(string id, string name, var keys)
    readonly property bool dirty: nameField.text.trim() !== startName || JSON.stringify(keys) !== JSON.stringify(startKeys)

    function open(id, orig, name, list) {
        appId = id
        origName = orig
        startName = name || ""
        startKeys = (list || []).slice()
        keys = startKeys.slice()
        nameField.text = startName
        keyField.text = ""
        visible = true
        nameField.input.forceActiveFocus()
        nameField.input.selectAll()
    }
    function close() {
        visible = false
    }
    function addKey(t) {
        t = t.trim().replace(/\s+/g, " ")
        if (t.length < 2 || keys.some(k => Ilot.norm(k) === Ilot.norm(t)))
            return
        keys = keys.concat([t])
    }
    function save() {
        if (keyField.text.trim())
            addKey(keyField.text)
        keyField.text = ""
        const n = nameField.text.trim()
        s.saved(appId, n === origName ? "" : n, keys)
        close()
    }
    Keys.onEscapePressed: close()

    // voile : un clic a cote ferme sans enregistrer
    Rectangle {
        anchors.fill: parent
        radius: 20
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onClicked: s.close()
            onWheel: w => { w.accepted = true }
        }
    }

    Rectangle {
        id: card
        width: Math.min(460, parent.width - 20)
        height: col.implicitHeight + 32
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        radius: 24
        color: Theme.surfaceC
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
        Column {
            id: col
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 6
            Txt {
                text: "Renommer"
                px: 15
                weight: Font.Medium
            }
            Txt {
                width: parent.width
                text: "Nom dans Windows : " + s.origName
                px: 11.5
                color: Theme.outline
                elide: Text.ElideRight
            }
            Item { width: 1; height: 6 }
            Txt {
                text: "Nom affiché dans l’îlot"
                px: 12
                color: Theme.inkVariant
            }
            Field {
                id: nameField
                width: parent.width
                height: 40
                radius: 14
                fontSize: 14
                placeholder: s.origName
                onAccepted: s.save()
                onKeyPressed: e => {
                    if (e.key === Qt.Key_Tab) {
                        keyField.input.forceActiveFocus()
                        e.accepted = true
                    }
                }
            }
            Txt {
                width: parent.width
                wrapMode: Text.Wrap
                readonly property string n: nameField.text.trim()
                text: n && n !== s.origName ? "« " + s.origName + " » reste cherchable." : "Vide : l’îlot garde le nom de Windows."
                px: 11.5
                color: Theme.outline
            }
            Item { width: 1; height: 6 }
            Txt {
                text: "Mots-clés de recherche"
                px: 12
                color: Theme.inkVariant
            }
            Rectangle {
                width: parent.width
                height: flow.implicitHeight + 12
                radius: 14
                color: Theme.surfaceHighest
                Flow {
                    id: flow
                    x: 6
                    y: 6
                    width: parent.width - 12
                    spacing: 6
                    Repeater {
                        model: s.keys
                        Rectangle {
                            id: chip
                            required property string modelData
                            required property int index
                            width: Math.min(kt.implicitWidth + 40, flow.width)
                            height: 28
                            radius: 14
                            color: Theme.secondaryContainer
                            Txt {
                                id: kt
                                x: 11
                                width: chip.width - 40
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: chip.modelData
                                px: 12.5
                                color: Theme.inkSecondaryContainer
                            }
                            Btn {
                                anchors.right: parent.right
                                anchors.rightMargin: 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                radius: 11
                                color: hovered ? Theme.alpha(Theme.ink, 0.12) : "transparent"
                                tip: "Retirer"
                                onClicked: s.keys = s.keys.filter((k, i) => i !== chip.index)
                                Ms {
                                    anchors.centerIn: parent
                                    name: "close"
                                    size: 15
                                    color: Theme.inkSecondaryContainer
                                }
                            }
                        }
                    }
                    Field {
                        id: keyField
                        width: Math.min(150, flow.width)
                        height: 28
                        bg: "transparent"
                        pad: 6
                        placeholder: "Ajouter, puis Entrée"
                        onAccepted: {
                            if (!text.trim())
                                return s.save()
                            s.addKey(text)
                            text = ""
                        }
                        onKeyPressed: e => {
                            if (e.key === Qt.Key_Comma) {
                                s.addKey(text)
                                text = ""
                                e.accepted = true
                            } else if (e.key === Qt.Key_Backspace && text === "" && s.keys.length) {
                                s.keys = s.keys.slice(0, -1)
                                e.accepted = true
                            }
                        }
                    }
                }
            }
            Txt {
                width: parent.width
                wrapMode: Text.Wrap
                text: "L’appli sort quand la recherche commence par un de ces mots."
                px: 11.5
                color: Theme.outline
            }
            Item { width: 1; height: 8 }
            Item {
                width: parent.width
                height: 34
                TextBtn {
                    visible: s.startName !== "" || s.startKeys.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "settings_backup_restore"
                    text: "Tout rétablir"
                    color: hovered ? Theme.surfaceHighest : "transparent"
                    onClicked: {
                        nameField.text = ""
                        keyField.text = ""
                        s.keys = []
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    TextBtn {
                        text: "Annuler"
                        onClicked: s.close()
                    }
                    TextBtn {
                        text: "Enregistrer"
                        primary: true
                        disabled: !s.dirty && keyField.text.trim() === ""
                        onClicked: s.save()
                    }
                }
            }
        }
    }
}
