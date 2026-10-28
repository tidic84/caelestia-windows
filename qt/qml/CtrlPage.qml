import QtQuick
import QtQuick.Shapes

// Controles : tuiles (Wi-Fi, Bluetooth, cafeine, ne pas deranger, mode
// sombre, minuteur), luminosite, sortie audio et melangeur ; feuilles
// (reseaux, Bluetooth, sorties, minuteur) ; notifications a droite
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "ctrl"
    property string sheet: ""
    onSheetChanged: {
        if (sheet !== "bt" && btScan)
            stopBt()
        if (sheet !== "")
            Ilot.overlay = "sheet"
        else if (Ilot.overlay === "sheet")
            Ilot.overlay = ""
    }
    // page dechargee (Panel) : Echap ne doit plus viser la feuille
    Component.onDestruction: {
        if (Ilot.overlay === "sheet")
            Ilot.overlay = ""
        if (btScan)
            stopBt()
        Api.unlisten("bt_pin", onBtPin)
    }
    Connections {
        target: Ilot
        function onCloseSheets() { page.sheet = "" }
    }
    function openSheet(name) {
        sheet = name
        if (name === "wifi")
            loadWifi(true)
        if (name === "bt")
            loadBt(true)
        if (name === "out")
            refreshOut()
    }

    onShownChanged: {
        if (shown)
            enter()
        else if (btScan)
            stopBt()
    }
    Component.onCompleted: {
        Api.listen("bt_pin", onBtPin)
        if (shown)
            enter()
    }
    function enter() {
        Api.invoke("net_get").then(n => { Ilot.net = n })
        Api.invoke("brightness_get").then(b => {
            page.bright = b
            if (b)
                brightSlider.value = Math.round(b.level * 100)
        })
        refreshOut()
        mixerView.refresh()
    }

    // ------------------------------------------------- sortie, melangeur
    // (le melangeur se sonde lui-meme : Mixer.qml)
    property var devices: []
    function refreshOut() {
        Api.invoke("audio_devices").then(l => { page.devices = l })
    }
    // Reglages > Son : sorties masquees (la sortie par defaut reste visible)
    readonly property var shownDevices: devices.filter(d => d.default || !Ilot.outHidden(d.id))
    // premier lancement : beaucoup de sorties virtuelles, rien de choisi
    readonly property bool outTip: Ilot.outHiddenMap === null && !Ilot.ui.outTip
        && devices.filter(d => Ilot.outVirtual(d.name)).length >= 3
    function manageOuts() {
        Ilot.saveUi({ outTip: true })
        sheet = ""
        Ilot.openSettings("sound")
    }

    // ------------------------------------------------------ luminosite
    property var bright: null
    property bool brightBusy: false
    property var brightPending: null
    // DDC/CI est lent : on n'envoie que la derniere valeur demandee
    function pushBright() {
        if (brightBusy || brightPending === null)
            return
        brightBusy = true
        const v = brightPending
        brightPending = null
        Api.invoke("brightness_set", { level: v }).then(() => {
            page.brightBusy = false
            page.pushBright()
        }, () => {
            page.brightBusy = false
            page.pushBright()
        })
    }

    // ----------------------------------------------------------- Wi-Fi
    property var wifi: []
    property bool scanning: false
    property bool wifiBusy: false
    property string wifiMsg: ""
    // mot de passe en cours de saisie : la liste attend (sinon les lignes
    // sont recreees et le champ s'efface)
    property int wifiAsking: 0
    property var wifiPending: null
    onWifiAskingChanged: {
        if (wifiAsking === 0 && wifiPending) {
            const l = wifiPending
            wifiPending = null
            showWifi(l)
        }
    }
    function loadWifi(scan) {
        if (Ilot.net.radios.wifi === false) {
            wifi = []
            wifiPending = null
            wifiMsg = "Le Wi-Fi est désactivé."
            return
        }
        if (!wifi.length)
            wifiMsg = "Recherche des réseaux…"
        Api.invoke("wifi_list", { scan: false }).then(l => page.showWifi(l))
        if (scan) {
            scanning = true
            Api.invoke("wifi_list", { scan: true }).then(l => {
                page.scanning = false
                page.showWifi(l)
            })
        }
    }
    function showWifi(l) {
        if (wifiBusy)
            return
        if (wifiAsking > 0) {
            wifiPending = l
            return
        }
        wifi = l
        wifiMsg = l.length ? "" : "Aucun réseau trouvé."
    }

    // ------------------------------------------------------- Bluetooth
    // appaires (connexion des casques et enceintes, oubli) puis appareils a
    // proximite (recherche tant que la feuille est ouverte, appairage)
    property var bt: []
    property bool btScan: false
    property string btMsg: ""
    // demande de code de l'appairage en cours : { id, kind, pin }
    property var btPin: null
    // action en cours ou derniere erreur, par appareil : { busy, msg }. Gardee
    // ici : les lignes sont recreees quand la liste change
    property var btOps: ({})
    readonly property var btPaired: bt.filter(d => d.paired)
    readonly property var btNear: bt.filter(d => !d.paired)
    function loadBt(scan) {
        if (Ilot.net.radios.bluetooth === false) {
            bt = []
            btMsg = "Le Bluetooth est désactivé."
            if (btScan)
                stopBt()
            return
        }
        btMsg = ""
        // reaffirmee a chaque sondage : Windows l'interrompt si la radio se coupe
        if (scan) {
            btScan = true
            Api.invoke("bt_scan", { on: true })
        }
        Api.invoke("bt_list").then(l => {
            // pas pendant la saisie d'un code : la ligne serait recreee
            if (!page.btPin && JSON.stringify(l) !== JSON.stringify(page.bt))
                page.bt = l
        })
    }
    function btOp(id, busy, msg) {
        const o = Object.assign({}, btOps)
        o[id] = { busy: busy, msg: msg || "" }
        btOps = o
    }
    function btDone(id, msg) {
        btOp(id, false, msg)
        loadBt(btScan)
        Api.invoke("net_get").then(n => { Ilot.net = n })
    }
    function btPair(d) {
        btOp(d.id, true, "Appairage…")
        const end = msg => {
            if (page.btPin && page.btPin.id === d.id)
                page.btPin = null
            page.btDone(d.id, msg)
        }
        Api.invoke("bt_pair", { id: d.id }).then(() => end(), e => end(String(e)))
    }
    function btConnect(d) {
        btOp(d.id, true, d.connected ? "Déconnexion…" : "Connexion…")
        // le casque met quelques secondes a (se) connecter
        Api.invoke("bt_connect", { id: d.id, on: !d.connected }).then(() => Ilot.later(3000, () => page.btDone(d.id)), e => page.btDone(d.id, String(e)))
    }
    function btUnpair(d) {
        btOp(d.id, true, "Suppression…")
        Api.invoke("bt_unpair", { id: d.id }).then(() => page.btDone(d.id), e => page.btDone(d.id, String(e)))
    }
    // reponse a la demande de code (refus : l'appairage echoue)
    function btAnswer(accept, code) {
        btPin = null
        Api.invoke("bt_pair_answer", { accept: accept, pin: code === undefined ? null : code })
    }
    function stopBt() {
        btScan = false
        Api.invoke("bt_scan", { on: false })
    }
    function onBtPin(p) { page.btPin = p }
    Timer {
        interval: 2000
        repeat: true
        running: page.shown && page.sheet === "bt"
        onTriggered: page.loadBt(page.btScan)
    }
    // radio activee feuille ouverte : la recherche demarre
    Connections {
        target: Ilot
        function onNetChanged() {
            if (page.sheet === "bt")
                page.loadBt(true)
        }
    }

    Item {
        id: main
        width: parent.width - 250 - 10
        height: parent.height
        clip: true

        // les autres elements disparaissent sous une feuille ouverte
        Column {
            id: mainCol
            width: parent.width
            height: parent.height
            spacing: 10
            visible: page.sheet === "" || hideDelay.running
            Timer {
                id: hideDelay
                interval: 200
            }
            Connections {
                target: page
                function onSheetChanged() { if (page.sheet !== "") hideDelay.restart() }
            }

            Grid {
                id: tiles
                width: parent.width
                columns: 3
                spacing: 8
                readonly property real tw: (width - 16) / 3
                readonly property var r: Ilot.net.radios
                Tile {
                    visible: tiles.r.wifi !== null
                    on: !!tiles.r.wifi
                    icon: "wifi"
                    title: "Wi-Fi"
                    sub: tiles.r.wifi ? Ilot.net.ssid || "Non connecté" : "Désactivé"
                    more: true
                    onMain: Ilot.toggleRadio("wifi")
                    onMoreClicked: page.openSheet("wifi")
                }
                Tile {
                    visible: tiles.r.bluetooth !== null
                    on: !!tiles.r.bluetooth
                    icon: "bluetooth"
                    title: "Bluetooth"
                    sub: tiles.r.bluetooth ? (Ilot.net.bt_devices.length ? Ilot.net.bt_devices.join(", ") : "Activé") : "Désactivé"
                    more: true
                    onMain: Ilot.toggleRadio("bluetooth")
                    onMoreClicked: page.openSheet("bt")
                }
                Tile {
                    on: Ilot.caffeine
                    icon: "coffee"
                    title: "Caféine"
                    sub: Ilot.caffeine ? "Veille bloquée" : "Veille normale"
                    onMain: Ilot.toggleCaffeine()
                }
                Tile {
                    on: !!Ilot.cfg.dnd
                    icon: "do_not_disturb_on"
                    title: "Ne pas déranger"
                    sub: Ilot.cfg.dnd ? "Activé" : "Désactivé"
                    onMain: Ilot.toggleDnd()
                }
                Tile {
                    on: Ilot.dark
                    icon: Ilot.dark ? "dark_mode" : "light_mode"
                    title: "Mode sombre"
                    sub: Ilot.cfg.mode === "auto" ? "Auto (" + (Ilot.dark ? "sombre" : "clair") + ")" : Ilot.dark ? "Activé" : "Désactivé"
                    onMain: Ilot.setCfg({ mode: Ilot.dark ? "light" : "dark" })
                }
                Tile {
                    readonly property bool active: Ilot.tmr.running || Ilot.tmr.remaining < Ilot.tmr.total
                    on: Ilot.tmr.running
                    icon: "timer"
                    title: "Minuteur"
                    sub: active ? Ilot.fmtMs(Ilot.timerLeft) + (Ilot.tmr.running ? "" : " · en pause") : "Arrêté"
                    more: true
                    onMain: {
                        if (active)
                            Ilot.timerToggle()
                        else
                            page.openSheet("timer")
                    }
                    onMoreClicked: page.openSheet("timer")
                }
            }

            // luminosite (ecran compatible DDC/CI ou portable)
            Card {
                visible: !!page.bright
                width: parent.width
                height: 40
                radius: height / 2
                Ms {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    name: "brightness_6"
                    color: Theme.inkVariant
                }
                M3Slider {
                    id: brightSlider
                    x: 16 + 20 + 12
                    width: parent.width - x - 12 - 28 - 18
                    anchors.verticalCenter: parent.verticalCenter
                    onMoved: v => {
                        page.brightPending = v / 100
                        page.pushBright()
                    }
                }
                Txt {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    horizontalAlignment: Text.AlignRight
                    text: brightSlider.value
                    px: 12
                    tnum: true
                    color: Theme.inkVariant
                }
            }

            // sortie audio et melangeur
            Card {
                width: parent.width
                height: parent.height - tiles.height - 10 - (page.bright ? 50 : 0)
                Btn {
                    id: outBtn
                    x: 8
                    y: 8
                    width: parent.width - 16
                    height: 38
                    radius: 14
                    color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                    onClicked: page.openSheet("out")
                    Ms {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: "speaker"
                        size: 19
                        color: Theme.inkVariant
                    }
                    Txt {
                        x: 12 + 19 + 10
                        width: parent.width - x - 41
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property var cur: page.devices.find(d => d.default)
                        text: cur ? Ilot.outLabel(cur.id, cur.name) : "Sortie audio"
                        weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Ms {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: "unfold_more"
                        size: 19
                        color: Theme.inkVariant
                    }
                }
                Mixer {
                    id: mixerView
                    x: 8
                    y: outBtn.y + outBtn.height + 6
                    width: parent.width - 16
                    height: parent.height - y - 8
                    shown: page.shown
                }
            }
        }

        // ---------------------------------------------- feuilles
        Sheet {
            id: wifiSheet
            on: page.sheet === "wifi"
            title: "Réseaux Wi-Fi"
            onBack: page.sheet = ""
            action: IconBtn {
                small: true
                icon: "refresh"
                tip: "Rechercher"
                RotationAnimator on rotation {
                    running: page.scanning
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    // finit le tour en cours : l'icone ne reste pas penchee
                    alwaysRunToEnd: true
                }
                onClicked: page.loadWifi(true)
            }
            Column {
                width: parent.width
                spacing: 4
                Empty {
                    visible: page.wifiMsg !== ""
                    width: parent.width
                    small: true
                    text: page.wifiMsg
                }
                Repeater {
                    model: page.wifi
                    WifiRow {
                        width: parent.width
                    }
                }
            }
        }
        Sheet {
            on: page.sheet === "bt"
            title: "Bluetooth"
            onBack: page.sheet = ""
            action: IconBtn {
                small: true
                icon: "refresh"
                tip: page.btScan ? "Recherche en cours" : "Rechercher"
                RotationAnimator on rotation {
                    running: page.btScan
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
                onClicked: page.loadBt(true)
            }
            Column {
                width: parent.width
                spacing: 4
                Empty {
                    visible: page.btMsg !== ""
                    width: parent.width
                    small: true
                    text: page.btMsg
                }
                BtHead {
                    visible: page.btMsg === ""
                    text: "Appareils appairés"
                }
                Txt {
                    visible: page.btMsg === "" && page.btPaired.length === 0
                    x: 12
                    height: 30
                    verticalAlignment: Text.AlignVCenter
                    text: "Aucun appareil appairé"
                    px: 12
                    color: Theme.outline
                }
                Repeater {
                    model: page.btPaired
                    BtRow {
                        width: parent.width
                    }
                }
                BtHead {
                    visible: page.btMsg === ""
                    text: "À proximité"
                }
                Txt {
                    visible: page.btMsg === "" && page.btNear.length === 0
                    x: 12
                    width: parent.width - 24
                    height: 30
                    verticalAlignment: Text.AlignVCenter
                    text: page.btScan ? "Recherche… Mets l’appareil en mode appairage." : "Aucun appareil trouvé"
                    px: 12
                    elide: Text.ElideRight
                    color: Theme.outline
                }
                Repeater {
                    model: page.btNear
                    BtRow {
                        width: parent.width
                    }
                }
            }
        }
        Sheet {
            on: page.sheet === "out"
            title: "Sortie audio"
            onBack: page.sheet = ""
            action: IconBtn {
                small: true
                icon: "tune"
                tip: "Choisir les sorties affichées"
                onClicked: page.manageOuts()
            }
            Column {
                width: parent.width
                spacing: 4
                Empty {
                    visible: page.devices.length === 0
                    width: parent.width
                    small: true
                    text: "Aucune sortie audio."
                }
                // premier lancement (Voicemeeter, Sonar...) : on propose, on ne
                // masque rien tout seul
                Rectangle {
                    visible: page.outTip
                    width: parent.width
                    height: visible ? 48 : 0
                    radius: 16
                    color: Theme.secondaryContainer
                    Ms {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: "tune"
                        size: 18
                        color: Theme.inkSecondaryContainer
                    }
                    Txt {
                        x: 40
                        width: parent.width - x - tipGo.width - tipX.width - 18
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property int nv: page.devices.filter(d => Ilot.outVirtual(d.name)).length
                        text: page.devices.length + " sorties, dont " + nv + " virtuelles : choisis celles à afficher"
                        px: 12
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Theme.inkSecondaryContainer
                    }
                    TextBtn {
                        id: tipGo
                        anchors.right: tipX.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        primary: true
                        text: "Choisir"
                        onClicked: page.manageOuts()
                    }
                    IconBtn {
                        id: tipX
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        small: true
                        icon: "close"
                        tip: "Ne plus proposer"
                        fg: Theme.inkSecondaryContainer
                        onClicked: Ilot.saveUi({ outTip: true })
                    }
                }
                Repeater {
                    model: page.shownDevices
                    Btn {
                        required property var modelData
                        width: parent.width
                        height: 40
                        radius: 16
                        color: modelData.default ? Theme.secondaryContainer : hovered ? Theme.surfaceHigh : "transparent"
                        readonly property color fg: modelData.default ? Theme.inkSecondaryContainer : Theme.ink
                        onClicked: Api.invoke("audio_set_default", { id: modelData.id }).then(() => {
                            page.refreshOut()
                            Ilot.refreshVolume()
                            mixerView.refresh()
                        })
                        Ms {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            name: /casque|headphone|headset|écouteur|airpods|buds/i.test(parent.modelData.name) ? "headphones" : "speaker"
                            color: parent.fg
                        }
                        Txt {
                            x: 44
                            width: parent.width - 44 - 44
                            anchors.verticalCenter: parent.verticalCenter
                            text: Ilot.outLabel(parent.modelData.id, parent.modelData.name)
                            weight: Font.Medium
                            elide: Text.ElideRight
                            color: parent.fg
                        }
                        Ms {
                            visible: parent.modelData.default
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            name: "check"
                            color: parent.fg
                        }
                    }
                }
                // sorties masquees : discret, mene a Reglages > Son
                Btn {
                    readonly property int n: page.devices.length - page.shownDevices.length
                    visible: n > 0
                    width: parent.width
                    height: visible ? 34 : 0
                    radius: 12
                    color: hovered ? Theme.surfaceHigh : "transparent"
                    onClicked: page.manageOuts()
                    Ms {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: "visibility_off"
                        size: 17
                        color: Theme.outline
                    }
                    Txt {
                        x: 40
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property string s: parent.n > 1 ? "s" : ""
                        text: parent.n + " sortie" + s + " masquée" + s + " · Gérer"
                        px: 12
                        color: parent.hovered ? Theme.inkVariant : Theme.outline
                    }
                }
            }
        }
        Sheet {
            on: page.sheet === "timer"
            title: "Minuteur"
            onBack: page.sheet = ""
            scroll: false
            TimerBody {
                width: parent.width
                height: parent.height
            }
        }
    }

    // ------------------------------------------------ notifications
    Card {
        x: parent.width - 250
        width: 250
        height: parent.height
        Item {
            id: nHead
            x: 16
            y: 12
            width: parent.width - 28
            height: 26
            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    text: "Notifications"
                    px: 14
                    weight: Font.Medium
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Ilot.notifs.length || ""
                    px: 12
                    color: Theme.inkVariant
                }
            }
            IconBtn {
                anchors.right: parent.right
                small: true
                icon: "clear_all"
                tip: "Tout effacer"
                onClicked: {
                    notifCol.gone = true
                    Ilot.later(220, () => Api.invoke("notifs_dismiss", { id: null }))
                }
            }
        }
        // l'heure relative (« il y a 5 min ») se met a jour toutes les minutes
        property int tick: 0
        Timer {
            interval: 60000
            repeat: true
            running: page.shown
            onTriggered: parent.tick++
        }
        Flickable {
            id: nFlick
            x: 10
            y: nHead.y + nHead.height + 8
            width: parent.width - 20
            height: parent.height - y - 10
            contentHeight: notifCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: notifCol
                width: parent.width
                spacing: 6
                property bool gone: false
                Connections {
                    target: Ilot
                    function onNotifsChanged() { notifCol.gone = false }
                }
                Empty {
                    visible: Ilot.notifs.length === 0
                    width: parent.width
                    small: true
                    icon: Ilot.cfg.dnd ? "do_not_disturb_on" : "notifications_none"
                    text: Ilot.cfg.dnd ? "Ne pas déranger est activé" : "Aucune notification"
                }
                Repeater {
                    model: Ilot.notifs
                    NotifRow {
                        width: notifCol.width
                        tick: nFlick.parent.tick
                        gone: notifCol.gone
                    }
                }
            }
        }
        Scroller { flick: nFlick }
    }

    // ------------------------------------------------ composants
    component Tile: Item {
        id: tile
        property bool on: false
        property string icon
        property string title
        property string sub
        property bool more: false
        signal main()
        signal moreClicked()
        width: tiles.tw
        height: 52
        readonly property color fg: on ? Theme.inkPrimary : Theme.ink
        Rectangle {
            id: tbg
            anchors.fill: parent
            radius: hov.hovered ? 24 : 20
            Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            color: tile.on ? Theme.primary : Theme.surfaceC
            Behavior on color { ColorAnimation { duration: 250 } }
            clip: true
            HoverHandler { id: hov }
            Btn {
                id: mainBtn
                width: parent.width - (tile.more ? 28 : 0)
                height: parent.height
                onClicked: tile.main()
                // voile de survol aux coins arrondis de la tuile
                Item {
                    anchors.fill: parent
                    clip: true
                    Rectangle {
                        width: tbg.width
                        height: parent.height
                        radius: tbg.radius
                        color: mainBtn.hovered ? Theme.alpha(tile.fg, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
                Row {
                    x: 10
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Ms {
                        name: tile.icon
                        size: 22
                        color: tile.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        width: mainBtn.width - 10 - 22 - 8 - 6
                        spacing: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Txt {
                            width: parent.width
                            text: tile.title
                            px: 12.5
                            weight: Font.Medium
                            elide: Text.ElideRight
                            color: tile.fg
                        }
                        Txt {
                            width: parent.width
                            text: tile.sub
                            px: 11
                            opacity: 0.8
                            elide: Text.ElideRight
                            color: tile.fg
                        }
                    }
                }
            }
            Btn {
                id: moreBtn
                visible: tile.more
                x: parent.width - 28
                width: 28
                height: parent.height
                tip: "Plus de réglages"
                onClicked: tile.moreClicked()
                Item {
                    anchors.fill: parent
                    clip: true
                    Rectangle {
                        x: -moreBtn.x
                        width: tbg.width
                        height: parent.height
                        radius: tbg.radius
                        color: moreBtn.hovered ? Theme.alpha(tile.fg, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
                Rectangle {
                    width: 1
                    height: parent.height
                    color: Theme.alpha(tile.fg, 0.18)
                }
                Ms {
                    anchors.centerIn: parent
                    name: "chevron_right"
                    color: tile.fg
                }
            }
        }
    }

    component Sheet: Rectangle {
        id: sh
        property bool on: false
        property string title
        property bool scroll: true
        property Item action
        default property alias content: body.data
        signal back()
        anchors.fill: parent
        z: 2
        radius: 22
        color: Theme.surfaceC
        opacity: on ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        transform: Translate {
            y: sh.on ? 0 : 16
            Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        }
        Item {
            id: head
            x: 12
            y: 12
            width: parent.width - 24
            height: 26
            IconBtn {
                small: true
                icon: "arrow_back"
                tip: "Retour"
                onClicked: sh.back()
            }
            Txt {
                anchors.centerIn: parent
                text: sh.title
                px: 14
                weight: Font.Medium
            }
            Item {
                id: actionBox
                anchors.right: parent.right
                width: 26
                height: 26
                children: sh.action ? [sh.action] : []
            }
        }
        Flickable {
            id: flick
            x: 10
            y: head.y + head.height + 10
            width: parent.width - 20
            height: parent.height - y - 10
            contentHeight: sh.scroll ? body.childrenRect.height : height
            interactive: sh.scroll
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Item {
                id: body
                width: flick.width
                height: sh.scroll ? childrenRect.height : flick.height
            }
        }
        Scroller { flick: flick }
    }

    component BtHead: Txt {
        x: 12
        height: 26
        verticalAlignment: Text.AlignBottom
        px: 11.5
        weight: Font.Medium
        color: Theme.inkVariant
    }

    component BtRow: Rectangle {
        id: dev
        required property var modelData
        readonly property bool connected: modelData.connected
        readonly property var op: page.btOps[modelData.id] || null
        readonly property bool busy: !!op && op.busy
        // action en cours ou erreur ; vide : etat de l'appareil
        readonly property string state2: op ? op.msg : ""
        readonly property var pin: page.btPin && page.btPin.id === modelData.id ? page.btPin : null
        height: 40 + (pin ? 44 : 0)
        radius: 16
        color: connected ? Theme.secondaryContainer : devBtn.hovered ? Theme.surfaceHigh : "transparent"
        opacity: busy && !pin ? 0.7 : 1
        readonly property color fg: connected ? Theme.inkSecondaryContainer : Theme.ink
        // survol de la ligne, meme sans action (souris, clavier : bouton Oublier)
        HoverHandler { id: rowHov }
        Btn {
            id: devBtn
            width: parent.width
            height: 40
            radius: 16
            active: !dev.busy && (dev.modelData.audio || !dev.modelData.paired)
            onClicked: {
                if (dev.modelData.paired)
                    page.btConnect(dev.modelData)
                else
                    page.btPair(dev.modelData)
            }
            Ms {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                name: dev.modelData.icon
                color: dev.fg
            }
            Column {
                x: 44
                width: parent.width - 44 - (forget.visible ? 40 : 12)
                spacing: 1
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    width: parent.width
                    text: dev.modelData.name
                    weight: Font.Medium
                    elide: Text.ElideRight
                    color: dev.fg
                }
                Txt {
                    width: parent.width
                    readonly property var d: dev.modelData
                    text: forget.armed ? "Cliquer encore pour oublier"
                        : dev.state2 || (!d.paired ? "Appairer" : d.connected ? "Connecté" : d.audio ? "Non connecté · Connecter" : "Non connecté")
                    px: 11.5
                    opacity: 0.75
                    elide: Text.ElideRight
                    color: forget.armed ? Theme.error : dev.fg
                }
            }
            // oublier : second clic pour confirmer
            IconBtn {
                id: forget
                visible: dev.modelData.paired && !dev.busy && (rowHov.hovered || armed)
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                small: true
                icon: "delete"
                tip: armed ? "Cliquer encore pour oublier" : "Oublier l’appareil"
                fg: armed ? Theme.inkError : dev.fg
                onClicked: {
                    if (!armed) {
                        armed = true
                        disarm.restart()
                        return
                    }
                    armed = false
                    page.btUnpair(dev.modelData)
                }
                Timer {
                    id: disarm
                    interval: 2500
                    onTriggered: forget.armed = false
                }
            }
        }
        // code de l'appairage : a comparer, a taper sur l'appareil, ou a saisir
        Row {
            visible: !!dev.pin
            x: 44
            y: 40
            height: 36
            spacing: 8
            Txt {
                visible: !!dev.pin && dev.pin.kind !== "provide"
                width: dev.width - 44 - 12 - (dev.pin && dev.pin.kind === "confirm" ? yes.width + no.width + 16 : 0)
                anchors.verticalCenter: parent.verticalCenter
                text: !dev.pin ? "" : (dev.pin.kind === "confirm" ? "Même code sur l’appareil ? " : "Tape ce code sur l’appareil : ") + dev.pin.pin
                px: 12
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: dev.fg
            }
            TextBtn {
                id: yes
                visible: !!dev.pin && dev.pin.kind === "confirm"
                anchors.verticalCenter: parent.verticalCenter
                primary: true
                text: "Oui"
                onClicked: page.btAnswer(true)
            }
            TextBtn {
                id: no
                visible: !!dev.pin && dev.pin.kind === "confirm"
                anchors.verticalCenter: parent.verticalCenter
                text: "Non"
                onClicked: page.btAnswer(false)
            }
            Field {
                id: pinField
                visible: !!dev.pin && dev.pin.kind === "provide"
                width: dev.width - 44 - 12 - 2 * (26 + 8)
                anchors.verticalCenter: parent.verticalCenter
                placeholder: "Code PIN de l’appareil"
                onAccepted: page.btAnswer(true, text)
            }
            IconBtn {
                visible: pinField.visible
                small: true
                filled: true
                icon: "arrow_forward"
                anchors.verticalCenter: parent.verticalCenter
                tip: "Valider"
                onClicked: page.btAnswer(true, pinField.text)
            }
            IconBtn {
                visible: pinField.visible
                small: true
                icon: "close"
                anchors.verticalCenter: parent.verticalCenter
                tip: "Annuler"
                onClicked: page.btAnswer(false)
            }
        }
        onPinChanged: {
            if (pin && pin.kind === "provide") {
                Ilot.grabFocus()
                pinField.input.forceActiveFocus()
            }
        }
    }

    component WifiRow: Rectangle {
        id: net
        required property var modelData
        property bool asking: false
        property string state2: modelData.connected ? "Connecté" : modelData.known ? "Enregistré" : modelData.secure ? "Sécurisé" : "Ouvert"
        property bool busy: false
        height: 40 + (asking ? 44 : 0)
        radius: 16
        color: modelData.connected ? Theme.secondaryContainer : netBtn.hovered ? Theme.surfaceHigh : "transparent"
        opacity: busy ? 0.7 : 1
        readonly property color fg: modelData.connected ? Theme.inkSecondaryContainer : Theme.ink
        onAskingChanged: page.wifiAsking += asking ? 1 : -1
        Component.onDestruction: if (asking) page.wifiAsking--
        // feuille fermee : le champ se referme, la liste peut changer
        Connections {
            target: page
            function onSheetChanged() { if (page.sheet !== "wifi") net.asking = false }
        }
        function connect(password) {
            busy = true
            page.wifiBusy = true
            state2 = "Connexion…"
            Api.invoke("wifi_connect", { ssidName: modelData.ssid, password: password === undefined ? null : password }).then(() => {
                Ilot.later(4000, () => {
                    page.wifiBusy = false
                    net.busy = false
                    Api.invoke("net_get").then(n => { Ilot.net = n })
                    page.loadWifi(false)
                    // en dernier : peut recreer cette ligne
                    net.asking = false
                })
            }).catch(e => {
                page.wifiBusy = false
                net.busy = false
                if (e === "password") {
                    net.asking = true
                    pass.input.forceActiveFocus()
                    return
                }
                net.state2 = String(e)
            })
        }
        Btn {
            id: netBtn
            width: parent.width
            height: 40
            radius: 16
            onClicked: {
                if (net.modelData.connected) {
                    net.state2 = "Déconnexion…"
                    Api.invoke("wifi_disconnect").then(() => Ilot.later(1500, () => {
                        Api.invoke("net_get").then(n => { Ilot.net = n })
                        page.loadWifi(false)
                    }))
                    return
                }
                if (net.modelData.secure && !net.modelData.known) {
                    net.asking = true
                    Ilot.grabFocus()
                    pass.input.forceActiveFocus()
                    return
                }
                net.connect()
            }
            Ms {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                readonly property int s: net.modelData.signal
                name: s > 66 ? "wifi" : s > 33 ? "wifi_2_bar" : "wifi_1_bar"
                color: net.fg
            }
            Column {
                x: 44
                width: parent.width - 44 - 36
                spacing: 1
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    width: parent.width
                    text: net.modelData.ssid
                    weight: Font.Medium
                    elide: Text.ElideRight
                    color: net.fg
                }
                Txt {
                    text: net.state2
                    px: 11.5
                    opacity: 0.75
                    color: net.fg
                }
            }
            Ms {
                visible: net.modelData.secure
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "lock"
                size: 15
                opacity: 0.6
                color: net.fg
            }
        }
        Row {
            visible: net.asking
            x: 44
            y: 40
            spacing: 8
            Field {
                id: pass
                width: net.width - 44 - 12 - 26 - 8
                password: true
                placeholder: "Mot de passe"
                onAccepted: net.connect(text)
            }
            IconBtn {
                small: true
                filled: true
                icon: "arrow_forward"
                anchors.verticalCenter: parent.verticalCenter
                tip: "Se connecter"
                onClicked: net.connect(pass.text)
            }
        }
    }
}
