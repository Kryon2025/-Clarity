import QtQuick

// 全屏遮罩上的时钟组件（CW2 风格：无边框、半透明白字）
Item {
    id: clock

    Column {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            id: timeText
            color: "#F2FAFF"
            font.pixelSize: 46
            font.bold: true
            font.letterSpacing: 1
            text: Qt.formatTime(new Date(), "HH:mm")
        }
        Text {
            color: "#9FD8EC"
            font.pixelSize: 13
            text: Qt.formatDate(new Date(), "yyyy-MM-dd dddd")
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: timeText.text = Qt.formatTime(new Date(), "HH:mm")
    }
}
