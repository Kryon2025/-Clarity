import QtQuick
import QtQuick.Window
import QtQuick.Effects
import "components"
import "glass"
import "components/Constants.js" as C

// 速启面板（CW2 TrayPanel 形态）：375×475、无边框、置顶、失焦自动隐藏。
// 对外：showAt(px, py) / hide()（Python 侧接托盘与快捷键）
Window {
    id: panel
    title: qsTr("深清 · 速启")
    width: 375
    height: 475
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
    color: "transparent"
    visible: false

    onActiveChanged: {
        if (!active && Qt.application.active !== true)
            hide()
    }

    function showAt(px, py) {
        var margin = 8
        var screenW = Screen.width
        var screenH = Screen.height
        var targetX = px - panel.width / 2
        var targetY = py + 30
        if (targetY + panel.height > screenH - margin)
            targetY = py - panel.height - 30
        if (targetY < margin)
            targetY = margin
        if (targetX < margin)
            targetX = margin
        if (targetX + panel.width > screenW - margin)
            targetX = screenW - panel.width - margin
        panel.x = Math.round(targetX)
        panel.y = Math.round(targetY)
        panel.visible = true
        panel.raise()
        panel.requestActivate()
    }

    function openPanel() {
        showAt(Screen.width / 2, Screen.height / 2)
    }

    function hide() {
        panel.visible = false
    }

    function closePanel() {
        hide()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: panel.hide()
    }

    // ---------- 背景：海玻璃底 + 光斑 + 细噪点 ----------
    Item {
        id: bgLayer
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            radius: 18
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#0B2A38" }
                GradientStop { position: 0.55; color: "#08222E" }
                GradientStop { position: 1.0; color: "#0A2E3B" }
            }
        }

        Rectangle {
            id: pb1
            visible: false
            width: 320
            height: 320
            radius: 160
            x: -80
            y: -120
            color: C.waterBlue
        }
        MultiEffect {
            source: pb1
            width: pb1.width
            height: pb1.height
            blurEnabled: true
            blur: 1.0
            blurMax: 96
            opacity: 0.22
        }

        Rectangle {
            id: pb2
            visible: false
            width: 280
            height: 280
            radius: 140
            x: 170
            y: 220
            color: C.waterTeal
        }
        MultiEffect {
            source: pb2
            width: pb2.width
            height: pb2.height
            blurEnabled: true
            blur: 1.0
            blurMax: 96
            opacity: 0.16
        }

        Image {
            anchors.fill: parent
            source: "assets/img/noise.png"
            fillMode: Image.Tile
            smooth: false
            opacity: 0.10
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: "transparent"
        border.width: 1
        border.color: "#4DFFFFFF"
    }

    // ---------- 内容 ----------
    Item {
        id: content
        anchors.fill: parent
        anchors.margins: 14
        property Item glassSource: bgLayer

        // ---- 顶部 header ----
        Item {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 44

            Item {
                id: appIcon
                width: 32
                height: 32
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    visible: appIconImage.status !== Image.Ready
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#7FE7DA" }
                        GradientStop { position: 0.55; color: "#2ED3C6" }
                        GradientStop { position: 1.0; color: "#1F6FD0" }
                    }
                    Glyph {
                        anchors.centerIn: parent
                        kind: "drop"
                        size: 18
                        color: "#04222B"
                    }
                }

                Image {
                    id: appIconImage
                    anchors.fill: parent
                    source: "../assets/img/app_icon.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    visible: status === Image.Ready
                }
            }

            Text {
                anchors.left: appIcon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "深清"
                color: "#EFF9FF"
                font.pixelSize: 16
                font.weight: Font.DemiBold
                font.family: C.numFont
                font.letterSpacing: 1
            }

            GlassButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("打开主界面")
                tone: "ghost"
                fontSize: 11
                padH: 12
                minHeight: 28
                onClicked: {
                    if (typeof App.showMainWindow === "function") App.showMainWindow()
                    panel.hide()
                }
            }
        }

        // ---- 区块一：专注模式 ----
        Text {
            id: modeTitle
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.topMargin: 14
            text: qsTr("专注模式")
            color: "#CFE6EC"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.family: C.numFont
            font.letterSpacing: 1
        }

        Row {
            id: modeRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: modeTitle.bottom
            anchors.topMargin: 10
            spacing: 10

            Repeater {
                model: [
                    { level: "light", label: qsTr("轻度"), glyph: "moon", desc: qsTr("只结束进程") },
                    { level: "medium", label: qsTr("中度"), glyph: "wave", desc: qsTr("进程 + 网站") },
                    { level: "heavy", label: qsTr("重度"), glyph: "lock", desc: qsTr("全屏锁机") }
                ]

                delegate: Item {
                    id: modeCell
                    width: (modeRow.width - 20) / 3
                    height: 92
                    property bool held: false
                    property point pressPoint: Qt.point(0.5, 0.5)

                    function trackPointer(mx, my) {
                        modeCell.pressPoint = Qt.point(
                            Math.max(0, Math.min(1, mx / modeCell.width)),
                            Math.max(0, Math.min(1, my / Math.max(1, 64))))
                    }

                    // 玻璃圆角图标卡
                    Item {
                        id: modeTile
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 66

                        LiquidGlass {
                            anchors.fill: parent
                            sourceItem: bgLayer
                            radius: 16
                            depth: 1.2
                            frost: 0.02
                            aberration: 0.58
                            highlight: 1.45
                            whiten: 0.05
                            tintAlpha: 0.14
                            tint: C.glassTint
                            sheen: 0.5
                            pointer: modeCell.pressPoint
                            pull: modeCell.held ? 1 : 0
                            Behavior on pull {
                                NumberAnimation {
                                    duration: modeCell.held ? 90 : 440
                                    easing.type: modeCell.held ? Easing.OutCubic : Easing.OutElastic
                                    easing.amplitude: 0.9
                                    easing.period: 0.5
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: "transparent"
                            border.width: 1
                            border.color: "#45FFFFFF"
                        }

                        Glyph {
                            anchors.centerIn: parent
                            kind: modelData.glyph
                            size: 24
                            color: "#EAF8FB"
                        }
                    }

                    Text {
                        anchors.top: modeTile.bottom
                        anchors.topMargin: 6
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label
                        color: "#E6F6FA"
                        font.pixelSize: 12
                        font.family: C.numFont
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: (mouse) => {
                            modeCell.held = true
                            modeCell.trackPointer(mouse.x, mouse.y)
                        }
                        onReleased: modeCell.held = false
                        onCanceled: modeCell.held = false
                        onPositionChanged: (mouse) => {
                            if (pressed) modeCell.trackPointer(mouse.x, mouse.y)
                        }
                        onClicked: {
                            if (typeof App.startLevel === "function")
                                App.startLevel(String(modelData.level))
                            panel.hide()
                        }
                    }
                }
            }
        }

        // ---- 区块二：空间 ----
        Text {
            id: spaceTitle
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: modeRow.bottom
            anchors.topMargin: 14
            text: qsTr("空间")
            color: "#CFE6EC"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.family: C.numFont
            font.letterSpacing: 1
        }

        ListView {
            id: spaceList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: spaceTitle.bottom
            anchors.topMargin: 10
            height: 76
            orientation: ListView.Horizontal
            spacing: 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: App.spaces || []

            delegate: Item {
                id: spaceCell
                width: 108
                height: 70

                LiquidGlass {
                    anchors.fill: parent
                    sourceItem: bgLayer
                    radius: 16
                    depth: 0.95
                    frost: 0.02
                    aberration: 0.45
                    highlight: 1.05
                    whiten: 0.04
                    tintAlpha: 0.16
                    tint: C.glassTint
                    sheen: 0.45
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    color: "transparent"
                    border.width: 1
                    border.color: "#3DFFFFFF"
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Text {
                        text: modelData.name !== undefined ? String(modelData.name) : ""
                        color: "#EFF9FF"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        font.family: C.numFont
                        width: 84
                        elide: Text.ElideRight
                    }
                    Text {
                        text: qsTr("%1 分钟").arg(modelData.minutes !== undefined ? String(modelData.minutes) : "0")
                        color: "#9FC3CE"
                        font.pixelSize: 11
                        font.family: C.numFont
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        App.startSpace(String(modelData.id))
                        panel.hide()
                    }
                }
            }
        }

        // ---- 区块三：今日 ----
        Text {
            id: todayText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: spaceList.bottom
            anchors.topMargin: 12
            text: qsTr("今日专注 %1 分钟 · 连续 %2 天")
                  .arg(Math.round(Number(App.todayMinutes) || 0))
                  .arg(Math.round(Number(App.streakDays) || 0))
            color: "#8FB3C0"
            font.pixelSize: 12
            font.family: C.numFont
        }

        // ---- 中部留白：一句提示 ----
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: todayText.bottom
            anchors.topMargin: 26
            spacing: 8

            Glyph {
                anchors.horizontalCenter: parent.horizontalCenter
                kind: "ripple"
                size: 26
                color: "#3A6A78"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("把注意力收回来")
                color: "#5E818E"
                font.pixelSize: 11
                font.family: C.numFont
                font.letterSpacing: 2
            }
        }

        // ---- 底部工具条 ----
        Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 40

            Rectangle {
                anchors.fill: parent
                anchors.margins: -6
                radius: 14
                color: "#0AFFFFFF"
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                MiniGlassButton {
                    size: 32
                    glyph: "gear"
                    onClicked: {
                        if (typeof App.showMainWindow === "function") App.showMainWindow()
                        if (typeof App.gotoSettings === "function") App.gotoSettings()
                        panel.hide()
                    }
                }

                MiniGlassButton {
                    size: 32
                    glyph: "refresh"
                    onClicked: if (typeof App.refreshStats === "function") App.refreshStats()
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter

                MiniGlassButton {
                    size: 32
                    glyph: "close"
                    onClicked: {
                        if (typeof App.quitApp === "function") App.quitApp()
                        else panel.hide()
                    }
                }
            }
        }
    }
}