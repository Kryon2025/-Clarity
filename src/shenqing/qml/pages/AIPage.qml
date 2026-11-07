import QtQuick
import "../theme"
import "../components"
import "../glass"
import "../components/Constants.js" as C

Item {
    id: page
    property Item glassSource: null
    property bool animationsEnabled: true
    property bool configOpen: false
    property bool providerMenuOpen: false
    property bool modelMenuOpen: false
    property int providerIndex: 0
    property string modelDraft: ""
    property string baseDraft: ""
    property string keyDraft: ""
    property string testText: ""
    property string testKind: "idle"
    property string localModelsError: ""
    property bool localReasoning: false
    property bool localWebSearch: false
    property string query: ""
    property bool copied: false
    property string expandedReasoningKey: ""
    property string currentConversationId: ""
    property var demoConversations: null
    property var demoMessages: null
    property var demoLastUsage: null
    property int demoTodayTokens: -1
    property real demoTodayCost: -1
    property string demoCurrency: ""

    readonly property var providerList: {
        var source = (typeof App !== "undefined" && App.aiProviders !== undefined && App.aiProviders !== null
                      && App.aiProviders.length > 0) ? App.aiProviders : [
            { id: "deepseek", label: "DeepSeek", base: "https://api.deepseek.com/v1",
              models: ["deepseek-chat", "deepseek-reasoner"], capabilities: ["reasoning"] },
            { id: "mimo", label: qsTr("小米 MiMo"), base: "https://api.xiaomimimo.com/v1",
              models: ["mimo-v2.6-flash", "mimo-v2.6-pro"] },
            { id: "openai", label: "ChatGPT", base: "https://api.openai.com/v1",
              models: ["gpt-4o-mini", "gpt-4o"], capabilities: ["webSearch"] },
            { id: "groq", label: "Groq", base: "https://api.groq.com/openai/v1",
              models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"] },
            { id: "glm", label: qsTr("智谱 GLM"), base: "https://open.bigmodel.cn/api/paas/v4",
              models: ["glm-4.7-flash", "glm-4-flash"], capabilities: ["reasoning", "webSearch"] },
            { id: "siliconflow", label: qsTr("硅基流动"), base: "https://api.siliconflow.cn/v1",
              models: ["Qwen/Qwen2.5-7B-Instruct", "deepseek-ai/DeepSeek-V3"] },
            { id: "custom", label: qsTr("自定义"), base: "", models: [] }
        ]
        var hasFree = false
        for (var i = 0; i < source.length; i++) {
            var item = source[i]
            if (String(item.id) === "free" || item.free === true || item.noConfig === true
                    || String(item.label).indexOf(qsTr("免配置")) >= 0) {
                hasFree = true
                break
            }
        }
        if (hasFree) return source
        var out = [{ id: "free", label: qsTr("免费直连（免配置）"), base: "", free: true,
                     models: ["deepseek-chat", "glm-4-flash"], capabilities: ["reasoning"] }]
        for (var j = 0; j < source.length; j++) out.push(source[j])
        return out
    }
    readonly property var currentProvider: {
        var list = page.providerList
        return (page.providerIndex >= 0 && page.providerIndex < list.length) ? list[page.providerIndex] : list[0]
    }
    readonly property string providerLabel: (page.currentProvider.label !== undefined) ? String(page.currentProvider.label) : ""
    readonly property bool freeProvider: page.currentProvider.needs_key === false
                                          || String(page.currentProvider.id) === "free"
                                          || String(page.currentProvider.id) === "pollinations"
                                          || page.currentProvider.free === true
                                          || page.currentProvider.noConfig === true
                                          || page.currentProvider.mode === "free"
                                          || String(page.currentProvider.label).indexOf(qsTr("免配置")) >= 0
    readonly property bool reasoningSupported: (typeof App !== "undefined" && App.aiSupportsReasoning !== undefined)
                                               ? App.aiSupportsReasoning === true
                                               : page.providerFlag("reasoning")
    readonly property bool webSupported: (typeof App !== "undefined" && App.aiSupportsWebSearch !== undefined)
                                         ? App.aiSupportsWebSearch === true
                                         : page.providerFlag("webSearch")
    readonly property bool reasoningEnabled: (typeof App !== "undefined" && App.aiReasoningEnabled !== undefined)
                                             ? App.aiReasoningEnabled === true : page.localReasoning
    readonly property bool webEnabled: (typeof App !== "undefined" && App.aiWebSearchEnabled !== undefined)
                                       ? App.aiWebSearchEnabled === true : page.localWebSearch

    function providerFlag(name) {
        var p = page.currentProvider
        if (!p) return false
        var caps = p.capabilities
        if (caps !== undefined && caps !== null) {
            if (typeof caps === "object" && caps[name] !== undefined) return caps[name] === true
            if (caps.length !== undefined)
                for (var i = 0; i < caps.length; i++)
                    if (String(caps[i]) === name) return true
        }
        if (name === "reasoning") {
            if (p.supports_reasoning !== undefined) return p.supports_reasoning === true
            if (p.supportsReasoning !== undefined) return p.supportsReasoning === true
            return ["pollinations", "free", "deepseek", "glm", "siliconflow"].indexOf(String(p.id)) >= 0
        }
        if (p.supports_web_search !== undefined) return p.supports_web_search === true
        if (p.supportsWebSearch !== undefined) return p.supportsWebSearch === true
        return ["pollinations", "free", "openai", "glm"].indexOf(String(p.id)) >= 0
    }

    readonly property var modelCandidates: {
        if (typeof App !== "undefined" && App.aiModels !== undefined && App.aiModels !== null
                && App.aiModels.length > 0)
            return App.aiModels
        return (page.currentProvider.models !== undefined) ? page.currentProvider.models : []
    }
    readonly property string modelsState: (typeof App !== "undefined" && App.aiModelsState !== undefined)
                                         ? String(App.aiModelsState) : ""
    readonly property string modelsError: page.localModelsError !== "" ? page.localModelsError
                                         : ((typeof App !== "undefined" && App.aiModelsError !== undefined)
                                            ? String(App.aiModelsError) : "")
    readonly property string modelsHint: page.modelsState === "loading" ? qsTr("正在获取模型列表…")
                                         : (page.modelsState === "error" && page.modelsError !== "" ? page.modelsError
                                            : (page.modelCandidates.length > 0
                                               ? qsTr("共 %1 个模型").arg(page.modelCandidates.length)
                                               : qsTr("暂无模型列表，可手动输入")))

    readonly property var conversations: page.demoConversations !== null ? page.demoConversations
                                        : ((typeof App !== "undefined" && App.aiConversations !== undefined)
                                           ? App.aiConversations : [])
    readonly property var messages: page.demoMessages !== null ? page.demoMessages
                                   : ((typeof App !== "undefined" && App.aiMessages !== undefined) ? App.aiMessages : [])
    readonly property int messageCount: page.messages !== null ? page.messages.length : 0
    readonly property var lastUsage: page.demoLastUsage !== null ? page.demoLastUsage
                                     : ((typeof App !== "undefined" && App.aiLastUsage !== undefined) ? App.aiLastUsage : ({}))
    readonly property int todayTokens: page.demoTodayTokens >= 0 ? page.demoTodayTokens
                                       : ((typeof App !== "undefined" && App.aiTodayTokens !== undefined) ? Number(App.aiTodayTokens) : 0)
    readonly property real todayCost: page.demoTodayCost >= 0 ? page.demoTodayCost
                                      : ((typeof App !== "undefined" && App.aiTodayCost !== undefined) ? Number(App.aiTodayCost) : 0)
    readonly property string currency: page.demoCurrency !== "" ? page.demoCurrency
                                       : ((typeof App !== "undefined" && App.aiCurrency !== undefined
                                           && String(App.aiCurrency) !== "") ? String(App.aiCurrency) : "CNY")
    readonly property string costSymbol: page.currency === "CNY" ? "¥" : page.currency + " "
    readonly property bool configured: page.freeProvider
                                       || ((typeof App !== "undefined") && App.aiConfigured === true)
    readonly property string chatState: (typeof App !== "undefined" && App.aiState !== undefined) ? String(App.aiState) : "idle"
    readonly property string chatAnswer: (typeof App !== "undefined" && App.aiAnswer !== undefined) ? String(App.aiAnswer) : ""
    readonly property string chatError: (typeof App !== "undefined" && App.aiError !== undefined) ? String(App.aiError) : ""

    function messageRole(m) { return (m !== null && m.role !== undefined) ? String(m.role) : "assistant" }
    function messageContent(m) { return (m !== null && m.content !== undefined) ? String(m.content) : "" }
    function messageReasoning(m) { return (m !== null && m.reasoning !== undefined) ? String(m.reasoning) : "" }
    function messageKey(i) { return page.currentConversationId + "#" + i }
    function toggleReasoningMessage(i) {
        var key = page.messageKey(i)
        page.expandedReasoningKey = page.expandedReasoningKey === key ? "" : key
    }
    function usageText() {
        var tokens = Number(page.lastUsage.tokens !== undefined ? page.lastUsage.tokens
                        : (page.lastUsage.totalTokens !== undefined ? page.lastUsage.totalTokens
                           : (Number(page.lastUsage.prompt_tokens || 0) + Number(page.lastUsage.completion_tokens || 0))))
        var cost = Number(page.lastUsage.cost !== undefined ? page.lastUsage.cost : 0)
        var currency = (page.lastUsage.currency !== undefined && String(page.lastUsage.currency) !== "")
                       ? String(page.lastUsage.currency) : page.currency
        var symbol = currency === "CNY" ? "¥" : (currency === "USD" ? "$" : currency + " ")
        return (tokens <= 0 && cost <= 0) ? ""
               : qsTr("上次回复 %1 tokens · %2%3（估算）").arg(tokens).arg(symbol).arg(cost.toFixed(4))
    }
    function init() {
        if (typeof App !== "undefined" && App.aiProvider !== undefined) {
            for (var i = 0; i < page.providerList.length; i++)
                if (String(page.providerList[i].id) === String(App.aiProvider)) { page.providerIndex = i; break }
        }
        var p = page.currentProvider
        page.baseDraft = (typeof App !== "undefined" && App.aiBase !== undefined && String(App.aiBase) !== "")
                         ? String(App.aiBase) : String(p.base || "")
        page.modelDraft = (typeof App !== "undefined" && App.aiModel !== undefined && String(App.aiModel) !== "")
                          ? String(App.aiModel) : (p.models && p.models.length > 0 ? String(p.models[0]) : "")
    }
    function toggleEnabled() {
        if (typeof App !== "undefined" && typeof App.setAIEnabled === "function")
            App.setAIEnabled(!(typeof App !== "undefined" && App.aiEnabled === true))
    }
    function selectProvider(i) {
        page.providerIndex = i
        page.providerMenuOpen = false
        page.modelMenuOpen = false
        var p = page.providerList[i]
        page.baseDraft = (p.base !== undefined) ? String(p.base) : ""
        page.localModelsError = ""
        page.modelDraft = (p.models && p.models.length > 0) ? String(p.models[0]) : ""
        if (typeof App !== "undefined" && typeof App.setAIProvider === "function") App.setAIProvider(String(p.id))
        if (typeof App !== "undefined" && typeof App.setAIBase === "function" && !page.freeProvider) App.setAIBase(page.baseDraft)
        if (typeof App !== "undefined" && typeof App.setAIModel === "function" && page.modelDraft !== "") App.setAIModel(page.modelDraft)
        if (typeof App !== "undefined" && typeof App.fetchAIModels === "function"
                && (page.freeProvider || App.aiConfigured === true)) App.fetchAIModels()
    }
    function selectModel(name) {
        page.modelDraft = String(name)
        page.modelMenuOpen = false
        if (typeof App !== "undefined" && typeof App.setAIModel === "function") App.setAIModel(page.modelDraft)
    }
    function saveModel() { if (typeof App !== "undefined" && typeof App.setAIModel === "function") App.setAIModel(page.modelDraft) }
    function saveBase() { if (typeof App !== "undefined" && typeof App.setAIBase === "function") App.setAIBase(page.baseDraft) }
    function saveKey() { if (typeof App !== "undefined" && typeof App.setAIKey === "function" && page.keyDraft !== "") App.setAIKey(page.keyDraft) }
    function refreshModels() {
        page.localModelsError = ""
        if (typeof App !== "undefined" && typeof App.fetchAIModels === "function") App.fetchAIModels()
        else page.localModelsError = qsTr("缺少模型获取接口（App.fetchAIModels）")
    }
    function testConnection() {
        page.testKind = "testing"
        page.testText = ""
        if (typeof App !== "undefined" && typeof App.testAIConnection === "function") App.testAIConnection()
        else { page.testKind = "error"; page.testText = qsTr("缺少测试接口（App.testAIConnection）") }
    }
    function toggleReasoning() {
        if (typeof App !== "undefined" && typeof App.setAIReasoningEnabled === "function")
            App.setAIReasoningEnabled(!page.reasoningEnabled)
        else page.localReasoning = !page.localReasoning
    }
    function toggleWebSearch() {
        if (typeof App !== "undefined" && typeof App.setAIWebSearchEnabled === "function")
            App.setAIWebSearchEnabled(!page.webEnabled)
        else page.localWebSearch = !page.localWebSearch
    }
    function newConversation() {
        page.currentConversationId = ""
        if (typeof App !== "undefined" && typeof App.newAIConversation === "function") App.newAIConversation()
    }
    function selectConversation(id) {
        page.currentConversationId = String(id)
        page.expandedReasoningKey = ""
        if (typeof App !== "undefined" && typeof App.selectAIConversation === "function") App.selectAIConversation(String(id))
    }
    function deleteConversation(id) {
        if (page.currentConversationId === String(id)) page.currentConversationId = ""
        if (typeof App !== "undefined" && typeof App.deleteAIConversation === "function") App.deleteAIConversation(String(id))
    }
    function send() {
        var text = String(page.query).trim()
        if (text.length === 0 || !page.configured) return
        if (typeof App !== "undefined" && typeof App.aiAsk === "function") App.aiAsk(text)
    }
    function resetUsage() {
        if (typeof App !== "undefined" && typeof App.resetAIUsage === "function") App.resetAIUsage()
    }

    Component.onCompleted: init()
    onMessageCountChanged: scrollTimer.restart()
    Timer { id: scrollTimer; interval: 60; onTriggered: messageFlick.contentY = Math.max(0, messageFlick.contentHeight - messageFlick.height) }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.height + 36
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: pageColumn
            width: Math.min(flick.width - 72, 940)
            x: (flick.width - width) / 2
            y: 18
            spacing: 12

            Item {
                width: parent.width
                height: 62
                Column {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 4
                    Text { text: qsTr("AI"); color: AppTheme.textPrimary; font.pixelSize: 28; font.weight: Font.Bold; font.family: C.numFont }
                    Text { text: qsTr("对话、历史与用量都在这里"); color: AppTheme.textSecondary; font.pixelSize: 12; font.family: C.numFont }
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    width: usageHeader.implicitWidth + 24
                    height: 30
                    radius: 15
                    color: AppTheme.glass ? "#1AFFFFFF" : AppTheme.cardBgAlt
                    border.width: 1
                    border.color: AppTheme.cardBorder
                    Text {
                        id: usageHeader
                        anchors.centerIn: parent
                        text: qsTr("今日 %1 tokens · %2%3（估算）").arg(page.todayTokens).arg(page.costSymbol).arg(Number(page.todayCost).toFixed(2))
                        color: AppTheme.textSecondary
                        font.pixelSize: 11
                        font.family: C.numFont
                    }
                }
            }

            // 会话列表
            Item {
                width: parent.width
                height: 38
                Flickable {
                    anchors.left: parent.left
                    anchors.right: newConversationButton.left
                    anchors.rightMargin: 10
                    height: parent.height
                    contentWidth: conversationRow.width
                    contentHeight: height
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    Row {
                        id: conversationRow
                        spacing: 8
                        Repeater {
                            model: page.conversations
                            delegate: Item {
                                width: Math.min(170, conversationTitle.implicitWidth + 52)
                                height: 34
                                readonly property bool selected: String(modelData.id) === page.currentConversationId
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 17
                                    color: selected ? AppTheme.accentSoft : (conversationArea.containsMouse ? AppTheme.cardBgAlt : AppTheme.cardBg)
                                    border.width: 1
                                    border.color: selected ? AppTheme.accent : AppTheme.cardBorder
                                }
                                Text {
                                    id: conversationTitle
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.right: deleteIcon.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (modelData.title !== undefined) ? String(modelData.title) : qsTr("新会话")
                                    color: selected ? AppTheme.accent : AppTheme.textSecondary
                                    font.pixelSize: 12
                                    font.family: C.numFont
                                    elide: Text.ElideRight
                                }
                                Item {
                                    id: deleteIcon
                                    visible: conversationArea.containsMouse || selected
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    height: 18
                                    Glyph { anchors.centerIn: parent; kind: "close"; size: 9; color: deleteArea.containsMouse ? AppTheme.danger : AppTheme.textTertiary }
                                    MouseArea { id: deleteArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.deleteConversation(modelData.id) }
                                }
                                MouseArea { id: conversationArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.selectConversation(modelData.id) }
                            }
                        }
                        Text {
                            visible: page.conversations.length === 0
                            text: qsTr("还没有会话，点右侧「新对话」开始")
                            color: AppTheme.textTertiary
                            font.pixelSize: 11
                            font.family: C.numFont
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
                Item {
                    id: newConversationButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 96
                    height: 34
                    Rectangle { anchors.fill: parent; radius: 17; color: newConversationArea.containsMouse ? AppTheme.accentSoft : AppTheme.accent }
                    Text { anchors.centerIn: parent; text: qsTr("＋ 新对话"); color: "#FFFFFF"; font.pixelSize: 12; font.weight: Font.DemiBold; font.family: C.numFont }
                    MouseArea { id: newConversationArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.newConversation() }
                }
            }

            Row {
                width: parent.width
                height: 470
                spacing: 14

                GlassCard {
                    width: pageColumn.width - (page.configOpen ? 314 : 0)
                    height: 470
                    radius: 22
                    interactive: false
                    glassSource: page.glassSource

                    Item {
                        anchors.fill: parent
                        anchors.margins: 16
                        Column {
                            width: parent.width
                            spacing: 10
                            Row {
                                width: parent.width
                                spacing: 8
                                Item {
                                    width: Math.min(240, providerButtonText.implicitWidth + (page.freeProvider ? 92 : 56))
                                    height: 32
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 9
                                        color: providerButtonArea.containsMouse ? AppTheme.cardBgAlt : AppTheme.cardBg
                                        border.width: 1
                                        border.color: page.providerMenuOpen ? AppTheme.accent : AppTheme.cardBorder
                                    }
                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6
                                        Text { id: providerButtonText; text: page.providerLabel; color: AppTheme.textPrimary; font.pixelSize: 12; font.family: C.numFont }
                                        Rectangle {
                                            visible: page.freeProvider
                                            width: 40
                                            height: 16
                                            radius: 8
                                            color: "#1FA36B"
                                            Text { anchors.centerIn: parent; text: qsTr("免配置"); color: "#FFFFFF"; font.pixelSize: 9; font.family: C.numFont }
                                        }
                                    }
                                    Text { anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter; text: "▾"; color: AppTheme.textTertiary; font.pixelSize: 11 }
                                    MouseArea { id: providerButtonArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.providerMenuOpen = !page.providerMenuOpen }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (page.reasoningSupported ? qsTr("思考") : "") + (page.reasoningSupported && page.webSupported ? " · " : "") + (page.webSupported ? qsTr("联网") : "")
                                    color: AppTheme.textTertiary
                                    font.pixelSize: 10
                                    font.family: C.numFont
                                }
                                Item { width: parent.width - 520; height: 1 }
                                Row {
                                    visible: page.reasoningSupported
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 5
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("思考"); color: page.reasoningEnabled ? AppTheme.accent : AppTheme.textTertiary; font.pixelSize: 11; font.family: C.numFont }
                                    GlassSwitch { anchors.verticalCenter: parent.verticalCenter; checked: page.reasoningEnabled; onClicked: page.toggleReasoning() }
                                }
                                Row {
                                    visible: page.webSupported
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 5
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("联网"); color: page.webEnabled ? AppTheme.accent : AppTheme.textTertiary; font.pixelSize: 11; font.family: C.numFont }
                                    GlassSwitch { anchors.verticalCenter: parent.verticalCenter; checked: page.webEnabled; onClicked: page.toggleWebSearch() }
                                }
                                Item {
                                    width: 30
                                    height: 30
                                    anchors.verticalCenter: parent.verticalCenter
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 15
                                        color: configArea.containsMouse ? AppTheme.cardBgAlt : "transparent"
                                        border.width: 1
                                        border.color: page.configOpen ? AppTheme.accent : AppTheme.cardBorder
                                    }
                                    Glyph { anchors.centerIn: parent; kind: "gear"; size: 13; color: page.configOpen ? AppTheme.accent : AppTheme.textSecondary }
                                    MouseArea { id: configArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.configOpen = !page.configOpen }
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: AppTheme.divider }

                            Item {
                                width: parent.width
                                height: 300
                                Flickable {
                                    id: messageFlick
                                    anchors.fill: parent
                                    contentWidth: width
                                    contentHeight: messageColumn.height
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    Column {
                                        id: messageColumn
                                        width: messageFlick.width
                                        spacing: 10
                                        Repeater {
                                            model: page.messages
                                            delegate: Item {
                                                width: messageColumn.width
                                                height: bubbleItem.height
                                                readonly property bool isUser: page.messageRole(modelData) === "user"
                                                readonly property string reasoningText: page.messageReasoning(modelData)
                                                readonly property bool reasoningOpen: page.expandedReasoningKey === page.messageKey(index)
                                                readonly property string reasoningKey: page.messageKey(index)
                                                Item {
                                                    id: bubbleItem
                                                    width: Math.min(parent.width * 0.8, contentText.implicitWidth + 28)
                                                    height: bubbleColumn.height + 20
                                                    x: isUser ? parent.width - width : 0
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: 14
                                                        color: isUser ? AppTheme.accentSoft : (AppTheme.glass ? "#1AFFFFFF" : AppTheme.cardBgAlt)
                                                        border.width: 1
                                                        border.color: isUser ? AppTheme.accent : AppTheme.cardBorder
                                                    }
                                                    Column {
                                                        id: bubbleColumn
                                                        x: 12
                                                        y: 8
                                                        width: parent.width - 24
                                                        spacing: 4
                                                        Item {
                                                            visible: !isUser && reasoningText !== ""
                                                            width: parent.width
                                                            height: 20
                                                            Text {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: (page.expandedReasoningKey === reasoningKey ? "▾ " : "▸ ") + qsTr("思考过程")
                                                                color: AppTheme.textTertiary
                                                                font.pixelSize: 10
                                                                font.family: C.numFont
                                                            }
                                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.toggleReasoningMessage(index) }
                                                        }
                                                        Rectangle {
                                                            visible: !isUser && reasoningText !== "" && page.expandedReasoningKey === reasoningKey
                                                            width: parent.width
                                                            height: reasoningTextLabel.implicitHeight + 14
                                                            radius: 8
                                                            color: AppTheme.glass ? "#12FFFFFF" : AppTheme.divider
                                                            Text {
                                                                id: reasoningTextLabel
                                                                x: 8
                                                                y: 7
                                                                width: parent.width - 16
                                                                text: reasoningText
                                                                color: AppTheme.textTertiary
                                                                font.pixelSize: 10
                                                                font.family: C.monoFont
                                                                wrapMode: Text.WordWrap
                                                            }
                                                        }
                                                        Text {
                                                            id: contentText
                                                            width: parent.width
                                                            text: page.messageContent(modelData)
                                                            color: AppTheme.textPrimary
                                                            font.pixelSize: 12
                                                            font.family: C.numFont
                                                            wrapMode: Text.WordWrap
                                                            lineHeight: 1.5
                                                        }
                                                        Text {
                                                            visible: modelData.tokens !== undefined && Number(modelData.tokens) > 0
                                                            text: qsTr("%1 tokens").arg(modelData.tokens !== undefined ? modelData.tokens : 0)
                                                            color: AppTheme.textTertiary
                                                            font.pixelSize: 9
                                                            font.family: C.numFont
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Text { visible: page.messageCount === 0 && page.configured && page.chatState === "loading"; text: qsTr("思考中…"); color: AppTheme.textSecondary; font.pixelSize: 12; font.family: C.numFont }
                                        TextEdit {
                                            visible: page.messageCount === 0 && page.configured && page.chatState === "ok"
                                            width: parent.width
                                            text: page.chatAnswer
                                            readOnly: true
                                            textFormat: TextEdit.PlainText
                                            wrapMode: TextEdit.Wrap
                                            color: AppTheme.textPrimary
                                            selectionColor: AppTheme.accentSoft
                                            selectedTextColor: "#FFFFFF"
                                            font.pixelSize: 12
                                            font.family: C.numFont
                                            selectByMouse: true
                                        }
                                        Text {
                                            visible: page.messageCount === 0 && page.configured && page.chatState === "error"
                                            width: parent.width
                                            text: page.chatError !== "" ? page.chatError : qsTr("AI 请求失败")
                                            color: AppTheme.danger
                                            font.pixelSize: 11
                                            font.family: C.numFont
                                            wrapMode: Text.WordWrap
                                        }
                                        Text {
                                            visible: page.messageCount === 0 && (!page.configured || page.chatState === "idle")
                                            width: parent.width
                                            text: page.configured ? qsTr("空会话：问问专注方法，或让它帮你整理今天的任务。")
                                                                  : qsTr("还没有配置 AI。点右上角齿轮填写服务商与 Key，或选择「免费直连（免配置）」。")
                                            color: AppTheme.textTertiary
                                            font.pixelSize: 11
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
                                    width: parent.width - 90
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
                                            text: page.configured ? qsTr("问点什么…（Enter 发送）") : qsTr("请先配置 AI")
                                            color: AppTheme.textTertiary
                                            font.pixelSize: 12
                                            font.family: C.numFont
                                        }
                                    }
                                }
                                Item {
                                    width: 82
                                    height: 38
                                    Rectangle { anchors.fill: parent; radius: 19; color: sendArea.containsMouse ? AppTheme.accentSoft : AppTheme.accent; opacity: page.configured ? 1 : 0.4 }
                                    Text { anchors.centerIn: parent; text: qsTr("发送"); color: "#FFFFFF"; font.pixelSize: 12; font.weight: Font.DemiBold; font.family: C.numFont }
                                    MouseArea { id: sendArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: page.configured; onClicked: page.send() }
                                }
                            }

                            Text { width: parent.width; visible: page.usageText() !== ""; text: page.usageText(); color: AppTheme.textTertiary; font.pixelSize: 10; font.family: C.numFont }
                        }
                    }
                }

                GlassCard {
                    visible: page.configOpen
                    width: 300
                    height: 470
                    radius: 22
                    interactive: false
                    glassSource: page.glassSource
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 16
                        contentWidth: width
                        contentHeight: configColumn.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: configColumn
                            width: parent.width
                            spacing: 8
                            Row {
                                width: parent.width
                                Text { text: qsTr("AI 设置"); color: AppTheme.textPrimary; font.pixelSize: 14; font.weight: Font.DemiBold; font.family: C.numFont }
                                Item { width: parent.width - 130; height: 1 }
                                GlassSwitch {
                                    checked: (typeof App !== "undefined" && App.aiEnabled !== undefined) ? App.aiEnabled === true : false
                                    onClicked: page.toggleEnabled()
                                }
                            }
                            Text {
                                width: parent.width
                                text: page.freeProvider ? qsTr("免配置服务商：无需 API Key，选好模型即可直接对话。")
                                                        : qsTr("Key 只保存在本机；模型列表可自动获取。")
                                color: AppTheme.textTertiary
                                font.pixelSize: 10
                                font.family: C.numFont
                                wrapMode: Text.WordWrap
                            }
                            Item {
                                width: parent.width
                                height: 30
                                Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: qsTr("服务商"); color: AppTheme.textSecondary; font.pixelSize: 11; font.family: C.numFont; width: 52 }
                                Item {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 52
                                    anchors.right: parent.right
                                    height: 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    Rectangle { anchors.fill: parent; radius: 8; color: AppTheme.cardBgAlt; border.width: 1; border.color: configProviderArea.containsMouse ? AppTheme.accent : AppTheme.cardBorder }
                                    Text { anchors.left: parent.left; anchors.leftMargin: 9; anchors.verticalCenter: parent.verticalCenter; text: page.providerLabel; color: AppTheme.textPrimary; font.pixelSize: 11; font.family: C.numFont }
                                    Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "▾"; color: AppTheme.textTertiary; font.pixelSize: 11 }
                                    MouseArea { id: configProviderArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.providerMenuOpen = !page.providerMenuOpen }
                                }
                            }
                            Row {
                                width: parent.width
                                spacing: 6
                                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("模型"); color: AppTheme.textSecondary; font.pixelSize: 11; font.family: C.numFont; width: 46 }
                                TextInput {
                                    id: modelInput
                                    width: parent.width - 46 - 24 - 52 - 18
                                    height: 28
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: AppTheme.textPrimary
                                    selectionColor: AppTheme.accentSoft
                                    selectedTextColor: "#FFFFFF"
                                    font.pixelSize: 10
                                    font.family: C.monoFont
                                    text: page.modelDraft
                                    onTextChanged: page.modelDraft = text
                                    onEditingFinished: page.saveModel()
                                    Rectangle { anchors.fill: parent; z: -1; radius: 8; color: AppTheme.cardBgAlt; border.width: 1; border.color: modelInput.activeFocus ? AppTheme.accent : AppTheme.cardBorder }
                                }
                                Item {
                                    width: 24
                                    height: 28
                                    Text { anchors.centerIn: parent; text: "▾"; color: AppTheme.textTertiary; font.pixelSize: 11 }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.modelMenuOpen = !page.modelMenuOpen }
                                }
                                Item {
                                    width: 52
                                    height: 28
                                    Rectangle { anchors.fill: parent; radius: 8; color: refreshArea.containsMouse ? AppTheme.cardBgAlt : "transparent"; border.width: 1; border.color: AppTheme.cardBorder }
                                    Text { anchors.centerIn: parent; text: page.modelsState === "loading" ? qsTr("获取中") : qsTr("刷新"); color: refreshArea.containsMouse ? AppTheme.accent : AppTheme.textSecondary; font.pixelSize: 10; font.family: C.numFont }
                                    MouseArea { id: refreshArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.refreshModels() }
                                }
                            }
                            Text {
                                width: parent.width
                                visible: page.modelsHint !== ""
                                text: page.modelsHint
                                color: page.modelsState === "error" || page.localModelsError !== "" ? AppTheme.danger : AppTheme.textTertiary
                                font.pixelSize: 9
                                font.family: C.numFont
                                wrapMode: Text.WordWrap
                            }
                            Item {
                                visible: !page.freeProvider
                                width: parent.width
                                height: 30
                                Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: qsTr("API Base"); color: AppTheme.textSecondary; font.pixelSize: 11; font.family: C.numFont; width: 52 }
                                TextInput {
                                    id: baseInput
                                    anchors.left: parent.left
                                    anchors.leftMargin: 52
                                    anchors.right: parent.right
                                    height: 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: AppTheme.textPrimary
                                    selectionColor: AppTheme.accentSoft
                                    selectedTextColor: "#FFFFFF"
                                    font.pixelSize: 9
                                    font.family: C.monoFont
                                    text: page.baseDraft
                                    onTextChanged: page.baseDraft = text
                                    onEditingFinished: page.saveBase()
                                    Rectangle { anchors.fill: parent; z: -1; radius: 8; color: AppTheme.cardBgAlt; border.width: 1; border.color: baseInput.activeFocus ? AppTheme.accent : AppTheme.cardBorder }
                                }
                            }
                            Item {
                                visible: !page.freeProvider
                                width: parent.width
                                height: 30
                                Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: qsTr("API Key"); color: AppTheme.textSecondary; font.pixelSize: 11; font.family: C.numFont; width: 52 }
                                TextInput {
                                    id: keyInput
                                    anchors.left: parent.left
                                    anchors.leftMargin: 52
                                    anchors.right: parent.right
                                    height: 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: AppTheme.textPrimary
                                    selectionColor: AppTheme.accentSoft
                                    selectedTextColor: "#FFFFFF"
                                    font.pixelSize: 11
                                    font.family: C.monoFont
                                    echoMode: TextInput.Password
                                    passwordCharacter: "•"
                                    text: page.keyDraft
                                    onTextChanged: page.keyDraft = text
                                    onEditingFinished: page.saveKey()
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: keyInput.text.length === 0
                                        text: (typeof App !== "undefined" && App.aiHasKey === true) ? qsTr("已保存，留空不修改") : qsTr("输入 API Key")
                                        color: AppTheme.textTertiary
                                        font.pixelSize: 10
                                        font.family: C.numFont
                                    }
                                    Rectangle { anchors.fill: parent; z: -1; radius: 8; color: AppTheme.cardBgAlt; border.width: 1; border.color: keyInput.activeFocus ? AppTheme.accent : AppTheme.cardBorder }
                                }
                            }
                            Row {
                                visible: !page.freeProvider
                                width: parent.width
                                spacing: 8
                                Item {
                                    width: 78
                                    height: 28
                                    Rectangle { anchors.fill: parent; radius: 8; color: testArea.containsMouse ? AppTheme.cardBgAlt : "transparent"; border.width: 1; border.color: AppTheme.cardBorder }
                                    Text { anchors.centerIn: parent; text: page.testKind === "testing" ? qsTr("测试中…") : qsTr("测试连接"); color: AppTheme.textSecondary; font.pixelSize: 10; font.family: C.numFont }
                                    MouseArea { id: testArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.testConnection() }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 90
                                    text: page.testText !== "" ? page.testText : (page.testKind === "error" ? qsTr("连接失败") : "")
                                    color: page.testKind === "error" ? AppTheme.danger : AppTheme.textTertiary
                                    font.pixelSize: 9
                                    font.family: C.numFont
                                    elide: Text.ElideRight
                                }
                            }
                            Rectangle { width: parent.width; height: 1; color: AppTheme.divider }
                            Row {
                                width: parent.width
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 90
                                    text: qsTr("用量统计：今日 %1 tokens · %2%3（估算）").arg(page.todayTokens).arg(page.costSymbol).arg(Number(page.todayCost).toFixed(2))
                                    color: AppTheme.textTertiary
                                    font.pixelSize: 9
                                    font.family: C.numFont
                                    wrapMode: Text.WordWrap
                                }
                                Item {
                                    width: 80
                                    height: 26
                                    Rectangle { anchors.fill: parent; radius: 8; color: resetArea.containsMouse ? AppTheme.cardBgAlt : "transparent"; border.width: 1; border.color: AppTheme.cardBorder }
                                    Text { anchors.centerIn: parent; text: qsTr("重置"); color: AppTheme.textSecondary; font.pixelSize: 9; font.family: C.numFont }
                                    MouseArea { id: resetArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.resetUsage() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 服务商下拉
    Item {
        visible: page.providerMenuOpen
        z: 60
        x: Math.round((flick.width - pageColumn.width) / 2)
        y: 136
        width: 300
        height: providerPopupColumn.height + 8
        Rectangle { anchors.fill: parent; radius: 12; color: AppTheme.cardBg; border.width: 1; border.color: AppTheme.cardBorderStrong }
        Column {
            id: providerPopupColumn
            x: 6
            y: 4
            width: parent.width - 12
            spacing: 2
            Repeater {
                model: page.providerList
                delegate: Item {
                    width: parent.width
                    height: 32
                    readonly property bool isFree: modelData.needs_key === false
                                                  || modelData.free === true
                                                  || String(modelData.id) === "free"
                                                  || String(modelData.id) === "pollinations"
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Text { text: String(modelData.label); color: page.providerIndex === index ? AppTheme.accent : AppTheme.textSecondary; font.pixelSize: 11; font.family: C.numFont }
                        Rectangle {
                            visible: isFree
                            width: 40
                            height: 15
                            radius: 7
                            color: "#1FA36B"
                            Text { anchors.centerIn: parent; text: qsTr("免配置"); color: "#FFFFFF"; font.pixelSize: 8; font.family: C.numFont }
                        }
                    }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.selectProvider(index) }
                }
            }
        }
    }

    // 模型下拉
    Item {
        visible: page.modelMenuOpen
        z: 60
        x: Math.round((flick.width - pageColumn.width) / 2) + pageColumn.width - 300
        y: 300
        width: 300
        height: Math.min(220, modelPopupColumn.height + 8)
        Rectangle { anchors.fill: parent; radius: 12; color: AppTheme.cardBg; border.width: 1; border.color: AppTheme.cardBorderStrong }
        Flickable {
            anchors.fill: parent
            anchors.margins: 4
            contentWidth: width
            contentHeight: modelPopupColumn.height
            clip: true
            Column {
                id: modelPopupColumn
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
                            color: page.modelDraft === String(modelData) ? AppTheme.accent : AppTheme.textSecondary
                            font.pixelSize: 10
                            font.family: C.monoFont
                            elide: Text.ElideRight
                        }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.selectModel(modelData) }
                    }
                }
            }
        }
    }
}
