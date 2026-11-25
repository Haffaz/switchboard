import AppKit
import SwitchboardCore

/// Demo mode: shows the real menu and dialogs with sample accounts and
/// captures them for the documentation.
///
///     swift run Switchboard --demo-screenshots docs/images
///
/// It never reads or changes a real account, and it needs no Screen
/// Recording permission: it draws its own windows into images.
@MainActor
enum Demo {
    static let samples: [Profile] = [
        Profile(name: "default", email: "you@personal.example", desktopSignedIn: true,
                cliDir: "", desktopDir: "", icon: "house"),
        Profile(name: "work", email: "you@company.example", desktopSignedIn: true,
                cliDir: "", desktopDir: "/demo/work", icon: "briefcase", label: "Work"),
        Profile(name: "client-acme", email: "you@acme.example", desktopSignedIn: true,
                cliDir: "", desktopDir: "/demo/client-acme", icon: "building.2", label: "Client ACME"),
        Profile(name: "side-project", email: "", desktopSignedIn: false,
                cliDir: "", desktopDir: "/demo/side-project", icon: "hammer", label: "Side Project"),
    ]
    static let running: Set<String> = ["default", "client-acme"]

    private static let settleTime: TimeInterval = 1.0

    static func run(output: URL) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        ProfileStore.shared.loadDemo(samples, running: running)
        // A bare program has no icon; borrow the project's, if run from its folder.
        Dialogs.iconOverride = NSImage(contentsOfFile: "design/icon-1024.png")
        let controller = MenuController()
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                // Light appearance only: drawn off screen, dark windows lose
                // their backing and come out unreadable.
                app.appearance = NSAppearance(named: .aqua)
                let failures = shootAll(controller, into: output)
                exit(failures == 0 ? 0 : 1)
            }
        }
        app.run()
        exit(0)
    }

    /// Returns how many captures failed.
    private static func shootAll(_ controller: MenuController, into output: URL) -> Int {
        // Open menus on the half of the screen the pointer is not in, so no
        // row is highlighted in the capture.
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let pointerOnLeft = NSEvent.mouseLocation.x < screen.midX
        let point = NSPoint(x: pointerOnLeft ? screen.maxX - 420 : screen.minX + 60, y: screen.maxY - 80)
        var failures = 0

        let menu = controller.builtMenu()
        failures += shoot(output.appendingPathComponent("menu.png"), dismiss: { menu.cancelTracking() }) {
            menu.popUp(positioning: nil, at: point, in: nil)
        }
        if let accountMenu = controller.builtAccountMenu("client-acme") {
            failures += shoot(output.appendingPathComponent("account-menu.png"),
                              dismiss: { accountMenu.cancelTracking() }) {
                accountMenu.popUp(positioning: nil, at: point, in: nil)
            }
        }
        failures += shoot(output.appendingPathComponent("add-account.png"), dismiss: { NSApp.abortModal() }) {
            _ = Dialogs.askNewAccountName(taken: { _ in false })
        }
        failures += shoot(output.appendingPathComponent("rename.png"), dismiss: { NSApp.abortModal() }) {
            _ = Dialogs.askRename(current: "Default", original: "Default")
        }
        return failures
    }

    /// `show` blocks while its menu or dialog is up. A timer fires inside
    /// that wait, captures the window, and dismisses it.
    private static func shoot(_ file: URL, dismiss: @escaping @MainActor () -> Void, show: () -> Void) -> Int {
        var failed = 0
        let timer = Timer(timeInterval: settleTime, repeats: false) { _ in
            MainActor.assumeIsolated {
                if !capture(to: file) { failed = 1 }
                dismiss()
            }
        }
        for mode in [RunLoop.Mode.common, .eventTracking, .modalPanel] { RunLoop.main.add(timer, forMode: mode) }
        show()
        timer.invalidate()
        return failed
    }

    /// Draw this program's own front window into an image. No Screen
    /// Recording permission is needed, because nothing outside this program
    /// is read. Menus and alerts have see-through backgrounds on screen, so
    /// the window is drawn onto a plain panel in the current appearance.
    private static func capture(to file: URL) -> Bool {
        // Each menu and alert is two stacked windows: a glass backdrop and
        // the content. Take the content one.
        let candidates = NSApp.windows.filter {
            $0.isVisible && $0.level != .statusBar && $0.frame.width > 60 && $0.frame.height > 40
                && !$0.className.contains("GlassEffect")
        }
        guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              let content = window.contentView else {
            report(file, "no window found")
            return false
        }
        let view = content.superview ?? content
        guard let shot = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            report(file, "could not make an image")
            return false
        }
        view.cacheDisplay(in: view.bounds, to: shot)

        guard let content = shot.cgImage else { report(file, "could not read the capture"); return false }
        let dark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        guard let png = compose(content, size: view.bounds.size, radius: window.level == .popUpMenu ? 10 : 14, dark: dark)
        else { report(file, "could not compose the image"); return false }
        do { try png.write(to: file) } catch { report(file, error.localizedDescription); return false }
        report(file, "captured \(Int(view.bounds.width))x\(Int(view.bounds.height)) from \(window.className)")
        return true
    }

    /// Put a capture on a solid rounded panel with a soft shadow.
    ///
    /// Menus and alerts are see-through on screen (the system draws glass
    /// behind them), so a capture alone is mostly transparent and turns dark
    /// on a dark page. The panel is painted first, in plain sRGB, and the
    /// capture goes on top.
    private static func compose(_ content: CGImage, size: NSSize, radius: CGFloat, dark: Bool) -> Data? {
        let margin: CGFloat = 28, scale: CGFloat = 2
        let width = Int((size.width + 2 * margin) * scale), height = Int((size.height + 2 * margin) * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        let panel = CGRect(x: margin, y: margin, width: size.width, height: size.height)
        let shape = CGPath(roundedRect: panel, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let fill = dark ? CGColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
                        : CGColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: dark ? 0.5 : 0.28))
        context.addPath(shape)
        context.setFillColor(fill)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.draw(content, in: panel)
        context.restoreGState()

        context.addPath(shape)
        context.setStrokeColor(CGColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0, alpha: dark ? 0.18 : 0.12))
        context.setLineWidth(0.5)
        context.strokePath()

        // Guard against see-through output: the middle of the panel must be
        // solid, or the image turns dark on a dark page.
        guard let pixels = context.data else { return nil }
        let centre = (height / 2) * context.bytesPerRow + (width / 2) * 4
        guard pixels.load(fromByteOffset: centre + 3, as: UInt8.self) == 255 else { return nil }

        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func report(_ file: URL, _ message: String) {
        FileHandle.standardError.write(Data("demo: \(file.lastPathComponent): \(message)\n".utf8))
    }
}
