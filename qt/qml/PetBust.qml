import QtQuick

// Buste anime d'un pack de compagnon (Reglages > Compagnon, cfg.pet =
// "pack:<id>", src/pets.rs), a la place de Pet dans la pilule et dans
// l'apercu des reglages. Il joue en boucle l'animation de l'humeur de Watch
// (json.bust.moods), et l'animation json.bust.click au clic.
//
// Planches par hauteur d'ecran (json.bust.variants -> variants.json :
// { size, variants: [{ h, dir }] }, une planche <dir>/<anim>.png deja
// recadree et reduite par variante) : hauteur voulue size x k (pixels
// logiques), soit size x k x DPR pixels physiques ; on prend la plus petite
// variante assez haute (sinon la plus grande) et on l'affiche telle quelle,
// 1:1 sur les pixels physiques (pas de sourceSize, filtrage au plus proche).
// Elle change si le DPR change (fenetre deplacee sur un autre ecran).
//
// Ancien format (json.bust.meta) : une seule planche, decoupee par
// json.bust.crop [x, y, w, h], reduite a la taille affichee par sourceSize,
// json.bust.scale (1 par defaut) pour l'agrandir.
//
// Encombrement : celui de Pet (20 x 18 x k). Le buste peut deborder un peu,
// centre, sans rien decaler.
Item {
    id: bust
    property var pack: Watch.petPack
    property string mood: Watch.mood
    property real k: 1
    property bool interactive: false
    // reagit aux tours demandes par Watch (fete, niveau gagne...)
    property bool listen: true
    property string tip: ""
    // centre sur la boite (pilule) ; sinon pose en bas (apercu)
    property bool centered: true
    // filtrage au plus proche (copie exacte de la planche) ; faux pendant
    // une mise a l'echelle (pilule reduite pendant une activite)
    property bool crisp: true

    signal poked()
    signal caressed()

    // meme encombrement que Pet : rien ne bouge dans la pilule
    width: 20 * k
    height: 18 * k

    readonly property var conf: pack && pack.json && pack.json.bust ? pack.json.bust : null
    readonly property var meta: pack && pack.meta && pack.meta.bust ? pack.meta.bust : null
    readonly property real dpr: Screen.devicePixelRatio || 1
    readonly property string dirUrl: conf && pack.url ? pack.url + (conf.dir ? conf.dir + "/" : "") : ""

    // ---------------------------------------------- planche a afficher
    readonly property var vlist: meta && Array.isArray(meta.variants)
        ? meta.variants.filter(v => v && v.h > 0 && v.dir && v.meta && v.meta.w > 0 && v.meta.h > 0 && v.meta.anims)
                       .sort((a, b) => a.h - b.h) : []
    readonly property bool multi: vlist.length > 0
    // hauteur voulue en pixels physiques (petite marge pour les arrondis)
    readonly property real need: (Number(meta && meta.size) || 18) * k * dpr
    readonly property var variant: multi ? vlist.find(v => v.h >= need - 0.05) || vlist[vlist.length - 1] : null
    // planche : { w, h, anims } (une image : w x h pixels de la planche)
    // calculee d'un bloc (dossier et dimensions changent ensemble) ; jamais
    // nulle : { w: 0 } si le pack est incomplet
    readonly property var sheet: {
        const m = variant ? variant.meta : meta
        if (!m || !(m.w > 0) || !(m.h > 0) || !m.anims || !dirUrl)
            return { w: 0, h: 0, anims: {}, crop: null, url: "" }
        return { w: m.w, h: m.h, anims: m.anims, crop: m.crop || null, url: variant ? dirUrl + variant.dir + "/" : dirUrl }
    }
    readonly property var anims: sheet.anims
    readonly property bool ok: !!conf && sheet.w > 0
    readonly property real fps: Math.max(1, Math.min(60, Number(conf && conf.fps) || 12))

    // animation jouee une fois (clic), puis retour a l'humeur
    property string once: ""
    readonly property string anim: {
        if (!ok)
            return ""
        const moods = conf.moods || {}
        // nom sur (il entre dans l'URL de la planche)
        const safe = a => typeof a === "string" && /^[\w-]+$/.test(a) && Array.isArray(anims[a])
        for (const a of [once, moods[mood], moods.idle])
            if (safe(a))
                return a
        return Object.keys(anims).find(safe) || ""
    }
    readonly property int count: anim ? anims[anim].length : 0
    onAnimChanged: frame = 0

    // ancien format : zone affichee (json.bust.crop ou "crop" du
    // sprites.json, [x, y, w, h], sinon l'image entiere) et taille
    function rectOf(c) {
        return Array.isArray(c) && c.length === 4 && c[2] > 0 && c[3] > 0 ? Qt.rect(c[0], c[1], c[2], c[3]) : null
    }
    readonly property rect crop: multi || !ok ? Qt.rect(0, 0, ok ? sheet.w : 1, ok ? sheet.h : 1)
        : rectOf(conf.crop) || rectOf(sheet.crop) || Qt.rect(0, 0, sheet.w, sheet.h)
    readonly property real zoom: Math.max(0.25, Math.min(4, Number(conf && conf.scale) || 1))
    readonly property real fit: Math.min(1, width * zoom / crop.width, height * zoom / crop.height)
    readonly property int sheetH: ok && !multi ? Math.max(1, Math.round(sheet.h * fit)) : 1
    // echelle planche -> pixels logiques : 1/DPR (1:1 physique) ou reduction
    readonly property real sc: !ok ? 0 : multi ? 1 / dpr : sheetH / sheet.h
    function snap(v) {
        return Math.round(v * dpr) / dpr
    }

    property int frame: 0
    // anime seulement quand quelqu'un regarde (comme Pet)
    readonly property bool alive: visible && ok && !Theme.reduced && (Ilot.ambient || Watch.petWinOn || interactive)
    Timer {
        interval: 1000 / bust.fps
        running: bust.alive && (bust.count > 1 || bust.once !== "")
        repeat: true
        onTriggered: {
            if (bust.frame + 1 < bust.count)
                return bust.frame++
            if (bust.once !== "")
                bust.once = ""
            else
                bust.frame = 0
        }
    }
    onAliveChanged: if (!alive) {
        once = ""
        frame = 0
    }

    // ------------------------------------------------------------ dessin
    Item {
        id: view
        visible: bust.ok
        width: bust.snap(bust.crop.width * bust.sc)
        height: bust.snap(bust.crop.height * bust.sc)
        x: bust.snap((bust.width - width) / 2)
        y: bust.snap(bust.centered ? (bust.height - height) / 2 : bust.height - height)
        // ancien format : la planche glisse dans la zone coupee, reduite par
        // Qt a la taille affichee (sourceSize)
        clip: !bust.multi
        Image {
            visible: !bust.multi
            source: !bust.multi && bust.ok && bust.anim ? bust.sheet.url + bust.anim + ".png" : ""
            sourceSize: Qt.size(0, bust.sheetH)
            smooth: true
            mipmap: true
            x: bust.snap(-(bust.frame * bust.sheet.w + bust.crop.x) * bust.sc)
            y: bust.snap(-bust.crop.y * bust.sc)
        }
        // variantes : une seule texture par planche, a sa taille native
        // (pixels physiques), image choisie par currentFrame ; au plus proche,
        // c'est une copie exacte meme si la pilule tombe entre deux pixels
        AnimatedSprite {
            visible: bust.multi
            width: bust.sheet.w / bust.dpr
            height: bust.sheet.h / bust.dpr
            source: bust.multi && bust.ok && bust.anim ? bust.sheet.url + bust.anim + ".png" : ""
            frameWidth: bust.sheet.w
            frameHeight: bust.sheet.h
            frameCount: Math.max(1, bust.count)
            currentFrame: bust.frame
            running: false
            interpolate: false
            smooth: !bust.crisp
        }
    }

    // --------------------------------------------- tours (API de Pet)
    // joue l'animation du clic ; rend sa duree en ms
    function trick(name) {
        const c = conf && conf.click && anims[conf.click] ? conf.click : ""
        if (!c || !alive)
            return 0
        once = c
        frame = 0
        return Math.round(anims[c].length * 1000 / fps)
    }
    function stopTricks() {
        once = ""
    }
    function fx(sym, o) {
    }
    function caress(on) {
        if (on)
            caressed()
    }
    Connections {
        target: Watch
        enabled: bust.listen
        function onPetTrick(name) {
            if (name === "flip" || name === "dance")
                bust.trick(name)
        }
    }

    MouseArea {
        id: touch
        enabled: bust.interactive
        visible: enabled
        anchors.fill: parent
        anchors.margins: -3 * bust.k
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        pressAndHoldInterval: 450
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            bust.poked()
            bust.trick("poke")
        }
        onDoubleClicked: bust.trick("flip")
        onPressAndHold: bust.caress(true)
    }
    Tip {
        text: bust.tip
        shown: bust.interactive && touch.containsMouse && !touch.pressed
    }
}
