import QtQuick
import "../theme"
import "../components"
import "../components/Constants.js" as C

// 设置页（v0.4）：权限与防退出 / 语言 / 默认专注时长 / 开机自启 / 关于
// 主题已移到独立的主题页（顶部菜单「主题」或全局搜索进入）
Item {
    id: page

    property Item glassSource: null

    signal onboardingRequested()

    // ---------- 还清（睡眠模式）本地状态 ----------
    property bool localSleepReminders: true
    property var localSleepTimes: ["23:30", "00:30"]
    property string newSleepTime: "23:30"
    property int clockClickCount: 0

    readonly property bool hasSleepBackend: (typeof App !== "undefined" && App.sleepScheduleItems !== undefined)
    readonly property var sleepItems: (typeof App !== "undefined" && App.sleepScheduleItems !== undefined)
                                      ? App.sleepScheduleItems : []
    readonly property var sleepTimes: hasSleepBackend ? sleepItems : page.localSleepTimes

    function addSleepTime(timeText) {
        var text = String(timeText).trim()
        if (text.length < 4) return
        if (typeof App !== "undefined" && typeof App.addSleepSchedule === "function") {
            App.addSleepSchedule(text)
        } else {
            var list = page.localSleepTimes.slice()
            if (list.indexOf(text) < 0) list.push(text)
            page.localSleepTimes = list
        }
    }
    function removeSleepTime(item) {
        if (typeof App !== "undefined" && typeof App.removeSleepSchedule === "function") {
            var key = (item !== null && item.id !== undefined) ? String(item.id)
                                                               : String(item)
            App.removeSleepSchedule(key)
        } else {
            var text = String(item)
            var list = page.localSleepTimes.slice()
            var idx = list.indexOf(text)
            if (idx >= 0) list.splice(idx, 1)
            page.localSleepTimes = list
        }
    }
    function toggleSleepReminders() {
        if (typeof App !== "undefined" && typeof App.setSleepReminders === "function") {
            App.setSleepReminders(!App.sleepRemindersEnabled)
        } else {
            page.localSleepReminders = !page.localSleepReminders
        }
    }
    function clickSleepClock() {
        if (typeof App !== "undefined" && typeof App.clickClockForUnlock === "function") {
            App.clickClockForUnlock()
            page.clockClickCount = (page.clockClickCount % 10) + 1
        } else {
            page.clockClickCount = (page.clockClickCount + 1) % 11
        }
        clockClickReset.restart()
    }
    Timer {
        id: clockClickReset
        interval: 5000
        repeat: false
        onTriggered: page.clockClickCount = 0
    }

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
                        color: AppTheme.textPrimary
                        font.pixelSize: 30
                        font.weight: Font.Bold
                        font.family: C.numFont
                        font.letterSpacing: 1
                    }
                    Text {
                        text: qsTr("%1（%2）v%3").arg(App.appName).arg(App.appAlias).arg(App.version)
                        color: AppTheme.textSecondary
                        font.pixelSize: 13
                        font.family: C.numFont
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
                                color: AppTheme.textPrimary
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                font.family: C.numFont
                            }
                            Text {
                                width: parent.width
                                text: qsTr("锁定期间隐藏任务栏，并屏蔽 Win、Alt+Tab 等系统快捷键")
                                color: AppTheme.textTertiary
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
                        color: AppTheme.divider
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
                                    color: AppTheme.textPrimary
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
                                color: AppTheme.textTertiary
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
                        color: AppTheme.divider
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
                                color: AppTheme.textPrimary
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                font.family: C.numFont
                            }
                            Text {
                                width: parent.width
                                text: qsTr("用计划任务在登录时以最高权限启动，不再弹 UAC；需要管理员")
                                color: AppTheme.textTertiary
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
                        color: AppTheme.textPrimary
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
                                { code: "en_US", label: "English" },
                                { code: "ja_JP", label: "日本語" },
                                { code: "fr_FR", label: "Français" }
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
                        color: AppTheme.textTertiary
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
                        color: AppTheme.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.family: C.numFont
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        text: qsTr("%1 分钟").arg(page.draftDefaultMinutes)
                        color: AppTheme.textSecondary
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

            // ---------- 反馈 ----------
            GlassCard {
                width: parent.width
                height: 132
                radius: 20
                interactive: false
                glassSource: page.glassSource

                Item {
                    anchors.fill: parent
                    anchors.margins: 20

                    Text {
                        id: feedbackLabel
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: qsTr("反馈")
                        color: AppTheme.textPrimary
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        font.family: C.numFont
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.top: feedbackLabel.bottom
                        anchors.topMargin: 10
                        spacing: 10

                        GlassButton {
                            text: qsTr("功能请求")
                            fontSize: 13
                            padH: 16
                            minHeight: 36
                            onClicked: App.openFeedback("request")
                        }
                        GlassButton {
                            text: qsTr("Bug 反馈")
                            fontSize: 13
                            padH: 16
                            minHeight: 36
                            onClicked: App.openFeedback("bug")
                        }
                        GlassButton {
                            text: qsTr("参与讨论")
                            fontSize: 13
                            padH: 16
                            minHeight: 36
                            onClicked: App.openFeedback("discuss")
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        text: qsTr("在 GitHub 仓库 Kryon2025/Clarity 提交功能请求、Bug 反馈或参与讨论。")
                        color: AppTheme.textTertiary
                        font.pixelSize: 11
                        font.family: C.numFont
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ---------- 还清（睡眠模式） ----------
            GlassCard {
                width: parent.width
                implicitHeight: sleepColumn.implicitHeight + 24
                height: implicitHeight
                radius: 20
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: sleepColumn
                    x: 16
                    y: 12
                    width: parent.width - 32
                    spacing: 10

                    Row {
                        width: parent.width
                        spacing: 9

                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            kind: "moon"
                            size: 16
                            color: AppTheme.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("还清（睡眠模式）")
                            color: AppTheme.textPrimary
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: C.numFont
                        }
                        Item { width: parent.width - 260; height: 1 }
                        GlassSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: (typeof App !== "undefined" && App.sleepRemindersEnabled !== undefined)
                                     ? App.sleepRemindersEnabled : page.localSleepReminders
                            onClicked: page.toggleSleepReminders()
                        }
                    }

                    Text {
                        width: parent.width
                        text: qsTr("到点自动进入深清锁定；开启右侧开关会提前提醒。")
                        color: AppTheme.textTertiary
                        font.pixelSize: 11
                        font.family: C.numFont
                        wrapMode: Text.WordWrap
                    }

                    // 多段锁定时间
                    Column {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: page.sleepTimes
                            delegate: Item {
                                width: sleepColumn.width
                                height: 32
                                readonly property string timeText: modelData.time !== undefined
                                                                   ? String(modelData.time)
                                                                   : String(modelData)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: AppTheme.glass ? "#12FFFFFF" : AppTheme.cardBgAlt
                                }
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("%1 锁定").arg(timeText)
                                    color: AppTheme.textPrimary
                                    font.pixelSize: 13
                                    font.family: C.numFont
                                }
                                Item {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    height: 24
                                    Glyph {
                                        anchors.centerIn: parent
                                        kind: "close"
                                        size: 11
                                        color: sleepRemoveArea.containsMouse ? AppTheme.danger : AppTheme.textTertiary
                                    }
                                    MouseArea {
                                        id: sleepRemoveArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: page.removeSleepTime(modelData)
                                    }
                                }
                            }
                        }

                        Row {
                            spacing: 8
                            TextInput {
                                id: newSleepInput
                                width: 88
                                height: 32
                                verticalAlignment: TextInput.AlignVCenter
                                horizontalAlignment: TextInput.AlignHCenter
                                text: page.newSleepTime
                                color: AppTheme.textPrimary
                                selectionColor: AppTheme.accentSoft
                                selectedTextColor: "#FFFFFF"
                                font.pixelSize: 13
                                font.family: C.numFont
                                onTextChanged: page.newSleepTime = text
                                Keys.onReturnPressed: page.addSleepTime(text)
                                Rectangle {
                                    anchors.fill: parent
                                    z: -1
                                    radius: 10
                                    color: AppTheme.cardBgAlt
                                    border.width: 1
                                    border.color: newSleepInput.activeFocus ? AppTheme.accent : AppTheme.cardBorder
                                }
                            }
                            GlassButton {
                                text: qsTr("添加时间")
                                tone: "ghost"
                                fontSize: 12
                                padH: 14
                                minHeight: 32
                                onClicked: page.addSleepTime(page.newSleepTime)
                            }
                        }

                        Text {
                            width: parent.width
                            text: qsTr("提醒：提前 1 小时 / 30 分钟 / 1 分钟")
                            color: AppTheme.textTertiary
                            font.pixelSize: 11
                            font.family: C.numFont
                        }

                        Row {
                            width: parent.width
                            spacing: 12

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (typeof App !== "undefined" && App.unlockChanceLabel !== undefined)
                                      ? String(App.unlockChanceLabel)
                                      : qsTr("本月剩余解锁次数：%1").arg(2)
                                color: AppTheme.textSecondary
                                font.pixelSize: 12
                                font.family: C.numFont
                            }

                            Item {
                                width: parent.width - 380
                                height: 1
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("连续点击时钟 10 次解锁")
                                color: AppTheme.textTertiary
                                font.pixelSize: 11
                                font.family: C.numFont
                            }

                            Item {
                                id: sleepClockButton
                                width: 30
                                height: 30
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 15
                                    color: sleepClockArea.containsMouse ? AppTheme.accentSoft : AppTheme.cardBgAlt
                                    border.width: 1
                                    border.color: AppTheme.cardBorder
                                }
                                Glyph {
                                    anchors.centerIn: parent
                                    kind: "clock"
                                    size: 15
                                    color: AppTheme.textPrimary
                                }
                                MouseArea {
                                    id: sleepClockArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: page.clickSleepClock()
                                }
                            }
                        }

                        // 连续点击进度
                        Item {
                            width: parent.width
                            height: 14
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 4
                                radius: 2
                                color: AppTheme.glass ? "#1AFFFFFF" : AppTheme.divider
                            }
                            Rectangle {
                                width: parent.width * page.clockClickCount / 10
                                height: 4
                                radius: 2
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                color: AppTheme.accent
                                Behavior on width { NumberAnimation { duration: 120 } }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -8
                                text: page.clockClickCount + " / 10"
                                color: AppTheme.textTertiary
                                font.pixelSize: 10
                                font.family: C.numFont
                            }
                        }
                    }
                }
            }

            // ---------- 新手引导 ----------
            GlassCard {
                width: parent.width
                height: 64
                radius: 20
                interactive: false
                glassSource: page.glassSource

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9
                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "sparkle"
                        size: 15
                        color: AppTheme.textSecondary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("新手引导")
                        color: AppTheme.textPrimary
                        font.pixelSize: 13
                        font.family: C.numFont
                    }
                }

                GlassButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("重新查看引导")
                    tone: "ghost"
                    fontSize: 12
                    padH: 16
                    minHeight: 32
                    onClicked: page.onboardingRequested()
                }
            }

            // ---------- 关于 ----------
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: qsTr("%1（%2）v%3 · Windows 专注锁机工具\n数据保存在 %APPDATA%/ShenQing/ · 主题可在左侧导航「主题」中切换").arg(App.appName).arg(App.appAlias).arg(App.version)
                color: AppTheme.textTertiary
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