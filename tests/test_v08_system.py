"""v0.8 系统控制：音量（mock pycaw 接口）与关机/重启命令。"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from shenqing.services import system_control  # noqa: E402


class _FakeVolume:
    def __init__(self) -> None:
        self.scalar = 0.42
        self.last = None

    def GetMasterVolumeLevelScalar(self):  # noqa: ANN201
        return self.scalar

    def SetMasterVolumeLevelScalar(self, value, context):  # noqa: ANN001,ANN201
        self.last = value
        self.scalar = value
        return 0


class SystemControlTest(unittest.TestCase):
    def test_get_volume(self) -> None:
        fake = _FakeVolume()
        with mock.patch.object(system_control, "_volume_interface", return_value=fake):
            self.assertEqual(system_control.get_volume(), 42)

    def test_get_volume_failure(self) -> None:
        with mock.patch.object(
            system_control, "_volume_interface", side_effect=OSError("no device")
        ):
            self.assertEqual(system_control.get_volume(), -1)

    def test_set_volume_clamps(self) -> None:
        fake = _FakeVolume()
        with mock.patch.object(system_control, "_volume_interface", return_value=fake):
            self.assertTrue(system_control.set_volume(150))
            self.assertAlmostEqual(fake.last, 1.0)
            self.assertTrue(system_control.set_volume(-5))
            self.assertAlmostEqual(fake.last, 0.0)
            self.assertFalse(system_control.set_volume("bad"))

    def test_power_action(self) -> None:
        with mock.patch.object(system_control.subprocess, "run") as run:
            self.assertTrue(system_control.power_action("shutdown"))
            args = run.call_args[0][0]
            self.assertEqual(args[:3], ["shutdown", "/s", "/t"])
            self.assertTrue(system_control.power_action("restart"))
            self.assertEqual(run.call_args[0][0][1], "/r")
            self.assertFalse(system_control.power_action("sleep"))

    def test_power_action_failure(self) -> None:
        with mock.patch.object(
            system_control.subprocess, "run", side_effect=OSError("denied")
        ):
            self.assertFalse(system_control.power_action("shutdown"))


if __name__ == "__main__":
    unittest.main()
