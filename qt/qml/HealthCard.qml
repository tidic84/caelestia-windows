import QtQuick

// Sante du PC (src/health.rs) : place libre et etat des disques, pilote
// NVIDIA a jour ou non, nettoyage en un clic (temporaires, caches de
// shaders, miniatures, corbeille). Relu au plus une fois par minute.
PcCard {
    id: hc
    title: "Santé du PC"
    property var h: null
    property real at: 0
    // cases cochees : id -> vrai (la corbeille n'est jamais cochee d'office)
    property var checked: ({})
    property bool first: true
    property bool cleaning: false

    function refresh(force) {
        if (!force && Date.now() - at < 60000)
            return
        at = Date.now()
        Api.invoke("health_get").then(r => {
            const c = {}
            for (const it of r.clean)
                c[it.id] = it.bytes > 0 && (hc.first ? it.id !== "recycle" : !!hc.checked[it.id])
            hc.checked = c
            hc.first = false
            hc.h = r
        })
    }
    // « 581.57 » > « 566.36 »
    function verGt(a, b) {
        const x = a.split(".").map(Number), y = b.split(".").map(Number)
        for (let i = 0; i < Math.max(x.length, y.length); i++)
            if ((x[i] || 0) !== (y[i] || 0))
                return (x[i] || 0) > (y[i] || 0)
        return false
    }
    readonly property bool anyChecked: Object.keys(checked).some(k => checked[k])

    Repeater {
        model: hc.h ? hc.h.disks : []
        Btn {
            id: dk
            required property var modelData
            readonly property real used: 1 - modelData.free / Math.max(1, modelData.total)
            readonly property bool bad: !!modelData.health && modelData.health !== "Healthy"
            readonly property bool low: modelData.free / Math.max(1, modelData.total) < 0.1
            width: parent.width
            height: 38
            cursor: Qt.ArrowCursor
            tip: Watch.fmtSize(modelData.total - modelData.free) + " utilisés sur " + Watch.fmtSize(modelData.total)
                + (modelData.media ? " · " + modelData.media : "") + (modelData.health ? " · état : " + (modelData.health === "Healthy" ? "sain" : modelData.health) : "")
            Ms {
                y: 2
                name: dk.modelData.media === "HDD" ? "album" : "hard_drive"
                size: 17
                color: dk.bad || dk.low ? Theme.bad : Theme.inkVariant
            }
            Txt {
                x: 24
                y: 2
                width: parent.width - 24 - free.width - 6
                text: dk.modelData.mount + " " + dk.modelData.name
                px: 12
                weight: Font.Medium
                elide: Text.ElideRight
            }
            Txt {
                id: free
                anchors.right: parent.right
                y: 3
                text: Watch.fmtSize(dk.modelData.free) + " libres" + (dk.bad ? " · ⚠ " + (dk.modelData.health === "Warning" ? "à surveiller" : "en panne") : "")
                px: 10.5
                color: dk.bad ? Theme.bad : Theme.inkVariant
            }
            Rectangle {
                x: 24
                y: 26
                width: parent.width - 24
                height: 6
                radius: 3
                color: Theme.surfaceHighest
                Rectangle {
                    width: parent.width * dk.used
                    height: parent.height
                    radius: 3
                    color: dk.low ? Theme.bad : Theme.primary
                }
            }
        }
    }
    Txt {
        visible: !hc.h
        text: "Chargement…"
        px: 11.5
        color: Theme.inkVariant
    }
    // pilote NVIDIA
    Btn {
        id: drv
        readonly property var d: hc.h ? hc.h.driver : null
        readonly property bool newer: !!d && !!d.latest && hc.verGt(d.latest, d.installed)
        visible: !!d && !!d.installed
        width: parent.width
        height: 32
        radius: 10
        color: newer ? Theme.tertiaryContainer : Theme.surfaceHigh
        active: newer
        cursor: newer ? Qt.PointingHandCursor : Qt.ArrowCursor
        tip: d ? d.gpu + (newer ? " · installé : " + d.installed + " · clic : page des pilotes" : "") : ""
        onClicked: Api.invoke("open_url", { url: "https://www.nvidia.com/fr-fr/drivers/" })
        Row {
            x: 10
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter
            Ms {
                name: drv.newer ? "system_update" : "verified"
                size: 17
                color: drv.newer ? Theme.inkTertiaryContainer : Theme.ok
            }
            Txt {
                text: !drv.d ? "" : drv.newer ? "Nouveau pilote NVIDIA " + drv.d.latest : "Pilote NVIDIA à jour (" + drv.d.installed + ")"
                px: 11.5
                color: drv.newer ? Theme.inkTertiaryContainer : Theme.ink
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    // nettoyage
    Repeater {
        model: hc.h ? hc.h.clean : []
        Btn {
            id: ci
            required property var modelData
            readonly property bool on: !!hc.checked[modelData.id]
            width: parent.width
            height: 26
            radius: 8
            active: modelData.bytes > 0
            opacity: active ? 1 : 0.5
            color: hovered ? Theme.surfaceHigh : "transparent"
            onClicked: {
                const c = Object.assign({}, hc.checked)
                c[modelData.id] = !c[modelData.id]
                hc.checked = c
            }
            Ms {
                x: 2
                anchors.verticalCenter: parent.verticalCenter
                name: ci.on ? "check_box" : "check_box_outline_blank"
                size: 18
                color: ci.on ? Theme.primary : Theme.inkVariant
            }
            Txt {
                x: 26
                width: parent.width - 26 - sz.width - 6
                anchors.verticalCenter: parent.verticalCenter
                text: ci.modelData.label
                px: 11.5
                elide: Text.ElideRight
            }
            Txt {
                id: sz
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: Watch.fmtSize(ci.modelData.bytes)
                px: 10.5
                tnum: true
                color: Theme.inkVariant
            }
        }
    }
    TextBtn {
        visible: !!hc.h
        primary: true
        icon: "cleaning_services"
        text: hc.cleaning ? "Nettoyage…" : "Nettoyer"
        busy: hc.cleaning
        disabled: !hc.anyChecked || hc.cleaning
        onClicked: {
            hc.cleaning = true
            const ids = Object.keys(hc.checked).filter(k => hc.checked[k])
            Api.invoke("health_clean", { ids: ids }).then(freed => {
                hc.cleaning = false
                Watch.osd("cleaning_services", null, Watch.fmtSize(freed) + " libérés")
                hc.refresh(true)
            }, () => { hc.cleaning = false })
        }
    }
}
