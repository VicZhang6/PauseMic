## PauseMic 0.1.0

首个原生 macOS 版本 / First native macOS release.

- 麦克风使用时保存系统输出音量并设为 0，空闲 1.5 秒后恢复。媒体继续播放。
- Save system output volume and set it to 0 during microphone use; restore after 1.5 seconds of inactivity. Playback keeps progressing.
- 菜单栏常驻、关闭窗口后继续运行、可选登录时启动、中文与英文。
- Menu bar app, persistent operation after closing settings, optional login item, English and Simplified Chinese.
- 按设备管理原音量，手动调整优先，异常退出后的本地恢复记录。
- Per-device volume ownership, manual changes take precedence, local crash recovery journal.
- 每小时检测 GitHub Release；支持手动检查，打开官方更新下载页面。
- Hourly GitHub Release checks with manual checks and links to the official download page.

Requires macOS 14.2+. Universal Apple Silicon / Intel app. Some digital/HDMI/USB outputs have no software volume control and are unsupported. Audio explicitly routed to a different output is unaffected. Hardware compatibility and Intel runtime coverage are described in docs/VALIDATION.md.

The initial published ZIP is Developer ID signed, not Apple notarized. Builds produced by GitHub Actions are ad-hoc signed unless the signing pipeline is configured separately. SHA256SUMS.txt accompanies each ZIP.

A [hecara Factory](https://hecara.com) project: practical, reliable little tools. Open source under the MIT License.
