"""生成应用图标：海洋风（深海渐变 + 水滴 + 涟漪）。

用法：python scripts/make_icon.py
输出：assets/icon.png（256）、assets/icon.ico（多尺寸）
"""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import (
    QBrush,
    QColor,
    QGuiApplication,
    QImage,
    QLinearGradient,
    QPainter,
    QPainterPath,
    QPen,
)


def _droplet(size: int) -> QPainterPath:
    """水滴：上方尖、下方圆。"""
    cx = size * 0.5
    top = size * 0.2
    r = size * 0.2
    cy = size * 0.6
    path = QPainterPath()
    path.moveTo(cx, top)
    path.cubicTo(cx + r * 0.85, top + r * 0.9, cx + r, cy - r * 0.55, cx + r, cy)
    path.arcTo(QRectF(cx - r, cy - r, r * 2, r * 2), 0, -180)
    path.cubicTo(cx - r, cy - r * 0.55, cx - r * 0.85, top + r * 0.9, cx, top)
    path.closeSubpath()
    return path


def render(size: int) -> QImage:
    image = QImage(size, size, QImage.Format.Format_ARGB32)
    image.fill(Qt.GlobalColor.transparent)
    painter = QPainter(image)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)

    rect = QRectF(size * 0.05, size * 0.05, size * 0.90, size * 0.90)
    gradient = QLinearGradient(rect.topLeft(), rect.bottomRight())
    gradient.setColorAt(0.0, QColor("#062A38"))
    gradient.setColorAt(0.55, QColor("#0C5566"))
    gradient.setColorAt(1.0, QColor("#22CDBE"))
    painter.setBrush(QBrush(gradient))
    painter.setPen(Qt.PenStyle.NoPen)
    painter.drawRoundedRect(rect, size * 0.24, size * 0.24)

    # 顶部水光
    sheen = QLinearGradient(rect.topLeft(), QPointF(rect.left(), rect.top() + size * 0.42))
    sheen.setColorAt(0.0, QColor(255, 255, 255, 46))
    sheen.setColorAt(1.0, QColor(255, 255, 255, 0))
    painter.setBrush(QBrush(sheen))
    painter.drawRoundedRect(rect, size * 0.24, size * 0.24)

    # 水滴（玻璃白）
    drop = _droplet(size)
    drop_grad = QLinearGradient(QPointF(0, size * 0.2), QPointF(0, size * 0.85))
    drop_grad.setColorAt(0.0, QColor(255, 255, 255, 246))
    drop_grad.setColorAt(1.0, QColor(206, 246, 255, 200))
    painter.setBrush(QBrush(drop_grad))
    painter.setPen(Qt.PenStyle.NoPen)
    painter.drawPath(drop)

    # 水滴内高光
    highlight = QPainterPath()
    highlight.addEllipse(QRectF(size * 0.40, size * 0.50, size * 0.10, size * 0.14))
    painter.setBrush(QBrush(QColor(255, 255, 255, 230)))
    painter.drawPath(highlight)

    # 涟漪
    pen = QPen(QColor(255, 255, 255, 150))
    pen.setWidthF(size * 0.018)
    painter.setPen(pen)
    painter.setBrush(Qt.BrushStyle.NoBrush)
    painter.drawArc(QRectF(size * 0.24, size * 0.70, size * 0.52, size * 0.20), 200 * 16, 140 * 16)
    pen.setColor(QColor(255, 255, 255, 80))
    pen.setWidthF(size * 0.012)
    painter.setPen(pen)
    painter.drawArc(QRectF(size * 0.15, size * 0.74, size * 0.70, size * 0.24), 205 * 16, 130 * 16)

    painter.end()
    return image


def main() -> int:
    app = QGuiApplication.instance() or QGuiApplication([])  # noqa: F841
    assets = Path(__file__).resolve().parents[1] / "assets"
    assets.mkdir(parents=True, exist_ok=True)

    png = render(256)
    png.save(str(assets / "icon.png"), "PNG")
    ico = render(256)
    ok = ico.save(str(assets / "icon.ico"), "ICO")
    print(f"icon.png: {assets / 'icon.png'}")
    print(f"icon.ico: {'ok' if ok else 'Qt 不支持写 ICO，已跳过'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
