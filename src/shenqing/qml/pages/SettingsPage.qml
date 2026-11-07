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
    signal aiPageRequested()

    // ---------- 还清（睡眠模式）本地状态 ----------
    property bool localSleepReminders: true
    property var localSleepTimes: ["23:30", "00:30"]
    property string newSleepTime: "23:30"
    property int clockClickCount: 0

    // ---------- v0.12 外观：字号 / 字体 / 导航展开方式 ----------
    property bool fontMenuOpen: false
    readonly property var fontFamilyList: {
        var out = [{ value: "", label: qsTr("默认") }]
        if (typeof App !== "undefined" && App.uiFontFamilies !== undefined && App.uiFontFamilies !== null
                && App.uiFontFamilies.length > 0) {
            for (var i = 0; i < App.uiFontFamilies.length; i++) {
                var family = String(App.uiFontFamilies[i])
                if (family !== "" && family.indexOf("@") !== 0)
                    out.push({ value: family, label: family })
            }
            return out
        }
        out.push({ value: "Microsoft YaHei UI", label: qsTr("微软雅黑") })
        out.push({ value: "Segoe UI", label: "Segoe UI" })
        out.push({ value: "SimSun", label: qsTr("宋体") })
        return out
    }
    readonly property string currentFontValue: (typeof App !== "undefined" && App.uiFontFamily !== undefined)
                                                ? String(App.uiFontFamily) : ""
    readonly property string currentFontLabel: {
        var list = page.fontFamilyList
        for (var i = 0; i < list.length; i++)
            if (String(list[i].value) === page.currentFontValue) return String(list[i].label)
        if (page.currentFontValue !== "") return page.currentFontValue
        return qsTr("默认")
    }
    readonly property real currentFontScale: (typeof App !== "undefined" && App.uiFontScale !== undefined)
                                              ? Number(App.uiFontScale) : AppTheme.fontScale
    readonly property string currentNavMode: (typeof App !== "undefined" && App.navMode !== undefined)
                                              ? String(App.navMode)
                                              : (AppTheme.navMode !== undefined ? AppTheme.navMode : "auto")
    function setFontScale(value) {
        if (typeof App !== "undefined" && typeof App.setUIFontScale === "function")
            App.setUIFontScale(Number(value))
        else
            AppTheme.fontScale = Number(value)
    }
    function setFontFamily(value) {
        if (typeof App !== "undefined" && typeof App.setUIFontFamily === "function")
            App.setUIFontFamily(String(value))
        else
            AppTheme.fontFamily = String(value) !== ""
                                  ? String(value)
                                  : ((typeof App !== "undefined" && App.defaultFontFamily !== undefined)
                                     ? String(App.defaultFontFamily) : C.numFont)
    }
    function setNavMode(value) {
        if (typeof App !== "undefined" && typeof App.setNavMode === "function")
            App.setNavMode(String(value))
        else
            AppTheme.navMode = String(value)
    }

    // ---------- v0.9 AI 助手设置 ----------
    property bool aiLocalEnabled: false
    property bool aiProviderMenuOpen: false
    property int aiProviderIndex: 0
    property string aiModelDraft: ""
    property string aiBaseDraft: ""
    property string aiKeyDraft: ""
    property string aiTestText: ""
    property string aiTestKind: "idle"
    readonly property var aiProviderList: {
        if (typeof App !== "undefined" && App.aiProviders !== undefined && App.aiProviders !== null
                && App.aiProviders.length > 0)
            return App.aiProviders
        return [
            { id: "groq", label: "Groq", base: "https://api.groq.com/openai/v1",
              models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"] },
            { id: "zhipu", label: qsTr("智谱 GLM"), base: "https://open.bigmodel.cn/api/paas/v4",
              models: ["glm-4-flash", "glm-4-plus"] },
            { id: "siliconflow", label: qsTr("硅基流动"), base: "https://api.siliconflow.cn/v1",
              models: ["Qwen/Qwen2.5-7B-Instruct", "deepseek-ai/DeepSeek-V3"] },
            { id: "custom", label: qsTr("自定义"), base: "", models: [] }
        ]
    }
    readonly property var currentAIProvider: {
        var list = page.aiProviderList
        if (page.aiProviderIndex < 0 || page.aiProviderIndex >= list.length) return list[0]
        return list[page.aiProviderIndex]
    }
    readonly property bool aiEnabledValue: (typeof App !== "undefined" && App.aiEnabled !== undefined)
                                           ? App.aiEnabled === true : page.aiLocalEnabled
    readonly property string aiProviderLabel: (page.currentAIProvider.label !== undefined)
                                               ? String(page.currentAIProvider.label) : ""
    readonly property string aiBackendState: (typeof App !== "undefined" && App.aiState !== undefined)
                                             ? String(App.aiState) : ""
    readonly property string aiStatusText: {
        if (page.aiBackendState === "testing") return qsTr("测试中…")
        if (page.aiBackendState === "ok") return qsTr("连接成功")
        if (page.aiBackendState === "error")
            return (typeof App !== "undefined" && App.aiError !== undefined && String(App.aiError) !== "")
                   ? String(App.aiError) : qsTr("连接失败")
        if (page.aiTestText !== "") return page.aiTestText
        if (typeof App !== "undefined" && App.aiConfigured === true) return qsTr("已配置")
        return qsTr("未配置")
    }
    readonly property string aiStatusColor: {
        if (page.aiBackendState === "ok" || page.aiTestKind === "ok") return AppTheme.accent
        if (page.aiBackendState === "error" || page.aiTestKind === "error") return AppTheme.danger
        return AppTheme.textTertiary
    }

    function initAI() {
        if (typeof App !== "undefined" && App.aiProvider !== undefined) {
            var providers = page.aiProviderList
            for (var i = 0; i < providers.length; i++) {
                if (String(providers[i].id) === String(App.aiProvider)) { page.aiProviderIndex = i; break }
            }
        }
        var p = page.currentAIProvider
        page.aiBaseDraft = (typeof App !== "undefined" && App.aiBase !== undefined && String(App.aiBase) !== "")
                           ? String(App.aiBase) : String(p.base || "")
        if (typeof App !== "undefined" && App.aiModel !== undefined && String(App.aiModel) !== "")
            page.aiModelDraft = String(App.aiModel)
        else if (p.models !== undefined && p.models.length > 0)
            page.aiModelDraft = String(p.models[0])
    }
    function selectAIProvider(index) {
        page.aiProviderIndex = index
        page.aiProviderMenuOpen = false
        var p = page.aiProviderList[index]
        page.aiBaseDraft = (p.base !== undefined) ? String(p.base) : ""
        page.aiModelDraft = (p.models !== undefined && p.models.length > 0) ? String(p.models[0]) : ""
        if (typeof App !== "undefined" && typeof App.setAIProvider === "function")
            App.setAIProvider(String(p.id))
        if (typeof App !== "undefined" && typeof App.setAIBase === "function")
            App.setAIBase(page.aiBaseDraft)
        if (typeof App !== "undefined" && typeof App.setAIModel === "function")
            App.setAIModel(page.aiModelDraft)
    }
    function saveAIModel() {
        if (typeof App !== "undefined" && typeof App.setAIModel === "function")
            App.setAIModel(page.aiModelDraft)
    }
    function saveAIBase() {
        if (typeof App !== "undefined" && typeof App.setAIBase === "function")
            App.setAIBase(page.aiBaseDraft)
    }
    function saveAIKey() {
        if (typeof App !== "undefined" && typeof App.setAIKey === "function" && page.aiKeyDraft !== "")
            App.setAIKey(page.aiKeyDraft)
    }
    function toggleAI() {
        if (typeof App !== "undefined" && typeof App.setAIEnabled === "function") {
            App.setAIEnabled(!page.aiEnabledValue)
        } else {
            page.aiLocalEnabled = !page.aiLocalEnabled
        }
    }
    function testAIConnection() {
        if (typeof App !== "undefined" && typeof App.testAIConnection === "function") {
            page.aiTestKind = "testing"
            page.aiTestText = ""
            App.testAIConnection()
        } else {
            page.aiTestKind = "error"
            page.aiTestText = qsTr("缺少测试接口（App.testAIConnection）")
        }
    }
    Component.onCompleted: initAI()

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
                        font.pixelSize: AppTheme.fs(30)
                        font.weight: Font.Bold
                        font.family: AppTheme.fontFamily
                        font.letterSpacing: 1
                    }
                    Text {
                        text: qsTr("%1（%2）v%3").arg(App.appName).arg(App.appAlias).arg(App.version)
                        color: AppTheme.textSecondary
                        font.pixelSize: AppTheme.fs(13)
                        font.family: AppTheme.fontFamily
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
                                font.pixelSize: AppTheme.fs(14)
                                font.weight: Font.DemiBold
                                font.family: AppTheme.fontFamily
                            }
                            Text {
                                width: parent.width
                                text: qsTr("锁定期间隐藏任务栏，并屏蔽 Win、Alt+Tab 等系统快捷键")
                                color: AppTheme.textTertiary
                                font.pixelSize: AppTheme.fs(11)
                                font.family: AppTheme.fontFamily
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
                                    font.pixelSize: AppTheme.fs(14)
                                    font.weight: Font.DemiBold
                                    font.family: AppTheme.fontFamily
                                }

                                Text {
                                    visible: App.isAdmin === true
                                    text: qsTr("当前已提权")
                                    color: "#6FE3B0"
                                    font.pixelSize: AppTheme.fs(11)
                                    font.family: AppTheme.fontFamily
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                width: parent.width
                                text: qsTr("开启后会弹一次 UAC 并以管理员身份重启")
                                color: AppTheme.textTertiary
                                font.pixelSize: AppTheme.fs(11)
                                font.family: AppTheme.fontFamily
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
                                font.pixelSize: AppTheme.fs(14)
                                font.weight: Font.DemiBold
                                font.family: AppTheme.fontFamily
                            }
                            Text {
                                width: parent.width
                                text: qsTr("用计划任务在登录时以最高权限启动，不再弹 UAC；需要管理员")
                                color: AppTheme.textTertiary
                                font.pixelSize: AppTheme.fs(11)
                                font.family: AppTheme.fontFamily
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
                        font.pixelSize: AppTheme.fs(15)
                        font.weight: Font.DemiBold
                        font.family: AppTheme.fontFamily
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
                        font.pixelSize: AppTheme.fs(11)
                        font.family: AppTheme.fontFamily
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ---------- v0.12 外观 ----------
            GlassCard {
                width: parent.width
                implicitHeight: appearanceColumn.implicitHeight + 36
                height: implicitHeight
                radius: 20
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: appearanceColumn
                    x: 20
                    y: 18
                    width: parent.width - 40
                    spacing: 12

                    Text {
                        text: qsTr("外观")
                        color: AppTheme.textPrimary
                        font.pixelSize: AppTheme.fs(15)
                        font.weight: Font.DemiBold
                        font.family: AppTheme.fontFamily
                    }

                    Row {
                        width: parent.width
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 88
                            text: qsTr("字号")
                            color: AppTheme.textSecondary
                            font.pixelSize: AppTheme.fs(12)
                            font.family: AppTheme.fontFamily
                        }
                        Repeater {
                            model: [
                                { value: 0.85, label: qsTr("小") },
                                { value: 1.0, label: qsTr("标准") },
                                { value: 1.15, label: qsTr("大") },
                                { value: 1.3, label: qsTr("特大") }
                            ]
                            delegate: GlassButton {
                                text: modelData.label
                                tone: Math.abs(page.currentFontScale - Number(modelData.value)) < 0.03 ? "light" : "ghost"
                                fontSize: AppTheme.fs(12)
                                padH: 16
                                minHeight: 32
                                selected: Math.abs(page.currentFontScale - Number(modelData.value)) < 0.03
                                onClicked: page.setFontScale(modelData.value)
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 72
                            text: qsTr("字体")
                            color: AppTheme.textSecondary
                            font.pixelSize: AppTheme.fs(12)
                            font.family: AppTheme.fontFamily
                        }
                        Item {
                            id: fontField
                            width: 240
                            height: 32
                            Rectangle {
                                anchors.fill: parent
                                radius: 9
                                color: AppTheme.cardBgAlt
                                border.width: 1
                                border.color: fontFieldArea.containsMouse ? AppTheme.accent : AppTheme.cardBorder
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.currentFontLabel
                                color: AppTheme.textPrimary
                                font.pixelSize: AppTheme.fs(12)
                                font.family: AppTheme.fontFamily
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "▾"
                                color: AppTheme.textTertiary
                                font.pixelSize: AppTheme.fs(12)
                                font.family: AppTheme.fontFamily
                            }
                            MouseArea {
                                id: fontFieldArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.fontMenuOpen = !page.fontMenuOpen
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("实时生效，无需重启")
                            color: AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(10)
                            font.family: AppTheme.fontFamily
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 120
                            text: qsTr("导航展开方式")
                            color: AppTheme.textSecondary
                            font.pixelSize: AppTheme.fs(12)
                            font.family: AppTheme.fontFamily
                        }
                        Repeater {
                            model: [
                                { value: "auto", label: qsTr("自动") },
                                { value: "expanded", label: qsTr("始终展开") },
                                { value: "icons", label: qsTr("仅图标") }
                            ]
                            delegate: GlassButton {
                                text: modelData.label
                                tone: page.currentNavMode === modelData.value ? "light" : "ghost"
                                fontSize: AppTheme.fs(12)
                                padH: 14
                                minHeight: 32
                                selected: page.currentNavMode === modelData.value
                                onClicked: page.setNavMode(modelData.value)
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: qsTr("字号与字体只影响界面显示；导航方式自动时会跟随窗口宽度。")
                        color: AppTheme.textTertiary
                        font.pixelSize: AppTheme.fs(10)
                        font.family: AppTheme.fontFamily
                        wrapMode: Text.WordWrap
                    }
                }

                // 字体下拉
                Item {
                    id: fontPopup
                    visible: page.fontMenuOpen
                    z: 40
                    x: fontField.x
                    y: fontField.y + fontField.height + 4
                    width: 240
                    height: Math.min(220, fontPopupColumn.height + 8)
                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: AppTheme.cardBg
                        border.width: 1
                        border.color: AppTheme.cardBorderStrong
                    }
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 4
                        contentWidth: width
                        contentHeight: fontPopupColumn.height
                        clip: true
                        Column {
                            id: fontPopupColumn
                            width: parent.width
                            spacing: 2
                            Repeater {
                                model: page.fontFamilyList
                                delegate: Item {
                                    width: parent.width
                                    height: 30
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(modelData.label)
                                        color: String(modelData.value) === page.currentFontValue
                                               ? AppTheme.accent : AppTheme.textSecondary
                                        font.pixelSize: AppTheme.fs(11)
                                        font.family: AppTheme.fontFamily
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            page.setFontFamily(String(modelData.value))
                                            page.fontMenuOpen = false
                                        }
                                    }
                                }
                            }
                        }
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
                        font.pixelSize: AppTheme.fs(15)
                        font.weight: Font.DemiBold
                        font.family: AppTheme.fontFamily
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        text: qsTr("%1 分钟").arg(page.draftDefaultMinutes)
                        color: AppTheme.textSecondary
                        font.pixelSize: AppTheme.fs(13)
                        font.family: AppTheme.fontFamily
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
                        font.pixelSize: AppTheme.fs(15)
                        font.weight: Font.DemiBold
                        font.family: AppTheme.fontFamily
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
                        font.pixelSize: AppTheme.fs(11)
                        font.family: AppTheme.fontFamily
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ---------- v0.10 AI 助手入口（配置与对话已迁移到独立 AI 页） ----------
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
                        color: AppTheme.accent
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: qsTr("AI 助手")
                            color: AppTheme.textPrimary
                            font.pixelSize: AppTheme.fs(13)
                            font.family: AppTheme.fontFamily
                        }
                        Text {
                            text: qsTr("服务商、模型与对话，已移到左侧「AI」页")
                            color: AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(11)
                            font.family: AppTheme.fontFamily
                        }
                    }
                }

                GlassButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("前往 AI 页")
                    tone: "ghost"
                    fontSize: 12
                    padH: 16
                    minHeight: 32
                    onClicked: page.aiPageRequested()
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
                            font.pixelSize: AppTheme.fs(15)
                            font.weight: Font.DemiBold
                            font.family: AppTheme.fontFamily
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
                        font.pixelSize: AppTheme.fs(11)
                        font.family: AppTheme.fontFamily
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
                                    font.pixelSize: AppTheme.fs(13)
                                    font.family: AppTheme.fontFamily
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
                                font.pixelSize: AppTheme.fs(13)
                                font.family: AppTheme.fontFamily
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
                            font.pixelSize: AppTheme.fs(11)
                            font.family: AppTheme.fontFamily
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
                                font.pixelSize: AppTheme.fs(12)
                                font.family: AppTheme.fontFamily
                            }

                            Item {
                                width: parent.width - 380
                                height: 1
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("连续点击时钟 10 次解锁")
                                color: AppTheme.textTertiary
                                font.pixelSize: AppTheme.fs(11)
                                font.family: AppTheme.fontFamily
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
                                font.pixelSize: AppTheme.fs(10)
                                font.family: AppTheme.fontFamily
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
                        font.pixelSize: AppTheme.fs(13)
                        font.family: AppTheme.fontFamily
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
                font.pixelSize: AppTheme.fs(12)
                font.family: AppTheme.fontFamily
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