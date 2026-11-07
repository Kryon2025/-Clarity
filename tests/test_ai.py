"""v0.9 AI：服务商预设 / 请求重试 / 错误回退 / 设置语义搜索 / Key 不落日志。"""

from __future__ import annotations

import io
import json
import logging
import os
import sys
import tempfile
import time
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
        self.assertEqual(
            set(providers),
            {
                "groq",
                "glm",
                "siliconflow",
                "custom",
                "deepseek",
                "mimo",
                "openai",
                "pollinations",
            },
        )
        self.assertIn("Qwen/Qwen2.5-7B-Instruct", providers["siliconflow"]["models"])
        self.assertEqual(providers["glm"]["id"], "glm")
        # v0.11 预设：deepseek 新模型 / 免 Key pollinations / 能力元数据
        self.assertEqual(providers["deepseek"]["base"], "https://api.deepseek.com/v1")
        self.assertEqual(providers["deepseek"]["models"], ["deepseek-flash", "deepseek-v4-pro"])
        self.assertEqual(providers["deepseek"]["models"][0], "deepseek-flash")
        self.assertTrue(providers["deepseek"]["supports_reasoning"])
        self.assertTrue(providers["deepseek"]["supports_web_search"])
        self.assertEqual(providers["deepseek"]["pricing"]["input"], 0.5)
        self.assertEqual(providers["deepseek"]["pricing"]["currency"], "CNY")
        self.assertFalse(providers["pollinations"]["needs_key"])
        self.assertEqual(
            providers["pollinations"]["base"], "https://text.pollinations.ai/openai"
        )
        self.assertEqual(providers["pollinations"]["models"], ["openai-fast"])
        self.assertEqual(providers["pollinations"]["pricing"]["input"], 0.0)
        self.assertTrue(providers["openai"]["supports_reasoning"])
        self.assertTrue(providers["glm"]["supports_web_search"])
        self.assertTrue(providers["custom"]["needs_key"])
        self.assertEqual(providers["mimo"]["base"], "https://api.xiaomimimo.com/v1")
        self.assertEqual(providers["mimo"]["models"][0], "mimo-v2.6-flash")
        self.assertIn("mimo-v2.6-pro", providers["mimo"]["models"])
        self.assertEqual(providers["openai"]["base"], "https://api.openai.com/v1")
        self.assertEqual(providers["openai"]["models"][0], "gpt-4o-mini")

    def test_provider_switch_defaults(self) -> None:
        for provider, base, model in (
            ("deepseek", "https://api.deepseek.com/v1", "deepseek-flash"),
            ("mimo", "https://api.xiaomimimo.com/v1", "mimo-v2.6-flash"),
            ("openai", "https://api.openai.com/v1", "gpt-4o-mini"),
            ("pollinations", "https://text.pollinations.ai/openai", "openai-fast"),
        ):
            self.assertTrue(self.service.set_provider(provider))
            self.assertEqual(self.service.api_base(), base)
            self.assertEqual(self.service.model(), model)

    def test_fetch_models_parses_and_dedupes(self) -> None:
        payload = {"data": [{"id": "model-a"}, {"id": "model-b"}, {"id": "model-a"}]}
        with mock.patch.object(
            ai_module.urllib.request, "urlopen", return_value=_Response(payload)
        ) as urlopen:
            models = ai_module.fetch_models("https://api.groq.com/openai/v1", "KEY")
        self.assertEqual(models, ["model-a", "model-b"])
        request = urlopen.call_args[0][0]
        self.assertTrue(request.full_url.endswith("/models"))
        self.assertEqual(request.get_method(), "GET")
        self.assertIn("Bearer KEY", request.headers.get("Authorization"))

    def test_fetch_models_failure_returns_empty(self) -> None:
        with mock.patch.object(
            ai_module.urllib.request, "urlopen", side_effect=URLError("boom")
        ):
            self.assertEqual(
                ai_module.fetch_models("https://api.groq.com/openai/v1", "KEY"), []
            )
        self.assertEqual(ai_module.fetch_models("", "KEY"), [])
        self.assertEqual(ai_module.fetch_models("https://x", ""), [])

    def test_fetch_models_mimo_api_key_fallback(self) -> None:
        payload = {"data": [{"id": "mimo-x"}]}
        calls: list[dict] = []

        def fake_urlopen(request, timeout=None):  # noqa: ANN001
            calls.append({k.lower(): v for k, v in dict(request.headers).items()})
            if len(calls) == 1:
                raise HTTPError(request.full_url, 401, "Unauthorized", None, io.BytesIO(b"{}"))
            return _Response(payload)

        with mock.patch.object(ai_module.urllib.request, "urlopen", side_effect=fake_urlopen):
            models = ai_module.fetch_models(
                "https://api.xiaomimimo.com/v1", "MIMO_KEY", "mimo"
            )
        self.assertEqual(models, ["mimo-x"])
        self.assertEqual(len(calls), 2)
        self.assertIn("authorization", calls[0])
        self.assertIn("bearer", calls[0]["authorization"].lower())
        self.assertEqual(calls[1].get("api-key"), "MIMO_KEY")

    def test_models_cache_expiry(self) -> None:
        cache = ai_module.cache_models({}, "groq", ["m1", "m2"], now=1000.0)
        self.assertEqual(ai_module.cached_models(cache, "groq", now=1000.0), ["m1", "m2"])
        self.assertEqual(
            ai_module.cached_models(cache, "groq", now=1000.0 + 23 * 3600), ["m1", "m2"]
        )
        self.assertEqual(ai_module.cached_models(cache, "groq", now=1000.0 + 25 * 3600), [])
        self.assertEqual(ai_module.cached_models({}, "groq"), [])

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
        # v0.11 追加的服务层用例复用 bridge 的 settings / AIService
        self.settings = self.bridge._settings
        self.service = self.bridge._ai

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
        self.assertEqual(providers[0]["value"], "pollinations")
        self.assertFalse(providers[0]["needs_key"])
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

    def test_ai_models_default_and_fetched(self) -> None:
        bridge = self.bridge
        self.assertEqual(bridge.aiModels, PROVIDERS["groq"]["models"])
        self.assertEqual(bridge.aiModelsState, "idle")
        bridge._on_ai_models_fetched("groq", ["m1", "m2"], "")
        self.assertEqual(bridge.aiModels, ["m1", "m2"])
        self.assertEqual(bridge.aiModelsState, "ok")
        self.assertEqual(bridge.aiModelsError, "")
        cache = bridge._settings.get("ai_models_cache", {})
        self.assertEqual(cache["groq"]["models"], ["m1", "m2"])
        bridge._on_ai_models_fetched("groq", [], "boom")
        self.assertEqual(bridge.aiModelsState, "error")
        self.assertTrue(bridge.aiModelsError)

    def test_ai_models_cache_used_and_expired(self) -> None:
        bridge = self.bridge
        bridge._ai_models = []
        bridge._settings.set(
            "ai_models_cache",
            {"groq": {"models": ["cached-1"], "fetchedAt": time.time()}},
        )
        self.assertEqual(bridge.aiModels, ["cached-1"])
        bridge._settings.set(
            "ai_models_cache",
            {"groq": {"models": ["stale"], "fetchedAt": time.time() - 25 * 3600}},
        )
        self.assertEqual(bridge.aiModels, PROVIDERS["groq"]["models"])

    def test_switch_provider_resets_and_auto_fetches(self) -> None:
        bridge = self.bridge
        bridge._on_ai_models_fetched("groq", ["old-model"], "")
        self.assertEqual(bridge.aiModels, ["old-model"])
        with mock.patch.object(bridge, "fetchAIModels") as fetch:
            bridge.setAIProvider("deepseek")
            _APP.processEvents()
        self.assertTrue(fetch.called)
        self.assertEqual(bridge.aiProvider, "deepseek")
        self.assertEqual(bridge.aiBase, "https://api.deepseek.com/v1")
        self.assertEqual(bridge.aiModel, "deepseek-flash")
        self.assertEqual(bridge.aiModels, PROVIDERS["deepseek"]["models"])
        self.assertEqual(bridge.aiModelsState, "idle")

    def test_fetch_models_without_key_sets_error(self) -> None:
        bridge = self.bridge
        bridge.setAIKey("")
        bridge._ai_models_state = "idle"
        bridge.fetchAIModels()
        self.assertEqual(bridge.aiModelsState, "error")
        self.assertIn("API Key", bridge.aiModelsError)

    def test_stale_provider_result_ignored(self) -> None:
        bridge = self.bridge
        with mock.patch.object(bridge, "fetchAIModels"):
            bridge.setAIProvider("openai")
        bridge._on_ai_models_fetched("groq", ["old"], "")
        self.assertEqual(bridge.aiModels, PROVIDERS["openai"]["models"])
        cache = bridge._settings.get("ai_models_cache", {})
        self.assertEqual(cache["groq"]["models"], ["old"])


    def test_pollinations_configured_without_key(self) -> None:
        self.settings.set("ai_enabled", False)
        self.settings.set("ai_provider", "pollinations")
        self.settings.set("ai_api_key", "")
        self.settings.set("ai_api_base", "")
        self.settings.set("ai_model", "")
        service = AIService(self.settings)
        try:
            self.assertFalse(service.needs_key())
            self.assertTrue(service.configured())
            captured: dict = {}

            def fake_urlopen(request, timeout=None):  # noqa: ANN001
                captured["headers"] = {k.lower(): v for k, v in dict(request.headers).items()}
                captured["payload"] = json.loads(request.data.decode("utf-8"))
                return _Response(_chat_payload("免费回答"))

            with mock.patch.object(ai_module.urllib.request, "urlopen", side_effect=fake_urlopen):
                result = service.ask("你好")
            self.assertTrue(result["ok"])
            self.assertEqual(result["text"], "免费回答")
            self.assertNotIn("authorization", captured["headers"])
        finally:
            service.shutdown()

    def test_deepseek_thinking_payload(self) -> None:
        self.settings.set("ai_provider", "deepseek")
        self.settings.set("ai_api_base", "https://api.deepseek.com/v1")
        self.settings.set("ai_model", "deepseek-flash")
        captured: dict = {}
        response = _Response(_chat_payload("答"))
        with mock.patch.object(
            ai_module.urllib.request, "urlopen", side_effect=lambda request, timeout=None: captured.update(payload=json.loads(request.data.decode("utf-8"))) or response
        ):
            result = self.service.ask("你好")
        self.assertTrue(result["ok"])
        self.assertEqual(captured["payload"]["thinking"]["type"], "enabled")

        self.settings.set("ai_reasoning_enabled", False)
        captured.clear()
        with mock.patch.object(
            ai_module.urllib.request, "urlopen", side_effect=lambda request, timeout=None: captured.update(payload=json.loads(request.data.decode("utf-8"))) or response
        ):
            self.service.ask("你好")
        self.assertEqual(captured["payload"]["thinking"]["type"], "disabled")

    def test_reasoning_content_and_usage_cost(self) -> None:
        self.settings.set("ai_provider", "deepseek")
        self.settings.set("ai_api_base", "https://api.deepseek.com/v1")
        self.settings.set("ai_model", "deepseek-flash")
        payload = {
            "choices": [
                {"message": {"content": "答案", "reasoning_content": "思考过程"}}
            ],
            "usage": {"prompt_tokens": 1000, "completion_tokens": 500, "total_tokens": 1500},
        }
        with mock.patch.object(ai_module.urllib.request, "urlopen", return_value=_Response(payload)):
            result = self.service.ask("你好")
        self.assertEqual(result["reasoning"], "思考过程")
        usage = result["usage"]
        self.assertEqual(usage["prompt_tokens"], 1000)
        self.assertEqual(usage["completion_tokens"], 500)
        self.assertEqual(usage["currency"], "CNY")
        self.assertAlmostEqual(usage["cost"], 0.0005 + 0.0015, places=6)

    def test_deepseek_web_search_injected(self) -> None:
        self.settings.set("ai_provider", "deepseek")
        self.settings.set("ai_api_base", "https://api.deepseek.com/v1")
        self.settings.set("ai_model", "deepseek-flash")
        self.settings.set("ai_web_search_enabled", True)
        captured: dict = {}
        response = _Response(_chat_payload("带联网答案"))
        with (
            mock.patch.object(
                self.service, "deepseek_web_context", return_value="- 结果：今天天气晴"
            ) as search,
            mock.patch.object(
                ai_module.urllib.request,
                "urlopen",
                side_effect=lambda request, timeout=None: captured.update(
                    payload=json.loads(request.data.decode("utf-8"))
                )
                or response,
            ),
        ):
            result = self.service.ask("今天天气")
        self.assertTrue(result["ok"])
        self.assertTrue(search.called)
        system_text = captured["payload"]["messages"][0]["content"]
        self.assertIn("今天天气晴", system_text)

    def test_glm_web_search_tool_payload(self) -> None:
        self.settings.set("ai_provider", "glm")
        self.settings.set("ai_api_base", "https://open.bigmodel.cn/api/paas/v4")
        self.settings.set("ai_model", "glm-4.7-flash")
        self.settings.set("ai_web_search_enabled", True)
        captured: dict = {}
        response = _Response(_chat_payload("ok"))
        with mock.patch.object(
            ai_module.urllib.request,
            "urlopen",
            side_effect=lambda request, timeout=None: captured.update(
                payload=json.loads(request.data.decode("utf-8"))
            )
            or response,
        ):
            self.service.ask("查询")
        tools = captured["payload"].get("tools") or []
        self.assertEqual(tools[0]["type"], "web_search")

    def test_estimate_cost(self) -> None:
        cost, currency = ai_module.estimate_cost("deepseek", "deepseek-v4-pro", 1_000_000, 1_000_000)
        self.assertEqual(currency, "CNY")
        self.assertAlmostEqual(cost, 10.0)
        cost, _currency = ai_module.estimate_cost("pollinations", "openai-fast", 10_000, 10_000)
        self.assertEqual(cost, 0.0)


class AIHistoryBridgeTest(unittest.TestCase):
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
        # v0.11 追加的服务层用例复用 bridge 的 settings / AIService
        self.settings = self.bridge._settings
        self.service = self.bridge._ai

    def tearDown(self) -> None:
        self.bridge._shutdown_services()
        try:
            self.bridge.deleteLater()
        except RuntimeError:
            pass
        self._tmp.cleanup()
        os.environ.pop("SHENQING_DATA_DIR", None)

    def _fake_submit(self, result: dict):  # noqa: ANN202
        def fake_submit(prompt, callback):  # noqa: ANN001
            callback(result)

        return fake_submit

    def test_history_flow_and_persistence(self) -> None:
        bridge = self.bridge
        result = {
            "ok": True,
            "text": "回答",
            "reasoning": "思考",
            "error": "",
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15, "cost": 0.0, "currency": "CNY"},
        }
        with mock.patch.object(bridge._ai, "submit_ask", side_effect=self._fake_submit(result)):
            bridge.askAI("这是第一个问题，标题应该取前二十四个字以内")
        messages = bridge.aiMessages
        self.assertEqual([item["role"] for item in messages], ["user", "assistant"])
        self.assertEqual(messages[-1]["content"], "回答")
        self.assertEqual(messages[-1]["reasoning"], "思考")
        self.assertEqual(messages[-1]["tokens"], 15)
        conversations = bridge.aiConversations
        self.assertEqual(len(conversations), 1)
        self.assertEqual(conversations[0]["count"], 2)
        self.assertTrue(conversations[0]["title"].startswith("这是第一个问题"))
        self.assertLessEqual(len(conversations[0]["title"]), 24)

        # 新会话 / 切换 / 删除
        bridge.newAIConversation()
        self.assertEqual(bridge.aiMessages, [])
        self.assertEqual(len(bridge.aiConversations), 2)
        first_id = conversations[0]["id"]
        self.assertTrue(bridge.selectAIConversation(first_id))
        self.assertEqual(len(bridge.aiMessages), 2)
        self.assertTrue(bridge.deleteAIConversation(first_id))
        self.assertEqual(len(bridge.aiConversations), 1)

        # 持久化：新 AppBridge 读取同一数据目录
        from shenqing.bridge.app_bridge import AppBridge as Bridge2

        other = Bridge2()
        try:
            self.assertGreaterEqual(len(other.aiConversations), 1)
        finally:
            other._shutdown_services()

    def test_usage_records_and_reset(self) -> None:
        bridge = self.bridge
        result = {
            "ok": True,
            "text": "答",
            "reasoning": "",
            "error": "",
            "usage": {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150, "cost": 0.123, "currency": "USD"},
        }
        with mock.patch.object(bridge._ai, "submit_ask", side_effect=self._fake_submit(result)):
            bridge.askAI("花费")
        self.assertEqual(bridge.aiTodayTokens, 150)
        self.assertAlmostEqual(bridge.aiTodayCost, 0.123, places=6)
        self.assertEqual(bridge.aiCurrency, "USD")
        last = bridge.aiLastUsage
        self.assertEqual(last["prompt_tokens"], 100)
        self.assertEqual(last["completion_tokens"], 50)
        self.assertEqual(last["model"], PROVIDERS["groq"]["default_model"])
        bridge.resetAIUsage()
        self.assertEqual(bridge.aiTodayTokens, 0)
        self.assertAlmostEqual(bridge.aiTodayCost, 0.0, places=6)
        self.assertEqual(bridge.aiLastUsage, {})

    def test_capability_flags_and_toggles(self) -> None:
        bridge = self.bridge
        self.assertTrue(bridge.aiNeedsKey)
        self.assertFalse(bridge.aiSupportsReasoning)  # groq
        self.assertFalse(bridge.aiSupportsWebSearch)
        self.assertTrue(bridge.aiReasoningEnabled)
        self.assertFalse(bridge.aiWebSearchEnabled)
        bridge.setAIWebSearchEnabled(True)
        self.assertTrue(bridge.aiWebSearchEnabled)
        with mock.patch.object(bridge, "fetchAIModels"):
            bridge.setAIProvider("deepseek")
        self.assertTrue(bridge.aiSupportsReasoning)
        self.assertTrue(bridge.aiSupportsWebSearch)
        with mock.patch.object(bridge, "fetchAIModels"):
            bridge.setAIProvider("pollinations")
        self.assertFalse(bridge.aiNeedsKey)
        self.assertTrue(bridge.aiSupportsReasoning)
        self.bridge.setAIEnabled(False)
        self.assertTrue(bridge.aiConfigured)  # 免 Key 服务商恒为可配置


if __name__ == "__main__":
    unittest.main()
