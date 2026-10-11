import AppKit
import ServiceManagement
import PauseMicCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let coordinator = VolumeCoordinator()
    private let updater = UpdateChecker()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var status = VolumeStatus(microphone: MicrophoneSample(active: nil, processCount: 0), quietCount: 0, savedVolume: nil, failure: nil)
    private var volumeFailure: VolumeFailure?
    private var statusLabel: NSTextField?
    private var detailLabel: NSTextField?
    private var errorLabel: NSTextField?
    private var updateLabel: NSTextField?
    private var loginError = ""
    private var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["enabled": true, "automaticUpdates": true, "language": "system"])
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        coordinator.onStatus = { [weak self] status in
            guard let self else { return }
            self.status = status
            if let failure = status.failure { self.volumeFailure = failure }
            else if status.quietCount > 0 { self.volumeFailure = nil }
            self.refreshStatus()
        }
        updater.onChange = { [weak self] in self?.refreshStatus() }
        updater.automatic = UserDefaults.standard.bool(forKey: "automaticUpdates")
        coordinator.start(enabled: enabled); updater.start(); refreshStatus()
        if !UserDefaults.standard.bool(forKey: "hasOpened") {
            showSettings(); UserDefaults.standard.set(true, forKey: "hasOpened")
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        coordinator.stop { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    private var statusText: String {
        if status.microphone.active == nil { return tr("Microphone status unavailable", "暂时无法读取麦克风状态") }
        if !enabled { return tr("Automatic quiet is off", "自动静音已关闭") }
        if status.microphone.active == true {
            return tr("Microphone in use", "麦克风正在使用")
        }
        if status.quietCount > 0 { return tr("Waiting to restore volume", "等待恢复音量") }
        return tr("Ready when you speak", "随时准备，安心开口")
    }
    private var detailText: String {
        if status.quietCount > 0 {
            let volume = Int((status.savedVolume ?? 0) * 100)
            return tr("Output volume is 0 · saved volume \(volume)%", "输出音量已设为 0 · 原音量 \(volume)%")
        }
        return tr("System output · restores after the microphone is idle for 1.5 seconds", "系统默认输出 · 麦克风空闲 1.5 秒后恢复原音量")
    }
    private func refreshStatus() {
        let symbol = !enabled ? "mic.slash" : (status.microphone.active == true ? "mic.fill" : "mic")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: statusText)
        image?.isTemplate = true; statusItem?.button?.image = image
        statusItem?.button?.toolTip = "PauseMic · \(statusText)"
        statusLabel?.stringValue = statusText; detailLabel?.stringValue = detailText
        updateLabel?.stringValue = updater.message
        errorLabel?.stringValue = volumeFailure.map { error in
            switch error {
            case .unsupported:
                return tr("This output has no software volume control (for example, some HDMI or USB devices). Choose an output with adjustable system volume.", "当前输出设备不支持软件音量控制（例如部分 HDMI 或 USB 设备），请选择可调整系统音量的输出。")
            case .journal:
                return tr("Could not save volume recovery data. No new automatic muting will occur until this is resolved.", "无法保存音量恢复记录。解决之前不会执行新的自动静音。")
            default:
                return tr("Could not read or change output volume. Check the output device and toggle automatic quiet to retry.", "无法读取或调整输出音量。请检查输出设备，再关闭并开启自动静音以重试。")
            }
        } ?? loginError

    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let headline = NSMenuItem(title: statusText, action: nil, keyEquivalent: ""); headline.isEnabled = false; menu.addItem(headline)
        if status.quietCount > 0 { menu.addItem(item(tr("Keep volume at zero", "保持音量为 0，取消恢复"), #selector(keepQuiet))) }
        menu.addItem(.separator())
        let toggle = item(tr("Automatic quiet", "自动静音"), #selector(toggleEnabled)); toggle.state = enabled ? .on : .off; menu.addItem(toggle)
        menu.addItem(item(tr("Settings…", "设置…"), #selector(showSettings), key: ","))
        if case .available(let version, _) = updater.state {
            menu.addItem(item(tr("Download \(version)…", "下载 \(version)…"), #selector(openRelease)))
        } else { menu.addItem(item(tr("Check for Updates…", "检查更新…"), #selector(checkUpdates))) }
        menu.addItem(.separator())
        menu.addItem(item("hecara Factory ↗", #selector(openFactory)))
        menu.addItem(item(tr("GitHub · MIT License ↗", "GitHub · MIT 开源协议 ↗"), #selector(openRepository)))
        menu.addItem(.separator())
        menu.addItem(item(tr("Quit PauseMic", "退出 PauseMic"), #selector(quit), key: "q"))
    }
    private func installMainMenu() {
        let main = NSMenu()
        let applicationMenu = NSMenu(title: "PauseMic")
        let root = NSMenuItem(); root.submenu = applicationMenu; main.addItem(root)
        applicationMenu.addItem(item(tr("Settings…", "设置…"), #selector(showSettings), key: ","))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(item(tr("Quit PauseMic", "退出 PauseMic"), #selector(quit), key: "q"))
        let windowMenu = NSMenu(title: tr("Window", "窗口"))
        let windowRoot = NSMenuItem(); windowRoot.submenu = windowMenu; main.addItem(windowRoot)
        windowMenu.addItem(NSMenuItem(title: tr("Close Window", "关闭窗口"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        NSApp.mainMenu = main
    }
    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    @objc private func toggleEnabled() {
        enabled.toggle(); volumeFailure = nil
        coordinator.setEnabled(enabled); refreshStatus()
        if window?.isVisible == true { rebuildWindow() }
    }
    @objc private func enabledChanged(_ sender: NSButton) { if (sender.state == .on) != enabled { toggleEnabled() } }
    @objc private func keepQuiet() { coordinator.keepQuiet() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openFactory() { NSWorkspace.shared.open(URL(string: "https://hecara.com")!) }
    @objc private func openRepository() { NSWorkspace.shared.open(URL(string: "https://github.com/hecara/PauseMic")!) }
    @objc private func openRelease() { updater.openRelease() }
    @objc private func checkUpdates() { updater.check(); showSettings() }
    @objc private func languageChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(AppLanguage.allCases[sender.indexOfSelectedItem].rawValue, forKey: "language")
        installMainMenu(); rebuildWindow(); refreshStatus()
    }
    @objc private func automaticUpdatesChanged(_ sender: NSButton) {
        updater.automatic = sender.state == .on
        UserDefaults.standard.set(updater.automatic, forKey: "automaticUpdates")
        if updater.automatic { updater.check() }
    }
    @objc private func loginChanged(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = SMAppService.mainApp.status == .requiresApproval ?
                tr("Allow PauseMic in System Settings → General → Login Items.", "请在系统设置 → 通用 → 登录项中允许 PauseMic。") : ""
        } catch {
            loginError = tr("Could not change login item. Install PauseMic in Applications and try again.", "无法更改登录项。请将 PauseMic 放入应用程序文件夹后重试。")
        }
        sender.state = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval ? .on : .off
        refreshStatus()
    }
    @objc private func showSettings() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.delegate = self
            window.center(); self.window = window; rebuildWindow()
        }
        refreshStatus(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func label(_ text: String, size: CGFloat = 13, color: NSColor = .labelColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded; return button
    }
    private func checkbox(_ title: String, on: Bool, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action); button.state = on ? .on : .off; return button
    }
    private func rebuildWindow() {
        guard let window else { return }
        window.title = tr("PauseMic Settings", "PauseMic 设置")
        let content = NSView(); window.contentView = content
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
        ])
        func add(_ view: NSView) {
            stack.addArrangedSubview(view)
            if view is NSTextField { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        }
        add(label("PauseMic", size: 30, weight: .bold))
        add(label(tr("A little quiet, right when you need it.", "开口那一刻，让声音安静下来。"), size: 15, color: .secondaryLabelColor))
        let stateLabel = label(statusText, size: 19, weight: .semibold); add(stateLabel); statusLabel = stateLabel
        let detail = label(detailText, color: .secondaryLabelColor); add(detail); detailLabel = detail
        add(checkbox(tr("Set system output volume to 0 while the microphone is in use", "麦克风使用时，将系统输出音量设为 0"), on: enabled, action: #selector(enabledChanged)))
        add(checkbox(tr("Launch at login", "登录时启动"), on: SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval, action: #selector(loginChanged)))
        add(checkbox(tr("Check GitHub Releases every hour", "每小时检查 GitHub Release 更新"), on: updater.automatic, action: #selector(automaticUpdatesChanged)))
        let languages = NSPopUpButton(); languages.addItems(withTitles: [tr("System language", "跟随系统"), "English", "简体中文"])
        languages.selectItem(at: AppLanguage.allCases.firstIndex(of: AppLanguage.current)!)
        languages.target = self; languages.action = #selector(languageChanged)
        let row = NSStackView(views: [label(tr("Language", "语言")), languages]); row.spacing = 16; add(row)
        add(button(tr("Keep volume at 0 · cancel restoration", "保持音量为 0 · 取消自动恢复"), action: #selector(keepQuiet)))
        let errors = label("", size: 12, color: .systemOrange); add(errors); errorLabel = errors
        add(label(tr("Media keeps playing. PauseMic saves your output volume, sets it to 0, then restores it. A detected manual volume or mute change cancels restoration for that output.",
                     "媒体继续播放。PauseMic 保存输出音量、设为 0，再恢复原音量。检测到手动调节音量或静音后，会放弃恢复该设备的音量。"), size: 12, color: .secondaryLabelColor))
        add(label(tr("No recording or audio uploads. Closing this window keeps PauseMic in the menu bar. Disabling or quitting restores volume still owned by PauseMic.",
                     "不录音，不上传音频。关闭窗口后继续在菜单栏运行。关闭自动静音或退出时，会恢复仍由 PauseMic 管理的音量。"), size: 12, color: .secondaryLabelColor))
        let update = label(updater.message, size: 12, color: .secondaryLabelColor); add(update); updateLabel = update
        let updateRow = NSStackView(views: [button(tr("Check now", "立即检查"), action: #selector(checkUpdates)), button(tr("Releases ↗", "下载更新 ↗"), action: #selector(openRelease))]); updateRow.spacing = 12; add(updateRow)
        add(label(tr("A hecara Factory project · Practical, reliable little tools.", "hecara Factory 工厂计划 · 提供实用可靠的小工具。"), size: 12, color: .secondaryLabelColor))
        let footer = NSStackView(views: [button("hecara.com ↗", action: #selector(openFactory)), button("GitHub · MIT ↗", action: #selector(openRepository)), label("v\(updater.version)", size: 11, color: .tertiaryLabelColor)])
        footer.spacing = 12; add(footer)
        refreshStatus()
    }
}
