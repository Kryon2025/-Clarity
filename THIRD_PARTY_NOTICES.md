# 第三方组件与许可证 / Third-party Notices

深清（Clarity）使用以下第三方开源组件。它们按各自的许可证授权，详见各项目主页。
ShenQing (Clarity) uses the following third-party open-source components under their own licenses.

| 组件 / Component | 版本 / Version | 许可证 / License | 项目主页 / Homepage |
| --- | --- | --- | --- |
| Qt (Qt Core / Qml / Quick / QuickControls2 / Svg / DBus) | 6.11 | LGPLv3 | https://www.qt.io/ |
| PySide6 (Qt for Python) | 6.11 | LGPLv3 (Python 绑定) | https://doc.qt.io/qtforpython/ |
| Shiboken6 | 6.11 | LGPLv3 | https://doc.qt.io/qtforpython/ |
| RinUI | 0.4.4 | MIT | https://github.com/RinLit-233-shiroko/RinUI |
| pywin32 | 306+ | PSF-2.0 | https://github.com/mhammond/pywin32 |
| pycaw | 2024+ | MIT | https://github.com/AndreMiras/pycaw |
| comtypes | 1.4+ | MIT | https://github.com/enthought/comtypes |
| PyInstaller（打包工具，产物中不含其源码） | 6.x | GPL-2.0-or-later with bootloader exception | https://pyinstaller.org/ |

## LGPLv3 说明

Qt / PySide6 / Shiboken6 以 LGPLv3 授权，本软件以动态链接方式使用它们。
如需替换这些库版本，可自行替换安装目录中对应的 Qt DLL 与 Python 模块。

Qt and PySide6/Shiboken6 are used under LGPLv3 via dynamic linking. You may replace
the bundled Qt libraries with your own builds, as permitted by the LGPL.

## MIT 说明

RinUI、pycaw、comtypes 以 MIT 授权，保留其原始版权与许可声明。

## 许可证原文

- LGPLv3: https://www.gnu.org/licenses/lgpl-3.0.txt
- MIT: https://opensource.org/license/mit
- PSF-2.0: https://opensource.org/license/psf-2-0
