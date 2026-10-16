import QtQuick

// Convertisseur de sensibilite : meme vitesse de visee d'un jeu a l'autre,
// et cm pour un tour complet (360°). Garde dans ui.json.
PcCard {
    id: sc
    title: "Convertisseur de sensibilité"
    // degres tournes par « point » de souris a la sensibilite 1
    readonly property var games: [
        ["apex", "Apex Legends", 0.022], ["cs2", "Counter-Strike 2", 0.022], ["valorant", "Valorant", 0.07],
        ["ow2", "Overwatch 2", 0.0066], ["cod", "Call of Duty (MW / Warzone)", 0.0066], ["tf2", "Titanfall 2", 0.022],
        ["gmod", "Garry’s Mod", 0.022], ["quake", "Quake Champions", 0.022]
    ]
    readonly property var s: Ilot.ui.sens || ({ game: "apex", val: "", dpi: "800" })
    readonly property var src: games.find(g => g[0] === s.game) || games[0]
    readonly property real v: parseFloat(String(s.val).replace(",", "."))
    readonly property real dpi: parseFloat(s.dpi)
    readonly property bool ok: v > 0 && dpi > 0
    readonly property real deg: ok ? v * src[2] : 0
    function set(patch) {
        Ilot.saveUi({ sens: Object.assign({}, s, patch) })
    }

    Row {
        spacing: 4
        Btn {
            id: gameBtn
            width: sc.width - 28 - 4 * 2 - 60 - 56
            height: 30
            radius: 10
            color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
            tip: "Jeu de départ"
            onClicked: {
                // liste des jeux sous le bouton
                menu.visible = !menu.visible
            }
            Txt {
                x: 10
                width: parent.width - 30
                anchors.verticalCenter: parent.verticalCenter
                text: sc.src[1]
                px: 11.5
                elide: Text.ElideRight
            }
            Ms {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                name: "expand_more"
                size: 16
                color: Theme.inkVariant
            }
        }
        Field {
            width: 60
            height: 30
            radius: 10
            pad: 8
            fontSize: 12
            bg: Theme.surfaceHigh
            placeholder: "Sensi"
            text: sc.s.val
            input.validator: RegularExpressionValidator { regularExpression: /^[0-9]*[.,]?[0-9]*$/ }
            onFocused: Ilot.pinned = true
            onEdited: sc.set({ val: text })
        }
        Field {
            width: 56
            height: 30
            radius: 10
            pad: 8
            fontSize: 12
            bg: Theme.surfaceHigh
            placeholder: "DPI"
            text: sc.s.dpi
            input.validator: IntValidator { bottom: 0; top: 64000 }
            onFocused: Ilot.pinned = true
            onEdited: sc.set({ dpi: text })
        }
    }
    Column {
        id: menu
        visible: false
        width: parent.width
        spacing: 2
        Repeater {
            model: sc.games
            Btn {
                required property var modelData
                width: menu.width
                height: 26
                radius: 8
                color: modelData[0] === sc.s.game ? Theme.secondaryContainer : hovered ? Theme.surfaceHighest : "transparent"
                onClicked: {
                    sc.set({ game: modelData[0] })
                    menu.visible = false
                }
                Txt {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData[1]
                    px: 11.5
                }
            }
        }
    }
    Txt {
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        px: 11.5
        color: sc.ok ? Theme.ink : Theme.inkVariant
        text: sc.ok ? "<b>" + (360 / (sc.deg * sc.dpi) * 2.54).toFixed(1).replace(".", ",") + " cm</b> pour un tour complet (360°)"
            : "Entre ta sensi et le DPI de ta souris."
    }
    Repeater {
        model: sc.ok ? sc.games.filter(g => g[0] !== sc.src[0]) : []
        Btn {
            id: out
            required property var modelData
            readonly property string val: (sc.deg / modelData[2]).toFixed(3).replace(/\.?0+$/, "")
            property bool done: false
            width: parent.width
            height: 24
            radius: 8
            color: done ? Theme.secondaryContainer : hovered ? Theme.surfaceHigh : "transparent"
            tip: "Copier"
            onClicked: {
                Api.invoke("clip_text", { text: val })
                done = true
                doneTimer.restart()
            }
            Timer {
                id: doneTimer
                interval: 1000
                onTriggered: out.done = false
            }
            Txt {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                text: out.modelData[1]
                px: 11.5
                color: Theme.inkVariant
            }
            Txt {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: out.val
                px: 12
                weight: Font.DemiBold
                tnum: true
            }
        }
    }
}
