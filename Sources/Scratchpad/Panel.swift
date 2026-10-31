import AppKit

let cornerRadius: CGFloat = 12

/// A borderless panel that takes typing without making Scratchpad the active app,
/// so the app you were in stays in front (like Spotlight).
final class ScratchpadPanel: NSPanel {
    /// Esc and ⌘W.
    var onClose: (() -> Void)?

    static func make(size: NSSize) -> ScratchpadPanel {
        let panel = ScratchpadPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.minSize = NSSize(width: 240, height: 180)
        return panel
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // The text view would turn Esc into word completion, so it is caught here first.
        // While typing with an input method, Esc still cancels the half-typed text.
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .keyDown, event.keyCode == 53, modifiers.isEmpty,
           (firstResponder as? NSTextView)?.hasMarkedText() != true {
            onClose?()
            return
        }
        super.sendEvent(event)
    }

    /// There is no Edit menu while another app is in front, so the editing shortcuts are wired here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers == .command || modifiers == [.command, .shift] else {
            return super.performKeyEquivalent(with: event)
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let action: Selector?
        switch (key, modifiers.contains(.shift)) {
        case ("x", false): action = #selector(NSText.cut(_:))
        case ("c", false): action = #selector(NSText.copy(_:))
        case ("v", false): action = #selector(NSText.paste(_:))
        case ("a", false): action = #selector(NSText.selectAll(_:))
        case ("z", false): action = Selector(("undo:"))
        case ("z", true): action = Selector(("redo:"))
        case ("w", false):
            onClose?()
            return true
        default: action = nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Liquid Glass like the Control Center menus (macOS 26 and later), the frosted menu
/// material before that. Rounded corners, `content` filling it.
func makeBackground(size: NSSize, content: NSView) -> NSView {
    let frame = NSRect(origin: .zero, size: size)
    content.frame = frame
    content.autoresizingMask = [.width, .height]
    if #available(macOS 26, *) {
        let glass = NSGlassEffectView(frame: frame)
        glass.style = Preferences.shared.clearGlass ? .clear : .regular
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        return glass
    }
    let view = NSVisualEffectView(frame: frame)
    view.material = .menu
    view.blendingMode = .behindWindow
    view.state = .active
    view.maskImage = roundedMask()
    view.addSubview(content)
    return view
}

private func roundedMask() -> NSImage {
    let edge = cornerRadius * 2 + 1
    let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        return true
    }
    image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
    image.resizingMode = .stretch
    return image
}

/// Header buttons work on the first click, even while another app is in front.
private final class HeaderButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Title, settings, minimize and pin buttons, then the text.
final class BoardView: NSView {
    let textView: ScratchTextView
    let pinButton: NSButton = HeaderButton()
    let minimizeButton: NSButton = HeaderButton()
    let settingsButton: NSButton = HeaderButton()
    private let scrollView = NSScrollView()
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        // Zero width: the scroll view grows it to its own width (autoresizing adds the difference).
        textView = ScratchTextView(frame: .zero)
        super.init(frame: frame)
        textView.setUp()

        let titleLabel = NSTextField(labelWithString: "Scratchpad")
        titleLabel.font = .boldSystemFont(ofSize: 13)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor

        for button in [settingsButton, minimizeButton, pinButton] {
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.refusesFirstResponder = true
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        }
        minimizeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Minimize")
        minimizeButton.contentTintColor = .secondaryLabelColor
        minimizeButton.toolTip = "Minimize into the menu bar"
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.toolTip = "Settings"

        let separator = NSBox()
        separator.boxType = .separator

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        for view in [titleLabel, subtitleLabel, settingsButton, minimizeButton, pinButton, separator, scrollView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            pinButton.centerYAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            pinButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pinButton.widthAnchor.constraint(equalToConstant: 24),
            pinButton.heightAnchor.constraint(equalToConstant: 24),
            minimizeButton.centerYAnchor.constraint(equalTo: pinButton.centerYAnchor),
            minimizeButton.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -2),
            minimizeButton.widthAnchor.constraint(equalToConstant: 24),
            minimizeButton.heightAnchor.constraint(equalToConstant: 24),
            settingsButton.centerYAnchor.constraint(equalTo: pinButton.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: minimizeButton.leadingAnchor, constant: -2),
            settingsButton.widthAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24),

            separator.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 2),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setPinned(_ pinned: Bool) {
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "Keep open")
        pinButton.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = pinned ? "Stop keeping it open" : "Keep it open over other windows"
        subtitleLabel.stringValue = pinned ? "Stays open" : "Hides when you click away"
    }

    /// A thin edge like the menus have. Glass draws its own.
    override func draw(_ dirtyRect: NSRect) {
        if #available(macOS 26, *) { return }
        NSColor.separatorColor.setStroke()
        let edge = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: cornerRadius - 0.5,
            yRadius: cornerRadius - 0.5
        )
        edge.lineWidth = 1
        edge.stroke()
    }
}
