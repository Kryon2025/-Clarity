"""AI 集成（v0.11）：OpenAI 兼容 /chat/completions + 多服务商思考/联网/费用。

- 预设服务商：deepseek / pollinations(免 Key) / mimo / openai / groq / glm / siliconflow / custom；
- 元数据：needs_key / supports_reasoning / supports_web_search / pricing（¥ 或 $ / 百万 tokens，估算）；
- 思考：DeepSeek thinking{enabled/disabled} + reasoning_effort；OpenAI reasoning_effort；pollinations 模型自带推理；
- 联网：DeepSeek 先查 /tools/search 拼上下文；GLM 用 web_search 工具参数；
- 解析 usage（prompt/completion tokens）并按 provider+model 估算费用；
- 线程池异步，超时 20s，失败重试 1 次；API Key 只存本机 settings.json，日志/错误一律脱敏。
"""

from __future__ import annotations

import json
import logging
import re
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Callable

logger = logging.getLogger("shenqing.ai")

REQUEST_TIMEOUT = 20.0
SEARCH_TIMEOUT = 6.0
WEB_SEARCH_TIMEOUT = 15.0
MAX_TOKENS = 768
MODELS_CACHE_TTL = 24 * 60 * 60
MODELS_TIMEOUT = 15.0

PROVIDERS: dict[str, dict[str, Any]] = {
    "deepseek": {
        "value": "deepseek",
        "label": "DeepSeek",
        "base": "https://api.deepseek.com/v1",
        "models": ["deepseek-flash", "deepseek-v4-pro"],
        "default_model": "deepseek-flash",
        "needs_key": True,
        "supports_reasoning": True,
        "supports_web_search": True,
        "pricing": {"input": 0.5, "output": 3.0, "currency": "CNY"},
        "model_pricing": {
            "deepseek-flash": {"input": 0.5, "output": 3.0, "currency": "CNY"},
            "deepseek-v4-pro": {"input": 2.0, "output": 8.0, "currency": "CNY"},
        },
    },
    "pollinations": {
        "value": "pollinations",
        "label": "免费直连（免配置）",
        "base": "https://text.pollinations.ai/openai",
        "models": ["openai-fast"],
        "default_model": "openai-fast",
        "needs_key": False,
        "supports_reasoning": True,
        "supports_web_search": False,
        "pricing": {"input": 0.0, "output": 0.0, "currency": "USD"},
    },
    "glm": {
        "value": "glm",
        "label": "智谱 GLM",
        "base": "https://open.bigmodel.cn/api/paas/v4",
        "models": ["glm-4.7-flash", "glm-4-flash", "glm-4-plus"],
        "default_model": "glm-4.7-flash",
        "needs_key": True,
        "supports_reasoning": True,
        "supports_web_search": True,
        "pricing": {"input": 0.0, "output": 0.0, "currency": "CNY"},
    },
    "siliconflow": {
        "value": "siliconflow",
        "label": "SiliconFlow",
        "base": "https://api.siliconflow.cn/v1",
        "models": ["Qwen/Qwen2.5-7B-Instruct", "Qwen/Qwen2.5-14B-Instruct"],
        "default_model": "Qwen/Qwen2.5-7B-Instruct",
        "needs_key": True,
        "supports_reasoning": False,
        "supports_web_search": False,
        "pricing": {"input": 0.0, "output": 0.0, "currency": "CNY"},
    },
    "mimo": {
        "value": "mimo",
        "label": "小米 MiMo",
        "base": "https://api.xiaomimimo.com/v1",
        "models": ["mimo-v2.6-flash", "mimo-v2.6-pro"],
        "default_model": "mimo-v2.6-flash",
        "needs_key": True,
        "supports_reasoning": True,
        "supports_web_search": False,
        "pricing": {"input": 0.0, "output": 0.0, "currency": "CNY"},
        #: 除 Bearer 外还支持 api-key 头（Bearer 失败时回退一次）
        "api_key_header": True,
    },
    "openai": {
        "value": "openai",
        "label": "ChatGPT",
        "base": "https://api.openai.com/v1",
        "models": ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"],
        "default_model": "gpt-4o-mini",
        "needs_key": True,
        "supports_reasoning": True,
        "supports_web_search": False,
        "pricing": {"input": 0.15, "output": 0.6, "currency": "USD"},
    },
    "groq": {
        "value": "groq",
        "label": "Groq",
        "base": "https://api.groq.com/openai/v1",
        "models": ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"],
        "default_model": "llama-3.3-70b-versatile",
        "needs_key": True,
        "supports_reasoning": False,
        "supports_web_search": False,
        "pricing": {"input": 0.0, "output": 0.0, "currency": "USD"},
    },
    "custom": {
        "value": "custom",
        "label": "自定义",
        "base": "",
        "models": [],
        "default_model": "",
        "needs_key": True,
        # 由设置 ai_reasoning_enabled / ai_web_search_enabled 决定（bridge 动态标注）
        "supports_reasoning": True,
        "supports_web_search": True,
        "pricing": {"input": 0.0, "output": 0.0, "currency": "USD"},
    },
}
DEFAULT_PROVIDER = "pollinations"
PROVIDER_ORDER = [
    "pollinations",
    "deepseek",
    "glm",
    "mimo",
    "openai",
    "groq",
    "siliconflow",
    "custom",
]


def provider_list() -> list[dict]:
    ordered = [key for key in PROVIDER_ORDER if key in PROVIDERS]
    ordered += [key for key in PROVIDERS if key not in ordered]
    return [
        {
            "value": key,
            "id": key,
            "label": PROVIDERS[key]["label"],
            "base": PROVIDERS[key]["base"],
            "models": list(PROVIDERS[key]["models"]),
            "default_model": PROVIDERS[key]["default_model"],
            "needs_key": bool(PROVIDERS[key].get("needs_key", True)),
            "supports_reasoning": bool(PROVIDERS[key].get("supports_reasoning", False)),
            "supports_web_search": bool(PROVIDERS[key].get("supports_web_search", False)),
            "pricing": dict(PROVIDERS[key].get("pricing") or {}),
        }
        for key in ordered
    ]


def provider_needs_key(provider: str) -> bool:
    return bool(PROVIDERS.get(str(provider or ""), {}).get("needs_key", True))


def provider_pricing(provider: str, model: str = "") -> dict:
    preset = PROVIDERS.get(str(provider or ""), {})
    model_prices = preset.get("model_pricing") if isinstance(preset.get("model_pricing"), dict) else {}
    if model and model in model_prices:
        return dict(model_prices[model])
    return dict(preset.get("pricing") or {"input": 0.0, "output": 0.0, "currency": "CNY"})


def estimate_cost(provider: str, model: str, prompt_tokens: int, completion_tokens: int) -> tuple[float, str]:
    """按「每百万 tokens」估算费用；返回 (cost, currency)。"""
    pricing = provider_pricing(provider, model)
    try:
        input_price = float(pricing.get("input", 0) or 0)
        output_price = float(pricing.get("output", 0) or 0)
    except (TypeError, ValueError):
        input_price = output_price = 0.0
    cost = (
        max(0, int(prompt_tokens)) * input_price / 1_000_000.0
        + max(0, int(completion_tokens)) * output_price / 1_000_000.0
    )
    return round(cost, 8), str(pricing.get("currency") or "CNY")


def local_search(query: str, items: list[dict], limit: int = 3) -> list[dict]:
    """本地模糊匹配（AI 未启用/失败时兜底）。"""
    text = str(query or "").strip().lower()
    if not text:
        return []
    tokens = [token for token in re.split(r"\s+", text) if token]
    scored: list[tuple[int, dict]] = []
    for item in items or []:
        key = str(item.get("key") or "")
        title = str(item.get("title") or "")
        hint = str(item.get("hint") or "")
        haystack = f"{key} {title} {hint}".lower()
        score = 0
        if text in haystack:
            score += 10
        for token in tokens:
            if token in haystack:
                score += 3
        if key.lower() == text:
            score += 20
        if score:
            scored.append((score, {"key": key, "title": title}))
    scored.sort(key=lambda pair: pair[0], reverse=True)
    return [item for _score, item in scored[: max(1, int(limit))]]


def _auth_headers(key: str, scheme: str = "bearer") -> dict[str, str]:
    headers = {"User-Agent": "ShenQing-AI"}
    key_text = str(key or "")
    if not key_text:
        return headers
    if scheme == "api-key":
        headers["api-key"] = key_text
    else:
        headers["Authorization"] = f"Bearer {key_text}"
    return headers


def _get_json(url: str, key: str, timeout: float, scheme: str) -> tuple[dict | None, str]:
    """GET JSON；错误信息已脱敏，不抛异常。"""
    request = urllib.request.Request(url, method="GET", headers=_auth_headers(key, scheme))
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310
            raw = response.read().decode("utf-8", errors="replace")
        data = json.loads(raw)
        if not isinstance(data, dict):
            return None, "返回格式不正确"
        return data, ""
    except urllib.error.HTTPError as exc:
        return None, f"AUTH {exc.code}" if exc.code in (401, 403) else f"HTTP {exc.code}"
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
        return None, f"网络错误：{exc}"


def fetch_models(base: str, key: str, provider: str = "") -> list[str]:
    """GET {base}/models，解析 data[].id；失败返回 []（不抛异常）。

    免 Key 服务商（pollinations）允许不带 Key；MiMo 先 Bearer，失败再 api-key 重试一次。
    """
    base_text = str(base or "").rstrip("/")
    key_text = str(key or "")
    if not base_text:
        return []
    if not key_text and provider and provider_needs_key(provider):
        return []
    url = f"{base_text}/models"
    schemes = ["bearer"]
    if str(provider or "") == "mimo" and key_text:
        schemes.append("api-key")
    last_error = ""
    for scheme in schemes:
        data, error = _get_json(url, key_text, MODELS_TIMEOUT, scheme)
        if data is None:
            last_error = error
            continue
        items = data.get("data")
        models: list[str] = []
        if isinstance(items, list):
            for item in items:
                model_id = ""
                if isinstance(item, dict):
                    model_id = str(item.get("id") or "").strip()
                elif isinstance(item, str):
                    model_id = item.strip()
                if model_id and model_id not in models:
                    models.append(model_id)
        return models
    logger.info("获取模型列表失败（provider=%s）：%s", provider, last_error)
    return []


def cache_models(cache: dict, provider: str, models: list[str], now: float | None = None) -> dict:
    result = dict(cache) if isinstance(cache, dict) else {}
    result[str(provider)] = {
        "models": [str(item) for item in models or []],
        "fetchedAt": float(now if now is not None else time.time()),
    }
    return result


def cached_models(cache: dict, provider: str, now: float | None = None) -> list[str]:
    if not isinstance(cache, dict):
        return []
    entry = cache.get(str(provider))
    if not isinstance(entry, dict):
        return []
    try:
        fetched_at = float(entry.get("fetchedAt", 0))
    except (TypeError, ValueError):
        return []
    current = float(now if now is not None else time.time())
    if fetched_at <= 0 or current - fetched_at > MODELS_CACHE_TTL:
        return []
    models = entry.get("models")
    if not isinstance(models, list):
        return []
    return [str(item) for item in models if str(item)]


class AIService:
    def __init__(self, settings) -> None:  # noqa: ANN001
        self._settings = settings
        self._executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="shenqing-ai")

    # ---------- 配置 ----------
    def enabled(self) -> bool:
        return bool(self._settings.get("ai_enabled", False))

    def provider(self) -> str:
        value = str(self._settings.get("ai_provider", DEFAULT_PROVIDER) or DEFAULT_PROVIDER)
        return value if value in PROVIDERS else DEFAULT_PROVIDER

    def preset(self) -> dict[str, Any]:
        return PROVIDERS[self.provider()]

    def api_base(self) -> str:
        return str(self._settings.get("ai_api_base", "") or self.preset()["base"] or "")

    def api_key(self) -> str:
        return str(self._settings.get("ai_api_key", "") or "")

    def has_key(self) -> bool:
        return bool(self.api_key())

    def needs_key(self) -> bool:
        return bool(self.preset().get("needs_key", True))

    def supports_reasoning(self) -> bool:
        return bool(self.preset().get("supports_reasoning", False))

    def supports_web_search(self) -> bool:
        return bool(self.preset().get("supports_web_search", False))

    def reasoning_enabled(self) -> bool:
        return bool(self._settings.get("ai_reasoning_enabled", True))

    def web_search_enabled(self) -> bool:
        return bool(self._settings.get("ai_web_search_enabled", False))

    def reasoning_effort(self) -> str:
        return str(self._settings.get("ai_reasoning_effort", "") or "")

    def model(self) -> str:
        return str(self._settings.get("ai_model", "") or self.preset()["default_model"] or "")

    def configured(self) -> bool:
        """免 Key 服务商恒为可聊；其余需要启用 + Key。"""
        if not self.api_base() or not self.model():
            return False
        if not self.needs_key():
            return True
        return bool(self.enabled() and self.api_key())

    def set_provider(self, value: str) -> bool:
        key = str(value or "").strip()
        if key not in PROVIDERS:
            return False
        old = self.provider()
        self._settings.set("ai_provider", key)
        if key != old:
            if key == "custom":
                self._settings.set("ai_api_base", "")
                self._settings.set("ai_model", "")
            else:
                self._settings.set("ai_api_base", PROVIDERS[key]["base"])
                self._settings.set("ai_model", PROVIDERS[key]["default_model"])
        return True

    # ---------- 脱敏 ----------
    def sanitize(self, text: object) -> str:
        result = str(text or "")
        key = self.api_key()
        if key:
            result = result.replace(key, "***")
            if len(key) > 6:
                result = result.replace(key[:6] + "***", "***")
        return result

    # ---------- HTTP ----------
    def _endpoint(self) -> str:
        return f"{self.api_base().rstrip('/')}/chat/completions"

    def _auth_schemes(self) -> list[str]:
        if not self.api_key():
            return ["none"]
        schemes = ["bearer"]
        if self.preset().get("api_key_header"):
            schemes.append("api-key")
        return schemes

    def _post_json(
        self, url: str, payload: dict, timeout: float, scheme: str = "bearer"
    ) -> tuple[dict | None, str]:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers = {"Content-Type": "application/json", "User-Agent": "ShenQing-AI"}
        headers.update(_auth_headers(self.api_key(), scheme))
        request = urllib.request.Request(url, data=body, method="POST", headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310
                raw = response.read().decode("utf-8", errors="replace")
            data = json.loads(raw)
            if not isinstance(data, dict):
                return None, "AI 返回格式不正确"
            return data, ""
        except urllib.error.HTTPError as exc:
            detail = ""
            try:
                detail = exc.read().decode("utf-8", errors="replace")[:200]
            except Exception:  # noqa: BLE001
                pass
            if exc.code in (401, 403):
                return None, f"AUTH {exc.code}"
            if exc.code == 404:
                return None, (
                    "接口地址可能不正确（HTTP 404）：请检查 API Base，"
                    "例如 DeepSeek 应为 https://api.deepseek.com/v1"
                )
            if exc.code == 429:
                return None, "请求过于频繁（HTTP 429），请稍后再试"
            if exc.code >= 500:
                return None, f"服务端错误（HTTP {exc.code}），请稍后再试"
            suffix = f"：{self.sanitize(detail)}" if detail else ""
            return None, f"请求被拒绝（HTTP {exc.code}）{suffix}"
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            return None, self.sanitize(f"网络错误：{exc}")

    def _request_once(
        self, payload: dict, timeout: float, scheme: str = "bearer"
    ) -> tuple[dict | None, str]:
        return self._post_json(self._endpoint(), payload, timeout, scheme)

    def _request(self, payload: dict, timeout: float, retries: int = 1) -> tuple[dict | None, str]:
        last_error = ""
        for scheme in self._auth_schemes():
            if scheme == "none":
                data, error = self._request_once(payload, timeout, "bearer")
                return (data, "") if data is not None else (None, error)
            for attempt in range(retries + 1):
                data, error = self._request_once(payload, timeout, scheme)
                if data is not None:
                    return data, ""
                last_error = error
                if error.startswith("AUTH"):
                    break
                if attempt < retries:
                    logger.info("AI 请求失败，重试一次：%s", error)
            if not last_error.startswith("AUTH"):
                break
        return None, last_error

    # ---------- 联网检索 ----------
    def deepseek_web_context(self, query: str, timeout: float = WEB_SEARCH_TIMEOUT) -> str:
        """DeepSeek /tools/search：返回可拼进 system 的摘要文本；失败返回空串。"""
        text = str(query or "").strip()
        if not text or self.provider() != "deepseek":
            return ""
        url = f"{self.api_base().rstrip('/')}/tools/search"
        payload = {"query": text, "count": 5, "need_content": True}
        data, error = self._post_json(url, payload, timeout, "bearer")
        if data is None:
            logger.info("DeepSeek 联网检索失败：%s", error)
            return ""
        results = data.get("results")
        if not isinstance(results, list):
            results = data.get("data") if isinstance(data.get("data"), list) else []
        lines: list[str] = []
        for item in results[:5]:
            if isinstance(item, str):
                lines.append(f"- {item[:500]}")
                continue
            if not isinstance(item, dict):
                continue
            title = str(item.get("title") or item.get("name") or "").strip()
            url_value = str(item.get("url") or item.get("link") or "").strip()
            content = str(
                item.get("content") or item.get("snippet") or item.get("summary") or ""
            ).strip()
            line = "- "
            if title:
                line += title
            if url_value:
                line += f" ({url_value})"
            if content:
                line += f"：{content[:500]}"
            if line.strip() != "-":
                lines.append(line)
        return "\n".join(lines)

    def _last_user_text(self, messages: list[dict]) -> str:
        for message in reversed(messages or []):
            if isinstance(message, dict) and str(message.get("role")) == "user":
                return str(message.get("content") or "")
        return ""

    def _enhance_messages(self, messages: list[dict]) -> list[dict]:
        """联网：DeepSeek 拼检索上下文；GLM 走 web_search 工具参数（在 payload 里）。"""
        result = [dict(message) for message in messages or []]
        if not self.web_search_enabled() or not self.supports_web_search():
            return result
        if self.provider() == "deepseek":
            context = self.deepseek_web_context(self._last_user_text(result))
            if context:
                injected = "以下是联网检索结果，请结合它们回答：\n" + context
                if result and str(result[0].get("role")) == "system":
                    result[0]["content"] = str(result[0].get("content") or "") + "\n\n" + injected
                else:
                    result.insert(0, {"role": "system", "content": injected})
        return result

    def _build_payload(self, messages: list[dict], max_tokens: int) -> dict:
        provider = self.provider()
        payload: dict[str, Any] = {
            "model": self.model(),
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": int(max_tokens),
        }
        if self.supports_reasoning() and self.reasoning_enabled():
            if provider == "deepseek":
                payload["thinking"] = {"type": "enabled"}
                effort = self.reasoning_effort()
                if effort:
                    payload["reasoning_effort"] = effort
            elif provider == "openai":
                # 仅推理型模型支持 reasoning_effort；gpt-4o-mini 等传了会 400
                effort = self.reasoning_effort()
                model = self.model().lower()
                if effort or model.startswith(("o1", "o3", "o4", "gpt-5")):
                    payload["reasoning_effort"] = effort or "medium"
            # pollinations / mimo：模型自带思考，无需额外参数
        elif provider == "deepseek":
            payload["thinking"] = {"type": "disabled"}
        if provider == "glm" and self.web_search_enabled() and self.supports_web_search():
            payload["tools"] = [{"type": "web_search", "web_search": {"enable": True}}]
        return payload

    def chat(
        self,
        messages: list[dict],
        *,
        timeout: float = REQUEST_TIMEOUT,
        max_tokens: int = MAX_TOKENS,
    ) -> dict:
        """同步调用 /chat/completions；返回 {ok,text,reasoning,error,provider,model,usage}。"""
        if not self.configured():
            return {
                "ok": False,
                "text": "",
                "reasoning": "",
                "error": "AI 未启用或未配置",
                "provider": self.provider(),
                "model": self.model(),
                "usage": {},
            }
        enhanced = self._enhance_messages(messages)
        payload = self._build_payload(enhanced, max_tokens)
        data, error = self._request(payload, timeout=timeout, retries=1)
        provider = self.provider()
        if data is None:
            logger.info("AI 请求失败（provider=%s model=%s）：%s", provider, self.model(), error)
            return {
                "ok": False,
                "text": "",
                "reasoning": "",
                "error": error,
                "provider": provider,
                "model": self.model(),
                "usage": {},
            }
        try:
            choices = data.get("choices") or []
            message = choices[0].get("message") if choices else {}
            text = str((message or {}).get("content") or "").strip()
            reasoning = str(
                (message or {}).get("reasoning_content")
                or (message or {}).get("reasoning")
                or ""
            ).strip()
        except (AttributeError, IndexError, TypeError):
            text = ""
            reasoning = ""
        usage = self._parse_usage(data)
        if not text:
            return {
                "ok": False,
                "text": "",
                "reasoning": reasoning,
                "error": "AI 返回为空",
                "provider": provider,
                "model": self.model(),
                "usage": usage,
            }
        return {
            "ok": True,
            "text": text,
            "reasoning": reasoning,
            "error": "",
            "provider": provider,
            "model": self.model(),
            "usage": usage,
        }

    def _parse_usage(self, data: dict) -> dict:
        raw = data.get("usage") if isinstance(data, dict) else None
        usage = raw if isinstance(raw, dict) else {}
        try:
            tokens_in = int(usage.get("prompt_tokens") or 0)
        except (TypeError, ValueError):
            tokens_in = 0
        try:
            tokens_out = int(usage.get("completion_tokens") or 0)
        except (TypeError, ValueError):
            tokens_out = 0
        try:
            total = int(usage.get("total_tokens") or (tokens_in + tokens_out))
        except (TypeError, ValueError):
            total = tokens_in + tokens_out
        cost, currency = estimate_cost(self.provider(), self.model(), tokens_in, tokens_out)
        return {
            "model": self.model(),
            "provider": self.provider(),
            "prompt_tokens": tokens_in,
            "completion_tokens": tokens_out,
            "total_tokens": total,
            "cost": cost,
            "currency": currency,
        }

    def ask(self, prompt: str, *, timeout: float = REQUEST_TIMEOUT) -> dict:
        messages = [
            {
                "role": "system",
                "content": "你是「深清」专注工具里的 AI 助手，回答简洁、实用、中文优先。",
            },
            {"role": "user", "content": str(prompt or "")},
        ]
        return self.chat(messages, timeout=timeout)

    # ---------- 设置语义搜索 ----------
    def search_settings(self, query: str, items: list[dict], limit: int = 3) -> list[dict]:
        text = str(query or "").strip()
        if not text:
            return []
        if not self.configured():
            return local_search(text, items, limit)
        catalog = [
            {"key": item.get("key"), "title": item.get("title"), "hint": item.get("hint", "")}
            for item in items or []
        ]
        prompt = (
            "从下面的设置项中选出与用户查询最相关的 1-3 个，只输出 JSON 数组，"
            '元素形如 {"key": "...", "title": "..."}，不要输出任何解释。\n'
            f"设置项：{json.dumps(catalog, ensure_ascii=False)}\n"
            f"用户查询：{text}"
        )
        result = self.chat(
            [
                {"role": "system", "content": "你是设置搜索助手，只输出合法 JSON 数组。"},
                {"role": "user", "content": prompt},
            ],
            timeout=SEARCH_TIMEOUT,
            max_tokens=200,
        )
        if not result.get("ok"):
            return local_search(text, items, limit)
        raw = str(result.get("text") or "")
        match = re.search(r"\[.*\]", raw, flags=re.S)
        if not match:
            return local_search(text, items, limit)
        try:
            parsed = json.loads(match.group(0))
        except json.JSONDecodeError:
            return local_search(text, items, limit)
        valid = {str(item.get("key")): str(item.get("title") or "") for item in items or []}
        results: list[dict] = []
        if isinstance(parsed, list):
            for entry in parsed:
                key = str(entry.get("key") or "") if isinstance(entry, dict) else str(entry or "")
                if key in valid and all(item["key"] != key for item in results):
                    results.append({"key": key, "title": valid[key]})
                if len(results) >= max(1, int(limit)):
                    break
        return results or local_search(text, items, limit)

    # ---------- 异步 ----------
    def submit_ask(self, prompt: str, callback: Callable[[dict], None]) -> None:
        def _work() -> None:
            try:
                result = self.ask(prompt)
            except Exception as exc:  # noqa: BLE001
                result = {"ok": False, "text": "", "reasoning": "", "error": self.sanitize(exc)}
            try:
                callback(result)
            except Exception:  # noqa: BLE001
                logger.debug("AI 回调异常", exc_info=True)

        self._executor.submit(_work)

    def submit_test(self, callback: Callable[[dict], None]) -> None:
        self.submit_ask("请只回复两个字：正常", callback)

    def shutdown(self) -> None:
        try:
            self._executor.shutdown(wait=False, cancel_futures=True)
        except TypeError:
            self._executor.shutdown(wait=False)

    def complete(self, prompt: str, *, context: str = "") -> dict:
        result = self.ask(prompt)
        result["context"] = str(context or "")
        return result
