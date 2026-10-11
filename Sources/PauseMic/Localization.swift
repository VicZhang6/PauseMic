import Foundation

enum AppLanguage: String, CaseIterable {
    case system, english, chinese
    static var current: AppLanguage { AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "system") ?? .system }
    var usesChinese: Bool {
        self == .chinese || (self == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true)
    }
    static func text(_ english: String, _ chinese: String) -> String { current.usesChinese ? chinese : english }
}
func tr(_ english: String, _ chinese: String) -> String { AppLanguage.text(english, chinese) }
