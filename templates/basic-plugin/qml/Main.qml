import QtQuick

// 导航入口页面：宿主用 Loader 载入 qmlPath，把页面放进内容区。
// 根元素请用 Item；尺寸由宿主内容区决定时可用 anchors.fill: parent。
Item {
    id: page

    Rectangle {
        anchors.fill: parent
        color: "#0B1220"
        radius: 18

        Column {
            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#F2F6FF"
                font.pixelSize: 24
                font.bold: true
                text: "基础插件模板"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#9FB4D8"
                font.pixelSize: 14
                text: "把 qml/Main.qml 换成你自己的页面"
            }
        }
    }
}
