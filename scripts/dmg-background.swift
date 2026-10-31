// Draws the DMG window background: a title, an arrow from the app to Applications,
// and a card about the first open.
//   swift scripts/dmg-background.swift out.png 2    (scale 1 or 2)
// Sizes and icon spots must match scripts/dmg-settings.py.
// Finder draws icon labels black on a background picture, even in Dark Mode, so it is light.
// The window height includes the title bar (about 30pt), so the bottom of the picture is
// hidden: keep everything above `visibleHeight`.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let scale = Double(args[2]) else {
  FileHandle.standardError.write("usage: dmg-background.swift out.png scale\n".data(using: .utf8)!)
  exit(1)
}
let size = CGSize(width: 600, height: 420)
let visibleHeight: CGFloat = 386
let iconY: CGFloat = 168
let appX: CGFloat = 150
let applicationsX: CGFloat = 450

let ctx = CGContext(
  data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin, like Finder icon positions.
ctx.scaleBy(x: scale, y: scale)
ctx.translateBy(x: 0, y: size.height)
ctx.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
          blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}
let blue = rgb(0x2F6FE4)
let ink = rgb(0x1D1D1F)
let secondaryInk = rgb(0x5A6070)

func draw(_ text: String, in rect: CGRect, font: NSFont, color: NSColor,
          alignment: NSTextAlignment = .center) {
  let para = NSMutableParagraphStyle()
  para.alignment = alignment
  NSAttributedString(string: text, attributes: [
    .font: font, .foregroundColor: color, .paragraphStyle: para,
  ]).draw(in: rect)
}

// Background
NSGradient(starting: rgb(0xF8FAFE), ending: rgb(0xE4ECFA))!
  .draw(in: CGRect(x: 0, y: 0, width: size.width, height: visibleHeight), angle: 90)
rgb(0xE4ECFA).setFill()
CGRect(x: 0, y: visibleHeight, width: size.width, height: size.height - visibleHeight).fill()

// Title
draw("Drag Scratchpad to Applications", in: CGRect(x: 0, y: 34, width: size.width, height: 30),
     font: .systemFont(ofSize: 20, weight: .semibold), color: ink)

// Soft light behind each icon
for x in [appX, applicationsX] {
  NSGradient(starting: rgb(0xFFFFFF, 0.9), ending: rgb(0xFFFFFF, 0))!
    .draw(fromCenter: CGPoint(x: x, y: iconY), radius: 0,
          toCenter: CGPoint(x: x, y: iconY), radius: 100, options: [])
}

// Arrow: a dotted trail and a chevron head
blue.setStroke()
let startX = appX + 88, tipX = applicationsX - 88
let trail = NSBezierPath()
trail.move(to: CGPoint(x: startX, y: iconY))
trail.line(to: CGPoint(x: tipX - 14, y: iconY))
trail.lineWidth = 7
trail.lineCapStyle = .round
trail.setLineDash([0.1, 17], count: 2, phase: 0)
trail.stroke()

let head = NSBezierPath()
head.move(to: CGPoint(x: tipX - 20, y: iconY - 20))
head.line(to: CGPoint(x: tipX, y: iconY))
head.line(to: CGPoint(x: tipX - 20, y: iconY + 20))
head.lineWidth = 7
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

// First-open card: the app is not notarized, so macOS blocks it until "Open Anyway".
let card = CGRect(x: 46, y: 290, width: 508, height: 60)
let cardPath = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
rgb(0xFFFFFF, 0.85).setFill()
cardPath.fill()
rgb(0xD3DDEE).setStroke()
cardPath.lineWidth = 1
cardPath.stroke()

let symbol = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: nil)!
  .withSymbolConfiguration(.init(pointSize: 22, weight: .regular).applying(.init(paletteColors: [.white, blue])))!
let symbolSize = symbol.size
symbol.draw(in: CGRect(x: card.minX + 17, y: card.midY - symbolSize.height / 2,
                       width: symbolSize.width, height: symbolSize.height),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

let textX = card.minX + 52
draw("Not notarized, so macOS blocks the first open", in: CGRect(x: textX, y: card.minY + 11, width: card.maxX - textX - 12, height: 20),
     font: .systemFont(ofSize: 13, weight: .semibold), color: ink, alignment: .left)
draw("Click Done, then System Settings → Privacy & Security → Open Anyway",
     in: CGRect(x: textX, y: card.minY + 31, width: card.maxX - textX - 12, height: 20),
     font: .systemFont(ofSize: 12, weight: .regular), color: secondaryInk, alignment: .left)

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = size
try! rep.representation(using: .png, properties: [:])!
  .write(to: URL(fileURLWithPath: args[1]))
