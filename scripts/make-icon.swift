import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let r = CGFloat(pixels)
        let bounds = NSRect(x: r*0.05, y: r*0.05, width: r*0.9, height: r*0.9)
        let path = NSBezierPath(roundedRect: bounds, xRadius: r*0.22, yRadius: r*0.22)
        NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.58, blue: 0.65, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.29, blue: 0.43, alpha: 1))!.draw(in: path, angle: -60)
        NSColor.white.withAlphaComponent(0.45).setFill()
        NSBezierPath(ovalIn: NSRect(x: r*0.51, y: r*0.48, width: r*0.19, height: r*0.19)).fill()
        NSBezierPath(roundedRect: NSRect(x: r*0.46, y: r*0.25, width: r*0.29, height: r*0.19), xRadius: r*0.08, yRadius: r*0.08).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: r*0.29, y: r*0.52, width: r*0.22, height: r*0.22)).fill()
        NSBezierPath(roundedRect: NSRect(x: r*0.22, y: r*0.25, width: r*0.35, height: r*0.22), xRadius: r*0.1, yRadius: r*0.1).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
    }
}
