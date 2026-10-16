import QtQuick

// Extinction programmee (Watch.off) : eteindre, mettre en veille ou
// redemarrer dans 30 min, 1 h, 2 h, a une heure precise, a la fin du media
// ou quand les mises a jour Steam sont finies.
PcCard {
    id: oc
    title: "Extinction programmée"
    readonly property string action: Watch.off ? Watch.off.action : Watch.offAction

    Row {
        spacing: 4
        Repeater {
            model: [["shutdown", "power_settings_new", "Éteindre"], ["sleep", "bedtime", "Veille"], ["restart", "restart_alt", "Redémarrer"]]
            Btn {
                required property var modelData
                readonly property bool on: oc.action === modelData[0]
                width: (oc.width - 28 - 8) / 3
                height: 30
                radius: on ? 15 : 10
                color: on ? Theme.secondaryContainer : hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                onClicked: {
                    Watch.offAction = modelData[0]
                    if (Watch.off) {
                        Watch.off = Object.assign({}, Watch.off, { action: modelData[0] })
                        Ilot.saveUi({ off: Watch.off })
                    }
                }
                Row {
                    anchors.centerIn: parent
                    spacing: 3
                    Ms {
                        name: parent.parent.modelData[1]
                        size: 15
                        color: parent.parent.on ? Theme.inkSecondaryContainer : Theme.ink
                    }
                    Txt {
                        text: parent.parent.modelData[2]
                        px: 11
                        color: parent.parent.on ? Theme.inkSecondaryContainer : Theme.ink
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
    Flow {
        width: parent.width
        spacing: 4
        Repeater {
            model: [[30, "30 min"], [60, "1 h"], [120, "2 h"]]
            Chipb {
                required property var modelData
                text: modelData[1]
                onClicked: Watch.offIn(modelData[0])
            }
        }
        // a une heure precise : HH:MM puis Entree
        Rectangle {
            width: 78
            height: 28
            radius: 14
            color: Theme.surfaceHigh
            Ms {
                x: 7
                name: "schedule"
                size: 15
                color: Theme.inkVariant
                anchors.verticalCenter: parent.verticalCenter
            }
            Field {
                id: at
                x: 22
                width: parent.width - 24
                height: parent.height
                bg: "transparent"
                pad: 4
                fontSize: 12
                placeholder: "23:30"
                input.inputMask: "99:99;_"
                input.maximumLength: 5
                onFocused: Ilot.pinned = true
                onAccepted: {
                    Watch.offAt(text)
                    text = ""
                }
            }
        }
        Chipb {
            text: "Fin du média"
            icon: "movie"
            tip: "Quand la musique ou la vidéo s'arrête"
            onClicked: Watch.setOff({ action: Watch.offAction, wait: "media" })
        }
        Chipb {
            text: "Fin MAJ Steam"
            icon: "download"
            tip: "Quand les téléchargements Steam sont finis"
            onClicked: Watch.setOff({ action: Watch.offAction, wait: "steam" })
        }
    }
    Rectangle {
        visible: !!Watch.off
        width: parent.width
        height: 32
        radius: 12
        color: Theme.tertiaryContainer
        Ms {
            x: 8
            name: "timer"
            size: 17
            color: Theme.inkTertiaryContainer
            anchors.verticalCenter: parent.verticalCenter
        }
        Txt {
            x: 30
            width: parent.width - 30 - cancel.width - 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            px: 11.5
            color: Theme.inkTertiaryContainer
            text: !Watch.off ? "" : Watch.off.at ? Watch.offLabel[Watch.off.action] + " dans " + Watch.fmtLeft(Watch.off.at - Watch.now)
                : Watch.offLabel[Watch.off.action] + (Watch.off.wait === "media" ? " à la fin du média" : " à la fin des MAJ Steam")
        }
        TextBtn {
            id: cancel
            anchors.right: parent.right
            anchors.rightMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            height: 26
            text: "Annuler"
            onClicked: {
                Watch.setOff(null)
                Watch.osd("timer_off", null, "Extinction annulée")
            }
        }
    }

    component Chipb: Btn {
        id: cb
        property string text
        property string icon: ""
        width: cbRow.implicitWidth + 18
        height: 28
        radius: 14
        color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
        Row {
            id: cbRow
            anchors.centerIn: parent
            spacing: 3
            Ms {
                visible: cb.icon !== ""
                name: cb.icon
                size: 15
                color: Theme.inkVariant
            }
            Txt {
                text: cb.text
                px: 11.5
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
