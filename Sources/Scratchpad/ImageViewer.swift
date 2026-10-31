import AppKit

/// A picture in the scratchpad, and what you can do with it.
struct Picture {
    let image: NSImage
    /// The file as it came in (PNG, JPEG…), if known.
    let data: Data?
    let filename: String

    init?(_ attachment: NSTextAttachment) {
        let data = attachment.fileWrapper?.regularFileContents
        guard let image = attachment.image ?? data.flatMap({ NSImage(data: $0) }) else { return nil }
        self.image = image
        self.data = data
        let name = attachment.fileWrapper?.preferredFilename ?? attachment.fileWrapper?.filename ?? ""
        filename = name.isEmpty || data == nil ? "Picture.png" : name
    }

    /// As an image, so it pastes as a picture anywhere (Messages, Slack, Preview…).
    func copyToClipboard() {
        let item = NSPasteboardItem()
        if let pngData = png { item.setData(pngData, forType: .png) }
        if let tiff = image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    func openInPreview() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scratchpad", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(filename)
        guard let bytes = data ?? png,
              (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              (try? bytes.write(to: url)) != nil
        else { return }
        if let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private var png: Data? {
        if let data, data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return data }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}

/// Shows a picture big, as large as fits the screen. Pinch or ⌘+ ⌘− to zoom, ⌘0 to fit,
/// ⌘C to copy, Esc to close.
final class ImageViewer: NSObject, NSWindowDelegate {
    static let shared = ImageViewer()
    private var panel: ViewerPanel?
    private var scrollView: NSScrollView?
    private var picture: Picture?

    func show(_ picture: Picture) {
        close()
        self.picture = picture
        let image = picture.image
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let titleBar: CGFloat = 28
        let fit = min(1, visible.width * 0.85 / image.size.width, (visible.height * 0.85 - titleBar) / image.size.height)
        let size = NSSize(width: max(360, (image.size.width * fit).rounded()), height: max(200, (image.size.height * fit).rounded()))
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)

        let panel = ViewerPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Picture"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.minSize = NSSize(width: 300, height: 200)
        panel.delegate = self
        panel.onClose = { [weak self] in self?.close() }
        panel.onCommand = { [weak self] key in self?.handleCommand(key) ?? false }

        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.allowsMagnification = true
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        scrollView.documentView = imageView
        scrollView.minMagnification = min(fit, 0.1)
        scrollView.maxMagnification = 8
        scrollView.magnification = fit
        panel.contentView = scrollView
        panel.addTitlebarAccessoryViewController(makeButtons())

        self.panel = panel
        self.scrollView = scrollView
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.delegate = nil
        panel?.close()
        panel = nil
        scrollView = nil
        picture = nil
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        scrollView = nil
        picture = nil
    }

    private func makeButtons() -> NSTitlebarAccessoryViewController {
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyPicture))
        let preview = NSButton(title: "Open in Preview", target: self, action: #selector(openInPreview))
        for button in [copy, preview] {
            button.controlSize = .small
            button.bezelStyle = .rounded
        }
        let stack = NSStackView(views: [copy, preview])
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        stack.frame = NSRect(origin: .zero, size: NSSize(width: stack.fittingSize.width, height: 28))
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = stack
        accessory.layoutAttribute = .trailing
        return accessory
    }

    @objc private func copyPicture() { picture?.copyToClipboard() }
    @objc private func openInPreview() { picture?.openInPreview() }

    /// ⌘ shortcuts. Returns whether it was one of ours.
    private func handleCommand(_ key: String) -> Bool {
        guard let scrollView, let picture else { return false }
        let clip = scrollView.contentView.bounds
        let center = NSPoint(x: clip.midX, y: clip.midY)
        switch key {
        case "c": picture.copyToClipboard()
        case "w": close()
        case "=", "+": scrollView.setMagnification(scrollView.magnification * 1.25, centeredAt: center)
        case "-": scrollView.setMagnification(scrollView.magnification / 1.25, centeredAt: center)
        case "0":
            let size = scrollView.contentSize
            let fit = min(1, size.width / picture.image.size.width, size.height / picture.image.size.height)
            scrollView.setMagnification(fit, centeredAt: center)
        default: return false
        }
        return true
    }
}

private final class ViewerPanel: NSPanel {
    var onClose: (() -> Void)?
    var onCommand: ((String) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { onClose?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command || modifiers == [.command, .shift],
           let key = event.charactersIgnoringModifiers?.lowercased(), onCommand?(key) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Keeps a picture smaller than the window in the middle instead of the bottom-left corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let document = documentView.frame
        if rect.width > document.width { rect.origin.x = (document.width - rect.width) / 2 }
        if rect.height > document.height { rect.origin.y = (document.height - rect.height) / 2 }
        return rect
    }
}
