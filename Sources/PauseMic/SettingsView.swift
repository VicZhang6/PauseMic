import SwiftUI
import AppKit

enum StatusKind {
    case unavailable, off, inUse, waiting, ready
    var symbol: String {
        switch self {
        case .unavailable: return "exclamationmark.triangle.fill"
        case .off: return "mic.slash.fill"
        case .inUse: return "mic.fill"
        case .waiting: return "speaker.slash.fill"
        case .ready: return "mic.fill"
        }
    }
    var tint: Color {
        switch self {
        case .unavailable: return .orange
        case .off: return .gray
        case .inUse: return .blue
        case .waiting: return .orange
        case .ready: return .green
        }
    }
}

final class SettingsModel: ObservableObject {
    @Published var kind: StatusKind = .ready
    @Published var title = ""
    @Published var detail = ""
    @Published var error = ""
    @Published var enabled = true
    @Published var loginOn = false
    @Published var autoUpdate = true
    @Published var language: AppLanguage = .system
    @Published var updateMessage = ""
    @Published var updateAvailable = false
    @Published var checking = false
    @Published var canKeepQuiet = false
    var version = ""

    var onEnabled: (Bool) -> Void = { _ in }
    var onLogin: (Bool) -> Void = { _ in }
    var onAutoUpdate: (Bool) -> Void = { _ in }
    var onLanguage: (AppLanguage) -> Void = { _ in }
    var onKeepQuiet: () -> Void = {}
    var onCheck: () -> Void = {}
    var onRelease: () -> Void = {}
    var onFactory: () -> Void = {}
    var onRepository: () -> Void = {}
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5))
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .textCase(.uppercase).tracking(0.6).padding(.leading, 4)
    }
}

private struct IconBadge: View {
    let symbol: String
    let tint: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient))
    }
}

private struct Row<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct Divided: View {
    var body: some View { Divider().padding(.leading, 54) }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let _ = model.language  // re-render when the language changes
        VStack(alignment: .leading, spacing: 20) {
            header
            hero
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: tr("General", "通用"))
                general
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: tr("Updates", "更新"))
                updates
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: tr("How it works", "工作方式"))
                howItWorks
            }
            footer
        }
        .padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 22)
        .frame(width: 468)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("PauseMic").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("v\(model.version)").font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Text(tr("A little quiet, right when you need it.", "开口那一刻，让声音安静下来。"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var hero: some View {
        let tint = model.kind.tint
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: model.kind.symbol)
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: model.kind == .inUse)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(tint.gradient))
                    .shadow(color: tint.opacity(0.35), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title).font(.system(size: 17, weight: .semibold))
                    Text(model.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { model.enabled }, set: { model.onEnabled($0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.large)
                    .help(tr("Set system output volume to 0 while the microphone is in use", "麦克风使用时，将系统输出音量设为 0"))
            }
            if model.canKeepQuiet {
                Button(action: model.onKeepQuiet) {
                    Label(tr("Keep volume at 0 · cancel restoration", "保持音量为 0 · 取消自动恢复"), systemImage: "speaker.slash")
                }.controlSize(.regular)
            }
            if !model.error.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(model.error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.12)))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 0.8))
        .animation(.easeInOut(duration: 0.25), value: model.kind)
    }

    private var general: some View {
        Card {
            Row(symbol: "power", tint: .green, title: tr("Launch at login", "登录时启动"),
                subtitle: tr("Start quietly in the menu bar", "自动在菜单栏静默运行")) {
                Toggle("", isOn: Binding(get: { model.loginOn }, set: { model.onLogin($0) })).toggleStyle(.switch).labelsHidden()
            }
            Divided()
            Row(symbol: "globe", tint: .blue, title: tr("Language", "语言")) {
                Picker("", selection: Binding(get: { model.language }, set: { model.onLanguage($0) })) {
                    Text(tr("System language", "跟随系统")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("简体中文").tag(AppLanguage.chinese)
                }.labelsHidden().fixedSize()
            }
        }
    }

    private var updates: some View {
        Card {
            Row(symbol: "arrow.triangle.2.circlepath", tint: .indigo, title: tr("Check automatically", "自动检查更新"),
                subtitle: tr("Every hour via GitHub Releases", "每小时通过 GitHub Release 检查")) {
                Toggle("", isOn: Binding(get: { model.autoUpdate }, set: { model.onAutoUpdate($0) })).toggleStyle(.switch).labelsHidden()
            }
            Divided()
            Row(symbol: model.updateAvailable ? "arrow.down.circle.fill" : "checkmark.seal.fill",
                tint: model.updateAvailable ? .orange : .teal, title: tr("Software update", "软件更新"), subtitle: model.updateMessage) {
                HStack(spacing: 8) {
                    if model.checking { ProgressView().controlSize(.small) }
                    if model.updateAvailable {
                        Button(tr("Download", "下载更新"), action: model.onRelease).buttonStyle(.borderedProminent)
                    } else {
                        Button(tr("Check now", "立即检查"), action: model.onCheck).disabled(model.checking)
                    }
                }
            }
        }
    }

    private var howItWorks: some View {
        Card {
            Row(symbol: "play.circle.fill", tint: .pink, title: tr("Media keeps playing", "媒体继续播放"),
                subtitle: tr("Saves your output volume, sets it to 0, then restores it.", "保存输出音量、设为 0，再恢复原音量。")) { EmptyView() }
            Divided()
            Row(symbol: "lock.shield.fill", tint: .green, title: tr("Private by design", "隐私优先"),
                subtitle: tr("No recording. No audio uploads.", "不录音，不上传音频。")) { EmptyView() }
            Divided()
            Row(symbol: "hand.raised.fill", tint: .orange, title: tr("You stay in control", "手动操作优先"),
                subtitle: tr("A manual volume or mute change cancels restoration for that output.", "检测到手动调节音量或静音后，会放弃恢复该设备的音量。")) { EmptyView() }
            Divided()
            Row(symbol: "menubar.rectangle", tint: .gray, title: tr("Lives in the menu bar", "常驻菜单栏"),
                subtitle: tr("Closing this window keeps PauseMic running. Disabling or quitting restores volume it still manages.",
                             "关闭窗口后继续运行；关闭自动静音或退出时，会恢复仍由 PauseMic 管理的音量。")) { EmptyView() }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text(tr("A hecara Factory project · Practical, reliable little tools.", "hecara Factory 工厂计划 · 提供实用可靠的小工具。"))
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button("hecara.com ↗", action: model.onFactory)
                Text("·").foregroundStyle(.tertiary)
                Button(tr("GitHub ↗", "GitHub ↗"), action: model.onRepository)
                Text("·").foregroundStyle(.tertiary)
                Text(tr("MIT License", "MIT 开源协议")).foregroundStyle(.tertiary)
            }
            .buttonStyle(.link).font(.system(size: 11.5))
        }
        .frame(maxWidth: .infinity).padding(.top, 2)
    }
}
