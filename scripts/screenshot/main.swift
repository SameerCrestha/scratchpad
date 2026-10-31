// Takes the README pictures, light and dark, using the app's real views:
//   docs/panel-*.png     the scratchpad on a made-up desktop (screencapture, so the glass is real)
//   docs/settings-*.png  the settings window
// Run through scripts/screenshot.sh. It flashes a few windows on screen for a second each.
import AppKit
import SwiftUI

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
NSApplication.shared.setActivationPolicy(.accessory)
NSApp.applicationIconImage = NSImage(contentsOfFile: "Resources/AppIcon.icns")

let prefs = Preferences.shared
prefs.loginItemStatus = .enabled

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func wait(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

// MARK: Scratchpad on a desktop

let sceneSize = NSSize(width: 600, height: 480)
let menuBarHeight: CGFloat = 30
let iconX: CGFloat = 220

/// A colorful wallpaper with a strip of menu bar and the note icon highlighted.
func desktop(dark: Bool) -> NSImage {
    NSImage(size: sceneSize, flipped: true) { rect in
        let colors = dark ? [rgb(0x1B1446), rgb(0x5A2A82), rgb(0x0F3D6E)] : [rgb(0xFF9A76), rgb(0xD06BE8), rgb(0x5B7CF5)]
        NSGradient(colors: colors)!.draw(in: rect, angle: -35)
        for (center, radius, color) in [
            (CGPoint(x: 180, y: 380), CGFloat(260), dark ? rgb(0xE0567A, 0.55) : rgb(0xFFD36B, 0.8)),
            (CGPoint(x: 480, y: 280), CGFloat(240), dark ? rgb(0x2FA6D9, 0.45) : rgb(0x46D6F5, 0.6)),
        ] {
            NSGradient(starting: color, ending: color.withAlphaComponent(0))!
                .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
        }
        (dark ? rgb(0x000000, 0.35) : rgb(0xFFFFFF, 0.35)).setFill()
        NSRect(x: 0, y: 0, width: rect.width, height: menuBarHeight).fill()
        let pill = NSRect(x: iconX, y: 4, width: 32, height: menuBarHeight - 8)
        (dark ? rgb(0xFFFFFF, 0.25) : rgb(0x000000, 0.12)).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        let symbol = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)
                .applying(.init(paletteColors: [dark ? .white : .black])))!
        symbol.draw(in: NSRect(x: pill.midX - symbol.size.width / 2, y: pill.midY - symbol.size.height / 2,
                               width: symbol.size.width, height: symbol.size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        return true
    }
}

/// A small made-up photo, to show a pasted picture.
func samplePicture() -> NSImage {
    NSImage(size: NSSize(width: 600, height: 240), flipped: false) { rect in
        NSGradient(starting: rgb(0xFFB36B), ending: rgb(0x6B8CFF))!.draw(in: rect, angle: 90)
        rgb(0xFFF1C2).setFill()
        NSBezierPath(ovalIn: NSRect(x: 380, y: 90, width: 90, height: 90)).fill()
        rgb(0x2E3A6B, 0.85).setFill()
        let hills = NSBezierPath()
        hills.move(to: .zero)
        hills.curve(to: NSPoint(x: 600, y: 40), controlPoint1: NSPoint(x: 200, y: 160), controlPoint2: NSPoint(x: 380, y: -20))
        hills.line(to: NSPoint(x: 600, y: 0))
        hills.close()
        hills.fill()
        return true
    }
}

func sampleNotes() -> NSAttributedString {
    let text = NSMutableAttributedString(string: """
    Call Alex back about the invoice
    Wifi: Garden-5G / sunflower42
    ⌃⇧⌘4 copies a screenshot, ⌘V pastes it:

    """)
    let tiff = samplePicture().tiffRepresentation!
    let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    text.append(NSAttributedString(attachment: ScratchAttachment.make(data: png, filename: "Sunset.png")))
    text.append(NSAttributedString(string: "\nBoarding pass, drag it to Mail:\n"))
    let pdf = Data(count: 248_000)
    text.append(NSAttributedString(attachment: ScratchAttachment.make(data: pdf, filename: "Boarding pass.pdf")))
    return text
}

func capturePanel(dark: Bool, to name: String) {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let screen = NSScreen.main!.visibleFrame
    // Top-left corner: system prompts and alerts show up in the middle.
    let scene = NSRect(x: screen.minX, y: screen.maxY - sceneSize.height,
                       width: sceneSize.width, height: sceneSize.height)

    let backdrop = NSWindow(contentRect: scene, styleMask: .borderless, backing: .buffered, defer: false)
    backdrop.level = .floating
    backdrop.appearance = appearance
    let imageView = NSImageView(frame: NSRect(origin: .zero, size: sceneSize))
    imageView.image = desktop(dark: dark)
    imageView.imageScaling = .scaleAxesIndependently
    backdrop.contentView = imageView

    let size = NSSize(width: 340, height: 400)
    let panel = ScratchpadPanel.make(size: size)
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    panel.appearance = appearance
    let board = BoardView(frame: NSRect(origin: .zero, size: size))
    panel.contentView = makeBackground(size: size, content: board)
    board.setPinned(true)
    let top = scene.maxY - menuBarHeight - 5
    panel.setFrameOrigin(NSPoint(x: scene.minX + iconX - 8, y: top - size.height))
    panel.contentView?.layoutSubtreeIfNeeded()
    board.textView.setContents(sampleNotes())

    backdrop.orderFrontRegardless()
    panel.orderFrontRegardless()
    wait(1.2)

    // screencapture counts from the top-left of the main display.
    let flippedY = NSScreen.screens[0].frame.maxY - scene.maxY
    let rect = "\(Int(scene.minX)),\(Int(flippedY)),\(Int(scene.width)),\(Int(scene.height))"
    let url = outputDir.appendingPathComponent(name)
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-R", rect, url.path]
    try! capture.run()
    capture.waitUntilExit()
    print("Wrote \(url.path)")
    panel.orderOut(nil)
    backdrop.orderOut(nil)
}

// MARK: Settings window

func renderSettings(dark: Bool, to name: String) {
    let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(prefs: prefs)))
    window.title = "Scratchpad Settings"
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
    // Switches only draw their "on" color in the key window of the active app.
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    wait(0.6)

    guard let frameView = window.contentView?.superview else { fatalError("no frame view") }
    let size = frameView.bounds.size
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    frameView.cacheDisplay(in: frameView.bounds, to: rep)
    let url = outputDir.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("Wrote \(url.path)")
    window.close()
}

capturePanel(dark: false, to: "panel-light.png")
capturePanel(dark: true, to: "panel-dark.png")
renderSettings(dark: false, to: "settings-light.png")
renderSettings(dark: true, to: "settings-dark.png")
exit(0)
