import AppKit
import UniformTypeIdentifiers

/// Plain text plus pictures. Pasted or dropped text always comes in plain. Copied pictures
/// (screenshots, "Copy Image" in a browser) and image files go in as images, shrunk to fit.
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
        // Saved colors are fixed (white in Dark Mode), so put back the ones that follow the theme.
        text.addAttributes(Self.textAttributes, range: NSRange(location: 0, length: text.length))
        textStorage?.setAttributedString(text)
        typingAttributes = Self.textAttributes
        fitPictures()
    }

    var contents: NSAttributedString {
        textStorage.map { NSAttributedString(attributedString: $0) } ?? NSAttributedString()
    }

    // MARK: Paste and drop

    /// Paste and drop both come through here.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        let pictures = Self.pictures(on: pboard)
        if !pictures.isEmpty {
            insert(pictures)
            return true
        }
        if pboard.availableType(from: [.string]) != nil {
            return super.readSelection(from: pboard, type: .string)
        }
        return super.readSelection(from: pboard, type: type)
    }

    private struct Picture {
        let image: NSImage
        let file: FileWrapper
    }

    private static func pictures(on pboard: NSPasteboard) -> [Picture] {
        // Image files, copied in Finder or dragged in.
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return urls.compactMap { url in
                guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return nil }
                let file = FileWrapper(regularFileWithContents: data)
                file.preferredFilename = url.lastPathComponent
                return Picture(image: image, file: file)
            }
        }
        // A copied picture. Some apps put real text next to a picture of it (Office does),
        // and that should paste as text. Browsers add only the image's link.
        guard isAtMostALink(pboard.string(forType: .string)),
              let image = NSImage(pasteboard: pboard),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return [] }
        let file = FileWrapper(regularFileWithContents: png)
        file.preferredFilename = "image.png"
        return [Picture(image: image, file: file)]
    }

    private static func isAtMostALink(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return true }
        guard !text.contains(where: { $0.isWhitespace }), let url = URL(string: text) else { return false }
        return url.scheme != nil
    }

    private func insert(_ pictures: [Picture]) {
        let inserted = NSMutableAttributedString()
        for picture in pictures {
            let attachment = NSTextAttachment(fileWrapper: picture.file)
            attachment.image = picture.image
            attachment.bounds = NSRect(origin: .zero, size: fittedSize(picture.image.size))
            inserted.append(NSAttributedString(attachment: attachment))
        }
        inserted.addAttributes(Self.textAttributes, range: NSRange(location: 0, length: inserted.length))

        let range = rangeForUserTextChange
        guard range.location != NSNotFound, shouldChangeText(in: range, replacementString: inserted.string) else { return }
        textStorage?.replaceCharacters(in: range, with: inserted)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + inserted.length, length: 0))
        typingAttributes = Self.textAttributes
    }

    // MARK: Picture size

    private func fittedSize(_ size: NSSize) -> NSSize {
        let padding = textContainer?.lineFragmentPadding ?? 5
        let maxWidth = max(60, bounds.width - 2 * textContainerInset.width - 2 * padding - 2)
        guard size.width > maxWidth, size.width > 0 else { return size }
        return NSSize(width: maxWidth, height: (size.height * maxWidth / size.width).rounded())
    }

    /// Fits every picture to the current width, and gives pictures read from disk their image.
    func fitPictures() {
        guard let storage = textStorage, storage.length > 0 else { return }
        var resized: [NSRange] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            if attachment.image == nil, let data = attachment.fileWrapper?.regularFileContents {
                attachment.image = NSImage(data: data)
            }
            guard let image = attachment.image else { return }
            let size = fittedSize(image.size)
            guard attachment.bounds.size != size else { return }
            attachment.bounds = NSRect(origin: .zero, size: size)
            resized.append(range)
        }
        guard !resized.isEmpty else { return }
        storage.beginEditing()
        for range in resized {
            storage.edited(.editedAttributes, range: range, changeInLength: 0)
        }
        storage.endEditing()
    }
}
