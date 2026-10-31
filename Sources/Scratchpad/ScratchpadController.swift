import AppKit
import Combine
import QuartzCore

/// Shows the scratchpad under the menu bar icon and hides it again.
final class ScratchpadController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private let statusItem: NSStatusItem
    private let panel: ScratchpadPanel
    private let board: BoardView
    private var outsideClickMonitor: Any?
    private var saveWork: DispatchWorkItem?
    private var hasUnsavedChanges = false
    private var subscriptions: Set<AnyCancellable> = []

    var isVisible: Bool { panel.isVisible }
    var onOpenSettings: (() -> Void)?

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        let size = Preferences.shared.panelSize
        panel = ScratchpadPanel.make(size: size)
        board = BoardView(frame: NSRect(origin: .zero, size: size))
        super.init()

        panel.contentView = makeBackground(size: size, content: board)
        panel.delegate = self
        panel.onClose = { [weak self] in self?.minimizeIntoIcon() }

        board.textView.setContents(NoteStore.load())
        board.textView.delegate = self
        board.pinButton.target = self
        board.pinButton.action = #selector(pinClicked)
        board.minimizeButton.target = self
        board.minimizeButton.action = #selector(minimizeClicked)
        board.settingsButton.target = self
        board.settingsButton.action = #selector(settingsClicked)

        // Changes from the pin, the menu and the settings window all land here.
        // On the main queue, so the new value is stored by the time this runs.
        Preferences.shared.$keepsOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] keepsOpen in
                self?.board.setPinned(keepsOpen)
                self?.updateOutsideClickWatching()
            }
            .store(in: &subscriptions)
        Preferences.shared.$clearGlass
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.replaceBackground() }
            .store(in: &subscriptions)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(otherAppActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func toggle() {
        if panel.isVisible {
            minimizeIntoIcon()
        } else {
            show()
        }
    }

    func show() {
        panel.setFrame(frameBelowIcon(size: Preferences.shared.panelSize), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        board.textView.fitPictures()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(board.textView)
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            self.panel.animator().alphaValue = 1
        }
        setIconHighlighted(true)
        updateOutsideClickWatching()
    }

    /// Hides at once. Used when you click somewhere else.
    private func hideNow() {
        guard panel.isVisible else { return }
        saveNow()
        panel.orderOut(nil)
        setIconHighlighted(false)
        updateOutsideClickWatching()
    }

    private func hideIfNotPinned() {
        if !Preferences.shared.keepsOpen { hideNow() }
    }

    /// Shrinks a picture of the scratchpad into the menu bar icon. The real panel hides at once,
    /// so its text does not reflow while it shrinks.
    func minimizeIntoIcon() {
        guard panel.isVisible else { return }
        guard let icon = iconFrame(), let picture = snapshot(of: board) else {
            hideNow()
            return
        }
        let ghost = makeGhost(frame: panel.frame, picture: picture)
        ghost.order(.above, relativeTo: panel.windowNumber)
        hideNow()

        let end = NSRect(x: icon.midX - 10, y: icon.midY - 8, width: 20, height: 16)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ghost.animator().setFrame(end, display: true)
            ghost.animator().alphaValue = 0.15
        }, completionHandler: {
            ghost.orderOut(nil)
        })
    }

    @objc private func pinClicked() {
        Preferences.shared.keepsOpen.toggle()
    }

    @objc private func settingsClicked() {
        hideIfNotPinned()
        onOpenSettings?()
    }

    /// After the glass style changes.
    private func replaceBackground() {
        board.removeFromSuperview()
        panel.contentView = makeBackground(size: panel.frame.size, content: board)
        panel.invalidateShadow()
    }

    @objc private func minimizeClicked() {
        minimizeIntoIcon()
    }

    // MARK: Hiding when you click away

    private func updateOutsideClickWatching() {
        let shouldWatch = panel.isVisible && !Preferences.shared.keepsOpen
        if shouldWatch, outsideClickMonitor == nil {
            // Only sees clicks in other apps. Clicks on the menu bar icon are Scratchpad's own.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                self?.hideIfNotPinned()
            }
        } else if !shouldWatch, let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    /// ⌘Tab to another app counts as clicking away.
    @objc private func otherAppActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        hideIfNotPinned()
    }

    // MARK: Saving

    func textDidChange(_ notification: Notification) {
        hasUnsavedChanges = true
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        NoteStore.save(board.textView.contents)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        Preferences.shared.panelSize = panel.frame.size
        board.textView.fitPictures()
    }

    // MARK: Placement

    private func iconFrame() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Just under the icon, left edges lined up like the Control Center menus, kept on screen.
    private func frameBelowIcon(size: NSSize) -> NSRect {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let icon = iconFrame() ?? NSRect(x: visible.midX - size.width / 2, y: visible.maxY, width: 0, height: 0)
        let top = min(icon.minY, visible.maxY) - 5
        let height = min(size.height, top - visible.minY - 8)
        let x = min(max(icon.minX - 8, visible.minX + 8), visible.maxX - size.width - 8)
        return NSRect(x: x, y: top - height, width: size.width, height: height)
    }

    private func setIconHighlighted(_ highlighted: Bool) {
        // The click on the icon clears the highlight when it ends, so set it after that.
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.highlight(highlighted)
        }
    }

    func refreshIconHighlight() {
        setIconHighlighted(panel.isVisible)
    }

    // MARK: Minimize animation

    private func snapshot(of view: NSView) -> NSImage? {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    /// The same glass background with a picture of the text on top. The background
    /// stays live while it shrinks, so it looks like the real thing.
    private func makeGhost(frame: NSRect, picture: NSImage) -> NSWindow {
        let ghost = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        ghost.isOpaque = false
        ghost.backgroundColor = .clear
        ghost.hasShadow = false
        ghost.ignoresMouseEvents = true
        ghost.isReleasedWhenClosed = false
        ghost.level = panel.level
        ghost.collectionBehavior = panel.collectionBehavior

        let imageView = NSImageView()
        imageView.image = picture
        imageView.imageScaling = .scaleAxesIndependently
        ghost.contentView = makeBackground(size: frame.size, content: imageView)
        return ghost
    }
}
