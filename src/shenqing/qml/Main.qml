import QtQuick
import RinUI
import "components"
import "pages"
import "glass"
import "components/Constants.js" as C

FluentWindow {
    id: win

    visible: true
    width: 1080
    height: 720
    minimumWidth: 960
    minimumHeight: 640
    title: qsTr("%1（%2）").arg(App.appName).arg(App.appAlias)

    // 关闭主窗口 = 收进托盘继续运行（真正退出走托盘/速启面板的「退出深清」）
    property bool allowClose: false
    onClosing: function (close) {
        if (!win.allowClose) {
            close.accepted = false
            win.hide()
        }
    }
    titleEnabled: false
    color: "transparent"
    appLayerEnabled: false

    property int navIndex: 0
    property string overlayMode: "none"       // none | sheet | whitelist
    property string editSpaceId: ""
    property bool editIsNew: false

    // 液态玻璃采样源：窗口背景层（渐变 + 光斑 + 噪点）
    readonly property Item glassSource: appBackdrop

    // 上方 3 项；「设置」固定在最底部（navIndex = 3）
    readonly property var navItems: [
        { label: qsTr("空间"), icon: "ripple" },
        { label: qsTr("数据"), icon: "waveBars" },
        { label: qsTr("插件"), icon: "grid" }
    ]

    // 自己画导航，收起 RinUI 内置导航视图
    Component.onCompleted: {
        navigationView.visible = false
        navigationView.navigationBar.visible = false
        navigationView.navigationBar.titleBarEnabled = false
    }

    background: Backdrop { id: appBackdrop }

    // ================= 浮层控制 =================
    function beginEdit(spaceId) {
        if (!spaceId) return
        editSpaceId = String(spaceId)
        editIsNew = false
        App.beginEditSpace(editSpaceId)
        settingsSheet.open(editSpaceId, false)
        overlayMode = "sheet"
    }

    function createSpace() {
        var newId = App.spacesNew()
        if (!newId) return
        editSpaceId = String(newId)
        editIsNew = true
        App.beginEditSpace(editSpaceId)
        settingsSheet.open(editSpaceId, true)
        overlayMode = "sheet"
    }

    function openWhitelist() {
        overlayMode = "whitelist"
    }

    function backToSheet() {
        overlayMode = "sheet"
    }

    function closeOverlay() {
        overlayMode = "none"
    }

    function handleSheetCancelled() {
        if (editIsNew && editSpaceId !== "") {
            // 取消新建：把刚创建的空空间收回去，保持列表干净
            App.deleteSpace(editSpaceId)
        }
        overlayMode = "none"
    }

    // ================= 主体 =================
    Item {
        id: rootContent
        anchors.fill: parent
        // 让所有后代控件能沿父链自动找到液态玻璃采样源
        property Item glassSource: win.glassSource

        // ---------- 左侧导航玻璃条 ----------
        // 导航玻璃条：真·液态玻璃
        LiquidGlass {
            id: railGlass
            x: 12
            y: 10
            width: 76
            height: parent.height - 20
            sourceItem: win.glassSource
            radius: 26
            depth: 0.9
            frost: 0.03
            aberration: 0.38
            highlight: 0.7
            whiten: 0.015
            tintAlpha: 0.14
            tint: C.glassTint
            sheen: 0.3
        }

        Rectangle {
            id: railBg
            x: 12
            y: 10
            width: 76
            height: parent.height - 20
            radius: 26
            color: "transparent"
            border.width: 1
            border.color: "#2BFFFFFF"
        }

        Item {
            id: rail
            x: 12
            y: 10
            width: 76
            height: parent.height - 20

            // 应用标记：海蓝水滴（不再有汉字）
            Rectangle {
                id: appMark
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 16
                width: 44
                height: 44
                radius: 15
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#7FE7DA" }
                    GradientStop { position: 0.5; color: "#2ED3C6" }
                    GradientStop { position: 1.0; color: "#1F6FD0" }
                }
                border.width: 1
                border.color: "#66FFFFFF"
                Glyph {
                    anchors.centerIn: parent
                    kind: "drop"
                    size: 22
                    color: "#04222B"
                }
            }

            // 唯一的高亮玻璃块：随选中项平滑滑动（这是「模块切换」唯一保留的动效）
            LiquidGlass {
                id: navHighlight
                width: 56
                height: 62
                x: navColumn.x
                y: win.navIndex < 3
                   ? navColumn.y + win.navIndex * (62 + navColumn.spacing)
                   : settingsNav.y
                sourceItem: win.glassSource
                radius: 16
                depth: 0.55
                frost: 0.02
                aberration: 0.28
                highlight: 0.9
                whiten: 0.05
                tintAlpha: 0.30
                tint: C.accentSoft
                sheen: 0.35
                Behavior on y {
                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                }
            }

            // 上方三项导航：只画图标 + 文字；选中态只改颜色（无 hover 特效）
            Column {
                id: navColumn
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: appMark.bottom
                anchors.topMargin: 24
                spacing: 10

                Repeater {
                    model: win.navItems
                    delegate: Item {
                        id: navItem
                        width: 56
                        height: 62
                        readonly property bool active: win.navIndex === index

                        Column {
                            anchors.centerIn: parent
                            spacing: 5

                            Glyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                kind: modelData.icon
                                size: 20
                                color: navItem.active ? "#FFFFFF" : "#9AA8C4"
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                color: navItem.active ? "#FFFFFF" : "#9AA8C4"
                                font.pixelSize: 11
                                font.family: C.numFont
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.navIndex = index
                        }
                    }
                }
            }

            // 底部固定的「设置」项
            Item {
                id: settingsNav
                width: 56
                height: 62
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: versionLabel.top
                anchors.bottomMargin: 10
                readonly property bool active: win.navIndex === 3

                Column {
                    anchors.centerIn: parent
                    spacing: 5

                    Glyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        kind: "shell"
                        size: 20
                        color: settingsNav.active ? "#FFFFFF" : "#9AA8C4"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("设置")
                        color: settingsNav.active ? "#FFFFFF" : "#9AA8C4"
                        font.pixelSize: 11
                        font.family: C.numFont
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.navIndex = 3
                }
            }

            Text {
                id: versionLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                text: "v" + App.version
                color: "#5F6C84"
                font.pixelSize: 10
                font.family: C.numFont
            }
        }

        // ---------- 页面区 ----------
        Item {
            id: pageHost
            anchors.left: rail.right
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            SpacesPage {
                anchors.fill: parent
                glassSource: win.glassSource
                z: win.navIndex === 0 ? 2 : 1
                enabled: win.navIndex === 0
                opacity: win.navIndex === 0 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                transform: Translate {
                    y: win.navIndex === 0 ? 0 : 12
                    Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
                onEditSpaceRequested: (id) => win.beginEdit(id)
                onNewSpaceRequested: win.createSpace()
            }

            StatsPage {
                anchors.fill: parent
                glassSource: win.glassSource
                z: win.navIndex === 1 ? 2 : 1
                enabled: win.navIndex === 1
                opacity: win.navIndex === 1 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                transform: Translate {
                    y: win.navIndex === 1 ? 0 : 12
                    Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }

            PluginsPage {
                anchors.fill: parent
                glassSource: win.glassSource
                z: win.navIndex === 2 ? 2 : 1
                enabled: win.navIndex === 2
                opacity: win.navIndex === 2 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                transform: Translate {
                    y: win.navIndex === 2 ? 0 : 12
                    Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }

            SettingsPage {
                anchors.fill: parent
                glassSource: win.glassSource
                z: win.navIndex === 3 ? 2 : 1
                enabled: win.navIndex === 3
                opacity: win.navIndex === 3 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                transform: Translate {
                    y: win.navIndex === 3 ? 0 : 12
                    Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
        }

        // ---------- 浮层（空间设置 / 白名单） ----------
        Item {
            id: overlayLayer
            anchors.fill: parent
            z: 300
            visible: win.overlayMode !== "none"
            focus: visible
            Keys.onEscapePressed: {
                if (win.overlayMode === "whitelist") win.backToSheet()
                else if (win.overlayMode === "sheet") win.handleSheetCancelled()
            }

            Rectangle {
                id: scrim
                anchors.fill: parent
                color: "#05070A"
                opacity: win.overlayMode !== "none" ? C.scrimOpacity : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
            }

            // 拦截下层点击
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: {}
            }

            SpaceSettingsSheet {
                id: settingsSheet
                glassSource: win.glassSource
                width: 600
                height: implicitHeight
                x: Math.round((parent.width - width) / 2)
                y: 30
                visible: win.overlayMode === "sheet"
                opacity: win.overlayMode === "sheet" ? 1 : 0
                scale: win.overlayMode === "sheet" ? 1 : 0.985
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                transform: Translate {
                    y: win.overlayMode === "sheet" ? 0 : 24
                    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                }
                onCloseRequested: win.handleSheetCancelled()
                onCommitted: win.closeOverlay()
                onDeleteConfirmed: win.closeOverlay()
                onWhitelistRequested: win.openWhitelist()
            }

            WhitelistPage {
                anchors.fill: parent
                anchors.margins: 16
                glassSource: win.glassSource
                spaceId: win.editSpaceId
                visible: win.overlayMode === "whitelist"
                opacity: win.overlayMode === "whitelist" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                transform: Translate {
                    y: win.overlayMode === "whitelist" ? 0 : 30
                    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                }
                onBackRequested: win.backToSheet()
            }
        }
    }

    // ---------- 重度锁机全屏遮罩 ----------
    LockOverlay {}
}