import QtQuick

// Mail : boite de reception des comptes IMAP (src/mail.rs, verifiee toutes
// les 2 min), lecture d'un message, gestion des comptes
Item {
    id: page
    // "list" | "reader" | "setup"
    property string view: "list"
    property string acc: ""
    property var open: null
    property string body: ""
    property bool busy: false
    readonly property var inbox: Ilot.inbox
    onInboxChanged: if (acc && !inbox.accounts.some(a => a.email === acc)) acc = ""
    onViewChanged: {
        if (view === "reader")
            Ilot.overlay = "reader"
        else if (Ilot.overlay === "reader")
            Ilot.overlay = ""
    }
    Connections {
        target: Ilot
        function onEscapeOverlay(what) { if (what === "reader") page.view = "list" }
    }

    function mailDate(ts) {
        const d = new Date(ts * 1000)
        const now = new Date()
        if (d.toDateString() === now.toDateString())
            return Ilot.hm(d)
        const y = new Date(now)
        y.setDate(now.getDate() - 1)
        if (d.toDateString() === y.toDateString())
            return "Hier"
        return Ilot.fmt(d, "d MMM")
    }
    function refresh() {
        if (busy)
            return
        busy = true
        Api.invoke("mail_refresh").then(ib => { Ilot.inbox = ib }).then(() => { page.busy = false }, () => { page.busy = false })
    }
    function esc(s) {
        return String(s).replace(/[&<>]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c])
    }
    function read(m) {
        open = m
        view = "reader"
        body = "<p>Chargement…</p>"
        Api.invoke("mail_read", { account: m.account, uid: m.uid }).then(b => {
            if (page.open !== m)
                return
            page.body = b.html ? b.html : "<pre style='white-space: pre-wrap; font-family: Segoe UI'>" + page.esc(b.text || "(message vide)") + "</pre>"
        }).catch(e => {
            if (page.open === m)
                page.body = "<p>Impossible de charger le message : " + page.esc(e) + "</p>"
        })
    }

    // ------------------------------------------------------- liste
    Item {
        anchors.fill: parent
        visible: page.view === "list"
        Item {
            id: head
            width: parent.width
            height: 46
            Seg {
                id: seg
                x: 4
                visible: page.inbox.accounts.length > 1
                anchors.verticalCenter: parent.verticalCenter
                itemMaxWidth: 120
                model: [{ id: "", label: "Tous", tip: "Tous les comptes" }].concat(page.inbox.accounts.map(a => ({ id: a.email, label: a.email.split("@")[0], tip: a.email })))
                current: page.acc
                onPicked: id => page.acc = id
            }
            Txt {
                x: seg.visible ? seg.x + seg.width + 8 : 4
                width: buttons.x - x - 8
                anchors.verticalCenter: parent.verticalCenter
                readonly property var errs: page.inbox.accounts.filter(a => a.error)
                readonly property int unread: page.inbox.accounts.filter(a => !page.acc || a.email === page.acc).reduce((n, a) => n + a.unread, 0)
                text: errs.length ? "⚠ " + errs[0].email + " : " + errs[0].error
                    : page.inbox.accounts.length ? (unread ? unread + " non lu" + (unread > 1 ? "s" : "") : "Tout est lu") : ""
                px: 12
                color: errs.length ? Theme.error : Theme.inkVariant
                elide: Text.ElideRight
            }
            Row {
                id: buttons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                TextBtn {
                    icon: "refresh"
                    text: "Actualiser"
                    busy: page.busy
                    onClicked: page.refresh()
                }
                TextBtn {
                    icon: "manage_accounts"
                    text: "Comptes"
                    onClicked: page.view = "setup"
                }
            }
        }
        Flickable {
            id: listFlick
            y: head.height + 10
            width: parent.width - 4
            height: parent.height - y
            contentHeight: listCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: listCol
                width: parent.width
                spacing: 4
                readonly property var mails: page.inbox.mails.filter(m => !page.acc || m.account === page.acc)
                readonly property bool multi: page.inbox.accounts.length > 1 && !page.acc
                Column {
                    visible: page.inbox.accounts.length === 0
                    width: parent.width
                    topPadding: 40
                    spacing: 14
                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Aucun compte."
                        color: Theme.inkVariant
                    }
                    TextBtn {
                        anchors.horizontalCenter: parent.horizontalCenter
                        primary: true
                        icon: "add"
                        text: "Ajouter un compte"
                        onClicked: page.view = "setup"
                    }
                }
                Empty {
                    visible: page.inbox.accounts.length > 0 && listCol.mails.length === 0
                    width: parent.width
                    text: page.busy ? "Chargement…" : "Boîte de réception vide"
                }
                Repeater {
                    model: listCol.mails
                    Btn {
                        id: item
                        required property var modelData
                        readonly property bool unread: !modelData.seen
                        width: listCol.width
                        height: 52
                        radius: 16
                        color: hovered ? Theme.surfaceHigh : Theme.surfaceC
                        tip: (listCol.multi ? modelData.account + "\n" : "") + modelData.from_addr
                        onClicked: page.read(modelData)
                        Rectangle {
                            x: 10
                            width: 8
                            height: 8
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: item.unread ? Theme.primary : "transparent"
                        }
                        Column {
                            x: 28
                            width: parent.width - 28 - 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Row {
                                width: parent.width
                                spacing: 8
                                Rectangle {
                                    visible: listCol.multi
                                    width: accText.implicitWidth + 14
                                    height: 16
                                    radius: 8
                                    color: Theme.tertiaryContainer
                                    anchors.verticalCenter: parent.verticalCenter
                                    Txt {
                                        id: accText
                                        anchors.centerIn: parent
                                        text: item.modelData.account.split("@")[0]
                                        px: 10
                                        color: Theme.inkTertiaryContainer
                                    }
                                }
                                Txt {
                                    width: parent.width - time.width - 8 - (listCol.multi ? accText.implicitWidth + 22 : 0)
                                    text: item.modelData.from || item.modelData.from_addr || "(inconnu)"
                                    weight: item.unread ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }
                                Txt {
                                    id: time
                                    text: page.mailDate(item.modelData.date)
                                    px: 11
                                    tnum: true
                                    weight: item.unread ? Font.Medium : Font.Normal
                                    color: item.unread ? Theme.primary : Theme.inkVariant
                                }
                            }
                            Txt {
                                width: parent.width
                                text: item.modelData.subject || "(sans objet)"
                                px: 12
                                color: item.unread ? Theme.ink : Theme.inkVariant
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
        Scroller { flick: listFlick }
    }

    // ------------------------------------------------------- lecteur
    Item {
        anchors.fill: parent
        visible: page.view === "reader"
        Item {
            id: rHead
            width: parent.width
            height: 36
            IconBtn {
                icon: "arrow_back"
                tip: "Retour"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: {
                    page.open = null
                    page.view = "list"
                }
            }
            Column {
                x: 46
                width: parent.width - 46 - (web.visible ? web.width + 10 : 0)
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    width: parent.width
                    text: page.open ? page.open.subject || "(sans objet)" : ""
                    px: 15
                    weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Txt {
                    width: parent.width
                    topPadding: 2
                    readonly property var m: page.open
                    text: m ? m.from + (m.from !== m.from_addr ? " <" + m.from_addr + ">" : "") + " · " + Ilot.fmt(new Date(m.date * 1000), "dd/MM/yyyy HH:mm:ss") : ""
                    px: 12
                    color: Theme.inkVariant
                    elide: Text.ElideRight
                }
            }
            TextBtn {
                id: web
                visible: !!(page.open && page.open.link)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                icon: "open_in_new"
                text: "Navigateur"
                onClicked: {
                    Api.invoke("open_url", { url: page.open.link })
                    Ilot.setMode("collapsed")
                }
            }
        }
        // message (HTML simple, sans script ni chargement distant)
        Rectangle {
            y: rHead.height + 10
            width: parent.width
            height: parent.height - y
            radius: 18
            color: "#ffffff"
            clip: true
            Flickable {
                id: bodyFlick
                anchors.fill: parent
                anchors.margins: 16
                contentHeight: bodyText.height
                contentWidth: width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Text {
                    id: bodyText
                    width: bodyFlick.width
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                    text: page.body
                    font.family: "Segoe UI"
                    font.pointSize: 14 * 0.75
                    color: "#1d1b20"
                    linkColor: "#6750a4"
                    onLinkActivated: link => {
                        if (/^https?:/i.test(link))
                            Api.invoke("open_url", { url: link })
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        cursorShape: bodyText.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }
            Scroller { flick: bodyFlick }
        }
    }

    // ------------------------------------------------------- comptes
    Item {
        anchors.fill: parent
        visible: page.view === "setup"
        Item {
            id: sHead
            width: parent.width
            height: 36
            IconBtn {
                icon: "arrow_back"
                tip: "Retour"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: page.view = "list"
            }
            Txt {
                x: 46
                anchors.verticalCenter: parent.verticalCenter
                text: "Comptes mail"
                px: 15
                weight: Font.DemiBold
            }
        }
        Flickable {
            id: accFlick
            y: sHead.height + 10
            width: parent.width
            height: Math.min(150, accCol.height)
            contentHeight: accCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: accCol
                width: parent.width
                spacing: 6
                Txt {
                    visible: page.inbox.accounts.length === 0
                    leftPadding: 6
                    topPadding: 4
                    bottomPadding: 4
                    text: "Aucun compte pour l'instant."
                    color: Theme.inkVariant
                }
                Repeater {
                    model: page.inbox.accounts
                    Rectangle {
                        id: acc
                        required property var modelData
                        width: accCol.width
                        height: 50
                        radius: 16
                        color: Theme.surfaceC
                        Ms {
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            name: "account_circle"
                            size: 26
                            color: Theme.primary
                        }
                        Column {
                            x: 14 + 26 + 12
                            width: parent.width - x - 40
                            anchors.verticalCenter: parent.verticalCenter
                            Txt {
                                width: parent.width
                                text: acc.modelData.email
                                weight: Font.Bold
                                elide: Text.ElideRight
                            }
                            Txt {
                                width: parent.width
                                readonly property var a: acc.modelData
                                text: a.error ? "⚠ " + a.error : (a.auth === "google" ? "Google" : a.host) + " · " + a.unread + " non lu" + (a.unread > 1 ? "s" : "")
                                px: 11.5
                                color: a.error ? Theme.error : Theme.inkVariant
                                elide: Text.ElideRight
                            }
                        }
                        IconBtn {
                            id: del
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            small: true
                            icon: "delete"
                            armed: delArm.running
                            tip: armed ? "Cliquer encore pour retirer" : "Retirer ce compte"
                            Timer {
                                id: delArm
                                interval: 3000
                            }
                            onClicked: {
                                if (!delArm.running) {
                                    delArm.start()
                                    return
                                }
                                Api.invoke("mail_remove", { email: acc.modelData.email }).then(ib => { Ilot.inbox = ib })
                            }
                        }
                    }
                }
            }
        }
        // connexion Google par le navigateur (src/google.rs)
        Card {
            id: gCard
            y: accFlick.y + accFlick.height + 10
            width: parent.width
            height: gCol.height + 28
            // saisie du client OAuth (Client ID + Secret)
            property bool setup: false
            property bool waiting: false
            property string err: ""
            function signIn() {
                if (!page.inbox.google) {
                    setup = true
                    return
                }
                err = "Terminez la connexion dans le navigateur…"
                waiting = true
                Api.invoke("mail_google").then(ib => {
                    Ilot.inbox = ib
                    gCard.err = ""
                    page.view = "list"
                }).catch(e => { gCard.err = "⚠ " + String(e) }).then(() => { gCard.waiting = false }, () => { gCard.waiting = false })
            }
            function saveClient() {
                if (!gid.text.trim() || !gsecret.text) {
                    (gid.text.trim() ? gsecret : gid).input.forceActiveFocus()
                    return
                }
                Api.invoke("mail_google_setup", { clientId: gid.text.trim(), secret: gsecret.text }).then(ib => {
                    Ilot.inbox = ib
                    gid.text = ""
                    gsecret.text = ""
                    gCard.setup = false
                    gCard.err = ""
                    gCard.signIn()
                }).catch(e => { gCard.err = "⚠ " + String(e) })
            }
            Column {
                id: gCol
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 8
                Item {
                    width: parent.width
                    height: 34
                    Column {
                        width: parent.width - gBtns.width - 10
                        anchors.verticalCenter: parent.verticalCenter
                        Txt {
                            text: "Compte Google"
                            weight: Font.Bold
                        }
                        Txt {
                            width: parent.width
                            text: gCard.err || "Connexion par le navigateur, sans mot de passe d'application"
                            px: 11.5
                            color: gCard.err.startsWith("⚠") ? Theme.error : Theme.inkVariant
                            elide: Text.ElideRight
                        }
                    }
                    Row {
                        id: gBtns
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        TextBtn {
                            visible: gCard.waiting || gCard.setup
                            icon: "close"
                            text: "Annuler"
                            onClicked: {
                                if (gCard.waiting)
                                    Api.invoke("mail_google_cancel")
                                gCard.setup = false
                                gCard.err = ""
                            }
                        }
                        TextBtn {
                            visible: !gCard.setup
                            primary: true
                            icon: "link"
                            text: "Se connecter"
                            busy: gCard.waiting
                            disabled: gCard.waiting
                            onClicked: gCard.signIn()
                        }
                    }
                }
                Txt {
                    visible: gCard.setup
                    width: parent.width
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    px: 11.5
                    lineHeight: 1.15
                    color: Theme.inkVariant
                    linkColor: Theme.primary
                    text: "Google demande un client OAuth à vous (gratuit, une seule fois) :<br>"
                        + "1. Dans la <a href=\"https://console.cloud.google.com/apis/library/gmail.googleapis.com\">console Google Cloud</a>, créez un projet et activez l'API Gmail.<br>"
                        + "2. <a href=\"https://console.cloud.google.com/auth/audience\">Audience</a> : type <font color=\"" + Theme.ink + "\">Externe</font>, puis <font color=\"" + Theme.ink + "\">Publier l'application</font> (sinon l'accès expire après 7 jours).<br>"
                        + "3. <a href=\"https://console.cloud.google.com/auth/clients\">Clients</a> › Créer › <font color=\"" + Theme.ink + "\">Application de bureau</font>, puis copiez l'ID client et le code secret."
                    onLinkActivated: link => Api.invoke("open_url", { url: link })
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
                Field {
                    id: gid
                    visible: gCard.setup
                    width: parent.width
                    height: 38
                    radius: 10
                    pad: 10
                    bg: Theme.surfaceHigh
                    focusRing: true
                    placeholder: "ID client (…apps.googleusercontent.com)"
                    onFocused: Ilot.pinned = true
                    onAccepted: gsecret.input.forceActiveFocus()
                }
                Item {
                    visible: gCard.setup
                    width: parent.width
                    height: 38
                    Field {
                        id: gsecret
                        width: parent.width - gSave.width - 10
                        height: 38
                        radius: 10
                        pad: 10
                        bg: Theme.surfaceHigh
                        focusRing: true
                        password: true
                        placeholder: "Code secret du client"
                        onFocused: Ilot.pinned = true
                        onAccepted: gCard.saveClient()
                    }
                    TextBtn {
                        id: gSave
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        primary: true
                        icon: "link"
                        text: "Continuer"
                        onClicked: gCard.saveClient()
                    }
                }
            }
        }
        Card {
            id: form
            visible: !gCard.setup
            y: gCard.y + gCard.height + 10
            width: parent.width
            height: formCol.height + 28
            property string err: ""
            property bool errOn: false
            property bool sending: false
            function submit() {
                if (!email.text.trim() || !pass.text) {
                    (email.text.trim() ? pass : email).input.forceActiveFocus()
                    return
                }
                err = "Connexion…"
                errOn = false
                sending = true
                Api.invoke("mail_add", { email: email.text.trim(), pass: pass.text, host: host.text.trim() || null }).then(ib => {
                    Ilot.inbox = ib
                    email.text = ""
                    pass.text = ""
                    host.text = ""
                    form.err = ""
                    page.view = "list"
                }).catch(e => {
                    form.err = String(e)
                    form.errOn = true
                }).then(() => { form.sending = false }, () => { form.sending = false })
            }
            Column {
                id: formCol
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 8
                Txt {
                    text: "Ajouter un compte"
                    weight: Font.Bold
                }
                Field {
                    id: email
                    width: parent.width
                    height: 38
                    radius: 10
                    pad: 10
                    bg: Theme.surfaceHigh
                    focusRing: true
                    placeholder: "Adresse mail"
                    onFocused: Ilot.pinned = true
                    onAccepted: pass.input.forceActiveFocus()
                }
                Field {
                    id: pass
                    width: parent.width
                    height: 38
                    radius: 10
                    pad: 10
                    bg: Theme.surfaceHigh
                    focusRing: true
                    password: true
                    placeholder: "Mot de passe d'application"
                    onFocused: Ilot.pinned = true
                    onAccepted: form.submit()
                }
                Field {
                    id: host
                    width: parent.width
                    height: 38
                    radius: 10
                    pad: 10
                    bg: Theme.surfaceHigh
                    focusRing: true
                    placeholder: "Serveur IMAP (automatique pour Gmail, Yahoo, iCloud, Orange…)"
                    onFocused: Ilot.pinned = true
                    onAccepted: form.submit()
                }
                Item {
                    width: parent.width
                    height: 32
                    Txt {
                        width: parent.width - addBtn.width - 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: form.err
                        px: 12
                        color: form.errOn ? Theme.error : Theme.inkVariant
                        elide: Text.ElideRight
                    }
                    TextBtn {
                        id: addBtn
                        anchors.right: parent.right
                        primary: true
                        icon: "add"
                        text: "Ajouter"
                        disabled: form.sending
                        onClicked: form.submit()
                    }
                }
                Txt {
                    width: parent.width
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    px: 11.5
                    lineHeight: 1.2
                    color: Theme.inkVariant
                    linkColor: Theme.primary
                    text: "Gmail : activez la validation en deux étapes puis créez un <a href=\"https://myaccount.google.com/apppasswords\">mot de passe d'application</a> (16 lettres). Le mot de passe est chiffré et reste sur ce PC."
                    onLinkActivated: link => Api.invoke("open_url", { url: link })
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }
        }
    }
}
