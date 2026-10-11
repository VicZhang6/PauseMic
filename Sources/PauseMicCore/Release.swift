import Foundation

public struct StableVersion: Comparable, Equatable {
    private let parts: [Int]
    public init?(_ value: String) {
        let raw = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let components = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              components.allSatisfy({ $0.count == 1 || !$0.hasPrefix("0") }) else { return nil }
        let parsed = components.compactMap { Int($0) }
        guard parsed.count == 3 else { return nil }
        parts = parsed
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}

public struct GitHubRelease: Decodable {
    public let tag_name: String
    public let html_url: String
    public let draft: Bool
    public let prerelease: Bool
    public var safeURL: URL? {
        guard !draft, !prerelease, StableVersion(tag_name) != nil,
              let url = URL(string: html_url), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.path.hasPrefix("/hecara/PauseMic/releases/tag/"), url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}
