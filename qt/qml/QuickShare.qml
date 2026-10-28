import QtQuick

// Quick Share (src/quickshare) : envoyer aux appareils a proximite les
// fichiers deposes sur l'ilot (ou un texte, un lien), recevoir (nom,
// visibilite) et suivre les transferts. Prend la place de la page en cours
// tant que Watch.shareOpen.
Item {
    id: page
    readonly property var st: Watch.qs
    readonly property bool hasStuff: Watch.qsFiles.length > 0 || textField.text.trim() !== ""
    property bool qrShown: false
    onQrShownChanged: Api.invoke("qs_qr", { on: qrShown })
    onVisibleChanged: if (!visible) {
        qrShown = false
        textField.text = ""
    }

    // l'heure, pour le compte a rebours de « Visible 10 min »
    property real now: Date.now()
    property real tempEnd: 0
    Component.onCompleted: nameField.text = st.name
    onStChanged: {
        tempEnd = st.temp_left > 0 ? Date.now() + st.temp_left * 1000 : 0
        // le nom n'est pas lie : une mise a jour effacerait la saisie en cours
        if (!nameField.input.activeFocus)
            nameField.text = st.name
    }
    Timer {
        running: page.visible && page.tempEnd > 0
        interval: 10000
        repeat: true
        onTriggered: page.now = Date.now()
    }

    function size(b) {
        return b >= 1073741824 ? (b / 1073741824).toFixed(1).replace(".", ",") + " Go"
            : b >= 1048576 ? (b / 1048576).toFixed(1).replace(".", ",") + " Mo"
            : b >= 1024 ? Math.round(b / 1024) + " Ko" : b + " o"
    }
    function fileIcon(name) {
        const ext = String(name).split(".").pop().toLowerCase()
        return ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp"].indexOf(ext) >= 0 ? "image"
            : ["mp4", "mkv", "mov", "webm", "avi"].indexOf(ext) >= 0 ? "movie"
            : ["mp3", "m4a", "flac", "wav", "ogg", "opus"].indexOf(ext) >= 0 ? "audiotrack"
            : ["zip", "7z", "rar"].indexOf(ext) >= 0 ? "folder_zip" : "description"
    }
    function itemIcon(it) {
        return it.kind === "url" ? "link" : it.kind === "text" ? "notes" : it.kind === "wifi" ? "wifi_password" : fileIcon(it.name)
    }
    function sendTo(id) {
        if (!hasStuff)
            return
        Watch.qsSend(id, textField.text.trim())
        textField.text = ""
    }
    function statusText(t) {
        switch (t.status) {
        case "ask": return "Code " + t.pin + " : vérifie qu’il s’affiche aussi sur l’appareil"
        case "connecting": return "Connexion…"
        case "waiting": return "En attente d’acceptation" + (t.pin ? " · code " + t.pin : "")
        case "transfer": return (t.total ? Math.floor(t.done / t.total * 100) + " % · " + size(t.done) + " sur " + size(t.total) : "Envoi…")
        case "done": return t.out ? "Envoyé" : t.items.some(i => i.kind === "file") ? "Reçu · Téléchargements" : "Reçu"
        case "rejected": return t.error || "Refusé"
        case "cancelled": return t.error || "Annulé"
        default: return t.error || "Échec"
        }
    }

    // ================================================== envoyer
    Card {
        id: sendCard
        width: Math.round(parent.width * 0.56)
        height: parent.height
        clip: true

        // fichiers deposes n'importe ou sur la carte
        DropArea {
            id: drop
            anchors.fill: parent
            onEntered: d => {
                if (!d.hasUrls)
                    return d.accepted = false
                Ilot.dragIn()
            }
            onExited: Ilot.dragLeft()
            onDropped: d => {
                Ilot.dragDone()
                d.acceptProposedAction()
                Watch.addShareFiles(Ilot.dropPaths(d.urls))
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.alpha(Theme.primary, 0.06)
            border.width: 2
            border.color: Theme.primary
            visible: drop.containsDrag
        }

        Column {
            id: sendCol
            x: 16
            y: 12
            width: parent.width - 32
            spacing: 10

            Item {
                width: parent.width
                height: 30
                Row {
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Ms {
                        name: "nearby"
                        size: 22
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Txt {
                        text: "Quick Share"
                        px: 15
                        weight: Font.Bold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    IconBtn {
                        small: true
                        visible: Watch.qsFiles.length > 0
                        icon: "clear_all"
                        tip: "Retirer tous les fichiers"
                        onClicked: Watch.clearShareFiles()
                    }
                    IconBtn {
                        small: true
                        on: page.qrShown
                        icon: "qr_code_2"
                        tip: "QR code : l’appareil photo du téléphone le scanne et reçoit les fichiers"
                        onClicked: page.qrShown = !page.qrShown
                    }
                }
            }

            // fichiers a envoyer
            Rectangle {
                width: parent.width
                height: Watch.qsFiles.length ? Math.min(files.contentHeight + 12, 128) : 66
                radius: 16
                color: Theme.surfaceHigh
                border.width: Ilot.fileDrag && !drop.containsDrag ? 1.5 : 0
                border.color: Theme.alpha(Theme.primary, 0.6)
                Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
                Column {
                    visible: !Watch.qsFiles.length
                    anchors.centerIn: parent
                    spacing: 2
                    Ms {
                        name: "upload_file"
                        size: 24
                        color: Ilot.fileDrag ? Theme.primary : Theme.inkVariant
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Txt {
                        text: Ilot.fileDrag ? "Lâche ici" : "Dépose des fichiers sur l’îlot"
                        px: 12
                        color: Theme.inkVariant
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
                Flickable {
                    id: files
                    anchors.fill: parent
                    anchors.margins: 6
                    contentHeight: fileCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: fileCol
                        width: parent.width
                        Repeater {
                            model: Watch.qsFiles
                            Item {
                                id: fileRow
                                required property var modelData
                                readonly property string name: modelData.split("\\").pop()
                                width: fileCol.width
                                height: 28
                                Ms {
                                    x: 6
                                    name: page.fileIcon(fileRow.name)
                                    size: 17
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Txt {
                                    x: 30
                                    width: parent.width - 64
                                    text: fileRow.name
                                    px: 12.5
                                    elide: Text.ElideMiddle
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                IconBtn {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    small: true
                                    iconSize: 16
                                    icon: "close"
                                    tip: "Retirer"
                                    onClicked: Watch.removeShareFile(fileRow.modelData)
                                }
                            }
                        }
                    }
                }
                Scroller { flick: files }
            }

            Field {
                id: textField
                width: parent.width
                placeholder: "…ou un texte, un lien à envoyer"
            }

            Item {
                width: parent.width
                height: 20
                Txt {
                    text: page.qrShown ? "Avec le QR code" : "Appareils à proximité"
                    px: 12
                    weight: Font.Medium
                    color: Theme.inkVariant
                    anchors.verticalCenter: parent.verticalCenter
                }
                Spinner {
                    visible: page.st.discovering && !page.qrShown && page.st.devices.length > 0
                    size: 14
                    stroke: 2
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // appareils trouves
        Flickable {
            id: devs
            visible: !page.qrShown
            x: 10
            y: sendCol.y + sendCol.height + 4
            width: parent.width - 20
            height: parent.height - y - 8
            contentHeight: devFlow.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Flow {
                id: devFlow
                width: parent.width
                spacing: 4
                Repeater {
                    model: page.st.devices
                    Btn {
                        id: tile
                        required property var modelData
                        readonly property bool hot: tileDrop.containsDrag || (hovered && page.hasStuff)
                        width: 96
                        height: 98
                        radius: 18
                        color: hot ? Theme.surfaceHighest : "transparent"
                        tip: page.hasStuff ? "Envoyer à " + modelData.name : "Ajoute d’abord des fichiers ou un texte"
                        onClicked: page.sendTo(modelData.id)
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                width: 54
                                height: 54
                                radius: 27
                                color: tile.hot ? Theme.primary : Theme.primaryContainer
                                anchors.horizontalCenter: parent.horizontalCenter
                                scale: tileDrop.containsDrag ? 1.12 : 1
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Ms {
                                    anchors.centerIn: parent
                                    name: Watch.qsKindIcon(tile.modelData.kind)
                                    size: 26
                                    color: tile.hot ? Theme.inkPrimary : Theme.inkPrimaryContainer
                                }
                            }
                            Txt {
                                width: 88
                                text: tile.modelData.name
                                px: 12
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                        // fichiers laches directement sur l'appareil : envoyes tout de suite
                        DropArea {
                            id: tileDrop
                            anchors.fill: parent
                            onEntered: d => {
                                if (!d.hasUrls)
                                    return d.accepted = false
                                Ilot.dragIn()
                            }
                            onExited: Ilot.dragLeft()
                            onDropped: d => {
                                Ilot.dragDone()
                                d.acceptProposedAction()
                                Watch.addShareFiles(Ilot.dropPaths(d.urls))
                                page.sendTo(tile.modelData.id)
                            }
                        }
                    }
                }
            }
        }
        Scroller { flick: devs }

        // personne en vue : radar et conseils
        Column {
            visible: !page.qrShown && !page.st.devices.length
            x: 16
            y: devs.y + Math.max(0, (devs.height - height) / 2)
            width: parent.width - 32
            spacing: 6
            Item {
                width: 64
                height: 64
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        anchors.centerIn: parent
                        width: 64
                        height: 64
                        radius: 32
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.primary
                        opacity: 0
                        // arret : une animation arretee garde sa valeur, on masque l'anneau
                        visible: page.st.discovering && !Theme.reduced
                        SequentialAnimation on scale {
                            running: page.visible && page.st.discovering && !Theme.reduced
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 900 }
                            NumberAnimation { from: 0.4; to: 1.2; duration: 1800; easing.type: Easing.OutCubic }
                        }
                        SequentialAnimation on opacity {
                            running: page.visible && page.st.discovering && !Theme.reduced
                            loops: Animation.Infinite
                            // reprise (reouverture) : invisible pendant la pause
                            PropertyAction { value: 0 }
                            PauseAnimation { duration: index * 900 }
                            NumberAnimation { from: 0.7; to: 0; duration: 1800; easing.type: Easing.OutCubic }
                        }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 40
                    height: 40
                    radius: 20
                    color: Theme.primaryContainer
                    Ms {
                        anchors.centerIn: parent
                        name: "radar"
                        color: Theme.inkPrimaryContainer
                    }
                }
            }
            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Recherche des appareils…"
                weight: Font.Medium
            }
            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                px: 11.5
                color: Theme.inkVariant
                text: (page.st.ble === "off" ? "Bluetooth du PC indisponible : ouvre Quick Share sur le téléphone pour qu’il soit visible. "
                    : "Le téléphone doit être sur le même Wi-Fi, écran allumé. ") + "Sinon, scanne le QR code."
            }
            TextBtn {
                icon: "qr_code_2"
                text: "Afficher le QR code"
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: page.qrShown = true
            }
        }

        // QR code : le telephone qui le scanne recoit les fichiers sans confirmer
        Row {
            visible: page.qrShown
            x: 16
            y: devs.y + 4
            width: parent.width - 32
            spacing: 14
            Rectangle {
                width: 150
                height: 150
                radius: 16
                color: "white"
                Image {
                    anchors.centerIn: parent
                    width: 138
                    height: 138
                    smooth: false
                    source: page.st.qr ? page.st.qr.png : ""
                }
                Spinner {
                    anchors.centerIn: parent
                    visible: !page.st.qr
                }
            }
            Column {
                width: parent.width - 164
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Scanne-le avec l’appareil photo du téléphone"
                    weight: Font.Medium
                }
                Txt {
                    width: parent.width
                    wrapMode: Text.Wrap
                    px: 11.5
                    color: Theme.inkVariant
                    text: Watch.qsFiles.length ? "Les fichiers ci-dessus partent dès qu’il est connecté, sans avoir à accepter."
                        : "Ajoute d’abord des fichiers : ils partiront dès que le téléphone sera connecté."
                }
                TextBtn {
                    icon: "close"
                    text: "Fermer"
                    onClicked: page.qrShown = false
                }
            }
        }
    }

    // ================================================== recevoir
    Card {
        id: recvCard
        x: sendCard.width + 12
        width: parent.width - x
        height: recvCol.height + 24
        Column {
            id: recvCol
            x: 16
            y: 12
            width: parent.width - 32
            spacing: 8
            Txt {
                text: "Recevoir"
                px: 14
                weight: Font.Bold
            }
            Field {
                id: nameField
                width: parent.width
                placeholder: "Nom de ce PC"
                focusRing: true
                onAccepted: input.focus = false
                Connections {
                    target: nameField.input
                    function onEditingFinished() {
                        const n = nameField.text.trim()
                        if (n && n !== page.st.name)
                            Api.invoke("qs_config", { name: n })
                        else
                            nameField.text = page.st.name
                    }
                }
            }
            Seg {
                width: parent.width
                itemMaxWidth: (width - 6) / 3
                model: [
                    { id: "on", label: "Visible", tip: "Visible par tous les appareils sur le même Wi-Fi" },
                    { id: "temp", label: "10 min", tip: "Visible pendant 10 minutes, puis masqué" },
                    { id: "off", label: "Masqué", tip: "Personne ne peut t’envoyer de fichiers" }
                ]
                current: page.st.visibility
                onPicked: id => Api.invoke("qs_config", { visibility: id })
            }
            Row {
                width: parent.width
                spacing: 6
                Ms {
                    name: page.st.error ? "error" : page.st.visibility === "off" ? "visibility_off" : "visibility"
                    size: 16
                    color: page.st.error ? Theme.error : Theme.inkVariant
                    anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                    width: parent.width - 22
                    px: 11.5
                    elide: Text.ElideRight
                    color: page.st.error ? Theme.error : Theme.inkVariant
                    text: page.st.error ? page.st.error
                        : page.st.visibility === "off" ? "Personne ne peut t’envoyer de fichiers"
                        : page.st.visibility === "temp" ? "Visible encore " + Math.max(1, Math.ceil((page.tempEnd - page.now) / 60000)) + " min"
                        : "Visible sur le Wi-Fi" + (page.st.ip ? " (" + page.st.ip + ")" : "")
                }
            }
        }
    }

    // ================================================== activite
    Card {
        id: actCard
        x: recvCard.x
        y: recvCard.height + 12
        width: recvCard.width
        height: parent.height - y
        Item {
            id: actHead
            x: 16
            y: 10
            width: parent.width - 32
            height: 28
            Txt {
                text: "Activité"
                px: 14
                weight: Font.Bold
                anchors.verticalCenter: parent.verticalCenter
            }
            TextBtn {
                visible: page.st.transfers.some(t => ["done", "rejected", "cancelled", "failed"].indexOf(t.status) >= 0)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 26
                text: "Effacer"
                onClicked: Api.invoke("qs_clear", { id: null })
            }
        }
        Empty {
            visible: !page.st.transfers.length
            y: actHead.y + actHead.height
            width: parent.width
            height: parent.height - y
            small: true
            icon: "nearby"
            text: "Les fichiers reçus arrivent dans Téléchargements, les textes dans le presse-papiers."
        }
        Flickable {
            id: acts
            x: 10
            y: actHead.y + actHead.height + 6
            width: parent.width - 20
            height: parent.height - y - 10
            contentHeight: actCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: actCol
                width: parent.width
                spacing: 6
                Repeater {
                    model: page.st.transfers
                    Rectangle {
                        id: row
                        required property var modelData
                        readonly property var t: modelData
                        readonly property bool live: ["connecting", "waiting", "transfer", "ask"].indexOf(t.status) >= 0
                        readonly property var one: t.items.length === 1 ? t.items[0] : null
                        width: actCol.width
                        height: rowCol.height + 20
                        radius: 16
                        color: t.status === "ask" ? Theme.secondaryContainer : Theme.surfaceHigh
                        Rectangle {
                            x: 10
                            y: 10
                            width: 34
                            height: 34
                            radius: 17
                            color: Theme.primaryContainer
                            Ms {
                                anchors.centerIn: parent
                                name: Watch.qsKindIcon(row.t.kind)
                                size: 18
                                color: Theme.inkPrimaryContainer
                            }
                            // sens du transfert
                            Rectangle {
                                x: 20
                                y: 20
                                width: 18
                                height: 18
                                radius: 9
                                color: row.color
                                Ms {
                                    anchors.centerIn: parent
                                    name: row.t.out ? "upload" : "download"
                                    size: 13
                                    color: Theme.primary
                                }
                            }
                        }
                        Column {
                            id: rowCol
                            x: 54
                            y: 10
                            width: parent.width - 64 - (closeBtn.visible ? 24 : 0)
                            spacing: 3
                            Txt {
                                width: parent.width
                                text: (row.t.out ? "Vers " : "De ") + row.t.peer
                                weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            // ce qui est partage (le premier element, puis « +2 »)
                            Row {
                                width: parent.width
                                spacing: 5
                                Ms {
                                    name: row.t.items.length ? page.itemIcon(row.t.items[0]) : "description"
                                    size: 14
                                    color: Theme.inkVariant
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Txt {
                                    width: Math.min(implicitWidth, parent.width - 19)
                                    px: 11.5
                                    color: Theme.inkVariant
                                    elide: Text.ElideMiddle
                                    text: (row.t.items.length ? row.t.items[0].name : "")
                                        + (row.t.items.length > 1 ? "  +" + (row.t.items.length - 1) : "")
                                        + (row.t.total ? " · " + page.size(row.t.total) : "")
                                }
                            }
                            // texte ou lien recu
                            Txt {
                                visible: row.t.text !== "" && !!row.one && row.one.kind !== "wifi"
                                width: parent.width
                                text: row.t.text
                                px: 12
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                color: row.one && row.one.kind === "url" ? Theme.primary : Theme.ink
                            }
                            Txt {
                                width: parent.width
                                px: 11.5
                                wrapMode: Text.Wrap
                                text: page.statusText(row.t)
                                color: row.t.status === "done" ? Theme.ok : ["failed", "rejected"].indexOf(row.t.status) >= 0 ? Theme.error
                                    : row.t.status === "ask" ? Theme.inkSecondaryContainer : Theme.inkVariant
                            }
                            Rectangle {
                                visible: row.t.status === "transfer" && row.t.total > 0
                                width: parent.width
                                height: 4
                                radius: 2
                                color: Theme.surfaceHighest
                                Rectangle {
                                    width: parent.width * Math.min(1, row.t.done / Math.max(1, row.t.total))
                                    height: parent.height
                                    radius: 2
                                    color: Theme.primary
                                    Behavior on width { NumberAnimation { duration: 200 } }
                                }
                            }
                            // actions
                            Flow {
                                width: parent.width
                                spacing: 6
                                topPadding: 3
                                TextBtn {
                                    visible: row.t.status === "ask"
                                    text: "Refuser"
                                    height: 28
                                    onClicked: Watch.qsAnswer(row.t.id, false)
                                }
                                TextBtn {
                                    visible: row.t.status === "ask"
                                    primary: true
                                    icon: "check"
                                    text: "Accepter"
                                    height: 28
                                    onClicked: Watch.qsAnswer(row.t.id, true)
                                }
                                TextBtn {
                                    visible: ["connecting", "waiting", "transfer"].indexOf(row.t.status) >= 0
                                    text: "Annuler"
                                    height: 28
                                    onClicked: Api.invoke("qs_cancel", { id: row.t.id })
                                }
                                TextBtn {
                                    visible: row.t.status === "done" && !row.t.out && !!row.one && row.one.kind === "file"
                                    icon: "open_in_new"
                                    text: "Ouvrir"
                                    height: 28
                                    onClicked: Api.invoke("file_open", { path: row.one.path })
                                }
                                TextBtn {
                                    visible: row.t.status === "done" && !row.t.out && row.t.items.some(i => i.kind === "file")
                                    icon: "folder_open"
                                    text: "Afficher"
                                    height: 28
                                    onClicked: Api.invoke("file_reveal", { path: row.t.items.find(i => i.kind === "file").path })
                                }
                                TextBtn {
                                    visible: row.t.status === "done" && !row.t.out && !!row.one && row.one.kind === "url"
                                    icon: "open_in_new"
                                    text: "Ouvrir le lien"
                                    height: 28
                                    onClicked: Api.invoke("open_url", { url: row.t.text })
                                }
                                TextBtn {
                                    visible: row.t.status === "done" && !row.t.out && !!row.one && row.one.kind === "wifi"
                                    icon: "wifi"
                                    text: "Se connecter"
                                    height: 28
                                    onClicked: Api.invoke("wifi_connect", { ssidName: row.one.name, password: row.t.text })
                                        .then(() => Watch.osd("wifi", null, "Connecté à " + row.one.name))
                                        .catch(e => Watch.osd("error", null, String(e)))
                                }
                                TextBtn {
                                    visible: row.t.status === "done" && !row.t.out && row.t.text !== ""
                                    icon: "content_copy"
                                    text: row.one && row.one.kind === "wifi" ? "Copier le mot de passe" : "Copier"
                                    height: 28
                                    onClicked: {
                                        Api.invoke("clip_text", { text: row.t.text })
                                        Watch.osd("content_copy", null, "Copié")
                                    }
                                }
                            }
                        }
                        IconBtn {
                            id: closeBtn
                            visible: !row.live
                            x: parent.width - width - 8
                            y: 8
                            small: true
                            iconSize: 16
                            icon: "close"
                            tip: "Retirer de la liste"
                            onClicked: Api.invoke("qs_clear", { id: row.t.id })
                        }
                    }
                }
            }
        }
        Scroller { flick: acts }
    }
}
