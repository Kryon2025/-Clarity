"""插件系统自测：直接运行 python -m shenqing.plugins._selftest。

全程只在临时目录里造插件与数据，不碰真实的 %APPDATA%\\ShenQing。
覆盖：清单校验、扫描加载、同 id 优先级、坏插件隔离、事件分发、插件设置落盘、
UI 贡献注册（导航入口 / 遮罩组件 / set_ui_state）、注册路径与 id 校验、
default_enabled 首次停用与启用持久化、停用清理、重载、validate 命令。

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
    DEFAULTS_APPLIED_KEY,
    DISABLED_PLUGINS_KEY,
    PLUGINS_DIR_ENV,
    PluginManager,
    default_plugins_dirs,
)
from .validate import validate_plugin_dir

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
    entry: str = "main.py",
    default_enabled: bool = True,
    files: dict[str, str] | None = None,
) -> Path:
    """在 root/<id>/ 下造一个插件目录（plugin.json + main.py + 额外文件）。"""
    plugin_dir = root / plugin_id
    plugin_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "id": plugin_id,
        "name": name,
        "version": version,
        "api_version": api_version,
        "entry": entry,
        "author": "自测",
        "description": "selftest 用的临时插件",
        "default_enabled": default_enabled,
    }
    (plugin_dir / "plugin.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (plugin_dir / "main.py").write_text(main_source, encoding="utf-8")
    for relative, content in (files or {}).items():
        target = plugin_dir / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
    return plugin_dir


QML_STUB = """import QtQuick

Item {
    width: 200
    height: 120
}
"""

SELFTEST_PLUGIN = '''# 自测插件：把收到的钩子、注册结果写进自己的 settings，供断言读取。
from __future__ import annotations

from shenqing.plugins.api import PluginAPI, PluginBase


class Plugin(PluginBase):
    def on_load(self, api: PluginAPI) -> None:
        self.api = api
        api.set_setting("loaded", int(api.get_setting("loaded", 0)) + 1)
        results = {
            "nav": api.register_nav_item(
                "home", "自测入口", "ic_test", "qml/main.qml"
            ),
            "nav_plain": api.register_nav_item("about", "关于", icon="ic_about"),
            "widget": api.register_widget(
                "panel", "自测组件", "qml/widget.qml",
                anchor="bottomLeft", width=300, height=170,
            ),
            "widget_clamp": api.register_widget(
                "big", "超大组件", "qml/widget.qml",
                anchor="center", width=5, height=99999,
            ),
            "nav_traversal": api.register_nav_item(
                "bad1", "坏路径", qml_relative_path="../evil.qml"
            ),
            "nav_absolute": api.register_nav_item(
                "bad2", "坏路径", qml_relative_path="C:/evil.qml"
            ),
            "nav_missing": api.register_nav_item(
                "bad3", "坏路径", qml_relative_path="qml/missing.qml"
            ),
            "nav_dup": api.register_nav_item("home", "重复"),
            "widget_traversal": api.register_widget(
                "badw1", "坏路径", "../evil.qml"
            ),
            "widget_anchor": api.register_widget(
                "badw2", "坏路径", "qml/widget.qml", anchor="nowhere"
            ),
            "widget_dup": api.register_widget(
                "panel", "重复", "qml/widget.qml"
            ),
        }
        api.set_setting("reg_results", results)
        api.set_ui_state({"phase": "loaded"})

    def on_unload(self) -> None:
        self.api.set_setting("unloaded", True)

    def on_session_start(self, space: dict) -> None:
        self.api.set_setting("last_space", space.get("name", ""))
        self.api.set_ui_state(
            {"phase": "running", "space": space.get("name", "")}
        )

    def on_session_end(self, summary: dict) -> None:
        sessions = int(self.api.get_setting("sessions", 0)) + 1
        minutes = float(self.api.get_setting("minutes", 0.0))
        self.api.set_setting("sessions", sessions)
        self.api.set_setting("minutes", minutes + float(summary.get("minutes", 0.0)))
        self.api.set_ui_state(
            {"phase": "ended", "last_minutes": summary.get("minutes", 0)}
        )
        self.api.emit_signal("selftest", {"sessions": sessions})

    def on_tick(self, remaining: int) -> None:
        self.api.set_setting("remaining", int(remaining))

    def on_process_blocked(self, exe: str) -> None:
        self.api.set_setting("blocked", str(exe))

    def on_settings_changed(self, key: str, value: object) -> None:
        self.api.set_setting("last_setting", str(key))
'''

DEFAULT_OFF_PLUGIN = '''# 自测插件：manifest default_enabled=false，验证首次扫描自动停用。
from __future__ import annotations

from shenqing.plugins.api import PluginAPI, PluginBase


class Plugin(PluginBase):
    def on_load(self, api: PluginAPI) -> None:
        self.api = api
        api.set_setting("loaded", int(api.get_setting("loaded", 0)) + 1)
'''

BROKEN_PLUGIN = '''# 自测插件：on_load 故意抛异常，验证 manager 的异常隔离。
from shenqing.plugins.api import PluginAPI, PluginBase


class Plugin(PluginBase):
    def on_load(self, api: PluginAPI) -> None:
        raise RuntimeError("selftest 故意失败")
'''


def check_manifest() -> None:
    print("[1/12] 清单校验（必填字段 / id / entry / icon / default_enabled）")
    data = {
        "id": "com.example.demo",
        "name": "演示",
        "version": "1.2.3",
        "api_version": "0.1",
        "entry": "main.py",
        "author": "作者",
        "icon": "assets/icon.png",
        "default_enabled": False,
        "custom": {"keep": True},
    }
    manifest = PluginManifest.from_dict(data)
    check(manifest.id == "com.example.demo", "合法清单解析出 id")
    check(manifest.icon == "assets/icon.png", "icon 相对路径被规范化")
    check(manifest.default_enabled is False, "default_enabled=false 被解析")
    check(manifest.extra == {"custom": {"keep": True}}, "未知字段保留在 extra")
    check(manifest.is_api_compatible(), "api_version 0.1 与宿主兼容")

    cases = [
        ("缺少 name", {key: value for key, value in data.items() if key != "name"}),
        ("非法 id", {**data, "id": "../evil"}),
        ("entry 越界", {**data, "entry": "../outside.py"}),
        ("entry 不是 .py", {**data, "entry": "main.txt"}),
        ("api_version 格式错误", {**data, "api_version": "abc"}),
        ("icon 越界", {**data, "icon": "../evil.png"}),
        ("default_enabled 不是布尔", {**data, "default_enabled": "yes"}),
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
    defaultoff_id = "com.example.defaultoff"
    write_plugin(
        user_root,
        selftest_id,
        "自测插件",
        SELFTEST_PLUGIN,
        files={"qml/main.qml": QML_STUB, "qml/widget.qml": QML_STUB},
    )
    write_plugin(
        project_root, selftest_id, "阴影插件", SELFTEST_PLUGIN, version="9.9.9"
    )
    write_plugin(user_root, "com.example.broken", "坏插件", BROKEN_PLUGIN)
    write_plugin(
        user_root,
        defaultoff_id,
        "默认停用插件",
        DEFAULT_OFF_PLUGIN,
        default_enabled=False,
    )
    invalid_dir = project_root / "com.example.invalid"
    invalid_dir.mkdir(parents=True, exist_ok=True)
    (invalid_dir / "plugin.json").write_text(
        '{"id": "com.example.invalid"}\n', encoding="utf-8"
    )

    print("[2/12] 扫描、加载与同 id 优先级（用户目录 > 项目目录）")
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

    print("[3/12] default_enabled=false 首次扫描自动停用")
    check(defaultoff_id in plugins, "扫描到默认停用插件")
    check(plugins[defaultoff_id]["enabled"] is False, "首次扫描自动停用")
    host_settings = read_json(settings.path)
    check(
        defaultoff_id in host_settings.get(DISABLED_PLUGINS_KEY, []),
        "自动停用写入 disabled_plugins",
    )
    check(
        defaultoff_id in host_settings.get(DEFAULTS_APPLIED_KEY, []),
        "默认停用规则写入 plugin_defaults_applied",
    )
    check(manager.is_loaded(defaultoff_id) is False, "默认停用插件未加载")

    print("[4/12] 坏插件隔离")
    broken = plugins.get("com.example.broken") or {}
    broken_error = str(broken.get("error", ""))
    check(
        "加载失败" in broken_error and "RuntimeError" in broken_error,
        "on_load 抛异常记录为 error 状态",
    )
    invalid = plugins.get("com.example.invalid") or {}
    check(bool(invalid.get("error")), "非法 plugin.json 记录为 error 状态")
    check(manager.is_loaded("com.example.broken") is False, "坏插件不会处于加载态")

    print("[5/12] UI 贡献注册（导航入口 / 遮罩组件 / UI 状态 / 路径校验）")
    plugin_settings_path = data_dir / selftest_id / "settings.json"
    saved = read_json(plugin_settings_path)
    results = saved.get("reg_results") or {}
    check(results.get("nav") is True, "注册导航入口成功")
    check(results.get("nav_plain") is True, "注册无页面导航入口成功")
    check(results.get("widget") is True, "注册遮罩组件成功")
    check(results.get("widget_clamp") is True, "尺寸越界会被吸附后注册成功")
    check(results.get("nav_traversal") is False, "拒绝 ../ 越界的导航入口 QML")
    check(results.get("nav_absolute") is False, "拒绝绝对路径的导航入口 QML")
    check(results.get("nav_missing") is False, "拒绝不存在的导航入口 QML")
    check(results.get("nav_dup") is False, "拒绝重复的导航入口 id")
    check(results.get("widget_traversal") is False, "拒绝 ../ 越界的组件 QML")
    check(results.get("widget_anchor") is False, "拒绝非法 anchor")
    check(results.get("widget_dup") is False, "拒绝重复的组件 id")

    nav_items = manager.list_nav_items()
    widgets = manager.list_widgets()
    check(len(nav_items) == 2, "list_nav_items 只包含注册成功的 2 个入口")
    check(
        nav_items[0]["pluginId"] == selftest_id
        and nav_items[0]["itemId"] == "home"
        and str(nav_items[0]["qmlPath"]).endswith("main.qml"),
        "导航入口扁平字段与绝对 qmlPath 正确",
    )
    about_item = next(item for item in nav_items if item["itemId"] == "about")
    check(about_item["qmlPath"] == "", "无页面入口的 qmlPath 为空字符串")
    check(about_item["icon"] == "ic_about", "register_nav_item 支持 icon 兼容别名")
    check(len(widgets) == 2, "list_widgets 只包含注册成功的 2 个组件")
    big = next(item for item in widgets if item["itemId"] == "big")
    check(big["width"] == 80 and big["height"] == 1080, "组件尺寸吸附到 80x1080")
    check(
        widgets[0]["anchor"] in {"bottomLeft", "center"}
        and widgets[0]["qmlPath"].endswith("widget.qml"),
        "组件锚点 / QML 路径正确",
    )
    selftest_row = {item["id"]: item for item in manager.list_plugins()}[selftest_id]
    check(len(selftest_row["navItems"]) == 2, "list_plugins 带 navItems")
    check(len(selftest_row["widgets"]) == 2, "list_plugins 带 widgets")
    check(selftest_row["state"].get("phase") == "loaded", "list_plugins 带 state")

    print("[6/12] 事件分发")
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

    saved = read_json(plugin_settings_path)
    check(saved.get("loaded") == 1, "on_load 只执行一次")
    check(saved.get("last_space") == "超禅", "on_session_start 收到空间名")
    check(saved.get("sessions") == 1, "on_session_end 累加会话数")
    check(saved.get("minutes") == 25.0, "on_session_end 累加分钟数")
    check(saved.get("remaining") == 42, "on_tick 收到剩余秒数")
    check(saved.get("blocked") == "game.exe", "on_process_blocked 收到进程名")
    check(saved.get("last_setting") == "theme", "on_settings_changed 收到设置键")
    check(signals and signals[0][:2] == (selftest_id, "selftest"), "插件信号送达监听器")
    state_row = {item["id"]: item for item in manager.list_plugins()}[selftest_id]
    check(state_row["state"].get("phase") == "ended", "set_ui_state 状态已更新")

    print("[7/12] 停用插件（清理注册数据 + on_unload + 状态持久化）")
    check(manager.set_enabled(selftest_id, False) is True, "set_enabled(False) 返回 True")
    by_id = {item["id"]: item for item in manager.list_plugins()}
    check(by_id[selftest_id]["enabled"] is False, "列表显示已停用")
    check(by_id[selftest_id]["navItems"] == [], "停用后 navItems 清空")
    check(by_id[selftest_id]["widgets"] == [], "停用后 widgets 清空")
    check(by_id[selftest_id]["state"] == {}, "停用后 state 清空")
    check(manager.list_nav_items() == [], "停用后 list_nav_items 为空")
    check(manager.list_widgets() == [], "停用后 list_widgets 为空")
    check(read_json(plugin_settings_path).get("unloaded") is True, "停用时调用 on_unload")
    host_settings = read_json(settings.path)
    check(
        selftest_id in host_settings.get(DISABLED_PLUGINS_KEY, []),
        "停用状态写入宿主 settings 的 disabled_plugins",
    )
    manager.dispatch("session_end", {"space": "超禅", "minutes": 25.0})
    check(read_json(plugin_settings_path).get("sessions") == 1, "停用后不再收到事件")

    print("[8/12] 重新启用")
    check(manager.set_enabled(selftest_id, True) is True, "set_enabled(True) 返回 True")
    check(read_json(plugin_settings_path).get("loaded") == 2, "重新启用再次执行 on_load")
    manager.dispatch("session_end", {"space": "超禅", "minutes": 10.0})
    check(read_json(plugin_settings_path).get("sessions") == 2, "重新启用后继续累加")
    check(read_json(plugin_settings_path).get("minutes") == 35.0, "历史数据保留")
    check(len(manager.list_nav_items()) == 2, "重新启用后导航入口重新注册")
    check(len(manager.list_widgets()) == 2, "重新启用后组件重新注册")

    print("[9/12] default_enabled 插件的手动启用会持久化")
    check(
        manager.set_enabled(defaultoff_id, True) is True,
        "手动启用默认停用插件成功",
    )
    check(manager.is_loaded(defaultoff_id), "默认停用插件已加载")
    check(
        defaultoff_id not in read_json(settings.path).get(DISABLED_PLUGINS_KEY, []),
        "启用后从 disabled_plugins 移除",
    )
    check(
        defaultoff_id in read_json(settings.path).get(DEFAULTS_APPLIED_KEY, []),
        "plugin_defaults_applied 保留，避免下次启动又被关掉",
    )

    print("[10/12] 热重载与「重启」后状态保持")
    manager.reload()
    check(manager.is_loaded(selftest_id), "reload 后插件重新加载")
    check(read_json(plugin_settings_path).get("loaded") == 3, "reload 触发 on_load")
    check(read_json(plugin_settings_path).get("sessions") == 2, "reload 不丢插件设置")
    check(len(manager.list_nav_items()) == 2, "reload 后导航入口重新注册")
    check(manager.is_loaded(defaultoff_id), "reload 后默认停用插件仍处于启用状态")

    # 模拟重启：新 manager 读同一份插件目录，settings 也重新从磁盘加载
    manager2 = PluginManager(
        Settings(settings.path),
        plugin_dirs=[user_root, project_root],
        builtin_dir=missing_builtin,
        data_dir=data_dir,
    )
    restart_row = {item["id"]: item for item in manager2.list_plugins()}.get(
        defaultoff_id
    ) or {}
    check(restart_row.get("enabled") is True, "重启后默认停用插件仍保持启用")
    check(manager2.is_loaded(defaultoff_id), "重启后默认停用插件正常加载")
    check(manager2.is_loaded(selftest_id), "重启后普通插件正常加载")
    check(len(manager2.list_nav_items()) == 2, "重启后导航入口重新注册")

    print("[11/12] 查询与未知插件")
    check(manager.get_plugin(selftest_id) is not None, "get_plugin 取到插件实例")
    check(
        manager.set_enabled("com.example.missing", True) is False,
        "未知插件启用返回 False",
    )
    check(manager.get_plugin("com.example.missing") is None, "未知插件实例为 None")

    print("[12/12] validate 命令 / SDK schema / 环境变量")
    selftest_validation = validate_plugin_dir(user_root / selftest_id)
    check(selftest_validation["ok"], "validate 通过合法插件目录")
    check(selftest_validation["entry"]["exists"] is True, "validate 确认 entry 存在")
    invalid_validation = validate_plugin_dir(invalid_dir)
    check(invalid_validation["ok"] is False, "validate 拒绝非法 plugin.json")
    check(bool(invalid_validation["errors"]), "validate 输出错误原因")

    validate_root = base / "validate_plugins"
    write_plugin(
        validate_root,
        "com.example.noentry",
        "缺入口",
        DEFAULT_OFF_PLUGIN,
        entry="missing.py",
        default_enabled=False,
    )
    noentry_validation = validate_plugin_dir(validate_root / "com.example.noentry")
    check(noentry_validation["entry"]["exists"] is False, "validate 识别 entry 不存在")
    check(noentry_validation["ok"] is False, "entry 不存在时 validate 不通过")

    repo_root = Path(__file__).resolve().parents[3]
    for relative in ("templates/basic-plugin", "templates/widget-plugin"):
        template_dir = repo_root / relative
        if template_dir.is_dir():
            result = validate_plugin_dir(template_dir)
            check(result["ok"], f"validate 通过模板 {relative}")
    for builtin_id in ("com.shenqing.hello", "com.shenqing.cw2widgets"):
        builtin_path = Path(__file__).resolve().parent / "builtin" / builtin_id
        if builtin_path.is_dir():
            result = validate_plugin_dir(builtin_path)
            check(result["ok"], f"validate 通过内置插件 {builtin_id}")

    schema_path = repo_root / "sdk" / "plugin.schema.json"
    if schema_path.is_file():
        schema = read_json(schema_path)
        check(
            schema.get("required") == ["id", "name", "version", "api_version", "entry"],
            "SDK schema 必填字段与宿主一致",
        )
        check(
            schema.get("properties", {}).get("default_enabled", {}).get("type")
            == "boolean",
            "SDK schema 包含 default_enabled",
        )

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

    check(manager2.list_plugins() != [], "重载后仍有插件记录")


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
