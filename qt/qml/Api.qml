pragma Singleton
import QtQuick
import IlotCore

// Commandes et evenements du coeur Rust, comme `invoke` et `listen` de
// Tauri : invoke(cmd, args) renvoie une promesse, listen(nom, fn) appelle fn
// avec la charge utile deja decodee.
QtObject {
    id: api

    property var pending: ({})
    property var listeners: ({})

    function invoke(cmd, args, label) {
        return new Promise((resolve, reject) => {
            const id = Backend.invoke(label || "island", cmd, JSON.stringify(args || {}))
            api.pending[id] = [resolve, reject]
        })
    }

    // pour le demarrage : reponse immediate (commandes rapides seulement)
    function call(cmd, args, label) {
        const r = JSON.parse(Backend.invokeSync(label || "island", cmd, JSON.stringify(args || {})))
        if ("err" in r)
            throw r.err
        return r.ok
    }

    function listen(name, fn) {
        if (!api.listeners[name])
            api.listeners[name] = []
        api.listeners[name].push(fn)
    }

    // pour une page dechargee (sinon fn appellerait un objet detruit)
    function unlisten(name, fn) {
        const fns = api.listeners[name]
        if (fns)
            api.listeners[name] = fns.filter(f => f !== fn)
    }

    property Connections conn: Connections {
        target: Backend
        function onReply(id, json) {
            const p = api.pending[id]
            if (!p)
                return
            delete api.pending[id]
            const r = JSON.parse(json)
            if ("err" in r)
                p[1](r.err)
            else
                p[0](r.ok)
        }
        function onEvent(name, json) {
            const fns = api.listeners[name]
            if (!fns)
                return
            const payload = JSON.parse(json)
            for (const fn of fns) {
                try {
                    fn(payload)
                } catch (e) {
                    console.warn("evenement", name, e, e.stack)
                }
            }
        }
    }
}
