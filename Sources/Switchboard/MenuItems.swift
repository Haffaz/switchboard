import AppKit

/// Small builders for menu rows that only display things.
@MainActor
enum MenuItems {


    static func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }


    /// The "running" mark for the checkmark column. Drawn as a plain colour
    /// image (not a template), because macOS repaints template images in
    /// the menu's text colour and the green would be lost.
    static func runningDot() -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Running"
        return image
    }

    /// Menu bar glyph: two meshing cogs with long, ray-like teeth, so each
    /// one also reads as a spark. The machinery that routes you between
    /// Claude accounts. Evenly spaced on purpose: a nod to Claude's spark,
    /// not Anthropic's logo.
    static func barIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let s = rect.width
            let small = CGPoint(x: 0.745 * s, y: 0.265 * s)
            cog(center: CGPoint(x: 0.37 * s, y: 0.61 * s), radius: 0.37 * s, teeth: 10, rotation: .pi / 10)
            // A thin gap where the two meet, so they read as two cogs.
            erase(center: small, radius: 0.27 * s)
            cog(center: small, radius: 0.24 * s, teeth: 8, rotation: 0)
            return true
        }
        image.isTemplate = true  // macOS tints it for light/dark menu bars
        image.accessibilityDescription = "Switchboard"
        return image
    }

    /// A cog: small round hub, long round-ended teeth, and a centre hole.
    private static func cog(center: CGPoint, radius: CGFloat, teeth: Int, rotation: CGFloat) {
        NSColor.black.set()
        let body = radius * 0.46
        NSBezierPath(ovalIn: NSRect(x: center.x - body, y: center.y - body, width: 2 * body, height: 2 * body)).fill()
        let toothWidth = 2 * .pi * radius / CGFloat(teeth) * 0.30
        for i in 0..<teeth {
            let angle = rotation + CGFloat(i) * 2 * .pi / CGFloat(teeth)
            let reach = radius - toothWidth / 2
            let path = NSBezierPath()
            path.move(to: CGPoint(x: center.x + cos(angle) * body * 0.8, y: center.y + sin(angle) * body * 0.8))
            path.line(to: CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach))
            path.lineWidth = toothWidth
            path.lineCapStyle = .round
            path.stroke()
        }
        erase(center: center, radius: radius * 0.20)
    }

    private static func erase(center: CGPoint, radius: CGFloat) {
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                    width: 2 * radius, height: 2 * radius)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    /// A monochrome system symbol that macOS tints for light and dark menus.
    static func symbol(_ name: String, pointSize: CGFloat? = nil) -> NSImage? {
        var image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        if let pointSize {
            image = image?.withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
        }
        image?.isTemplate = true
        return image
    }
}
