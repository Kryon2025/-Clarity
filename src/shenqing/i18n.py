"""应用国际化：Qt .ts/.qm 翻译加载 + 语言解析。

- 译文目录：`src/shenqing/locales/<locale>.qm`（打包后位于 _MEIPASS/locales）
- 语言设置：settings.json 的 `language`，取值 `auto` / `zh_CN` / `en_US`
- QML 用 qsTr()，Python 用 QCoreApplication.translate("ShenQing", "...")，两者都能被
  pyside6-lupdate 提取到同一份 .ts

首个交付：中文（源语言）+ 英文（en_US）。
"""

from __future__ import annotations

import logging
from pathlib import Path

from PySide6.QtCore import QCoreApplication, QLocale, QObject, QTranslator, Signal

from .paths import resource_root

logger = logging.getLogger("shenqing.i18n")

#: 支持的语言（code 与 .ts/.qm 文件名一致）
LOCALES: list[dict] = [
    {"code": "zh_CN", "label": "简体中文", "english": "Simplified Chinese"},
    {"code": "en_US", "label": "English", "english": "English"},
]

DEFAULT_LOCALE = "zh_CN"
AUTO = "auto"


def locales_dir() -> Path:
    return resource_root() / "locales"


def supported_codes() -> list[str]:
    return [item["code"] for item in LOCALES]


def system_locale() -> str:
    """系统语言 → 我们支持的 code（目前中/英两种，其余回落到英文）。"""
    name = QLocale.system().name()
    if name.lower().startswith("zh"):
        return "zh_CN"
    return "en_US"


def resolve(language: str | None) -> str:
    """把设置值（auto/zh_CN/en_US）解析成实际 locale code。"""
    value = str(language or AUTO).strip()
    if value in ("", AUTO, "system"):
        return system_locale()
    if value in supported_codes():
        return value
    return DEFAULT_LOCALE


def tr(text: str, context: str = "ShenQing") -> str:
    """Python 侧翻译快捷方式（等价于 QCoreApplication.translate）。"""
    return QCoreApplication.translate(context, text)


class Translator(QObject):
    """安装 / 切换应用翻译器（含 RinUI 自带控件的语言包）。"""

    languageChanged = Signal(str)

    def __init__(self, app: QCoreApplication, language: str = AUTO) -> None:
        super().__init__()
        self._app = app
        self._translator = QTranslator()
        self._rinui_translator = None  # noqa: ANN001 - RinUITranslator
        self._language = AUTO
        self._locale = DEFAULT_LOCALE
        self.apply(language)

    @property
    def language(self) -> str:
        """设置里的原始值：auto / zh_CN / en_US。"""
        return self._language

    @property
    def locale(self) -> str:
        """实际生效的 locale code。"""
        return self._locale

    @property
    def available(self) -> bool:
        return (locales_dir() / f"{self._locale}.qm").exists()

    def apply(self, language: str | None) -> str:
        """切换语言；返回实际生效的 locale code。"""
        self._language = str(language or AUTO)
        locale = resolve(self._language)
        self._locale = locale

        if self._translator is not None:
            self._app.removeTranslator(self._translator)
        if self._rinui_translator is not None:
            self._app.removeTranslator(self._rinui_translator)
        self._translator = QTranslator()
        self._rinui_translator = None

        qm_path = locales_dir() / f"{locale}.qm"
        installed = False
        if qm_path.exists():
            installed = bool(self._translator.load(str(qm_path)))
        else:
            logger.info("未找到翻译文件 %s，使用源语言", qm_path)
        if installed:
            self._app.installTranslator(self._translator)

        # RinUI 自带控件（Text/ToolButton 等）的语言包
        try:
            from RinUI import RinUITranslator

            fallback = QLocale("en_US") if locale == "en_US" else QLocale("zh_CN")
            self._rinui_translator = RinUITranslator(fallback)
            self._app.installTranslator(self._rinui_translator)
        except Exception as exc:  # noqa: BLE001 - RinUI 可选
            logger.debug("RinUI 语言包加载失败：%s", exc)

        QLocale.setDefault(QLocale(locale))
        self.languageChanged.emit(locale)
        logger.info("翻译已切换：%s（文件：%s，加载：%s）", locale, qm_path, installed)
        return locale

    def set_language(self, language: str) -> str:
        return self.apply(language)
