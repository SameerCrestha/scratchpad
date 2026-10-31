import AppKit
import QuartzCore

/// The shape of the genie effect, shared by the app and the README GIF. y grows upward.
/// The panel first bends into a funnel whose neck is the menu bar icon, then flows up
/// through it. Progress 0 is the whole panel, 1 is inside the icon.
struct GenieShape {
    let panel: CGRect
    /// A thin rect at the icon: the funnel's neck.
    let target: CGRect

    struct Strip {
        /// The slice of the picture, 0 at its bottom and 1 at its top.
        let from: CGFloat
        let to: CGFloat
        let rect: CGRect
    }

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// First the sides bend in, then everything slides into the icon, speeding up.
    private func phases(_ progress: Double) -> (bend: CGFloat, slide: CGFloat) {
        let b = Self.clamp(progress / 0.45)
        let s = Self.clamp((progress - 0.3) / 0.7)
        return (CGFloat(b * b * (3 - 2 * b)), CGFloat(s * s))
    }

    /// Where a row of the picture is, `v` from 0 (bottom) to 1 (top). Rows that reach the
    /// neck stay there, squeezed to nothing.
    private func y(_ v: CGFloat, slide: CGFloat) -> CGFloat {
        let neck = target.midY
        return min(panel.minY + v * panel.height + (neck - panel.minY) * slide, neck)
    }

    /// The funnel's sides at height `y`: the panel's width at its bottom, the icon's at the neck.
    private func edges(_ y: CGFloat, bend: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let span = target.midY - panel.minY
        let s = span > 0 ? min(max((y - panel.minY) / span, 0), 1) : 1
        let k = bend * (1 - cos(.pi * s)) / 2
        return (panel.minX + (target.minX - panel.minX) * k, panel.maxX + (target.maxX - panel.maxX) * k)
    }

    func strips(_ progress: Double, count: Int = 64) -> [Strip] {
        let (bend, slide) = phases(progress)
        var strips: [Strip] = []
        for k in 0 ..< count {
            let from = CGFloat(k) / CGFloat(count)
            let to = CGFloat(k + 1) / CGFloat(count)
            let bottom = y(from, slide: slide)
            let top = y(to, slide: slide)
            guard top - bottom > 0.05 else { continue }
            let (left, right) = edges((bottom + top) / 2, bend: bend)
            // A hair taller, so neighbouring strips leave no gap.
            strips.append(Strip(from: from, to: to, rect: CGRect(x: left, y: bottom - 0.3, width: right - left, height: top - bottom + 0.6)))
        }
        return strips
    }

    /// The outline: up the left side, down the right.
    func outline(_ progress: Double, count: Int = 64) -> [CGPoint] {
        let (bend, slide) = phases(progress)
        let rows = (0 ... count).map { y(CGFloat($0) / CGFloat(count), slide: slide) }
        let left = rows.map { CGPoint(x: edges($0, bend: bend).left, y: $0) }
        let right = rows.reversed().map { CGPoint(x: edges($0, bend: bend).right, y: $0) }
        return left + right
    }

    /// How far the sides have bent in, 0 to 1.
    func bend(_ progress: Double) -> CGFloat { phases(progress).bend }

    /// Fades a little at the very end, as it disappears into the icon.
    func alpha(_ progress: Double) -> CGFloat {
        let x = Self.clamp((progress - 0.75) / 0.25)
        return 1 - 0.7 * CGFloat(x * x * (3 - 2 * x))
    }
}

/// Plays the genie effect in a window of its own: the same glass as the panel, clipped to the
/// funnel, with a picture of the scratchpad drawn in strips. Hold Shift to see it in slow
/// motion, like macOS.
final class GenieAnimation: NSObject {
    static var duration: TimeInterval = 0.5

    private let window: NSWindow
    private let background: NSView
    private let setCornerRadius: (CGFloat) -> Void
    private let funnel = CAShapeLayer()
    private let view: GenieView
    private let opening: Bool
    private let completion: () -> Void
    private var timer: Timer?
    private var startTime: CFTimeInterval = 0
    private var length: TimeInterval = 0.5

    init(picture: NSImage, panel: NSRect, icon: NSRect, opening: Bool, level: NSWindow.Level,
         completion: @escaping () -> Void) {
        let frame = panel.union(icon).insetBy(dx: -8, dy: -8)
        let neck = NSRect(x: icon.midX - 10, y: icon.midY - 2, width: 20, height: 4)
        let shape = GenieShape(panel: panel.offsetBy(dx: -frame.minX, dy: -frame.minY),
                               target: neck.offsetBy(dx: -frame.minX, dy: -frame.minY))
        let bounds = NSRect(origin: .zero, size: frame.size)

        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = level
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .regular
            background = glass
            setCornerRadius = { glass.cornerRadius = $0 }
        } else {
            let frosted = NSVisualEffectView(frame: bounds)
            frosted.material = .menu
            frosted.blendingMode = .behindWindow
            frosted.state = .active
            frosted.wantsLayer = true
            frosted.layer?.masksToBounds = true
            background = frosted
            setCornerRadius = { frosted.layer?.cornerRadius = $0 }
        }
        view = GenieView(frame: bounds, picture: picture, shape: shape)
        let container = NSView(frame: bounds)
        container.wantsLayer = true
        funnel.frame = bounds
        container.layer?.mask = funnel
        container.addSubview(background)
        container.addSubview(view)
        window.contentView = container

        self.opening = opening
        self.completion = completion
        super.init()
        update(opening ? 1 : 0)
    }

    func run() {
        window.orderFrontRegardless()
        length = Self.duration * (NSEvent.modifierFlags.contains(.shift) ? 10 : 1)
        startTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        let x = min(1, (CACurrentMediaTime() - startTime) / length)
        update(opening ? 1 - x : x)
        guard x >= 1 else { return }
        timer?.invalidate()
        timer = nil
        completion()
        window.orderOut(nil)
    }

    private func update(_ progress: Double) {
        let outline = CGMutablePath()
        outline.addLines(between: view.shape.outline(progress))
        outline.closeSubpath()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        funnel.path = outline
        CATransaction.commit()
        // The glass fills the funnel's box. At the start that box is the panel, so its rounded
        // corners match; they straighten as the sides bend in.
        background.frame = outline.boundingBoxOfPath
        setCornerRadius(cornerRadius * (1 - view.shape.bend(progress)))
        view.progress = progress
        view.needsDisplay = true
        window.alphaValue = view.shape.alpha(progress)
    }
}

private final class GenieView: NSView {
    let picture: NSImage
    let shape: GenieShape
    var progress = 0.0

    init(frame: NSRect, picture: NSImage, shape: GenieShape) {
        self.picture = picture
        self.shape = shape
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .high
        let size = picture.size
        for strip in shape.strips(progress) {
            let slice = NSRect(x: 0, y: strip.from * size.height, width: size.width, height: (strip.to - strip.from) * size.height)
            picture.draw(in: strip.rect, from: slice, operation: .sourceOver, fraction: 1)
        }
    }
}
