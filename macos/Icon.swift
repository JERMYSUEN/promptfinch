import AppKit

let target = CommandLine.arguments[1]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(x: Double(pixels) * 0.06, y: Double(pixels) * 0.06, width: Double(pixels) * 0.88, height: Double(pixels) * 0.88)
        NSColor(calibratedRed: 0.14, green: 0.39, blue: 0.31, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: Double(pixels) * 0.20, yRadius: Double(pixels) * 0.20).fill()
        let text: NSString = "P"
        let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: Double(pixels) * 0.65, weight: .semibold), .foregroundColor: NSColor.white]
        let bounds = text.size(withAttributes: style)
        text.draw(at: NSPoint(x: (Double(pixels) - bounds.width) / 2, y: (Double(pixels) - bounds.height) / 2), withAttributes: style)
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: URL(fileURLWithPath: "\(target)/icon_\(size)x\(size)\(suffix).png"))
    }
}
