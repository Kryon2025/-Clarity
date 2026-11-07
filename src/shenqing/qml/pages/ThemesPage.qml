import QtQuick
import "../theme"
import "../components"
import "../components/Constants.js" as C

// 主题页（v0.4）：纯色（默认）/ 清空间浅色 / 液态玻璃（实验性）
// 从顶部菜单「主题」或全局搜索进入，不占 navIndex。
Item {
    id: page

    property Item glassSource: null
    // 从搜索点进来时可指定要闪亮提示的主题值
    property string highlightValue: ""

    readonly property var themes: (typeof App !== "undefined" && App.themes && App.themes.length > 0)
                                  ? App.themes
                                  : [
                                        { value: "solid", label: qsTr("纯色"), desc: qsTr("平面纯色，无需 GPU 特效"), experimental: false },
                                        { value: "light", label: qsTr("清空间浅色"), desc: qsTr("浅色底的清空间主题"), experimental: false },
                                        { value: "glass", label: qsTr("液态玻璃"), desc: qsTr("折射玻璃与拖拽高光（实验性）"), experimental: true }
                                    ]

    readonly property string currentTheme: (typeof App !== "undefined" && App.themeMode)
                                           ? String(App.themeMode) : "solid"

    function themeValue(index) {
        var list = page.themes
        if (index >= 0 && index < list.length) return String(list[index].value)
        return ""
    }

    function currentThemeLabel() {
        var list = page.themes
        for (var i = 0; i < list.length; i++) {
            if (String(list[i].value) === page.currentTheme)
                return String(list[i].label)
        }
        return page.currentTheme
    }

    function selectTheme(value) {
        page.highlightValue = String(value)
        if (typeof App.setThemeMode === "function")
            App.setThemeMode(String(value))
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.height + 64
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: pageColumn
            width: Math.min(flick.width - 96, 780)
            x: (flick.width - width) / 2
            y: 26
            spacing: 16

            // ---------- 页头 ----------
            Item {
                width: parent.width
                height: 76

                Column {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 6
                    Text {
                        text: qsTr("主题")
                        color: AppTheme.textPrimary
                        font.pixelSize: AppTheme.fs(30)
                        font.weight: Font.Bold
                        font.family: AppTheme.fontFamily
                        font.letterSpacing: 1
                    }
                    Text {
                        text: qsTr("外观风格会立即生效；顶栏、导航与卡片都会跟着切换")
                        color: AppTheme.textSecondary
                        font.pixelSize: AppTheme.fs(13)
                        font.family: AppTheme.fontFamily
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    spacing: 6

                    Rectangle {
                        width: 7
                        height: 7
                        radius: 3.5
                        anchors.verticalCenter: parent.verticalCenter
                        color: AppTheme.accent
                    }
                    Text {
                        text: qsTr("当前：%1").arg(page.currentThemeLabel())
                        color: AppTheme.textSecondary
                        font.pixelSize: AppTheme.fs(12)
                        font.family: AppTheme.fontFamily
                    }
                }
            }

            // ---------- 主题卡片列表 ----------
            Repeater {
                model: page.themes

                delegate: GlassCard {
                    id: themeCard
                    width: pageColumn.width
                    height: 126
                    radius: 22
                    interactive: true
                    selected: page.currentTheme === String(modelData.value)
                    accentTint: AppTheme.accent
                    glassSource: page.glassSource
                    onClicked: page.selectTheme(String(modelData.value))

                    Item {
                        anchors.fill: parent
                        anchors.margins: 20

                        // 左侧预览缩略
                        Item {
                            id: previewBox
                            width: 86
                            height: 86
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                visible: String(modelData.value) === "solid"
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#0E2A38" }
                                    GradientStop { position: 1.0; color: "#04121C" }
                                }
                                border.width: 1
                                border.color: "#2BFFFFFF"

                                Rectangle {
                                    x: 12
                                    y: 14
                                    width: 34
                                    height: 10
                                    radius: 5
                                    color: "#2ED3C6"
                                }
                                Rectangle {
                                    x: 12
                                    y: 30
                                    width: 62
                                    height: 8
                                    radius: 4
                                    color: "#1FFFFFFF"
                                }
                                Rectangle {
                                    x: 12
                                    y: 44
                                    width: 50
                                    height: 8
                                    radius: 4
                                    color: "#14FFFFFF"
                                }
                                Rectangle {
                                    x: 12
                                    y: 60
                                    width: 40
                                    height: 14
                                    radius: 7
                                    color: "#2ED3C6"
                                    opacity: 0.85
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                visible: String(modelData.value) === "light"
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#FFFFFF" }
                                    GradientStop { position: 1.0; color: "#DCEBEF" }
                                }
                                border.width: 1
                                border.color: "#330E2831"

                                Rectangle {
                                    x: 12
                                    y: 14
                                    width: 34
                                    height: 10
                                    radius: 5
                                    color: "#0E9E95"
                                }
                                Rectangle {
                                    x: 12
                                    y: 30
                                    width: 62
                                    height: 8
                                    radius: 4
                                    color: "#C6DEE3"
                                }
                                Rectangle {
                                    x: 12
                                    y: 44
                                    width: 50
                                    height: 8
                                    radius: 4
                                    color: "#D8E9ED"
                                }
                                Rectangle {
                                    x: 12
                                    y: 60
                                    width: 40
                                    height: 14
                                    radius: 7
                                    color: "#0E9E95"
                                    opacity: 0.9
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                visible: String(modelData.value) === "glass"
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#1F6FD0" }
                                    GradientStop { position: 0.55; color: "#2ED3C6" }
                                    GradientStop { position: 1.0; color: "#0A2A36" }
                                }
                                opacity: 0.55
                                border.width: 1
                                border.color: "#A6FFFFFF"

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    radius: 10
                                    color: "#1FFFFFFF"
                                    border.width: 1
                                    border.color: "#66FFFFFF"
                                }

                                Glyph {
                                    anchors.centerIn: parent
                                    kind: "sparkle"
                                    size: 20
                                    color: "#FFFFFF"
                                }
                            }
                        }

                        // 文字
                        Column {
                            anchors.left: previewBox.right
                            anchors.leftMargin: 18
                            anchors.right: currentBadge.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Row {
                                spacing: 8

                                Text {
                                    text: String(modelData.label)
                                    color: AppTheme.textPrimary
                                    font.pixelSize: AppTheme.fs(17)
                                    font.weight: Font.DemiBold
                                    font.family: AppTheme.fontFamily
                                }

                                Rectangle {
                                    visible: modelData.experimental === true
                                    width: experimentalText.implicitWidth + 14
                                    height: 18
                                    radius: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: AppTheme.glass ? "#26FFB86B" : "#FFF3E2"
                                    border.width: 1
                                    border.color: AppTheme.glass ? "#66FFB86B" : "#F0C48A"

                                    Text {
                                        id: experimentalText
                                        anchors.centerIn: parent
                                        text: qsTr("实验性")
                                        color: AppTheme.glass ? "#FFD9A6" : "#9A5B12"
                                        font.pixelSize: AppTheme.fs(9)
                                        font.family: AppTheme.fontFamily
                                    }
                                }

                                Rectangle {
                                    visible: page.currentTheme === String(modelData.value)
                                    width: currentText.implicitWidth + 14
                                    height: 18
                                    radius: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: AppTheme.glass ? "#2A2ED3C6" : "#E4F4F2"
                                    border.width: 1
                                    border.color: AppTheme.accent

                                    Text {
                                        id: currentText
                                        anchors.centerIn: parent
                                        text: qsTr("使用中")
                                        color: AppTheme.accent
                                        font.pixelSize: AppTheme.fs(9)
                                        font.family: AppTheme.fontFamily
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                text: modelData.desc !== undefined ? String(modelData.desc) : ""
                                color: AppTheme.textSecondary
                                font.pixelSize: AppTheme.fs(12)
                                font.family: AppTheme.fontFamily
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                visible: String(modelData.value) === "glass"
                                text: qsTr("低配设备建议使用纯色，性能更稳")
                                color: AppTheme.textTertiary
                                font.pixelSize: AppTheme.fs(10)
                                font.family: AppTheme.fontFamily
                            }
                        }

                        // 右侧选中标记
                        Item {
                            id: currentBadge
                            width: 34
                            height: 34
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: 17
                                visible: page.currentTheme === String(modelData.value)
                                color: AppTheme.accent
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 17
                                visible: page.currentTheme !== String(modelData.value)
                                color: "transparent"
                                border.width: 1
                                border.color: AppTheme.glass ? "#2EFFFFFF" : AppTheme.cardBorderStrong
                            }

                            Glyph {
                                anchors.centerIn: parent
                                kind: page.currentTheme === String(modelData.value) ? "check" : "chevron"
                                size: 15
                                color: page.currentTheme === String(modelData.value)
                                       ? "#FFFFFF" : AppTheme.textTertiary
                            }
                        }
                    }
                }
            }


            Item { width: parent.width; height: 2 }
        }
    }

    // 从搜索点进来时，闪一下被点名的主题（纯视觉提示，不改设置）
    Rectangle {
        id: flashRing
        visible: page.highlightValue !== ""
        width: pageColumn.width
        height: 126
        radius: 22
        x: (flick.width - width) / 2
        color: "transparent"
        border.width: 2
        border.color: AppTheme.accent
        opacity: 0
        y: {
            var list = page.themes
            for (var i = 0; i < list.length; i++) {
                if (String(list[i].value) === page.highlightValue)
                    return 118 + i * 142 - flick.contentY
            }
            return -100
        }

        SequentialAnimation {
            running: page.highlightValue !== ""
            loops: 1
            NumberAnimation { target: flashRing; property: "opacity"; to: 0.8; duration: 160 }
            NumberAnimation { target: flashRing; property: "opacity"; to: 0; duration: 420 }
            onFinished: page.highlightValue = ""
        }
    }
}
