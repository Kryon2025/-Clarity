import QtQuick
import "Constants.js" as C

// 应用图标：优先加载 exe 抓出来的 file:// png；失败降级为渐变方块 + 首字
Item {
    id: root
    property string iconUrl: ""
    property string appName: ""
    property real size: 44

    width: size
    height: size

    readonly property color tint: {
        var palette = [C.accent, C.cyan, C.violet, C.mint, C.rose]
        var text = String(root.appName || "")
        var h = 0
        for (var i = 0; i < text.length; i++)
            h = (h * 31 + text.charCodeAt(i)) % 977
        return palette[h % palette.length]
    }

    Rectangle {
        id: fallback
        anchors.fill: parent
        radius: root.size * 0.26
        visible: iconImage.status !== Image.Ready
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(root.tint, 1.18) }
            GradientStop { position: 1.0; color: Qt.darker(root.tint, 1.45) }
        }
        Text {
            anchors.centerIn: parent
            text: root.appName.length > 0 ? root.appName.charAt(0) : "?"
            color: "#F4F8FF"
            font.pixelSize: Math.round(root.size * 0.42)
            font.weight: Font.DemiBold
            font.family: C.numFont
        }
    }

    Image {
        id: iconImage
        anchors.fill: parent
        source: root.iconUrl
        visible: status === Image.Ready
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
        cache: true
        sourceSize.width: Math.round(root.size * 2)
        sourceSize.height: Math.round(root.size * 2)
    }
}
