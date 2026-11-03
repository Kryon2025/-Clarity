"""GitHub 自动更新测试：版本比较、资产选择、检查/下载分支、bridge 状态流转。"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock
from urllib.error import URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ["SHENQING_NO_SCAN"] = "1"
os.environ["SHENQING_NO_KEEPER"] = "1"

from PySide6.QtWidgets import QApplication  # noqa: E402

_APP = QApplication.instance() or QApplication([])

from shenqing.services import updater  # noqa: E402
from shenqing.bridge.app_bridge import AppBridge  # noqa: E402


def _release(version: str = "0.6.1", assets: list[dict] | None = None) -> dict:
    return {
        "tag_name": f"v{version}",
        "body": "本次更新说明\n- 修复问题",
        "html_url": "https://github.com/Kryon2025/Clarity/releases/tag/" + version,
        "assets": assets
        if assets is not None
        else [
            {"name": "ShenQing-0.6.1-portable.exe", "browser_download_url": "https://x/p.exe", "size": 10},
            {"name": "ShenQing-0.6.1-Setup.exe", "browser_download_url": "https://x/s.exe", "size": 20},
            {"name": "source.zip", "browser_download_url": "https://x/s.zip", "size": 30},
        ],
    }


class VersionTest(unittest.TestCase):
    def test_version_tuple(self) -> None:
        self.assertEqual(updater.version_tuple("0.6.0"), (0, 6, 0))
        self.assertEqual(updater.version_tuple("v1.2.3"), (1, 2, 3))
        self.assertEqual(updater.version_tuple("1.2"), (1, 2))
        self.assertEqual(updater.version_tuple("bad"), (0,))

    def test_is_newer(self) -> None:
        # 0.5.9 < 0.6.0；0.6.0 == 0.6.0；0.6.10 > 0.6.9
        self.assertTrue(updater.is_newer("0.6.0", "0.5.9"))
        self.assertFalse(updater.is_newer("0.6.0", "0.6.0"))
        self.assertTrue(updater.is_newer("0.6.10", "0.6.9"))
        self.assertTrue(updater.is_newer("0.7", "0.6.99"))
        self.assertFalse(updater.is_newer("0.6", "0.6.0"))


class AssetTest(unittest.TestCase):
    def test_prefers_setup_exe(self) -> None:
        asset = updater.select_asset(_release()["assets"])
        self.assertIsNotNone(asset)
        self.assertEqual(asset["name"], "ShenQing-0.6.1-Setup.exe")

    def test_falls_back_to_first_exe(self) -> None:
        asset = updater.select_asset(
            [
                {"name": "readme.txt", "browser_download_url": "https://x/r.txt"},
                {"name": "ShenQing-portable.exe", "browser_download_url": "https://x/p.exe"},
                {"name": "another.exe", "browser_download_url": "https://x/a.exe"},
            ]
        )
        self.assertEqual(asset["name"], "ShenQing-portable.exe")

    def test_no_installer(self) -> None:
        self.assertIsNone(updater.select_asset([{"name": "source.zip"}]))
        self.assertIsNone(updater.select_asset(None))


class CheckLatestTest(unittest.TestCase):
    def test_has_update(self) -> None:
        with mock.patch.object(updater, "_fetch_release", return_value=_release("0.6.1")):
            info = updater.check_latest("0.6.0")
        self.assertIsNotNone(info)
        self.assertEqual(info["version"], "0.6.1")
        self.assertEqual(info["tag"], "v0.6.1")
        self.assertIn("本次更新说明", info["notes"])
        self.assertEqual(info["assetName"], "ShenQing-0.6.1-Setup.exe")
        self.assertEqual(info["assetUrl"], "https://x/s.exe")
        self.assertEqual(info["assetSize"], 20)
        self.assertTrue(info["pageUrl"].startswith("https://github.com/"))

    def test_same_or_older_version(self) -> None:
        for version in ("0.6.0", "0.5.9"):
            with mock.patch.object(updater, "_fetch_release", return_value=_release(version)):
                self.assertIsNone(updater.check_latest("0.6.0"))

    def test_network_error(self) -> None:
        with mock.patch.object(updater, "_fetch_release", side_effect=URLError("boom")):
            self.assertIsNone(updater.check_latest("0.6.0"))


class DownloadTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)
        self.source = self.dir / "payload.bin"
        self.source.write_bytes(b"x" * 200_000)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_download_with_progress(self) -> None:
        progress: list[int] = []
        dest = self.dir / "out" / "setup.exe"
        ok = updater.download(
            self.source.as_uri(), dest, on_progress=progress.append
        )
        self.assertTrue(ok)
        self.assertTrue(dest.exists())
        self.assertEqual(dest.stat().st_size, 200_000)
        self.assertIn(100, progress)
        self.assertEqual(progress, sorted(progress))

    def test_cancel(self) -> None:
        dest = self.dir / "cancelled.exe"
        token = updater.CancelToken()
        token.cancel()
        ok = updater.download(self.source.as_uri(), dest, cancel=token)
        self.assertFalse(ok)
        self.assertFalse(dest.exists())
        self.assertFalse(dest.with_name(dest.name + ".part").exists())

    def test_bad_url(self) -> None:
        self.assertFalse(updater.download("", self.dir / "x.exe"))


class UpdateBridgeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        os.environ["SHENQING_DATA_DIR"] = self._tmp.name
        self.bridge = AppBridge()
        self.toasts: list[str] = []
        self.states: list[str] = []
        self.bridge.toast.connect(self.toasts.append)
        self.bridge.stateChanged.connect(lambda: self.states.append(self.bridge.updateState))

    def tearDown(self) -> None:
        try:
            self.bridge.deleteLater()
        except RuntimeError:
            pass
        self._tmp.cleanup()
        os.environ.pop("SHENQING_DATA_DIR", None)

    def _wait_state(self, target: str, timeout: float = 5.0) -> bool:
        deadline = time.time() + timeout
        while time.time() < deadline:
            QApplication.processEvents()
            if self.bridge.updateState == target:
                return True
            time.sleep(0.01)
        QApplication.processEvents()
        return self.bridge.updateState == target

    def _fake_download(self, url, dest, on_progress=None, cancel=None) -> bool:  # noqa: ANN001
        dest = Path(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"fake-installer")
        if on_progress:
            on_progress(30)
            on_progress(70)
            on_progress(100)
        return True

    def test_flow_available_download_ready(self) -> None:
        bridge = self.bridge
        self.assertEqual(bridge.updateState, "idle")
        self.assertFalse(bridge.updateAvailable)
        info = {
            "version": "0.6.1",
            "tag": "v0.6.1",
            "notes": "notes",
            "pageUrl": "https://github.com/x",
            "assetName": "ShenQing-Setup.exe",
            "assetUrl": "https://x/s.exe",
            "assetSize": 20,
        }
        with mock.patch.object(updater, "check_latest", return_value=info):
            bridge.checkUpdate()
            self.assertEqual(bridge.updateState, "checking")
            self.assertTrue(self._wait_state("available"))
        self.assertEqual(bridge.updateLatestVersion, "0.6.1")
        self.assertTrue(bridge.updateAvailable)
        self.assertEqual(bridge.updateNotes, "notes")
        self.assertTrue(any("发现新版本" in t for t in self.toasts))

        with mock.patch.object(updater, "download", side_effect=self._fake_download):
            bridge.downloadUpdate()
            self.assertEqual(bridge.updateState, "downloading")
            self.assertTrue(self._wait_state("ready"))
        self.assertEqual(bridge.updateProgress, 100)
        self.assertTrue(any("下载完成" in t for t in self.toasts))
        self.assertIn("downloading", self.states)
        self.assertIn("ready", self.states)

    def test_flow_check_error_and_idle(self) -> None:
        bridge = self.bridge
        with mock.patch.object(updater, "check_latest", side_effect=RuntimeError("boom")):
            bridge.checkUpdate()
            self.assertTrue(self._wait_state("error"))
        self.assertTrue(bridge.updateError)
        self.assertFalse(bridge.updateAvailable)

        with mock.patch.object(updater, "check_latest", return_value=None):
            bridge.checkUpdate()
            self.assertTrue(self._wait_state("idle"))
        self.assertFalse(bridge.updateAvailable)

    def test_download_failure(self) -> None:
        bridge = self.bridge
        with mock.patch.object(updater, "check_latest", return_value={
            "version": "0.6.1",
            "tag": "v0.6.1",
            "notes": "",
            "pageUrl": "",
            "assetName": "ShenQing-Setup.exe",
            "assetUrl": "https://x/s.exe",
            "assetSize": 1,
        }):
            bridge.checkUpdate()
            self.assertTrue(self._wait_state("available"))
        with mock.patch.object(updater, "download", return_value=False):
            bridge.downloadUpdate()
            self.assertTrue(self._wait_state("error"))
        self.assertTrue(bridge.updateError)

    def test_install_requires_ready(self) -> None:
        self.bridge.installUpdate()
        self.assertTrue(any("尚未下载" in t for t in self.toasts))

    def test_auto_update_setting(self) -> None:
        self.assertTrue(self.bridge.autoUpdate)
        self.bridge.setAutoUpdate(False)
        self.assertFalse(self.bridge.autoUpdate)


if __name__ == "__main__":
    unittest.main()
