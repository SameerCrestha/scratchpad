import AppKit
import UniformTypeIdentifiers

/// Plain text plus pictures and files. Pasted or dropped text always comes in plain.
/// Copied pictures (screenshots, "Copy Image" in a browser) and files from Finder go in as
/// attachments, and can be dragged back out.
final class ScratchTextView: NSTextView {
    static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
    }

    /// Called once after `init(frame:)`. No init override, so all of NSTextView's inits stay.
    func setUp() {
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true

        drawsBackground = false
        isRichText = true
        importsGraphics = true
        allowsUndo = true
        textContainerInset = NSSize(width: 6, height: 6)
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        typingAttributes = Self.textAttributes
    }

    func setContents(_ contents: NSAttributedString) {
        let text = NSMutableAttributedString(attributedString: contents)
        let whole = NSRange(location: 0, length: text.length)
        // Saved colors are fixed (white in Dark Mode), so put back the ones that follow the theme.
        text.addAttributes(Self.textAttributes, range: whole)
        // Attachments come back from disk as plain ones, which do not draw the way we want.
        text.enumerateAttribute(.attachment, in: whole) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            if let ours = ScratchAttachment.make(from: attachment) {
                text.addAttribute(.attachment, value: ours, range: range)
            } else {
                text.removeAttribute(.attachment, range: range)
            }
        }
        textStorage?.setAttributedString(text)
        typingAttributes = Self.textAttributes
    }

    var contents: NSAttributedString {
        textStorage.map { NSAttributedString(attributedString: $0) } ?? NSAttributedString()
    }

    // MARK: Paste and drop

    /// Paste and drop both come through here.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if let rich = Self.textWithAttachments(on: pboard) {
            insert(rich)
            return true
        }
        let attachments = Self.attachments(on: pboard)
        if !attachments.isEmpty {
            let inserted = NSMutableAttributedString()
            for attachment in attachments {
                if inserted.length > 0 { inserted.append(NSAttributedString(string: "\n")) }
                inserted.append(NSAttributedString(attachment: attachment))
            }
            insert(inserted)
            return true
        }
        if pboard.availableType(from: [.string]) != nil {
            return super.readSelection(from: pboard, type: .string)
        }
        return super.readSelection(from: pboard, type: type)
    }

    private static func attachments(on pboard: NSPasteboard) -> [ScratchAttachment] {
        // Files, copied in Finder or dragged in. Folders and very big files are left out,
        // and if nothing is left their names paste as text.
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            let files = urls.compactMap { ScratchAttachment.make(contentsOf: $0) }
            if files.count < urls.count { NSSound.beep() }
            return files
        }
        // A copied picture. Some apps put real text next to a picture of it (Office does),
        // and that should paste as text. Browsers add only the image's link.
        guard isAtMostALink(pboard.string(forType: .string)),
              let image = NSImage(pasteboard: pboard),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return [] }
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
        return [ScratchAttachment.make(data: png, filename: "Pasted image \(stamp).png")]
    }

    /// Text with pictures or files in it, copied from the scratchpad itself, Notes or TextEdit.
    /// The text comes in plain, the attachments as they are. Nil if there are no attachments.
    private static func textWithAttachments(on pboard: NSPasteboard) -> NSAttributedString? {
        guard pboard.availableType(from: [.fileURL]) == nil,
              let data = pboard.data(forType: .rtfd),
              let rich = NSAttributedString(rtfd: data, documentAttributes: nil)
        else { return nil }
        let plain = NSMutableAttributedString(string: rich.string)
        var found = false
        rich.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rich.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment, let ours = ScratchAttachment.make(from: attachment) else { return }
            plain.addAttribute(.attachment, value: ours, range: range)
            found = true
        }
        return found ? plain : nil
    }

    private static func isAtMostALink(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return true }
        guard !text.contains(where: { $0.isWhitespace }), let url = URL(string: text) else { return false }
        return url.scheme != nil
    }

    private func insert(_ text: NSAttributedString) {
        let inserted = NSMutableAttributedString(attributedString: text)
        inserted.addAttributes(Self.textAttributes, range: NSRange(location: 0, length: inserted.length))

        let range = rangeForUserTextChange
        guard range.location != NSNotFound, shouldChangeText(in: range, replacementString: inserted.string) else { return }
        textStorage?.replaceCharacters(in: range, with: inserted)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + inserted.length, length: 0))
        typingAttributes = Self.textAttributes
    }

    // MARK: Clicking and dragging attachments

    /// On a picture or file: a drag takes a copy out to another app or Finder.
    /// A click opens a picture big. A double click opens a file.
    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        guard event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty,
              let (index, attachment) = attachment(at: start),
              let window
        else {
            super.mouseDown(with: event)
            return
        }
        // Wait to see whether this is a click or the start of a drag.
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp {
                clicked(attachment, at: index, clickCount: event.clickCount)
                return
            }
            let point = convert(next.locationInWindow, from: nil)
            if hypot(point.x - start.x, point.y - start.y) > 3 {
                dragOut(attachment, at: index, event: event)
                return
            }
        }
    }

    private func clicked(_ attachment: ScratchAttachment, at index: Int, clickCount: Int) {
        if attachment.isPicture {
            if clickCount == 1, let picture = Picture(attachment) { ImageViewer.shared.show(picture) }
        } else if clickCount == 2 {
            open(attachment)
        } else {
            // Selected, so ⌘C copies the file and Delete removes it.
            setSelectedRange(NSRange(location: index, length: 1))
        }
    }

    private func dragOut(_ attachment: ScratchAttachment, at index: Int, event: NSEvent) {
        guard let url = attachment.exportToTemporaryFile() else { return }
        // A file for Finder, Mail, Slack and upload fields. Pictures also as image data,
        // for apps that only take images.
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if attachment.isPicture, let data = attachment.data, let type = UTType(filenameExtension: url.pathExtension) {
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let shown = frame(ofCharacterAt: index)
            ?? NSRect(origin: convert(event.locationInWindow, from: nil), size: NSSize(width: 32, height: 32))
        let preview = attachment.pictureImage ?? NSWorkspace.shared.icon(forFile: url.path)
        let previewFrame = attachment.isPicture ? shown : NSRect(x: shown.minX + 6, y: shown.midY - 16, width: 32, height: 32)
        dragging.setDraggingFrame(previewFrame, contents: preview)
        beginDraggingSession(with: [dragging], event: event, source: DragOutSource.shared)
    }

    private func open(_ attachment: ScratchAttachment) {
        guard let url = attachment.exportToTemporaryFile() else { return }
        NSWorkspace.shared.open(url)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if attachment(at: convert(event.locationInWindow, from: nil)) != nil {
            NSCursor.pointingHand.set()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let (index, attachment) = attachment(at: convert(event.locationInWindow, from: nil)) else {
            return super.menu(for: event)
        }
        let items: [(String, Selector)] = attachment.isPicture
            ? [("Open Large", #selector(openFromMenu(_:))), ("Copy Image", #selector(copyFromMenu(_:))),
               ("Open in Preview", #selector(previewFromMenu(_:)))]
            : [("Open", #selector(openFromMenu(_:))), ("Copy", #selector(copyFromMenu(_:)))]
        let menu = NSMenu()
        for (title, action) in items + [("Delete", #selector(deleteFromMenu(_:)))] {
            if title == "Delete" { menu.addItem(.separator()) }
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = index
        }
        return menu
    }

    @objc private func openFromMenu(_ item: NSMenuItem) {
        guard let attachment = attachment(for: item) else { return }
        if let picture = Picture(attachment) {
            ImageViewer.shared.show(picture)
        } else {
            open(attachment)
        }
    }

    @objc private func copyFromMenu(_ item: NSMenuItem) {
        if let attachment = attachment(for: item) { copyToClipboard(attachment) }
    }

    @objc private func previewFromMenu(_ item: NSMenuItem) {
        if let attachment = attachment(for: item) { Picture(attachment)?.openInPreview() }
    }

    @objc private func deleteFromMenu(_ item: NSMenuItem) {
        guard let index = item.representedObject as? Int, let storage = textStorage, index < storage.length else { return }
        let range = NSRange(location: index, length: 1)
        guard shouldChangeText(in: range, replacementString: "") else { return }
        storage.replaceCharacters(in: range, with: "")
        didChangeText()
    }

    private func attachment(for item: NSMenuItem) -> ScratchAttachment? {
        guard let index = item.representedObject as? Int, let storage = textStorage, index < storage.length else { return nil }
        return storage.attribute(.attachment, at: index, effectiveRange: nil) as? ScratchAttachment
    }

    /// A picture copies as an image, a file as a file (paste it in Finder, Mail, Slack…).
    private func copyToClipboard(_ attachment: ScratchAttachment) {
        if let picture = Picture(attachment) {
            picture.copyToClipboard()
        } else if let url = attachment.exportToTemporaryFile() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        }
    }

    /// A lone selected picture or file copies on its own, so it pastes into any app.
    /// Anything bigger copies as rich text, which keeps text and attachments together.
    override func copy(_ sender: Any?) {
        let range = selectedRange()
        if range.length == 1, let storage = textStorage,
           let attachment = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? ScratchAttachment {
            copyToClipboard(attachment)
            return
        }
        super.copy(sender)
    }

    /// The attachment under `point`, with its character index.
    private func attachment(at point: NSPoint) -> (Int, ScratchAttachment)? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let index = characterIndexForInsertion(at: point)
        // The index is the gap nearest the point, so the attachment is just before or just after it.
        for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
            guard let attachment = storage.attribute(.attachment, at: candidate, effectiveRange: nil) as? ScratchAttachment,
                  let rect = frame(ofCharacterAt: candidate)
            else { continue }
            if rect.insetBy(dx: -2, dy: -2).contains(point) { return (candidate, attachment) }
        }
        return nil
    }

    private func frame(ofCharacterAt index: Int) -> NSRect? {
        guard let window else { return nil }
        let onScreen = firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil)
        return convert(window.convertFromScreen(onScreen), from: nil)
    }
}
