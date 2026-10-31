// Draws the app icon: a glass note hanging under a menu bar icon, on a colorful plate.
// Run it after changing the design, and commit Resources/AppIcon.icns:
//   swift scripts/app-icon.swift build/AppIcon.iconset
//   iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
// The shape follows Apple's macOS icon grid: an 824pt rounded square on a 1024pt canvas.
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
  FileHandle.standardError.write("usage: app-icon.swift out.iconset\n".data(using: .utf8)!)
  exit(1)
}
let iconset = URL(fileURLWithPath: args[1])
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
          blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
  NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

extension NSBezierPath {
  func fill(using color: NSColor) {
    color.setFill()
    fill()
  }
}

func draw(pixels: Int) -> Data {
  let scale = CGFloat(pixels) / 1024
  let ctx = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  // Top-left origin, in points of the 1024 canvas.
  ctx.scaleBy(x: scale, y: scale)
  ctx.translateBy(x: 0, y: 1024)
  ctx.scaleBy(x: 1, y: -1)
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

  // Plate, with Apple's drop shadow (shadow offsets ignore the flip and the scale)
  let plateRect = CGRect(x: 100, y: 100, width: 824, height: 824)
  let plate = roundedRect(plateRect, 185)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale,
                color: rgb(0x000000, 0.3).cgColor)
  rgb(0x5B4BE0).setFill()
  plate.fill()
  ctx.restoreGState()

  ctx.saveGState()
  plate.addClip()
  NSGradient(colors: [rgb(0xFF8F6B), rgb(0xC659E6), rgb(0x4F5BF0)])!
    .draw(in: plateRect, angle: -60)
  // Soft blobs of light, so the glass has something to show through
  for (center, radius, color) in [
    (CGPoint(x: 300, y: 640), CGFloat(260), rgb(0xFFD36B, 0.75)),
    (CGPoint(x: 760, y: 420), CGFloat(240), rgb(0x46D6F5, 0.6)),
  ] {
    NSGradient(starting: color, ending: color.withAlphaComponent(0))!
      .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
  }

  // Menu bar across the top, with the note icon highlighted like an open menu
  NSBezierPath(rect: CGRect(x: 100, y: 100, width: 824, height: 104)).fill(using: rgb(0xFFFFFF, 0.28))
  let pill = CGRect(x: 650, y: 122, width: 104, height: 60)
  roundedRect(pill, 30).fill(using: rgb(0xFFFFFF, 0.55))
  let noteIcon = CGRect(x: pill.midX - 20, y: pill.midY - 22, width: 40, height: 44)
  rgb(0x2A1F5C).setStroke()
  let noteOutline = roundedRect(noteIcon, 8)
  noteOutline.lineWidth = 6
  noteOutline.stroke()
  for y in [noteIcon.minY + 15, noteIcon.minY + 29] {
    roundedRect(CGRect(x: noteIcon.minX + 9, y: y - 2.5, width: 22, height: 5), 2.5).fill(using: rgb(0x2A1F5C))
  }
  ctx.restoreGState()

  // Glass note under the icon: frosted fill, bright rim, soft shadow
  let card = CGRect(x: 236, y: 252, width: 560, height: 584)
  let cardPath = roundedRect(card, 64)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 40 * scale,
                color: rgb(0x26105C, 0.35).cgColor)
  cardPath.fill(using: rgb(0xFFFFFF, 0.42))
  ctx.restoreGState()
  ctx.saveGState()
  cardPath.addClip()
  NSGradient(starting: rgb(0xFFFFFF, 0.45), ending: rgb(0xFFFFFF, 0.08))!
    .draw(in: card, angle: -90)
  ctx.restoreGState()
  rgb(0xFFFFFF, 0.85).setStroke()
  let rim = roundedRect(card.insetBy(dx: 3, dy: 3), 61)
  rim.lineWidth = 6
  rim.stroke()

  // Title, a line under it, then scribbled notes
  let ink = rgb(0x2A1F5C, 0.85)
  roundedRect(CGRect(x: card.minX + 56, y: card.minY + 64, width: 220, height: 34), 17).fill(using: ink)
  NSBezierPath(rect: CGRect(x: card.minX + 48, y: card.minY + 136, width: card.width - 96, height: 4)).fill(using: rgb(0x2A1F5C, 0.18))
  for (index, width) in [380.0, 300.0, 410.0, 240.0].enumerated() {
    let y = card.minY + 186 + CGFloat(index) * 74
    roundedRect(CGRect(x: card.minX + 56, y: y, width: width, height: 26), 13).fill(using: rgb(0x2A1F5C, 0.5))
  }

  let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
  return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
  try! draw(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
  try! draw(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
