import AppKit

let application = NSApplication.shared
let instanceLock = InstanceLock()
if instanceLock.acquire() {
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
} else {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.hecara.PauseMic")
        .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
        .activate(options: [])
}
