import XCTest
@testable import PauseMicCore

final class ReleaseTests: XCTestCase {
    func testVersionOrderingAndPrefix() {
        XCTAssertEqual(StableVersion("v1.2.3"), StableVersion("1.2.3"))
        XCTAssertTrue(StableVersion("1.10.0")! > StableVersion("1.9.9")!)
        XCTAssertTrue(StableVersion("2.0.0")! > StableVersion("1.99.99")!)
        XCTAssertFalse(StableVersion("0.1.0")! > StableVersion("0.1.0")!)
    }
    func testMalformedAndPrereleaseVersionsAreRejected() {
        for value in ["", "1", "1.2", "1.2.3.4", "1.2.3-beta", "1.2.3+meta", "1.-2.3", "01.2.3", "1..3", "１.2.3", "999999999999999999999999.0.0"] {
            XCTAssertNil(StableVersion(value), value)
        }
    }
    func testReleaseURLValidation() throws {
        func release(_ url: String, draft: Bool = false, prerelease: Bool = false) throws -> GitHubRelease {
            let data = try JSONSerialization.data(withJSONObject: ["tag_name": "v0.2.0", "html_url": url, "draft": draft, "prerelease": prerelease])
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        }
        XCTAssertNotNil(try release("https://github.com/hecara/PauseMic/releases/tag/v0.2.0").safeURL)
        for url in ["http://github.com/hecara/PauseMic/releases/tag/v0.2.0", "https://github.com.evil.test/hecara/PauseMic/releases/tag/v0.2.0", "https://github.com/other/repo/releases/tag/v0.2.0", "https://user@github.com/hecara/PauseMic/releases/tag/v0.2.0", "https://github.com:444/hecara/PauseMic/releases/tag/v0.2.0", "https://github.com/hecara/PauseMic/releases/tag/v0.2.0?next=evil"] {
            XCTAssertNil(try release(url).safeURL)
        }
        XCTAssertNil(try release("https://github.com/hecara/PauseMic/releases/tag/v0.2.0", draft: true).safeURL)
        XCTAssertNil(try release("https://github.com/hecara/PauseMic/releases/tag/v0.2.0", prerelease: true).safeURL)
    }
}
