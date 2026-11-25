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
                cliDir: "", desktopDir: "/demo/work", icon: "briefcase"),
        Profile(name: "client-acme", email: "you@acme.example", desktopSignedIn: true,
                cliDir: "", desktopDir: "/demo/client-acme", icon: "building.2"),
        Profile(name: "side-project", email: "", desktopSignedIn: false,
                cliDir: "", desktopDir: "/demo/side-project", icon: "hammer"),
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
        failures += shoot(output.appendingPathComponent("rename.png"), dismiss: { NSApp.abortModal() }) {
            _ = Dialogs.askRename(current: "Default", original: "Default")
        }
        failures += shoot(output.appendingPathComponent("add-account.png"), dismiss: { NSApp.abortModal() }) {
            _ = Dialogs.askNewAccountName()
        }
        failures += shoot(output.appendingPathComponent("sign-in-choice.png"), dismiss: { NSApp.abortModal() }) {
            _ = Dialogs.afterCreate("work")
        }
        failures += shoot(output.appendingPathComponent("sign-in-steps.png"), dismiss: { NSApp.abortModal() }) {
            _ = Dialogs.signInIntro("work")
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

        let margin: CGFloat = 28, radius: CGFloat = window.level == .popUpMenu ? 10 : 14
        let size = NSSize(width: view.bounds.width + 2 * margin, height: view.bounds.height + 2 * margin)
        let scale: CGFloat = 2
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        canvas.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        let panel = NSRect(x: margin, y: margin, width: view.bounds.width, height: view.bounds.height)
        let shape = NSBezierPath(roundedRect: panel, xRadius: radius, yRadius: radius)
        // The backing panel is drawn in fixed colours that match the window's
        // light or dark look, so the capture reads the same on any Mac.
        let dark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.5 : 0.28)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        (dark ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
              : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1)).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        (dark ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.12)).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
        shape.addClip()
        shot.draw(in: panel)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = canvas.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: file) } catch { report(file, error.localizedDescription); return false }
        report(file, "captured \(Int(view.bounds.width))x\(Int(view.bounds.height)) from \(window.className)")
        return true
    }

    private static func report(_ file: URL, _ message: String) {
        FileHandle.standardError.write(Data("demo: \(file.lastPathComponent): \(message)\n".utf8))
    }
}
