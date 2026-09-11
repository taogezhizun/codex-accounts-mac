import AppKit

// Original installation artwork. The app and Applications icons are real Finder items.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let image = NSImage(size: NSSize(width: 640, height: 400))
func color(_ rgb: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255, alpha: 1)
}
for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640 * scale, pixelsHigh: 400 * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 640, height: 400)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    color(0xF6F7FB).setFill()
    NSRect(x: 0, y: 0, width: 640, height: 400).fill()
    func text(_ value: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: UInt32) {
        (value as NSString).draw(at: NSPoint(x: x, y: 400 - top - size * 1.25), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color(ink)
        ])
    }
    text("安装 Codex Accounts", x: 52, top: 38, size: 24, weight: .semibold, ink: 0x20283D)
    text("将 App 拖入 Applications 文件夹", x: 52, top: 77, size: 14, weight: .regular, ink: 0x657087)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 294, y: 195)); arrow.line(to: NSPoint(x: 346, y: 195))
    arrow.move(to: NSPoint(x: 333, y: 208)); arrow.line(to: NSPoint(x: 346, y: 195)); arrow.line(to: NSPoint(x: 333, y: 182))
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    color(0x5572D8).setStroke(); arrow.stroke()
    text("安装后，从「应用程序」打开。", x: 52, top: 343, size: 13, weight: .regular, ink: 0x657087)
    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(rep)
}
try image.tiffRepresentation!.write(to: destination)
