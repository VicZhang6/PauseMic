import AppKit
import SwiftUI
import ServiceManagement
import PauseMicCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let coordinator = VolumeCoordinator()
    private let updater = UpdateChecker()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var status = VolumeStatus(microphone: MicrophoneSample(active: nil, processCount: 0), quietCount: 0, savedVolume: nil, failure: nil)
    private var volumeFailure: VolumeFailure?
    private let model = SettingsModel()
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
    /// Template glyph: sound bars settling into a pause. Dimmed when automatic quiet is off; a dot marks microphone use.
    private func menuBarImage(dimmed: Bool, inUse: Bool) -> NSImage {
        let bars: [(x: CGFloat, w: CGFloat, y: CGFloat, h: CGFloat)] = [
            (270, 115, 345, 590), (410, 110, 437, 416), (545, 107, 527, 246),
            (676, 89, 587, 130), (803, 77, 515, 274), (908, 77, 515, 274)]
        let scale: CGFloat = 15 / 590
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.withAlphaComponent(dimmed ? 0.35 : 1).setFill()
            for bar in bars {
                let rect = NSRect(x: 1.5 + (bar.x - 270) * scale, y: 1.5 + (590 - (bar.y - 345) - bar.h) * scale,
                                  width: bar.w * scale, height: bar.h * scale)
                NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2).fill()
            }
            if inUse { NSBezierPath(ovalIn: NSRect(x: 17.5, y: 12.5, width: 4.5, height: 4.5)).fill() }
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = statusText
        return image
    }
    private var statusKind: StatusKind {
        if status.microphone.active == nil { return .unavailable }
        if !enabled { return .off }
        if status.microphone.active == true { return .inUse }
        return status.quietCount > 0 ? .waiting : .ready
    }
    private var detailText: String {
        if status.quietCount > 0 {
            let volume = Int((status.savedVolume ?? 0) * 100)
            return tr("Output volume is 0 · saved volume \(volume)%", "输出音量已设为 0 · 原音量 \(volume)%")
        }
        return tr("System output · restores after the microphone is idle for 1.5 seconds", "系统默认输出 · 麦克风空闲 1.5 秒后恢复原音量")
    }
    private func refreshStatus() {
        statusItem?.button?.image = menuBarImage(dimmed: !enabled, inUse: enabled && status.microphone.active == true)
        statusItem?.button?.toolTip = "PauseMic · \(statusText)"
        model.title = statusText; model.detail = detailText
        model.kind = statusKind; model.enabled = enabled; model.canKeepQuiet = status.quietCount > 0
        model.updateMessage = updater.message; model.autoUpdate = updater.automatic; model.language = AppLanguage.current
        model.loginOn = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        if case .checking = updater.state { model.checking = true } else { model.checking = false }
        if case .available = updater.state { model.updateAvailable = true } else { model.updateAvailable = false }
        model.error = volumeFailure.map { error in
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
    }
    @objc private func keepQuiet() { coordinator.keepQuiet() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openFactory() { NSWorkspace.shared.open(URL(string: "https://hecara.com")!) }
    @objc private func openRepository() { NSWorkspace.shared.open(URL(string: "https://github.com/hecara/PauseMic")!) }
    @objc private func openRelease() { updater.openRelease() }
    @objc private func checkUpdates() { updater.check(); showSettings() }
    private func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: "language")
        installMainMenu(); window?.title = tr("PauseMic Settings", "PauseMic 设置"); refreshStatus()
    }
    private func setAutomaticUpdates(_ on: Bool) {
        updater.automatic = on
        UserDefaults.standard.set(updater.automatic, forKey: "automaticUpdates")
        if updater.automatic { updater.check() }
        refreshStatus()
    }
    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = SMAppService.mainApp.status == .requiresApproval ?
                tr("Allow PauseMic in System Settings → General → Login Items.", "请在系统设置 → 通用 → 登录项中允许 PauseMic。") : ""
        } catch {
            loginError = tr("Could not change login item. Install PauseMic in Applications and try again.", "无法更改登录项。请将 PauseMic 放入应用程序文件夹后重试。")
        }
        refreshStatus()
    }
    @objc private func showSettings() {
        if window == nil {
            model.version = updater.version
            model.onEnabled = { [weak self] want in if let self, want != self.enabled { self.toggleEnabled() } }
            model.onLogin = { [weak self] in self?.setLogin($0) }
            model.onAutoUpdate = { [weak self] in self?.setAutomaticUpdates($0) }
            model.onLanguage = { [weak self] in self?.setLanguage($0) }
            model.onKeepQuiet = { [weak self] in self?.keepQuiet() }
            model.onCheck = { [weak self] in self?.updater.check() }
            model.onRelease = { [weak self] in self?.openRelease() }
            model.onFactory = { [weak self] in self?.openFactory() }
            model.onRepository = { [weak self] in self?.openRepository() }
            let controller = NSHostingController(rootView: SettingsView(model: model))
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.title = tr("PauseMic Settings", "PauseMic 设置")
            window.isReleasedWhenClosed = false; window.delegate = self
            window.center(); self.window = window
        }
        refreshStatus(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
