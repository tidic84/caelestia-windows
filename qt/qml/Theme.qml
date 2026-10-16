pragma Singleton
import QtQuick
import "mcu.mjs" as Mcu

// Palette Material You (style.css : :root et applyTheme d'app.js), polices
// et courbes d'animation. Les couleurs « on-* » s'appellent ink* : un nom en
// on + majuscule serait pris pour un gestionnaire de signal.
Item {
    id: t

    // palette par defaut, remplacee des que le fond d'ecran est lu
    property color primary: "#cfbdfe"
    property color inkPrimary: "#36265d"
    property color primaryContainer: "#4d3d75"
    property color inkPrimaryContainer: "#e9ddff"
    property color secondary: "#cbc2db"
    property color secondaryContainer: "#4a4458"
    property color inkSecondaryContainer: "#e8def8"
    property color tertiary: "#efb8c8"
    property color tertiaryContainer: "#633b48"
    property color inkTertiaryContainer: "#ffd8e4"
    property color surface: "#141218"
    property color surfaceLow: "#1d1b20"
    property color surfaceC: "#211f26"
    property color surfaceHigh: "#2b2930"
    property color surfaceHighest: "#36343b"
    property color ink: "#e6e0e9"
    property color inkVariant: "#cac4d0"
    property color outline: "#938f99"
    property color outlineVariant: "#49454f"
    property color error: "#ffb4ab"
    property color inkError: "#690005"

    // les couleurs s'interpolent quand la palette change (.9s ease)
    Behavior on primary { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on inkPrimary { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on primaryContainer { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on inkPrimaryContainer { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on secondary { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on secondaryContainer { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on inkSecondaryContainer { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on tertiary { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on tertiaryContainer { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on inkTertiaryContainer { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on surface { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on surfaceLow { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on surfaceC { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on surfaceHigh { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on surfaceHighest { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on ink { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on inkVariant { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on outline { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on outlineVariant { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on error { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }
    Behavior on inkError { ColorAnimation { duration: 900; easing.type: Easing.OutQuad } }

    property bool light: false
    // opacite du fond de l'ilot et de la barre (Reglages > Fond de l'ilot)
    property real islandAlpha: 1
    readonly property color islandBg: alpha(surface, islandAlpha)

    readonly property string font: "Rubik"
    readonly property string icons: "Material Symbols Rounded"
    readonly property var locale: Qt.locale("fr_FR")

    // courbes de style.css (--spring, --emph, --std)
    readonly property var spring: [0.34, 1.36, 0.5, 1, 1, 1]
    readonly property var emph: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var std: [0.2, 0, 0, 1, 1, 1]

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, c.a * a)
    }
    // color-mix(in srgb, a p, b)
    function mix(a, b, p) {
        return Qt.rgba(a.r * p + b.r * (1 - p), a.g * p + b.g * (1 - p), a.b * p + b.b * (1 - p), a.a * p + b.a * (1 - p))
    }
    // couleur au survol d'un bouton plein : color-mix(primary 88 %, blanc)
    function lift(c) {
        return mix(c, "#ffffff", 0.88)
    }

    // ------------------------------------------------------- Material You
    readonly property var variants: [
        { id: "tonalspot", label: "Tonal Spot", scheme: "SchemeTonalSpot" },
        { id: "vibrant", label: "Vibrant", scheme: "SchemeVibrant" },
        { id: "expressive", label: "Expressive", scheme: "SchemeExpressive" },
        { id: "fidelity", label: "Fidélité", scheme: "SchemeFidelity" },
        { id: "content", label: "Contenu", scheme: "SchemeContent" },
        { id: "rainbow", label: "Arc-en-ciel", scheme: "SchemeRainbow" },
        { id: "fruitsalad", label: "Salade de fruits", scheme: "SchemeFruitSalad" },
        { id: "neutral", label: "Neutre", scheme: "SchemeNeutral" },
        { id: "monochrome", label: "Monochrome", scheme: "SchemeMonochrome" }
    ]

    readonly property var roles: ({
        primary: "primary", inkPrimary: "onPrimary",
        primaryContainer: "primaryContainer", inkPrimaryContainer: "onPrimaryContainer",
        secondary: "secondary", secondaryContainer: "secondaryContainer", inkSecondaryContainer: "onSecondaryContainer",
        tertiary: "tertiary", tertiaryContainer: "tertiaryContainer", inkTertiaryContainer: "onTertiaryContainer",
        surface: "surface", surfaceLow: "surfaceContainerLow", surfaceC: "surfaceContainer",
        surfaceHigh: "surfaceContainerHigh", surfaceHighest: "surfaceContainerHighest",
        ink: "onSurface", inkVariant: "onSurfaceVariant",
        outline: "outline", outlineVariant: "outlineVariant", error: "error", inkError: "onError"
    })

    function scheme(source, variant, dark) {
        const v = variants.find(x => x.id === variant) || variants[0]
        return new Mcu[v.scheme](Mcu.Hct.fromInt(source), dark, 0)
    }

    // palette { role: "#rrggbb" } d'un schema
    function paletteOf(s) {
        const p = {}
        for (const k in roles)
            p[k] = Mcu.hexFromArgb(Mcu.MaterialDynamicColors[roles[k]].getArgb(s))
        return p
    }

    function applyPalette(p) {
        for (const k in p) {
            if (k in roles)
                t[k] = p[k]
        }
    }

    // apercu d'une variante (Reglages) : primaire, secondaire, tertiaire, fond
    function swatch(source, variant, dark) {
        const s = scheme(source, variant, dark)
        const c = r => Mcu.hexFromArgb(Mcu.MaterialDynamicColors[r].getArgb(s))
        return { dots: [c("primary"), c("secondary"), c("tertiary")], bg: c("surfaceContainerHigh") }
    }

    // 8 teintes pour l'accent de Windows, de la plus claire a la plus foncee
    function accentList(s) {
        const pal = s.primaryPalette
        const list = [90, 78, 62, 50, 40, 28, 14].map(x => pal.tone(x) & 0xffffff)
        list.push(s.tertiaryPalette.tone(55) & 0xffffff)
        return list
    }

    function hex(argb) {
        return Mcu.hexFromArgb(argb)
    }
}
