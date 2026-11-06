import QtQuick
import QtQuick.Window
import "../theme"
import "../components/Constants.js" as C

// v0.8 进入专注倒计时：单 Canvas 绘制 1200 个透明水光点汇聚成发光光圈。
// 参数在启动时一次性预计算到 Float32Array，30fps 绘制，不做每帧对象分配。
Window {
    id: overlay
    objectName: "EnterCountdown"
    title: qsTr("深清 · 即将进入")
    property bool animationsEnabled: true

    readonly property bool shouldShow: (typeof App !== "undefined" && App.prepareActive === true)
    readonly property int totalSeconds: 10
    readonly property int remaining: (typeof App !== "undefined" && App.prepareRemaining !== undefined)
                                      ? Math.max(0, Number(App.prepareRemaining)) : 10
    property real progress01: 0
    readonly property int particleCount: 1200
    readonly property int dropCount: overlay.particleCount
    readonly property real ringFill: {
        var x = Math.max(0, Math.min(1, (overlay.progress01 - 0.08) / 0.84))
        return x * x * (3 - 2 * x)
    }
    readonly property int condensedCount: Math.round(overlay.ringFill * overlay.particleCount)
    readonly property string prepareLevel: (typeof App !== "undefined" && App.prepareLevel !== undefined) ? String(App.prepareLevel) : ""
    readonly property string prepareSpaceName: (typeof App !== "undefined" && App.prepareSpaceName !== undefined) ? String(App.prepareSpaceName) : ""
    readonly property real circleSize: Math.max(220, Math.min(width, height) * 0.42)
    readonly property real ringDrawRadius: overlay.circleSize / 2 + 8
    readonly property real expandScale: Math.max(1.2, Math.max(width, height) / overlay.circleSize * 1.15)
    readonly property real scatterDistance: Math.max(width, height) * 0.62

    property string displaySpaceName: ""
    property string displayLevel: ""
    property bool hasShown: false
    property bool closing: false
    property bool expanding: false
    property bool finishing: false
    property bool canceling: false
    property int lastRemaining: 10
    property real scatter01: 0
    property bool progressSmoothing: true
    Behavior on progress01 {
        enabled: overlay.animationsEnabled && overlay.progressSmoothing
        NumberAnimation { duration: overlay.animationsEnabled ? 1000 : 0; easing.type: Easing.Linear }
    }

    property var pSpawn: null
    property var pStartR: null
    property var pStartA: null
    property var pTargetA: null
    property var pTravel: null
    property var pSize: null
    property var pPhase: null
    property var pWobAmp: null
    property var pWobSpeed: null
    property var pScatDx: null
    property var pScatDy: null
    property var pScatDist: null
    property var pBright: null

    visibility: (overlay.shouldShow || overlay.closing || overlay.expanding || overlay.canceling) ? Window.FullScreen : Window.Hidden
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"

    function rand01(seed) {
        var x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453
        return x - Math.floor(x)
    }

    function buildParticles() {
        var n = overlay.particleCount
        var spawn = new Float32Array(n), startR = new Float32Array(n), startA = new Float32Array(n)
        var targetA = new Float32Array(n), travel = new Float32Array(n), size = new Float32Array(n)
        var phase = new Float32Array(n), wobAmp = new Float32Array(n), wobSpeed = new Float32Array(n)
        var sdx = new Float32Array(n), sdy = new Float32Array(n), sdist = new Float32Array(n), bright = new Float32Array(n)
        var minDim = Math.min(overlay.width, overlay.height)
        for (var i = 0; i < n; i++) {
            var r1 = overlay.rand01(i * 1.37 + 0.11), r2 = overlay.rand01(i * 2.11 + 0.53)
            var r3 = overlay.rand01(i * 3.73 + 0.29), r4 = overlay.rand01(i * 5.19 + 0.71)
            var r5 = overlay.rand01(i * 7.07 + 0.37), r6 = overlay.rand01(i * 9.13 + 0.97)
            var u = (i + 0.5) / n
            spawn[i] = 0.02 + 0.80 * Math.pow(u, 0.66) + r1 * 0.03
            startR[i] = (0.10 + r2 * 0.75) * minDim
            startA[i] = r3 * Math.PI * 2
            targetA[i] = u * Math.PI * 2 + (r4 - 0.5) * 0.35
            travel[i] = 0.10 + r5 * 0.16
            size[i] = 0.8 + r6 * 2.6
            phase[i] = r4 * Math.PI * 2
            wobAmp[i] = 1.2 + r5 * 2.8
            wobSpeed[i] = 0.6 + r1 * 1.4
            var sa = r3 * Math.PI * 2
            sdx[i] = Math.cos(sa); sdy[i] = Math.sin(sa)
            sdist[i] = overlay.scatterDistance * (0.25 + r6 * 0.95)
            bright[i] = 0.35 + r2 * 0.65
        }
        overlay.pSpawn = spawn; overlay.pStartR = startR; overlay.pStartA = startA
        overlay.pTargetA = targetA; overlay.pTravel = travel; overlay.pSize = size
        overlay.pPhase = phase; overlay.pWobAmp = wobAmp; overlay.pWobSpeed = wobSpeed
        overlay.pScatDx = sdx; overlay.pScatDy = sdy; overlay.pScatDist = sdist; overlay.pBright = bright
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
        return overlay.modeLabel(overlay.shouldShow ? overlay.prepareLevel : overlay.displayLevel)
    }
    function progressAt(secondsLeft) {
        var left = Math.max(0, Math.min(overlay.totalSeconds, Number(secondsLeft)))
        return (overlay.totalSeconds - left) / overlay.totalSeconds
    }

    function startEnter() {
        overlay.closing = false; overlay.expanding = false; overlay.finishing = false
        overlay.canceling = false; overlay.hasShown = true; overlay.scatter01 = 0
        overlay.syncDisplay(); overlay.lastRemaining = overlay.remaining
        overlay.progressSmoothing = false
        overlay.progress01 = overlay.progressAt(overlay.remaining)
        overlay.progressSmoothing = true
        sceneRoot.opacity = overlay.animationsEnabled ? 0 : 1
        waterLayer.scale = 1
        enterAnim.stop(); fadeAnim.stop(); expandAnim.stop(); scatterAnim.stop()
        if (overlay.animationsEnabled) enterAnim.restart()
        overlay.show(); overlay.raise(); overlay.requestActivate()
    }
    function cancel() {
        if (!overlay.hasShown || overlay.canceling || overlay.closing || overlay.expanding) return
        overlay.canceling = true
        if (typeof App !== "undefined" && typeof App.cancelPrepare === "function") App.cancelPrepare()
        if (!overlay.animationsEnabled) { overlay.scatter01 = 1; overlay.finishCancelHide(); return }
        overlay.scatter01 = 0
        scatterAnim.restart()
    }
    function finishCancelHide() {
        overlay.canceling = false; overlay.closing = false; overlay.expanding = false
        overlay.finishing = false; overlay.hasShown = false
        sceneRoot.opacity = 0
    }
    function startFadeOut() {
        if (!overlay.hasShown) return
        overlay.closing = true
        enterAnim.stop(); expandAnim.stop()
        if (!overlay.animationsEnabled) {
            sceneRoot.opacity = 0; overlay.closing = false; overlay.hasShown = false; return
        }
        fadeAnim.restart()
    }
    function startExpand() {
        if (overlay.expanding) return
        overlay.expanding = true; overlay.closing = false
        enterAnim.stop(); fadeAnim.stop(); scatterAnim.stop()
        overlay.scatter01 = 0
        overlay.progressSmoothing = false; overlay.progress01 = 1; overlay.progressSmoothing = true
        if (!overlay.animationsEnabled) {
            waterLayer.scale = overlay.expandScale; sceneRoot.opacity = 0
            overlay.expanding = false; overlay.hasShown = false; return
        }
        sceneRoot.opacity = 1; waterLayer.scale = 1
        expandAnim.restart()
    }

    onShouldShowChanged: {
        if (overlay.shouldShow) overlay.startEnter()
        else if (overlay.canceling) { /* scatter path */ }
        else if (overlay.hasShown && !overlay.expanding) {
            if (overlay.finishing) overlay.startExpand()
            else overlay.startFadeOut()
        }
    }
    onPrepareSpaceNameChanged: overlay.syncDisplay()
    onPrepareLevelChanged: overlay.syncDisplay()
    onRemainingChanged: {
        if (!overlay.shouldShow) return
        overlay.lastRemaining = overlay.remaining
        if (!overlay.finishing) {
            var target = overlay.progressAt(overlay.remaining)
            if (overlay.remaining === 1) target = 0.97
            overlay.progress01 = target
        }
        if (overlay.remaining <= 0) { overlay.finishing = true; overlay.startExpand() }
    }
    Component.onCompleted: {
        overlay.buildParticles()
        if (overlay.shouldShow) overlay.startEnter()
    }
    Shortcut { sequence: "Escape"; onActivated: overlay.cancel() }

    Timer {
        interval: 33
        repeat: true
        running: overlay.shouldShow || overlay.canceling || overlay.expanding
        onTriggered: field.requestPaint()
    }
    onWidthChanged: overlay.buildParticles()
    onHeightChanged: overlay.buildParticles()

    NumberAnimation {
        id: scatterAnim
        target: overlay; property: "scatter01"; from: 0; to: 1
        duration: overlay.animationsEnabled ? 350 : 0
        easing.type: Easing.OutCubic
        onFinished: overlay.finishCancelHide()
    }
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: sceneRoot; property: "opacity"; from: 0; to: 1; duration: overlay.animationsEnabled ? 200 : 0; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: fadeAnim
        NumberAnimation { target: sceneRoot; property: "opacity"; to: 0; duration: overlay.animationsEnabled ? 200 : 0; easing.type: Easing.OutCubic }
        onFinished: { overlay.closing = false; overlay.hasShown = false }
    }
    ParallelAnimation {
        id: expandAnim
        NumberAnimation { target: waterLayer; property: "scale"; to: overlay.expandScale; duration: overlay.animationsEnabled ? 350 : 0; easing.type: Easing.OutCubic }
        NumberAnimation { target: sceneRoot; property: "opacity"; to: 0; duration: overlay.animationsEnabled ? 350 : 0; easing.type: Easing.InCubic }
        onFinished: { overlay.expanding = false; overlay.finishing = false; overlay.hasShown = false }
    }

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
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: overlay.cancel() }

        Item {
            id: waterLayer
            objectName: "EnterWater"
            anchors.fill: parent
            scale: 1
            transformOrigin: Item.Center

            Canvas {
                id: field
                anchors.fill: parent
                renderTarget: Canvas.FramebufferObject
                antialiasing: true
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var w = width, h = height, cx = w / 2, cy = h / 2
                    var radius = overlay.ringDrawRadius
                    var progress = overlay.progress01
                    var scatter = overlay.scatter01
                    var twoPi = Math.PI * 2
                    var n = overlay.particleCount
                    var spawn = overlay.pSpawn
                    if (spawn !== null && spawn.length === n) {
                        var startR = overlay.pStartR, startA = overlay.pStartA, targetA = overlay.pTargetA
                        var travelArr = overlay.pTravel, sizeArr = overlay.pSize, phaseArr = overlay.pPhase
                        var wobAmpArr = overlay.pWobAmp, wobSpeedArr = overlay.pWobSpeed
                        var sdx = overlay.pScatDx, sdy = overlay.pScatDy, sdist = overlay.pScatDist
                        var brightArr = overlay.pBright
                        var burst = scatter > 0 ? Math.min(1, scatter / 0.14) * (1 - scatter) : 0
                        ctx.globalCompositeOperation = "lighter"
                        for (var i = 0; i < n; i++) {
                            var t = progress - spawn[i]
                            if (t < 0) continue
                            var appear = Math.min(1, t / 0.08)
                            var travel = Math.min(1, Math.max(0, (t - 0.03) / travelArr[i]))
                            var e = travel * travel * (3 - 2 * travel)
                            var ang = startA[i] + (targetA[i] - startA[i]) * e
                                  + Math.sin(progress * twoPi * wobSpeedArr[i] + phaseArr[i]) * wobAmpArr[i] * (1 - e) * Math.PI / 180
                            var r = startR[i] + (radius - startR[i]) * e
                            var x = cx + Math.cos(ang) * r
                            var y = cy + Math.sin(ang) * r
                            if (scatter > 0) {
                                x += sdx[i] * sdist[i] * scatter
                                y += sdy[i] * sdist[i] * scatter
                            }
                            var alpha = appear * (0.28 + 0.72 * e) * brightArr[i]
                            alpha = alpha * (1 - scatter) + burst * 0.85
                            if (alpha <= 0.01) continue
                            var sz = sizeArr[i] * (0.6 + 0.8 * e)
                            ctx.globalAlpha = Math.min(1, alpha * 0.35)
                            ctx.beginPath(); ctx.arc(x, y, sz * 2.6, 0, twoPi)
                            ctx.fillStyle = "#2ED3C6"; ctx.fill()
                            ctx.globalAlpha = Math.min(1, alpha)
                            ctx.beginPath(); ctx.arc(x, y, sz, 0, twoPi)
                            ctx.fillStyle = e > 0.7 ? "#DFFBFF" : "#7FE7DA"; ctx.fill()
                        }
                        ctx.globalCompositeOperation = "source-over"
                        ctx.globalAlpha = 1
                    }
                    var track = AppTheme.glass ? "#2BFFFFFF" : "#2AFFFFFF"
                    ctx.beginPath(); ctx.arc(cx, cy, radius, 0, twoPi)
                    ctx.strokeStyle = track; ctx.lineWidth = 3; ctx.stroke()
                    var fill = overlay.ringFill
                    if (fill > 0.001 && scatter < 0.98) {
                        var startA2 = -Math.PI / 2
                        var endA2 = startA2 + twoPi * fill
                        var lw = 2.5 + 9 * fill
                        ctx.globalAlpha = (0.55 + 0.45 * fill) * (1 - scatter)
                        ctx.beginPath(); ctx.arc(cx, cy, radius, startA2, endA2)
                        ctx.strokeStyle = AppTheme.accent; ctx.lineWidth = lw; ctx.lineCap = "round"; ctx.stroke()
                        if (progress > 0.90) {
                            var glowT = Math.max(0, Math.min(1, (progress - 0.90) / 0.10))
                            ctx.globalAlpha = glowT * 0.55 * (1 - scatter)
                            ctx.beginPath(); ctx.arc(cx, cy, radius, startA2, endA2)
                            ctx.strokeStyle = AppTheme.accentSoft; ctx.lineWidth = lw + 14; ctx.stroke()
                        }
                        ctx.globalAlpha = 1
                    }
                }
            }
        }

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
                    color: cancelArea.containsMouse ? (AppTheme.glass ? "#26FFFFFF" : AppTheme.cardBgAlt) : "transparent"
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
