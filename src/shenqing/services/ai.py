"""AI 集成骨架（v0.8）：只做配置与占位，不发起真实请求。

设置项：ai_enabled / ai_api_base / ai_api_key / ai_model。
等用户给出 API 与具体需求后，在 complete() 里接真实请求（保持该接口不变）。
"""

from __future__ import annotations

import logging

logger = logging.getLogger("shenqing.ai")

DEFAULTS = {
    "ai_enabled": False,
    "ai_api_base": "",
    "ai_api_key": "",
    "ai_model": "",
}


class AIService:
    def __init__(self, settings) -> None:  # noqa: ANN001
        self._settings = settings

    def enabled(self) -> bool:
        return bool(self._settings.get("ai_enabled", False))

    def api_base(self) -> str:
        return str(self._settings.get("ai_api_base", "") or "")

    def api_key(self) -> str:
        return str(self._settings.get("ai_api_key", "") or "")

    def model(self) -> str:
        return str(self._settings.get("ai_model", "") or "")

    def configured(self) -> bool:
        return bool(self.enabled() and self.api_base() and self.api_key() and self.model())

    def complete(self, prompt: str, *, context: str = "") -> dict:
        """占位实现：接入真实 API 前统一返回 not_configured。"""
        return {
            "ok": False,
            "error": "" if self.configured() else "AI 未配置",
            "text": "",
            "prompt": str(prompt or ""),
            "context": str(context or ""),
        }
