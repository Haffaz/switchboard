// Draws Switchboard's app icon.
//   make-icon <out.iconset> [design]   -> iconset for iconutil
//   make-icon --sheet <out.png>        -> all designs side by side, for choosing
// Designs: cogs (default; two meshing cogs, matches the menu bar), fanout, patchbay, cards, toggle.
import AppKit

// MARK: - Shared drawing

struct Canvas {
    let s: CGFloat
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: (1 - y) * s) }  // y from top
    func len(_ v: CGFloat) -> CGFloat { v * s }
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// macOS icon body: 824/1024 rounded square with gradient, inner highlight and drop shadow.
func drawBody(_ c: Canvas, top: NSColor, bottom: NSColor) -> NSBezierPath {
    let inset = c.len(100 / 1024)
    let rect = NSRect(x: inset, y: inset, width: c.s - 2 * inset, height: c.s - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: c.len(185 / 1024), yRadius: c.len(185 / 1024))

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -c.len(0.012))
    shadow.shadowBlurRadius = c.len(0.03)
    shadow.set()
    bottom.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [top, bottom])?.draw(in: shape, angle: -90)
    // Soft light from above.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])?
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    // Hairline edge.
    NSColor.white.withAlphaComponent(0.08).setStroke()
    shape.lineWidth = c.len(0.004)
    shape.stroke()
    return shape
}

// MARK: - Design: patch bay

/// Three sockets on each side, joined by crossing cables: one Mac, routed to many accounts.
func drawPatchbay(_ c: Canvas) {
    let body = drawBody(c, top: rgb(0x2A2F45), bottom: rgb(0x14172A))
    NSGraphicsContext.saveGraphicsState()
    body.addClip()

    let rows: [CGFloat] = [0.35, 0.50, 0.65]
    let leftX: CGFloat = 0.31, rightX: CGFloat = 0.69
    let cables: [(from: Int, to: Int, color: NSColor)] = [
        (0, 2, rgb(0xF2B84B)),  // amber
        (2, 0, rgb(0x4CC9B0)),  // teal
        (1, 1, rgb(0xF0785A)),  // coral, drawn last so it sits on top
    ]

    for cable in cables {
        let a = c.p(leftX, rows[cable.from]), b = c.p(rightX, rows[cable.to])
        let path = NSBezierPath()
        path.move(to: a)
        path.curve(to: b, controlPoint1: CGPoint(x: a.x + c.len(0.24), y: a.y),
                   controlPoint2: CGPoint(x: b.x - c.len(0.24), y: b.y))
        path.lineCapStyle = .round
        // Dark outline so crossings read clearly.
        rgb(0x14172A).setStroke(); path.lineWidth = c.len(0.075); path.stroke()
        cable.color.setStroke(); path.lineWidth = c.len(0.048); path.stroke()
    }

    // Sockets and plugs.
    for (i, y) in rows.enumerated() {
        for (x, isLeft) in [(leftX, true), (rightX, false)] {
            let center = c.p(x, y)
            let r = c.len(0.045)
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            rgb(0xE9ECF5).setFill(); ring.fill()
            let color = cables.first { isLeft ? $0.from == i : $0.to == i }?.color ?? .gray
            let inner = r * 0.55
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - inner, y: center.y - inner,
                                        width: 2 * inner, height: 2 * inner)).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Design: cogs

/// Two meshing cogs with long, ray-like teeth, so each also reads as a
/// spark: a large white one and a small amber one. The machinery that routes
/// you between Claude accounts. Evenly spaced on purpose: a nod to Claude's
/// spark, not Anthropic's logo. Matches the menu bar icon.
func drawCogs(_ c: Canvas) {
    let body = drawBody(c, top: rgb(0x2B3049), bottom: rgb(0x121527))
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    // The tile's own colour at a given height (0 = top), so holes and the
    // gap between the cogs blend into the gradient.
    func tile(_ y: CGFloat) -> NSColor {
        let t = min(max((y - 100.0 / 1024) / (824.0 / 1024), 0), 1)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { (a + (b - a) * t) / 255 }
        return NSColor(srgbRed: mix(0x2B, 0x12), green: mix(0x30, 0x15), blue: mix(0x49, 0x27), alpha: 1)
    }
    func disc(_ center: CGPoint, _ r: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)).fill()
    }
    func cog(_ center: CGPoint, _ radius: CGFloat, y: CGFloat, teeth: Int, rotation: CGFloat, _ color: NSColor) {
        let core = radius * 0.46
        disc(center, core, color)
        let toothWidth = 2 * .pi * radius / CGFloat(teeth) * 0.30
        color.setStroke()
        for i in 0..<teeth {
            let a = rotation + CGFloat(i) * 2 * .pi / CGFloat(teeth)
            let reach = radius - toothWidth / 2
            let path = NSBezierPath()
            path.move(to: CGPoint(x: center.x + cos(a) * core * 0.8, y: center.y + sin(a) * core * 0.8))
            path.line(to: CGPoint(x: center.x + cos(a) * reach, y: center.y + sin(a) * reach))
            path.lineWidth = toothWidth; path.lineCapStyle = .round; path.stroke()
        }
        disc(center, radius * 0.20, tile(y))
    }
    let big = c.p(0.41, 0.43), small = c.p(0.665, 0.665)
    cog(big, c.len(0.255), y: 0.43, teeth: 10, rotation: .pi / 10, rgb(0xF5F6FA))
    disc(small, c.len(0.185), tile(0.70))  // gap where the two meet
    cog(small, c.len(0.165), y: 0.665, teeth: 8, rotation: 0, rgb(0xF2B84B))
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Design: fan-out

/// One plug on the left (this Mac) routed to three accounts on the right.
func drawFanout(_ c: Canvas) {
    let body = drawBody(c, top: rgb(0x2B3049), bottom: rgb(0x121527))
    NSGraphicsContext.saveGraphicsState()
    body.addClip()

    let source = c.p(0.30, 0.50)
    let targets: [(y: CGFloat, color: NSColor)] = [
        (0.32, rgb(0xF2B84B)), (0.50, rgb(0xF0785A)), (0.68, rgb(0x4CC9B0)),
    ]
    let rightX: CGFloat = 0.72

    for t in targets {
        let b = c.p(rightX, t.y)
        let path = NSBezierPath()
        path.move(to: source)
        path.curve(to: b, controlPoint1: CGPoint(x: source.x + c.len(0.20), y: source.y),
                   controlPoint2: CGPoint(x: b.x - c.len(0.20), y: b.y))
        path.lineCapStyle = .round
        rgb(0x121527).setStroke(); path.lineWidth = c.len(0.070); path.stroke()
        t.color.setStroke(); path.lineWidth = c.len(0.044); path.stroke()
    }

    func dot(_ center: CGPoint, _ r: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)).fill()
    }
    // Accounts: light rings with a coloured core.
    for t in targets {
        let b = c.p(rightX, t.y)
        dot(b, c.len(0.062), rgb(0xE9ECF5))
        dot(b, c.len(0.034), t.color)
    }
    // Source plug: larger, white, with a dark core.
    dot(source, c.len(0.080), rgb(0xF5F6FA))
    dot(source, c.len(0.036), rgb(0x2B3049))
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Design: cards

/// Three stacked account cards, the front one with a person; a curved arrow swaps them.
func drawCards(_ c: Canvas) {
    let body = drawBody(c, top: rgb(0xFF8A65), bottom: rgb(0xD9485F))
    NSGraphicsContext.saveGraphicsState()
    body.addClip()

    let cards: [(dx: CGFloat, dy: CGFloat, alpha: CGFloat)] = [(0.10, -0.10, 0.35), (0.05, -0.05, 0.6), (0, 0, 1)]
    for card in cards {
        let rect = NSRect(x: c.len(0.25 + card.dx), y: c.len(1 - 0.70 + card.dy - 0.02),
                          width: c.len(0.42), height: c.len(0.30))
        let path = NSBezierPath(roundedRect: rect, xRadius: c.len(0.05), yRadius: c.len(0.05))
        NSColor.white.withAlphaComponent(card.alpha).setFill(); path.fill()
    }
    // Person on the front card.
    let head = c.p(0.36, 0.49), hr = c.len(0.045)
    rgb(0xD9485F).setFill()
    NSBezierPath(ovalIn: NSRect(x: head.x - hr, y: head.y - hr, width: 2 * hr, height: 2 * hr)).fill()
    let shoulders = NSBezierPath(roundedRect: NSRect(x: head.x - c.len(0.07), y: c.len(1 - 0.64),
                                                     width: c.len(0.14), height: c.len(0.07)),
                                 xRadius: c.len(0.035), yRadius: c.len(0.035))
    shoulders.fill()
    // Text lines.
    for (i, w) in [0.16, 0.11].enumerated() {
        let line = NSBezierPath(roundedRect: NSRect(x: c.len(0.46), y: c.len(1 - 0.50 - CGFloat(i) * 0.07),
                                                    width: c.len(w), height: c.len(0.035)),
                                xRadius: c.len(0.0175), yRadius: c.len(0.0175))
        rgb(0xD9485F, 0.45).setFill(); line.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Design: toggle (the original, refined)

func drawToggle(_ c: Canvas) {
    _ = drawBody(c, top: rgb(0x5B4BB0), bottom: rgb(0x2A2448))
    let config = NSImage.SymbolConfiguration(pointSize: c.len(0.40), weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "switch.2", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: (c.s - size.width) / 2, y: (c.s - size.height) / 2,
                               width: size.width, height: size.height))
    }
}

let designs: [String: (Canvas) -> Void] = [
    "cogs": drawCogs, "fanout": drawFanout, "patchbay": drawPatchbay, "cards": drawCards, "toggle": drawToggle,
]
let designOrder = ["cogs", "fanout", "patchbay"]

// MARK: - Output

func render(_ design: String, pixels: Int) -> NSBitmapImageRep? {
    guard let draw = designs[design], let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(Canvas(s: CGFloat(pixels)))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writeIconset(_ design: String, to out: URL) throws {
    let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                               (256, 1), (256, 2), (512, 1), (512, 2)]
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (points, scale) in sizes {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        guard let data = render(design, pixels: points * scale)?.representation(using: .png, properties: [:])
        else { fatalError("could not draw \(name)") }
        try data.write(to: out.appendingPathComponent(name))
    }
}

/// Each design large, plus at Dock (64) and Finder-list (32) sizes, on light and dark.
func writeSheet(to out: URL) throws {
    let big = 300, cell = 340, rows = 2
    let width = cell * designOrder.count, height = (big + 120) * rows
    guard let sheet = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
    for row in 0..<rows {
        let bg = row == 0 ? rgb(0xF2F2F5) : rgb(0x1E1E22)
        let y0 = CGFloat(height - (row + 1) * (big + 120))
        bg.setFill(); NSRect(x: 0, y: y0, width: CGFloat(width), height: CGFloat(big + 120)).fill()
        for (i, design) in designOrder.enumerated() {
            let x0 = CGFloat(i * cell + (cell - big) / 2)
            for (size, dx) in [(big, 0), (64, 0), (32, 80)] {
                guard let rep = render(design, pixels: size * 2) else { continue }
                let image = NSImage(size: NSSize(width: size, height: size)); image.addRepresentation(rep)
                let rect = size == big
                    ? NSRect(x: x0, y: y0 + 100, width: CGFloat(size), height: CGFloat(size))
                    : NSRect(x: x0 + 40 + CGFloat(dx), y: y0 + 20 + CGFloat(64 - size) / 2,
                             width: CGFloat(size), height: CGFloat(size))
                image.draw(in: rect)
            }
            let label = NSAttributedString(string: "\(i + 1). \(design)", attributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: row == 0 ? NSColor.black : NSColor.white])
            label.draw(at: NSPoint(x: x0 + 160, y: y0 + 42))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try sheet.representation(using: .png, properties: [:])?.write(to: out)
}

let args = CommandLine.arguments
if args.count > 2 && args[1] == "--sheet" {
    try writeSheet(to: URL(fileURLWithPath: args[2]))
} else {
    let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "AppIcon.iconset")
    try writeIconset(args.count > 2 ? args[2] : "cogs", to: out)
}
