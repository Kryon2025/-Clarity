import QtQuick
import QtQuick.Window
import "../theme"
import "../components/Constants.js" as C

// v0.8 进入专注倒计时：1000+ 发光水光点从四周出现，向屏幕中心自然流动汇聚（轻微螺旋/切向）。
// 结束瞬间中心发出一道光波向外扩散，然后切到专注遮罩。
// 单 Canvas 绘制，参数预计算到 Float32Array，30fps；取消时所有光点向外散开淡出。
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
    readonly property int condensedCount: Math.round(overlay.progress01 * overlay.particleCount)
    readonly property string prepareLevel: (typeof App !== "undefined" && App.prepareLevel !== undefined) ? String(App.prepareLevel) : ""
    readonly property string prepareSpaceName: (typeof App !== "undefined" && App.prepareSpaceName !== undefined) ? String(App.prepareSpaceName) : ""
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
    property real wave01: 0
    property bool progressSmoothing: true
    Behavior on progress01 {
        enabled: overlay.animationsEnabled && overlay.progressSmoothing
        NumberAnimation { duration: overlay.animationsEnabled ? 1000 : 0; easing.type: Easing.Linear }
    }

    // 预计算粒子参数
    property var pSpawn: null
    property var pStartR: null
    property var pStartA: null
    property var pSwirl: null
    property var pEndR: null
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
        var swirl = new Float32Array(n), endR = new Float32Array(n), size = new Float32Array(n)
        var phase = new Float32Array(n), wobAmp = new Float32Array(n), wobSpeed = new Float32Array(n)
        var sdx = new Float32Array(n), sdy = new Float32Array(n), sdist = new Float32Array(n), bright = new Float32Array(n)
        var maxDim = Math.max(overlay.width, overlay.height)
        for (var i = 0; i < n; i++) {
            var r1 = overlay.rand01(i * 1.37 + 0.11), r2 = overlay.rand01(i * 2.11 + 0.53)
            var r3 = overlay.rand01(i * 3.73 + 0.29), r4 = overlay.rand01(i * 5.19 + 0.71)
            var r5 = overlay.rand01(i * 7.07 + 0.37), r6 = overlay.rand01(i * 9.13 + 0.97)
            spawn[i] = 0.02 + r1 * 0.78                            // 0.2s ~ 8s 随机出现
            startR[i] = (0.12 + r2 * 0.55) * maxDim                // 屏幕随机位置
            startA[i] = r3 * Math.PI * 2
            swirl[i] = (r4 - 0.5) * 3.2                            // 轻微螺旋方向/量
            endR[i] = 1 + r5 * 26                                  // 中心附近落点（越晚越密）
            size[i] = 0.9 + r6 * 2.8
            phase[i] = r4 * Math.PI * 2
            wobAmp[i] = 1.0 + r5 * 2.4
            wobSpeed[i] = 0.7 + r1 * 1.6
            var sa = r3 * Math.PI * 2 + (r6 - 0.5) * 1.6
            sdx[i] = Math.cos(sa); sdy[i] = Math.sin(sa)
            sdist[i] = overlay.scatterDistance * (0.25 + r6 * 0.95)
            bright[i] = 0.38 + r2 * 0.62
        }
        overlay.pSpawn = spawn; overlay.pStartR = startR; overlay.pStartA = startA
        overlay.pSwirl = swirl; overlay.pEndR = endR; overlay.pSize = size
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
        overlay.canceling = false; overlay.hasShown = true; overlay.scatter01 = 0; overlay.wave01 = 0
        overlay.syncDisplay(); overlay.lastRemaining = overlay.remaining
        overlay.progressSmoothing = false
        overlay.progress01 = overlay.progressAt(overlay.remaining)
        overlay.progressSmoothing = true
        sceneRoot.opacity = overlay.animationsEnabled ? 0 : 1
        enterAnim.stop(); fadeAnim.stop(); scatterAnim.stop(); waveAnim.stop()
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
        enterAnim.stop(); waveAnim.stop()
        if (!overlay.animationsEnabled) {
            sceneRoot.opacity = 0; overlay.closing = false; overlay.hasShown = false; return
        }
        fadeAnim.restart()
    }
    // 结束瞬间：中心光波扩散
    function startExpand() {
        if (overlay.expanding) return
        overlay.expanding = true; overlay.closing = false
        enterAnim.stop(); fadeAnim.stop(); scatterAnim.stop()
        overlay.scatter01 = 0
        overlay.progressSmoothing = false; overlay.progress01 = 1; overlay.progressSmoothing = true
        overlay.wave01 = 0
        if (!overlay.animationsEnabled) {
            sceneRoot.opacity = 0
            overlay.expanding = false; overlay.hasShown = false; return
        }
        sceneRoot.opacity = 1
        waveAnim.restart()
    }

    onShouldShowChanged: {
        if (overlay.shouldShow) overlay.startEnter()
        else if (overlay.canceling) { /* cancel path */ }
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
    NumberAnimation {
        id: waveAnim
        target: overlay; property: "wave01"; from: 0; to: 1
        duration: overlay.animationsEnabled ? 500 : 0
        easing.type: Easing.OutCubic
        onFinished: {
            overlay.expanding = false
            overlay.finishing = false
            overlay.hasShown = false
            sceneRoot.opacity = 0
        }
    }
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: sceneRoot; property: "opacity"; from: 0; to: 1; duration: overlay.animationsEnabled ? 220 : 0; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: fadeAnim
        NumberAnimation { target: sceneRoot; property: "opacity"; to: 0; duration: overlay.animationsEnabled ? 200 : 0; easing.type: Easing.OutCubic }
        onFinished: { overlay.closing = false; overlay.hasShown = false }
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

        Canvas {
            id: field
            anchors.fill: parent
            renderTarget: Canvas.FramebufferObject
            antialiasing: true
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height, cx = w / 2, cy = h / 2
                var progress = overlay.progress01
                var scatter = overlay.scatter01
                var wave = overlay.wave01
                var twoPi = Math.PI * 2
                var maxDim = Math.max(w, h)
                var n = overlay.particleCount
                var spawn = overlay.pSpawn

                // 中心光晕：随进度增强变大
                var glow = Math.max(0, Math.min(1, progress * progress * 1.08)) * (1 - wave * 0.9)
                if (glow > 0.001) {
                    ctx.globalCompositeOperation = "lighter"
                    var baseR = Math.max(8, Math.min(w, h) * 0.03 + Math.min(w, h) * 0.15 * glow)
                    for (var g = 0; g < 5; g++) {
                        var gr = baseR * (0.35 + g * 0.22)
                        ctx.globalAlpha = (0.03 + 0.035 * g) * glow
                        ctx.beginPath(); ctx.arc(cx, cy, gr, 0, twoPi)
                        ctx.fillStyle = "#2ED3C6"; ctx.fill()
                    }
                    ctx.globalAlpha = 1
                    ctx.globalCompositeOperation = "source-over"
                }

                // 水光点：自然出现 → 螺旋向中心流动 → 中心累积
                if (spawn !== null && spawn.length === n) {
                    var startR = overlay.pStartR, startA = overlay.pStartA, swirl = overlay.pSwirl
                    var endR = overlay.pEndR, sizeArr = overlay.pSize, phaseArr = overlay.pPhase
                    var wobAmpArr = overlay.pWobAmp, wobSpeedArr = overlay.pWobSpeed
                    var sdx = overlay.pScatDx, sdy = overlay.pScatDy, sdist = overlay.pScatDist
                    var brightArr = overlay.pBright
                    var burst = scatter > 0 ? Math.min(1, scatter / 0.14) * (1 - scatter) : 0
                    ctx.globalCompositeOperation = "lighter"
                    for (var i = 0; i < n; i++) {
                        var t = progress - spawn[i]
                        if (t < 0) continue
                        var appear = Math.min(1, t / 0.10)
                        var life = Math.min(1, t / Math.max(0.15, 0.92 - spawn[i]))
                        var flow = life * life * (3 - 2 * life)
                        var angle = startA[i] + swirl[i] * flow
                              + Math.sin(progress * twoPi * wobSpeedArr[i] + phaseArr[i])
                                * wobAmpArr[i] * (1 - flow * 0.6) * Math.PI / 180
                        var radius = endR[i] + (startR[i] - endR[i]) * (1 - flow)
                        var x = cx + Math.cos(angle) * radius
                        var y = cy + Math.sin(angle) * radius
                        if (scatter > 0) {
                            x += sdx[i] * sdist[i] * scatter
                            y += sdy[i] * sdist[i] * scatter
                        }
                        var brightness = 0.35 + 0.65 * flow
                        var alpha = appear * brightness * brightArr[i]
                        alpha = alpha * (1 - scatter) + burst * 0.85
                        if (alpha <= 0.01) continue
                        var sz = sizeArr[i] * (0.75 + 0.55 * flow) * (0.4 + 0.6 * appear)
                        ctx.globalAlpha = Math.min(1, alpha * (0.30 + 0.25 * glow))
                        ctx.beginPath(); ctx.arc(x, y, sz * 2.8, 0, twoPi)
                        ctx.fillStyle = "#2ED3C6"; ctx.fill()
                        ctx.globalAlpha = Math.min(1, alpha)
                        ctx.beginPath(); ctx.arc(x, y, sz, 0, twoPi)
                        ctx.fillStyle = flow > 0.6 ? "#E8FCFF" : "#7FE7DA"; ctx.fill()
                    }
                    ctx.globalCompositeOperation = "source-over"
                    ctx.globalAlpha = 1
                }

                // 结束光波：从中心向外扩散的亮环
                if (wave > 0.0001) {
                    var maxR = maxDim * 0.72
                    var waveR = maxR * wave
                    var fade = 1 - wave
                    ctx.globalCompositeOperation = "lighter"
                    ctx.globalAlpha = Math.min(1, 1.15 * fade)
                    ctx.beginPath(); ctx.arc(cx, cy, waveR, 0, twoPi)
                    ctx.strokeStyle = "#FFFFFF"; ctx.lineWidth = 3 + 16 * fade; ctx.stroke()
                    ctx.globalAlpha = 0.5 * fade
                    ctx.beginPath(); ctx.arc(cx, cy, waveR * 0.9, 0, twoPi)
                    ctx.strokeStyle = "#7FE7DA"; ctx.lineWidth = 2 + 10 * fade; ctx.stroke()
                    ctx.globalAlpha = 0.28 * fade
                    ctx.beginPath(); ctx.arc(cx, cy, waveR * 1.06, 0, twoPi)
                    ctx.strokeStyle = "#2ED3C6"; ctx.lineWidth = 2 + 6 * fade; ctx.stroke()
                    ctx.globalAlpha = Math.min(1, (1 - wave) * 1.4)
                    ctx.beginPath(); ctx.arc(cx, cy, Math.max(2, 18 * fade + 4), 0, twoPi)
                    ctx.fillStyle = "#FFFFFF"; ctx.fill()
                    ctx.globalAlpha = 1
                    ctx.globalCompositeOperation = "source-over"
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 10
            opacity: 1 - overlay.wave01 * 0.92
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: String(overlay.shouldShow ? overlay.remaining : overlay.lastRemaining)
                color: AppTheme.textPrimary
                font.family: C.monoFont
                font.pixelSize: Math.max(96, Math.min(overlay.width * 0.13, overlay.height * 0.22))
                font.weight: Font.Light
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("即将进入 · %1").arg(overlay.displaySpaceLabel())
                color: AppTheme.textSecondary
                font.pixelSize: Math.max(14, Math.round(overlay.height * 0.02))
                font.family: C.numFont
                font.letterSpacing: 1
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(34, Math.round(overlay.height * 0.06))
            spacing: 12
            opacity: 1 - overlay.wave01 * 0.92
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
