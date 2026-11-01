"""国际化工具：提取 / 编译 / 检查翻译（Qt .ts <-> .qm）。

用法：
    python scripts/i18n.py extract     # pyside6-lupdate：扫描 py+qml，更新所有 .ts
    python scripts/i18n.py compile     # pyside6-lrelease：.ts -> .qm
    python scripts/i18n.py check       # 检查未翻译条数（CI / 本地都用）

目录约定（与 CW2 一致）：
    源文件：src/shenqing/**/*.py、**/*.qml
    翻译：src/shenqing/locales/<locale>.ts / .qm
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "shenqing"
LOCALES = SRC / "locales"
SOURCE_SUFFIXES = {".py", ".qml"}


def _tool(name: str) -> str:
    """优先用当前解释器所在 Scripts 下的 pyside6-*，找不到就交给 PATH。"""
    candidate = Path(sys.executable).parent / "Scripts" / f"{name}.exe"
    if candidate.exists():
        return str(candidate)
    found = shutil.which(name)
    if found:
        return found
    raise SystemExit(f"找不到 {name}（pip install pyside6 会一起安装）")


def source_files() -> list[str]:
    files: list[str] = []
    for path in sorted(SRC.rglob("*")):
        if path.suffix in SOURCE_SUFFIXES and "__pycache__" not in path.parts:
            files.append(str(path))
    return files


def ts_files() -> list[Path]:
    return sorted(LOCALES.glob("*.ts"))


def cmd_extract() -> int:
    files = source_files()
    targets = ts_files()
    if not targets:
        print(f"没有找到 .ts 文件，请先在 {LOCALES} 放一个 <locale>.ts")
        return 1
    lupdate = _tool("pyside6-lupdate")
    args = [lupdate, *files, "-ts", *[str(t) for t in targets]]
    print(f"[extract] {len(files)} 个源文件 -> {len(targets)} 个 .ts")
    result = subprocess.run(args, cwd=ROOT)
    return int(result.returncode)


def cmd_compile() -> int:
    lrelease = _tool("pyside6-lrelease")
    targets = ts_files()
    if not targets:
        print("没有 .ts 可编译")
        return 1
    failed = 0
    for ts in targets:
        qm = ts.with_suffix(".qm")
        print(f"[compile] {ts.name} -> {qm.name}")
        code = subprocess.run([lrelease, str(ts), "-qm", str(qm)], cwd=ROOT).returncode
        failed += int(code != 0)
    return 1 if failed else 0


def _unfinished(ts: Path) -> tuple[int, int]:
    try:
        tree = ET.parse(ts)
    except ET.ParseError as exc:
        print(f"[check] {ts.name} 解析失败：{exc}")
        return (0, 0)
    total = unfinished = 0
    for message in tree.getroot().iter("message"):
        total += 1
        translation = message.find("translation")
        if translation is None:
            unfinished += 1
            continue
        if translation.get("type") in ("unfinished", "obsolete"):
            unfinished += 1
        elif not (translation.text or "").strip():
            unfinished += 1
    return total, unfinished


def cmd_check() -> int:
    if not ts_files():
        print("没有 .ts")
        return 1
    bad = 0
    for ts in ts_files():
        total, unfinished = _unfinished(ts)
        mark = "OK" if unfinished == 0 else "TODO"
        print(f"[check] {ts.name}: {total - unfinished}/{total} 已翻译（{mark}）")
        bad += int(unfinished > 0)
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else "check"
    if command == "extract":
        return cmd_extract()
    if command == "compile":
        return cmd_compile()
    if command == "check":
        return cmd_check()
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
