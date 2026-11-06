import QtQuick
import "../theme"
import QtQuick.Window
import QtQuick.Effects
import "../glass"
import "Constants.js" as C

// 专注全屏遮罩（App.locked 由 Python 控制；预览模式 App.previewActive 也会显示）。
// v0.4：
//  - 真实专注：左侧大倒计时 + 顶部状态条 + 右上灵动岛 + 覆清档右侧竖向 dock；
//    深清档不显示暂停/提前结束，体验模式（App.trialActive）允许提前结束。
//  - 预览：10 秒假倒计时 +「预览」角标 + 关闭按钮，调 App.stopPreview()；
//    预览不调用 App.overlayOpened()（不隐藏任务栏、不装键盘钩子）。
//  - glass 主题沿用海水玻璃；solid / light 主题用平面遮罩，不做折射/噪点。
Window {
    id: overlay
    objectName: "LockOverlay"
    title: qsTr("深清 · 专注中")
    // v0.6 进出场动画：退出时 closing=true 保持窗口可见，等淡出动画结束再隐藏
    readonly property bool shouldShow: App.locked === true || overlay.previewing
    property bool closing: false
    visibility: (overlay.shouldShow || overlay.closing) ? Window.FullScreen : Window.Hidden
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: AppTheme.glass ? AppTheme.bgTop : AppTheme.overlayTop

    onClosing: function (close) {
        if (App.locked) {
            close.accepted = false
        } else if (overlay.previewing) {
            // 预览被关闭（Alt+F4 等）时同步结束预览，避免 App.previewActive 悬挂
            if (typeof App.stopPreview === "function") App.stopPreview()
        }
    }

    // ================= App 状态 =================
    readonly property bool previewing: App.previewActive === true
    readonly property bool trial: App.trialActive === true
    readonly property string level: {
        if (overlay.previewing) return String(App.previewLevel !== undefined ? App.previewLevel : "")
        return App.locked === true ? String(App.sessionLevel !== undefined ? App.sessionLevel : "") : ""
    }
    readonly property bool mediumDock: overlay.level === "medium"
    // 深清：真实会话按 sessionLevel 判断；老接口没有 sessionLevel 时退回「主空间 super」判断
    readonly property bool heavyLock: {
        if (overlay.level !== "") return overlay.level === "heavy"
        if (overlay.previewing) return false
        var sid = String(App.activeSpaceId || "")
        var list = App.spaces || []
        for (var i = 0; i < list.length; i++) {
            if (String(list[i].id) === sid)
                return list[i].super === true
        }
        return false
    }

    // 真实专注才通知 Python；预览绝不触发（不隐藏任务栏、不锁键）
    readonly property bool realFocusActive: App.locked === true && !overlay.previewing
    onRealFocusActiveChanged: {
        if (overlay.realFocusActive) {
            if (typeof App.overlayOpened === "function") App.overlayOpened()
        } else {
            if (typeof App.overlayClosed === "function") App.overlayClosed()
        }
    }

    function modeLabel(value) {
        var lv = String(value || "")
        if (lv === "light") return qsTr("浅清")
        if (lv === "medium") return qsTr("覆清")
        if (lv === "heavy") return qsTr("深清")
        return qsTr("专注")
    }
    readonly property string levelLabel: overlay.modeLabel(overlay.level)
    readonly property string spaceName: {
        var active = App.activeSpaceName !== undefined ? String(App.activeSpaceName) : ""
        if (active !== "") return active
        var sp = App.space
        if (sp !== undefined && sp !== null && sp.name !== undefined) return String(sp.name)
        return ""
    }

    readonly property var dockApps: App.dockApps !== undefined ? App.dockApps : []
    readonly property int dockCount: overlay.dockApps !== null && overlay.dockApps !== undefined
                                    ? overlay.dockApps.length : 0

    // ================= v0.8：dock 设置 / 时钟 / 右侧组件 =================
    property string clockTime: ""
    property string clockDate: ""
    property bool dockSettingsOpen: false
    property bool powerConfirmOpen: false
    property string pendingPower: ""
    property int volumeDraft: 50
    property bool widgetMenuOpen: false
    property var widgetIds: ["quote", "focusCount", "streak"]
    readonly property var allWidgetIds: ["clock", "quote", "countdown", "focusCount", "streak"]

    function refreshClock() {
        var d = new Date()
        function two(n) { return n < 10 ? "0" + n : String(n) }
        overlay.clockTime = two(d.getHours()) + ":" + two(d.getMinutes())
        overlay.clockDate = d.getFullYear() + "/" + two(d.getMonth() + 1) + "/" + two(d.getDate())
    }
    Timer {
        interval: 1000
        repeat: true
        running: overlay.shouldShow
        onTriggered: overlay.refreshClock()
    }


    function widgetTitle(id) {
        if (id === "clock") return qsTr("时钟")
        if (id === "quote") return qsTr("每日一言")
        if (id === "countdown") return qsTr("倒数日")
        if (id === "focusCount") return qsTr("今日专注")
        return qsTr("连续打卡")
    }
    function widgetValue(id) {
        if (id === "clock") return overlay.clockTime
        if (id === "quote") return (typeof App !== "undefined" && App.dailyQuote !== undefined)
                                    ? String(App.dailyQuote) : qsTr("把这件事做完，再抬头。")
        if (id === "countdown") {
            if (typeof App !== "undefined" && App.countdownDays !== undefined && Number(App.countdownDays) >= 0)
                return qsTr("%1 天").arg(Number(App.countdownDays))
            return qsTr("还没有倒数日")
        }
        if (id === "focusCount") return (typeof App !== "undefined" && App.todaySessions !== undefined)
                                        ? qsTr("%1 次").arg(Number(App.todaySessions)) : qsTr("0 次")
        return (typeof App !== "undefined" && App.streakDays !== undefined)
               ? qsTr("%1 天").arg(Number(App.streakDays)) : qsTr("0 天")
    }
    function persistWidgetOrder() {
        if (typeof App !== "undefined" && typeof App.setOverlayWidgetOrder === "function") {
            var arr = []
            for (var i = 0; i < overlay.widgetIds.length; i++)
                arr.push("builtin:" + overlay.widgetIds[i])
            App.setOverlayWidgetOrder(arr)
        }
    }
    function loadWidgetOrder() {
        if (typeof App !== "undefined" && App.overlayWidgetOrder !== undefined) {
            var order = App.overlayWidgetOrder || []
            var list = []
            for (var i = 0; i < order.length; i++) {
                var value = String(order[i])
                if (value.indexOf("builtin:") === 0) {
                    var id = value.substring(8)
                    if (overlay.allWidgetIds.indexOf(id) >= 0 && list.indexOf(id) < 0)
                        list.push(id)
                }
            }
            if (list.length > 0)
                overlay.widgetIds = list
        }
    }
    function addWidget(id) {
        var list = overlay.widgetIds.slice()
        if (list.indexOf(id) < 0) list.push(id)
        overlay.widgetIds = list
        overlay.persistWidgetOrder()
        overlay.widgetMenuOpen = false
    }
    function removeWidget(id) {
        var list = overlay.widgetIds.slice()
        var idx = list.indexOf(id)
        if (idx >= 0) list.splice(idx, 1)
        overlay.widgetIds = list
        overlay.persistWidgetOrder()
    }
    function openDockSettings() {
        overlay.volumeDraft = (typeof App !== "undefined" && App.systemVolume !== undefined
                               && Number(App.systemVolume) >= 0) ? Number(App.systemVolume) : 50
        overlay.powerConfirmOpen = false
        overlay.dockSettingsOpen = true
    }
    function closeDockSettings() {
        overlay.powerConfirmOpen = false
        overlay.dockSettingsOpen = false
    }
    function requestPower(kind) {
        overlay.pendingPower = String(kind)
        overlay.powerConfirmOpen = true
    }
    function confirmPower() {
        if (typeof App !== "undefined" && typeof App.systemPower === "function")
            App.systemPower(overlay.pendingPower)
        overlay.powerConfirmOpen = false
        overlay.dockSettingsOpen = false
    }
    function setVolume(value) {
        overlay.volumeDraft = Math.max(0, Math.min(100, Math.round(Number(value))))
        if (typeof App !== "undefined" && typeof App.setSystemVolume === "function")
            App.setSystemVolume(overlay.volumeDraft)
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (overlay.powerConfirmOpen) overlay.powerConfirmOpen = false
            else if (overlay.dockSettingsOpen) overlay.closeDockSettings()
            else if (overlay.widgetMenuOpen) overlay.widgetMenuOpen = false
        }
    }

    // ================= 进出场动画（v0.6） =================
    // Main.pageTransitions=false 时由 Main 传 false，所有过渡瞬时完成
    property bool animationsEnabled: true
    property real bgOpacity: 0
    property real contentOpacity: 0

    ParallelAnimation {
        id: enterAnim
        NumberAnimation {
            target: overlay
            property: "bgOpacity"
            from: 0
            to: 1
            duration: overlay.animationsEnabled ? 260 : 0
            easing.type: Easing.OutCubic
        }
        SequentialAnimation {
            // 内容比背景晚 60ms 淡入
            PauseAnimation { duration: overlay.animationsEnabled ? 60 : 0 }
            NumberAnimation {
                target: overlay
                property: "contentOpacity"
                from: 0
                to: 1
                duration: overlay.animationsEnabled ? 260 : 0
                easing.type: Easing.OutCubic
            }
        }
    }

    ParallelAnimation {
        id: exitAnim
        NumberAnimation {
            target: overlay
            property: "bgOpacity"
            to: 0
            duration: overlay.animationsEnabled ? 200 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: overlay
            property: "contentOpacity"
            to: 0
            duration: overlay.animationsEnabled ? 200 : 0
            easing.type: Easing.OutCubic
        }
        onFinished: overlay.closing = false
    }

    onShouldShowChanged: {
        if (overlay.shouldShow) {
            overlay.closing = false
            overlay.bgOpacity = 0
            overlay.contentOpacity = 0
            if (overlay.animationsEnabled) {
                exitAnim.stop()
                enterAnim.restart()
            } else {
                overlay.bgOpacity = 1
                overlay.contentOpacity = 1
            }
        } else if (overlay.animationsEnabled) {
            enterAnim.stop()
            overlay.closing = true
            exitAnim.restart()
        } else {
            enterAnim.stop()
            exitAnim.stop()
            overlay.closing = false
            overlay.bgOpacity = 0
            overlay.contentOpacity = 0
        }
    }

    Component.onCompleted: {
        overlay.refreshClock()
        overlay.loadWidgetOrder()
        if (overlay.shouldShow) {
            overlay.bgOpacity = 1
            overlay.contentOpacity = 1
        }
    }

    readonly property int remainingSecondsValue: {
        if (overlay.previewing) return overlay.previewRemaining
        var s = Number(App.remainingSeconds)
        return isFinite(s) ? Math.max(0, Math.round(s)) : 0
    }

    // ================= 预览倒计时（假计时 10 秒） =================
    property int previewRemaining: 10
    Timer {
        id: previewTimer
        interval: 1000
        repeat: true
        running: overlay.previewing && overlay.previewRemaining > 0
        onTriggered: overlay.previewRemaining = Math.max(0, overlay.previewRemaining - 1)
    }
    onPreviewingChanged: if (overlay.previewing) overlay.previewRemaining = 10

    function two(n) { return n < 10 ? "0" + n : String(n) }
    readonly property string previewTimeText: "00:" + overlay.two(overlay.previewRemaining)

    // ================= 真实会话数值 =================
    readonly property real progressValue: {
        if (overlay.previewing)
            return Math.max(0, Math.min(1, (10 - overlay.previewRemaining) / 10))
        var p = Number(App.progress)
        if (!isFinite(p)) return 0
        return Math.max(0, Math.min(1, p))
    }
    readonly property int percentValue: Math.round(overlay.progressValue * 100)
    readonly property int remainingMinutesValue: {
        if (overlay.previewing) return 0
        var s = Number(App.remainingSeconds)
        if (!isFinite(s)) s = 0
        return Math.max(0, Math.ceil(s / 60))
    }
    readonly property string remainingTextValue: {
        if (overlay.previewing) return overlay.previewTimeText
        return App.remainingText !== undefined ? String(App.remainingText) : ""
    }

    // ================= 媒体 =================
    readonly property bool hasMedia: App.mediaHasSession === true
    readonly property string mediaTitleText: App.mediaTitle !== undefined ? String(App.mediaTitle) : ""
    readonly property string mediaArtistText: App.mediaArtist !== undefined ? String(App.mediaArtist) : ""
    readonly property string mediaAlbumText: App.mediaAlbum !== undefined ? String(App.mediaAlbum) : ""
    readonly property string mediaAppText: App.mediaApp !== undefined ? String(App.mediaApp) : ""
    readonly property bool mediaPlayingValue: App.mediaPlaying === true
    readonly property real mediaPositionValue: App.mediaPosition !== undefined ? Number(App.mediaPosition) : 0
    readonly property real mediaDurationValue: App.mediaDuration !== undefined ? Number(App.mediaDuration) : 0

    // ================= 背景 =================
    Item {
        id: water
        objectName: "LockWater"
        anchors.fill: parent
        clip: true
        opacity: overlay.bgOpacity

        // 纯色 / 浅色：平面渐变
        Rectangle {
            anchors.fill: parent
            visible: !AppTheme.glass
            gradient: Gradient {
                GradientStop { position: 0.0; color: AppTheme.overlayTop }
                GradientStop { position: 0.55; color: AppTheme.bgMid }
                GradientStop { position: 1.0; color: AppTheme.overlayBottom }
            }
        }

        // 玻璃：海水渐变 + 极慢水光
        Rectangle {
            anchors.fill: parent
            visible: AppTheme.glass
            gradient: Gradient {
                GradientStop { position: 0.0; color: AppTheme.bgTop }
                GradientStop { position: 0.55; color: "#06202C" }
                GradientStop { position: 1.0; color: AppTheme.bgBottom }
            }
        }

        Item {
            anchors.fill: parent
            visible: AppTheme.glass

            Rectangle {
                id: glowA
                visible: false
                width: Math.max(680, overlay.width * 0.72)
                height: width
                radius: width / 2
                x: 0
                y: 0
                color: C.waterBlue
            }
            MultiEffect {
                source: glowA
                width: glowA.width
                height: glowA.height
                blurEnabled: true
                blur: 1.0
                blurMax: 128
                opacity: 0.20
                SequentialAnimation on x {
                    running: AppTheme.glass
                    loops: Animation.Infinite
                    NumberAnimation { from: -overlay.width * 0.34; to: -overlay.width * 0.06; duration: 64000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: -overlay.width * 0.06; to: -overlay.width * 0.34; duration: 64000; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on y {
                    running: AppTheme.glass
                    loops: Animation.Infinite
                    NumberAnimation { from: -overlay.height * 0.30; to: -overlay.height * 0.10; duration: 52000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: -overlay.height * 0.10; to: -overlay.height * 0.30; duration: 52000; easing.type: Easing.InOutSine }
                }
            }

            Rectangle {
                id: glowB
                visible: false
                width: Math.max(560, overlay.width * 0.58)
                height: width
                radius: width / 2
                x: 0
                y: 0
                color: C.waterTeal
            }
            MultiEffect {
                source: glowB
                width: glowB.width
                height: glowB.height
                blurEnabled: true
                blur: 1.0
                blurMax: 128
                opacity: 0.16
                SequentialAnimation on x {
                    running: AppTheme.glass
                    loops: Animation.Infinite
                    NumberAnimation { from: overlay.width * 0.42; to: overlay.width * 0.58; duration: 72000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: overlay.width * 0.58; to: overlay.width * 0.42; duration: 72000; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on y {
                    running: AppTheme.glass
                    loops: Animation.Infinite
                    NumberAnimation { from: overlay.height * 0.34; to: overlay.height * 0.56; duration: 58000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: overlay.height * 0.56; to: overlay.height * 0.34; duration: 58000; easing.type: Easing.InOutSine }
                }
            }

            Rectangle {
                id: glowC
                visible: false
                width: Math.max(420, overlay.width * 0.4)
                height: width
                radius: width / 2
                x: 0
                y: 0
                color: C.waterSand
            }
            MultiEffect {
                source: glowC
                width: glowC.width
                height: glowC.height
                blurEnabled: true
                blur: 1.0
                blurMax: 128
                opacity: 0.10
                SequentialAnimation on x {
                    running: AppTheme.glass
                    loops: Animation.Infinite
                    NumberAnimation { from: overlay.width * 0.10; to: overlay.width * 0.26; duration: 80000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: overlay.width * 0.26; to: overlay.width * 0.10; duration: 80000; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on y {
                    running: AppTheme.glass
                    loops: Animation.Infinite
                    NumberAnimation { from: overlay.height * 0.62; to: overlay.height * 0.72; duration: 66000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: overlay.height * 0.72; to: overlay.height * 0.62; duration: 66000; easing.type: Easing.InOutSine }
                }
            }

            Image {
                anchors.fill: parent
                source: "../assets/img/noise.png"
                fillMode: Image.Tile
                smooth: false
                opacity: 0.10
            }
        }
    }

    // ================= 内容层 =================
    Item {
        id: content
        objectName: "LockContent"
        anchors.fill: parent
        opacity: overlay.contentOpacity
        property Item glassSource: water

        // ---------- 顶部状态条：预览角标 / 应用标记 / 档位 / 空间名 / 顶部剩余时间 ----------
        Row {
            id: topBar
            visible: !overlay.heavyLock
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: Math.round(overlay.width * 0.085)
            anchors.topMargin: 24
            spacing: 12

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: overlay.previewing
                width: previewBadgeText.implicitWidth + 20
                height: 26
                radius: 13
                color: AppTheme.accent
                Text {
                    id: previewBadgeText
                    anchors.centerIn: parent
                    text: qsTr("预览")
                    color: AppTheme.textOnLight
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.family: C.numFont
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                radius: 9
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#7FE7DA" }
                    GradientStop { position: 1.0; color: "#1F6FD0" }
                }
                Glyph {
                    anchors.centerIn: parent
                    kind: "drop"
                    size: 15
                    color: "#04222B"
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: levelChipText.implicitWidth + 22
                height: 26
                radius: 13
                color: AppTheme.glass ? "#1FFFFFFF" : AppTheme.chipBg
                border.width: 1
                border.color: AppTheme.glass ? "#33FFFFFF" : AppTheme.cardBorder
                Text {
                    id: levelChipText
                    anchors.centerIn: parent
                    text: overlay.levelLabel
                    color: AppTheme.textPrimary
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    font.family: C.numFont
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: overlay.spaceName !== ""
                text: overlay.spaceName
                color: AppTheme.textSecondary
                font.pixelSize: 13
                font.family: C.numFont
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: overlay.remainingTextValue
                color: AppTheme.textTertiary
                font.pixelSize: 13
                font.family: C.monoFont
            }
        }

        // ---------- 左侧：大时钟 + 日期 + 剩余时间（v0.8） ----------
        Column {
            id: mainInfo
            visible: !overlay.heavyLock
            anchors.left: parent.left
            anchors.leftMargin: Math.round(overlay.width * 0.085)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(overlay.width * 0.42, 760)
            spacing: 12

            Row {
                spacing: 10
                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "ripple"
                    size: 18
                    color: AppTheme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: overlay.previewing
                          ? qsTr("预览 · %1档").arg(overlay.levelLabel)
                          : (overlay.spaceName !== "" ? overlay.spaceName : qsTr("专注中"))
                    color: AppTheme.textSecondary
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    font.family: C.numFont
                    font.letterSpacing: 2
                }
            }

            Text {
                id: clockTextDisplay
                text: overlay.clockTime
                color: AppTheme.textPrimary
                font.family: C.monoFont
                font.pixelSize: Math.max(96, Math.min(overlay.width * 0.13, overlay.height * 0.22))
                font.weight: Font.Light
                font.letterSpacing: 4
            }

            Text {
                text: overlay.clockDate
                color: AppTheme.textSecondary
                font.pixelSize: 16
                font.family: C.numFont
                font.letterSpacing: 2
            }

            Item {
                width: parent.width
                height: 12
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: AppTheme.glass ? "#1AFFFFFF" : AppTheme.divider
                    border.width: 1
                    border.color: AppTheme.glass ? "#2BFFFFFF" : AppTheme.cardBorder
                }
                Rectangle {
                    width: parent.width * overlay.progressValue
                    height: parent.height
                    radius: parent.height / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#2B86FF" }
                        GradientStop { position: 0.55; color: "#2ED3C6" }
                        GradientStop { position: 1.0; color: "#7FE7DA" }
                    }
                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                }
            }

            Row {
                spacing: 12
                Text {
                    id: mainCountdownText
                    objectName: "MainCountdown"
                    text: overlay.remainingTextValue
                    color: overlay.countdownFinal ? AppTheme.danger : AppTheme.textPrimary
                    Behavior on color {
                        enabled: overlay.animationsEnabled
                        ColorAnimation { duration: 140 }
                    }
                    font.family: C.monoFont
                    font.pixelSize: 34
                    font.weight: Font.Light
                    font.letterSpacing: 2
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: overlay.previewing
                          ? qsTr("预览剩余 · 不计入专注统计")
                          : qsTr("剩余 · 已完成 %1%").arg(overlay.percentValue)
                    color: AppTheme.textSecondary
                    font.pixelSize: 14
                    font.family: C.numFont
                }
            }

            Text {
                text: overlay.previewing ? qsTr("10 秒假倒计时，仅用于预览遮罩效果")
                                          : (overlay.trial ? qsTr("体验模式 · 可提前结束")
                                                           : qsTr("可以暂停，但时间不会等你"))
                color: AppTheme.textTertiary
                font.pixelSize: 13
                font.family: C.numFont
            }
        }

        // ---------- 深清：只保留倒计时 ----------
        Text {
            id: heavyCountdownText
            visible: overlay.heavyLock
            anchors.centerIn: parent
            text: overlay.remainingTextValue
            color: AppTheme.textPrimary
            Behavior on color {
                enabled: overlay.animationsEnabled
                ColorAnimation { duration: 140 }
            }
            font.family: C.monoFont
            font.pixelSize: Math.max(140, Math.min(overlay.width * 0.20, overlay.height * 0.32))
            font.weight: Font.Light
            font.letterSpacing: 4
        }

        // ---------- 右侧自定义组件区（v0.8；预览模式下可增删） ----------
        Column {
            id: rightWidgets
            visible: !overlay.heavyLock
            z: 2
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.top: parent.top
            anchors.topMargin: overlay.mediumDock ? 96 : 96
            width: 300
            spacing: 10

            Row {
                width: parent.width
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("组件")
                    color: AppTheme.textTertiary
                    font.pixelSize: 12
                    font.family: C.numFont
                    font.letterSpacing: 2
                }

                Item { width: parent.width - 150; height: 1 }

                Item {
                    id: addWidgetButton
                    visible: overlay.previewing
                    width: 96
                    height: 28
                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: addWidgetArea.containsMouse ? (AppTheme.glass ? "#33FFFFFF" : AppTheme.cardBgAlt) : "#1AFFFFFF"
                        border.width: 1
                        border.color: "#40FFFFFF"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("＋ 添加组件")
                        color: AppTheme.textSecondary
                        font.pixelSize: 11
                        font.family: C.numFont
                    }
                    MouseArea {
                        id: addWidgetArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: overlay.widgetMenuOpen = !overlay.widgetMenuOpen
                    }
                }
            }

            Repeater {
                model: overlay.widgetIds

                delegate: Item {
                    id: widgetCard
                    width: rightWidgets.width
                    height: cardColumn.implicitHeight + 24

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: AppTheme.glass ? "#1AFFFFFF" : AppTheme.cardBg
                        border.width: 1
                        border.color: AppTheme.glass ? "#33FFFFFF" : AppTheme.cardBorder
                    }

                    Column {
                        id: cardColumn
                        x: 14
                        y: 12
                        width: parent.width - 28
                        spacing: 4

                        Row {
                            width: parent.width
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: overlay.widgetTitle(String(modelData))
                                color: AppTheme.textTertiary
                                font.pixelSize: 11
                                font.family: C.numFont
                                font.letterSpacing: 1
                            }
                            Item { width: parent.width - 92; height: 1 }
                            Item {
                                visible: overlay.previewing
                                width: 20
                                height: 20
                                Glyph {
                                    anchors.centerIn: parent
                                    kind: "close"
                                    size: 10
                                    color: removeArea.containsMouse ? AppTheme.danger : AppTheme.textTertiary
                                }
                                MouseArea {
                                    id: removeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: overlay.removeWidget(String(modelData))
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: overlay.widgetValue(String(modelData))
                            color: AppTheme.textPrimary
                            font.pixelSize: 14
                            font.family: C.numFont
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // 添加组件菜单
            Column {
                visible: overlay.widgetMenuOpen && overlay.previewing
                width: parent.width
                spacing: 6

                Repeater {
                    model: {
                        var out = []
                        for (var i = 0; i < overlay.allWidgetIds.length; i++) {
                            if (overlay.widgetIds.indexOf(overlay.allWidgetIds[i]) < 0)
                                out.push(overlay.allWidgetIds[i])
                        }
                        return out
                    }
                    delegate: Item {
                        width: parent.width
                        height: 34
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: overlay.widgetTitle(String(modelData))
                            color: addItemArea.containsMouse ? AppTheme.accent : AppTheme.textSecondary
                            font.pixelSize: 12
                            font.family: C.numFont
                        }
                        MouseArea {
                            id: addItemArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: overlay.addWidget(String(modelData))
                        }
                    }
                }
            }
        }

        // ---------- 插件组件区（App.pluginWidgets，按 anchor 四角定位） ----------
        Item {
            id: widgetLayer
            visible: !overlay.heavyLock
            anchors.fill: parent
            z: 1

            Repeater {
                model: App.pluginWidgets !== undefined ? App.pluginWidgets : []

                delegate: Loader {
                    id: widgetLoader
                    readonly property var widgetData: modelData
                    readonly property string anchorName: widgetData.anchor !== undefined
                                                          ? String(widgetData.anchor) : "topLeft"
                    readonly property bool rightSide: anchorName === "topRight"
                                                      || anchorName === "bottomRight"
                    readonly property bool bottomSide: anchorName === "bottomLeft"
                                                       || anchorName === "bottomRight"

                    width: widgetData.width !== undefined ? Number(widgetData.width) : 240
                    height: widgetData.height !== undefined ? Number(widgetData.height) : 120
                    source: (widgetData.qmlPath !== undefined && String(widgetData.qmlPath) !== "")
                            ? String(widgetData.qmlPath) : ""
                    x: widgetLoader.rightSide ? overlay.width - widgetLoader.width - 28 : 28
                    // 底部组件上移，给「暂停 / 提前结束」留出点击空间
                    y: widgetLoader.bottomSide
                       ? overlay.height - widgetLoader.height - 104
                       : 92
                }
            }
        }

        // ---------- 右上灵动岛 ----------
        MediaIsland {
            id: island
            visible: !overlay.heavyLock
            z: 2
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 28
            anchors.topMargin: 28
            glassSource: content.glassSource
            hasMedia: overlay.hasMedia
            mediaTitle: overlay.mediaTitleText
            mediaArtist: overlay.mediaArtistText
            mediaAlbum: overlay.mediaAlbumText
            mediaApp: overlay.mediaAppText
            mediaPlaying: overlay.mediaPlayingValue
            mediaPosition: overlay.mediaPositionValue
            mediaDuration: overlay.mediaDurationValue
            focusLine: overlay.previewing
                       ? qsTr("预览 · %1").arg(overlay.levelLabel)
                       : qsTr("专注中 · 剩余 %1").arg(overlay.remainingTextValue)
            focusSub: overlay.spaceName !== ""
                      ? qsTr("%1 · 已完成 %2%").arg(overlay.spaceName).arg(overlay.percentValue)
                      : qsTr("已完成 %1%").arg(overlay.percentValue)
            onTogglePlay: if (typeof App.mediaToggle === "function") App.mediaToggle()
            onNextTrack: if (typeof App.mediaNext === "function") App.mediaNext()
            onPrevTrack: if (typeof App.mediaPrev === "function") App.mediaPrev()
        }

        // ---------- 覆清档右侧竖向 dock ----------
        Item {
            id: dockLayer
            z: 3
            visible: overlay.mediumDock
            anchors.right: parent.right
            anchors.rightMargin: 44
            anchors.verticalCenter: parent.verticalCenter
            width: overlay.dockCount === 0 ? 168 : 92
            height: dockPanel.height + 24

            Rectangle {
                id: dockBg
                anchors.fill: parent
                radius: 26
                color: AppTheme.glass ? "#1AFFFFFF" : AppTheme.cardBg
                border.width: 1
                border.color: AppTheme.glass ? "#3DFFFFFF" : AppTheme.cardBorder
            }

            LiquidGlass {
                anchors.fill: parent
                visible: AppTheme.glass
                sourceItem: content.glassSource
                radius: 26
                depth: 0.85
                frost: 0.03
                aberration: 0.32
                highlight: 0.8
                whiten: 0.02
                tintAlpha: 0.16
                tint: AppTheme.glassTint
                sheen: 0.35
            }

            Rectangle {
                anchors.fill: parent
                visible: AppTheme.glass
                radius: 26
                color: "transparent"
                border.width: 1
                border.color: "#33FFFFFF"
            }

            Column {
                id: dockPanel
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                Text {
                    visible: overlay.dockCount === 0
                    width: 136
                    text: qsTr("未设置允许使用的应用")
                    color: AppTheme.textTertiary
                    font.pixelSize: 12
                    font.family: C.numFont
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Repeater {
                    model: overlay.dockApps

                    delegate: Item {
                        id: dockItem
                        width: 64
                        height: 64
                        readonly property string appName: modelData.name !== undefined
                                                          ? String(modelData.name) : String(modelData.exe)

                        Rectangle {
                            anchors.fill: parent
                            radius: 18
                            color: dockPointer.containsMouse
                                   ? (AppTheme.glass ? "#33FFFFFF" : AppTheme.buttonBgAlt)
                                   : (AppTheme.glass ? "#1FFFFFFF" : AppTheme.buttonBg)
                            border.width: 1
                            border.color: AppTheme.glass ? "#33FFFFFF" : AppTheme.buttonBorder
                            Behavior on color { ColorAnimation { duration: 130 } }
                        }

                        // 应用图标：iconUrl 可用时显示图片，失败降级为首字
                        Item {
                            id: iconHolder
                            anchors.fill: parent
                            anchors.margins: 10

                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: modelData.iconUrl !== undefined && String(modelData.iconUrl) !== ""
                                        ? String(modelData.iconUrl) : ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: appIcon.status !== Image.Ready
                                text: {
                                    var t = dockItem.appName
                                    return t.length > 0 ? t.substring(0, 1).toUpperCase() : "?"
                                }
                                color: AppTheme.textPrimary
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                                font.family: C.numFont
                            }
                        }

                        MouseArea {
                            id: dockPointer
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof App.launchApp === "function")
                                    App.launchApp(String(modelData.exe))
                            }
                        }

                        // 名称 tooltip
                        Rectangle {
                            id: dockTip
                            visible: dockPointer.containsMouse
                            z: 10
                            anchors.right: parent.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: tipText.implicitWidth + 20
                            height: 28
                            radius: 14
                            color: AppTheme.glass ? "#E6122634" : AppTheme.cardBg
                            border.width: 1
                            border.color: AppTheme.glass ? "#33FFFFFF" : AppTheme.cardBorder
                            Text {
                                id: tipText
                                anchors.centerIn: parent
                                text: dockItem.appName
                                color: AppTheme.textPrimary
                                font.pixelSize: 12
                                font.family: C.numFont
                            }
                        }
                    }
                }
            }
        }

        // ---------- 右下控制按钮 ----------
        Row {
            z: 4
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 32
            anchors.bottomMargin: 32
            spacing: 12

            GlassButton {
                visible: overlay.previewing
                text: qsTr("结束预览")
                tone: "light"
                fontSize: 14
                padH: 24
                minHeight: 46
                onClicked: if (typeof App.stopPreview === "function") App.stopPreview()
            }

            GlassButton {
                visible: !overlay.previewing && !overlay.heavyLock
                text: App.state === "paused" ? qsTr("继续") : qsTr("暂停")
                tone: "light"
                fontSize: 14
                padH: 24
                minHeight: 46
                onClicked: {
                    if (App.state === "paused") App.resumeSession()
                    else App.pauseSession()
                }
            }

            GlassButton {
                // 深清档默认不显示；体验模式允许提前结束
                visible: !overlay.previewing && (!overlay.heavyLock || overlay.trial)
                text: overlay.trial ? qsTr("结束体验") : qsTr("提前结束")
                tone: "ghost"
                fontSize: 14
                padH: 24
                minHeight: 46
                onClicked: App.stopSession()
            }
        }

        // ---------- v0.8：dock 设置面板（音量 / 关机 / 重启） ----------
        Item {
            id: dockSettingsLayer
            anchors.fill: parent
            z: 20
            visible: overlay.dockSettingsOpen || overlay.powerConfirmOpen
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: overlay.closeDockSettings()
            }
            Rectangle { anchors.fill: parent; color: "#99040A10" }

            Rectangle {
                id: dockSettingsPanel
                anchors.centerIn: parent
                width: 440
                height: settingsColumn.implicitHeight + 44
                radius: 22
                color: AppTheme.glass ? "#F20A1B26" : AppTheme.cardBg
                border.width: 1
                border.color: AppTheme.glass ? "#4DFFFFFF" : AppTheme.cardBorderStrong
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: {} }

                Column {
                    id: settingsColumn
                    x: 22
                    y: 20
                    width: parent.width - 44
                    spacing: 14

                    Row {
                        width: parent.width
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("声音与电源")
                            color: AppTheme.textPrimary
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            font.family: C.numFont
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: AppTheme.divider }

                    Row {
                        width: parent.width
                        spacing: 10
                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            kind: "volume"
                            size: 16
                            color: AppTheme.textSecondary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("系统音量")
                            color: AppTheme.textPrimary
                            font.pixelSize: 13
                            font.family: C.numFont
                        }
                        Item { width: parent.width - 260; height: 1 }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(overlay.volumeDraft) + "%"
                            color: AppTheme.accent
                            font.pixelSize: 13
                            font.family: C.monoFont
                        }
                    }

                    GlassSlider {
                        width: parent.width
                        height: 30
                        from: 0
                        to: 100
                        step: 1
                        value: overlay.volumeDraft
                        enabled: (typeof App !== "undefined" && App.systemVolume !== undefined
                                  && Number(App.systemVolume) >= 0)
                        onMoved: (value) => overlay.setVolume(value)
                    }

                    Text {
                        width: parent.width
                        visible: typeof App !== "undefined" && App.systemVolume !== undefined
                                 && Number(App.systemVolume) < 0
                        text: qsTr("当前系统不支持音量调节")
                        color: AppTheme.textTertiary
                        font.pixelSize: 11
                        font.family: C.numFont
                    }

                    Rectangle { width: parent.width; height: 1; color: AppTheme.divider }

                    Row {
                        width: parent.width
                        spacing: 10
                        GlassButton {
                            text: qsTr("关机")
                            tone: "ghost"
                            fontSize: 13
                            padH: 22
                            minHeight: 38
                            onClicked: overlay.requestPower("shutdown")
                        }
                        GlassButton {
                            text: qsTr("重启")
                            tone: "ghost"
                            fontSize: 13
                            padH: 22
                            minHeight: 38
                            onClicked: overlay.requestPower("restart")
                        }
                        Item { width: parent.width - 260; height: 1 }
                        GlassButton {
                            text: qsTr("关闭")
                            tone: "light"
                            fontSize: 12
                            padH: 16
                            minHeight: 34
                            onClicked: overlay.closeDockSettings()
                        }
                    }

                    Text {
                        width: parent.width
                        text: qsTr("关机 / 重启会先弹出确认，避免误触。")
                        color: AppTheme.textTertiary
                        font.pixelSize: 11
                        font.family: C.numFont
                    }
                }
            }

            Rectangle {
                visible: overlay.powerConfirmOpen
                anchors.fill: parent
                color: "#AA040A10"
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: overlay.powerConfirmOpen = false }
                Rectangle {
                    anchors.centerIn: parent
                    width: 400
                    height: confirmColumn.implicitHeight + 40
                    radius: 20
                    color: AppTheme.cardBg
                    border.width: 1
                    border.color: AppTheme.cardBorderStrong
                    Column {
                        id: confirmColumn
                        x: 22
                        y: 20
                        width: parent.width - 44
                        spacing: 14
                        Text {
                            width: parent.width
                            text: overlay.pendingPower === "shutdown" ? qsTr("确认关机？") : qsTr("确认重启？")
                            color: AppTheme.textPrimary
                            font.pixelSize: 17
                            font.weight: Font.Bold
                            font.family: C.numFont
                        }
                        Text {
                            width: parent.width
                            text: qsTr("系统会立即执行该操作，未保存的工作可能丢失。")
                            color: AppTheme.textSecondary
                            font.pixelSize: 12
                            font.family: C.numFont
                            wrapMode: Text.WordWrap
                        }
                        Row {
                            width: parent.width
                            spacing: 10
                            Item { width: parent.width - 200; height: 1 }
                            GlassButton {
                                text: qsTr("取消")
                                tone: "ghost"
                                fontSize: 13
                                padH: 18
                                minHeight: 36
                                onClicked: overlay.powerConfirmOpen = false
                            }
                            Rectangle {
                                width: 118
                                height: 36
                                radius: 18
                                color: confirmArea.containsMouse ? "#F06870" : AppTheme.danger
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("确认执行")
                                    color: "#FFFFFF"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    font.family: C.numFont
                                }
                                MouseArea {
                                    id: confirmArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: overlay.confirmPower()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
