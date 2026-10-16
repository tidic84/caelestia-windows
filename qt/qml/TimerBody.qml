import QtQuick
import QtQuick.Shapes

// Feuille du minuteur : cadran, prereglages, commandes, Pomodoro
Item {
    id: tb
    Row {
        anchors.centerIn: parent
        spacing: 28

        // cadran (svg de 120 : cercle de rayon 54, trait de 8)
        Item {
            id: face
            width: 170
            height: 170
            anchors.verticalCenter: parent.verticalCenter
            readonly property real k: width / 120
            readonly property real frac: Ilot.timerLeft / Math.max(1, Ilot.tmr.total)
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Theme.surfaceHighest
                    strokeWidth: 8 * face.k
                    fillColor: "transparent"
                    PathAngleArc { centerX: 85; centerY: 85; radiusX: 54 * face.k; radiusY: 54 * face.k; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeColor: Theme.primary
                    strokeWidth: face.frac > 0.001 ? 8 * face.k : 0
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 85; centerY: 85; radiusX: 54 * face.k; radiusY: 54 * face.k; startAngle: -90; sweepAngle: 360 * face.frac }
                }
            }
            Column {
                anchors.centerIn: parent
                spacing: 2
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Ilot.fmtMs(Ilot.timerLeft)
                    px: 32
                    weight: Font.Medium
                    tnum: true
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property var t: Ilot.tmr
                    text: t.pomo === "focus" ? "Concentration" : t.pomo === "break" ? "Pause" : t.running ? "En cours" : Ilot.timerLeft < t.total ? "En pause" : ""
                    px: 12
                    color: Theme.inkVariant
                }
            }
        }

        Column {
            spacing: 14
            anchors.verticalCenter: parent.verticalCenter
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                spacing: 6
                Repeater {
                    model: [[1, "1 min"], [5, "5 min"], [10, "10 min"], [15, "15 min"], [30, "30 min"], [60, "1 h"]]
                    Btn {
                        required property var modelData
                        width: 64
                        height: 32
                        radius: 16
                        color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                        onClicked: Ilot.timerSet(modelData[0] * 60000)
                        Txt {
                            anchors.centerIn: parent
                            text: parent.modelData[1]
                            px: 12.5
                        }
                    }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                IconBtn {
                    icon: "remove"
                    tip: "−1 min"
                    onClicked: Ilot.adjustTimer(-60000)
                }
                IconBtn {
                    filled: true
                    width: 56
                    icon: Ilot.tmr.running ? "pause" : "play_arrow"
                    onClicked: Ilot.timerToggle()
                }
                IconBtn {
                    icon: "add"
                    tip: "+1 min"
                    onClicked: Ilot.adjustTimer(60000)
                }
                IconBtn {
                    icon: "replay"
                    tip: "Réinitialiser"
                    onClicked: Ilot.timerReset()
                }
            }
            TextBtn {
                anchors.horizontalCenter: parent.horizontalCenter
                icon: "nest_eco_leaf"
                text: "Pomodoro 25 / 5"
                onClicked: Ilot.startPomodoro()
            }
        }
    }
}
