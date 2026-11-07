pragma Singleton
import QtQuick
import "../components/Constants.js" as C

// 全局主题状态：solid（纯色，默认）/ light（浅色）/ glass（液态玻璃）
// v0.12：fontScale / fontFamily / fs() 供全局字号与字体缩放使用。
QtObject {
    id: t

    property string mode: "solid"

    // ---------- 字体 ----------
    property real fontScale: 1.0
    property string fontFamily: C.numFont
    property string navMode: "expanded"

    function fs(basePixelSize) {
        var value = Number(basePixelSize)
        if (!isFinite(value)) value = 0
        return Math.round(value * t.fontScale)
    }

    readonly property bool solid: mode === "solid"
    readonly property bool light: mode === "light"
    readonly property bool glass: mode === "glass"

    // ---------- 背景 ----------
    readonly property color bgTop: light ? "#F1F6F8" : "#04121C"
    readonly property color bgMid: light ? "#E4EEF1" : "#061B26"
    readonly property color bgBottom: light ? "#D5E5E9" : "#0A2A36"

    // ---------- 文本 ----------
    readonly property color textPrimary: light ? "#0C2831" : "#EFF9FF"
    readonly property color textSecondary: light ? "#3D626E" : "#A9C6D2"
    readonly property color textTertiary: light ? "#5F7E89" : "#6E8C99"
    readonly property color textOnLight: "#06222B"

    // ---------- 强调色 ----------
    readonly property color accent: light ? "#0E9E95" : "#2ED3C6"
    readonly property color accentSoft: light ? "#1E7FA8" : "#2B86FF"
    readonly property color accentDeep: light ? "#2C8FA8" : "#1F6FD0"
    readonly property color danger: "#E2555F"
    readonly property color success: light ? "#15855F" : "#6FE3B0"

    // ---------- 卡片 / 玻璃 ----------
    readonly property color cardBg: light ? "#FFFFFF" : "#0E2A38"
    readonly property color cardBgAlt: light ? "#F4F9FA" : "#123243"
    readonly property color cardBorder: light ? "#260E2831" : "#2BFFFFFF"
    readonly property color cardBorderStrong: light ? "#400E2831" : "#47FFFFFF"
    readonly property color glassTint: light ? "#FFFFFF" : "#071A24"
    readonly property color divider: light ? "#140E2831" : "#14FFFFFF"

    // ---------- 平面按钮 ----------
    readonly property color buttonBg: light ? "#FFFFFF" : "#14405A"
    readonly property color buttonBgAlt: light ? "#EAF3F5" : "#0F2E3E"
    readonly property color buttonBorder: light ? "#2E0E2831" : "#3DFFFFFF"
    readonly property color chipBg: light ? "#E6F0F3" : "#12303E"

    // ---------- 遮罩 ----------
    readonly property color overlayTop: light ? "#E8F2F4" : "#04121C"
    readonly property color overlayBottom: light ? "#CFE3E7" : "#0B3340"
}
