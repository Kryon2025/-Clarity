import QtQuick
import "../theme"
import "../glass"
import "Constants.js" as C

// 「+ 新增空间」虚线玻璃卡
Item {
    id: root
    property bool interactive: true
    property Item glassSource: null
    signal clicked()

    implicitHeight: 88

    implicitWidth: 400

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.interactive) root.clicked()
    }

    Item {
        id: lift
        anchors.fill: parent
        scale: pointer.pressed ? 0.98 : 1.0
        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack }
        }

        Rectangle {
            anchors.fill: parent
            radius: C.radiusCard
            color: pointer.containsMouse ? "#0FFFFFFF" : "#08FFFFFF"
            Behavior on color {
                ColorAnimation { duration: 160 }
            }
        }

        Canvas {
            id: dashBorder
            anchors.fill: parent
            property color strokeColor: "#3DFFFFFF"
            onStrokeColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = dashBorder.strokeColor
                ctx.lineWidth = 1.5
                ctx.setLineDash([6, 6])
                var x = 1, y = 1, w = width - 2, h = height - 2, r = C.radiusCard - 1
                ctx.beginPath()
                ctx.moveTo(x + r, y)
                ctx.lineTo(x + w - r, y)
                ctx.arcTo(x + w, y, x + w, y + r, r)
                ctx.lineTo(x + w, y + h - r)
                ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
                ctx.lineTo(x + r, y + h)
                ctx.arcTo(x, y + h, x, y + h - r, r)
                ctx.lineTo(x, y + r)
                ctx.arcTo(x, y, x + r, y, r)
                ctx.closePath()
                ctx.stroke()
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 10

            Item {
                width: 26
                height: 26
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.fill: parent
                    radius: 13
                    color: "transparent"
                    border.width: 1.4
                    border.color: "#5CFFFFFF"
                }
                Glyph {
                    anchors.centerIn: parent
                    kind: "plus"
                    size: 14
                    color: "#B9C4D8"
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("新增空间")
                color: "#A7B4CC"
                font.pixelSize: AppTheme.fs(15)
                font.family: AppTheme.fontFamily
            }
        }
    }
}