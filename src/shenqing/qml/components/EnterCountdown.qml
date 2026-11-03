import QtQuick
import QtQuick.Window
import QtQuick.Effects
import "../theme"
import "../components/Constants.js" as C

// 进入专注前的 10 秒倒计时（v0.6「水滴凝聚成环」）
// 过程：水滴从圆环内外随机位置凭空淡入 → 越来越多/越来越快 → 沿半径汇聚到圆环并融入
//      → 圆环由水滴凝结成形，10 秒时是一个完整发光的环（不再有游离水滴）
// 进入：完整圆环 → 放大到覆盖全屏（350ms OutCubic）→ 交给专注遮罩
// 取消：所有水滴（含已融入圆环的部分）向外随机炸开并淡出（350ms OutCubic），散完隐藏
// 所有档位 / 所有空间都走 App.prepareActive，这里不按 mode 过滤。
Window {
    id: overlay
    objectName: "EnterCountdown"
    title: qsTr("深清 · 即将进入")

    property bool animationsEnabled: true

    readonly property bool shouldShow: (typeof App !== "undefined" && App.prepareActive === true)
    readonly property int totalSeconds: 10
    readonly property int remaining: (typeof App !== "undefined" && App.prepareRemaining !== undefined)
                                      ? Math.max(0, Number(App.prepareRemaining)) : 10
    // 0→1 连续进度（进入时按剩余秒数用 NumberAnimation Linear 驱动）
    property real progress01: 0
    readonly property int dropCount: 60
    // 圆环「凝结」程度：0→1（最后 0.5s 加辉光）
    readonly property real ringFill: {
        var x = Math.max(0, Math.min(1, (overlay.progress01 - 0.08) / 0.84))
        return x * x * (3 - 2 * x)
    }
    readonly property int condensedCount: Math.round(overlay.ringFill * overlay.dropCount)
    readonly property string prepareLevel: (typeof App !== "undefined" && App.prepareLevel !== undefined)
                                            ? String(App.prepareLevel) : ""
    readonly property string prepareSpaceName: (typeof App !== "undefined" && App.prepareSpaceName !== undefined)
                                                ? String(App.prepareSpaceName) : ""

    readonly property real circleSize: Math.max(220, Math.min(width, height) * 0.42)
    readonly property real ringDrawRadius: overlay.circleSize / 2 + 8
    readonly property real expandScale: Math.max(1.2, Math.max(width, height) / overlay.circleSize * 1.15)
    readonly property real scatterDistance: Math.max(width, height) * 0.62

    // 取消 / 扩散期间 App 的 prepare* 已被清空，用快照保持文案稳定
    property string displaySpaceName: ""
    property string displayLevel: ""
    // 连续进度平滑开关：正常为 true；重置/扩散时临时关掉以瞬时跳到目标
    property bool progressSmoothing: true
    Behavior on progress01 {
        enabled: overlay.animationsEnabled && overlay.progressSmoothing
        NumberAnimation { duration: overlay.animationsEnabled ? 1000 : 0; easing.type: Easing.Linear }
    }

    property bool hasShown: false
    property bool closing: false
    property bool expanding: false
    property bool finishing: false
    property bool canceling: false
    property int lastRemaining: 10
    property real scatter01: 0
    // 每滴随机参数：启动时一次性算好（出现时间/起点半径/角度/目标弧段/尺寸/飞散方向）
    property var dropData: []

    visibility: (overlay.shouldShow || overlay.closing || overlay.expanding || overlay.canceling)
                ? Window.FullScreen : Window.Hidden
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"

    function rand01(seed) {
        var x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453
        return x - Math.floor(x)
    }

    function buildDropData() {
        var list = []
        var n = overlay.dropCount
        for (var i = 0; i < n; i++) {
            var r1 = overlay.rand01(i * 1.37 + 0.11)
            var r2 = overlay.rand01(i * 2.11 + 0.53)
            var r3 = overlay.rand01(i * 3.73 + 0.29)
            var r4 = overlay.rand01(i * 5.19 + 0.71)
            var r5 = overlay.rand01(i * 7.07 + 0.37)
            var r6 = overlay.rand01(i * 9.13 + 0.97)

            var spawnAt = 0.04 + r1 * 0.66                 // 0.4s ~ 7s
            var appearDur = 0.08
            var mergeDur = 0.05 + r3 * 0.05
            var travelMax = Math.max(0.08, 0.94 - spawnAt - appearDur - mergeDur)
            var travelSpan = Math.max(0.08, Math.min(0.12 + r2 * 0.14, travelMax))

            // 起点角度均匀铺满一圈（带少量抖动），保证「从四周出现」而不是随机聚成一团
            var a0 = (i / n) * Math.PI * 2 + (r4 - 0.5) * 0.7
            var targetAngle = a0 + (r5 - 0.5) * 0.25
            var scatAngle = a0 + (r6 - 0.5) * 1.4

            list.push({
                spawnAt: spawnAt,
                travelSpan: travelSpan,
                mergeSpan: mergeDur,
                startR: 1.10 + r2 * 1.30,                  // 1.1~2.4 倍圆半径
                angle0: a0,
                targetAngle: targetAngle,
                size: 6 + r5 * 12,                         // 直径 6~18px
                phase: r3 * Math.PI * 2,
                wobAmp: 1.0 + r3 * 2.4,
                wobSpeed: 0.7 + r1 * 1.2,
                scatterDist: overlay.scatterDistance * (0.35 + r6 * 0.85),
                sx: Math.cos(scatAngle),
                sy: Math.sin(scatAngle)
            })
        }
        return list
    }

    function modeLabel(value) {
        if (value === "light") return qsTr("浅清")
        if (value === "medium") return qsTr("覆清")
        if (value === "heavy") return qsTr("深清")
        return qsTr("专注")
    }

    function syncDisplay() {
        if (overlay.prepareSpaceName !== "") overlay.displaySpaceName = overlay.prepareSpaceName
        if (overlay.prepareLevel !== "") overlay.displayLevel = overlay.prepareLevel
    }

    function displaySpaceLabel() {
        var name = overlay.shouldShow ? overlay.prepareSpaceName : overlay.displaySpaceName
        if (name !== "") return name
        var level = overlay.shouldShow ? overlay.prepareLevel : overlay.displayLevel
        return overlay.modeLabel(level)
    }

    function progressAt(secondsLeft) {
        var left = Math.max(0, Math.min(overlay.totalSeconds, Number(secondsLeft)))
        return (overlay.totalSeconds - left) / overlay.totalSeconds
    }

    function startEnter() {
        overlay.closing = false
        overlay.expanding = false
        overlay.finishing = false
        overlay.canceling = false
        overlay.hasShown = true
        overlay.scatter01 = 0
        overlay.syncDisplay()
        overlay.lastRemaining = overlay.remaining
        overlay.progressSmoothing = false
        overlay.progress01 = overlay.progressAt(overlay.remaining)
        overlay.progressSmoothing = true
        sceneRoot.opacity = overlay.animationsEnabled ? 0 : 1
        waterLayer.scale = 1
        enterAnim.stop()
        fadeAnim.stop()
        expandAnim.stop()
        scatterAnim.stop()
        if (overlay.animationsEnabled)
            enterAnim.restart()
        overlay.show()
        overlay.raise()
        overlay.requestActivate()
    }

    // 取消：水滴全部炸开并淡出，散完隐藏窗口
    function cancel() {
        if (!overlay.hasShown || overlay.canceling || overlay.closing || overlay.expanding)
            return
        overlay.canceling = true
        // 立即停止后端准备，避免 350ms 炸开期间恰好到点误进入
        if (typeof App !== "undefined" && typeof App.cancelPrepare === "function")
            App.cancelPrepare()
        if (!overlay.animationsEnabled) {
            overlay.scatter01 = 1
            overlay.finishCancelHide()
            return
        }
        overlay.scatter01 = 0
        scatterAnim.restart()
    }

    function finishCancelHide() {
        // 散完直接隐藏窗口（不再额外淡出，避免动画链未结束导致窗口残留）
        overlay.canceling = false
        overlay.closing = false
        overlay.expanding = false
        overlay.finishing = false
        overlay.hasShown = false
        sceneRoot.opacity = 0
    }

    function startFadeOut() {
        if (!overlay.hasShown) return
        overlay.closing = true
        enterAnim.stop()
        expandAnim.stop()
        if (!overlay.animationsEnabled) {
            sceneRoot.opacity = 0
            overlay.closing = false
            overlay.hasShown = false
            return
        }
        fadeAnim.restart()
    }

    function startExpand() {
        if (overlay.expanding) return
        overlay.expanding = true
        overlay.closing = false
        enterAnim.stop()
        fadeAnim.stop()
        scatterAnim.stop()
        overlay.scatter01 = 0
        overlay.progressSmoothing = false
        overlay.progress01 = 1
        overlay.progressSmoothing = true
        if (!overlay.animationsEnabled) {
            waterLayer.scale = overlay.expandScale
            sceneRoot.opacity = 0
            overlay.expanding = false
            overlay.hasShown = false
            return
        }
        sceneRoot.opacity = 1
        waterLayer.scale = 1
        expandAnim.restart()
    }

    onShouldShowChanged: {
        if (overlay.shouldShow) {
            overlay.startEnter()
        } else if (overlay.canceling) {
            // 取消路径自己控制炸开与隐藏
        } else if (overlay.hasShown && !overlay.expanding) {
            if (overlay.finishing)
                overlay.startExpand()
            else
                overlay.startFadeOut()
        }
    }

    onPrepareSpaceNameChanged: overlay.syncDisplay()
    onPrepareLevelChanged: overlay.syncDisplay()

    onRemainingChanged: {
        if (!overlay.shouldShow) return
        overlay.lastRemaining = overlay.remaining
        // 每秒更新目标进度，Behavior 用 1s Linear 平滑跟上（不跳格）
        if (!overlay.finishing) {
            var target = overlay.progressAt(overlay.remaining)
            // 最后一秒略微提前，让 10 秒时圆环已完整成形
            if (overlay.remaining === 1) target = 0.97
            overlay.progress01 = target
        }
        if (overlay.remaining <= 0) {
            overlay.finishing = true
            overlay.startExpand()
        }
    }

    Component.onCompleted: {
        overlay.dropData = overlay.buildDropData()
        if (overlay.shouldShow)
            overlay.startEnter()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: overlay.cancel()
    }

    // ---------- 取消炸开（350ms OutCubic） ----------
    NumberAnimation {
        id: scatterAnim
        target: overlay
        property: "scatter01"
        from: 0
        to: 1
        duration: overlay.animationsEnabled ? 350 : 0
        easing.type: Easing.OutCubic
        onFinished: overlay.finishCancelHide()
    }

    // ---------- 进场 / 退场 / 扩散 ----------
    ParallelAnimation {
        id: enterAnim
        NumberAnimation {
            target: sceneRoot
            property: "opacity"
            from: 0
            to: 1
            duration: overlay.animationsEnabled ? 200 : 0
            easing.type: Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: fadeAnim
        NumberAnimation {
            target: sceneRoot
            property: "opacity"
            to: 0
            duration: overlay.animationsEnabled ? 200 : 0
            easing.type: Easing.OutCubic
        }
        onFinished: {
            overlay.closing = false
            overlay.hasShown = false
        }
    }

    ParallelAnimation {
        id: expandAnim
        NumberAnimation {
            target: waterLayer
            property: "scale"
            to: overlay.expandScale
            duration: overlay.animationsEnabled ? 350 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: sceneRoot
            property: "opacity"
            to: 0
            duration: overlay.animationsEnabled ? 350 : 0
            easing.type: Easing.InCubic
        }
        onFinished: {
            overlay.expanding = false
            overlay.finishing = false
            overlay.hasShown = false
        }
    }

    // ================= 内容 =================
    Item {
        id: sceneRoot
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(AppTheme.overlayTop.r, AppTheme.overlayTop.g, AppTheme.overlayTop.b, 0.97)
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(AppTheme.bgMid.r, AppTheme.bgMid.g, AppTheme.bgMid.b, 0.55) }
                GradientStop { position: 1.0; color: Qt.rgba(AppTheme.overlayBottom.r, AppTheme.overlayBottom.g, AppTheme.overlayBottom.b, 0.55) }
            }
        }

        // 点击任意位置取消
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: overlay.cancel()
        }

        // ---------- 水滴 + 圆环层（扩散时整体放大） ----------
        Item {
            id: waterLayer
            objectName: "EnterWater"
            anchors.fill: parent
            scale: 1
            transformOrigin: Item.Center

            // 圆环组：取消时一起淡出/轻微外扩
            Item {
                id: ringGroup
                anchors.fill: parent
                opacity: 1 - overlay.scatter01

                // 圆环内水膜 / 光晕（随 ringFill 增强）
                Item {
                    anchors.centerIn: parent
                    width: overlay.circleSize
                    height: width

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.94
                        height: width
                        radius: width / 2
                        color: AppTheme.accentSoft
                        opacity: 0.04 + overlay.ringFill * 0.18
                    }

                    Rectangle {
                        id: glowCircle
                        anchors.centerIn: parent
                        width: parent.width * 0.8
                        height: width
                        radius: width / 2
                        color: AppTheme.accent
                        visible: false
                    }

                    MultiEffect {
                        source: glowCircle
                        anchors.fill: glowCircle
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 96
                        opacity: 0.06 + overlay.ringFill * 0.34
                    }
                }

                // 圆环：底环 + 由水滴凝结出的进度弧（抗锯齿、圆头、末端小圆点）
                Canvas {
                    id: ringCanvas
                    anchors.centerIn: parent
                    width: overlay.circleSize + 48
                    height: width

                    property color trackColor: AppTheme.glass ? "#2BFFFFFF" : AppTheme.cardBorder
                    property color accentColor: AppTheme.accent
                    property color glowColor: AppTheme.accentSoft
                    property real fill: overlay.ringFill
                    property real progress: overlay.progress01

                    onFillChanged: requestPaint()
                    onProgressChanged: requestPaint()
                    onTrackColorChanged: requestPaint()
                    onAccentColorChanged: requestPaint()
                    onGlowColorChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var cx = width / 2
                        var cy = height / 2
                        var r = width / 2 - 14
                        var twoPi = Math.PI * 2

                        // 底环（由细变亮）
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, 0, twoPi)
                        ctx.strokeStyle = ringCanvas.trackColor
                        ctx.lineWidth = 3
                        ctx.stroke()

                        if (ringCanvas.fill > 0.001) {
                            var startA = -Math.PI / 2
                            var endA = startA + twoPi * ringCanvas.fill
                            var lw = 2.5 + 8.5 * ringCanvas.fill

                            // 主弧：随 ringFill 变粗变亮
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, startA, endA)
                            ctx.strokeStyle = ringCanvas.accentColor
                            ctx.globalAlpha = 0.55 + 0.45 * ringCanvas.fill
                            ctx.lineWidth = lw
                            ctx.lineCap = "round"
                            ctx.stroke()

                            // 末端小圆头（未满时）
                            if (ringCanvas.fill < 0.995) {
                                ctx.beginPath()
                                ctx.arc(cx + Math.cos(endA) * r, cy + Math.sin(endA) * r, lw / 2, 0, twoPi)
                                ctx.fillStyle = ringCanvas.accentColor
                                ctx.fill()
                            }

                            // 最后 0.5s 辉光
                            if (ringCanvas.progress > 0.95) {
                                var glowT = Math.max(0, Math.min(1, (ringCanvas.progress - 0.95) / 0.05))
                                ctx.beginPath()
                                ctx.arc(cx, cy, r, startA, endA)
                                ctx.strokeStyle = ringCanvas.glowColor
                                ctx.globalAlpha = glowT * 0.55
                                ctx.lineWidth = lw + 12
                                ctx.stroke()
                            }
                            ctx.globalAlpha = 1
                        }

                        // 内侧水膜边缘
                        ctx.beginPath()
                        ctx.arc(cx, cy, r - 16, 0, twoPi)
                        ctx.strokeStyle = ringCanvas.glowColor
                        ctx.globalAlpha = 0.08 + ringCanvas.fill * 0.30
                        ctx.lineWidth = 2
                        ctx.stroke()
                        ctx.globalAlpha = 1
                    }
                }
            }

            // 60 颗水滴：凭空出现 → 沿半径汇聚到圆环 → 融入（opacity→0）；取消时向外炸开
            Repeater {
                model: overlay.dropCount

                delegate: Item {
                    id: drop
                    readonly property int dropIndex: index
                    readonly property var d: overlay.dropData.length > dropIndex
                                             ? overlay.dropData[dropIndex] : null
                    readonly property real t: drop.d === null ? 0
                                              : Math.max(0, overlay.progress01 - drop.d.spawnAt)
                    readonly property real appear: drop.d === null ? 0
                                                   : Math.min(1, drop.t / 0.08)
                    readonly property real travel: drop.d === null ? 0
                                                   : Math.min(1, Math.max(0,
                                                       (drop.t - 0.08) / drop.d.travelSpan))
                    readonly property real travelE: drop.travel * drop.travel * (3 - 2 * drop.travel)
                    readonly property real merge: drop.d === null ? 0
                                                  : Math.max(0, Math.min(1,
                                                      (drop.t - 0.08 - drop.d.travelSpan) / drop.d.mergeSpan))
                    readonly property real radiusFactor: drop.d === null ? 1
                                                          : drop.d.startR + (1.0 - drop.d.startR) * drop.travelE
                    readonly property real curAngle: drop.d === null ? 0
                                                     : drop.d.angle0
                                                       + (drop.d.targetAngle - drop.d.angle0) * drop.travelE
                                                       + Math.sin(overlay.progress01 * Math.PI * 2
                                                                  * drop.d.wobSpeed + drop.d.phase)
                                                         * drop.d.wobAmp * (1 - drop.travelE) * Math.PI / 180
                    readonly property real baseX: overlay.width / 2
                                                  + Math.cos(drop.curAngle) * overlay.ringDrawRadius
                                                    * drop.radiusFactor
                    readonly property real baseY: overlay.height / 2
                                                  + Math.sin(drop.curAngle) * overlay.ringDrawRadius
                                                    * drop.radiusFactor
                    readonly property real baseOpacity: drop.d === null ? 0
                                                        : Math.max(0, drop.appear * (0.22 + 0.78 * drop.travelE)
                                                                   * (1 - drop.merge * 0.94))
                    // 炸开时：所有水滴（包括已融入的）重新亮起并向外飞散/淡出
                    readonly property real scatterVis: overlay.scatter01 <= 0 ? 0
                                                       : Math.min(1, overlay.scatter01 / 0.18)

                    width: drop.d === null ? 10 : drop.d.size
                    height: width
                    z: 3
                    x: drop.baseX + overlay.scatter01 * (drop.d === null ? 0 : drop.d.sx) * (drop.d === null ? 0 : drop.d.scatterDist) - width / 2
                    y: drop.baseY + overlay.scatter01 * (drop.d === null ? 0 : drop.d.sy) * (drop.d === null ? 0 : drop.d.scatterDist) - height / 2
                    opacity: Math.min(1, drop.baseOpacity
                                      + (1 - overlay.scatter01) * drop.scatterVis * 0.95)
                    scale: (0.20 + 0.95 * drop.appear) * (1 + overlay.scatter01 * 0.4)

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: drop.merge > 0.3 ? "#E8FCFF" : AppTheme.accent
                        border.width: 1
                        border.color: drop.merge > 0.3 ? "#8AFFFFFF" : "#33FFFFFF"
                    }
                }
            }
        }

        // ---------- 中央文字（数字不缩放） ----------
        Column {
            anchors.centerIn: parent
            spacing: Math.round(overlay.circleSize * 0.045)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: String(overlay.shouldShow ? overlay.remaining : overlay.lastRemaining)
                color: AppTheme.textPrimary
                font.family: C.monoFont
                font.pixelSize: Math.round(overlay.circleSize * 0.30)
                font.weight: Font.Light
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("即将进入 · %1").arg(overlay.displaySpaceLabel())
                color: AppTheme.textSecondary
                font.pixelSize: Math.max(14, Math.round(overlay.circleSize * 0.055))
                font.family: C.numFont
                font.letterSpacing: 1
            }
        }

        // ---------- 底部：取消按钮 + 提示 ----------
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(34, Math.round(overlay.height * 0.06))
            spacing: 12

            Item {
                id: cancelButton
                objectName: "EnterCancelButton"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(84, cancelLabel.implicitWidth + 36)
                height: 34

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: cancelArea.containsMouse
                           ? (AppTheme.glass ? "#26FFFFFF" : AppTheme.cardBgAlt)
                           : "transparent"
                    border.width: 1
                    border.color: AppTheme.glass ? "#55FFFFFF" : AppTheme.cardBorderStrong
                }

                Text {
                    id: cancelLabel
                    anchors.centerIn: parent
                    text: qsTr("取消")
                    color: AppTheme.textSecondary
                    font.pixelSize: 13
                    font.family: C.numFont
                }

                MouseArea {
                    id: cancelArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: overlay.cancel()
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("点击任意位置取消 / Esc")
                color: AppTheme.textTertiary
                font.pixelSize: 12
                font.family: C.numFont
                font.letterSpacing: 1
            }
        }
    }
}
