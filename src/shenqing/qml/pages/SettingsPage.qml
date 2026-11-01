import QtQuick
import "../components"
import "../components/Constants.js" as C

// 设置页：主题 / 开机自启 / 默认时长 / 插件 / 关于
Item {
    id: page

    property Item glassSource: null

    readonly property var themeChoices: [
        { value: "Auto", label: qsTr("跟随系统") },
        { value: "Light", label: qsTr("浅色") },
        { value: "Dark", label: qsTr("深色") }
    ]

    readonly property var defaultMinutesValue: {
        var value = App.defaultMinutes
        return (typeof value === "number" && isFinite(value)) ? value : 45
    }

    property int draftDefaultMinutes: defaultMinutesValue

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.height + 60
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
                        text: qsTr("设置")
                        color: C.textPrimary
                        font.pixelSize: 30
                        font.weight: Font.Bold
                        font.family: C.numFont
                        font.letterSpacing: 1
                    }
                    Text {
                        text: qsTr("%1（%2）v%3").arg(App.appName).arg(App.appAlias).arg(App.version)
                        color: C.textSecondary
                        font.pixelSize: 13
                        font.family: C.numFont
                    }
                }
            }

            // ---------- 外观 ----------
            GlassCard {
                width: parent.width
                height: 108
                radius: 20
                interactive: false
                glassSource: page.glassSource

                Item {
                    anchors.fill: parent
                    anchors.margins: 20

                    Text {
                        id: themeLabel
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: qsTr("主题")
                        color: C.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.family: C.numFont
                    }

                    Text {
                        anchors.left: themeLabel.right
                        anchors.leftMargin: 8
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        text: qsTr("深色优先的液态玻璃界面")
                        color: C.textTertiary
                        font.pixelSize: 12
                        font.family: C.numFont
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        spacing: 10

                        Repeater {
                            model: page.themeChoices
                            delegate: GlassButton {
                                text: modelData.label
                                tone: App.theme === modelData.value ? "light" : "ghost"
                                fontSize: 13
                                padH: 18
                                minHeight: 36
                                selected: App.theme === modelData.value
                                onClicked: App.setTheme(modelData.value)
                            }
                        }
                    }
                }
            }

            // ---------- 权限与防退出 ----------
            GlassCard {
                width: parent.width
                implicitHeight: permissionColumn.implicitHeight + 16
                height: implicitHeight
                radius: 20
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: permissionColumn
                    width: parent.width
                    anchors.top: parent.top
                    anchors.topMargin: 8

                    // 防退出加固
                    Item {
                        width: parent.width
                        height: 88

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.right: hardeningSwitch.left
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Text {
                                text: qsTr("防退出加固")
                                color: C.textPrimary
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                font.family: C.numFont
                            }
                            Text {
                                width: parent.width
                                text: qsTr("锁定期间隐藏任务栏，并屏蔽 Win、Alt+Tab 等系统快捷键")
                                color: C.textTertiary
                                font.pixelSize: 11
                                font.family: C.numFont
                                wrapMode: Text.WordWrap
                            }
                        }

                        GlassSwitch {
                            id: hardeningSwitch
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            checked: App.hardeningEnabled === true
                            onClicked: {
                                if (typeof App.setHardeningEnabled === "function")
                                    App.setHardeningEnabled(!(App.hardeningEnabled === true))
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width - 28
                        x: 14
                        height: 1
                        color: C.divider
                    }

                    // 以管理员身份运行
                    Item {
                        width: parent.width
                        height: 88

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.right: adminSwitch.left
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Row {
                                spacing: 8

                                Text {
                                    text: qsTr("以管理员身份运行")
                                    color: C.textPrimary
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    font.family: C.numFont
                                }

                                Text {
                                    visible: App.isAdmin === true
                                    text: qsTr("当前已提权")
                                    color: "#6FE3B0"
                                    font.pixelSize: 11
                                    font.family: C.numFont
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                width: parent.width
                                text: qsTr("开启后会弹一次 UAC 并以管理员身份重启")
                                color: C.textTertiary
                                font.pixelSize: 11
                                font.family: C.numFont
                                wrapMode: Text.WordWrap
                            }
                        }

                        GlassSwitch {
                            id: adminSwitch
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            checked: App.adminMode === true
                            onClicked: {
                                if (typeof App.setAdminMode === "function")
                                    App.setAdminMode(!(App.adminMode === true))
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width - 28
                        x: 14
                        height: 1
                        color: C.divider
                    }

                    // 最高权限开机自启
                    Item {
                        width: parent.width
                        height: 92

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.right: elevatedSwitch.left
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Text {
                                text: qsTr("最高权限开机自启")
                                color: C.textPrimary
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                font.family: C.numFont
                            }
                            Text {
                                width: parent.width
                                text: qsTr("用计划任务在登录时以最高权限启动，不再弹 UAC；需要管理员")
                                color: C.textTertiary
                                font.pixelSize: 11
                                font.family: C.numFont
                                wrapMode: Text.WordWrap
                            }
                        }

                        GlassSwitch {
                            id: elevatedSwitch
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            checked: App.elevatedAutostart === true
                            onClicked: {
                                if (typeof App.setElevatedAutostart === "function")
                                    App.setElevatedAutostart(!(App.elevatedAutostart === true))
                            }
                        }
                    }
                }
            }

            // ---------- 语言 ----------
            GlassCard {
                width: parent.width
                height: 152
                radius: 20
                interactive: false
                glassSource: page.glassSource

                Item {
                    anchors.fill: parent
                    anchors.margins: 20

                    Text {
                        id: languageLabel
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: qsTr("语言")
                        color: C.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.family: C.numFont
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.top: languageLabel.bottom
                        anchors.topMargin: 10
                        spacing: 10

                        Repeater {
                            model: [
                                { code: "auto", label: qsTr("跟随系统") },
                                { code: "zh_CN", label: qsTr("简体中文") },
                                { code: "en_US", label: "English" }
                            ]
                            delegate: GlassButton {
                                text: modelData.label
                                tone: App.language === modelData.code ? "light" : "ghost"
                                fontSize: 13
                                padH: 18
                                minHeight: 36
                                selected: App.language === modelData.code
                                onClicked: {
                                    if (typeof App.setLanguage === "function")
                                        App.setLanguage(modelData.code)
                                }
                            }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        text: qsTr("切换后界面会立即更新；托盘菜单在下次启动时生效。")
                        color: C.textTertiary
                        font.pixelSize: 11
                        font.family: C.numFont
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ---------- 专注 ----------
            GlassCard {
                width: parent.width
                height: 118
                radius: 20
                interactive: false
                glassSource: page.glassSource

                Item {
                    anchors.fill: parent
                    anchors.margins: 20

                    Text {
                        id: minutesLabel
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: qsTr("默认专注时长")
                        color: C.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.family: C.numFont
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        text: qsTr("%1 分钟").arg(page.draftDefaultMinutes)
                        color: C.textSecondary
                        font.pixelSize: 13
                        font.family: C.numFont
                    }

                    GlassSlider {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        from: 15
                        to: 240
                        step: 5
                        value: page.draftDefaultMinutes
                        onMoved: (value) => {
                            page.draftDefaultMinutes = value
                            App.setDefaultMinutes(value)
                        }
                    }
                }
            }

            // ---------- 系统 ----------
            GlassCard {
                width: parent.width
                implicitHeight: systemColumn.implicitHeight + 12
                height: implicitHeight
                radius: 20
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: systemColumn
                    width: parent.width
                    anchors.top: parent.top
                    anchors.topMargin: 6

                    GlassRow {
                        width: parent.width
                        title: qsTr("开机自启")
                        interactive: false
                        showChevron: false

                        GlassSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: App.autostartEnabled
                            onClicked: App.setAutostart(!App.autostartEnabled)
                        }
                    }
                }
            }

            // ---------- 关于 ----------
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: qsTr("%1（%2）× Windows 专注锁机工具\n数据保存在 %APPDATA%/ShenQing/ · 界面：液态玻璃 v0.2").arg(App.appName).arg(App.appAlias)
                color: C.textTertiary
                font.pixelSize: 12
                font.family: C.numFont
                lineHeight: 1.4
            }

            Item { width: parent.width; height: 2 }
        }
    }

    Rectangle {
        visible: flick.contentHeight > flick.height + 4
        width: 4
        radius: 2
        color: "#26FFFFFF"
        x: flick.width - 14
        height: Math.max(48, flick.height * flick.height / Math.max(1, flick.contentHeight))
        y: 18 + Math.max(0, Math.min(1, flick.contentY / Math.max(1, flick.contentHeight - flick.height)))
           * Math.max(1, flick.height - 36 - height)
    }
}