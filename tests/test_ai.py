"""v0.9 AI：服务商预设 / 请求重试 / 错误回退 / 设置语义搜索 / Key 不落日志。"""

from __future__ import annotations

import io
import json
import logging
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication  # noqa: E402

_APP = QApplication.instance() or QApplication([])

from shenqing.services import ai as ai_module  # noqa: E402
from shenqing.services.ai import AIService, PROVIDERS, local_search  # noqa: E402
from shenqing.settings import Settings  # noqa: E402


class _Response:
    def __init__(self, payload: dict) -> None:
        self._body = json.dumps(payload, ensure_ascii=False).encode("utf-8")

    def read(self) -> bytes:
        return self._body

    def __enter__(self):  # noqa: ANN001
        return self

    def __exit__(self, *args) -> bool:  # noqa: ANN002
        return False


def _chat_payload(text: str = "你好") -> dict:
    return {"choices": [{"message": {"content": text}}]}


SETTINGS_ITEMS = [
    {"key": "theme_mode", "title": "主题", "hint": "纯色 / 浅色 / 液态玻璃"},
    {"key": "autostart", "title": "开机自启", "hint": "登录时启动"},
    {"key": "ai_enabled", "title": "AI 助手", "hint": "问答与设置搜索"},
    {"key": "sleepRemindersEnabled", "title": "睡眠提醒", "hint": "提前提醒"},
]


class AIServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.path = Path(self._tmp.name) / "settings.json"
        self.settings = Settings(self.path)
        self.settings.set("ai_enabled", True)
        self.settings.set("ai_provider", "groq")
        self.settings.set("ai_api_key", "SECRET_KEY_123456")
        self.settings.set("ai_api_base", PROVIDERS["groq"]["base"])
        self.settings.set("ai_model", PROVIDERS["groq"]["default_model"])
        self.service = AIService(self.settings)

    def tearDown(self) -> None:
        self.service.shutdown()
        self._tmp.cleanup()

    def test_provider_presets(self) -> None:
        self.assertEqual(self.service.provider(), "groq")
        self.assertEqual(self.service.api_base(), "https://api.groq.com/openai/v1")
        self.assertEqual(self.service.model(), "llama-3.3-70b-versatile")
        self.assertTrue(self.service.set_provider("glm"))
        self.assertEqual(self.service.api_base(), "https://open.bigmodel.cn/api/paas/v4")
        self.assertEqual(self.service.model(), "glm-4.7-flash")
        self.assertFalse(self.service.set_provider("nope"))
        providers = {item["value"]: item for item in ai_module.provider_list()}
        self.assertEqual(set(providers), {"groq", "glm", "siliconflow", "custom"})
        self.assertIn("Qwen/Qwen2.5-7B-Instruct", providers["siliconflow"]["models"])
        self.assertEqual(providers["glm"]["id"], "glm")

    def test_chat_success(self) -> None:
        with mock.patch.object(
            ai_module.urllib.request, "urlopen", return_value=_Response(_chat_payload("正常"))
        ) as urlopen:
            result = self.service.ask("你好")
        self.assertTrue(result["ok"])
        self.assertEqual(result["text"], "正常")
        request = urlopen.call_args[0][0]
        self.assertTrue(request.full_url.endswith("/chat/completions"))
        self.assertIn("Bearer SECRET_KEY_123456", request.headers.get("Authorization"))

    def test_retry_once_then_success(self) -> None:
        with mock.patch.object(
            ai_module.urllib.request,
            "urlopen",
            side_effect=[URLError("boom"), _Response(_chat_payload("ok"))],
        ) as urlopen:
            result = self.service.ask("你好")
        self.assertTrue(result["ok"])
        self.assertEqual(urlopen.call_count, 2)

    def test_network_failure_returns_error(self) -> None:
        with mock.patch.object(
            ai_module.urllib.request, "urlopen", side_effect=URLError("boom")
        ) as urlopen:
            result = self.service.ask("你好")
        self.assertFalse(result["ok"])
        self.assertIn("网络错误", result["error"])
        self.assertEqual(urlopen.call_count, 2)  # 超时/网络失败重试一次

    def test_not_configured(self) -> None:
        self.settings.set("ai_enabled", False)
        result = self.service.ask("你好")
        self.assertFalse(result["ok"])
        self.assertIn("未启用", result["error"])

    def test_key_not_logged(self) -> None:
        logger = logging.getLogger("shenqing.ai")
        records: list[str] = []

        class _Handler(logging.Handler):
            def emit(self, record: logging.LogRecord) -> None:
                records.append(record.getMessage())

        handler = _Handler()
        logger.addHandler(handler)
        old_level = logger.level
        logger.setLevel(logging.DEBUG)
        try:
            with mock.patch.object(
                ai_module.urllib.request,
                "urlopen",
                side_effect=HTTPError(
                    "https://x",
                    401,
                    "Unauthorized",
                    None,
                    io.BytesIO(b'{"error":"bad key SECRET_KEY_123456"}'),
                ),
            ):
                result = self.service.ask("你好")
            self.assertFalse(result["ok"])
            self.assertNotIn("SECRET_KEY_123456", result["error"])
            self.assertTrue(any("***" in record or "AUTH" in record for record in records) or records)
            for record in records:
                self.assertNotIn("SECRET_KEY_123456", record)
        finally:
            logger.removeHandler(handler)
            logger.setLevel(old_level)

    def test_search_settings_uses_ai(self) -> None:
        with mock.patch.object(
            self.service,
            "chat",
            return_value={"ok": True, "text": '[{"key":"theme_mode","title":"主题"}]', "error": ""},
        ):
            results = self.service.search_settings("换主题", SETTINGS_ITEMS)
        self.assertEqual(results, [{"key": "theme_mode", "title": "主题"}])

    def test_search_settings_fallback(self) -> None:
        with mock.patch.object(
            self.service, "chat", return_value={"ok": False, "text": "", "error": "x"}
        ):
            results = self.service.search_settings("睡眠提醒", SETTINGS_ITEMS)
        self.assertEqual(results[0]["key"], "sleepRemindersEnabled")
        self.assertEqual(local_search("主题", SETTINGS_ITEMS)[0]["key"], "theme_mode")

    def test_bad_json_falls_back(self) -> None:
        with mock.patch.object(
            self.service, "chat", return_value={"ok": True, "text": "not json", "error": ""}
        ):
            results = self.service.search_settings("AI 助手", SETTINGS_ITEMS)
        self.assertEqual(results[0]["key"], "ai_enabled")


class AIBridgeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        os.environ["SHENQING_DATA_DIR"] = self._tmp.name
        os.environ["SHENQING_NO_SCAN"] = "1"
        from shenqing.bridge.app_bridge import AppBridge

        self.bridge = AppBridge()
        self.bridge.setAIKey("SECRET_KEY_123456")
        self.bridge.setAIBase(PROVIDERS["groq"]["base"])
        self.bridge.setAIModel(PROVIDERS["groq"]["default_model"])
        self.bridge.setAIProvider("groq")
        self.bridge.setAIEnabled(True)

    def tearDown(self) -> None:
        self.bridge._shutdown_services()
        try:
            self.bridge.deleteLater()
        except RuntimeError:
            pass
        self._tmp.cleanup()
        os.environ.pop("SHENQING_DATA_DIR", None)

    def test_ai_properties(self) -> None:
        self.assertTrue(self.bridge.aiConfigured)
        self.assertTrue(self.bridge.aiHasKey)
        self.assertEqual(self.bridge.aiProvider, "groq")
        providers = self.bridge.aiProviders
        self.assertEqual(providers[0]["id"], "groq")
        self.assertNotIn("SECRET_KEY_123456", json.dumps(providers))

    def test_ask_flow(self) -> None:
        def fake_submit(prompt, callback):  # noqa: ANN001
            callback({"ok": True, "text": "答案", "error": ""})

        with mock.patch.object(self.bridge._ai, "submit_ask", side_effect=fake_submit):
            self.bridge.askAI("问题")
        self.assertEqual(self.bridge.aiState, "ok")
        self.assertEqual(self.bridge.aiAnswer, "答案")
        self.assertEqual(self.bridge.aiError, "")
        self.bridge.aiCancel()
        self.assertEqual(self.bridge.aiState, "idle")

    def test_ask_error_and_test_connection(self) -> None:
        def fake_submit(prompt, callback):  # noqa: ANN001
            callback({"ok": False, "text": "", "error": "boom SECRET_KEY_123456"})

        with mock.patch.object(self.bridge._ai, "submit_ask", side_effect=fake_submit):
            self.bridge.testAIConnection()
        self.assertEqual(self.bridge.aiState, "error")
        self.assertNotIn("SECRET_KEY_123456", self.bridge.aiError)

    def test_search_fallback_when_disabled(self) -> None:
        self.bridge.setAIEnabled(False)
        results = self.bridge.aiSearchSettings("主题")
        self.assertTrue(results)
        self.assertEqual(results[0]["key"], "theme_mode")


if __name__ == "__main__":
    unittest.main()
