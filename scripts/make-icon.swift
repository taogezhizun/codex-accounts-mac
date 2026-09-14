import AppKit

// An original exchange-rail mark. All sizes are rendered from vector geometry,
// not downsampled from a screenshot or an AI-generated image.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let root = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func drawIcon(in rect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform(); transform.translateX(by: rect.minX, yBy: rect.minY); transform.scale(by: rect.width); transform.concat()
    let plate = NSBezierPath(roundedRect: NSRect(x: 0.065, y: 0.065, width: 0.87, height: 0.87), xRadius: 0.205, yRadius: 0.205)
    let shadow = NSShadow(); shadow.shadowColor = color(0.08, 0.16, 0.40, 0.23); shadow.shadowBlurRadius = 0.025; shadow.shadowOffset = NSSize(width: 0, height: -0.014)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    color(0.18, 0.30, 0.72).setFill(); plate.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0.34, 0.48, 0.91), color(0.21, 0.36, 0.80), color(0.12, 0.25, 0.63)])!.draw(in: plate, angle: -65)
    let rim = NSBezierPath(roundedRect: NSRect(x: 0.072, y: 0.072, width: 0.856, height: 0.856), xRadius: 0.2, yRadius: 0.2)
    color(1, 1, 1, 0.22).setStroke(); rim.lineWidth = 0.006; rim.stroke()
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: 1-y) }
    func rail(top: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { top ? point(x, y) : point(1-x, 1-y) }
        path.move(to: p(0.245, 0.455)); path.line(to: p(0.245, 0.35))
        path.curve(to: p(0.345, 0.25), controlPoint1: p(0.245, 0.295), controlPoint2: p(0.29, 0.25))
        path.line(to: p(0.755, 0.25))
        path.move(to: p(0.635, 0.13)); path.line(to: p(0.755, 0.25)); path.line(to: p(0.635, 0.37))
        path.lineWidth = 0.075; path.lineCapStyle = .round; path.lineJoinStyle = .round
        return path
    }
    let markShadow = NSShadow(); markShadow.shadowColor = color(0.04, 0.13, 0.39, 0.22); markShadow.shadowBlurRadius = 0.012; markShadow.shadowOffset = NSSize(width: 0, height: -0.01)
    NSGraphicsContext.saveGraphicsState(); markShadow.set()
    color(0.99, 1, 1).setStroke(); rail(top: true).stroke()
    color(0.77, 0.85, 1).setStroke(); rail(top: false).stroke()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
}

func bitmap(width: Int, height: Int, drawing: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawing(); NSGraphicsContext.restoreGraphicsState()
    return rep
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = bitmap(width: pixels, height: pixels) { drawIcon(in: NSRect(x: 0, y: 0, width: pixels, height: pixels)) }
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
    }
}

// Shareable review board contains no account, device or workspace information.
let board = bitmap(width: 960, height: 520) {
    color(0.956, 0.966, 0.985).setFill(); NSRect(x: 0, y: 0, width: 960, height: 520).fill()
    func label(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, foreground: NSColor = .secondaryLabelColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: foreground])
    }
    label("Codex Switcher", at: NSPoint(x: 44, y: 448), size: 27, weight: .semibold, foreground: color(0.08, 0.13, 0.23))
    label("A native switch, in both directions.", at: NSPoint(x: 45, y: 418), size: 14)
    drawIcon(in: NSRect(x: 48, y: 55, width: 330, height: 330))
    color(0.10, 0.13, 0.21).setFill(); NSBezierPath(roundedRect: NSRect(x: 438, y: 180, width: 476, height: 194), xRadius: 22, yRadius: 22).fill()
    for (offset, size) in [(470, 128), (652, 64), (779, 32), (862, 16)] {
        drawIcon(in: NSRect(x: offset, y: 280-size/2, width: size, height: size))
        label("\(size) px", at: NSPoint(x: offset, y: 196), size: 11, foreground: color(0.69, 0.75, 0.85))
    }
    label("One mark. Every size.", at: NSPoint(x: 453, y: 122), size: 18, weight: .medium, foreground: color(0.16, 0.23, 0.36))
    label("Original vector artwork · No third-party icon assets", at: NSPoint(x: 453, y: 91), size: 12)
}
try board.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("IconPreview.png"))
