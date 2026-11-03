import QtQuick
import QtQuick.Effects
import "../theme"
import "Constants.js" as C

// 页面底：纯色 / 浅色主题只画极简线性渐变；液态玻璃主题额外加光斑 + 噪点
Item {
    id: root
    property real blobStrength: 1.0
    property real noiseOpacity: 0.13

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: AppTheme.bgMid }
            GradientStop { position: 0.55; color: AppTheme.bgTop }
            GradientStop { position: 1.0; color: AppTheme.bgBottom }
        }
    }

    // ---------- 以下仅液态玻璃主题 ----------
    Item {
        anchors.fill: parent
        visible: AppTheme.glass

        Rectangle {
            id: blobBlue
            visible: false
            width: Math.max(320, root.width * 0.52)
            height: width
            radius: width / 2
            x: -width * 0.3
            y: -height * 0.46
            color: C.waterBlue
            opacity: 0.85
        }
        MultiEffect {
            source: blobBlue
            anchors.fill: blobBlue
            blurEnabled: true
            blur: 1.0
            blurMax: 96
            opacity: 0.34 * root.blobStrength
        }

        Rectangle {
            id: blobCyan
            visible: false
            width: Math.max(320, root.width * 0.46)
            height: width
            radius: width / 2
            x: root.width * 0.62
            y: root.height * 0.44
            color: C.waterTeal
            opacity: 0.85
        }
        MultiEffect {
            source: blobCyan
            anchors.fill: blobCyan
            blurEnabled: true
            blur: 1.0
            blurMax: 96
            opacity: 0.22 * root.blobStrength
        }

        Rectangle {
            id: blobViolet
            visible: false
            width: Math.max(320, root.width * 0.42)
            height: width
            radius: width / 2
            x: root.width * -0.04
            y: root.height * 0.66
            color: C.waterSand
            opacity: 0.75
        }
        MultiEffect {
            source: blobViolet
            anchors.fill: blobViolet
            blurEnabled: true
            blur: 1.0
            blurMax: 96
            opacity: 0.16 * root.blobStrength
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#33040F18" }
                GradientStop { position: 0.34; color: "#00000000" }
                GradientStop { position: 0.76; color: "#00000000" }
                GradientStop { position: 1.0; color: "#3D041018" }
            }
        }

        Image {
            anchors.fill: parent
            source: "../assets/img/noise.png"
            fillMode: Image.Tile
            smooth: false
            opacity: root.noiseOpacity
        }
    }
}
