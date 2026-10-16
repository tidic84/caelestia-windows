import QtQuick

// Partage avec le telephone (src/share.rs) : petit serveur web local, adresse
// avec jeton dans un QR code. Les fichiers deposes sur l'ilot pendant que la
// fenetre est ouverte sont ajoutes au partage.
Item {
    id: pop
    visible: Watch.shareOpen
    // clic a cote : referme
    MouseArea {
        anchors.fill: parent
        onClicked: Watch.shareOpen = false
    }
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.surface, 0.6)
    }
    DropArea {
        anchors.fill: parent
        onDropped: d => {
            const paths = (d.urls || []).map(u => decodeURIComponent(String(u).replace(/^file:\/\/\//, "")).replace(/\//g, "\\"))
            if (paths.length)
                Watch.openShare(paths)
        }
    }

    Card {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        height: Math.min(parent.height - 20, body.height + 32)
        color: Theme.surfaceHigh
        MouseArea { anchors.fill: parent }
        Row {
            id: body
            x: 16
            y: 16
            spacing: 16
            Rectangle {
                width: 196
                height: 196
                radius: 16
                color: "white"
                Image {
                    anchors.centerIn: parent
                    width: 180
                    height: 180
                    smooth: false
                    source: Watch.share ? Watch.share.qr : ""
                }
                Spinner {
                    anchors.centerIn: parent
                    visible: !Watch.share && !Watch.shareErr
                }
            }
            Column {
                width: card.width - 32 - 212
                spacing: 6
                Item {
                    width: parent.width
                    height: 26
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Partage avec le téléphone"
                        px: 14
                        weight: Font.Bold
                    }
                    IconBtn {
                        anchors.right: parent.right
                        small: true
                        icon: "close"
                        tip: "Fermer"
                        onClicked: Watch.shareOpen = false
                    }
                }
                Txt {
                    width: parent.width
                    wrapMode: Text.Wrap
                    px: 11.5
                    color: Theme.inkVariant
                    text: "Scanne le QR code avec l'appareil photo du téléphone (même Wi-Fi que le PC). Dépose d'autres fichiers sur l'îlot pour les ajouter."
                }
                Btn {
                    width: parent.width
                    height: 26
                    radius: 8
                    color: hovered ? Theme.surfaceHighest : "transparent"
                    tip: "Clic pour copier le lien"
                    onClicked: if (Watch.share) Api.invoke("clip_text", { text: Watch.share.url })
                    Txt {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        text: Watch.share ? Watch.share.url : Watch.shareErr
                        px: 12
                        color: Watch.shareErr ? Theme.error : Theme.primary
                        elide: Text.ElideRight
                    }
                }
                Txt {
                    text: "Fichiers partagés"
                    px: 11.5
                    weight: Font.Medium
                    color: Theme.inkVariant
                }
                Repeater {
                    model: Watch.share ? Watch.share.files : []
                    Row {
                        required property var modelData
                        spacing: 6
                        Ms {
                            name: "description"
                            size: 16
                            color: Theme.inkVariant
                        }
                        Txt {
                            text: parent.modelData
                            px: 12
                            elide: Text.ElideMiddle
                            width: Math.min(implicitWidth, 220)
                        }
                        Txt {
                            visible: !!Watch.shareSent[parent.modelData]
                            text: "✓ récupéré"
                            px: 11
                            color: Theme.ok
                        }
                    }
                }
                Txt {
                    visible: !Watch.share || !Watch.share.files.length
                    text: "Aucun : le téléphone peut seulement envoyer."
                    px: 11.5
                    color: Theme.inkVariant
                }
                Txt {
                    text: "Reçus du téléphone (Téléchargements)"
                    px: 11.5
                    weight: Font.Medium
                    color: Theme.inkVariant
                }
                Repeater {
                    model: Watch.shareRecv.slice(0, 4)
                    Btn {
                        required property var modelData
                        width: parent.width
                        height: 24
                        radius: 8
                        color: hovered ? Theme.surfaceHighest : "transparent"
                        tip: "Afficher dans l’Explorateur"
                        onClicked: Api.invoke("file_reveal", { path: modelData.path })
                        Row {
                            spacing: 6
                            anchors.verticalCenter: parent.verticalCenter
                            Ms {
                                name: "download_done"
                                size: 16
                                color: Theme.primary
                            }
                            Txt {
                                text: parent.parent.modelData.name
                                px: 12
                            }
                        }
                    }
                }
                Txt {
                    visible: !Watch.shareRecv.length
                    text: "Rien pour l’instant."
                    px: 11.5
                    color: Theme.inkVariant
                }
                Item {
                    width: parent.width
                    height: 34
                    TextBtn {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        icon: "link_off"
                        text: "Arrêter le partage"
                        onClicked: Watch.stopShare()
                    }
                }
            }
        }
    }
}
