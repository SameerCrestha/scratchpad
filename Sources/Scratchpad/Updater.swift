import AppKit
import Security
import UserNotifications
import os

private let log = Logger(subsystem: "io.github.sameercrestha.scratchpad", category: "update")

/// Checks GitHub once a day for a newer release, and installs it in place.
/// The new app must be signed like the running one, so a tampered download is refused.
final class Updater: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Updater()
    private static let latestRelease = URL(string: "https://api.github.com/repos/SameerCrestha/scratchpad/releases/latest")!

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case installing
        case failed(String)
    }

    @Published private(set) var status = Status.idle
    @Published var installsAutomatically: Bool {
        didSet { UserDefaults.standard.set(installsAutomatically, forKey: "installUpdatesAutomatically") }
    }

    /// Called when the update notification is clicked.
    var onNotificationClick: (() -> Void)?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private var downloadURL: URL?
    private var timer: Timer?

    private override init() {
        installsAutomatically = UserDefaults.standard.bool(forKey: "installUpdatesAutomatically")
        super.init()
    }

    func startDailyChecks() {
        UNUserNotificationCenter.current().delegate = self
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in self?.check() }
    }

    /// `manual` is the Check Now button: then errors are shown instead of ignored.
    func check(manual: Bool = false) {
        guard status != .checking, status != .installing else { return }
        status = .checking
        var request = URLRequest(url: Self.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let release = data.flatMap { try? JSONDecoder().decode(Release.self, from: $0) }
            DispatchQueue.main.async { self.handle(release, manual: manual) }
        }.resume()
    }

    private func handle(_ release: Release?, manual: Bool) {
        guard let release else {
            status = manual ? .failed("Could not reach GitHub to check for updates.") : .idle
            return
        }
        guard Self.isNewer(release.version, than: currentVersion),
              let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") })
        else {
            status = .upToDate
            return
        }
        downloadURL = dmg.browserDownloadURL
        status = .available(version: release.version)
        log.notice("version \(release.version, privacy: .public) is available")
        if installsAutomatically {
            install()
        } else if !manual {
            notify(release.version)
        }
    }

    func install() {
        guard let downloadURL, status != .installing else { return }
        status = .installing
        URLSession.shared.downloadTask(with: downloadURL) { file, _, _ in
            // The downloaded file is deleted when this handler returns, so install right here.
            var failure: String?
            if let file {
                do {
                    try Self.installApp(fromDMG: file)
                } catch {
                    failure = error.localizedDescription
                }
            } else {
                failure = "The download failed."
            }
            DispatchQueue.main.async {
                if let failure {
                    log.error("update failed: \(failure, privacy: .public)")
                    self.status = .failed(failure)
                } else {
                    Self.relaunch()
                }
            }
        }.resume()
    }

    // MARK: Notification

    private func notify(_ version: String) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "notifiedVersion") != version else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            defaults.set(version, forKey: "notifiedVersion")
            let content = UNMutableNotificationContent()
            content.title = "Scratchpad \(version) is available"
            content.body = "Click to open Scratchpad settings and install it."
            center.add(UNNotificationRequest(identifier: "update", content: content, trigger: nil))
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async { self.onNotificationClick?() }
        completionHandler()
    }

    // MARK: Install

    private static func installApp(fromDMG dmg: URL) throws {
        let fileManager = FileManager.default
        let mountPoint = fileManager.temporaryDirectory.appendingPathComponent("Scratchpad-update-\(UUID().uuidString)")
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path)
        defer {
            try? run("/usr/bin/hdiutil", "detach", mountPoint.path, "-force")
            try? fileManager.removeItem(at: mountPoint)
        }

        let newApp = mountPoint.appendingPathComponent("Scratchpad.app")
        try verifySignature(of: newApp)

        // Copy next to the current app first, so the swap stays on one disk.
        let current = Bundle.main.bundleURL
        let staged = current.deletingLastPathComponent().appendingPathComponent(".Scratchpad-update.app")
        try? fileManager.removeItem(at: staged)
        try fileManager.copyItem(at: newApp, to: staged)
        _ = try fileManager.replaceItemAt(current, withItemAt: staged)
    }

    /// The update must meet the running app's designated requirement: same bundle ID, same certificate.
    private static func verifySignature(of app: URL) throws {
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        var newStatic: SecStaticCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
              SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &newStatic) == errSecSuccess, let newStatic,
              SecStaticCodeCheckValidity(newStatic, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
        else {
            throw UpdateError("The update is not signed like this copy of Scratchpad, so it was not installed.")
        }
    }

    /// Starts the new copy once this one has quit.
    private static func relaunch() {
        let script = "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\" --args --updated"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, Bundle.main.bundleURL.path]
        try? process.run()
        AppDelegate.quitRequested = true
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("\(URL(fileURLWithPath: tool).lastPathComponent) failed while installing the update.")
        }
    }

    static func isNewer(_ version: String, than current: String) -> Bool {
        let new = version.split(separator: ".").map { Int($0) ?? 0 }
        let old = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0 ..< max(new.count, old.count) {
            let a = i < new.count ? new[i] : 0
            let b = i < old.count ? old[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}

private struct Release: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
}

private struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
