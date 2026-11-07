"""AI 集成（v0.9）：OpenAI 兼容 /chat/completions，异步、可重试。

- 预设服务商：groq / glm(智谱) / siliconflow / custom；
- 设置项：ai_enabled / ai_provider / ai_api_base / ai_api_key / ai_model；
- 线程池异步（bridge 用回调转信号回主线程），超时 20s，失败重试 1 次；
- API Key 只在本机 settings.json，日志与错误信息里一律脱敏；
- 用途：问答 ask() + 设置语义搜索 search_settings()（失败回退本地模糊匹配）。
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
MAX_TOKENS = 768

PROVIDERS: dict[str, dict[str, Any]] = {
    "groq": {
        "value": "groq",
        "label": "Groq",
        "base": "https://api.groq.com/openai/v1",
        "models": ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"],
        "default_model": "llama-3.3-70b-versatile",
    },
    "glm": {
        "value": "glm",
        "label": "智谱 GLM",
        "base": "https://open.bigmodel.cn/api/paas/v4",
        "models": ["glm-4.7-flash", "glm-4-flash", "glm-4-plus"],
        "default_model": "glm-4.7-flash",
    },
    "siliconflow": {
        "value": "siliconflow",
        "label": "SiliconFlow",
        "base": "https://api.siliconflow.cn/v1",
        "models": ["Qwen/Qwen2.5-7B-Instruct", "Qwen/Qwen2.5-14B-Instruct"],
        "default_model": "Qwen/Qwen2.5-7B-Instruct",
    },
    "deepseek": {
        "value": "deepseek",
        "label": "DeepSeek",
        "base": "https://api.deepseek.com/v1",
        "models": ["deepseek-chat", "deepseek-reasoner"],
        "default_model": "deepseek-chat",
    },
    "mimo": {
        "value": "mimo",
        "label": "小米 MiMo",
        "base": "https://api.xiaomimimo.com/v1",
        "models": ["mimo-v2.6-flash", "mimo-v2.6-pro"],
        "default_model": "mimo-v2.6-flash",
        #: 除 Bearer 外还支持 api-key 头（Bearer 失败时回退一次）
        "api_key_header": True,
    },
    "openai": {
        "value": "openai",
        "label": "ChatGPT",
        "base": "https://api.openai.com/v1",
        "models": ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"],
        "default_model": "gpt-4o-mini",
    },
    "custom": {
        "value": "custom",
        "label": "自定义",
        "base": "",
        "models": [],
        "default_model": "",
    },
}
DEFAULT_PROVIDER = "groq"


def provider_list() -> list[dict]:
    return [
        {
            "value": key,
            "id": key,
            "label": item["label"],
            "base": item["base"],
            "models": list(item["models"]),
        }
        for key, item in PROVIDERS.items()
    ]


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


MODELS_CACHE_TTL = 24 * 60 * 60
MODELS_TIMEOUT = 15.0


def _auth_headers(key: str, scheme: str = "bearer") -> dict[str, str]:
    headers = {"User-Agent": "ShenQing-AI"}
    if scheme == "api-key":
        headers["api-key"] = str(key or "")
    else:
        headers["Authorization"] = f"Bearer {key}"
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

    MiMo 先 Bearer，失败后再用 api-key 头重试一次。
    """
    base_text = str(base or "").rstrip("/")
    key_text = str(key or "")
    if not base_text or not key_text:
        return []
    url = f"{base_text}/models"
    schemes = ["bearer"]
    if str(provider or "") == "mimo":
        # MiMo 除 Bearer 外还支持 api-key 头：Bearer 失败后再试一次
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


def cache_models(
    cache: dict, provider: str, models: list[str], now: float | None = None
) -> dict:
    """返回更新后的 provider → {models, fetchedAt} 缓存（24h 过期）。"""
    result = dict(cache) if isinstance(cache, dict) else {}
    result[str(provider)] = {
        "models": [str(item) for item in models or []],
        "fetchedAt": float(now if now is not None else time.time()),
    }
    return result


def cached_models(
    cache: dict, provider: str, now: float | None = None
) -> list[str]:
    """读取未过期的模型缓存；没有/过期返回 []。"""
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

    def model(self) -> str:
        return str(self._settings.get("ai_model", "") or self.preset()["default_model"] or "")

    def configured(self) -> bool:
        return bool(self.enabled() and self.api_base() and self.api_key() and self.model())

    def set_provider(self, value: str) -> bool:
        key = str(value or "").strip()
        if key not in PROVIDERS:
            return False
        old = self.provider()
        self._settings.set("ai_provider", key)
        if key != old:
            if key == "custom":
                # 自定义：清空旧服务商的 base/model，由用户填写
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
        base = self.api_base().rstrip("/")
        return f"{base}/chat/completions"

    def _auth_schemes(self) -> list[str]:
        schemes = ["bearer"]
        if self.preset().get("api_key_header"):
            schemes.append("api-key")
        return schemes

    def _request_once(
        self, payload: dict, timeout: float, scheme: str = "bearer"
    ) -> tuple[dict | None, str]:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "User-Agent": "ShenQing-AI",
        }
        headers.update(_auth_headers(self.api_key(), scheme))
        request = urllib.request.Request(
            self._endpoint(),
            data=body,
            method="POST",
            headers=headers,
        )
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
            code = "AUTH" if exc.code in (401, 403) else "HTTP"
            return (
                None,
                self.sanitize(f"{code} {exc.code}: {detail}") if detail else f"{code} {exc.code}",
            )
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            return None, self.sanitize(f"网络错误：{exc}")

    def _request(self, payload: dict, timeout: float, retries: int = 1) -> tuple[dict | None, str]:
        last_error = ""
        for scheme in self._auth_schemes():
            for attempt in range(retries + 1):
                data, error = self._request_once(payload, timeout, scheme)
                if data is not None:
                    return data, ""
                last_error = error
                if error.startswith("AUTH"):
                    break  # 鉴权失败：换下一种认证头（MiMo）
                if attempt < retries:
                    logger.info("AI 请求失败，重试一次：%s", error)
            if not last_error.startswith("AUTH"):
                break
        return None, last_error

    def chat(
        self,
        messages: list[dict],
        *,
        timeout: float = REQUEST_TIMEOUT,
        max_tokens: int = MAX_TOKENS,
    ) -> dict:
        """同步调用 /chat/completions；返回 {ok,text,error,provider}。"""
        if not self.configured():
            return {
                "ok": False,
                "text": "",
                "error": "AI 未启用或未配置",
                "provider": self.provider(),
            }
        payload = {
            "model": self.model(),
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": int(max_tokens),
        }
        data, error = self._request(payload, timeout=timeout, retries=1)
        if data is None:
            logger.info(
                "AI 请求失败（provider=%s model=%s）：%s",
                self.provider(),
                self.model(),
                error,
            )
            return {"ok": False, "text": "", "error": error, "provider": self.provider()}
        try:
            choices = data.get("choices") or []
            message = choices[0].get("message") if choices else {}
            text = str((message or {}).get("content") or "").strip()
        except (AttributeError, IndexError, TypeError):
            text = ""
        if not text:
            return {"ok": False, "text": "", "error": "AI 返回为空", "provider": self.provider()}
        return {"ok": True, "text": text, "error": "", "provider": self.provider()}

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
                result = {"ok": False, "text": "", "error": self.sanitize(exc)}
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
        except TypeError:  # 旧 Python
            self._executor.shutdown(wait=False)

    # ---------- 兼容旧接口 ----------
    def complete(self, prompt: str, *, context: str = "") -> dict:
        result = self.ask(prompt)
        result["context"] = str(context or "")
        return result
