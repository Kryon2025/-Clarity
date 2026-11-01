import QtQuick
import "Constants.js" as C

// 纯 Canvas 矢量图标：不依赖 RinUI 图标字体（该字体在本机运行时未必加载成功）
Canvas {
    id: glyph
    property string kind: "gear"
    property color color: C.textPrimary
    property real size: 20
    property real strokeWidth: Math.max(1.4, size * 0.085)

    width: size
    height: size
    antialiasing: true

    onKindChanged: requestPaint()
    onColorChanged: requestPaint()
    onSizeChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function rrect(ctx, x, y, w, h, r) {
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.lineTo(x + w - r, y)
        ctx.arcTo(x + w, y, x + w, y + r, r)
        ctx.lineTo(x + w, y + h - r)
        ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
        ctx.lineTo(x + r, y + h)
        ctx.arcTo(x, y + h, x, y + h - r, r)
        ctx.lineTo(x, y + r)
        ctx.arcTo(x, y, x + r, y, r)
        ctx.closePath()
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var s = width / 24
        ctx.scale(s, s)
        ctx.strokeStyle = glyph.color
        ctx.fillStyle = glyph.color
        ctx.lineWidth = Math.max(1.1, glyph.strokeWidth / s)
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        if (kind === "gear") {
            ctx.beginPath()
            ctx.arc(12, 12, 6.2, 0, Math.PI * 2)
            ctx.stroke()
            ctx.beginPath()
            for (var i = 0; i < 8; i++) {
                var a = i * Math.PI / 4
                ctx.moveTo(12 + Math.cos(a) * 6.4, 12 + Math.sin(a) * 6.4)
                ctx.lineTo(12 + Math.cos(a) * 9.2, 12 + Math.sin(a) * 9.2)
            }
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(12, 12, 2.1, 0, Math.PI * 2)
            ctx.stroke()
        } else if (kind === "back") {
            ctx.beginPath()
            ctx.moveTo(19.5, 12)
            ctx.lineTo(6.5, 12)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(12.5, 5.5)
            ctx.lineTo(6, 12)
            ctx.lineTo(12.5, 18.5)
            ctx.stroke()
        } else if (kind === "chevron") {
            ctx.beginPath()
            ctx.moveTo(9.5, 5.5)
            ctx.lineTo(16, 12)
            ctx.lineTo(9.5, 18.5)
            ctx.stroke()
        } else if (kind === "chevronLeft") {
            ctx.beginPath()
            ctx.moveTo(14.5, 5.5)
            ctx.lineTo(8, 12)
            ctx.lineTo(14.5, 18.5)
            ctx.stroke()
        } else if (kind === "chevronDown") {
            ctx.beginPath()
            ctx.moveTo(5.5, 9.5)
            ctx.lineTo(12, 16)
            ctx.lineTo(18.5, 9.5)
            ctx.stroke()
        } else if (kind === "plus") {
            ctx.beginPath()
            ctx.moveTo(12, 5.5)
            ctx.lineTo(12, 18.5)
            ctx.moveTo(5.5, 12)
            ctx.lineTo(18.5, 12)
            ctx.stroke()
        } else if (kind === "minus") {
            ctx.beginPath()
            ctx.moveTo(5.5, 12)
            ctx.lineTo(18.5, 12)
            ctx.stroke()
        } else if (kind === "search") {
            ctx.beginPath()
            ctx.arc(10.5, 10.5, 5.8, 0, Math.PI * 2)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(14.9, 14.9)
            ctx.lineTo(19.6, 19.6)
            ctx.stroke()
        } else if (kind === "space") {
            glyph.rrect(ctx, 3.6, 5, 16.8, 14, 4.4)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(12, 12, 2.6, 0, Math.PI * 2)
            ctx.fill()
        } else if (kind === "stats") {
            glyph.rrect(ctx, 4, 13.5, 3.6, 6.5, 1.6)
            ctx.fill()
            glyph.rrect(ctx, 10.2, 8.5, 3.6, 11.5, 1.6)
            ctx.fill()
            glyph.rrect(ctx, 16.4, 4, 3.6, 16, 1.6)
            ctx.fill()
        } else if (kind === "settings") {
            kind = "gear"
        } else if (kind === "clock") {
            ctx.beginPath()
            ctx.arc(12, 12, 7.6, 0, Math.PI * 2)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(12, 7.4)
            ctx.lineTo(12, 12)
            ctx.lineTo(15.4, 14)
            ctx.stroke()
        } else if (kind === "check") {
            ctx.beginPath()
            ctx.moveTo(5, 12.6)
            ctx.lineTo(9.8, 17.2)
            ctx.lineTo(19, 7)
            ctx.stroke()
        } else if (kind === "close") {
            ctx.beginPath()
            ctx.moveTo(6.5, 6.5)
            ctx.lineTo(17.5, 17.5)
            ctx.moveTo(17.5, 6.5)
            ctx.lineTo(6.5, 17.5)
            ctx.stroke()
        } else if (kind === "play") {
            ctx.beginPath()
            ctx.moveTo(7.5, 4.8)
            ctx.lineTo(19, 12)
            ctx.lineTo(7.5, 19.2)
            ctx.closePath()
            ctx.fill()
        } else if (kind === "pause") {
            glyph.rrect(ctx, 6.5, 5, 4, 14, 1.8)
            ctx.fill()
            glyph.rrect(ctx, 13.5, 5, 4, 14, 1.8)
            ctx.fill()
        } else if (kind === "stop") {
            glyph.rrect(ctx, 6.5, 6.5, 11, 11, 3)
            ctx.fill()
        } else if (kind === "lock") {
            ctx.beginPath()
            ctx.moveTo(8, 11)
            ctx.lineTo(8, 8.6)
            ctx.arc(12, 8.6, 4, Math.PI, 0)
            ctx.lineTo(16, 11)
            ctx.stroke()
            glyph.rrect(ctx, 6, 11, 12, 9.4, 2.6)
            ctx.stroke()
        } else if (kind === "trash") {
            ctx.beginPath()
            ctx.moveTo(5, 7)
            ctx.lineTo(19, 7)
            ctx.moveTo(9.5, 7)
            ctx.lineTo(9.5, 4.8)
            ctx.lineTo(14.5, 4.8)
            ctx.lineTo(14.5, 7)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(6.8, 7)
            ctx.lineTo(7.9, 19.4)
            ctx.lineTo(16.1, 19.4)
            ctx.lineTo(17.2, 7)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(10.4, 10.4)
            ctx.lineTo(10.7, 16.4)
            ctx.moveTo(13.6, 10.4)
            ctx.lineTo(13.3, 16.4)
            ctx.stroke()
        } else if (kind === "refresh") {
            ctx.beginPath()
            ctx.arc(12, 12, 7.4, -Math.PI * 0.75, Math.PI * 0.42)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(18.4, 6.2)
            ctx.lineTo(19.1, 10.7)
            ctx.lineTo(14.7, 9.9)
            ctx.stroke()
        } else if (kind === "download") {
            ctx.beginPath()
            ctx.moveTo(12, 3.8)
            ctx.lineTo(12, 14.6)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(7.6, 10.6)
            ctx.lineTo(12, 15)
            ctx.lineTo(16.4, 10.6)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(5.4, 19.2)
            ctx.lineTo(18.6, 19.2)
            ctx.stroke()
        } else if (kind === "moon") {
            ctx.beginPath()
            ctx.arc(12, 12, 7.6, Math.PI * 0.35, Math.PI * 1.55)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(15.6, 8.4, 7.2, Math.PI * 0.2, Math.PI * 1.1)
            ctx.stroke()
        } else if (kind === "leaf") {
            ctx.beginPath()
            ctx.moveTo(5.6, 18.4)
            ctx.bezierCurveTo(6.4, 8, 14, 4.6, 18.6, 5.4)
            ctx.bezierCurveTo(18.8, 14, 13.4, 18.6, 5.6, 18.4)
            ctx.closePath()
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(7.4, 16.8)
            ctx.lineTo(14.6, 9.6)
            ctx.stroke()
        } else if (kind === "sparkle") {
            ctx.beginPath()
            ctx.moveTo(12, 3.6)
            ctx.lineTo(13.9, 10.1)
            ctx.lineTo(20.4, 12)
            ctx.lineTo(13.9, 13.9)
            ctx.lineTo(12, 20.4)
            ctx.lineTo(10.1, 13.9)
            ctx.lineTo(3.6, 12)
            ctx.lineTo(10.1, 10.1)
            ctx.closePath()
            ctx.fill()
        } else if (kind === "dot") {
            ctx.beginPath()
            ctx.arc(12, 12, 3.2, 0, Math.PI * 2)
            ctx.fill()
        } else if (kind === "ripple") {
            ctx.beginPath()
            ctx.arc(12, 13.5, 3.0, Math.PI * 0.15, Math.PI * 0.85, true)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(12, 13.5, 6.2, Math.PI * 0.15, Math.PI * 0.85, true)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(12, 13.5, 9.2, Math.PI * 0.15, Math.PI * 0.85, true)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(12, 13.5, 1.4, 0, Math.PI * 2)
            ctx.fill()
        } else if (kind === "wave") {
            ctx.beginPath()
            ctx.moveTo(3, 14.5)
            ctx.bezierCurveTo(6.2, 9.2, 8.8, 9.2, 12, 14.5)
            ctx.bezierCurveTo(15.2, 19.8, 17.8, 19.8, 21, 14.5)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(3, 9.6)
            ctx.bezierCurveTo(6.2, 4.3, 8.8, 4.3, 12, 9.6)
            ctx.bezierCurveTo(15.2, 14.9, 17.8, 14.9, 21, 9.6)
            ctx.stroke()
        } else if (kind === "waveBars") {
            glyph.rrect(ctx, 4.2, 14.5, 3.4, 5.0, 1.7)
            ctx.fill()
            glyph.rrect(ctx, 10.3, 10.4, 3.4, 9.1, 1.7)
            ctx.fill()
            glyph.rrect(ctx, 16.4, 6.4, 3.4, 13.1, 1.7)
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(4.2, 5.2)
            ctx.bezierCurveTo(7.0, 1.6, 9.8, 1.6, 12.6, 5.2)
            ctx.bezierCurveTo(15.4, 8.8, 18.2, 8.8, 21, 5.2)
            ctx.stroke()
        } else if (kind === "drop") {
            ctx.beginPath()
            ctx.moveTo(12, 3.2)
            ctx.bezierCurveTo(15.6, 7.4, 18.4, 10.8, 18.4, 14.0)
            ctx.arc(12.0, 14.0, 6.4, 0, Math.PI, false)
            ctx.bezierCurveTo(12.0, 12.0, 12.0, 12.0, 12.0, 3.2)
            ctx.closePath()
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(9.6, 13.6, 1.5, 0, Math.PI * 2)
            ctx.fill()
        } else if (kind === "shell") {
            ctx.beginPath()
            ctx.arc(12, 15.6, 8.2, Math.PI, Math.PI * 2, false)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(3.8, 15.6)
            ctx.lineTo(20.2, 15.6)
            ctx.stroke()
            for (var si = 1; si <= 4; si++) {
                var sa = Math.PI + si * Math.PI / 5
                ctx.beginPath()
                ctx.moveTo(12, 15.6)
                ctx.lineTo(12 + Math.cos(sa) * 8.2, 15.6 + Math.sin(sa) * 8.2)
                ctx.stroke()
            }
            ctx.beginPath()
            ctx.arc(12, 15.6, 1.6, 0, Math.PI * 2)
            ctx.fill()
        } else if (kind === "grid") {
            glyph.rrect(ctx, 3.8, 3.8, 7.2, 7.2, 2.2)
            ctx.stroke()
            glyph.rrect(ctx, 13, 3.8, 7.2, 7.2, 2.2)
            ctx.stroke()
            glyph.rrect(ctx, 3.8, 13, 7.2, 7.2, 2.2)
            ctx.stroke()
            glyph.rrect(ctx, 13, 13, 7.2, 7.2, 2.2)
            ctx.stroke()
        }
    }
}