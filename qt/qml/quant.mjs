// Couleur source du theme (comme sourceColorFromImage de
// material-color-utilities), hors du thread de l'interface : la
// quantification de quelques dizaines de milliers de pixels prend du temps.
import { QuantizerCelebi, Score } from "mcu.mjs"

WorkerScript.onMessage = function (m) {
    let source = null
    if (m.pixels && m.pixels.length) {
        const ranked = Score.score(QuantizerCelebi.quantize(m.pixels, 128))
        source = ranked[0]
    }
    WorkerScript.sendMessage({ id: m.id, source: source })
}
