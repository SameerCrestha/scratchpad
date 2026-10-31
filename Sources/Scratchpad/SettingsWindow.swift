import AppKit
import ServiceManagement
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        Preferences.shared.refresh()
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(prefs: .shared)))
            window.title = "Scratchpad Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        // While the window is open the app gets a Dock icon and a menu bar, so it is easy to find.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }

    var isVisible: Bool { window.map { $0.isVisible || $0.isMiniaturized } ?? false }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var updater: Updater = .shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scratchpad").font(.title2.bold())
                        Text("A notepad in the menu bar. Click the note icon at the top of the screen to open it.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Keep open over other windows", isOn: $prefs.keepsOpen)
                if #available(macOS 26, *) {
                    Toggle("Clear glass", isOn: $prefs.clearGlass)
                }
                HStack {
                    Text("Notes and pictures")
                    Spacer()
                    Button("Show in Finder", action: showNotesInFinder)
                }
            } header: {
                Text("Scratchpad")
            } footer: {
                Text("When it is not kept open, it hides as soon as you click anywhere else. The pin button in the scratchpad does the same as the switch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { prefs.launchesAtLogin },
                    set: { prefs.setLaunchAtLogin($0) }
                ))
                if prefs.loginItemStatus == .requiresApproval {
                    HStack {
                        Text("Approve Scratchpad in Login Items.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let error = prefs.loginItemError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Updates") {
                HStack {
                    Text("Version \(updater.currentVersion)")
                    Spacer()
                    updateStatus
                }
                if case .failed(let message) = updater.status {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                Toggle("Install updates automatically", isOn: $updater.installsAutomatically)
            }

            Section {
                HStack {
                    Text("Quit removes the menu bar icon until you open Scratchpad again, or log in.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Scratchpad") {
                        AppDelegate.quitRequested = true
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 636)
    }

    @ViewBuilder private var updateStatus: some View {
        switch updater.status {
        case .checking:
            ProgressView().controlSize(.small)
        case .available(let version):
            Button("Install \(version)") { updater.install() }
                .buttonStyle(.borderedProminent)
        case .installing:
            HStack {
                ProgressView().controlSize(.small)
                Text("Installing…").foregroundStyle(.secondary)
            }
        case .upToDate:
            HStack {
                Text("Up to date").foregroundStyle(.secondary)
                Button("Check Now") { updater.check(manual: true) }
            }
        case .idle, .failed:
            Button("Check Now") { updater.check(manual: true) }
        }
    }

    private func showNotesInFinder() {
        if FileManager.default.fileExists(atPath: NoteStore.fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([NoteStore.fileURL])
        } else {
            try? FileManager.default.createDirectory(at: NoteStore.folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(NoteStore.folder)
        }
    }
}
