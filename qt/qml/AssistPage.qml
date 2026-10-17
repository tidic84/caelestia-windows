import QtQuick

// Assistant : traduction (src/translate.rs), sous-titres en direct de tout le
// son du PC (src/captions.rs, bandeau Captions.qml) et questions envoyees a
// l'application Claude (lien claude://, rien ne passe par l'API). Chaque
// partie se desactive dans Reglages > Addons (cfg.assist_tr, cfg.assist_claude).
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "assist"
    readonly property bool trOn: Ilot.cfg.assist_tr !== false
    readonly property bool clOn: Ilot.cfg.assist_claude !== false
    property string pick: "translate"
    // partie desactivee : l'autre
    readonly property string view: !clOn ? "translate" : !trOn ? "claude" : pick
    onShownChanged: if (shown) Qt.callLater(focusInput)
    function focusInput() {
        Ilot.grabFocus()
        const area = view === "claude" ? clIn : trIn
        area.edit.forceActiveFocus()
    }

    Item {
        id: head
        width: parent.width
        height: 34
        Seg {
            id: seg
            anchors.verticalCenter: parent.verticalCenter
            // une seule partie : pas de choix
            visible: page.trOn && page.clOn
            width: visible ? implicitWidth : 0
            model: [{ id: "translate", label: "Traduction" }, { id: "claude", label: "Claude" }]
            current: page.view
            onPicked: id => {
                page.pick = id
                Qt.callLater(page.focusInput)
            }
        }
        // traduction : langues
        Row {
            visible: page.view === "translate"
            x: seg.visible ? seg.width + 12 : 0
            spacing: 4
            anchors.verticalCenter: parent.verticalCenter
            LangBtn {
                id: fromBtn
                value: page.from
                auto: true
                tip: "Langue du texte"
                onPicked: v => { page.from = v; page.saveLangs(); page.run() }
            }
            IconBtn {
                small: true
                icon: "swap_horiz"
                tip: "Inverser les langues"
                onClicked: page.swap()
            }
            LangBtn {
                value: page.to
                tip: "Traduire en"
                onPicked: v => { page.to = v; page.saveLangs(); page.run() }
            }
        }
        Txt {
            visible: page.view === "claude"
            x: seg.visible ? seg.width + 12 : 0
            width: parent.width - x - clTools.width - 10
            anchors.verticalCenter: parent.verticalCenter
            text: page.clNote
            px: 11.5
            color: Theme.inkVariant
            elide: Text.ElideRight
        }
        Row {
            id: trTools
            visible: page.view === "translate"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            TextBtn {
                icon: "closed_caption"
                text: "Sous-titres"
                primary: Watch.capOn
                tip: "Sous-titres en direct de tout le son du PC, traduits en français (Live Captions de Windows)"
                onClicked: Watch.toggleCaptions()
            }
            IconBtn {
                icon: "content_paste"
                tip: "Coller le dernier texte copié"
                onClicked: {
                    const last = Ilot.clips.find(c => c.text)
                    if (!last)
                        return
                    trIn.text = last.text.slice(0, 4500)
                    page.run()
                    trIn.edit.forceActiveFocus()
                }
            }
        }
        Row {
            id: clTools
            visible: page.view === "claude"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Seg {
                model: [{ id: "chat", label: "Discussion" }, { id: "cowork", label: "Cowork" }]
                current: page.clMode
                onPicked: id => { page.clMode = id; clIn.edit.forceActiveFocus() }
            }
            TextBtn {
                icon: "terminal"
                text: "Code"
                tip: "Nouvelle session Claude Code"
                onClicked: { Api.invoke("open_url", { url: "claude://code/new" }); Ilot.setMode("collapsed") }
            }
            TextBtn {
                icon: "open_in_new"
                text: "Ouvrir"
                tip: "Ouvrir l'application Claude"
                onClicked: { Api.invoke("open_url", { url: "claude://claude.ai/new" }); Ilot.setMode("collapsed") }
            }
        }
    }

    // ======================================================== traduction
    readonly property var langs: [
        ["auto", "Détecter la langue"], ["fr", "Français"], ["en", "Anglais"], ["es", "Espagnol"], ["de", "Allemand"],
        ["it", "Italien"], ["pt", "Portugais"], ["nl", "Néerlandais"], ["pl", "Polonais"], ["ru", "Russe"], ["uk", "Ukrainien"],
        ["tr", "Turc"], ["ar", "Arabe"], ["hi", "Hindi"], ["ja", "Japonais"], ["ko", "Coréen"], ["zh-CN", "Chinois"]
    ]
    function langName(c) {
        const l = langs.find(x => x[0] === c || x[0].split("-")[0] === c)
        return l ? l[1] : c
    }
    property string from: "auto"
    property string to: "fr"
    property string detected: ""
    property string out: ""
    property string det: ""
    property bool trBusy: false
    property int seq: 0
    Component.onCompleted: {
        Api.invoke("store_get", { key: "translate" }).then(t => {
            if (t && t.from)
                page.from = t.from
            if (t && t.to)
                page.to = t.to
        })
        Api.invoke("store_get", { key: "claude" }).then(c => { if (c && Array.isArray(c.hist)) page.clHist = c.hist })
    }
    function saveLangs() {
        Api.invoke("store_set", { key: "translate", value: { from: from, to: to } })
    }
    Timer {
        id: trTimer
        interval: 450
        onTriggered: page.run()
    }
    function run() {
        const text = trIn.text
        const n = ++seq
        if (!text.trim()) {
            out = ""
            det = ""
            return
        }
        trBusy = true
        Api.invoke("translate", { text: text, from: from, to: to }).then(r => {
            // texte deja dans la langue visee (« Detecter ») : vers l'anglais (ou le francais)
            let dest = page.to
            if (page.from === "auto" && r.detected && r.detected.split("-")[0] === dest.split("-")[0]) {
                dest = dest === "en" ? "fr" : "en"
                return Api.invoke("translate", { text: text, from: "auto", to: dest }).then(r2 => [r2, dest])
            }
            return [r, dest]
        }).then(res => {
            if (n !== page.seq)
                return
            const r = res[0]
            page.detected = r.detected || ""
            page.out = r.text
            page.det = (page.from === "auto" && r.detected ? "Détecté : " + page.langName(r.detected) + " · " : "") + "vers " + page.langName(res[1])
            page.trBusy = false
        }, e => {
            if (n !== page.seq)
                return
            page.out = ""
            page.det = "⚠ " + e
            page.trBusy = false
        })
    }
    function swap() {
        // « Detecter » n'a pas de sens a l'arrivee : on prend la langue detectee
        const known = c => langs.slice(1).some(l => l[0] === c)
        const f = from !== "auto" ? from : known(detected) ? detected : (to === "fr" ? "en" : "fr")
        from = to
        to = f
        if (out)
            trIn.text = out
        saveLangs()
        run()
    }

    Row {
        visible: page.view === "translate"
        y: head.height + 12
        width: parent.width
        height: parent.height - y
        spacing: 10
        Card {
            width: (parent.width - 10) / 2
            height: parent.height
            Area {
                id: trIn
                anchors.fill: parent
                anchors.margins: 10
                anchors.bottomMargin: 40
                color: "transparent"
                border.width: 0
                fontSize: 15
                placeholder: "Tape ou colle un texte à traduire…"
                onFocused: Ilot.pinned = true
                onEdited: {
                    if (text.length > 4500)
                        text = text.slice(0, 4500)
                    trTimer.restart()
                }
            }
            Txt {
                x: 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                text: trIn.text.length + " / 4500"
                px: 11
                color: Theme.inkVariant
            }
            IconBtn {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                small: true
                icon: "close"
                tip: "Effacer"
                onClicked: {
                    trIn.text = ""
                    page.run()
                    trIn.edit.forceActiveFocus()
                }
            }
        }
        Card {
            width: (parent.width - 10) / 2
            height: parent.height
            color: Theme.surfaceHigh
            Flickable {
                id: outFl
                anchors.fill: parent
                anchors.margins: 20
                anchors.bottomMargin: 44
                contentHeight: outText.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                TextEdit {
                    id: outText
                    width: outFl.width
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    text: page.out
                    font.family: Theme.font
                    font.pointSize: 15 * 0.75
                    color: Theme.ink
                    opacity: page.trBusy ? 0.6 : 1
                    selectionColor: Theme.alpha(Theme.primary, 0.4)
                }
            }
            Scroller { flick: outFl }
            Txt {
                x: 16
                width: parent.width - 60
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                text: page.det
                px: 11
                elide: Text.ElideRight
                color: page.det.startsWith("⚠") ? Theme.error : Theme.inkVariant
            }
            IconBtn {
                id: copyBtn
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                small: true
                property bool done: false
                icon: done ? "check" : "content_copy"
                tip: "Copier la traduction"
                onClicked: {
                    if (!page.out)
                        return
                    Api.invoke("clip_text", { text: page.out })
                    done = true
                    copyDone.restart()
                }
                Timer {
                    id: copyDone
                    interval: 1200
                    onTriggered: copyBtn.done = false
                }
            }
        }
    }

    // ============================================================ Claude
    property string clMode: "chat"
    property var clHist: []
    property string clNote: ""
    readonly property var quick: [
        ["summarize", "Résumer", "Résume ce texte en quelques points :"],
        ["help", "Expliquer", "Explique-moi simplement :"],
        ["spellcheck", "Corriger", "Corrige l’orthographe et la grammaire de ce texte, sans changer le sens :"],
        ["translate", "En français", "Traduis en français :"],
        ["reply", "Répondre", "Aide-moi à répondre à ce message :"],
        ["code", "Code", "Explique ce code et signale les bugs éventuels :"]
    ]
    function ask(text) {
        text = text.trim()
        if (!text)
            return
        const host = clMode === "cowork" ? "cowork" : "claude.ai"
        Api.invoke("open_url", { url: "claude://" + host + "/new?q=" + encodeURIComponent(text) })
        clHist = [text].concat(clHist.filter(t => t !== text)).slice(0, 20)
        Api.invoke("store_set", { key: "claude", value: { hist: clHist } })
        clIn.text = ""
        clNote = "Envoyé : valide dans Claude avec Entrée"
        Ilot.setMode("collapsed")
    }

    Row {
        visible: page.view === "claude"
        y: head.height + 12
        width: parent.width
        height: parent.height - y
        spacing: 10
        Card {
            width: parent.width - 240 - 10
            height: parent.height
            Area {
                id: clIn
                anchors.fill: parent
                anchors.margins: 10
                anchors.bottomMargin: 96
                color: "transparent"
                border.width: 0
                fontSize: 14
                placeholder: "Demande quelque chose à Claude…"
                onFocused: Ilot.pinned = true
                onEdited: {
                    page.clNote = ""
                    if (text.length > 6000)
                        text = text.slice(0, 6000)
                }
                // Entree : envoyer ; Maj+Entree : nouvelle ligne
                onKeyPressed: e => {
                    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                        e.accepted = true
                        page.ask(clIn.text)
                    }
                }
            }
            // le prompt + le dernier texte copie
            Flow {
                x: 12
                width: parent.width - 24
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 50
                spacing: 6
                Repeater {
                    model: page.quick
                    Btn {
                        required property var modelData
                        width: qRow.implicitWidth + 20
                        height: 28
                        radius: 14
                        color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                        tip: modelData[2] + " + dernier texte copié"
                        onClicked: {
                            const last = Ilot.clips.find(c => c.text)
                            if (!last) {
                                page.clNote = "Copie d’abord un texte (Ctrl+C)"
                                return
                            }
                            clIn.text = (modelData[2] + "\n\n" + last.text).slice(0, 6000)
                            clIn.edit.forceActiveFocus()
                        }
                        Row {
                            id: qRow
                            anchors.centerIn: parent
                            spacing: 4
                            Ms {
                                name: parent.parent.modelData[0]
                                size: 16
                                color: Theme.primary
                            }
                            Txt {
                                text: parent.parent.modelData[1]
                                px: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
            Txt {
                x: 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                text: "Entrée : envoyer · Maj+Entrée : nouvelle ligne"
                px: 11
                color: Theme.inkVariant
            }
            TextBtn {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                primary: true
                icon: "send"
                text: "Demander"
                onClicked: page.ask(clIn.text)
            }
        }
        Card {
            width: 240
            height: parent.height
            Txt {
                x: 14
                y: 14
                text: "Dernières questions"
                px: 11.5
                weight: Font.Medium
                color: Theme.inkVariant
            }
            ListView {
                id: hist
                x: 8
                y: 38
                width: parent.width - 16
                height: parent.height - y - 8
                clip: true
                spacing: 2
                model: page.clHist
                boundsBehavior: Flickable.StopAtBounds
                delegate: Btn {
                    required property var modelData
                    width: hist.width
                    height: 44
                    radius: 12
                    color: hovered ? Theme.surfaceHigh : "transparent"
                    tip: "Reprendre cette question"
                    onClicked: {
                        clIn.text = modelData
                        clIn.edit.forceActiveFocus()
                    }
                    Txt {
                        x: 8
                        width: parent.width - 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData
                        px: 12
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
                Empty {
                    visible: !page.clHist.length
                    width: hist.width
                    small: true
                    text: "Tes questions apparaîtront ici."
                }
            }
        }
    }

    // bouton de langue : ouvre la liste
    component LangBtn: Btn {
        id: lb
        property string value
        property bool auto: false
        signal picked(string v)
        width: lbRow.implicitWidth + 22
        height: 30
        radius: 15
        color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
        onClicked: {
            const p = lb.mapToItem(page, 0, lb.height + 4)
            ctx.show(p.x, p.y, (lb.auto ? page.langs : page.langs.slice(1)).map(l => ({
                icon: l[0] === lb.value ? "check" : "translate", label: l[1], run: () => { ctx.hide(); lb.picked(l[0]) }
            })))
        }
        Row {
            id: lbRow
            anchors.centerIn: parent
            spacing: 4
            Txt {
                text: page.langName(lb.value)
                px: 12.5
                anchors.verticalCenter: parent.verticalCenter
            }
            Ms {
                name: "expand_more"
                size: 16
                color: Theme.inkVariant
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    CtxMenu {
        id: ctx
        area: page
    }
    MouseArea {
        anchors.fill: parent
        z: 9
        visible: ctx.visible
        onPressed: ctx.hide()
    }
}
