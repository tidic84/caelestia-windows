import QtQuick

// PC : Discord (RPC si configure, sinon melangeur de Windows) ; a droite,
// etat des services, sante du PC, extinction programmee, logiciels du
// constructeur, mode d'alimentation de Windows 11, convertisseur de sensibilite
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "pc"
    readonly property var dc: Ilot.dc
    readonly property bool rpc: dc.status === "ready"
    // sourdines Windows (mode simple) : partagees avec la pilule (Watch)
    readonly property bool localMic: Watch.dcLocalMic
    readonly property bool localOut: Watch.dcLocalOut
    readonly property real side: 270
    property var dcVol: null
    property bool setupOpen: false
    property string dcErr: ""

    onShownChanged: if (shown) refresh()
    Component.onCompleted: if (shown) refresh()
    Timer {
        interval: 3000
        repeat: true
        running: page.shown
        onTriggered: page.refresh()
    }
    function refresh() {
        health.refresh(false)
        renderHardware()
        refreshPower()
        Api.invoke("app_volume_get", { app: "discord" }).then(v => {
            page.dcVol = v
            if (v && !page.rpc)
                Watch.dcLocalOut = v.muted
        })
    }

    // logiciels constructeur : nom dans le menu Demarrer + executable de leur interface
    readonly property var hardware: [
        { match: /^msi center/i, exe: "DCv2", label: "MSI Center", icon: "memory" },
        { match: /^armoury crate/i, exe: "ArmouryCrate", label: "Armoury Crate", icon: "developer_board" },
        { match: /^logitech g hub/i, exe: "lghub", label: "Logitech G HUB", icon: "mouse" }
    ]
    property var hw: []
    function renderHardware() {
        const list = hardware.map(h => Object.assign({}, h, { app: Ilot.apps.find(a => h.match.test(a.name)) || null }))
        Api.invoke("procs_running", { names: list.map(h => h.exe) }).then(running => {
            page.hw = list.map((h, i) => Object.assign(h, { running: !!running[i] }))
        })
    }
    property string power: ""
    property bool powerKnown: false
    function refreshPower() {
        Api.invoke("power_get").then(m => {
            page.power = m
            page.powerKnown = true
        })
    }

    readonly property var statusNames: ({ setup: "Mode simple", closed: "Discord fermé", authorizing: "Autorise Ilot dans Discord…", ready: "Connecté", error: "Erreur" })

    // ----------------------------------------------------------- Discord
    Card {
        id: dcCard
        width: parent.width - page.side - 10
        height: parent.height
        readonly property bool mic: page.rpc ? !!page.dc.mute : page.localMic
        readonly property bool deaf: page.rpc ? !!page.dc.deaf : page.localOut
        readonly property bool showSetup: page.dc.status === "setup" || page.dc.status === "error" || page.setupOpen

        Item {
            id: dcHead
            x: 14
            y: 14
            width: parent.width - 28
            height: 26
            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                Ms {
                    name: "headset_mic"
                    color: "#8c9eff"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                    text: "Discord"
                    px: 15
                    weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                Chip {
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.statusNames[page.dc.status] || page.dc.status
                    color: page.rpc ? Theme.secondaryContainer : page.dc.status === "error" ? Theme.error : Theme.surfaceHighest
                    fg: page.rpc ? Theme.inkSecondaryContainer : page.dc.status === "error" ? Theme.inkError : Theme.inkVariant
                }
                IconBtn {
                    small: true
                    icon: "settings"
                    tip: "Réglages Discord"
                    onClicked: page.setupOpen = !page.setupOpen
                }
            }
        }

        // micro, sourdine, volume
        Row {
            id: selfRow
            x: 14
            y: dcHead.y + dcHead.height + 10
            width: parent.width - 28
            height: 38
            spacing: 8
            DcBtn {
                off: dcCard.mic
                icon: dcCard.mic ? "mic_off" : "mic"
                text: "Micro"
                tip: dcCard.mic ? "Réactiver le micro" : "Couper le micro"
                onClicked: Watch.toggleDcMic()
            }
            DcBtn {
                off: dcCard.deaf
                icon: dcCard.deaf ? "headset_off" : "headphones"
                text: "Son"
                tip: dcCard.deaf ? "Réactiver le son" : "Couper le son (sourdine)"
                onClicked: Watch.toggleDcDeaf()
            }
            Item {
                width: parent.width - x
                height: parent.height
                Btn {
                    anchors.fill: parent
                    active: true
                    cursor: Qt.ArrowCursor
                    tip: page.dcVol ? "Volume de Discord (mélangeur Windows)" : "Discord ne joue pas de son pour l’instant"
                }
                Ms {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "volume_up"
                    color: Theme.inkVariant
                }
                M3Slider {
                    id: dcSlider
                    x: 26
                    width: parent.width - 26 - 30
                    anchors.verticalCenter: parent.verticalCenter
                    disabled: !page.dcVol
                    Binding on value {
                        when: !dcSlider.dragging
                        value: page.dcVol ? Math.round(page.dcVol.level * 100) : 0
                    }
                    onMoved: v => {
                        page.dcVol = { level: v / 100, muted: false }
                        Api.invoke("app_volume_set", { app: "discord", level: v / 100 })
                    }
                }
                Txt {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    horizontalAlignment: Text.AlignRight
                    text: page.dcVol ? Math.round(page.dcVol.level * 100) : "–"
                    px: 12
                    tnum: true
                    color: Theme.inkVariant
                }
            }
        }

        // salon
        Row {
            id: chan
            x: 14
            y: selfRow.y + selfRow.height + 10
            width: parent.width - 28
            spacing: 6
            visible: !dcCard.showSetup
            Ms {
                visible: page.rpc && !!page.dc.channel
                name: "volume_up"
                size: 16
                color: Theme.inkVariant
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                width: parent.width - 22
                wrapMode: Text.Wrap
                text: !page.rpc
                    ? (page.dc.status === "authorizing" ? "Une fenêtre d’autorisation s’est ouverte dans Discord : clique sur « Autoriser »." : "Lance Discord pour voir les personnes du salon.")
                    : (page.dc.channel || "Pas dans un salon vocal") + (page.dc.error ? " (" + page.dc.error + ")" : "")
                px: 12
                color: Theme.inkVariant
            }
        }

        // personnes du salon
        Flickable {
            id: people
            x: 14
            y: chan.y + chan.height + 10
            width: parent.width - 28
            height: (dcCard.showSetup ? setup.y - 10 : parent.height - 14) - y
            visible: !dcCard.showSetup && page.rpc
            contentHeight: peopleCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: peopleCol
                width: parent.width - 4
                spacing: 4
                Repeater {
                    model: page.rpc ? page.dc.people : []
                    DcPerson {
                        width: peopleCol.width
                    }
                }
            }
        }
        Scroller { flick: people }

        // configuration de l'application Discord
        Column {
            id: setup
            visible: dcCard.showSetup
            x: 14
            width: parent.width - 28
            y: parent.height - 14 - height
            spacing: 6
            Txt {
                width: parent.width
                wrapMode: Text.Wrap
                px: 12
                color: Theme.inkVariant
                text: "Pour régler le volume de chaque personne, Discord demande une « application » à toi (gratuit, 2 min) :"
            }
            Txt {
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.StyledText
                px: 12
                lineHeight: 1.15
                color: Theme.inkVariant
                linkColor: Theme.primary
                leftPadding: 4
                text: "1. Ouvre le <a href=\"https://discord.com/developers/applications\">portail développeurs Discord</a> › <font color=\"" + Theme.ink + "\">New Application</font> (nom : Ilot).<br>"
                    + "2. Onglet <font color=\"" + Theme.ink + "\">OAuth2</font> : ajoute la redirection <code>http://localhost</code>, puis copie le <font color=\"" + Theme.ink + "\">Client ID</font> et le <font color=\"" + Theme.ink + "\">Client Secret</font> (Reset Secret)."
                onLinkActivated: link => Api.invoke("open_url", { url: link })
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
            Field {
                id: cid
                width: parent.width
                height: 38
                radius: 10
                pad: 10
                bg: Theme.surfaceC
                focusRing: true
                placeholder: "Client ID"
                onFocused: Ilot.pinned = true
                onAccepted: secret.input.forceActiveFocus()
            }
            Field {
                id: secret
                width: parent.width
                height: 38
                radius: 10
                pad: 10
                bg: Theme.surfaceC
                focusRing: true
                password: true
                placeholder: "Client Secret"
                onFocused: Ilot.pinned = true
                onAccepted: connectBtn.clicked(null)
            }
            Item {
                width: parent.width
                height: 34
                Txt {
                    width: parent.width - btns.width - 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.dc.status === "error" ? page.dc.error || "" : page.dcErr
                    px: 11.5
                    color: page.dc.status === "error" || page.dcErr ? Theme.error : Theme.inkVariant
                    elide: Text.ElideRight
                }
                Row {
                    id: btns
                    anchors.right: parent.right
                    spacing: 10
                    TextBtn {
                        visible: page.dc.status !== "setup"
                        icon: "link_off"
                        text: "Oublier"
                        onClicked: {
                            Api.invoke("discord_forget")
                            page.setupOpen = false
                        }
                    }
                    TextBtn {
                        id: connectBtn
                        primary: true
                        icon: "link"
                        text: "Connecter"
                        onClicked: {
                            if (!cid.text.trim() || !secret.text) {
                                (cid.text.trim() ? secret : cid).input.forceActiveFocus()
                                return
                            }
                            Api.invoke("discord_setup", { clientId: cid.text.trim(), secret: secret.text }).then(() => {
                                cid.text = ""
                                secret.text = ""
                                page.setupOpen = false
                                page.dcErr = ""
                            }).catch(e => { page.dcErr = String(e) })
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------- cote droit
    Flickable {
        id: sideFlick
        x: parent.width - page.side
        width: page.side
        height: parent.height
        contentHeight: sideCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
    Column {
        id: sideCol
        width: page.side - 6
        spacing: 10
        ServicesCard {}
        HealthCard {
            id: health
        }
        ShutdownCard {}
        Card {
            width: parent.width
            height: hwCol.height + 28
            Column {
                id: hwCol
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 6
                Txt {
                    topPadding: 4
                    text: "Logiciels du PC"
                    px: 11.5
                    weight: Font.Medium
                    color: Theme.inkVariant
                }
                Repeater {
                    model: page.hw
                    Btn {
                        id: hwBtn
                        required property var modelData
                        readonly property bool missing: !modelData.app
                        width: hwCol.width
                        height: 40
                        radius: hovered && !missing ? 20 : 14
                        Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                        color: hovered && !missing ? Theme.surfaceHighest : Theme.surfaceHigh
                        opacity: missing ? 0.5 : 1
                        active: !missing
                        onClicked: {
                            Api.invoke("app_launch", { id: modelData.app.id })
                            Ilot.setMode("collapsed")
                        }
                        onRightClicked: Api.invoke("app_folder", { id: modelData.app.id, name: modelData.app.name }).then(ok => { if (ok) Ilot.setMode("collapsed") })
                        Item {
                            x: 10
                            width: 26
                            height: 26
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                anchors.fill: parent
                                visible: !!(hwBtn.modelData.app && hwBtn.modelData.app.icon)
                                source: hwBtn.modelData.app && hwBtn.modelData.app.icon ? hwBtn.modelData.app.icon : ""
                                sourceSize.width: 52
                                mipmap: true
                            }
                            Ms {
                                anchors.centerIn: parent
                                visible: !(hwBtn.modelData.app && hwBtn.modelData.app.icon)
                                name: hwBtn.modelData.icon
                                size: 22
                                color: Theme.primary
                            }
                        }
                        Txt {
                            x: 46
                            width: parent.width - 46 - status.width - 20
                            anchors.verticalCenter: parent.verticalCenter
                            text: hwBtn.modelData.label
                            elide: Text.ElideRight
                        }
                        Txt {
                            id: status
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: hwBtn.missing ? "non installé" : hwBtn.modelData.running ? "●  ouvert" : ""
                            px: 10.5
                            color: hwBtn.modelData.running ? "#3ba55d" : Theme.inkVariant
                        }
                    }
                }
            }
        }
        Card {
            width: parent.width
            height: pwCol.height + 28
            Column {
                id: pwCol
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 6
                Txt {
                    topPadding: 4
                    text: "Mode d'alimentation"
                    px: 11.5
                    weight: Font.Medium
                    color: Theme.inkVariant
                }
                Column {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: [{ id: "eco", icon: "eco", label: "Économie" }, { id: "balanced", icon: "balance", label: "Équilibré" }, { id: "perf", icon: "bolt", label: "Performances" }]
                        Btn {
                            required property var modelData
                            readonly property bool on: page.power === modelData.id
                            width: pwCol.width
                            height: 38
                            radius: on ? 20 : 14
                            Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                            color: on ? Theme.primary : Theme.surfaceHigh
                            readonly property color fg: on ? Theme.inkPrimary : Theme.inkVariant
                            onClicked: {
                                page.power = modelData.id
                                Api.invoke("power_set", { mode: modelData.id }).then(ok => { if (!ok) page.refreshPower() })
                            }
                            Row {
                                x: 12
                                spacing: 10
                                anchors.verticalCenter: parent.verticalCenter
                                Ms {
                                    name: parent.parent.modelData.icon
                                    size: 19
                                    color: parent.parent.fg
                                }
                                Txt {
                                    text: parent.parent.modelData.label
                                    color: parent.parent.fg
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
                Txt {
                    visible: page.powerKnown && !page.power
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Mode non disponible avec le plan d’alimentation actuel (il faut « Utilisation normale »)."
                    px: 11
                    color: Theme.inkVariant
                }
            }
        }
        SensCard {}
    }
    }
    Scroller { flick: sideFlick }

    component DcBtn: Btn {
        id: db
        property bool off: false
        property string icon
        property string text
        width: dbRow.implicitWidth + 25
        height: 38
        radius: hovered ? 20 : 14
        Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        color: off ? Theme.error : Theme.primary
        readonly property color fg: off ? Theme.inkError : Theme.inkPrimary
        Row {
            id: dbRow
            x: 11
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            Ms {
                name: db.icon
                color: db.fg
            }
            Txt {
                text: db.text
                color: db.fg
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // une personne du salon ; sa propre ligne regle le volume de son micro
    component DcPerson: Rectangle {
        id: p
        required property var modelData
        readonly property bool me: modelData.id === page.dc.me_id
        readonly property bool muted: me ? !!page.dc.mute : !!modelData.mute
        readonly property real max: me ? 100 : 200
        property real vol: me ? Math.round(page.dc.mic_volume === undefined || page.dc.mic_volume === null ? 100 : page.dc.mic_volume) : Math.round(modelData.volume)
        height: 46
        radius: 14
        color: Theme.surfaceHigh
        Rectangle {
            id: av
            x: 8
            width: 34
            height: 34
            radius: 17
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.tertiaryContainer
            border.width: p.modelData.speaking ? 2 : 0
            border.color: "#3ba55d"
            Txt {
                anchors.centerIn: parent
                visible: !p.modelData.avatar
                text: (p.modelData.name[0] || "?").toUpperCase()
                weight: Font.DemiBold
                color: Theme.inkTertiaryContainer
            }
            RoundImage {
                anchors.fill: parent
                anchors.margins: p.modelData.speaking ? 3 : 0
                visible: !!p.modelData.avatar
                radius: width / 2
                source: p.modelData.avatar || ""
            }
        }
        Column {
            x: 52
            width: parent.width - 52 - 38 - 26 - 16
            anchors.verticalCenter: parent.verticalCenter
            opacity: p.muted ? 0.45 : 1
            Row {
                spacing: 4
                width: parent.width
                Txt {
                    width: Math.min(implicitWidth, parent.width - 40)
                    text: p.modelData.name + (p.me ? " (toi)" : "")
                    px: 12.5
                    weight: Font.Medium
                    elide: Text.ElideRight
                }
                Ms {
                    visible: p.me || p.modelData.self_mute
                    name: p.me ? "mic" : "mic_off"
                    size: 14
                    color: p.me ? Theme.primary : Theme.error
                }
                Ms {
                    visible: !p.me && !!p.modelData.self_deaf
                    name: "headset_off"
                    size: 14
                    color: Theme.error
                }
            }
            M3Slider {
                width: parent.width
                to: p.max
                value: p.vol
                onMoved: v => {
                    p.vol = v
                    if (p.me)
                        Api.invoke("discord_mic", { volume: v })
                    else
                        Api.invoke("discord_user", { userId: p.modelData.id, volume: v })
                }
            }
        }
        Txt {
            x: parent.width - 38 - 26 - 12
            width: 38
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(p.vol) + "%"
            px: 11
            tnum: true
            color: Theme.inkVariant
        }
        IconBtn {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            small: true
            icon: p.me ? (p.muted ? "mic_off" : "mic") : (p.muted ? "volume_off" : "volume_up")
            tip: p.me ? (p.muted ? "Réactiver le micro" : "Couper le micro") : (p.muted ? "Réactiver" : "Rendre muet (pour moi)")
            onClicked: {
                if (p.me)
                    Api.invoke("discord_self", { mute: !page.dc.mute })
                else
                    Api.invoke("discord_user", { userId: p.modelData.id, mute: !p.modelData.mute })
            }
        }
    }
}
