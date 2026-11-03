"""插件目录校验命令。

用法::

    python -m shenqing.plugins.validate <插件目录>
    python -m shenqing.plugins.validate <插件目录> --json

检查内容：plugin.json 是否合法、api_version 与宿主是否兼容、entry 是否存在、
icon 是否可用。退出码 0 = 通过，1 = 未通过（有错误）。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from .api import PLUGIN_API_VERSION, ManifestError, PluginManifest
from .manager import resolve_relative_path


def validate_plugin_dir(target: str | Path) -> dict[str, Any]:
    """校验一个插件目录，返回可直接 JSON 化的结果字典。"""
    path = Path(target)
    if path.is_file() and path.name == "plugin.json":
        plugin_dir = path.parent
        manifest_path = path
    else:
        plugin_dir = path
        manifest_path = plugin_dir / "plugin.json"

    result: dict[str, Any] = {
        "path": str(plugin_dir),
        "ok": False,
        "manifest": None,
        "apiCompatible": None,
        "defaultEnabled": None,
        "entry": {"declared": "", "path": None, "exists": False},
        "icon": {"declared": "", "path": None, "exists": False},
        "errors": [],
        "warnings": [],
    }
    errors: list[str] = result["errors"]
    warnings: list[str] = result["warnings"]

    if not plugin_dir.is_dir():
        errors.append(f"插件目录不存在：{plugin_dir}")
        return result
    if not manifest_path.is_file():
        errors.append(f"缺少 plugin.json：{manifest_path}")
        return result

    try:
        manifest = PluginManifest.from_file(manifest_path)
    except ManifestError as exc:
        errors.append(str(exc))
        return result

    result["manifest"] = manifest.to_dict()
    result["defaultEnabled"] = manifest.default_enabled
    result["apiCompatible"] = manifest.is_api_compatible()
    if not result["apiCompatible"]:
        errors.append(
            f"API 版本不兼容：插件要求 {manifest.api_version}，"
            f"宿主为 {PLUGIN_API_VERSION}（主版本需一致）"
        )
    if manifest.id != plugin_dir.name:
        warnings.append(
            f"插件 id（{manifest.id}）与目录名（{plugin_dir.name}）不一致"
            "（允许，但同 id 会按目录优先级覆盖）"
        )

    try:
        entry_path = resolve_relative_path(plugin_dir, manifest.entry, ".py")
    except ValueError as exc:
        result["entry"] = {"declared": manifest.entry, "path": None, "exists": False}
        errors.append(f"entry 不可用：{manifest.entry}（{exc}）")
    else:
        result["entry"] = {
            "declared": manifest.entry,
            "path": str(entry_path),
            "exists": True,
        }

    if manifest.icon:
        try:
            icon_path = resolve_relative_path(plugin_dir, manifest.icon)
        except ValueError as exc:
            result["icon"] = {
                "declared": manifest.icon,
                "path": None,
                "exists": False,
            }
            warnings.append(f"icon 不可用（会被忽略）：{manifest.icon}（{exc}）")
        else:
            result["icon"] = {
                "declared": manifest.icon,
                "path": str(icon_path),
                "exists": True,
            }

    result["ok"] = not errors
    return result


def _print_report(result: dict[str, Any]) -> None:
    manifest = result.get("manifest")
    print(f"插件目录：{result['path']}")
    if manifest is None:
        print("清单：不合法")
    else:
        print(
            "清单：合法（id=%s，name=%s，version=%s）"
            % (manifest["id"], manifest["name"], manifest["version"])
        )
        print(
            "API 版本：%s（宿主 %s，%s）"
            % (
                manifest["api_version"],
                PLUGIN_API_VERSION,
                "兼容" if result.get("apiCompatible") else "不兼容",
            )
        )
        print(
            "默认状态：%s"
            % ("启用" if result.get("defaultEnabled") else "停用（首次安装默认禁用）")
        )
    entry = result.get("entry") or {}
    if entry.get("exists"):
        print(f"入口：{entry['declared']} -> {entry['path']}（存在）")
    else:
        print(f"入口：{entry.get('declared') or '未声明'}（不存在或不可用）")
    icon = result.get("icon") or {}
    if not icon.get("declared"):
        print("图标：未声明")
    elif icon.get("exists"):
        print(f"图标：{icon['declared']} -> {icon['path']}（存在）")
    else:
        print(f"图标：{icon['declared']}（不存在，会被忽略）")
    for warning in result.get("warnings", []):
        print(f"警告：{warning}")
    for error in result.get("errors", []):
        print(f"错误：{error}")
    print("结果：通过" if result.get("ok") else "结果：未通过")


def main(argv: list[str] | None = None) -> int:
    # Windows 控制台默认 GBK，先切到 UTF-8，保证中文结果能正常打印
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    parser = argparse.ArgumentParser(
        prog="python -m shenqing.plugins.validate",
        description="校验深清插件目录（plugin.json / API 版本 / 入口 / 图标）",
    )
    parser.add_argument("plugin_dir", help="插件目录（内含 plugin.json）")
    parser.add_argument("--json", action="store_true", help="输出机器可读的 JSON")
    args = parser.parse_args(argv)

    result = validate_plugin_dir(args.plugin_dir)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        _print_report(result)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
