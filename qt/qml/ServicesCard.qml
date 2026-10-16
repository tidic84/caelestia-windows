import QtQuick

// Etat des services (src/status.rs) : page d'etat officielle + temps de
// reponse depuis ce PC. Distingue « panne chez eux » et « souci de ton cote ».
PcCard {
    id: sv
    title: "État des services"
    tool: "refresh"
    toolTip: "Tester maintenant"
    property bool busy: false
    toolBusy: busy
    onToolClicked: {
        busy = true
        Api.invoke("services_get", { fresh: true }).then(l => {
            Watch.applyServices(l)
            sv.busy = false
        }, () => { sv.busy = false })
    }
    readonly property var list: Watch.services
    readonly property var down: list.filter(x => x.ms === null || x.ms === undefined)

    Flow {
        width: parent.width
        spacing: 4
        Repeater {
            model: sv.list
            Btn {
                id: b
                required property var modelData
                readonly property string lv: Watch.svLevel(modelData)
                width: (parent.width - 4) / 2
                height: 30
                radius: 10
                color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                tip: [
                    modelData.official ? "Officiel : " + (modelData.official === "none" ? "tout fonctionne" : Watch.svFr[modelData.official] || modelData.official) + (modelData.desc ? " (" + modelData.desc + ")" : "") : "Pas de page d’état officielle",
                    modelData.ms === null ? "Injoignable depuis ce PC" : "Répond en " + modelData.ms + " ms depuis ce PC",
                    "Clic : page d’état"
                ].join("\n")
                onClicked: Api.invoke("open_url", { url: modelData.page })
                Rectangle {
                    x: 9
                    width: 8
                    height: 8
                    radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: b.lv === "ok" ? Theme.ok : b.lv === "warn" ? Theme.warn : Theme.bad
                }
                Txt {
                    x: 23
                    width: parent.width - 23 - ms.width - 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: b.modelData.name
                    px: 11.5
                    elide: Text.ElideRight
                }
                Txt {
                    id: ms
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: b.modelData.ms === null ? "HS" : b.modelData.ms + " ms"
                    px: 10
                    tnum: true
                    color: Theme.inkVariant
                }
            }
        }
    }
    Txt {
        visible: !sv.list.length
        text: "Test en cours…"
        px: 11.5
        color: Theme.inkVariant
    }
    // tout injoignable = la connexion ; un seul HS alors que l'officiel dit OK = souci local
    Txt {
        width: parent.width
        wrapMode: Text.Wrap
        px: 11
        color: Theme.bad
        visible: text !== ""
        text: sv.list.length && sv.down.length === sv.list.length ? "Aucun service ne répond : ta connexion Internet semble coupée."
            : sv.down.some(x => x.official === "none") ? sv.down.filter(x => x.official === "none").map(x => x.name).join(", ")
                + " : tout va bien chez eux, le blocage vient sûrement de ta connexion (essaie WARP)." : ""
    }
}
