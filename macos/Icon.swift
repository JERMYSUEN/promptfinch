import AppKit

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawSpark(at point: CGPoint, radius: CGFloat, fill: NSColor) {
    let path = NSBezierPath()
    let inner = radius * 0.24
    path.move(to: CGPoint(x: point.x, y: point.y + radius))
    path.line(to: CGPoint(x: point.x + inner, y: point.y + inner))
    path.line(to: CGPoint(x: point.x + radius, y: point.y))
    path.line(to: CGPoint(x: point.x + inner, y: point.y - inner))
    path.line(to: CGPoint(x: point.x, y: point.y - radius))
    path.line(to: CGPoint(x: point.x - inner, y: point.y - inner))
    path.line(to: CGPoint(x: point.x - radius, y: point.y))
    path.line(to: CGPoint(x: point.x - inner, y: point.y + inner))
    path.close()
    fill.setFill()
    path.fill()
}

// Render the unified PromptFinch blue finch badge matching docs/assets/logo.svg.
let target = CommandLine.arguments[1]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let s = CGFloat(pixels) / 120.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: (120 - y) * s) }
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: bitmap)!
        ctx.shouldAntialias = true
        ctx.imageInterpolation = .high
        NSGraphicsContext.current = ctx

        // Outer soft glow ring
        let outerRing = NSBezierPath(ovalIn: NSRect(x: 4 * s, y: 4 * s, width: 112 * s, height: 112 * s))
        color(0x2979FF, alpha: 0.16).setStroke()
        outerRing.lineWidth = 6 * s
        outerRing.stroke()

        // Deep navy disc
        let discRect = NSRect(x: 9 * s, y: 9 * s, width: 102 * s, height: 102 * s)
        let discPath = NSBezierPath(ovalIn: discRect)
        if let gradient = NSGradient(starting: color(0x152A42), ending: color(0x0B1626)) {
            gradient.draw(in: discPath, relativeCenterPosition: NSPoint(x: -0.2, y: 0.25))
        }

        // Cyan-blue gradient border ring
        NSGraphicsContext.saveGraphicsState()
        let ringStroke = NSBezierPath(ovalIn: NSRect(x: 6 * s, y: 6 * s, width: 108 * s, height: 108 * s))
        let ringInner = NSBezierPath(ovalIn: NSRect(x: 10 * s, y: 10 * s, width: 100 * s, height: 100 * s))
        ringStroke.append(ringInner.reversed)
        ringStroke.windingRule = .evenOdd
        if let ringGradient = NSGradient(starting: color(0x2979FF), ending: color(0x26C6DA)) {
            ringGradient.draw(in: ringStroke, angle: -45)
        }
        NSGraphicsContext.restoreGraphicsState()

        // Sparkles
        drawSpark(at: pt(33, 30), radius: 4.8 * s, fill: color(0x9BE7FF))
        if pixels >= 32 {
            drawSpark(at: pt(96, 66), radius: 3.1 * s, fill: .white)
            drawSpark(at: pt(88, 28), radius: 2.5 * s, fill: color(0x26C6DA))
        }

        // Code prompt glyph </>
        if pixels >= 32 {
            let code = NSBezierPath()
            code.lineWidth = max(1.2, 2.5 * s)
            code.lineCapStyle = .round
            code.lineJoinStyle = .round
            code.move(to: pt(94, 38)); code.line(to: pt(88, 44)); code.line(to: pt(94, 50))
            code.move(to: pt(99, 36)); code.line(to: pt(93, 52))
            code.move(to: pt(103, 38)); code.line(to: pt(109, 44)); code.line(to: pt(103, 50))
            color(0xD6F0FF).setStroke()
            code.stroke()
        }

        // Finch tail
        let tail = NSBezierPath()
        tail.move(to: pt(46, 66))
        tail.curve(to: pt(23, 82), controlPoint1: pt(36, 68), controlPoint2: pt(27, 74))
        tail.curve(to: pt(49, 72), controlPoint1: pt(33, 82), controlPoint2: pt(43, 78))
        tail.close()
        color(0x1E88E5).setFill()
        tail.fill()

        // Finch body & head gradient
        let body = NSBezierPath()
        body.appendOval(in: NSRect(x: 39 * s, y: (120 - 79) * s, width: 36 * s, height: 30 * s))
        body.appendOval(in: NSRect(x: 45 * s, y: (120 - 56) * s, width: 24 * s, height: 24 * s))
        if let birdGrad = NSGradient(starting: color(0x6FD4FF), ending: color(0x1E6FD9)) {
            birdGrad.draw(in: body, angle: -90)
        }

        // Wing
        let wing = NSBezierPath()
        wing.move(to: pt(46, 57))
        wing.curve(to: pt(70, 58), controlPoint1: pt(53, 49), controlPoint2: pt(66, 49))
        wing.curve(to: pt(44, 64), controlPoint1: pt(66, 69), controlPoint2: pt(52, 71))
        wing.curve(to: pt(46, 57), controlPoint1: pt(43, 61), controlPoint2: pt(44, 59))
        wing.close()
        color(0x1E88E5).setFill()
        wing.fill()

        // Crest
        let crest = NSBezierPath()
        crest.move(to: pt(51, 34))
        crest.line(to: pt(49, 27))
        crest.line(to: pt(54, 31.5))
        crest.line(to: pt(56, 25))
        crest.line(to: pt(60, 31.5))
        crest.close()
        color(0x4FC3F7).setFill()
        crest.fill()

        // Beak
        let beak = NSBezierPath()
        beak.move(to: pt(68, 41.5))
        beak.line(to: pt(77, 45))
        beak.line(to: pt(68, 48.5))
        beak.close()
        color(0xE3F2FD).setFill()
        beak.fill()

        // Eye
        color(0xFFFFFF).setFill()
        NSBezierPath(ovalIn: NSRect(x: 60 * s, y: (120 - 43.5) * s, width: 6 * s, height: 6 * s)).fill()
        color(0x0B1626).setFill()
        NSBezierPath(ovalIn: NSRect(x: 62 * s, y: (120 - 42) * s, width: 3 * s, height: 3 * s)).fill()

        // Legs & perch prompt bar
        if pixels >= 32 {
            let legs = NSBezierPath()
            legs.lineWidth = max(1.1, 2.4 * s)
            legs.lineCapStyle = .round
            legs.move(to: pt(54, 79)); legs.line(to: pt(52, 89))
            legs.move(to: pt(62, 79)); legs.line(to: pt(64, 89))
            color(0xE3F2FD).setStroke()
            legs.stroke()

            let perch = NSBezierPath()
            perch.lineWidth = max(1.4, 3.2 * s)
            perch.lineCapStyle = .round
            perch.move(to: pt(38, 93)); perch.line(to: pt(84, 93))
            perch.move(to: pt(38, 93)); perch.line(to: pt(38, 88.5))
            perch.move(to: pt(84, 93)); perch.line(to: pt(84, 88.5))
            color(0xEAF6FF).setStroke()
            perch.stroke()

            color(0x66BB6A).setFill()
            NSBezierPath(ovalIn: NSRect(x: 75.5 * s, y: (120 - 95.5) * s, width: 5 * s, height: 5 * s)).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: URL(fileURLWithPath: "\(target)/icon_\(size)x\(size)\(suffix).png"))
    }
}
