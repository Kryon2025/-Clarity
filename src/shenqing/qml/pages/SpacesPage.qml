import QtQuick
import "../theme"
import "../components"
import "../glass"
import "../components/Constants.js" as C

// 空间页（v0.6）
// - 顶部浏览器式标签页：浅清 / 覆清 / 深清，下划线指示器 240ms 滑动
// - 标签页下方两列卡片：该档的每个空间一张卡（切标签时卡片区 200ms 淡入 + 上移 6px）
//   · 大字号空间名（浅清/覆清点名字就地改名；深清固定不可改）
//   · 「%1 分钟 >」副标题，点击展开轻量滑块改时长
//   · 右侧白色「开始」胶囊 → App.startSpace(spaceId)（深清为「开始深清」）
//   · 浅清/覆清卡片右上角小 × → 180ms 反向淡出后 App.deleteSpaceFor(mode, spaceId)
// - 网格末尾一张虚线「新增空间」卡（仅浅清/覆清）→ App.addSpaceFor(mode)
// - 卡片使用手动两列布局：位置补位用 Behavior 平滑过渡（Grid/Row 定位器会绕过 Behavior）
// - 全局搜索在 Main.qml 的窗口右上角，所有页面可见
Item {
    id: page

    property Item glassSource: null
    // Main.pageTransitions 传入；false 时所有动画瞬时完成
    property bool animationsEnabled: true

    signal whitelistRequested(string mode, string spaceId)

    readonly property var modeList: (typeof App !== "undefined" && App.modes && App.modes.length > 0)
                                    ? App.modes
                                    : [
                                          { value: "light", label: qsTr("浅清"), desc: qsTr("只屏蔽黑名单应用的窗口与声音") },
                                          { value: "medium", label: qsTr("覆清"), desc: qsTr("屏蔽干扰并显示允许使用的应用 dock") },
                                          { value: "heavy", label: qsTr("深清"), desc: qsTr("白名单之外的应用全部屏蔽，不可提前结束") }
                                      ]

    readonly property bool busy: (typeof App !== "undefined" && App.busy === true)

    function modeLabel(value) {
        for (var i = 0; i < page.modeList.length; i++) {
            if (String(page.modeList[i].value) === String(value))
                return String(page.modeList[i].label)
        }
        if (value === "light") return qsTr("浅清")
        if (value === "medium") return qsTr("覆清")
        if (value === "heavy") return qsTr("深清")
        return String(value)
    }

    // 当前标签页：本地状态，初始化时读一次 Python 的默认档；切换标签不改默认档
    property string activeMode: "medium"
    onActiveModeChanged: page.syncSpaces()

    readonly property int activeModeIndex: {
        for (var i = 0; i < page.modeList.length; i++) {
            if (String(page.modeList[i].value) === page.activeMode) return i
        }
        return 0
    }

    // 展开滑块的空间 id（"" 表示都收起）；同一时间只展开一张
    property string expandedSpaceId: ""

    readonly property bool addEnabled: page.activeMode !== "heavy"

    // 只有「新增空间」触发的短窗口内，新建卡片才做入场动画（避免切标签时所有卡片乱入）
    property bool entryAnimationEnabled: false
    Timer {
        id: entryWindowTimer
        interval: 340
        repeat: false
        onTriggered: page.entryAnimationEnabled = false
    }

    // ---------- 固定页头 / 可滚动卡片区（v0.6 修复：标签不再随卡片滚动） ----------
    readonly property real contentWidth: Math.min(page.width - 96, 820)
    readonly property real contentX: (page.width - contentWidth) / 2

    // ---------- 卡片说明气泡（同一时间只开一个；点空白 / Esc 关闭） ----------
    property string infoMode: ""

    function openInfo(mode) {
        var value = String(mode)
        if (value !== "light" && value !== "medium" && value !== "heavy") return
        page.infoMode = value
        infoOverlay.forceActiveFocus()
    }

    function closeInfo() {
        page.infoMode = ""
    }

    function infoTitle(mode) {
        return qsTr("%1空间").arg(page.modeLabel(mode))
    }

    function infoBullets(mode) {
        if (mode === "light") {
            return [
                qsTr("只屏蔽黑名单应用的窗口与声音，其余应用照常使用。"),
                qsTr("可以暂停，也可以提前结束本轮专注。"),
                qsTr("可新增多个浅清空间，单独改名、改时长、设置白名单。")
            ]
        }
        if (mode === "medium") {
            return [
                qsTr("屏蔽干扰应用，并在屏幕右侧显示白名单应用的 dock。"),
                qsTr("可以暂停，也可以提前结束本轮专注。"),
                qsTr("可新增多个覆清空间，单独改名、改时长、设置白名单。")
            ]
        }
        return [
            qsTr("只显示全屏倒计时，白名单之外的应用全部屏蔽。"),
            qsTr("不可暂停、不可提前结束，只能到点自动结束。"),
            qsTr("深清固定一个空间，不设置白名单，只能改时长。")
        ]
    }

    // ---------- 手动两列布局 ----------
    readonly property real cardGap: 16
    readonly property real cardWidth: Math.max(240, (page.contentWidth - page.cardGap) / 2)
    readonly property real collapsedCardHeight: 156
    readonly property real expandedCardHeight: 218
    property real cardsHeight: 0
    onCardWidthChanged: page.scheduleLayout()

    // 空间数据用 ListModel 增量同步：改时长/改名只会 setProperty，不会重建卡片，
    // 这样拖动滑块时不会因为 App.spacesChanged 重建 delegate 而中断拖动，也保住补位动画。
    ListModel { id: spaceModel }

    Connections {
        target: (typeof App !== "undefined") ? App : null
        function onSpacesChanged() { page.syncSpaces() }
    }

    Timer {
        id: layoutTimer
        interval: 0
        repeat: false
        onTriggered: page.layoutCards()
    }

    Component.onCompleted: {
        var initial = (typeof App !== "undefined" && App.defaultMode) ? String(App.defaultMode) : ""
        if (initial === "light" || initial === "medium" || initial === "heavy")
            page.activeMode = initial
        page.syncSpaces()
    }

    // ---------- 数据同步（增量：add 只 append、delete 只 remove，保证补位动画） ----------
    function rowData(entry) {
        return {
            spaceId: String(entry.id),
            mode: (entry.mode !== undefined) ? String(entry.mode) : String(page.activeMode),
            name: (entry.name !== undefined) ? String(entry.name) : "",
            minutes: (entry.minutes !== undefined) ? Number(entry.minutes) : 45,
            allowedCount: (entry.allowedCount !== undefined) ? Number(entry.allowedCount) : 0,
            fixedName: (entry.fixedName !== undefined) ? entry.fixedName === true
                                                       : String(entry.mode) === "heavy"
        }
    }

    function rebuildModel(rows) {
        spaceModel.clear()
        for (var i = 0; i < rows.length; i++)
            spaceModel.append(page.rowData(rows[i]))
        page.scheduleLayout()
    }

    function syncSpaces() {
        var list = (typeof App !== "undefined" && App.spaces) ? App.spaces : []
        var rows = []
        for (var i = 0; i < list.length; i++) {
            var item = list[i]
            if (item && String(item.mode) === String(page.activeMode))
                rows.push(item)
        }

        // 1) 删除模型里已不存在 / 不属于当前档的项
        for (var r = spaceModel.count - 1; r >= 0; r--) {
            var mid = String(spaceModel.get(r).spaceId)
            var keep = false
            for (var j = 0; j < rows.length; j++) {
                if (String(rows[j].id) === mid) {
                    keep = true
                    break
                }
            }
            if (!keep) spaceModel.remove(r)
        }

        // 2) 逐项更新；顺序不一致时整体重建（正常不会发生）
        for (var k = 0; k < rows.length; k++) {
            var data = page.rowData(rows[k])
            if (k < spaceModel.count) {
                if (String(spaceModel.get(k).spaceId) !== data.spaceId) {
                    page.rebuildModel(rows)
                    return
                }
                spaceModel.setProperty(k, "name", data.name)
                spaceModel.setProperty(k, "minutes", data.minutes)
                spaceModel.setProperty(k, "allowedCount", data.allowedCount)
                spaceModel.setProperty(k, "fixedName", data.fixedName)
            } else {
                spaceModel.append(data)
            }
        }

        // 3) 展开的卡片被删掉时自动收起
        if (page.expandedSpaceId !== "") {
            var found = false
            for (var n = 0; n < spaceModel.count; n++) {
                if (String(spaceModel.get(n).spaceId) === page.expandedSpaceId) {
                    found = true
                    break
                }
            }
            if (!found) page.expandedSpaceId = ""
        }

        page.scheduleLayout()
    }

    // ---------- 两列布局与补位 ----------
    function scheduleLayout() {
        layoutTimer.restart()
    }

    function cardAt(index) {
        if (index < spaceRepeater.count) return spaceRepeater.itemAt(index)
        return (index === spaceRepeater.count) ? addCard : null
    }

    function cardTargetHeight(index) {
        if (index < spaceRepeater.count) {
            var item = spaceRepeater.itemAt(index)
            return (item && item.expanded) ? page.expandedCardHeight : page.collapsedCardHeight
        }
        return page.collapsedCardHeight
    }

    function layoutCards() {
        var count = spaceRepeater.count + (page.addEnabled ? 1 : 0)
        var gap = page.cardGap
        var cardW = page.cardWidth
        var y = 0
        var rowHeight = 0
        for (var i = 0; i < count; i++) {
            var item = page.cardAt(i)
            if (!item) continue
            var targetHeight = page.cardTargetHeight(i)
            var col = i % 2
            if (col === 0) rowHeight = targetHeight
            else rowHeight = Math.max(rowHeight, targetHeight)
            item.width = cardW
            item.x = col * (cardW + gap)
            item.y = y
            if (col === 1 || i === count - 1)
                y += rowHeight + gap
        }
        page.cardsHeight = count > 0 ? Math.max(0, y - gap) : 0
    }

    // ---------- 切标签：卡片区淡入 + 上移 6px（用 Translate，不动布局 y） ----------
    function playCardsIn() {
        if (!page.animationsEnabled) {
            cardsRegion.opacity = 1
            cardsShift.y = 0
            return
        }
        cardsRegion.opacity = 0
        cardsShift.y = 6
        cardsInAnim.restart()
    }

    ParallelAnimation {
        id: cardsInAnim
        NumberAnimation {
            target: cardsRegion
            property: "opacity"
            to: 1
            duration: page.animationsEnabled ? 200 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: cardsShift
            property: "y"
            to: 0
            duration: page.animationsEnabled ? 200 : 0
            easing.type: Easing.OutCubic
        }
    }

    // ---------- 档位标签 ----------
    function selectMode(mode) {
        var value = String(mode)
        if (value !== "light" && value !== "medium" && value !== "heavy") return
        if (page.activeMode === value) return
        page.expandedSpaceId = ""
        page.playCardsIn()
        page.activeMode = value
        // 只切换模式，不滚动内容（标签固定，卡片不应被顶到标签下面）
    }

    // ---------- 写操作（Python 接口缺失时逐级兜底） ----------
    function toggleExpanded(spaceId) {
        var value = String(spaceId)
        page.expandedSpaceId = (page.expandedSpaceId === value) ? "" : value
    }

    function commitMinutes(spaceId, mode, value) {
        var next = Math.round(Number(value))
        if (!isFinite(next)) return
        if (typeof App.setSpaceMinutes === "function")
            App.setSpaceMinutes(String(spaceId), next)
        else if (typeof App.setSpaceMinutesFor === "function")
            App.setSpaceMinutesFor(String(mode), next)
    }

    function commitName(spaceId, mode, name) {
        var text = String(name).trim().slice(0, 20)
        if (text.length === 0) return
        if (typeof App.setSpaceName === "function")
            App.setSpaceName(String(spaceId), text)
        else if (typeof App.setSpaceNameFor === "function")
            App.setSpaceNameFor(String(mode), text)
    }

    function addSpace() {
        if (!page.addEnabled) return
        page.entryAnimationEnabled = true
        entryWindowTimer.restart()
        if (typeof App.addSpaceFor === "function")
            App.addSpaceFor(page.activeMode)
    }

    function deleteSpace(spaceId, mode) {
        if (typeof App.deleteSpaceFor === "function")
            App.deleteSpaceFor(String(mode), String(spaceId))
    }

    function startSpace(spaceId, mode) {
        if (typeof App.startSpace === "function")
            App.startSpace(String(spaceId))
        else if (typeof App.startMode === "function")
            App.startMode(String(mode))
    }

    function openWhitelist(spaceId, mode) {
        // 深清固定不含白名单：UI 层直接拒绝
        if (String(mode) === "heavy") return
        page.whitelistRequested(String(mode), String(spaceId))
    }

    onAddEnabledChanged: page.scheduleLayout()

    // ================= 页面主体 =================
    // 页头 + 标签栏固定在页面顶部，不随卡片滚动
    Item {
        id: headerBlock
        x: page.contentX
        y: 24
        width: page.contentWidth
        height: 78

                Column {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 6

                    Text {
                        text: qsTr("空间")
                        color: AppTheme.textPrimary
                        font.pixelSize: AppTheme.fs(30)
                        font.weight: Font.Bold
                        font.family: AppTheme.fontFamily
                        font.letterSpacing: 1
                    }

                    Text {
                        text: page.busy
                              ? qsTr("专注中 · %1 · 剩余 %2").arg(page.modeLabel(App.sessionLevel)).arg(String(App.remainingText))
                              : qsTr("每个档位可建多个空间，各自保存时长与白名单")
                        color: page.busy ? AppTheme.accent : AppTheme.textSecondary
                        font.pixelSize: AppTheme.fs(13)
                        font.family: AppTheme.fontFamily
                    }
                }
            }

    // ---------- 浏览器式标签页：浅清 / 覆清 / 深清（固定顶部） ----------
    Item {
        id: tabBar
        objectName: "TabBar"
        x: page.contentX
        y: headerBlock.y + headerBlock.height
        width: page.contentWidth
        height: 46

                // 底部基线
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: AppTheme.glass ? "#26FFFFFF" : AppTheme.divider
                }

                // 选中指示器：240ms 滑动（x / width 插值）
                Rectangle {
                    id: tabIndicator
                    objectName: "TabIndicator"
                    anchors.bottom: parent.bottom
                    height: 2.5
                    radius: 1.25
                    color: AppTheme.accent
                    x: {
                        var item = tabRepeater.itemAt(page.activeModeIndex)
                        return item ? tabRow.x + item.x : 0
                    }
                    width: {
                        var item = tabRepeater.itemAt(page.activeModeIndex)
                        return item ? Math.max(20, item.width) : 24
                    }
                    Behavior on x {
                        enabled: page.animationsEnabled
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }
                    Behavior on width {
                        enabled: page.animationsEnabled
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }
                }

                Row {
                    id: tabRow
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 30

                    Repeater {
                        id: tabRepeater
                        model: page.modeList

                        delegate: Item {
                            id: tabItem
                            width: tabLabel.implicitWidth + 4
                            height: 42
                            readonly property string modeValue: String(modelData.value)
                            readonly property bool selected: page.activeMode === tabItem.modeValue

                            Text {
                                id: tabLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(modelData.label)
                                color: tabItem.selected ? AppTheme.textPrimary
                                                       : (tabArea.containsMouse ? AppTheme.textSecondary
                                                                                : AppTheme.textTertiary)
                                font.pixelSize: AppTheme.fs(16)
                                font.weight: tabItem.selected ? Font.DemiBold : Font.Medium
                                font.family: AppTheme.fontFamily
                                font.letterSpacing: 1
                                Behavior on color {
                                    enabled: page.animationsEnabled
                                    ColorAnimation { duration: 120 }
                                }
                            }

                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                anchors.topMargin: 4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.selectMode(tabItem.modeValue)
                            }
                        }
                    }
                }
            }

    // ---------- 可滚动区域（从标签栏下方开始，标签永远不动） ----------
    Flickable {
        id: flick
        objectName: "SpaceFlick"
        x: page.contentX
        y: tabBar.y + tabBar.height + 10
        width: page.contentWidth
        height: Math.max(0, page.height - y - 8)
        contentWidth: width
        contentHeight: scrollColumn.height + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: scrollColumn
            width: flick.width
            spacing: 16

            // ---------- 空间卡片（两列，手动布局以便补位动画） ----------
            Item {
                id: cardsRegion
                objectName: "CardsRegion"
                width: parent.width
                height: page.cardsHeight
                opacity: 1
                // 供测试/调试读取切标签时的 6px 上移动画进度
                readonly property alias cardsShiftY: cardsShift.y
                transform: Translate {
                    id: cardsShift
                    y: 0
                }

                Repeater {
                    id: spaceRepeater
                    model: spaceModel

                    delegate: GlassCard {
                        id: spaceCard
                        objectName: "SpaceCard"
                        width: page.cardWidth
                        height: spaceCard.expanded ? page.expandedCardHeight : page.collapsedCardHeight
                        radius: 22
                        interactive: false
                        glassSource: page.glassSource
                        accentTint: AppTheme.accent

                        readonly property string spaceId: String(model.spaceId)
                        readonly property string spaceMode: String(model.mode)
                        readonly property string spaceName: String(model.name)
                        readonly property int spaceMinutes: Number(model.minutes)
                        readonly property int allowedCount: Number(model.allowedCount)
                        readonly property bool fixedName: model.fixedName === true
                        readonly property bool expanded: page.expandedSpaceId === spaceCard.spaceId

                        property bool renameActive: false
                        property bool removing: false
                        property bool layoutReady: false

                        Behavior on height {
                            enabled: page.animationsEnabled
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }
                        // 删除后的平滑补位（位置变化 200ms）
                        Behavior on x {
                            enabled: page.animationsEnabled && spaceCard.layoutReady
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        Behavior on y {
                            enabled: page.animationsEnabled && spaceCard.layoutReady
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }

                        Timer {
                            id: layoutReadyTimer
                            interval: 240
                            repeat: false
                            running: true
                            onTriggered: spaceCard.layoutReady = true
                        }

                        // 入场：opacity 0→1 + scale 0.96→1，180ms（仅新增空间时）
                        ParallelAnimation {
                            id: enterAnim
                            NumberAnimation {
                                target: spaceCard
                                property: "opacity"
                                to: 1
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: spaceCard
                                property: "scale"
                                to: 1
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }

                        // 删除：反向动画结束后再真正删数据
                        ParallelAnimation {
                            id: removeAnim
                            NumberAnimation {
                                target: spaceCard
                                property: "opacity"
                                to: 0
                                duration: 180
                                easing.type: Easing.InCubic
                            }
                            NumberAnimation {
                                target: spaceCard
                                property: "scale"
                                to: 0.96
                                duration: 180
                                easing.type: Easing.InCubic
                            }
                            onFinished: page.deleteSpace(spaceCard.spaceId, spaceCard.spaceMode)
                        }

                        Component.onCompleted: {
                            if (page.entryAnimationEnabled && page.animationsEnabled) {
                                spaceCard.opacity = 0
                                spaceCard.scale = 0.96
                                enterAnim.restart()
                            }
                            page.scheduleLayout()
                        }
                        onExpandedChanged: page.scheduleLayout()

                        function requestRemove() {
                            if (spaceCard.removing) return
                            if (!page.animationsEnabled) {
                                page.deleteSpace(spaceCard.spaceId, spaceCard.spaceMode)
                                return
                            }
                            spaceCard.removing = true
                            removeAnim.restart()
                        }

                        function beginRename() {
                            if (spaceCard.fixedName) return
                            nameInput.text = spaceCard.spaceName
                            spaceCard.renameActive = true
                            nameInput.forceActiveFocus()
                            nameInput.selectAll()
                        }

                        function finishRename(commit) {
                            if (!spaceCard.renameActive) return
                            var value = String(nameInput.text)
                            spaceCard.renameActive = false
                            if (commit) page.commitName(spaceCard.spaceId, spaceCard.spaceMode, value)
                        }

                        // ---- 删除入口（右上角小 ×，深清无） ----
                        Item {
                            visible: !spaceCard.fixedName && !spaceCard.removing
                            width: 26
                            height: 26
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 10

                            Rectangle {
                                anchors.fill: parent
                                radius: 13
                                color: deleteArea.containsMouse
                                       ? (AppTheme.glass ? "#2EFFFFFF" : AppTheme.cardBgAlt)
                                       : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            Glyph {
                                anchors.centerIn: parent
                                kind: "close"
                                size: 11
                                color: deleteArea.containsMouse ? AppTheme.danger : AppTheme.textTertiary
                            }

                            MouseArea {
                                id: deleteArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: spaceCard.requestRemove()
                            }
                        }

                        // ---- 说明入口（右上角倒感叹号；深清没有删除按钮时占最右） ----
                        Item {
                            id: infoButton
                            objectName: "SpaceInfoButton"
                            width: 26
                            height: 26
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: spaceCard.fixedName ? 10 : 40

                            Rectangle {
                                anchors.fill: parent
                                radius: 13
                                color: infoArea.containsMouse
                                       ? (AppTheme.glass ? "#2EFFFFFF" : AppTheme.cardBgAlt)
                                       : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            // 倒感叹号：竖线 + 点，整体旋转 180°
                            Item {
                                anchors.centerIn: parent
                                width: 12
                                height: 14
                                rotation: 180

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 0
                                    width: 2
                                    height: 8.5
                                    radius: 1
                                    color: infoArea.containsMouse ? AppTheme.accent : AppTheme.textTertiary
                                }

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 11.5
                                    width: 2.6
                                    height: 2.6
                                    radius: 1.3
                                    color: infoArea.containsMouse ? AppTheme.accent : AppTheme.textTertiary
                                }
                            }

                            MouseArea {
                                id: infoArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.openInfo(spaceCard.spaceMode)
                            }
                        }

                        // ---- 空间名（大字号；浅清/覆清可点名字改名） ----
                        Item {
                            id: nameRow
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            anchors.top: parent.top
                            anchors.topMargin: 20
                            anchors.right: startButton.left
                            anchors.rightMargin: 14
                            height: 34

                            Text {
                                visible: !spaceCard.renameActive
                                width: parent.width
                                anchors.verticalCenter: parent.verticalCenter
                                text: spaceCard.spaceName
                                color: AppTheme.textPrimary
                                font.pixelSize: AppTheme.fs(24)
                                font.weight: Font.DemiBold
                                font.family: AppTheme.fontFamily
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Rectangle {
                                visible: spaceCard.renameActive
                                anchors.fill: parent
                                radius: 9
                                color: AppTheme.cardBgAlt
                                border.width: 1
                                border.color: AppTheme.accent

                                TextInput {
                                    id: nameInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                    color: AppTheme.textPrimary
                                    selectionColor: AppTheme.accentSoft
                                    selectedTextColor: "#FFFFFF"
                                    font.pixelSize: AppTheme.fs(18)
                                    font.family: AppTheme.fontFamily
                                    activeFocusOnTab: true
                                    onActiveFocusChanged: {
                                        if (!activeFocus && spaceCard.renameActive)
                                            spaceCard.finishRename(true)
                                    }
                                    Keys.onReturnPressed: spaceCard.finishRename(true)
                                    Keys.onEnterPressed: spaceCard.finishRename(true)
                                    Keys.onEscapePressed: spaceCard.finishRename(false)
                                }
                            }

                            MouseArea {
                                visible: !spaceCard.fixedName && !spaceCard.renameActive
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.IBeamCursor
                                onClicked: spaceCard.beginRename()
                            }
                        }

                        // ---- 副标题：「%1 分钟 >」，点击展开/收起轻量滑块 ----
                        Item {
                            id: minuteRow
                            anchors.left: nameRow.left
                            anchors.top: nameRow.bottom
                            anchors.topMargin: 2
                            width: Math.min(parent.width * 0.45, minuteLabel.implicitWidth + minuteChevron.width + 12)
                            height: 22

                            Text {
                                id: minuteLabel
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("%1 分钟").arg(spaceCard.spaceMinutes)
                                color: AppTheme.textSecondary
                                font.pixelSize: AppTheme.fs(13)
                                font.family: AppTheme.fontFamily
                            }

                            Glyph {
                                id: minuteChevron
                                anchors.left: minuteLabel.right
                                anchors.leftMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                kind: "chevron"
                                size: 10
                                color: minuteArea.containsMouse ? AppTheme.accent : AppTheme.textTertiary
                                rotation: spaceCard.expanded ? 90 : 0
                                Behavior on rotation {
                                    enabled: page.animationsEnabled
                                    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                                }
                            }

                            MouseArea {
                                id: minuteArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.toggleExpanded(spaceCard.spaceId)
                            }
                        }

                        // ---- 轻量滑块（副标题点击后展开） ----
                        Item {
                            id: sliderBlock
                            anchors.left: nameRow.left
                            anchors.right: startButton.left
                            anchors.rightMargin: 12
                            anchors.top: minuteRow.bottom
                            anchors.topMargin: 10
                            height: 46
                            visible: spaceCard.expanded || opacity > 0.01
                            opacity: spaceCard.expanded ? 1 : 0
                            Behavior on opacity {
                                enabled: page.animationsEnabled
                                NumberAnimation { duration: 160 }
                            }

                            GlassSlider {
                                id: minutesSlider
                                width: parent.width
                                height: 30
                                from: (typeof App !== "undefined" && App.spaceMinMinutes !== undefined)
                                      ? Number(App.spaceMinMinutes) : 1
                                to: (typeof App !== "undefined" && App.spaceMaxMinutes !== undefined)
                                    ? Number(App.spaceMaxMinutes) : 240
                                step: (typeof App !== "undefined" && App.spaceMinuteStep !== undefined)
                                      ? Number(App.spaceMinuteStep) : 1
                                value: spaceCard.spaceMinutes
                                onMoved: (value) => page.commitMinutes(spaceCard.spaceId, spaceCard.spaceMode, value)
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: minutesSlider.bottom
                                anchors.topMargin: 2

                                Text {
                                    width: parent.width / 2
                                    text: qsTr("%1 分钟（最短即体验）").arg(Math.round(minutesSlider.from))
                                    color: AppTheme.textTertiary
                                    font.pixelSize: AppTheme.fs(10)
                                    font.family: AppTheme.fontFamily
                                }

                                Text {
                                    width: parent.width / 2
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("%1 分钟").arg(Math.round(minutesSlider.to))
                                    color: AppTheme.textTertiary
                                    font.pixelSize: AppTheme.fs(10)
                                    font.family: AppTheme.fontFamily
                                }
                            }
                        }

                        // ---- 白名单入口（左下角；深清固定不含白名单，只显示说明） ----
                        Item {
                            id: whitelistRow
                            anchors.left: nameRow.left
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 18
                            height: 18
                            width: whitelistContent.width

                            Row {
                                id: whitelistContent
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    kind: spaceCard.spaceMode === "heavy" ? "lock" : "grid"
                                    size: 12
                                    color: spaceCard.spaceMode !== "heavy" && whitelistArea.containsMouse
                                           ? AppTheme.accent : AppTheme.textTertiary
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: spaceCard.spaceMode === "heavy"
                                          ? qsTr("深清固定不含白名单")
                                          : (spaceCard.allowedCount > 0
                                             ? qsTr("白名单 · %1 个应用").arg(spaceCard.allowedCount)
                                             : qsTr("白名单 · 未设置"))
                                    color: spaceCard.spaceMode !== "heavy" && whitelistArea.containsMouse
                                           ? AppTheme.textSecondary : AppTheme.textTertiary
                                    font.pixelSize: AppTheme.fs(11)
                                    font.family: AppTheme.fontFamily
                                }
                            }

                            MouseArea {
                                id: whitelistArea
                                visible: spaceCard.spaceMode !== "heavy"
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.openWhitelist(spaceCard.spaceId, spaceCard.spaceMode)
                            }
                        }

                        // ---- 开始（右侧白色胶囊，深色/浅色/玻璃三种主题下都保持白底深字） ----
                        Item {
                            id: startButton
                            anchors.right: parent.right
                            anchors.rightMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(88, startLabel.implicitWidth + 46)
                            height: 42
                            opacity: page.busy ? 0.55 : 1.0
                            scale: startArea.pressed && !page.busy ? 0.97 : 1.0
                            Behavior on scale {
                                enabled: page.animationsEnabled
                                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                            }
                            Behavior on opacity {
                                enabled: page.animationsEnabled
                                NumberAnimation { duration: 120 }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: startArea.containsMouse && !page.busy ? "#FFFFFF" : "#F3FAFC"
                                border.width: 1
                                border.color: AppTheme.light ? AppTheme.cardBorderStrong : "#40FFFFFF"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            // 顶部一抹柔光，让白胶囊更有玻璃质感
                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#66FFFFFF" }
                                    GradientStop { position: 0.48; color: "#00FFFFFF" }
                                    GradientStop { position: 1.0; color: "#14000000" }
                                }
                            }

                            Text {
                                id: startLabel
                                anchors.centerIn: parent
                                text: spaceCard.spaceMode === "heavy" ? qsTr("开始深清") : qsTr("开始")
                                color: "#08222B"
                                font.pixelSize: AppTheme.fs(14)
                                font.weight: Font.DemiBold
                                font.family: AppTheme.fontFamily
                            }

                            MouseArea {
                                id: startArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: page.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (!page.busy)
                                        page.startSpace(spaceCard.spaceId, spaceCard.spaceMode)
                                }
                            }
                        }
                    }
                }

                // ---------- 新增空间（虚线卡；仅浅清/覆清） ----------
                Item {
                    id: addCard
                    objectName: "AddCard"
                    visible: page.addEnabled
                    width: page.cardWidth
                    height: page.collapsedCardHeight
                    property bool layoutReady: false

                    Timer {
                        id: addLayoutReadyTimer
                        interval: 300
                        repeat: false
                        running: true
                        onTriggered: addCard.layoutReady = true
                    }

                    Behavior on x {
                        enabled: page.animationsEnabled && addCard.layoutReady
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        enabled: page.animationsEnabled && addCard.layoutReady
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    readonly property bool hovered: addArea.containsMouse

                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        color: addCard.hovered
                               ? (AppTheme.glass ? "#12FFFFFF" : AppTheme.cardBgAlt)
                               : (AppTheme.glass ? "#08FFFFFF" : "transparent")
                        Behavior on color { ColorAnimation { duration: 130 } }
                    }

                    Canvas {
                        id: dashBorder
                        anchors.fill: parent

                        property color strokeColor: addCard.hovered ? AppTheme.accent : AppTheme.cardBorderStrong
                        onStrokeColorChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onVisibleChanged: if (visible) requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var w = width
                            var h = height
                            var r = 22
                            var inset = 1.2
                            ctx.strokeStyle = dashBorder.strokeColor
                            ctx.lineWidth = 1.4
                            ctx.setLineDash([7, 6])
                            ctx.beginPath()
                            ctx.moveTo(inset + r, inset)
                            ctx.lineTo(w - inset - r, inset)
                            ctx.arcTo(w - inset, inset, w - inset, inset + r, r)
                            ctx.lineTo(w - inset, h - inset - r)
                            ctx.arcTo(w - inset, h - inset, w - inset - r, h - inset, r)
                            ctx.lineTo(inset + r, h - inset)
                            ctx.arcTo(inset, h - inset, inset, h - inset - r, r)
                            ctx.lineTo(inset, inset + r)
                            ctx.arcTo(inset, inset, inset + r, inset, r)
                            ctx.closePath()
                            ctx.stroke()
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 10

                        Glyph {
                            anchors.horizontalCenter: parent.horizontalCenter
                            kind: "plus"
                            size: 26
                            color: addCard.hovered ? AppTheme.accent : AppTheme.textTertiary
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: qsTr("新增空间")
                            color: addCard.hovered ? AppTheme.textSecondary : AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(14)
                            font.family: AppTheme.fontFamily
                            font.letterSpacing: 1
                        }
                    }

                    MouseArea {
                        id: addArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.addSpace()
                    }
                }
            }

            // ---------- 底部说明 ----------
            Text {
                width: parent.width
                text: qsTr("「浅清」「覆清」可以新增多个空间，各自保存名称、锁定时长与白名单；「深清」固定一个空间，不可新增或删除，只能改时长，且不设置白名单。")
                color: AppTheme.textTertiary
                font.pixelSize: AppTheme.fs(11)
                font.family: AppTheme.fontFamily
                wrapMode: Text.WordWrap
            }
        }
    }

    // 纤细滚动指示（跟随可滚动卡片区）
    Rectangle {
        id: scrollThumb
        visible: flick.contentHeight > flick.height + 4
        width: 4
        radius: 2
        color: AppTheme.glass ? "#26FFFFFF" : AppTheme.divider
        x: flick.x + flick.width - 14
        height: Math.max(48, flick.height * flick.height / Math.max(1, flick.contentHeight))
        y: flick.y + 8 + Math.max(0, Math.min(1, flick.contentY / Math.max(1, flick.contentHeight - flick.height)))
           * Math.max(1, flick.height - 16 - height)
    }

    // ================= 空间说明气泡（点空白 / Esc 关闭；同时只开一个） =================
    Item {
        id: infoOverlay
        objectName: "SpaceInfoOverlay"
        anchors.fill: parent
        z: 60
        visible: page.infoMode !== "" || opacity > 0.01
        focus: visible
        opacity: page.infoMode !== "" ? 1 : 0
        Keys.onEscapePressed: page.closeInfo()

        Behavior on opacity {
            enabled: page.animationsEnabled
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        // 半透明遮罩：点击空白处关闭
        Rectangle {
            anchors.fill: parent
            color: "#66040810"
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: page.closeInfo()
        }

        Rectangle {
            id: infoCard
            width: Math.min(420, page.width - 80)
            height: infoColumn.implicitHeight + 44
            radius: 20
            anchors.centerIn: parent
            color: AppTheme.glass ? "#F20A1B26" : AppTheme.cardBg
            border.width: 1
            border.color: AppTheme.glass ? "#4DFFFFFF" : AppTheme.cardBorderStrong

            // 吃掉气泡内点击，避免误触关闭
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: {}
            }

            Column {
                id: infoColumn
                x: 22
                y: 20
                width: parent.width - 44
                spacing: 12

                Row {
                    width: parent.width
                    spacing: 9

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        kind: page.infoMode === "heavy" ? "lock"
                                                       : (page.infoMode === "medium" ? "wave" : "moon")
                        size: 17
                        color: AppTheme.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.infoTitle(page.infoMode)
                        color: AppTheme.textPrimary
                        font.pixelSize: AppTheme.fs(17)
                        font.weight: Font.DemiBold
                        font.family: AppTheme.fontFamily
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: AppTheme.divider
                }

                Repeater {
                    model: page.infoBullets(page.infoMode)

                    delegate: Row {
                        width: infoColumn.width
                        spacing: 9

                        Rectangle {
                            width: 5
                            height: 5
                            radius: 2.5
                            anchors.top: parent.top
                            anchors.topMargin: 7
                            color: AppTheme.accent
                        }

                        Text {
                            width: parent.width - 14
                            text: String(modelData)
                            color: AppTheme.textSecondary
                            font.pixelSize: AppTheme.fs(13)
                            font.family: AppTheme.fontFamily
                            wrapMode: Text.WordWrap
                            lineHeight: 1.3
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: qsTr("点击空白处或按 Esc 关闭")
                    color: AppTheme.textTertiary
                    font.pixelSize: AppTheme.fs(11)
                    font.family: AppTheme.fontFamily
                }
            }
        }
    }
}
