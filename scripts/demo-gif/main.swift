// Draws docs/demo.gif for the README: open the scratchpad, type, paste a screenshot, view it
// big, pin, drop a file in, drag it out to Mail, put it away. A drawing, not a screen
// recording, but the scratchpad itself is the app's real BoardView.
// Run through scripts/demo-gif.sh. Mostly flat colors: GIF has 256 colors per frame.
import AppKit
import CoreImage
import UniformTypeIdentifiers

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1.5)
NSApplication.shared.setActivationPolicy(.accessory)
NSApp.appearance = NSAppearance(named: .darkAqua)

let size = CGSize(width: 720, height: 450)
let frameTime = 0.04

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func smoothstep(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
    CGRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t),
           width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
}

/// A bitmap context with a top-left origin, in points.
func makeContext(_ size: CGSize) -> CGContext {
    let ctx = CGContext(
        data: nil, width: Int((size.width * scale).rounded()), height: Int((size.height * scale).rounded()),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    return ctx
}

/// CGContext draws images upside down in a flipped context, so flip them back.
func draw(_ image: CGImage, in rect: CGRect, _ ctx: CGContext, alpha: CGFloat = 1) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

func draw(_ image: NSImage, in rect: CGRect, alpha: CGFloat = 1) {
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
}

func text(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = .white, alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph,
    ]).draw(in: rect)
}

func symbol(_ name: String, _ pointSize: CGFloat, color: NSColor = .white) -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular).applying(.init(paletteColors: [color])))!
}

// MARK: Layout

let menuBarHeight: CGFloat = 24
let noteIcon = CGRect(x: 428, y: 2, width: 26, height: 20)
let panelRect = CGRect(x: 410, y: menuBarHeight + 5, width: 300, height: 330)
let desktopFile = CGPoint(x: 70, y: 62)
let mailRect = CGRect(x: 24, y: 150, width: 300, height: 226)
let mailDrop = CGRect(x: mailRect.minX + 16, y: mailRect.maxY - 64, width: mailRect.width - 32, height: 48)
let viewerRect = CGRect(x: 40, y: 34, width: 640, height: 366)

// MARK: Wallpaper, plain and blurred for the glass

func makeWallpaper() -> CGImage {
    let ctx = makeContext(size)
    rgb(0x231A4B).setFill()
    CGRect(origin: .zero, size: size).fill()
    for (center, radius, color) in [
        (CGPoint(x: 140, y: 380), CGFloat(240), rgb(0x6E3A9C)),
        (CGPoint(x: 650, y: 120), CGFloat(220), rgb(0x1D6593)),
        (CGPoint(x: 520, y: 480), CGFloat(170), rgb(0xB24F6A)),
    ] {
        color.setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    }
    return ctx.makeImage()!
}

let wallpaper = makeWallpaper()
let blurredWallpaper: CGImage = {
    let input = CIImage(cgImage: wallpaper).clampedToExtent()
    let blurred = input.applyingGaussianBlur(sigma: Double(22 * scale)).cropped(to: CIImage(cgImage: wallpaper).extent)
    return CIContext().createCGImage(blurred, from: blurred.extent)!
}()

// MARK: The real scratchpad

let boardWindow = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: panelRect.width, height: panelRect.height),
                           styleMask: .borderless, backing: .buffered, defer: false)
boardWindow.appearance = NSAppearance(named: .darkAqua)
boardWindow.isOpaque = false
boardWindow.backgroundColor = .clear
let board = BoardView(frame: CGRect(origin: .zero, size: panelRect.size))
boardWindow.contentView = board
boardWindow.orderFrontRegardless()

let note = "Call Alex back about the invoice"

/// A screenshot of a booking page: too small to read in the scratchpad, easy when big.
func bookingScreenshot() -> Data {
    let image = NSImage(size: NSSize(width: 1400, height: 740), flipped: true) { rect in
        rgb(0xFFFFFF).setFill(); rect.fill()
        // Browser bar
        rgb(0xE9EAEE).setFill(); CGRect(x: 0, y: 0, width: rect.width, height: 64).fill()
        for (i, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            rgb(color).setFill()
            NSBezierPath(ovalIn: CGRect(x: 24 + CGFloat(i) * 28, y: 24, width: 16, height: 16)).fill()
        }
        rgb(0xFFFFFF).setFill()
        rounded(CGRect(x: 440, y: 14, width: 520, height: 36), 10).fill()
        text("flyaway.example/booking/K7Q2PX", in: CGRect(x: 440, y: 21, width: 520, height: 24), size: 18,
             color: rgb(0x55596A), alignment: .center)
        // Page
        rgb(0x2457C2).setFill(); CGRect(x: 0, y: 64, width: rect.width, height: 96).fill()
        text("Booking confirmed", in: CGRect(x: 60, y: 88, width: 800, height: 50), size: 38, weight: .bold)
        text("Ref K7Q2PX", in: CGRect(x: 1000, y: 98, width: 340, height: 34), size: 24, color: rgb(0xD6E2FF), alignment: .right)
        let rows = [("Passenger", "Alex Morgan"), ("Flight", "BA 284"), ("From", "London Heathrow, Terminal 5"),
                    ("To", "San Francisco"), ("Date", "Sat 7 Nov, 11:20"), ("Seat", "32A, window"),
                    ("Gate", "B12, boards 10:40")]
        for (i, (label, value)) in rows.enumerated() {
            let y = 196 + CGFloat(i) * 70
            text(label, in: CGRect(x: 60, y: y, width: 220, height: 34), size: 24, color: rgb(0x6B7080))
            text(value, in: CGRect(x: 280, y: y, width: 620, height: 34), size: 26, weight: .semibold, color: rgb(0x1D1D1F))
            rgb(0xE6E8EF).setFill()
            CGRect(x: 60, y: y + 50, width: 840, height: 2).fill()
        }
        // Boarding pass card with a code
        rgb(0xF2F5FC).setFill()
        rounded(CGRect(x: 960, y: 196, width: 380, height: 470), 20).fill()
        text("Boarding pass", in: CGRect(x: 990, y: 222, width: 320, height: 34), size: 26, weight: .bold, color: rgb(0x1D1D1F))
        rgb(0x1D1D1F).setFill()
        var seed: UInt32 = 7
        for row in 0 ..< 11 {
            for col in 0 ..< 11 {
                seed = seed &* 1_103_515_245 &+ 12345
                let corner = (row < 3 || row > 7) && (col < 3 || col > 7) && !(row > 7 && col > 7)
                guard corner || (seed >> 16) % 2 == 0 else { continue }
                CGRect(x: 1010 + CGFloat(col) * 26, y: 284 + CGFloat(row) * 26, width: 26, height: 26).fill()
            }
        }
        text("Show this at the gate", in: CGRect(x: 990, y: 588, width: 320, height: 30), size: 20, color: rgb(0x6B7080), alignment: .center)
        return true
    }
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return bitmap.representation(using: .png, properties: [:])!
}

let screenshotData = bookingScreenshot()
let screenshotImage = NSImage(data: screenshotData)!
let pictureAttachment = ScratchAttachment.make(data: screenshotData, filename: "Booking.png")
let fileAttachment = ScratchAttachment.make(data: Data(count: 248_000), filename: "Boarding pass.pdf")
let pdfIcon = NSWorkspace.shared.icon(for: .pdf)

struct BoardState: Hashable {
    var typed = 0
    var picture = false
    var file = false
    var pinned = false
}

var boardCache: [BoardState: CGImage] = [:]
var currentBoard: BoardState?

func setBoard(_ state: BoardState) {
    guard currentBoard != state else { return }
    currentBoard = state
    let content = NSMutableAttributedString(string: String(note.prefix(state.typed)))
    if state.picture {
        content.append(NSAttributedString(string: "\n"))
        content.append(NSAttributedString(attachment: pictureAttachment))
    }
    if state.file {
        content.append(NSAttributedString(string: "\n"))
        content.append(NSAttributedString(attachment: fileAttachment))
    }
    board.textView.setContents(content)
    board.setPinned(state.pinned)
    board.layoutSubtreeIfNeeded()
    board.textView.layoutSubtreeIfNeeded()
}

func boardImage(_ state: BoardState) -> CGImage {
    if let cached = boardCache[state] { return cached }
    setBoard(state)
    let bitmap = board.bitmapImageRepForCachingDisplay(in: board.bounds)!
    board.cacheDisplay(in: board.bounds, to: bitmap)
    let image = bitmap.cgImage!
    boardCache[state] = image
    return image
}

/// Where a character of the board's text sits in the scene (top-left origin).
func sceneRect(ofCharacter index: Int, in state: BoardState) -> CGRect {
    setBoard(state)
    let onScreen = board.textView.firstRect(forCharacterRange: NSRange(location: index, length: 0), actualRange: nil)
    return sceneRect(fromBoard: board.convert(boardWindow.convertFromScreen(onScreen), from: nil))
}

func sceneRect(fromBoard rect: CGRect) -> CGRect {
    CGRect(x: panelRect.minX + rect.minX, y: panelRect.minY + panelRect.height - rect.maxY,
           width: rect.width, height: rect.height)
}

func attachmentRect(file: Bool, in state: BoardState) -> CGRect {
    setBoard(state)
    let index = (board.textView.string as NSString).range(of: "\u{FFFC}", options: file ? .backwards : []).location
    let onScreen = board.textView.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil)
    return sceneRect(fromBoard: board.convert(boardWindow.convertFromScreen(onScreen), from: nil))
}

// MARK: Frame state

enum CursorKind { case arrow, hand }

struct Frame {
    var cursor = CGPoint(x: 330, y: 250)
    var cursorKind = CursorKind.arrow
    var click = 0.0
    var iconOn = false
    var panel = 0.0            // 0 hidden, 1 shown
    var minimize = 0.0         // 0 open, 1 inside the icon
    var board = BoardState()
    var caret = false
    var caption: String?
    var captionAlpha: CGFloat = 0
    var keycap: String?
    var keycapAlpha: CGFloat = 0
    var viewer = 0.0           // 0 closed, 1 open
    var drag: (image: NSImage, at: CGPoint)?
    var mail = 0.0
    var mailHighlight = false
    var mailAttachment = false
}

// MARK: Drawing

func drawMenuBar(_ f: Frame) {
    rgb(0x000000, 0.35).setFill()
    CGRect(x: 0, y: 0, width: size.width, height: menuBarHeight).fill()
    draw(symbol("apple.logo", 13), in: CGRect(x: 16, y: 4, width: 13, height: 16))
    text("Finder", in: CGRect(x: 40, y: 4, width: 60, height: 16), size: 13, weight: .bold)
    var x: CGFloat = 92
    for item in ["File", "Edit", "View", "Go", "Window", "Help"] {
        text(item, in: CGRect(x: x, y: 4, width: 60, height: 16), size: 13)
        x += item.count < 4 ? 40 : 58
    }
    if f.iconOn {
        rgb(0xFFFFFF, 0.25).setFill()
        rounded(noteIcon, 5).fill()
    }
    draw(symbol("note.text", 13), in: CGRect(x: noteIcon.midX - 8, y: noteIcon.midY - 7, width: 16, height: 14))
    for (i, name) in ["magnifyingglass", "wifi", "battery.75percent", "switch.2"].enumerated() {
        let image = symbol(name, 13)
        let w = image.size.width, h = image.size.height
        let cx = 480 + CGFloat(i) * 30
        draw(image, in: CGRect(x: cx - w / 2, y: 12 - h / 2, width: w, height: h))
    }
    text("Sat 10:47", in: CGRect(x: 600, y: 4, width: 108, height: 16), size: 13, alignment: .right)
}

func drawDesktopFile() {
    draw(pdfIcon, in: CGRect(x: desktopFile.x - 24, y: desktopFile.y - 24, width: 48, height: 48))
    let shadow = NSShadow()
    shadow.shadowColor = rgb(0x000000, 0.6)
    shadow.shadowBlurRadius = 2
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    NSAttributedString(string: "Boarding pass.pdf", attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white,
        .shadow: shadow, .paragraphStyle: paragraph,
    ]).draw(in: CGRect(x: desktopFile.x - 60, y: desktopFile.y + 26, width: 120, height: 16))
}

func drawTrafficLights(at origin: CGPoint) {
    for (i, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        rgb(color).setFill()
        NSBezierPath(ovalIn: CGRect(x: origin.x + CGFloat(i) * 18, y: origin.y, width: 11, height: 11)).fill()
    }
}

func drawMail(_ f: Frame, _ ctx: CGContext) {
    guard f.mail > 0 else { return }
    ctx.saveGState()
    ctx.setAlpha(CGFloat(f.mail))
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 18 * scale, color: rgb(0x000000, 0.45).cgColor)
    rgb(0x1F1F23).setFill()
    rounded(mailRect, 10).fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    rgb(0x2C2C31).setFill()
    let titleBar = NSBezierPath(roundedRect: CGRect(x: mailRect.minX, y: mailRect.minY, width: mailRect.width, height: 30), xRadius: 10, yRadius: 10)
    titleBar.fill()
    CGRect(x: mailRect.minX, y: mailRect.minY + 20, width: mailRect.width, height: 10).fill()
    drawTrafficLights(at: CGPoint(x: mailRect.minX + 12, y: mailRect.minY + 10))
    text("New Message", in: CGRect(x: mailRect.minX, y: mailRect.minY + 8, width: mailRect.width, height: 16),
         size: 12, weight: .semibold, color: rgb(0xD0D0D5), alignment: .center)
    for (i, (label, value)) in [("To:", "Sam"), ("Subject:", "Trip")].enumerated() {
        let y = mailRect.minY + 40 + CGFloat(i) * 28
        text(label, in: CGRect(x: mailRect.minX + 16, y: y, width: 60, height: 16), size: 12, color: rgb(0x8E8E95))
        text(value, in: CGRect(x: mailRect.minX + 76, y: y, width: 200, height: 16), size: 12, color: rgb(0xE5E5EA))
        rgb(0xFFFFFF, 0.1).setFill()
        CGRect(x: mailRect.minX + 16, y: y + 21, width: mailRect.width - 32, height: 1).fill()
    }
    text("Here is my boarding pass.", in: CGRect(x: mailRect.minX + 16, y: mailRect.minY + 100, width: 260, height: 16),
         size: 12, color: rgb(0xE5E5EA))
    if f.mailHighlight {
        rgb(0x0A84FF, 0.18).setFill()
        rounded(mailDrop, 8).fill()
        rgb(0x0A84FF).setStroke()
        let outline = rounded(mailDrop, 8)
        outline.lineWidth = 2
        outline.stroke()
    }
    if f.mailAttachment {
        draw(pdfIcon, in: CGRect(x: mailDrop.minX + 8, y: mailDrop.midY - 16, width: 32, height: 32))
        text("Boarding pass.pdf", in: CGRect(x: mailDrop.minX + 48, y: mailDrop.midY - 15, width: 200, height: 16),
             size: 12, weight: .medium, color: rgb(0xE5E5EA))
        text("248 KB", in: CGRect(x: mailDrop.minX + 48, y: mailDrop.midY + 1, width: 200, height: 14),
             size: 11, color: rgb(0x8E8E95))
    }
    ctx.restoreGState()
}

/// Glass: the blurred wallpaper, a dark tint and a bright rim, with the real board on top.
func drawPanel(_ f: Frame, _ ctx: CGContext) {
    guard f.panel > 0 else { return }
    let icon = CGRect(x: noteIcon.midX - 10, y: noteIcon.midY - 8, width: 20, height: 16)
    let t = smoothstep(f.minimize)
    let rect = lerp(panelRect, icon, t)
    let alpha = CGFloat(f.panel) * (1 - 0.85 * CGFloat(t))
    let radius = max(4, 12 * (1 - CGFloat(t)))

    ctx.saveGState()
    ctx.setAlpha(alpha)
    if t == 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 24 * scale, color: rgb(0x000000, 0.4).cgColor)
        rgb(0x000000, 0.01).setFill()
        rounded(rect, radius).fill()
        ctx.restoreGState()
    }
    ctx.saveGState()
    rounded(rect, radius).addClip()
    draw(blurredWallpaper, in: CGRect(origin: .zero, size: size), ctx)
    rgb(0x15151B, 0.42).setFill()
    rect.fill()
    ctx.restoreGState()
    rgb(0xFFFFFF, 0.22).setStroke()
    let rim = rounded(rect.insetBy(dx: 0.5, dy: 0.5), radius - 0.5)
    rim.lineWidth = 1
    rim.stroke()
    draw(boardImage(f.board), in: rect, ctx)
    ctx.restoreGState()

    if f.caret, t == 0 {
        let caret = sceneRect(ofCharacter: f.board.typed, in: f.board)
        rgb(0xFFFFFF).setFill()
        CGRect(x: caret.minX, y: caret.minY, width: 1.5, height: max(caret.height, 16)).fill()
    }
}

func drawViewer(_ f: Frame, _ ctx: CGContext) {
    guard f.viewer > 0 else { return }
    let t = smoothstep(f.viewer)
    let from = attachmentRect(file: false, in: f.board)
    let rect = lerp(from, viewerRect, t)
    ctx.saveGState()
    ctx.setAlpha(CGFloat(min(1, f.viewer * 1.5)))
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 30 * scale, color: rgb(0x000000, 0.5).cgColor)
    rgb(0x1E1E22).setFill()
    rounded(rect, 10).fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    let titleHeight = 30 * CGFloat(t)
    if t > 0.5 {
        rgb(0x2C2C31).setFill()
        NSBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: titleHeight), xRadius: 10, yRadius: 10).fill()
        CGRect(x: rect.minX, y: rect.minY + titleHeight - 10, width: rect.width, height: 10).fill()
        drawTrafficLights(at: CGPoint(x: rect.minX + 12, y: rect.minY + 10))
        text("Picture", in: CGRect(x: rect.minX + 80, y: rect.minY + 8, width: 80, height: 16), size: 12, weight: .semibold, color: rgb(0xD0D0D5))
        var x = rect.maxX - 8
        for title in ["Open in Preview", "Copy"] {
            let width: CGFloat = title == "Copy" ? 46 : 108
            x -= width
            let button = CGRect(x: x, y: rect.minY + 6, width: width, height: 19)
            rgb(0x48484E).setFill()
            rounded(button, 5).fill()
            text(title, in: button.insetBy(dx: 0, dy: 2), size: 11, color: rgb(0xE5E5EA), alignment: .center)
            x -= 6
        }
    }
    let content = CGRect(x: rect.minX, y: rect.minY + titleHeight, width: rect.width, height: rect.height - titleHeight)
    let fit = min(content.width / screenshotImage.size.width, content.height / screenshotImage.size.height)
    let pictureSize = CGSize(width: screenshotImage.size.width * fit, height: screenshotImage.size.height * fit)
    draw(screenshotImage, in: CGRect(x: content.midX - pictureSize.width / 2, y: content.midY - pictureSize.height / 2,
                                     width: pictureSize.width, height: pictureSize.height))
    ctx.restoreGState()
}

func drawCaption(_ f: Frame) {
    guard let caption = f.caption, f.captionAlpha > 0 else { return }
    let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
    let width = (caption as NSString).size(withAttributes: [.font: font]).width + 32
    let pill = CGRect(x: (size.width - width) / 2, y: 406, width: width, height: 30)
    rgb(0x000000, 0.62 * f.captionAlpha).setFill()
    rounded(pill, 15).fill()
    text(caption, in: pill.insetBy(dx: 0, dy: 6), size: 14, weight: .semibold,
         color: rgb(0xFFFFFF, f.captionAlpha), alignment: .center)
}

func drawKeycap(_ f: Frame) {
    guard let key = f.keycap, f.keycapAlpha > 0 else { return }
    let cap = CGRect(x: panelRect.minX - 70, y: panelRect.minY + 150, width: 56, height: 40)
    rgb(0xF2F2F5, f.keycapAlpha).setFill()
    rounded(cap, 8).fill()
    rgb(0xB8B8C0, f.keycapAlpha).setFill()
    rounded(CGRect(x: cap.minX, y: cap.maxY - 4, width: cap.width, height: 4), 2).fill()
    text(key, in: cap.insetBy(dx: 0, dy: 9), size: 16, weight: .semibold, color: rgb(0x1D1D1F, f.keycapAlpha), alignment: .center)
}

func drawCursor(_ f: Frame) {
    if let drag = f.drag {
        draw(drag.image, in: CGRect(x: drag.at.x - 20, y: drag.at.y - 20, width: 40, height: 40), alpha: 0.85)
    }
    if f.click > 0, f.click < 1 {
        let radius = 5 + 15 * CGFloat(f.click)
        rgb(0xFFFFFF, 0.7 * (1 - CGFloat(f.click))).setStroke()
        let ring = NSBezierPath(ovalIn: CGRect(x: f.cursor.x - radius, y: f.cursor.y - radius, width: radius * 2, height: radius * 2))
        ring.lineWidth = 2.5
        ring.stroke()
    }
    let cursor = f.cursorKind == .hand ? NSCursor.pointingHand : NSCursor.arrow
    let image = cursor.image
    draw(image, in: CGRect(x: f.cursor.x - cursor.hotSpot.x, y: f.cursor.y - cursor.hotSpot.y,
                           width: image.size.width, height: image.size.height))
}

func render(_ f: Frame) -> CGImage {
    let ctx = makeContext(size)
    draw(wallpaper, in: CGRect(origin: .zero, size: size), ctx)
    drawDesktopFile()
    drawMail(f, ctx)
    drawMenuBar(f)
    drawPanel(f, ctx)
    drawViewer(f, ctx)
    drawKeycap(f)
    drawCaption(f)
    drawCursor(f)
    return ctx.makeImage()!
}

// MARK: Timeline

var frames: [(Frame, Double)] = []
var s = Frame()

func hold(_ seconds: Double) { frames.append((s, seconds)) }

func animate(_ seconds: Double, _ update: (Double) -> Void) {
    let count = max(1, Int((seconds / frameTime).rounded()))
    for i in 1 ... count {
        update(Double(i) / Double(count))
        frames.append((s, frameTime))
    }
}

/// A gentle curve, the way a hand moves a mouse.
func move(to target: CGPoint, _ seconds: Double = 0.6, bend: CGFloat = 40) {
    let start = s.cursor
    let control = CGPoint(x: (start.x + target.x) / 2 + bend, y: (start.y + target.y) / 2 + bend)
    animate(seconds) { t in
        let k = CGFloat(smoothstep(t))
        s.cursor = CGPoint(x: (1 - k) * (1 - k) * start.x + 2 * (1 - k) * k * control.x + k * k * target.x,
                           y: (1 - k) * (1 - k) * start.y + 2 * (1 - k) * k * control.y + k * k * target.y)
        if let drag = s.drag { s.drag = (drag.image, s.cursor) }
    }
}

func click() {
    animate(0.24) { t in s.click = t }
    s.click = 0
}

func caption(_ text: String) {
    s.caption = text
    animate(0.16) { t in s.captionAlpha = CGFloat(t) }
}

func keycap(_ key: String) {
    s.keycap = key
    animate(0.12) { t in s.keycapAlpha = CGFloat(t) }
}

func hideKeycap() {
    animate(0.16) { t in s.keycapAlpha = CGFloat(1 - t) }
    s.keycap = nil
}

hold(0.8)

// 1. Open
caption("Click the note icon")
move(to: CGPoint(x: noteIcon.midX + 2, y: noteIcon.midY + 2), 0.7)
click()
s.iconOn = true
animate(0.16) { t in s.panel = t }

// 2. Type
caption("Type a note")
s.caret = true
for typed in stride(from: 2, through: note.count, by: 2) {
    s.board.typed = typed
    frames.append((s, 0.06))
}
s.board.typed = note.count
hold(0.6)

// 3. Paste a screenshot
caption("Paste a screenshot")
keycap("⌘V")
hold(0.3)
s.caret = false
s.board.picture = true
hold(0.5)
hideKeycap()
hold(0.4)

// 4. See it big
caption("Click a picture to see it big")
let picture = attachmentRect(file: false, in: s.board)
move(to: CGPoint(x: picture.midX + 20, y: picture.midY), 0.6, bend: -30)
s.cursorKind = .hand
hold(0.2)
click()
animate(0.26) { t in s.viewer = t }
s.cursorKind = .arrow
hold(1.8)
keycap("esc")
hold(0.3)
animate(0.18) { t in s.viewer = 1 - t }
hideKeycap()

// 5. Pin
caption("Pin it to keep it open")
let pin = sceneRect(fromBoard: board.pinButton.frame)
move(to: CGPoint(x: pin.midX, y: pin.midY), 0.6, bend: 20)
click()
s.board.pinned = true
hold(0.8)

// 6. Drop a file in
caption("Drop in a file")
move(to: desktopFile, 0.8, bend: 60)
s.drag = (pdfIcon, s.cursor)
hold(0.15)
let dropPoint = CGPoint(x: panelRect.midX, y: panelRect.maxY - 40)
move(to: dropPoint, 0.9, bend: -40)
s.drag = nil
s.board.file = true
hold(0.9)

// 7. Drag it out to another app
caption("Drag it out to any app")
animate(0.24) { t in s.mail = t }
let chip = attachmentRect(file: true, in: s.board)
move(to: CGPoint(x: chip.minX + 22, y: chip.midY), 0.5)
s.cursorKind = .hand
hold(0.15)
s.drag = (pdfIcon, s.cursor)
s.cursorKind = .arrow
move(to: CGPoint(x: mailDrop.midX, y: mailDrop.midY), 0.9, bend: 30)
s.mailHighlight = true
hold(0.25)
s.drag = nil
s.mailHighlight = false
s.mailAttachment = true
hold(1.1)

// 8. Put it away
caption("Click the icon to put it away")
move(to: CGPoint(x: noteIcon.midX + 2, y: noteIcon.midY + 2), 0.8, bend: -50)
click()
animate(0.26) { t in s.minimize = t }
s.panel = 0
s.minimize = 0
s.iconOn = false
hold(1.2)

// Back to the start
animate(0.3) { t in
    s.captionAlpha = CGFloat(1 - t)
    s.mail = 1 - t
}
s = Frame(cursor: s.cursor)
move(to: Frame().cursor, 0.5)

// MARK: Write the GIF

let gif = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (frame, duration) in frames {
    CGImageDestinationAddImage(gif, render(frame), [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: duration,
            kCGImagePropertyGIFUnclampedDelayTime: duration,
        ],
    ] as CFDictionary)
}
guard CGImageDestinationFinalize(gif) else {
    FileHandle.standardError.write("could not write the GIF\n".data(using: .utf8)!)
    exit(1)
}
print("Wrote \(outURL.path), \(frames.count) frames")
exit(0)
