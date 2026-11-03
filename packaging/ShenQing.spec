# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller 打包配置。

用法（不直接用，走 scripts/build_exe.ps1）：
    python -m PyInstaller --noconfirm --clean packaging/ShenQing.spec
环境变量：
    SHENQING_ONEFILE=1  打成单文件 exe；否则产出 onedir 绿色目录。
"""

import os
from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files

ROOT = Path(SPECPATH).resolve().parent  # 项目根目录（深清/）
SRC = ROOT / "src"

datas = [
    (str(SRC / "shenqing" / "qml"), "qml"),      # 界面（app.py 中按 _MEIPASS/qml 找）
    (str(ROOT / "assets"), "assets"),            # 图标
    # 内置插件：manager.default_builtin_dir() = <包目录>/plugins/builtin
    (str(SRC / "shenqing" / "plugins" / "builtin"), "shenqing/plugins/builtin"),
    # 翻译：i18n.locales_dir() = resource_root()/locales
    (str(SRC / "shenqing" / "locales"), "locales"),
]
datas += collect_data_files("RinUI")             # RinUI 的 QML 组件与字体

hiddenimports = [
    "RinUI",
    "PySide6.QtQml",
    "PySide6.QtQuick",
    "PySide6.QtQuickControls2",
    "PySide6.QtSvg",
    "PySide6.QtDBus",
    "win32api",
    "win32gui",
    "win32con",
    "win32com.shell",
    "winreg",
]

a = Analysis(
    [str(ROOT / "run.py")],
    pathex=[str(SRC)],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "pytest"],
    noarchive=False,
)
pyz = PYZ(a.pure)

_ICON = str(ROOT / "assets" / "icon.ico")
_EXE_ARGS = dict(
    name="深清",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    icon=_ICON,
    version=str(ROOT / "packaging" / "version_info.txt"),
)

if os.environ.get("SHENQING_ONEFILE") == "1":
    exe = EXE(pyz, a.scripts, a.binaries, a.datas, [], **_EXE_ARGS)
else:
    exe = EXE(pyz, a.scripts, [], exclude_binaries=True, **_EXE_ARGS)
    coll = COLLECT(
        exe,
        a.binaries,
        a.datas,
        strip=False,
        upx=False,
        name="深清",
    )
