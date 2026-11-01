import QtQuick
import QtQuick.Effects
import "Constants.js" as C

// 页面底：深色渐变 + 两团彩色光斑（MultiEffect 模糊）+ 细噪点
Item {
    id: root
    property real blobStrength: 1.0
    property real noiseOpacity: 0.13

    // 底色
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: C.bgMid }
            GradientStop { position: 0.55; color: C.bgTop }
            GradientStop { position: 1.0; color: C.bgBottom }
        }
    }

    // 彩色光斑
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

    // 上下压暗，拉开层次
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#33040F18" }
            GradientStop { position: 0.34; color: "#00000000" }
            GradientStop { position: 0.76; color: "#00000000" }
            GradientStop { position: 1.0; color: "#3D041018" }
        }
    }

    // 细噪点
    Image {
        anchors.fill: parent
        source: "../assets/img/noise.png"
        fillMode: Image.Tile
        smooth: false
        opacity: root.noiseOpacity
    }
}