import QtQuick
import QtQuick.Window
import "../theme"
import "../components/Constants.js" as C

// v0.9 进入专注倒计时：持续流动的流场粒子（1200 粒子上限，单 Canvas，30fps）。
// - 伪 curl noise + 向心引力 + 切向漩涡，粒子永远在动；
// - 靠近中心后快速淡出并重生到外围，生命周期循环；
// - 远/中/近三层（小暗慢 → 大亮快），独立 twinkle 与尺寸脉动，带极淡拖尾；
// - 结束时光波从中心扩散，粒子被推开并加速淡出；取消时向外炸散。
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
    readonly property int particleCount: 1000
    // Canvas 降分辨率倍率（1=原生；0.42 在软件渲染下仍保持 30fps，粒子本身是柔光）
    readonly property real fieldDownscale: 0.42
    readonly property int dropCount: overlay.particleCount
    readonly property int condensedCount: overlay.particleCount
    readonly property string prepareLevel: (typeof App !== "undefined" && App.prepareLevel !== undefined) ? String(App.prepareLevel) : ""
    readonly property string prepareSpaceName: (typeof App !== "undefined" && App.prepareSpaceName !== undefined) ? String(App.prepareSpaceName) : ""

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
    property int frameCount: 0
    property real timeSeconds: 0
    property bool progressSmoothing: true
    Behavior on progress01 {
        enabled: overlay.animationsEnabled && overlay.progressSmoothing
        NumberAnimation { duration: overlay.animationsEnabled ? 1000 : 0; easing.type: Easing.Linear }
    }

    // 粒子状态（Float32Array，一次性分配，每帧只改数值不建对象）
    property var pX: null
    property var pY: null
    property var pVX: null
    property var pVY: null
    property var pAge: null
    property var pLife: null
    property var pSize: null
    property var pLayer: null
    property var pPhase: null
    property var pTwinkle: null
    property var pBright: null
    property var pKillR: null
    property var pSwirlDir: null
    property var pPrev1X: null
    property var pPrev1Y: null
    property var pPrev2X: null
    property var pPrev2Y: null
    property var pColorIdx: null

    readonly property var layerSize: [1.2, 2.4, 4.2]
    readonly property var layerSpeed: [0.58, 1.0, 1.5]
    readonly property var layerBright: [0.60, 0.85, 1.05]
    readonly property var particleColors: ["#2ED3C6", "#5AC8FA", "#7FB6FF", "#E8FCFF", "#C9A7FF"]

    visibility: (overlay.shouldShow || overlay.closing || overlay.expanding || overlay.canceling) ? Window.FullScreen : Window.Hidden
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"

    function rand01() { return Math.random() }

    function buildParticles() {
        var n = overlay.particleCount
        overlay.pX = new Float32Array(n)
        overlay.pY = new Float32Array(n)
        overlay.pVX = new Float32Array(n)
        overlay.pVY = new Float32Array(n)
        overlay.pAge = new Float32Array(n)
        overlay.pLife = new Float32Array(n)
        overlay.pSize = new Float32Array(n)
        overlay.pLayer = new Float32Array(n)
        overlay.pPhase = new Float32Array(n)
        overlay.pTwinkle = new Float32Array(n)
        overlay.pBright = new Float32Array(n)
        overlay.pKillR = new Float32Array(n)
        overlay.pSwirlDir = new Float32Array(n)
        overlay.pPrev1X = new Float32Array(n)
        overlay.pPrev1Y = new Float32Array(n)
        overlay.pPrev2X = new Float32Array(n)
        overlay.pPrev2Y = new Float32Array(n)
        overlay.pColorIdx = new Float32Array(n)
        for (var i = 0; i < n; i++) {
            var layer = (i % 10 < 5) ? 0 : (i % 10 < 8 ? 1 : 2)
            overlay.pLayer[i] = layer
            overlay.pSize[i] = overlay.layerSize[layer] * (0.60 + Math.random() * 1.35)
            overlay.pTwinkle[i] = 0.6 + Math.random() * 2.4
            overlay.pBright[i] = (0.35 + Math.random() * 0.60) * overlay.layerBright[layer]
            overlay.pColorIdx[i] = Math.random() < 0.10 ? 4
                                    : (layer === 2 ? (Math.random() < 0.52 ? 3 : 1)
                                                   : (Math.random() < 0.72 ? 0 : 2))
            overlay.pKillR[i] = 22 + layer * 16 + Math.random() * 22
            overlay.pSwirlDir[i] = Math.random() < 0.5 ? -1 : 1
            overlay.spawnParticle(i, true)
        }
    }

    function spawnParticle(i, initial) {
        var w = overlay.width, h = overlay.height
        var cx = w / 2, cy = h / 2
        var maxDim = Math.max(w, h)
        var angle = Math.random() * Math.PI * 2
        var halfDiag = Math.sqrt(w * w + h * h) / 2
        var radius = halfDiag * (0.30 + Math.random() * 0.68)
        var x = cx + Math.cos(angle) * radius
        var y = cy + Math.sin(angle) * radius
        var layer = overlay.pLayer[i] | 0
        var speed = (70 + Math.random() * 130) * overlay.layerSpeed[layer]
        overlay.pX[i] = x
        overlay.pY[i] = y
        overlay.pPrev1X[i] = x
        overlay.pPrev1Y[i] = y
        overlay.pPrev2X[i] = x
        overlay.pPrev2Y[i] = y
        overlay.pVX[i] = -Math.cos(angle) * speed + (Math.random() - 0.5) * 24
        overlay.pVY[i] = -Math.sin(angle) * speed + (Math.random() - 0.5) * 24
        overlay.pLife[i] = 3.4 + Math.random() * 4.0 + layer * 0.35
        overlay.pAge[i] = initial ? Math.random() * overlay.pLife[i] * 0.55 : 0
        overlay.pPhase[i] = Math.random() * Math.PI * 2
    }

    function respawn(i) { overlay.spawnParticle(i, false) }

    function updateParticles(dt) {
        var n = overlay.particleCount
        var X = overlay.pX, Y = overlay.pY, VX = overlay.pVX, VY = overlay.pVY
        if (X === null || X.length !== n) return
        overlay.timeSeconds += dt
        var t = overlay.timeSeconds
        var w = overlay.width, h = overlay.height
        var cx = w / 2, cy = h / 2
        var progress = overlay.progress01
        var wave = overlay.wave01
        var scatter = overlay.scatter01
        var gravityBase = 90 + 260 * progress
        var swirlBase = 80 + 140 * progress
        var AGE = overlay.pAge, LIFE = overlay.pLife, SIZE = overlay.pSize
        var LAYER = overlay.pLayer, PHASE = overlay.pPhase, TW = overlay.pTwinkle
        var BRIGHT = overlay.pBright, KILL = overlay.pKillR, DIR = overlay.pSwirlDir
        var P1X = overlay.pPrev1X, P1Y = overlay.pPrev1Y, P2X = overlay.pPrev2X, P2Y = overlay.pPrev2Y

        for (var i = 0; i < n; i++) {
            var x = X[i], y = Y[i]
            var dx = cx - x, dy = cy - y
            var r = Math.sqrt(dx * dx + dy * dy) + 0.001
            var nx = dx / r, ny = dy / r
            var layer = LAYER[i] | 0
            var speedLayer = layer === 0 ? 0.62 : (layer === 1 ? 1.0 : 1.42)
            var falloff = 1 + 420 / (r + 90)
            var gravity = gravityBase * speedLayer * falloff
            var phase = PHASE[i]
            var swirl = swirlBase * DIR[i] * speedLayer * (0.45 + 0.55 * Math.min(2.2, falloff * 0.5))
            var ax = nx * gravity - ny * swirl
            var ay = ny * gravity + nx * swirl
            // 伪 curl noise：中层/近层才采样（远层小暗，省算力）
            if (layer !== 0) {
                var f1 = Math.sin(y * 0.012 + t * 0.82 + phase) * Math.cos(x * 0.009 - t * 0.55 + phase * 0.7)
                var f2 = Math.cos(x * 0.014 - t * 0.71 + phase * 1.3) * Math.sin(y * 0.011 + t * 0.96 + phase)
                ax += f2 * 30
                ay += f1 * 30
            }
            if (wave > 0.0001) {
                var push = wave * 1150 * speedLayer
                ax -= nx * push
                ay -= ny * push
            }
            if (scatter > 0.0001) {
                ax -= nx * scatter * 1500
                ay -= ny * scatter * 1500
            }
            var vx = VX[i] + ax * dt
            var vy = VY[i] + ay * dt
            vx *= 0.997
            vy *= 0.997
            var sp2 = vx * vx + vy * vy
            var maxSp = 520 + progress * 260
            if (sp2 > maxSp * maxSp) {
                var scale = maxSp / Math.sqrt(sp2)
                vx *= scale
                vy *= scale
            }
            var prevX = x
            var prevY = y
            P2X[i] = P1X[i]
            P2Y[i] = P1Y[i]
            P1X[i] = prevX
            P1Y[i] = prevY
            x += vx * dt
            y += vy * dt
            X[i] = x
            Y[i] = y
            VX[i] = vx
            VY[i] = vy

            var age = AGE[i] + dt
            AGE[i] = age
            var expired = age >= LIFE[i] || r < KILL[i]
            if (expired || x < -140 || x > w + 140 || y < -140 || y > h + 140)
                overlay.respawn(i)
        }
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
        overlay.buildParticles()
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
        else if (overlay.canceling) { }
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
        onTriggered: {
            overlay.updateParticles(0.033)
            overlay.frameCount++
            field.requestPaint()
        }
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
        duration: overlay.animationsEnabled ? 520 : 0
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
            // 半分辨率渲染再放大：单 Canvas 1200 粒子在软件渲染下也能稳定 30fps
            width: Math.max(1, Math.round(overlay.width * overlay.fieldDownscale))
            height: Math.max(1, Math.round(overlay.height * overlay.fieldDownscale))
            anchors.left: parent.left
            anchors.top: parent.top
            scale: 1 / overlay.fieldDownscale
            transformOrigin: Item.TopLeft
            renderTarget: Canvas.FramebufferObject
            antialiasing: true
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.scale(overlay.fieldDownscale, overlay.fieldDownscale)
                var w = overlay.width, h = overlay.height, cx = w / 2, cy = h / 2
                var progress = overlay.progress01
                var scatter = overlay.scatter01
                var wave = overlay.wave01
                var t = overlay.timeSeconds
                var twoPi = Math.PI * 2
                var maxDim = Math.max(w, h)
                var n = overlay.particleCount
                var X = overlay.pX
                if (X !== null && X.length === n) {
                    var Y = overlay.pY, AGE = overlay.pAge, LIFE = overlay.pLife
                    var SIZE = overlay.pSize, LAYER = overlay.pLayer, PHASE = overlay.pPhase
                    var TW = overlay.pTwinkle, BRIGHT = overlay.pBright
                    var P1X = overlay.pPrev1X, P1Y = overlay.pPrev1Y, P2X = overlay.pPrev2X, P2Y = overlay.pPrev2Y
                    var colors = overlay.layerColor
                    ctx.globalCompositeOperation = "lighter"
                    var scatterAlpha = 1 - scatter
                    for (var i = 0; i < n; i++) {
                        var age = AGE[i]
                        var life = LIFE[i]
                        if (age <= 0 || age >= life) continue
                        var lifeT = age / life
                        var fadeIn = Math.min(1, age / 0.5)
                        var fadeOut = Math.min(1, (life - age) / 0.75)
                        var x = X[i], y = Y[i]
                        var dx = x - cx, dy = y - cy
                        var rr = Math.sqrt(dx * dx + dy * dy)
                        var centerBoost = Math.max(0, 1 - rr / (Math.min(w, h) * 0.32))
                        var twinkle = 0.66 + 0.34 * Math.sin(t * TW[i] + PHASE[i])
                        var alpha = fadeIn * fadeOut * twinkle * BRIGHT[i]
                        alpha *= (1 - wave * 0.9) * scatterAlpha
                        if (centerBoost > 0) alpha *= (0.70 + 0.42 * centerBoost)
                        alpha = Math.min(0.88, alpha)
                        if (alpha <= 0.012) continue
                        var layer = LAYER[i] | 0
                        var sz = SIZE[i] * (1 + 0.18 * Math.sin(t * TW[i] * 1.7 + PHASE[i] * 2.0))
                        sz *= (1 + 0.28 * centerBoost)
                        sz = Math.max(1, Math.min(7, sz))
                        var color = overlay.particleColors[overlay.pColorIdx[i] | 0]
                        // 水光拖尾：上一/两帧位置 → 当前位置，速度越快光带越长
                        var sx = P2X[i], sy = P2Y[i]
                        var streakLen = layer >= 1
                                         ? Math.sqrt((x - sx) * (x - sx) + (y - sy) * (y - sy)) : 0
                        if (layer >= 1 && streakLen > 0.6) {
                            ctx.globalAlpha = Math.min(0.55, alpha * (layer === 0 ? 0.30 : 0.46))
                            ctx.beginPath()
                            ctx.moveTo(sx, sy)
                            ctx.lineTo(x, y)
                            ctx.strokeStyle = color
                            ctx.lineWidth = Math.max(0.7, sz * (layer === 0 ? 0.30 : 0.46))
                            ctx.stroke()
                        }
                        if (layer === 0) {
                            // 远层只留极短光带 + 1px 头，成本最低
                            ctx.globalAlpha = Math.min(1, alpha * 0.42)
                            ctx.fillStyle = color
                            ctx.fillRect(x - 0.5, y - 0.5, 1.2, 1.2)
                        } else if (layer === 1) {
                            // 中层：光带 + 小方点头
                            ctx.globalAlpha = Math.min(1, alpha * 0.80)
                            ctx.fillStyle = color
                            ctx.fillRect(x - sz * 0.4, y - sz * 0.4,
                                         Math.max(1.2, sz * 0.8), Math.max(1.2, sz * 0.8))
                        } else {
                            // 近层：光晕 + 内核 + 白心
                            ctx.globalAlpha = Math.min(1, alpha * 0.20)
                            ctx.beginPath(); ctx.arc(x, y, sz * 2.6, 0, twoPi)
                            ctx.fillStyle = color; ctx.fill()
                            ctx.globalAlpha = Math.min(1, alpha * 0.92)
                            ctx.beginPath(); ctx.arc(x, y, sz, 0, twoPi)
                            ctx.fillStyle = color; ctx.fill()
                            if (sz > 2.4) {
                                ctx.globalAlpha = Math.min(0.75, alpha * 0.55)
                                ctx.beginPath(); ctx.arc(x, y, sz * 0.45, 0, twoPi)
                                ctx.fillStyle = "#FFFFFF"; ctx.fill()
                            }
                        }
                    }
                    ctx.globalCompositeOperation = "source-over"
                    ctx.globalAlpha = 1
                }

                // 中心光晕（随进度增强；结束时让位给光波）
                var glow = Math.max(0, Math.min(1, progress * progress * 1.1)) * (1 - wave * 0.92)
                if (glow > 0.001) {
                    ctx.globalCompositeOperation = "lighter"
                    var baseR = Math.max(10, Math.min(w, h) * 0.04 + Math.min(w, h) * 0.17 * glow)
                    for (var g = 0; g < 3; g++) {
                        ctx.globalAlpha = (0.04 + 0.045 * g) * glow
                        ctx.beginPath(); ctx.arc(cx, cy, baseR * (0.5 + g * 0.3), 0, twoPi)
                        ctx.fillStyle = g < 2 ? "#2ED3C6" : "#7FE7DA"; ctx.fill()
                    }
                    ctx.globalAlpha = 1
                    ctx.globalCompositeOperation = "source-over"
                }

                // 中央文字可读性保护：淡淡的深色径向遮罩，压住中心粒子叠加亮度
                var scrimR = Math.max(190, Math.min(w, h) * 0.21)
                var scrim = ctx.createRadialGradient(cx, cy, 0, cx, cy, scrimR)
                scrim.addColorStop(0.0, "rgba(2, 8, 14, 0.56)")
                scrim.addColorStop(0.48, "rgba(2, 8, 14, 0.30)")
                scrim.addColorStop(1.0, "rgba(2, 8, 14, 0)")
                ctx.globalCompositeOperation = "source-over"
                ctx.globalAlpha = 1
                ctx.fillStyle = scrim
                ctx.beginPath(); ctx.arc(cx, cy, scrimR, 0, twoPi); ctx.fill()

                // 结束光波
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
                    ctx.globalAlpha = 0.26 * fade
                    ctx.beginPath(); ctx.arc(cx, cy, waveR * 1.06, 0, twoPi)
                    ctx.strokeStyle = "#2ED3C6"; ctx.lineWidth = 2 + 6 * fade; ctx.stroke()
                    ctx.globalAlpha = Math.min(1, fade * 1.4)
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
                font.pixelSize: Math.max(AppTheme.fs(96), Math.min(overlay.width * 0.13, overlay.height * 0.22))
                font.weight: Font.Light
                style: Text.Outline
                styleColor: "#88020A10"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("即将进入 · %1").arg(overlay.displaySpaceLabel())
                color: AppTheme.textSecondary
                font.pixelSize: Math.max(AppTheme.fs(14), Math.round(overlay.height * 0.02))
                font.family: AppTheme.fontFamily
                font.letterSpacing: 1
                style: Text.Outline
                styleColor: "#88020A10"
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
                    color: cancelArea.containsMouse ? "#8A1B3340" : "#66040A10"
                    border.width: 1
                    border.color: AppTheme.glass ? "#55FFFFFF" : AppTheme.cardBorderStrong
                }
                Text {
                    id: cancelLabel
                    anchors.centerIn: parent
                    text: qsTr("取消")
                    color: AppTheme.textSecondary
                    font.pixelSize: AppTheme.fs(13)
                    font.family: AppTheme.fontFamily
                }
                MouseArea {
                    id: cancelArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: overlay.cancel()
                }
            }
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: hintLabel.implicitWidth + 22
                height: 24
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: "#5A040A10"
                }
                Text {
                    id: hintLabel
                    anchors.centerIn: parent
                    text: qsTr("点击任意位置取消 / Esc")
                    color: AppTheme.textSecondary
                    font.pixelSize: AppTheme.fs(12)
                    font.family: AppTheme.fontFamily
                    font.letterSpacing: 1
                }
            }
        }
    }
}
