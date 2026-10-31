import AppKit
import UniformTypeIdentifiers

/// A picture or a file in the scratchpad. The file wrapper holds the real bytes and name,
/// and that is what gets saved. The attachment's `image` is never set: with it, saving
/// writes a re-encoded PNG named "Attachment.png" and drops anything that is not a picture.
/// So this draws itself: pictures shrunk to fit the width, other files as a chip.
final class ScratchAttachment: NSTextAttachment {
    /// Bigger files stay out. The whole note is held in memory and saved as one file.
    static let maxFileSize = 100 * 1024 * 1024

    private lazy var picture: NSImage? = {
        guard let type = UTType(filenameExtension: (filename as NSString).pathExtension), type.conforms(to: .image),
              let data = fileWrapper?.regularFileContents
        else { return nil }
        return NSImage(data: data)
    }()
    private var rendered: (key: String, image: NSImage)?

    static func make(data: Data, filename: String) -> ScratchAttachment {
        let file = FileWrapper(regularFileWithContents: data)
        file.preferredFilename = filename
        return make(fileWrapper: file)
    }

    /// A file from Finder, a drag or a paste. Nil for folders and files over `maxFileSize`.
    static func make(contentsOf url: URL) -> ScratchAttachment? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) <= maxFileSize,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return make(data: data, filename: url.lastPathComponent)
    }

    /// Attachments read from disk come back as plain NSTextAttachments.
    static func make(from attachment: NSTextAttachment) -> ScratchAttachment? {
        if let existing = attachment as? ScratchAttachment { return existing }
        if let file = attachment.fileWrapper, file.isRegularFile { return make(fileWrapper: file) }
        guard let data = attachment.contents else { return nil }
        let ext = attachment.fileType.flatMap { UTType($0)?.preferredFilenameExtension } ?? "dat"
        return make(data: data, filename: "Attachment.\(ext)")
    }

    private static func make(fileWrapper: FileWrapper) -> ScratchAttachment {
        let attachment = ScratchAttachment(fileWrapper: fileWrapper)
        attachment.allowsTextAttachmentView = false
        return attachment
    }

    var filename: String {
        let name = fileWrapper?.preferredFilename ?? fileWrapper?.filename ?? ""
        return name.isEmpty ? "Attachment" : name
    }

    var data: Data? { fileWrapper?.regularFileContents }

    /// The picture, if this is one. Other files (PDFs too) show as a chip.
    /// Not `image`: that is NSTextAttachment's own, which must stay empty (see above).
    var pictureImage: NSImage? { picture }
    var isPicture: Bool { picture != nil }

    /// Writes a copy to a temporary folder, under its own name, for dragging out, copying
    /// as a file or opening.
    func exportToTemporaryFile() -> URL? {
        guard let data else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scratchpad", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Size and drawing

    private func size(forWidth available: CGFloat) -> NSSize {
        if let picture {
            let natural = picture.size
            guard natural.width > available, natural.width > 0 else { return natural }
            return NSSize(width: available, height: (natural.height * available / natural.width).rounded())
        }
        return NSSize(width: min(available, 280), height: 44)
    }

    private func availableWidth(_ container: NSTextContainer?, _ lineFragment: CGRect) -> CGFloat {
        let padding = container?.lineFragmentPadding ?? 5
        return max(60, (container?.size.width ?? lineFragment.width) - 2 * padding - 2)
    }

    /// A bitmap at exactly the size shown. TextKit 2 draws attachment images at their own
    /// size (a big picture comes out cropped) and skips images that draw on demand.
    private func drawing(for size: NSSize, in container: NSTextContainer?) -> NSImage? {
        let view = container?.textView
        let appearance = view?.effectiveAppearance ?? NSApp.effectiveAppearance
        let scale = view?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let key = "\(size.width)x\(size.height)@\(scale) \(appearance.name.rawValue)"
        if let cached = rendered, cached.key == key { return cached.image }
        guard size.width >= 1, size.height >= 1,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        appearance.performAsCurrentDrawingAppearance {
            let rect = NSRect(origin: .zero, size: size)
            if let picture {
                picture.draw(in: rect)
            } else {
                drawChip(in: rect)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        rendered = (key, image)
        return image
    }

    /// macOS gives file attachments a cell that draws the file at its own size (a big picture
    /// comes out cropped, a PDF not at all). Without one, the methods below are used.
    override var attachmentCell: (any NSTextAttachmentCellProtocol)? {
        get { nil }
        set {}
    }

    // TextKit 2, which the scratchpad uses.
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        CGRect(origin: .zero, size: size(forWidth: availableWidth(textContainer, proposedLineFragment)))
    }

    override func image(
        for bounds: CGRect,
        attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSImage? {
        drawing(for: bounds.size, in: textContainer)
    }

    // TextKit 1, in case the text view ever falls back to it.
    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        CGRect(origin: .zero, size: size(forWidth: availableWidth(textContainer, lineFrag)))
    }

    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> NSImage? {
        drawing(for: imageBounds.size, in: textContainer)
    }

    /// "PDF · 1.2 MB"
    private var detail: String {
        let ext = (filename as NSString).pathExtension.uppercased()
        let size = ByteCountFormatter.string(fromByteCount: Int64(data?.count ?? 0), countStyle: .file)
        return ext.isEmpty ? size : "\(ext) · \(size)"
    }

    /// Icon, name and size in a rounded box.
    private func drawChip(in rect: NSRect) {
        let box = rect.insetBy(dx: 0.5, dy: 2.5)
        let path = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
        let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data)
        icon.draw(in: NSRect(x: box.minX + 6, y: box.midY - 15, width: 30, height: 30))

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let textX = box.minX + 42
        let textWidth = box.maxX - textX - 8
        NSAttributedString(string: filename, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]).draw(in: NSRect(x: textX, y: box.maxY - 21, width: textWidth, height: 16))
        NSAttributedString(string: detail, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]).draw(in: NSRect(x: textX, y: box.maxY - 37, width: textWidth, height: 15))
    }
}

/// Dragging out only copies: the scratchpad keeps its own copy.
final class DragOutSource: NSObject, NSDraggingSource {
    static let shared = DragOutSource()

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
