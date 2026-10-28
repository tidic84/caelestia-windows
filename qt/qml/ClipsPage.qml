import QtQuick

// Presse-papiers : historique (texte et images) et bloc-notes a plusieurs
// notes, en Markdown ou en texte brut (%LOCALAPPDATA%\Ilot\notes.json :
// { notes: [{ id, text, t }], cur, md })
Item {
    id: page
    // "hist" | "notes"
    property string view: "hist"
    property string status: ""
    readonly property int n: Ilot.clips.length
    readonly property string count: n ? n + " élément" + (n > 1 ? "s" : "") : "Historique vide"
    // historique a l'ecran (Win+V) : fleches pour choisir, Entree pour valider
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "clips" && view === "hist"
        && !Watch.shareOpen && !Watch.convertOpen
    property int sel: 0
    onShownChanged: if (shown) resetSel()
    // Win+V alors que l'historique est deja affiche : le focus revient a la liste
    Connections {
        target: Ilot
        function onTabShown(tab) { if (tab === "clips" && page.shown) page.resetSel() }
    }
    onNChanged: sel = Math.max(0, Math.min(sel, n - 1))
    function resetSel() {
        sel = 0
        flick.contentY = 0
        // la page vient d'etre activee (enabled) : focus apres
        Qt.callLater(() => page.forceActiveFocus())
    }
    // copie l'element, puis referme l'ilot (clic ou Entree)
    function pick(id) {
        Api.invoke("clip_copy", { id: id })
        Ilot.close()
    }
    function ensureVisible(i) {
        const it = clipRep.itemAt(i)
        if (!it)
            return
        if (it.y < flick.contentY)
            flick.contentY = it.y
        else if (it.y + it.height > flick.contentY + flick.height)
            flick.contentY = it.y + it.height - flick.height
    }
    Keys.onPressed: e => {
        if (!shown || !n)
            return
        if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) {
            sel = Math.max(0, Math.min(n - 1, sel + (e.key === Qt.Key_Down ? 1 : -1)))
            ensureVisible(sel)
            e.accepted = true
        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            e.accepted = true
            pick(Ilot.clips[sel].id)
        }
    }
    function noteStatus() {
        const c = notes.text.length
        return c ? c + " caractère" + (c > 1 ? "s" : "") : "Note vide"
    }
    function flash(msg, ms) {
        status = msg
        statusTimer.interval = ms
        statusTimer.restart()
    }
    Timer {
        id: statusTimer
        onTriggered: page.status = ""
    }
    // ------------------------------------------------------ notes
    readonly property var cur: Ilot.notes.find(x => x.id === Ilot.noteCur) || null
    // Markdown : apercu de la note, ou edition (texte brut)
    readonly property bool md: Ilot.notesMd
    property bool editing: true
    readonly property bool preview: md && !editing
    // texte tape pas encore reporte dans la liste
    property bool dirty: false
    Timer {
        id: saveTimer
        interval: 400
        onTriggered: page.commit()
    }
    function store() {
        Api.invoke("store_set", { key: "notes", value: { notes: Ilot.notes, cur: Ilot.noteCur, md: Ilot.notesMd } })
            .then(ok => page.flash(ok ? "Enregistré" : "Erreur d’enregistrement", 1500))
    }
    // le texte de l'editeur dans la note ouverte, puis sur le disque
    function commit() {
        saveTimer.stop()
        if (!dirty)
            return
        dirty = false
        const id = Ilot.noteCur
        // la liste est recreee : elle garde son defilement
        const y = noteList.contentY
        if (!Ilot.notes.some(x => x.id === id))
            Ilot.notes = [{ id: id, text: notes.text, t: Date.now() }].concat(Ilot.notes)
        else
            Ilot.notes = Ilot.notes.map(x => x.id === id ? { id: id, text: notes.text, t: Date.now() } : x)
        Qt.callLater(() => { noteList.contentY = Math.max(0, Math.min(y, noteList.contentHeight - noteList.height)) })
        store()
    }
    function saveNotes() {
        dirty = true
        saveTimer.restart()
    }
    // ouvre une note : apercu si elle a du texte (Markdown), edition sinon
    function openNote(id) {
        commit()
        Ilot.noteCur = id
        const nt = Ilot.notes.find(x => x.id === id)
        notes.text = nt ? nt.text : ""
        editing = !md || !notes.text
        notes.edit.cursorPosition = notes.text.length
        if (view === "notes" && editing)
            Qt.callLater(() => notes.edit.forceActiveFocus())
        store()
    }
    function newNote() {
        commit()
        // la note ouverte est deja vide : on la garde
        if (cur && !cur.text.trim())
            return openNote(cur.id)
        const id = "n" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36)
        Ilot.notes = [{ id: id, text: "", t: Date.now() }].concat(Ilot.notes)
        openNote(id)
    }
    function deleteNote(id) {
        commit()
        const i = Ilot.notes.findIndex(x => x.id === id)
        Ilot.notes = Ilot.notes.filter(x => x.id !== id)
        if (!Ilot.notes.length)
            return newNote()
        if (id === Ilot.noteCur)
            openNote(Ilot.notes[Math.min(i, Ilot.notes.length - 1)].id)
        else
            store()
    }
    function setMd(on) {
        commit()
        Ilot.notesMd = on
        editing = !on || !notes.text
        store()
    }
    function startEdit() {
        editing = true
        Qt.callLater(() => notes.edit.forceActiveFocus())
    }
    function addToNotes(t) {
        if (!Ilot.noteCur)
            newNote()
        const v = notes.text.replace(/\s+$/, "")
        notes.text = (v ? v + "\n\n" : "") + t
        saveNotes()
    }
    // le Markdown ignore linkColor : libelles des liens [texte](url) colores
    function mdLinks(t) {
        const c = String(Theme.primary)
        return t.replace(/(^|[^!\\])\[([^\]\n]+)\]\(([^)\s]+)\)/g, (m, a, label, url) => a + "[<span style=\"color:" + c + "\">" + label + "</span>](" + url + ")")
    }
    // titre : premiere ligne, sans les marques Markdown
    function noteTitle(nt) {
        const line = nt.text.split("\n").map(l => l.trim()).find(l => l) || ""
        return line.replace(/^(#+|>|[-*+]\s+\[[ xX]\]|[-*+]|\d+[.)])\s*/, "").replace(/[*_`~]/g, "").trim() || "Nouvelle note"
    }
    function noteDate(t) {
        if (!t)
            return ""
        const d = new Date(t), now = new Date()
        if (d.toDateString() === now.toDateString())
            return d.toLocaleTimeString(Qt.locale("fr_FR"), "HH:mm")
        return d.toLocaleDateString(Qt.locale("fr_FR"), d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy")
    }
    Component.onCompleted: loadNotes()
    // notes lues apres la creation de la page
    Connections {
        target: Ilot
        function onNotesLoaded() { page.loadNotes() }
    }
    function loadNotes() {
        if (!Ilot.notes.length) {
            const id = "n" + Date.now().toString(36)
            Ilot.notes = [{ id: id, text: "", t: Date.now() }]
            Ilot.noteCur = id
        } else if (!Ilot.notes.some(x => x.id === Ilot.noteCur)) {
            Ilot.noteCur = Ilot.notes[0].id
        }
        dirty = false
        notes.text = cur ? cur.text : ""
        editing = !md || !notes.text
    }
    onViewChanged: if (view !== "notes") commit()
    Component.onDestruction: commit()

    // ---------------------------------------- mise en forme Markdown
    // entoure la selection (gras, italique...) ou place le curseur au milieu
    function wrap(mark) {
        const e = notes.edit
        const a = e.selectionStart, b = e.selectionEnd
        const sel = e.text.slice(a, b)
        if (sel.startsWith(mark) && sel.endsWith(mark) && sel.length >= 2 * mark.length) {
            e.remove(a, b)
            e.insert(a, sel.slice(mark.length, sel.length - mark.length))
            e.select(a, b - 2 * mark.length)
        } else {
            e.remove(a, b)
            e.insert(a, mark + sel + mark)
            if (sel)
                e.select(a, b + 2 * mark.length)
            else
                e.cursorPosition = a + mark.length
        }
        e.forceActiveFocus()
        saveNotes()
    }
    // ajoute ou retire un debut de ligne (titre, liste...) aux lignes choisies
    function prefix(p) {
        const e = notes.edit
        const t = e.text
        const start = t.lastIndexOf("\n", e.selectionStart - 1) + 1
        let end = t.indexOf("\n", Math.max(e.selectionEnd, start))
        if (end < 0)
            end = t.length
        const lines = t.slice(start, end).split("\n")
        // marques du meme genre remplacees (« - » devient « - [ ] »...)
        const kind = /^(#{1,6} |[-*] \[[ xX]\] |[-*] |\d+\. |> )/
        const all = lines.every(l => l.startsWith(p))
        const out = lines.map((l, i) => {
            if (all)
                return l.slice(p.length)
            const bare = l.replace(kind, "")
            return (p === "1. " ? (i + 1) + ". " : p) + bare
        }).join("\n")
        e.remove(start, end)
        e.insert(start, out)
        e.cursorPosition = start + out.length
        e.forceActiveFocus()
        saveNotes()
    }

    Item {
        id: head
        width: parent.width
        height: 32
        Seg {
            id: seg
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            model: [{ id: "hist", label: "Historique" }, { id: "notes", label: "Bloc-notes" }]
            current: page.view
            onPicked: id => {
                page.view = id
                if (id === "notes" && page.editing)
                    notes.edit.forceActiveFocus()
            }
        }
        Txt {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: (seg.width - buttons.width) / 2
            text: page.view === "notes" ? (page.status || (notes.text, page.noteStatus())) : page.count
            color: Theme.inkVariant
        }
        Row {
            id: buttons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            TextBtn {
                visible: page.view === "hist"
                icon: "delete"
                text: "Effacer"
                onClicked: Api.invoke("clips_clear")
            }
            spacing: 8
            Txt {
                visible: page.view === "notes"
                anchors.verticalCenter: parent.verticalCenter
                text: "Markdown"
                px: 12.5
                color: Theme.inkVariant
            }
            M3Switch {
                visible: page.view === "notes"
                anchors.verticalCenter: parent.verticalCenter
                checked: page.md
                tip: page.md ? "Mise en forme Markdown : titres, gras, listes, cases à cocher, liens…" : "Texte brut, sans mise en forme"
                onToggled: on => page.setMd(on)
            }
            TextBtn {
                visible: page.view === "notes"
                icon: "content_copy"
                text: "Copier"
                onClicked: {
                    Api.invoke("clip_text", { text: notes.text })
                    page.flash("Copié", 1200)
                }
            }
        }
    }

    Flickable {
        id: flick
        visible: page.view === "hist"
        y: head.height + 10
        width: parent.width - 4
        height: parent.height - y
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            spacing: 6
            Empty {
                visible: page.n === 0
                width: parent.width
                text: "Copiez du texte ou une image : ils apparaîtront ici."
            }
            Repeater {
                id: clipRep
                model: Ilot.clips
                Btn {
                    id: clip
                    required property var modelData
                    required property int index
                    readonly property bool isText: modelData.text !== null && modelData.text !== undefined
                    readonly property bool selected: page.sel === clip.index
                    property bool done: false
                    width: col.width
                    height: isText ? Math.max(42, txt.implicitHeight + 22) : Math.min(120, imgBox.h) + 16
                    radius: 16
                    color: hovered || noteAdd.hovered || selected ? Theme.surfaceHigh : Theme.surfaceC
                    border.width: selected ? 1.5 : 0
                    border.color: Theme.primary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Timer {
                        id: doneTimer
                        interval: 1200
                        onTriggered: clip.done = false
                    }
                    onClicked: page.pick(clip.modelData.id)
                    Txt {
                        id: txt
                        visible: clip.isText
                        x: 14
                        width: parent.width - 14 - 14 - 12 - 20 - 12 - 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: clip.isText ? (clip.modelData.text.length > 600 ? clip.modelData.text.slice(0, 600) + "…" : clip.modelData.text) : ""
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        lineHeight: 1.35
                        textFormat: Text.PlainText
                    }
                    // image : damier sous la transparence
                    Item {
                        id: imgBox
                        visible: !clip.isText
                        x: 8
                        y: 8
                        readonly property real w: clip.modelData.w || 1
                        readonly property real h: clip.modelData.h || 1
                        readonly property real k: Math.min(120 / h, (clip.width * 0.7) / w, 1)
                        width: w * k
                        height: Math.min(120, h * k)
                        Canvas {
                            anchors.fill: parent
                            visible: imgBox.visible
                            readonly property color a: Theme.surfaceHigh
                            readonly property color b: Theme.surfaceHighest
                            onAChanged: requestPaint()
                            onPaint: {
                                const g = getContext("2d")
                                g.fillStyle = a
                                g.fillRect(0, 0, width, height)
                                g.fillStyle = b
                                for (let y = 0; y < height; y += 7)
                                    for (let x = ((y / 7) % 2) * 7; x < width; x += 14)
                                        g.fillRect(x, y, 7, 7)
                            }
                        }
                        RoundImage {
                            anchors.fill: parent
                            radius: 10
                            cover: false
                            source: clip.isText ? "" : clip.modelData.thumb || ""
                        }
                    }
                    Txt {
                        visible: !clip.isText
                        x: imgBox.x + imgBox.width + 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: (clip.modelData.w || 0) + " × " + (clip.modelData.h || 0)
                        px: 12
                        color: Theme.inkVariant
                    }
                    // ajouter au bloc-notes
                    Btn {
                        id: noteAdd
                        visible: clip.isText
                        anchors.right: check.left
                        anchors.rightMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        radius: 14
                        opacity: clip.hovered || hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        color: hovered ? Theme.surfaceHighest : "transparent"
                        tip: "Ajouter au bloc-notes"
                        onClicked: {
                            page.addToNotes(clip.modelData.text)
                            clip.done = true
                            doneTimer.restart()
                        }
                        Ms {
                            anchors.centerIn: parent
                            name: "note_add"
                            size: 18
                            color: parent.hovered ? Theme.ink : Theme.inkVariant
                        }
                    }
                    Ms {
                        id: check
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check"
                        color: Theme.primary
                        opacity: clip.done ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }
            }
        }
    }
    Scroller { flick: flick }

    // liste des notes
    Rectangle {
        id: list
        visible: page.view === "notes"
        y: head.height + 10
        width: 210
        height: parent.height - y
        radius: 18
        color: Theme.surfaceC
        Btn {
            id: addBtn
            x: 8
            y: 8
            width: parent.width - 16
            height: 36
            radius: 12
            color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
            onClicked: page.newNote()
            Row {
                anchors.centerIn: parent
                spacing: 6
                Ms {
                    name: "add"
                    size: 18
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                    text: "Nouvelle note"
                    px: 12.5
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
        ListView {
            id: noteList
            x: 8
            y: addBtn.y + addBtn.height + 6
            width: parent.width - 16
            height: parent.height - y - 8
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: Ilot.notes
            delegate: Btn {
                id: item
                required property var modelData
                readonly property bool on: modelData.id === Ilot.noteCur
                // la note ouverte suit la frappe
                readonly property string text: on ? notes.text : modelData.text
                width: noteList.width
                height: 48
                radius: 12
                color: on ? Theme.secondaryContainer : hovered || del.hovered ? Theme.surfaceHigh : "transparent"
                onClicked: if (!on) page.openNote(modelData.id)
                Column {
                    x: 10
                    width: parent.width - 20 - (del.visible ? del.width + 4 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Txt {
                        width: parent.width
                        text: page.noteTitle({ text: item.text })
                        px: 12.5
                        weight: Font.Medium
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: item.on ? Theme.inkSecondaryContainer : Theme.ink
                    }
                    Txt {
                        width: parent.width
                        text: page.noteDate(item.modelData.t)
                        px: 11
                        elide: Text.ElideRight
                        color: item.on ? Theme.inkSecondaryContainer : Theme.inkVariant
                    }
                }
                // supprimer : second clic pour confirmer
                IconBtn {
                    id: del
                    visible: item.hovered || hovered || armed
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    small: true
                    icon: "delete"
                    tip: armed ? "Cliquer encore pour supprimer" : "Supprimer la note"
                    onClicked: {
                        if (!armed) {
                            armed = true
                            disarm.restart()
                            return
                        }
                        page.deleteNote(item.modelData.id)
                    }
                    Timer {
                        id: disarm
                        interval: 2500
                        onTriggered: del.armed = false
                    }
                }
            }
        }
        Scroller { flick: noteList }
    }

    // note ouverte
    Rectangle {
        id: noteBox
        visible: page.view === "notes"
        x: list.width + 10
        y: head.height + 10
        width: parent.width - x
        height: parent.height - y
        radius: 18
        color: Theme.surfaceC

        // barre de mise en forme (Markdown)
        Row {
            id: tools
            visible: page.md
            x: 10
            y: 8
            height: visible ? 30 : 0
            spacing: 2
            Repeater {
                model: page.editing ? [
                    ["title", "Titre", () => page.prefix("# ")],
                    ["format_bold", "Gras (Ctrl+B)", () => page.wrap("**")],
                    ["format_italic", "Italique (Ctrl+I)", () => page.wrap("*")],
                    ["format_strikethrough", "Barré", () => page.wrap("~~")],
                    ["format_list_bulleted", "Liste", () => page.prefix("- ")],
                    ["format_list_numbered", "Liste numérotée", () => page.prefix("1. ")],
                    ["checklist", "Cases à cocher", () => page.prefix("- [ ] ")],
                    ["format_quote", "Citation", () => page.prefix("> ")],
                    ["code", "Code", () => page.wrap("`")]
                ] : []
                IconBtn {
                    required property var modelData
                    small: true
                    icon: modelData[0]
                    tip: modelData[1]
                    onClicked: modelData[2]()
                }
            }
        }
        IconBtn {
            visible: page.md
            anchors.right: parent.right
            anchors.rightMargin: 10
            y: 8
            small: true
            on: page.preview
            icon: page.preview ? "edit" : "visibility"
            tip: page.preview ? "Modifier (clic dans la note)" : "Aperçu (Échap)"
            onClicked: {
                if (page.preview)
                    return page.startEdit()
                page.commit()
                page.editing = false
            }
        }

        Area {
            id: notes
            visible: !page.preview
            y: tools.height + (page.md ? 8 : 0)
            width: parent.width
            height: parent.height - y
            radius: 18
            color: "transparent"
            fontSize: 14
            padX: 16
            padY: page.md ? 6 : 14
            placeholder: page.md
                ? "Écrivez en Markdown : # titre, **gras**, *italique*, - liste, - [ ] case à cocher, [lien](https://…)"
                : "Écrivez vos notes ici… Elles sont enregistrées automatiquement."
            // on ecrit : l'ilot reste ouvert meme si la souris sort
            onFocused: Ilot.pinned = true
            onEdited: page.saveNotes()
            onKeyPressed: e => {
                if (!page.md)
                    return
                if (e.key === Qt.Key_Escape) {
                    e.accepted = true
                    page.commit()
                    page.editing = false
                } else if (e.modifiers & Qt.ControlModifier && e.key === Qt.Key_B) {
                    e.accepted = true
                    page.wrap("**")
                } else if (e.modifiers & Qt.ControlModifier && e.key === Qt.Key_I) {
                    e.accepted = true
                    page.wrap("*")
                } else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                    // Entree dans une liste : l'element suivant (vide : fin de la liste)
                    const ed = notes.edit
                    const t = ed.text
                    const pos = ed.cursorPosition
                    const start = t.lastIndexOf("\n", pos - 1) + 1
                    const m = t.slice(start, pos).match(/^(\s*)([-*+] \[[ xX]\] |[-*+] |(\d+)\. |> )(.*)$/)
                    if (!m || ed.selectionStart !== ed.selectionEnd)
                        return
                    e.accepted = true
                    if (!m[4].trim()) {
                        ed.remove(start, pos)
                    } else {
                        const next = m[3] ? (Number(m[3]) + 1) + ". " : m[2].replace(/\[[xX]\]/, "[ ]")
                        ed.insert(pos, "\n" + m[1] + next)
                    }
                    page.saveNotes()
                }
            }
        }

        // apercu Markdown : clic pour modifier, liens ouverts dans le navigateur
        Flickable {
            id: prevFl
            visible: page.preview
            x: 18
            y: tools.height + 12
            width: parent.width - 36
            height: parent.height - y - 14
            contentHeight: prev.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Text {
                id: prev
                width: prevFl.width
                // toute la zone : un clic sous une note courte la modifie aussi
                height: Math.max(implicitHeight, prevFl.height)
                verticalAlignment: Text.AlignTop
                text: page.preview ? page.mdLinks(notes.text) : ""
                textFormat: Text.MarkdownText
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pointSize: 14 * 0.75
                lineHeight: 1.2
                color: Theme.ink
                HoverHandler {
                    cursorShape: prev.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor
                }
                TapHandler {
                    onTapped: ev => {
                        const link = prev.linkAt(ev.position.x, ev.position.y)
                        if (link)
                            Api.invoke("open_url", { url: link })
                        else
                            page.startEdit()
                    }
                }
            }
        }
        Scroller {
            visible: page.preview && prevFl.contentHeight > prevFl.height + 1
            flick: prevFl
        }
    }
}
