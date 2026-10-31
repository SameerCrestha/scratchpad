import AppKit
import ServiceManagement
import os

private let log = Logger(subsystem: "io.github.sameercrestha.scratchpad", category: "storage")

/// Settings shared by the scratchpad and the settings window. Main thread only.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    /// On: the scratchpad floats over other windows until it is minimized.
    /// Off: any click outside it hides it at once.
    @Published var keepsOpen: Bool {
        didSet { defaults.set(keepsOpen, forKey: "keepsOpen") }
    }

    /// Clear glass shows more of what is behind it. Regular glass is easier to read (macOS 26 and later).
    @Published var clearGlass: Bool {
        didSet { defaults.set(clearGlass, forKey: "clearGlass") }
    }

    @Published var loginItemStatus = SMAppService.mainApp.status
    @Published private(set) var loginItemError: String?

    private init() {
        keepsOpen = defaults.bool(forKey: "keepsOpen")
        clearGlass = defaults.bool(forKey: "clearGlass")
    }

    var panelSize: NSSize {
        get {
            let width = defaults.double(forKey: "panelWidth")
            let height = defaults.double(forKey: "panelHeight")
            return width > 0 && height > 0 ? NSSize(width: width, height: height) : NSSize(width: 340, height: 380)
        }
        set {
            defaults.set(Double(newValue.width), forKey: "panelWidth")
            defaults.set(Double(newValue.height), forKey: "panelHeight")
        }
    }

    var launchesAtLogin: Bool { loginItemStatus == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        loginItemStatus = SMAppService.mainApp.status
    }

    /// Launch at login is on by default. Done once, so turning it off later sticks.
    func enableLaunchAtLoginOnFirstRun() {
        guard !defaults.bool(forKey: "launchAtLoginDefaultApplied") else { return }
        defaults.set(true, forKey: "launchAtLoginDefaultApplied")
        if !launchesAtLogin { setLaunchAtLogin(true) }
    }

    func refresh() {
        loginItemStatus = SMAppService.mainApp.status
    }
}

/// The text and pictures live in ~/Library/Application Support/Scratchpad/scratchpad.rtfd
/// (opens in TextEdit).
enum NoteStore {
    static let folder: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Scratchpad", isDirectory: true)
    }()
    static let fileURL = folder.appendingPathComponent("scratchpad.rtfd", isDirectory: true)
    /// 0.1.0 kept plain text here. Read only while there is no .rtfd yet.
    private static let plainTextURL = folder.appendingPathComponent("scratchpad.txt")

    static func load() -> NSAttributedString {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.rtfd]
        if let text = try? NSAttributedString(url: fileURL, options: options, documentAttributes: nil) {
            return text
        }
        return NSAttributedString(string: (try? String(contentsOf: plainTextURL, encoding: .utf8)) ?? "")
    }

    static func save(_ text: NSAttributedString) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = try text.fileWrapper(
                from: NSRange(location: 0, length: text.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            try file.write(to: fileURL, options: .atomic, originalContentsURL: nil)
        } catch {
            log.error("could not save: \(error.localizedDescription, privacy: .public)")
        }
    }
}
