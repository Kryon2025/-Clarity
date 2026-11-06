import QtQuick
import QtQuick.Window
import QtQuick.Effects
import "../theme"
import "../components"
import "../glass"
import "../components/Constants.js" as C

// v0.8 专注结束「今日专注卡片」（OPPO 禅定空间风格）
// 流程：全屏水滴汇聚成中心光点（~0.8s）→ 光点闪烁 → 展开成今日专注卡片
// 数据优先取 App.lastSession / App.dailyQuote / App.bingWallpaperUrl / App.userAvatarUrl（缺失时本地兜底）
// 操作：App.shareSummary / App.saveSummaryImage / App.extendSession（缺失时本地提示并上报）
Window {
    id: overlay
    objectName: "FocusSummary"
    title: qsTr("深清 · 今日专注")
    property bool animationsEnabled: true
    width: Screen.width
    height: Screen.height

    property bool showing: false
    property bool closing: false
    property bool hasShown: false
    property var summary: ({})
    property real converge01: 0
    property real cardScale: 0.2
    property real cardOpacity: 0
    property bool cardReady: false
    property int bgStyle: 0
    property string toastText: ""
    property bool toastVisible: false
    readonly property int particleCount: 72

    readonly property string spaceName: (overlay.summary.spaceName !== undefined) ? String(overlay.summary.spaceName) : ""
    readonly property string levelLabel: {
        var lv = (overlay.summary.level !== undefined) ? String(overlay.summary.level) : ""
        if (lv === "light") return qsTr("浅清")
        if (lv === "medium") return qsTr("覆清")
        if (lv === "heavy") return qsTr("深清")
        return qsTr("专注")
    }
    readonly property string displaySpace: overlay.spaceName !== "" ? overlay.spaceName : overlay.levelLabel
    readonly property string quote: (overlay.summary.quote !== undefined && String(overlay.summary.quote) !== "")
                                    ? String(overlay.summary.quote)
                                    : qsTr("把注意力收回来，今天也算没有白过。")
    readonly property string avatarUrl: (overlay.summary.avatarUrl !== undefined) ? String(overlay.summary.avatarUrl) : ""
    readonly property string wallpaperUrl: (overlay.summary.wallpaperUrl !== undefined) ? String(overlay.summary.wallpaperUrl) : ""
    readonly property int minutes: (overlay.summary.minutes !== undefined)
                                   ? Math.max(1, Math.round(Number(overlay.summary.minutes))) : 1
    readonly property string dateRange: overlay.formatRange()
    readonly property int cardWidth: Math.min(520, Math.round(overlay.width * 0.34))
    readonly property int cardHeight: Math.round(overlay.cardWidth * 1.30)

    visibility: (overlay.showing || overlay.closing) ? Window.FullScreen : Window.Hidden
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"

    function pad2(n) { return n < 10 ? "0" + n : String(n) }
    function formatDate(ms) {
        var d = new Date(ms)
        return d.getFullYear() + "/" + overlay.pad2(d.getMonth() + 1) + "/" + overlay.pad2(d.getDate())
               + " " + overlay.pad2(d.getHours()) + ":" + overlay.pad2(d.getMinutes())
    }
    function formatRange() {
        var now = Date.now()
        var start = (overlay.summary.startMs !== undefined) ? Number(overlay.summary.startMs) : now
        var end = (overlay.summary.endMs !== undefined) ? Number(overlay.summary.endMs) : now
        if (overlay.summary.dateText !== undefined && String(overlay.summary.dateText) !== "")
            return String(overlay.summary.dateText)
        return overlay.formatDate(start) + " - " + overlay.formatDate(end).substring(11)
    }
    function showToast(text) {
        overlay.toastText = text
        overlay.toastVisible = true
        toastTimer.restart()
    }
    function showSummary(data) {
        overlay.summary = data || ({})
        overlay.bgStyle = 0
        overlay.cardReady = false
        overlay.closing = false
        overlay.hasShown = true
        overlay.showing = true
        overlay.converge01 = 0
        overlay.cardScale = 0.2
        overlay.cardOpacity = 0
        sceneRoot.opacity = overlay.animationsEnabled ? 0 : 1
        if (overlay.animationsEnabled) enterAnim.restart()
        overlay.show()
        overlay.raise()
        overlay.requestActivate()
        if (overlay.animationsEnabled) {
            convergeAnim.restart()
            revealAnim.restart()
        } else {
            overlay.finishReveal()
        }
    }
    function finishReveal() {
        overlay.converge01 = 1
        overlay.cardScale = 1
        overlay.cardOpacity = 1
        overlay.sceneRoot.opacity = 1
        overlay.cardReady = true
    }
    function hide() {
        if (!overlay.hasShown || overlay.closing) return
        if (!overlay.animationsEnabled) {
            overlay.showing = false
            overlay.hasShown = false
            sceneRoot.opacity = 0
            return
        }
        overlay.closing = true
        hideAnim.restart()
    }
    function editBackground() {
        overlay.bgStyle = (overlay.bgStyle + 1) % 4
        overlay.showToast(qsTr("背景已切换"))
    }
    function copyTextSummary() {
        var text = qsTr("来自深清 · %1 · %2 分钟\n%3").arg(overlay.displaySpace).arg(overlay.minutes).arg(overlay.quote)
        clipHelper.text = text
        clipHelper.selectAll()
        clipHelper.copy()
        overlay.showToast(qsTr("已复制"))
    }
    function shareSummary() {
        if (typeof App !== "undefined" && typeof App.shareSummary === "function") {
            var text = App.shareSummary()
            if (typeof text === "string" && text !== "") {
                clipHelper.text = text
                clipHelper.selectAll()
                clipHelper.copy()
                overlay.showToast(qsTr("摘要已复制"))
            } else {
                overlay.showToast(qsTr("已发起分享"))
            }
        } else {
            overlay.copyTextSummary()
        }
    }
    function saveSummary() {
        var path = ""
        if (typeof App !== "undefined" && typeof App.saveSummaryImage === "function")
            path = String(App.saveSummaryImage() || "")
        if (path !== "") {
            overlay.showToast(qsTr("图片已保存"))
            return
        }
        // 后端不渲染图片：QML 自己截图，保存到数据目录（路径接口缺失时提示）
        card.grabToImage(function (result) {
            var dir = (typeof App !== "undefined" && App.dataDir !== undefined) ? String(App.dataDir) : ""
            if (dir !== "") {
                var ok = result.saveToFile("file:///" + dir.replace(/\\/g, "/") + "/summary.png")
                overlay.showToast(ok ? qsTr("图片已保存到数据目录") : qsTr("保存图片失败"))
            } else {
                overlay.showToast(qsTr("保存图片需要数据目录接口"))
            }
        })
    }
    function extendSession() {
        if (typeof App !== "undefined" && typeof App.extendSession === "function") {
            App.extendSession(20)
            overlay.hide()
        } else {
            overlay.showToast(qsTr("延长专注需要后端接口支持"))
        }
    }

    Timer {
        id: toastTimer
        interval: 2200
        repeat: false
        onTriggered: overlay.toastVisible = false
    }
    TextEdit {
        id: clipHelper
        visible: false
        width: 1
        height: 1
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation {
            target: sceneRoot
            property: "opacity"
            from: 0
            to: 1
            duration: overlay.animationsEnabled ? 220 : 0
            easing.type: Easing.OutCubic
        }
    }

    NumberAnimation {
        id: convergeAnim
        target: overlay
        property: "converge01"
        from: 0
        to: 1
        duration: overlay.animationsEnabled ? 800 : 0
        easing.type: Easing.OutCubic
    }
    SequentialAnimation {
        id: revealAnim
        PauseAnimation { duration: overlay.animationsEnabled ? 560 : 0 }
        ParallelAnimation {
            NumberAnimation {
                target: overlay
                property: "cardScale"
                to: 1
                duration: overlay.animationsEnabled ? 420 : 0
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: overlay
                property: "cardOpacity"
                to: 1
                duration: overlay.animationsEnabled ? 320 : 0
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction { script: overlay.cardReady = true }
    }
    ParallelAnimation {
        id: hideAnim
        NumberAnimation {
            target: sceneRoot
            property: "opacity"
            to: 0
            duration: overlay.animationsEnabled ? 180 : 0
            easing.type: Easing.OutCubic
        }
        onFinished: {
            overlay.closing = false
            overlay.showing = false
            overlay.hasShown = false
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: overlay.hide()
    }

    Item {
        id: sceneRoot
        anchors.fill: parent
        opacity: 1

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(AppTheme.overlayTop.r, AppTheme.overlayTop.g, AppTheme.overlayTop.b, 0.985)
        }

        // 汇聚阶段：粒子从四周飞向中心光点
        Item {
            anchors.fill: parent
            opacity: 1 - overlay.cardOpacity
            visible: overlay.cardOpacity < 0.98

            Repeater {
                model: overlay.particleCount

                delegate: Item {
                    id: dot
                    readonly property int idx: index
                    readonly property real a: idx / overlay.particleCount * Math.PI * 2
                    readonly property real dist: Math.max(overlay.width, overlay.height)
                                                  * (0.35 + overlay.randLike(idx) * 0.35)
                    readonly property real r: dist * (1 - overlay.converge01)
                                                * (0.45 + overlay.randLike(idx + 7) * 0.55)
                    width: 3 + overlay.randLike(idx + 3) * 4
                    height: width
                    x: overlay.width / 2 + Math.cos(dot.a) * dot.r - width / 2
                    y: overlay.height / 2 + Math.sin(dot.a) * dot.r - height / 2
                    opacity: overlay.converge01 <= 0 ? 0
                             : Math.min(1, overlay.converge01 * 2) * (1 - Math.max(0, overlay.converge01 - 0.85) * 6)
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "#7FE7DA"
                    }
                }
            }

            // 中心光点 + 闪烁
            Item {
                anchors.centerIn: parent
                width: 40
                height: 40
                scale: overlay.converge01 < 0.75 ? 0.2
                       : (overlay.converge01 < 0.95 ? 1.6 : 2.2 * (1 - overlay.cardOpacity))
                opacity: overlay.converge01 < 0.2 ? 0 : Math.min(1, (overlay.converge01 - 0.2) * 2.2)
                         * (1 - overlay.cardOpacity * 0.9)

                Rectangle {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    radius: 10
                    color: "#E8FCFF"
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 40
                    height: 40
                    radius: 20
                    color: "#2ED3C6"
                    opacity: 0.25
                }
            }
        }

        // 今日专注卡片
        Item {
            id: card
            width: overlay.cardWidth
            height: overlay.cardHeight
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Math.round(overlay.height * 0.03)
            scale: overlay.cardScale
            opacity: overlay.cardOpacity

            Rectangle {
                id: cardBg
                anchors.fill: parent
                radius: 28
                color: "#0E2A38"
                border.width: 1
                border.color: "#33FFFFFF"

                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#16405A" }
                    GradientStop { position: 0.55; color: "#0E2A38" }
                    GradientStop { position: 1.0; color: "#081C28" }
                }
            }

            // Bing 壁纸 / 渐变背景（风格切换）
            Image {
                id: wallpaper
                anchors.fill: parent
                visible: false
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                source: (overlay.bgStyle === 0 && overlay.wallpaperUrl !== "") ? overlay.wallpaperUrl : ""
            }
            MultiEffect {
                anchors.fill: parent
                visible: wallpaper.source !== "" && wallpaper.status === Image.Ready
                source: wallpaper
                maskEnabled: true
                maskSource: cardMask
                brightness: -0.12
            }
            Rectangle {
                id: cardMask
                anchors.fill: parent
                radius: 28
                color: "#FFFFFF"
                visible: false
            }

            // 背景纯色/渐变兜底（编辑背景循环）
            Rectangle {
                anchors.fill: parent
                radius: 28
                visible: wallpaper.status !== Image.Ready
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: overlay.bgStyle === 1 ? "#2E4B6E"
                                                          : overlay.bgStyle === 2 ? "#5A3C4F"
                                                          : (overlay.bgStyle === 3 ? "#12212B" : "#1B4258") }
                    GradientStop { position: 1.0; color: "#08131B" }
                }
            }

            // 可读性遮罩
            Rectangle {
                anchors.fill: parent
                radius: 28
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#33000000" }
                    GradientStop { position: 0.45; color: "#55070F16" }
                    GradientStop { position: 1.0; color: "#CC060C12" }
                }
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                spacing: 12

                Row {
                    width: parent.width
                    spacing: 12

                    Item {
                        width: 54
                        height: 54
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "#2ED3C6"
                            visible: overlay.avatarUrl === ""

                            Text {
                                anchors.centerIn: parent
                                text: "深"
                                color: "#04222B"
                                font.pixelSize: 22
                                font.weight: Font.Bold
                                font.family: C.numFont
                            }
                        }
                        Image {
                            anchors.fill: parent
                            visible: overlay.avatarUrl !== ""
                            source: overlay.avatarUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: avatarMask
                            }
                        }
                        Rectangle {
                            id: avatarMask
                            anchors.fill: parent
                            radius: width / 2
                            color: "#FFFFFF"
                            visible: false
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: qsTr("来自深清")
                            color: "#B3DDE8"
                            font.pixelSize: 12
                            font.family: C.numFont
                        }
                        Text {
                            text: overlay.dateRange
                            color: "#8FB7C6"
                            font.pixelSize: 11
                            font.family: C.numFont
                        }
                    }

                    Item { width: parent.width - 54 - 12 - 220; height: 1 }
                }

                Item {
                    width: parent.width
                    height: 4
                }

                Text {
                    width: parent.width
                    text: overlay.displaySpace
                    color: "#EFF9FF"
                    font.pixelSize: 26
                    font.weight: Font.Bold
                    font.family: C.numFont
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: overlay.quote
                    color: "#C7E3EC"
                    font.pixelSize: 14
                    font.family: C.numFont
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                }
            }

            // 底部大字：本次时长
            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 24
                spacing: 2

                Text {
                    text: qsTr("本次专注")
                    color: "#8FB7C6"
                    font.pixelSize: 12
                    font.family: C.numFont
                    font.letterSpacing: 1
                }

                Row {
                    spacing: 8
                    Text {
                        text: String(overlay.minutes)
                        color: "#FFFFFF"
                        font.pixelSize: Math.round(overlay.cardWidth * 0.19)
                        font.weight: Font.Light
                        font.family: C.monoFont
                    }
                    Text {
                        anchors.baseline: parent.children[0].baseline
                        text: qsTr("分钟")
                        color: "#CFEAF2"
                        font.pixelSize: 18
                        font.family: C.numFont
                    }
                }
            }

            // 编辑背景
            Item {
                id: editBgButton
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                width: editBgText.implicitWidth + 24
                height: 30

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: editBgArea.containsMouse ? "#40FFFFFF" : "#26000000"
                    border.width: 1
                    border.color: "#40FFFFFF"
                }
                Text {
                    id: editBgText
                    anchors.centerIn: parent
                    text: qsTr("编辑背景")
                    color: "#E8F6FA"
                    font.pixelSize: 11
                    font.family: C.numFont
                }
                MouseArea {
                    id: editBgArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: overlay.editBackground()
                }
            }
        }

        // 左上返回 / 右上保存
        Item {
            id: backButton
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 26
            width: 40
            height: 40
            Rectangle {
                anchors.fill: parent
                radius: 20
                color: backArea.containsMouse ? "#33FFFFFF" : "#1A000000"
                border.width: 1
                border.color: "#40FFFFFF"
            }
            Glyph {
                anchors.centerIn: parent
                kind: "back"
                size: 18
                color: "#EAF8FB"
            }
            MouseArea {
                id: backArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: overlay.hide()
            }
        }

        Item {
            id: saveButton
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 26
            width: 40
            height: 40
            Rectangle {
                anchors.fill: parent
                radius: 20
                color: saveArea.containsMouse ? "#33FFFFFF" : "#1A000000"
                border.width: 1
                border.color: "#40FFFFFF"
            }
            Glyph {
                anchors.centerIn: parent
                kind: "download"
                size: 18
                color: "#EAF8FB"
            }
            MouseArea {
                id: saveArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: overlay.saveSummary()
            }
        }

        // 卡片下方按钮
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: card.bottom
            anchors.topMargin: 18
            spacing: 12
            visible: overlay.cardReady

            Item {
                width: shareText.implicitWidth + 40
                height: 38
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: shareArea.containsMouse ? "#2E5F76" : "#1B3A4A"
                    border.width: 1
                    border.color: "#4D9EB4"
                }
                Text {
                    id: shareText
                    anchors.centerIn: parent
                    text: qsTr("分享")
                    color: "#EAF8FB"
                    font.pixelSize: 13
                    font.family: C.numFont
                }
                MouseArea {
                    id: shareArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: overlay.shareSummary()
                }
            }

            Item {
                width: extendText.implicitWidth + 40
                height: 38
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: extendArea.containsMouse ? "#2E5F76" : "#1B3A4A"
                    border.width: 1
                    border.color: "#4D9EB4"
                }
                Text {
                    id: extendText
                    anchors.centerIn: parent
                    text: qsTr("延长 20 分钟")
                    color: "#EAF8FB"
                    font.pixelSize: 13
                    font.family: C.numFont
                }
                MouseArea {
                    id: extendArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: overlay.extendSession()
                }
            }
        }

        // toast
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            width: toastLabel.implicitWidth + 32
            height: 34
            opacity: overlay.toastVisible ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Rectangle {
                anchors.fill: parent
                radius: 17
                color: "#CC0A1B26"
                border.width: 1
                border.color: "#4DFFFFFF"
            }
            Text {
                id: toastLabel
                anchors.centerIn: parent
                text: overlay.toastText
                color: "#EAF8FB"
                font.pixelSize: 12
                font.family: C.numFont
            }
        }
    }

    function randLike(seed) {
        var x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453
        return x - Math.floor(x)
    }
}
