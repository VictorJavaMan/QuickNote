import AppKit
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
func icon(_ pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 196, yRadius: 196)
    NSGradient(starting: NSColor(calibratedRed: 1, green: 0.84, blue: 0.42, alpha: 1), ending: NSColor(calibratedRed: 0.96, green: 0.58, blue: 0.16, alpha: 1))!.draw(in: tile, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -15); shadow.set()
    NSColor(calibratedRed: 1, green: 0.98, blue: 0.89, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 258, y: 210, width: 485, height: 620), xRadius: 48, yRadius: 48).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(calibratedRed: 0.81, green: 0.69, blue: 0.47, alpha: 1).setStroke()
    for y in [660, 556, 452] {
        let line = NSBezierPath(); line.lineWidth = 24; line.lineCapStyle = .round
        line.move(to: NSPoint(x: 340, y: y)); line.line(to: NSPoint(x: 652, y: y)); line.stroke()
    }
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform(); transform.translateX(by: 686, yBy: 395); transform.rotate(byDegrees: -38); transform.concat()
    NSColor(calibratedWhite: 0.17, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: -44, y: -110, width: 88, height: 340), xRadius: 17, yRadius: 17).fill()
    let tip = NSBezierPath(); tip.move(to: NSPoint(x: -44, y: -122)); tip.line(to: NSPoint(x: 44, y: -122)); tip.line(to: NSPoint(x: 0, y: -198)); tip.close(); tip.fill()
    NSColor.white.withAlphaComponent(0.4).setFill()
    NSBezierPath(roundedRect: NSRect(x: -27, y: -88, width: 9, height: 260), xRadius: 4, yRadius: 4).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(size)x\(size)\(suffix).png"
        try icon(size * scale).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(filename))
    }
}
