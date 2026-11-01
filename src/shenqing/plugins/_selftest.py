"""插件系统自测：直接运行 `python -m shenqing.plugins._selftest`。

全程只在临时目录里造插件与数据，不碰真实的 %APPDATA%\\ShenQing。
覆盖：清单校验、扫描加载、同 id 优先级、坏插件隔离、事件分发、插件设置落盘、
插件信号、停用（on_unload）/ 重新启用、热重载。

退出码 0 = 全部通过，1 = 有断言失败。
"""

from __future__ import annotations

import json
import logging
import os
import sys
import tempfile
from pathlib import Path

from ..settings import Settings
from .api import ManifestError, PluginManifest
from .manager import (
    PLUGINS_DIR_ENV,
    PluginManager,
    default_plugins_dirs,
)

PASSED: list[str] = []


def check(condition: bool, message: str) -> None:
    """断言 + 打印一行通过信息；失败抛 AssertionError。"""
    if not condition:
        raise AssertionError(message)
    PASSED.append(message)
    print(f"  [通过] {message}")


def read_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AssertionError(f"读取 {path} 失败：{exc}") from exc
    return data if isinstance(data, dict) else {}


def write_plugin(
    root: Path,
    plugin_id: str,
    name: str,
    main_source: str,
    *,
    version: str = "1.0.0",
    api_version: str = "0.1",
) -> Path:
    """在 root/<id>/ 下造一个插件目录（plugin.json + main.py）。"""
    plugin_dir = root / plugin_id
    plugin_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "id": plugin_id,
        "name": name,
        "version": version,
        "api_version": api_version,
        "entry": "main.py",
        "author": "自测",
        "description": "selftest 用的临时插件",
    }
    (plugin_dir / "plugin.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (plugin_dir / "main.py").write_text(main_source, encoding="utf-8")
    return plugin_dir


SELFTEST_PLUGIN = '''# 自测插件：把收到的钩子写进自己的 settings，供断言读取。
from __future__ import annotations

from shenqing.plugins.api import PluginAPI, PluginBase


class Plugin(PluginBase):
    def on_load(self, api: PluginAPI) -> None:
        self.api = api
        api.set_setting("loaded", int(api.get_setting("loaded", 0)) + 1)

    def on_unload(self) -> None:
        self.api.set_setting("unloaded", True)

    def on_session_start(self, space: dict) -> None:
        self.api.set_setting("last_space", space.get("name", ""))

    def on_session_end(self, summary: dict) -> None:
        sessions = int(self.api.get_setting("sessions", 0)) + 1
        minutes = float(self.api.get_setting("minutes", 0.0))
        self.api.set_setting("sessions", sessions)
        self.api.set_setting("minutes", minutes + float(summary.get("minutes", 0.0)))
        self.api.emit_signal("selftest", {"sessions": sessions})

    def on_tick(self, remaining: int) -> None:
        self.api.set_setting("remaining", int(remaining))

    def on_process_blocked(self, exe: str) -> None:
        self.api.set_setting("blocked", str(exe))

    def on_settings_changed(self, key: str, value: object) -> None:
        self.api.set_setting("last_setting", str(key))
'''

BROKEN_PLUGIN = '''# 自测插件：on_load 故意抛异常，验证 manager 的异常隔离。
from shenqing.plugins.api import PluginAPI, PluginBase


class Plugin(PluginBase):
    def on_load(self, api: PluginAPI) -> None:
        raise RuntimeError("selftest 故意失败")
'''


def check_manifest() -> None:
    print("[1/10] 清单校验（必填字段 / id / entry / api_version）")
    data = {
        "id": "com.example.demo",
        "name": "演示",
        "version": "1.2.3",
        "api_version": "0.1",
        "entry": "main.py",
        "author": "作者",
        "custom": {"keep": True},
    }
    manifest = PluginManifest.from_dict(data)
    check(manifest.id == "com.example.demo", "合法清单解析出 id")
    check(manifest.extra == {"custom": {"keep": True}}, "未知字段保留在 extra")
    check(manifest.is_api_compatible(), "api_version 0.1 与宿主兼容")

    cases = [
        ("缺少 name", {key: value for key, value in data.items() if key != "name"}),
        ("非法 id", {**data, "id": "../evil"}),
        ("entry 越界", {**data, "entry": "../outside.py"}),
        ("entry 不是 .py", {**data, "entry": "main.txt"}),
        ("api_version 格式错误", {**data, "api_version": "abc"}),
    ]
    for label, broken in cases:
        try:
            PluginManifest.from_dict(broken)
        except ManifestError:
            check(True, f"拒绝{label}")
        else:
            raise AssertionError(f"应当拒绝{label}")

    newer = PluginManifest.from_dict({**data, "api_version": "1.0"})
    check(not newer.is_api_compatible(), "主版本不同判为不兼容")


def run(base: Path) -> None:
    logging.getLogger("shenqing.plugins").setLevel(logging.CRITICAL)
    user_root = base / "appdata_plugins"
    project_root = base / "project_plugins"
    missing_builtin = base / "builtin_missing"
    data_dir = base / "plugin_data"
    settings = Settings(base / "host_settings.json")

    selftest_id = "com.example.selftest"
    write_plugin(user_root, selftest_id, "自测插件", SELFTEST_PLUGIN)
    write_plugin(
        project_root, selftest_id, "阴影插件", SELFTEST_PLUGIN, version="9.9.9"
    )
    write_plugin(user_root, "com.example.broken", "坏插件", BROKEN_PLUGIN)
    invalid_dir = project_root / "com.example.invalid"
    invalid_dir.mkdir(parents=True, exist_ok=True)
    (invalid_dir / "plugin.json").write_text(
        '{"id": "com.example.invalid"}\n', encoding="utf-8"
    )

    print("[2/10] 扫描、加载与同 id 优先级（用户目录 > 项目目录）")
    manager = PluginManager(
        settings,
        plugin_dirs=[user_root, project_root],
        builtin_dir=missing_builtin,
        data_dir=data_dir,
    )
    plugins = {item["id"]: item for item in manager.list_plugins()}
    check(selftest_id in plugins, "扫描到自测插件")
    check(plugins[selftest_id]["enabled"] is True, "默认启用")
    check(plugins[selftest_id]["error"] is None, "加载无错误")
    check(plugins[selftest_id]["version"] == "1.0.0", "同 id 取用户目录版本（非 9.9.9）")
    check(
        Path(plugins[selftest_id]["path"]) == (user_root / selftest_id).resolve(),
        "插件路径指向用户目录",
    )
    check(manager.is_loaded(selftest_id), "插件实例已加载")

    print("[3/10] 坏插件隔离")
    broken = plugins.get("com.example.broken") or {}
    broken_error = str(broken.get("error", ""))
    check(
        "加载失败" in broken_error and "RuntimeError" in broken_error,
        "on_load 抛异常记录为 error 状态",
    )
    invalid = plugins.get("com.example.invalid") or {}
    check(bool(invalid.get("error")), "非法 plugin.json 记录为 error 状态")
    check(manager.is_loaded("com.example.broken") is False, "坏插件不会处于加载态")

    print("[4/10] 事件分发")
    signals: list[tuple[str, str, object]] = []
    manager.add_signal_listener(
        lambda pid, name, payload: signals.append((pid, name, payload))
    )
    manager.dispatch("session_start", {"id": "sp_1", "name": "超禅", "minutes": 25})
    manager.dispatch(
        "session_end",
        {"space": "超禅", "minutes": 25.0, "completed": True, "pauses": 0},
    )
    manager.dispatch("tick", 42)
    manager.dispatch("process_blocked", "game.exe")
    manager.dispatch("settings_changed", "theme", "Dark")

    plugin_settings_path = data_dir / selftest_id / "settings.json"
    saved = read_json(plugin_settings_path)
    check(saved.get("loaded") == 1, "on_load 只执行一次")
    check(saved.get("last_space") == "超禅", "on_session_start 收到空间名")
    check(saved.get("sessions") == 1, "on_session_end 累加会话数")
    check(saved.get("minutes") == 25.0, "on_session_end 累加分钟数")
    check(saved.get("remaining") == 42, "on_tick 收到剩余秒数")
    check(saved.get("blocked") == "game.exe", "on_process_blocked 收到进程名")
    check(saved.get("last_setting") == "theme", "on_settings_changed 收到设置键")
    check(signals and signals[0][:2] == (selftest_id, "selftest"), "插件信号送达监听器")

    print("[5/10] 停用插件（on_unload + 状态持久化）")
    check(manager.set_enabled(selftest_id, False) is True, "set_enabled(False) 返回 True")
    by_id = {item["id"]: item for item in manager.list_plugins()}
    check(by_id[selftest_id]["enabled"] is False, "列表显示已停用")
    check(read_json(plugin_settings_path).get("unloaded") is True, "停用时调用 on_unload")
    host_settings = read_json(settings.path)
    check(
        selftest_id in host_settings.get("disabled_plugins", []),
        "停用状态写入宿主 settings 的 disabled_plugins",
    )
    manager.dispatch("session_end", {"space": "超禅", "minutes": 25.0})
    check(read_json(plugin_settings_path).get("sessions") == 1, "停用后不再收到事件")

    print("[6/10] 重新启用")
    check(manager.set_enabled(selftest_id, True) is True, "set_enabled(True) 返回 True")
    check(read_json(plugin_settings_path).get("loaded") == 2, "重新启用再次执行 on_load")
    manager.dispatch("session_end", {"space": "超禅", "minutes": 10.0})
    check(read_json(plugin_settings_path).get("sessions") == 2, "重新启用后继续累加")
    check(read_json(plugin_settings_path).get("minutes") == 35.0, "历史数据保留")

    print("[7/10] 热重载")
    manager.reload()
    check(manager.is_loaded(selftest_id), "reload 后插件重新加载")
    check(read_json(plugin_settings_path).get("loaded") == 3, "reload 触发 on_load")
    check(read_json(plugin_settings_path).get("sessions") == 2, "reload 不丢插件设置")
    check(
        any(item["id"] == selftest_id for item in manager.list_plugins()),
        "reload 后列表完整",
    )

    print("[8/10] 查询与未知插件")
    check(manager.get_plugin(selftest_id) is not None, "get_plugin 取到插件实例")
    check(
        manager.set_enabled("com.example.missing", True) is False,
        "未知插件启用返回 False",
    )
    check(manager.get_plugin("com.example.missing") is None, "未知插件实例为 None")

    print("[9/10] 目录环境变量覆盖")
    old = os.environ.get(PLUGINS_DIR_ENV)
    try:
        override = base / "env_plugins"
        os.environ[PLUGINS_DIR_ENV] = str(override)
        check(default_plugins_dirs() == [override], "SHENQING_PLUGINS_DIR 覆盖默认目录")
    finally:
        if old is None:
            os.environ.pop(PLUGINS_DIR_ENV, None)
        else:
            os.environ[PLUGINS_DIR_ENV] = old

    print("[10/10] 清理")
    manager.reload()  # 再走一遍卸载路径，确认没有残留模块报错
    check(manager.list_plugins() != [], "重载后仍有插件记录")


def main() -> int:
    # Windows 控制台默认 GBK，先切到 UTF-8，保证中文结果能正常打印
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    print("深清插件系统自测开始（临时目录，不写真实 APPDATA）")
    check_manifest()
    try:
        with tempfile.TemporaryDirectory(prefix="shenqing_plugin_selftest_") as tmp:
            run(Path(tmp))
    except AssertionError as exc:
        print(f"\n[失败] {exc}")
        return 1
    print(f"\n全部通过：{len(PASSED)} 项检查，插件系统自测 OK。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
