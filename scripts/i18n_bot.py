"""用 AI 批量翻译未完成的 .ts 条目（GitHub Actions 里跑，也支持本地）。

用法：
    DEEPSEEK_API_KEY=sk-xxx python scripts/i18n_bot.py fr_FR ja_JP

- 通过 OpenAI 兼容接口（默认 DeepSeek）批量翻译未完成 / 空的 translation；
- 只处理 zh_CN 源文案 → 目标语言，保留占位符 %1/%2 与换行；
- 翻译完写回 .ts（标记为 finished），之后由 i18n.py compile 生成 .qm。
"""

from __future__ import annotations

import json
import os
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

LOCALES = Path("src/shenqing/locales")
API_BASE = os.environ.get("TRANSLATE_API_BASE", "https://api.deepseek.com/v1")
API_KEY = os.environ.get("DEEPSEEK_API_KEY") or os.environ.get("TRANSLATE_API_KEY", "")
MODEL = os.environ.get("TRANSLATE_MODEL", "deepseek-chat")
BATCH = 25

LANG_NAMES = {"fr_FR": "French", "ja_JP": "Japanese", "en_US": "English"}


def call_llm(messages: list[dict]) -> str:
    payload = json.dumps(
        {"model": MODEL, "messages": messages, "temperature": 0.2}, ensure_ascii=False
    ).encode("utf-8")
    request = urllib.request.Request(
        API_BASE + "/chat/completions",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + API_KEY,
            "User-Agent": "ShenQing-i18n-bot",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=120) as response:  # noqa: S310
        data = json.loads(response.read().decode("utf-8"))
    return str(data["choices"][0]["message"]["content"])


def translate_batch(sources: list[str], target_language: str) -> list[str]:
    joined = json.dumps(sources, ensure_ascii=False)
    prompt = (
        "You are a professional software localizer. Translate the following Chinese UI strings "
        "into " + target_language + ". Keep placeholders like %1 %2 and newlines exactly as-is. "
        "Return ONLY a JSON array of strings in the same order, no commentary."
        "\n\n" + joined
    )
    text = call_llm([{"role": "user", "content": prompt}]).strip()
    if text.startswith("```"):
        text = text.strip("`")
        text = text[4:] if text.startswith("json") else text
        text = text.strip()
    result = json.loads(text)
    if not isinstance(result, list) or len(result) != len(sources):
        raise ValueError("model returned unexpected result shape")
    return [str(item) for item in result]


def main(argv: list[str]) -> int:
    codes = [code for code in argv if code in LANG_NAMES] or ["fr_FR", "ja_JP"]
    if not API_KEY:
        print("TRANSLATE_API_KEY / DEEPSEEK_API_KEY is not set, skip bot translation")
        return 0
    for code in codes:
        if code == "en_US":
            continue
        path = LOCALES / (code + ".ts")
        if not path.exists():
            print("missing " + str(path) + ", skip")
            continue
        tree = ET.parse(path)
        targets: list[tuple[ET.Element, str]] = []
        for ctx in tree.getroot().iter("context"):
            for message in ctx.iter("message"):
                source = message.findtext("source") or ""
                translation = message.find("translation")
                if translation is None:
                    translation = ET.SubElement(message, "translation")
                text = (translation.text or "").strip()
                if not source.strip():
                    continue
                if text and translation.get("type") != "unfinished":
                    continue
                targets.append((translation, source))
        print(code + ": " + str(len(targets)) + " strings to translate")
        for index in range(0, len(targets), BATCH):
            chunk = targets[index:index + BATCH]
            sources = [item[1] for item in chunk]
            try:
                translated = translate_batch(sources, LANG_NAMES[code])
            except Exception as exc:  # noqa: BLE001
                print("  batch " + str(index // BATCH + 1) + " failed: " + str(exc))
                continue
            for (translation, _source), text in zip(chunk, translated):
                translation.attrib.pop("type", None)
                translation.text = text
            print("  batch " + str(index // BATCH + 1) + " done")
        tree.write(path, encoding="utf-8", xml_declaration=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
