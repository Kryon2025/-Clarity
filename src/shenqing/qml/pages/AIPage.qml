import QtQuick
import "../theme"
import "../components"
import "../glass"
import "../components/Constants.js" as C

// v0.10 AI 页：左侧配置（服务商 / 模型自动获取 / Base / Key / 测试），右侧内嵌 AI 对话。
Item {
    id: page

    property Item glassSource: null
    property bool animationsEnabled: true

    // ---------- 配置状态 ----------
    property bool localAIEnabled: false
    property bool providerMenuOpen: false
    property bool modelMenuOpen: false
    property int providerIndex: 0
    property string modelDraft: ""
    property string baseDraft: ""
    property string keyDraft: ""
    property string testText: ""
    property string testKind: "idle"
    property string localModelsError: ""
    property string query: ""
    property bool copied: false

    readonly property var providerList: {
        if (typeof App !== "undefined" && App.aiProviders !== undefined && App.aiProviders !== null
                && App.aiProviders.length > 0)
            return App.aiProviders
        return [
            { id: "deepseek", label: "DeepSeek", base: "https://api.deepseek.com/v1",
              models: ["deepseek-chat", "deepseek-reasoner"] },
            { id: "mimo", label: qsTr("小米 MiMo"), base: "https://api.xiaomi.com/v1",
              models: ["mimo-7b", "mimo-13b"] },
            { id: "openai", label: "ChatGPT", base: "https://api.openai.com/v1",
              models: ["gpt-4o-mini", "gpt-4o"] },
            { id: "groq", label: "Groq", base: "https://api.groq.com/openai/v1",
              models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"] },
            { id: "glm", label: qsTr("智谱 GLM"), base: "https://open.bigmodel.cn/api/paas/v4",
              models: ["glm-4.7-flash", "glm-4-flash"] },
            { id: "siliconflow", label: qsTr("硅基流动"), base: "https://api.siliconflow.cn/v1",
              models: ["Qwen/Qwen2.5-7B-Instruct", "deepseek-ai/DeepSeek-V3"] },
            { id: "custom", label: qsTr("自定义"), base: "", models: [] }
        ]
    }
    readonly property var currentProvider: {
        var list = page.providerList
        if (page.providerIndex < 0 || page.providerIndex >= list.length) return list[0]
        return list[page.providerIndex]
    }
    readonly property string providerLabel: (page.currentProvider.label !== undefined)
                                            ? String(page.currentProvider.label) : ""
    readonly property var modelCandidates: {
        if (typeof App !== "undefined" && App.aiModels !== undefined && App.aiModels !== null
                && App.aiModels.length > 0)
            return App.aiModels
        if (page.currentProvider.models !== undefined)
            return page.currentProvider.models
        return []
    }
    readonly property string modelsState: (typeof App !== "undefined" && App.aiModelsState !== undefined)
                                         ? String(App.aiModelsState) : ""
    readonly property string modelsError: {
        if (page.localModelsError !== "") return page.localModelsError
        return (typeof App !== "undefined" && App.aiModelsError !== undefined) ? String(App.aiModelsError) : ""
    }
    readonly property string modelsHint: {
        if (page.modelsState === "loading") return qsTr("正在获取模型列表…")
        if (page.modelsState === "error" && page.modelsError !== "") return page.modelsError
        if (page.modelCandidates.length > 0) return qsTr("共 %1 个模型").arg(page.modelCandidates.length)
        return qsTr("暂无模型列表，可手动输入")
    }
    readonly property bool aiEnabledValue: (typeof App !== "undefined" && App.aiEnabled !== undefined)
                                            ? App.aiEnabled === true : page.localAIEnabled
    readonly property string backendState: (typeof App !== "undefined" && App.aiState !== undefined)
                                           ? String(App.aiState) : ""
    readonly property string statusText: {
        if (page.backendState === "loading" && page.testKind === "testing") return qsTr("测试中…")
        if (page.backendState === "ok" && page.testKind === "testing") return qsTr("连接成功")
        if (page.backendState === "error" && page.testKind === "testing")
            return (typeof App !== "undefined" && App.aiError !== undefined && String(App.aiError) !== "")
                   ? String(App.aiError) : qsTr("连接失败")
        if (page.testText !== "") return page.testText
        if (typeof App !== "undefined" && App.aiConfigured === true) return qsTr("已配置")
        return qsTr("未配置")
    }
    readonly property string statusColor: {
        if (page.testKind === "ok") return AppTheme.accent
        if (page.testKind === "error") return AppTheme.danger
        if (page.backendState === "ok") return AppTheme.accent
        if (page.backendState === "error") return AppTheme.danger
        return AppTheme.textTertiary
    }

    readonly property bool configured: (typeof App !== "undefined") && App.aiConfigured === true
    readonly property string chatState: {
        if (typeof App !== "undefined" && App.aiState !== undefined) return String(App.aiState)
        return "idle"
    }
    readonly property string chatAnswer: (typeof App !== "undefined" && App.aiAnswer !== undefined)
                                          ? String(App.aiAnswer) : ""
    readonly property string chatError: (typeof App !== "undefined" && App.aiError !== undefined)
                                        ? String(App.aiError) : ""

    function init() {
        if (typeof App !== "undefined" && App.aiProvider !== undefined) {
            var list = page.providerList
            for (var i = 0; i < list.length; i++) {
                if (String(list[i].id) === String(App.aiProvider)) { page.providerIndex = i; break }
            }
        }
        var p = page.currentProvider
        page.baseDraft = (typeof App !== "undefined" && App.aiBase !== undefined && String(App.aiBase) !== "")
                         ? String(App.aiBase) : String(p.base || "")
        page.modelDraft = (typeof App !== "undefined" && App.aiModel !== undefined && String(App.aiModel) !== "")
                          ? String(App.aiModel)
                          : (p.models !== undefined && p.models.length > 0 ? String(p.models[0]) : "")
    }
    function toggleEnabled() {
        if (typeof App !== "undefined" && typeof App.setAIEnabled === "function")
            App.setAIEnabled(!page.aiEnabledValue)
        else
            page.localAIEnabled = !page.localAIEnabled
    }
    function selectProvider(index) {
        page.providerIndex = index
        page.providerMenuOpen = false
        var p = page.providerList[index]
        page.baseDraft = (p.base !== undefined) ? String(p.base) : ""
        page.localModelsError = ""
        var models = (p.models !== undefined) ? p.models : []
        page.modelDraft = models.length > 0 ? String(models[0]) : ""
        if (typeof App !== "undefined" && typeof App.setAIProvider === "function")
            App.setAIProvider(String(p.id))
        if (typeof App !== "undefined" && typeof App.setAIBase === "function")
            App.setAIBase(page.baseDraft)
        if (typeof App !== "undefined" && typeof App.setAIModel === "function" && page.modelDraft !== "")
            App.setAIModel(page.modelDraft)
    }
    function selectModel(name) {
        page.modelDraft = String(name)
        page.modelMenuOpen = false
        if (typeof App !== "undefined" && typeof App.setAIModel === "function")
            App.setAIModel(page.modelDraft)
    }
    function saveModel() {
        if (typeof App !== "undefined" && typeof App.setAIModel === "function")
            App.setAIModel(page.modelDraft)
    }
    function saveBase() {
        if (typeof App !== "undefined" && typeof App.setAIBase === "function")
            App.setAIBase(page.baseDraft)
    }
    function saveKey() {
        if (typeof App !== "undefined" && typeof App.setAIKey === "function" && page.keyDraft !== "")
            App.setAIKey(page.keyDraft)
    }
    function refreshModels() {
        page.localModelsError = ""
        if (typeof App !== "undefined" && typeof App.fetchAIModels === "function") {
            App.fetchAIModels()
        } else {
            page.localModelsError = qsTr("缺少模型获取接口（App.fetchAIModels）")
        }
    }
    function testConnection() {
        page.testKind = "testing"
        page.testText = ""
        if (typeof App !== "undefined" && typeof App.testAIConnection === "function")
            App.testAIConnection()
        else {
            page.testKind = "error"
            page.testText = qsTr("缺少测试接口（App.testAIConnection）")
        }
    }
    function send() {
        var text = String(page.query).trim()
        if (text.length === 0) return
        if (typeof App !== "undefined" && typeof App.aiAsk === "function")
            App.aiAsk(text)
    }
    function copyAnswer() {
        helper.text = page.chatAnswer
        helper.selectAll()
        helper.copy()
        page.copied = true
        copyTimer.restart()
    }

    Component.onCompleted: init()
    Timer {
        id: copyTimer
        interval: 1600
        onTriggered: page.copied = false
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.height + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: pageColumn
            width: Math.min(flick.width - 84, 900)
            x: (flick.width - width) / 2
            y: 22
            spacing: 14

            Item {
                width: parent.width
                height: 68
                Column {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 5
                    Text {
                        text: qsTr("AI")
                        color: AppTheme.textPrimary
                        font.pixelSize: 30
                        font.weight: Font.Bold
                        font.family: C.numFont
                        font.letterSpacing: 1
                    }
                    Text {
                        text: qsTr("配置服务商与模型，然后在右侧直接对话")
                        color: AppTheme.textSecondary
                        font.pixelSize: 13
                        font.family: C.numFont
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 14

                // ---------- 配置卡片 ----------
                GlassCard {
                    width: Math.round((pageColumn.width - 14) * 0.47)
                    height: Math.max(520, configColumn.implicitHeight + 40)
                    radius: 22
                    interactive: false
                    glassSource: page.glassSource

                    Item {
                        anchors.fill: parent
                        anchors.margins: 18

                        Column {
                            id: configColumn
                            width: parent.width
                            spacing: 10

                            Row {
                                width: parent.width
                                spacing: 8
                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    kind: "sparkle"
                                    size: 16
                                    color: AppTheme.accent
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("AI 设置")
                                    color: AppTheme.textPrimary
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    font.family: C.numFont
                                }
                                Item { width: parent.width - 150; height: 1 }
                                GlassSwitch {
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: page.aiEnabledValue
                                    onClicked: page.toggleEnabled()
                                }
                            }

                            Text {
                                width: parent.width
                                text: qsTr("Key 只保存在本机；模型列表可自动获取，也可手动输入。")
                                color: AppTheme.textTertiary
                                font.pixelSize: 11
                                font.family: C.numFont
                                wrapMode: Text.WordWrap
                            }

                            Rectangle { width: parent.width; height: 1; color: AppTheme.divider }

                            // 服务商
                            Item {
                                width: parent.width
                                height: 34
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("服务商")
                                    color: AppTheme.textSecondary
                                    font.pixelSize: 12
                                    font.family: C.numFont
                                    width: 66
                                }
                                Item {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 66
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 66
                                    height: 32
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 9
                                        color: AppTheme.cardBgAlt
                                        border.width: 1
                                        border.color: providerArea.containsMouse ? AppTheme.accent : AppTheme.cardBorder
                                    }
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: page.providerLabel
                                        color: AppTheme.textPrimary
                                        font.pixelSize: 12
                                        font.family: C.numFont
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "▾"
                                        color: AppTheme.textTertiary
                                        font.pixelSize: 12
                                    }
                                    MouseArea {
                                        id: providerArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            page.providerMenuOpen = !page.providerMenuOpen
                                            page.modelMenuOpen = false
                                        }
                                    }
                                }
                            }

                            // 模型
                            Item {
                                width: parent.width
                                height: 34
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("模型")
                                    color: AppTheme.textSecondary
                                    font.pixelSize: 12
                                    font.family: C.numFont
                                    width: 66
                                }
                                Item {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 66
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 66
                                    height: 32
                                    TextInput {
                                        id: modelInput
                                        anchors.left: parent.left
                                        anchors.right: modelChevron.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 32
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: AppTheme.textPrimary
                                        selectionColor: AppTheme.accentSoft
                                        selectedTextColor: "#FFFFFF"
                                        font.pixelSize: 12
                                        font.family: C.monoFont
                                        text: page.modelDraft
                                        onTextChanged: page.modelDraft = text
                                        onEditingFinished: page.saveModel()
                                        Rectangle {
                                            anchors.fill: parent
                                            z: -1
                                            radius: 9
                                            color: AppTheme.cardBgAlt
                                            border.width: 1
                                            border.color: modelInput.activeFocus ? AppTheme.accent : AppTheme.cardBorder
                                        }
                                    }
                                    Item {
                                        id: modelChevron
                                        anchors.right: refreshButton.left
                                        anchors.rightMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 22
                                        height: 32
                                        Text {
                                            anchors.centerIn: parent
                                            text: "▾"
                                            color: AppTheme.textTertiary
                                            font.pixelSize: 12
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                page.modelMenuOpen = !page.modelMenuOpen
                                                page.providerMenuOpen = false
                                            }
                                        }
                                    }
                                    Item {
                                        id: refreshButton
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 58
                                        height: 32
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 9
                                            color: refreshArea.containsMouse ? AppTheme.cardBgAlt : "transparent"
                                            border.width: 1
                                            border.color: AppTheme.cardBorder
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: page.modelsState === "loading" ? qsTr("获取中") : qsTr("刷新")
                                            color: refreshArea.containsMouse ? AppTheme.accent : AppTheme.textSecondary
                                            font.pixelSize: 11
                                            font.family: C.numFont
                                        }
                                        MouseArea {
                                            id: refreshArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: page.refreshModels()
                                        }
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: page.modelsHint !== ""
                                text: page.modelsHint
                                color: page.modelsState === "error" || page.localModelsError !== ""
                                       ? AppTheme.danger : AppTheme.textTertiary
                                font.pixelSize: 10
                                font.family: C.numFont
                                wrapMode: Text.WordWrap
                            }

                            // API Base
                            Item {
                                width: parent.width
                                height: 34
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("API Base")
                                    color: AppTheme.textSecondary
                                    font.pixelSize: 12
                                    font.family: C.numFont
                                    width: 66
                                }
                                TextInput {
                                    id: baseInput
                                    anchors.left: parent.left
                                    anchors.leftMargin: 66
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 66
                                    height: 32
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: AppTheme.textPrimary
                                    selectionColor: AppTheme.accentSoft
                                    selectedTextColor: "#FFFFFF"
                                    font.pixelSize: 11
                                    font.family: C.monoFont
                                    text: page.baseDraft
                                    onTextChanged: page.baseDraft = text
                                    onEditingFinished: page.saveBase()
                                    Rectangle {
                                        anchors.fill: parent
                                        z: -1
                                        radius: 9
                                        color: AppTheme.cardBgAlt
                                        border.width: 1
                                        border.color: baseInput.activeFocus ? AppTheme.accent : AppTheme.cardBorder
                                    }
                                }
                            }

                            // API Key
                            Item {
                                width: parent.width
                                height: 34
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("API Key")
                                    color: AppTheme.textSecondary
                                    font.pixelSize: 12
                                    font.family: C.numFont
                                    width: 66
                                }
                                TextInput {
                                    id: keyInput
                                    anchors.left: parent.left
                                    anchors.leftMargin: 66
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 66
                                    height: 32
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: AppTheme.textPrimary
                                    selectionColor: AppTheme.accentSoft
                                    selectedTextColor: "#FFFFFF"
                                    font.pixelSize: 12
                                    font.family: C.monoFont
                                    echoMode: TextInput.Password
                                    passwordCharacter: "•"
                                    text: page.keyDraft
                                    onTextChanged: page.keyDraft = text
                                    onEditingFinished: page.saveKey()
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: keyInput.text.length === 0
                                        text: (typeof App !== "undefined" && App.aiHasKey === true)
                                              ? qsTr("已保存，留空不修改") : qsTr("输入 API Key")
                                        color: AppTheme.textTertiary
                                        font.pixelSize: 11
                                        font.family: C.numFont
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        z: -1
                                        radius: 9
                                        color: AppTheme.cardBgAlt
                                        border.width: 1
                                        border.color: keyInput.activeFocus ? AppTheme.accent : AppTheme.cardBorder
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 10
                                GlassButton {
                                    text: page.testKind === "testing" ? qsTr("测试中…") : qsTr("测试连接")
                                    tone: "ghost"
                                    fontSize: 12
                                    padH: 16
                                    minHeight: 32
                                    enabled: page.testKind !== "testing"
                                    onClicked: page.testConnection()
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 180
                                    text: page.statusText
                                    color: page.statusColor
                                    font.pixelSize: 11
                                    font.family: C.numFont
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // 服务商 / 模型下拉浮层
                        Item {
                            id: providerPopup
                            visible: page.providerMenuOpen
                            z: 30
                            x: 66
                            y: 108
                            width: parent.width - 66
                            height: providerListColumn.height + 8
                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: AppTheme.cardBg
                                border.width: 1
                                border.color: AppTheme.cardBorderStrong
                            }
                            Column {
                                id: providerListColumn
                                x: 6
                                y: 4
                                width: parent.width - 12
                                spacing: 2
                                Repeater {
                                    model: page.providerList
                                    delegate: Item {
                                        width: parent.width
                                        height: 30
                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: String(modelData.label)
                                            color: page.providerIndex === index ? AppTheme.accent : AppTheme.textSecondary
                                            font.pixelSize: 12
                                            font.family: C.numFont
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: page.selectProvider(index)
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            id: modelPopup
                            visible: page.modelMenuOpen
                            z: 30
                            x: 66
                            y: 142
                            width: parent.width - 66
                            height: Math.min(220, modelListColumn.height + 8)
                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: AppTheme.cardBg
                                border.width: 1
                                border.color: AppTheme.cardBorderStrong
                            }
                            Flickable {
                                anchors.fill: parent
                                anchors.margins: 4
                                contentWidth: width
                                contentHeight: modelListColumn.height
                                clip: true
                                Column {
                                    id: modelListColumn
                                    width: parent.width
                                    spacing: 2
                                    Repeater {
                                        model: page.modelCandidates
                                        delegate: Item {
                                            width: parent.width
                                            height: 30
                                            Text {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 10
                                                width: parent.width - 20
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: String(modelData)
                                                color: page.modelDraft === String(modelData)
                                                       ? AppTheme.accent : AppTheme.textSecondary
                                                font.pixelSize: 11
                                                font.family: C.monoFont
                                                elide: Text.ElideRight
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: page.selectModel(modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------- 对话卡片 ----------
                GlassCard {
                    width: pageColumn.width - Math.round((pageColumn.width - 14) * 0.47) - 14
                    height: 520
                    radius: 22
                    interactive: false
                    glassSource: page.glassSource

                    Item {
                        anchors.fill: parent
                        anchors.margins: 18

                        Column {
                            width: parent.width
                            spacing: 10

                            Row {
                                width: parent.width
                                spacing: 8
                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    kind: "sparkle"
                                    size: 15
                                    color: AppTheme.accent
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("对话")
                                    color: AppTheme.textPrimary
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    font.family: C.numFont
                                }
                                Item { width: parent.width - 160; height: 1 }
                                Text {
                                    visible: page.chatState === "ok"
                                    text: page.copied ? qsTr("已复制") : qsTr("复制全文")
                                    color: copyArea.containsMouse ? AppTheme.accent : AppTheme.textTertiary
                                    font.pixelSize: 11
                                    font.family: C.numFont
                                    MouseArea {
                                        id: copyArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: page.copyAnswer()
                                    }
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: AppTheme.divider }

                            Item {
                                width: parent.width
                                height: 338

                                Flickable {
                                    anchors.fill: parent
                                    contentWidth: width
                                    contentHeight: answerColumn.height
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds

                                    Column {
                                        id: answerColumn
                                        width: parent.width
                                        spacing: 10

                                        Text {
                                            visible: !page.configured
                                            width: parent.width
                                            text: qsTr("还没有配置 AI 助手。\n请在左侧填写服务商与 API Key，然后发送消息。")
                                            color: AppTheme.textSecondary
                                            font.pixelSize: 12
                                            font.family: C.numFont
                                            wrapMode: Text.WordWrap
                                            lineHeight: 1.5
                                        }

                                        Row {
                                            visible: page.configured && page.chatState === "loading"
                                            spacing: 9
                                            Rectangle {
                                                width: 16; height: 16; radius: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: "transparent"
                                                border.width: 2
                                                border.color: AppTheme.accent
                                                opacity: 0.4
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: qsTr("思考中…")
                                                color: AppTheme.textSecondary
                                                font.pixelSize: 12
                                                font.family: C.numFont
                                            }
                                        }

                                        TextEdit {
                                            visible: page.configured && page.chatState === "ok"
                                            width: parent.width
                                            text: page.chatAnswer
                                            readOnly: true
                                            textFormat: TextEdit.PlainText
                                            wrapMode: TextEdit.Wrap
                                            color: AppTheme.textPrimary
                                            selectionColor: AppTheme.accentSoft
                                            selectedTextColor: "#FFFFFF"
                                            font.pixelSize: 13
                                            font.family: C.numFont
                                            selectByMouse: true
                                        }

                                        Text {
                                            visible: page.configured && page.chatState === "error"
                                            width: parent.width
                                            text: page.chatError !== "" ? page.chatError : qsTr("AI 请求失败")
                                            color: AppTheme.danger
                                            font.pixelSize: 12
                                            font.family: C.numFont
                                            wrapMode: Text.WordWrap
                                        }

                                        Text {
                                            visible: page.configured && page.chatState === "idle"
                                            width: parent.width
                                            text: qsTr("把问题交给深清：可以问专注方法、帮你整理思路，或随便聊聊。")
                                            color: AppTheme.textTertiary
                                            font.pixelSize: 12
                                            font.family: C.numFont
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 8
                                Item {
                                    width: parent.width - 86
                                    height: 38
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 12
                                        color: AppTheme.cardBgAlt
                                        border.width: 1
                                        border.color: chatInput.activeFocus ? AppTheme.accent : AppTheme.cardBorder
                                    }
                                    TextInput {
                                        id: chatInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: AppTheme.textPrimary
                                        selectionColor: AppTheme.accentSoft
                                        selectedTextColor: "#FFFFFF"
                                        font.pixelSize: 12
                                        font.family: C.numFont
                                        enabled: page.configured
                                        text: page.query
                                        onTextChanged: page.query = text
                                        onAccepted: page.send()
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: chatInput.text.length === 0
                                            text: page.configured ? qsTr("问点什么…（Enter 发送）")
                                                                  : qsTr("请先在左侧配置 AI")
                                            color: AppTheme.textTertiary
                                            font.pixelSize: 12
                                            font.family: C.numFont
                                        }
                                    }
                                }
                                Item {
                                    width: 78
                                    height: 38
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 19
                                        color: sendArea.containsMouse ? AppTheme.accentSoft : AppTheme.accent
                                        opacity: page.configured ? 1 : 0.4
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: qsTr("发送")
                                        color: "#FFFFFF"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        font.family: C.numFont
                                    }
                                    MouseArea {
                                        id: sendArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: page.configured
                                        onClicked: page.send()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    TextEdit {
        id: helper
        visible: false
        width: 1
        height: 1
    }
}
