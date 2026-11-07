import QtQuick
import "theme"
import QtQuick.Window
import QtQuick.Effects
import "components"
import "glass"
import "components/Constants.js" as C

// 速启面板（CW2 TrayPanel 形态）：375×475、无边框、置顶、失焦自动隐藏。
// v0.4：三档文案来自 App.modes；空间只展示唯一的清空间，点击即按默认档开始。
// 对外：showAt(px, py) / hide()（Python 侧接托盘与快捷键）
Window {
    id: panel
    title: qsTr("深清 · 速启")
    width: 375
    height: 475
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
    color: "transparent"
    visible: false

    // 刚 showAt 后的一个短保护期：避免「点托盘 → 面板弹出 → 立刻被判失焦」而闪退
    property double guardUntil: 0

    // Python 侧触发入口：每次右键托盘把 requestTick +1 并带上坐标，面板就重新定位并显示
    property real requestX: 0
    property real requestY: 0
    property int requestTick: 0
    onRequestTickChanged: panel.toggleAt(requestX, requestY)

    // 主题跟随 Python 设置（typeof 兜底：单独加载面板时退回纯色）
    readonly property string resolvedThemeMode: (typeof App !== "undefined" && App.themeMode)
                                                ? String(App.themeMode) : "solid"
    onResolvedThemeModeChanged: AppTheme.mode = panel.resolvedThemeMode

    onActiveChanged: {
        if (active) return
        if (Qt.application.active === true) return
        if (Date.now() < guardUntil) return
        hide()
    }

    // 幂等：无论面板当前开/关，都重新定位到托盘图标附近并置顶激活（不会把自己关掉）
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

        panel.guardUntil = Date.now() + 280
        panel.x = Math.round(targetX)
        panel.y = Math.round(targetY)

        if (!panel.visible) {
            hideAnim.stop()
            panelRoot.opacity = 0
            panelShift.y = 10
            panel.visible = true
            if (panel.animationsEnabled) {
                showAnim.restart()
            } else {
                panelRoot.opacity = 1
                panelShift.y = 0
            }
        } else if (hideAnim.running) {
            hideAnim.stop()
            panelRoot.opacity = 1
            panelShift.y = 0
        }

        panel.raise()
        panel.requestActivate()
    }

    // 托盘右键每次都调这个：已打开时重新定位+置顶，而不是关掉
    function toggleAt(px, py) {
        showAt(px, py)
    }

    function openPanel() {
        showAt(Screen.width / 2, Screen.height / 2)
    }

    function hide() {
        if (!panel.visible) return
        if (!panel.animationsEnabled) {
            hideAnim.stop()
            showAnim.stop()
            panelRoot.opacity = 0
            panelShift.y = 10
            panel.visible = false
            return
        }
        if (hideAnim.running) return
        showAnim.stop()
        hideAnim.restart()
    }

    function closePanel() {
        hide()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: panel.hide()
    }

    // ---------- 显示 / 隐藏动画（v0.6） ----------
    // 独立 Window 由 Python 加载，拿不到 Main.pageTransitions，用本地开关（默认开启）
    property bool animationsEnabled: true

    ParallelAnimation {
        id: showAnim
        NumberAnimation {
            target: panelRoot
            property: "opacity"
            from: 0
            to: 1
            duration: panel.animationsEnabled ? 160 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: panelShift
            property: "y"
            from: 10
            to: 0
            duration: panel.animationsEnabled ? 160 : 0
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: hideAnim
        NumberAnimation {
            target: panelRoot
            property: "opacity"
            to: 0
            duration: panel.animationsEnabled ? 120 : 0
            easing.type: Easing.OutCubic
        }
        ScriptAction { script: panel.visible = false }
    }

    readonly property var modes: (typeof App !== "undefined" && App.modes && App.modes.length > 0)
                                ? App.modes
                                : [
                                      { value: "light", label: qsTr("浅清") },
                                      { value: "medium", label: qsTr("覆清") },
                                      { value: "heavy", label: qsTr("深清") }
                                  ]

    readonly property var spaceData: (typeof App !== "undefined" && App.space) ? App.space : ({})

    readonly property int spaceMinutes: (typeof App !== "undefined" && App.spaceMinutes !== undefined)
                                        ? Number(App.spaceMinutes) : 45

    readonly property string defaultModeValue: (typeof App !== "undefined" && App.defaultMode)
                                               ? String(App.defaultMode) : "medium"

    function modeGlyph(value) {
        if (value === "light") return "moon"
        if (value === "medium") return "wave"
        if (value === "heavy") return "lock"
        return "wave"
    }

    function modeLabel(value) {
        for (var i = 0; i < panel.modes.length; i++) {
            if (String(panel.modes[i].value) === String(value))
                return String(panel.modes[i].label)
        }
        return String(value)
    }

    // v0.8：速启面板的空间/档位点击 → 打开主窗口空间页并切到对应标签
    function openSpaces(value) {
        if (typeof App !== "undefined" && typeof App.openSpacesPage === "function")
            App.openSpacesPage(String(value || ""))
        else if (typeof App.startMode === "function")
            App.startMode(String(value))
        panel.hide()
    }

    function startMode(value) {
        if (typeof App.startMode === "function")
            App.startMode(String(value))
        panel.hide()
    }

    Component.onCompleted: {
        AppTheme.mode = (typeof App !== "undefined" && App.themeMode) ? App.themeMode : "solid"
    }

    // ---------- 内容根：显示时上滑 10px + 淡入（160ms），隐藏 120ms 淡出后 visible=false ----------
    Item {
        id: panelRoot
        objectName: "PanelRoot"
        anchors.fill: parent
        opacity: 1
        // anchors.fill 锁住 x/y，位移用 Translate
        property alias shiftY: panelShift.y
        transform: Translate {
            id: panelShift
            y: 0
        }

    // ---------- 背景：主题底色 + 光斑 + 细噪点（光斑/噪点仅玻璃主题） ----------
    Item {
        id: bgLayer
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            radius: 18
            gradient: Gradient {
                GradientStop { position: 0.0; color: AppTheme.bgMid }
                GradientStop { position: 0.55; color: AppTheme.bgTop }
                GradientStop { position: 1.0; color: AppTheme.bgBottom }
            }
        }

        Item {
            anchors.fill: parent
            visible: AppTheme.glass

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
                opacity: 0.1
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: "transparent"
        border.width: 1
        border.color: AppTheme.glass ? "#4DFFFFFF" : AppTheme.cardBorderStrong
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
            }

            Row {
                anchors.left: appIcon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("深清")
                    color: AppTheme.textPrimary
                    font.pixelSize: AppTheme.fs(16)
                    font.weight: Font.DemiBold
                    font.family: AppTheme.fontFamily
                    font.letterSpacing: 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Clarity"
                    color: AppTheme.textTertiary
                    font.pixelSize: AppTheme.fs(10)
                    font.family: AppTheme.fontFamily
                }
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

        // ---- 区块一：专注档位 ----
        Text {
            id: modeTitle
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.topMargin: 14
            text: qsTr("专注档位")
            color: AppTheme.textSecondary
            font.pixelSize: AppTheme.fs(13)
            font.weight: Font.DemiBold
            font.family: AppTheme.fontFamily
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
                model: panel.modes

                delegate: Item {
                    id: modeCell
                    width: (modeRow.width - 20) / 3
                    height: 92
                    property bool held: false
                    property point pressPoint: Qt.point(0.5, 0.5)
                    readonly property bool isDefault: String(modelData.value) === panel.defaultModeValue

                    function trackPointer(mx, my) {
                        modeCell.pressPoint = Qt.point(
                            Math.max(0, Math.min(1, mx / modeCell.width)),
                            Math.max(0, Math.min(1, my / Math.max(1, 66))))
                    }

                    // 档位卡（玻璃主题：液态玻璃；纯色/浅色：平面卡）
                    Item {
                        id: modeTile
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 66
                        scale: !AppTheme.glass && modeArea.pressed ? 0.98 : 1.0
                        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                        LiquidGlass {
                            anchors.fill: parent
                            visible: AppTheme.glass
                            sourceItem: bgLayer
                            radius: 16
                            depth: 1.2
                            frost: 0.02
                            aberration: 0.58
                            highlight: 1.45
                            whiten: 0.05
                            tintAlpha: modeCell.isDefault ? 0.26 : 0.14
                            tint: modeCell.isDefault ? AppTheme.accentSoft : AppTheme.glassTint
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
                            visible: !AppTheme.glass
                            radius: 16
                            color: modeArea.containsMouse ? AppTheme.buttonBgAlt : AppTheme.buttonBg
                            border.width: 1
                            border.color: modeCell.isDefault ? AppTheme.accent : AppTheme.cardBorder
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: AppTheme.glass
                            radius: 16
                            color: "transparent"
                            border.width: 1
                            border.color: modeCell.isDefault ? AppTheme.accent : "#45FFFFFF"
                        }

                        Glyph {
                            anchors.centerIn: parent
                            kind: panel.modeGlyph(String(modelData.value))
                            size: 24
                            color: AppTheme.textPrimary
                        }
                    }

                    Text {
                        anchors.top: modeTile.bottom
                        anchors.topMargin: 6
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String(modelData.label)
                        color: AppTheme.textPrimary
                        font.pixelSize: AppTheme.fs(12)
                        font.family: AppTheme.fontFamily
                    }

                    MouseArea {
                        id: modeArea
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
                        onClicked: panel.openSpaces(String(modelData.value))
                    }
                }
            }
        }

        // ---- 区块二：清空间（唯一空间） ----
        Text {
            id: spaceTitle
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: modeRow.bottom
            anchors.topMargin: 14
            text: qsTr("空间")
            color: AppTheme.textSecondary
            font.pixelSize: AppTheme.fs(13)
            font.weight: Font.DemiBold
            font.family: AppTheme.fontFamily
            font.letterSpacing: 1
        }

        Item {
            id: spaceCard
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: spaceTitle.bottom
            anchors.topMargin: 10
            height: 78
            scale: !AppTheme.glass && spaceArea.pressed ? 0.985 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

            LiquidGlass {
                anchors.fill: parent
                visible: AppTheme.glass
                sourceItem: bgLayer
                radius: 16
                depth: 0.95
                frost: 0.02
                aberration: 0.45
                highlight: 1.05
                whiten: 0.04
                tintAlpha: 0.16
                tint: AppTheme.glassTint
                sheen: 0.45
            }

            Rectangle {
                anchors.fill: parent
                visible: !AppTheme.glass
                radius: 16
                color: spaceArea.containsMouse ? AppTheme.buttonBgAlt : AppTheme.buttonBg
                border.width: 1
                border.color: AppTheme.cardBorder
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Rectangle {
                anchors.fill: parent
                visible: AppTheme.glass
                radius: 16
                color: "transparent"
                border.width: 1
                border.color: "#3DFFFFFF"
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Row {
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.spaceData.name !== undefined ? String(panel.spaceData.name) : qsTr("清空间")
                        color: AppTheme.textPrimary
                        font.pixelSize: AppTheme.fs(14)
                        font.weight: Font.DemiBold
                        font.family: AppTheme.fontFamily
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("%1 分钟").arg(panel.spaceMinutes)
                        color: AppTheme.textTertiary
                        font.pixelSize: AppTheme.fs(11)
                        font.family: AppTheme.fontFamily
                    }
                }

                Text {
                    width: spaceCard.width - 80
                    text: qsTr("点击以「%1」开始专注").arg(panel.modeLabel(panel.defaultModeValue))
                    color: AppTheme.textSecondary
                    font.pixelSize: AppTheme.fs(11)
                    font.family: AppTheme.fontFamily
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                width: 30
                height: 30
                radius: 15
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                color: AppTheme.glass ? "#26FFFFFF" : AppTheme.accent

                Glyph {
                    anchors.centerIn: parent
                    kind: "play"
                    size: 13
                    color: AppTheme.glass ? AppTheme.textPrimary : "#FFFFFF"
                }
            }

            MouseArea {
                id: spaceArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.openSpaces(panel.defaultModeValue)
            }
        }

        // ---- 区块三：今日 ----
        Text {
            id: todayText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: spaceCard.bottom
            anchors.topMargin: 14
            text: qsTr("今日专注 %1 分钟 · 连续 %2 天")
                  .arg(Math.round(Number(App.todayMinutes) || 0))
                  .arg(Math.round(Number(App.streakDays) || 0))
            color: AppTheme.textTertiary
            font.pixelSize: AppTheme.fs(12)
            font.family: AppTheme.fontFamily
        }

        // ---- 中部留白：一句提示 ----
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: todayText.bottom
            anchors.topMargin: 24
            spacing: 8

            Glyph {
                anchors.horizontalCenter: parent.horizontalCenter
                kind: "ripple"
                size: 26
                color: AppTheme.glass ? "#3A6A78" : AppTheme.textTertiary
                opacity: 0.6
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("把注意力收回来")
                color: AppTheme.textTertiary
                font.pixelSize: AppTheme.fs(11)
                font.family: AppTheme.fontFamily
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
                color: AppTheme.glass ? "#0AFFFFFF" : AppTheme.buttonBgAlt
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
}
