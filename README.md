# PauseMic

**开口那一刻，让声音安静下来。 / A little quiet, right when you need it.**

PauseMic 是原生 macOS 菜单栏小工具。在 Codex、Claude Code 等工具中使用麦克风语音输入时，它会保存系统输出音量、将音量设为 **0**，并在麦克风空闲后恢复原音量。音乐、播客和视频继续播放。

A native macOS menu bar utility: save your system output volume, set it to **0** while the microphone is in use, and restore it afterward. Music, podcasts and videos keep playing.

[下载 / Download](https://github.com/hecara/PauseMic/releases) · [English documentation](docs/README.en.md) · [hecara Factory](https://hecara.com) · [MIT](LICENSE)

## 功能

- Swift、AppKit、Core Audio 原生实现，支持 macOS **14.2+**，提供 Apple Silicon / Intel 通用应用。
- 检测任意进程的音频输入使用状态，不录音，不申请麦克风或播放器自动化权限。
- 麦克风空闲 **1.5 秒**后恢复，短暂间隙或其他进程仍在使用麦克风时保持音量为 0。
- 菜单栏常驻；关闭设置窗口继续运行；支持登录时启动。
- 中文、英文，默认跟随系统语言，可即时切换。
- 默认每小时检查一次 GitHub Release，并在启动、睡眠唤醒后按需要检查；支持手动检查。更新提示打开 Release 下载页面。
- 按设备分别保存原音量，支持默认输出切换、手动调整优先、异常退出后的恢复记录。
- 只运行一个实例；关闭自动静音或正常退出时恢复仍由 PauseMic 管理的音量。

## 安装与使用

1. 在 [Releases](https://github.com/hecara/PauseMic/releases) 下载 `PauseMic-*-macOS-universal.zip`，解压后将 `PauseMic.app` 拖到“应用程序”。
2. 打开应用，在菜单栏麦克风图标中查看状态和设置。首次启动显示设置窗口。
3. 根据需要开启“登录时启动”。macOS 如要求登录项审批，请在“系统设置 → 通用 → 登录项”中允许。
4. 使用语音输入。结束后，系统输出音量会恢复为原值。

首个下载包使用 Developer ID 签名，但尚未经过 Apple 公证；Gatekeeper 可能要求在“系统设置 → 隐私与安全性”中确认打开。GitHub Actions 默认构建使用 ad-hoc 签名。不要禁用系统安全保护；签名、公证构建方法见下文。

## 恢复规则与设备范围

控制的是 macOS **默认声音输出设备**的软件音量；显式路由到其他设备的应用音频不在控制范围内。期间切换默认输出时，新输出也会设为 0，并分别保存原音量。原本音量为 0 或已通过硬件静音的设备不会被修改。

检测到用户手动改音量或静音状态后，放弃该设备的自动恢复，并且本次麦克风使用期间不会再次将其设为 0。可以使用“保持音量为 0 · 取消自动恢复”明确保留静音。重复设置 0、或短于约 300 毫秒的变化可能无法识别。

部分 HDMI、数字音频、USB 或虚拟输出没有可写软件音量，PauseMic 会显示不支持的提示。Core Audio 无法读取麦克风状态时不执行自动静音或恢复。设备断开时保留恢复记录，重新连接并在麦克风空闲后再恢复。强制结束应用不能立即恢复音量；再次启动后才会根据记录恢复，用户也可以自行调节系统音量。

## 隐私

不录制、不保存、不上传音频，不收集遥测。音量恢复记录仅在本机 `~/Library/Application Support/com.hecara.PauseMic/volume-recovery.json` 保存设备标识及音量状态。唯一网络请求为 GitHub Release 更新检查；可在设置中关闭自动检查。

## 开发

需要 macOS 14.2+、Xcode 15.2+ / Swift 5.9+。

```sh
scripts/install-hooks.sh
swift test
scripts/build-app.sh
open dist/PauseMic.app
```

本机音量测试会短暂将实际输出音量设为 0，再恢复：

```sh
PAUSEMIC_HARDWARE_TEST=1 swift test --filter NativeTests/testRealVolumeRoundTrip
```

使用已有 Developer ID 证书和已配置的 notarytool keychain profile：

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-existing-profile' scripts/build-app.sh
```

无签名参数时为 ad-hoc 签名。脚本打包通用 `.app`、ZIP 和 SHA-256 校验文件。Release tag 必须与 `Resources/Info.plist` 的版本一致。自动测试、构建和 tag 发布的 GitHub Actions 模板保存在 `docs/workflow-templates/`。当前发布凭据缺少 `workflow` 权限，尚未启用云端工作流；由本机完成验证和签名发布。具备相应权限后，可将模板复制到 `.github/workflows/` 启用。已有 Release 不会被该模板替换。

[实施计划](docs/PLAN.md) · [验证记录](docs/VALIDATION.md) · [发布说明](docs/RELEASE.md)

## 私钥上传保护

签名使用本机钥匙串，不导出私钥；公证使用已有的 notarytool 钥匙串配置。仓库排除 `.p12`、`.pfx`、`.p8`、`.key`、`.pem` 以及本地 `.env` 凭据文件。

运行 `scripts/install-hooks.sh` 安装本仓库的提交和推送检查：提交检查暂存区的实际内容，推送检查本地所有 Git 历史，防止“后来删除了私钥，但旧提交仍上传”。打包脚本在公证上传和生成 Release 包前检查应用包与 ZIP 内容；工作流模板也会在上传前检查明确指定的文件。

```sh
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/check-sensitive.py --history
python3 scripts/check-sensitive.py --artifacts dist/PauseMic.app
```

检查发现敏感文件名、常见 PEM 私钥标记、未扫描的嵌套 ZIP 或超过扫描限制的文件时会停止，不打印密钥内容。公开证书 `.cer` 和应用中的公钥签名信息允许存在。新克隆需要安装钩子；本地钩子可被绕过，任意改名的二进制私钥、其他形式的凭据或手工上传不保证被识别，因此这些保护不能替代钥匙串和凭据管理。

## hecara Factory

PauseMic 是 [hecara Factory 工厂计划](https://hecara.com) 的开源项目，旨在提供**实用可靠的小工具**。源代码使用 [MIT 协议](LICENSE)，欢迎反馈设备兼容性、提交 Issue 和 Pull Request。
