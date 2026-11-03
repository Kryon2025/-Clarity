import QtQuick

// 专注提示牌：可自己改文案
Item {
    Rectangle {
        anchors.fill: parent
        radius: 16
        color: "#14FFFFFF"
        border.width: 1
        border.color: "#2EFFFFFF"

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 6

            Text {
                width: parent.width
                color: "#EAF8FF"
                font.pixelSize: 16
                wrapMode: Text.WordWrap
                text: "把这件事做完，再抬头。"
            }
            Text {
                width: parent.width
                color: "#8FC7DC"
                font.pixelSize: 12
                text: "—— 深清 · CW2 组件插件"
            }
        }
    }
}
