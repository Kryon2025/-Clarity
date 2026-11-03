import QtQuick

// 全屏遮罩组件：宿主按 anchor / width / height 摆放。
// 根元素必须是 Item；建议半透明、无边框，和深色遮罩协调。
Item {
    id: widget

    Rectangle {
        anchors.fill: parent
        color: "#14FFFFFF"
        radius: 16
        border.width: 1
        border.color: "#33FFFFFF"
    }

    Column {
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#F2FAFF"
            font.pixelSize: 22
            font.bold: true
            text: "专注中"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#9FD8EC"
            font.pixelSize: 12
            text: "改成你自己的组件"
        }
    }
}
