import QtQuick

// Accueil : horloge | calendrier + jauges | lecteur
Item {
    id: home
    readonly property bool shown: visible && win.mode === "open"
    readonly property int gap: 12

    // ------------------------------------------------------------ horloge
    Rectangle {
        id: clock
        width: 160
        height: gauges.y - home.gap
        radius: 22
        color: Theme.primaryContainer
        Column {
            anchors.centerIn: parent
            spacing: -8
            Text { text: Qt.formatTime(win.now, "hh"); font.family: Theme.font; font.pixelSize: 64; font.weight: Font.Bold; color: Theme.inkPrimaryContainer; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: Qt.formatTime(win.now, "mm"); font.family: Theme.font; font.pixelSize: 64; font.weight: Font.Bold; color: Theme.primary; anchors.horizontalCenter: parent.horizontalCenter }
            Item { width: 1; height: 16 }
            Text { text: win.now.toLocaleDateString(Theme.locale, "dddd d MMMM"); font.family: Theme.font; font.pixelSize: 12; color: Theme.inkPrimaryContainer; anchors.horizontalCenter: parent.horizontalCenter }
        }
    }

    // -------------------------------------------------------------- lecteur
    Rectangle {
        id: player
        anchors.right: parent.right
        width: 200
        height: parent.height
        radius: 22
        color: Theme.surfaceLow
        clip: true
        VizBars { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 40; opacity: 0.45 }
        Column {
            anchors.centerIn: parent
            width: parent.width - 28
            spacing: 6
            Item {
                width: 128
                height: 128
                anchors.horizontalCenter: parent.horizontalCenter
                RoundArt {
                    id: disc
                    anchors.fill: parent
                    // ne tourne que si l'accueil se voit
                    RotationAnimator on rotation {
                        from: 0; to: 360; duration: 14000; loops: Animation.Infinite
                        running: media.playing && media.hasArt && home.shown
                    }
                }
            }
            Text { text: win.hasMedia ? media.title || "Sans titre" : "Rien en lecture"; width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium; color: Theme.ink }
            Text { text: media.artist; width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12; color: Theme.inkVariant }
            Controls { anchors.horizontalCenter: parent.horizontalCenter }
        }
    }

    // --------------------------------------------------------------- jauges
    Rectangle {
        id: gauges
        width: player.x - home.gap
        height: 84
        anchors.bottom: parent.bottom
        radius: 22
        color: Theme.surfaceLow
        Row {
            anchors.centerIn: parent
            spacing: 24
            Gauge { animate: home.shown; label: "CPU"; value: sys.cpu / 100; text: Math.round(sys.cpu) + " %" }
            Gauge { animate: home.shown; label: "RAM"; value: sys.memTotal ? sys.memUsed / sys.memTotal : 0; text: (sys.memUsed / 1073741824).toFixed(1) + " / " + (sys.memTotal / 1073741824).toFixed(1) + " Go" }
            Gauge { animate: home.shown; label: "C:"; value: sys.diskTotal ? sys.diskUsed / sys.diskTotal : 0; text: Math.round(sys.diskUsed / 1073741824) + " / " + Math.round(sys.diskTotal / 1073741824) + " Go" }
        }
    }

    // ---------------------------------------------------------- calendrier
    Rectangle {
        x: clock.width + home.gap
        width: player.x - x - home.gap
        height: gauges.y - home.gap
        radius: 22
        color: Theme.surfaceLow
        Column {
            anchors.centerIn: parent
            spacing: 6
            Text { text: win.now.toLocaleDateString(Theme.locale, "MMMM yyyy"); font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium; color: Theme.ink; anchors.horizontalCenter: parent.horizontalCenter }
            Grid {
                id: cal
                columns: 7
                // premier lundi affiche : debut de la semaine du 1er du mois
                readonly property date first: {
                    const d = new Date(win.now.getFullYear(), win.now.getMonth(), 1)
                    d.setDate(1 - (d.getDay() + 6) % 7)
                    return d
                }
                Repeater {
                    model: ["L", "M", "M", "J", "V", "S", "D"]
                    Text { required property string modelData; width: 44; height: 26; horizontalAlignment: Text.AlignHCenter; text: modelData; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; color: Theme.inkVariant }
                }
                Repeater {
                    model: 42
                    Item {
                        required property int index
                        readonly property date day: new Date(cal.first.getFullYear(), cal.first.getMonth(), cal.first.getDate() + index)
                        readonly property bool today: day.toDateString() === win.now.toDateString()
                        width: 44
                        height: 34
                        Rectangle { anchors.centerIn: parent; width: 28; height: 28; radius: 14; color: Theme.primary; visible: today }
                        Text {
                            anchors.centerIn: parent
                            text: day.getDate()
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: today ? Theme.inkPrimary : day.getMonth() !== win.now.getMonth() ? Theme.outlineVariant : Theme.ink
                        }
                    }
                }
            }
        }
    }
}
