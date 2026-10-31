import AppKit

/// Lives in the menu bar. Click the icon to show or hide the scratchpad.
/// Right-click (or Control-click) it for the menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var scratchpad: ScratchpadController!
    private let settingsWindow = SettingsWindowController()
    private let menu = NSMenu()
    private var keepOpenItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMainMenu()
        setUpStatusItem()
        scratchpad = ScratchpadController(statusItem: statusItem)
        scratchpad.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        Preferences.shared.enableLaunchAtLoginOnFirstRun()

        Updater.shared.onNotificationClick = { [weak self] in self?.settingsWindow.show() }
        Updater.shared.startDailyChecks()

        // At login and after an update it starts quietly. Any other launch opens the scratchpad,
        // so whoever opened the app sees where it lives. The wait lets the icon find its place.
        let quietLaunch = launchedAsLoginItem || CommandLine.arguments.contains("--updated")
        if !quietLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.scratchpad.show() }
        }
    }

    /// Opening the app again (Spotlight, Launchpad, Finder) shows the scratchpad.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !scratchpad.isVisible { scratchpad.show() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        scratchpad.saveNow()
    }

    /// Set by the Quit buttons, the only ways to really stop Scratchpad.
    static var quitRequested = false

    /// ⌘Q and Quit in the Dock are easy to press by habit while settings are open,
    /// so they only close the window and the menu bar icon stays.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard settingsWindow.isVisible, !AppDelegate.quitRequested, !isSystemQuit else { return .terminateNow }
        settingsWindow.close()
        return .terminateCancel
    }

    /// Log out, restart and shut down send a quit event with a reason. Those must go through.
    private var isSystemQuit: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == fourCharCode("aevt"),
              event.eventID == fourCharCode("quit")
        else { return false }
        return event.attributeDescriptor(forKeyword: fourCharCode("why?")) != nil
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == fourCharCode("oapp")
        else { return false }
        return event.paramDescriptor(forKeyword: fourCharCode("prdt"))?.enumCodeValue == fourCharCode("lgit")
    }

    // MARK: Menu bar icon

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Scratchpad")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        keepOpenItem = menu.addItem(withTitle: "Keep Open", action: #selector(toggleKeepOpen), keyEquivalent: "")
        keepOpenItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Scratchpad", action: #selector(quit), keyEquivalent: "q").target = self
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            scratchpad.toggle()
        }
    }

    private func showMenu() {
        keepOpenItem.state = Preferences.shared.keepsOpen ? .on : .off
        // Setting the menu only for this click keeps a left click free for the scratchpad.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
        scratchpad.refreshIconHighlight()
    }

    @objc private func toggleKeepOpen() {
        Preferences.shared.keepsOpen.toggle()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func quit() {
        AppDelegate.quitRequested = true
        NSApp.terminate(nil)
    }

    /// Only shown while the settings window is open.
    private func setUpMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Scratchpad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        let mainMenu = NSMenu()
        for submenu in [appMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}

private func fourCharCode(_ code: String) -> UInt32 {
    code.utf8.reduce(0) { $0 << 8 | UInt32($1) }
}
