import AppKit
import PauseMicCore

final class UpdateChecker {
    enum State {
        case idle, checking, current, available(String, URL), noRelease, failed
    }
    private(set) var state: State = .idle { didSet { onChange?() } }
    private(set) var lastChecked: Date?
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var task: URLSessionDataTask?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()
    var automatic = true
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

    func start() {
        if automatic { check() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self, self.automatic else { return }; self.check()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
    }
    @objc private func woke() {
        if automatic, lastChecked == nil || Date().timeIntervalSince(lastChecked!) >= 3600 { check() }
    }
    func check() {
        guard task == nil else { return }
        state = .checking
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/hecara/PauseMic/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PauseMic/\(version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.task = nil; self.lastChecked = Date()
                let code = (response as? HTTPURLResponse)?.statusCode
                if error == nil, code == 404 { self.state = .noRelease; return }
                guard error == nil, code == 200, let data,
                      let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
                      let url = release.safeURL, let remote = StableVersion(release.tag_name),
                      let local = StableVersion(self.version) else { self.state = .failed; return }
                self.state = remote > local ? .available(release.tag_name, url) : .current
            }
        }
        task?.resume()
    }
    var message: String {
        switch state {
        case .idle: return tr("Checks GitHub Releases every hour.", "每小时检查 GitHub Release。")
        case .checking: return tr("Checking GitHub…", "正在检查 GitHub…")
        case .current: return tr("You’re up to date.", "已是最新版本。")
        case .available(let version, _): return tr("Update available: \(version)", "有新版本：\(version)")
        case .noRelease: return tr("No release published yet.", "尚未发布 Release。")
        case .failed: return tr("Update check failed. Try again later.", "检查更新失败，请稍后重试。")
        }
    }
    func openRelease() {
        if case .available(_, let url) = state { NSWorkspace.shared.open(url) }
        else { NSWorkspace.shared.open(URL(string: "https://github.com/hecara/PauseMic/releases")!) }
    }
}
