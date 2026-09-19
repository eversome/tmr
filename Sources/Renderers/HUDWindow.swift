import AppKit
import TimerCore

/// A borderless panel still has to be allowed to take key events, otherwise the
/// keyboard shortcuts silently do nothing.
public final class HUDWindow: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}

public final class HUDController: NSObject, NSWindowDelegate {
    public var onKey: ((Character) -> Void)?

    private static let originDefaultsKey = "tmr.hud.origin"
    private static let size = NSSize(width: 248, height: 96)

    private let view = HUDView()
    private var window: HUDWindow?

    public override init() {
        super.init()
    }

    public func show() {
        let app = NSApplication.shared
        // .accessory keeps the timer out of the Dock and the app switcher. If
        // keyboard focus ever misbehaves, .regular is the reliable fallback.
        app.setActivationPolicy(.accessory)

        let frame = NSRect(origin: .zero, size: HUDController.size)
        let window = HUDWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.delegate = self

        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        view.frame = effect.bounds
        view.autoresizingMask = [.width, .height]
        view.onKey = { [weak self] character in
            self?.onKey?(character)
        }
        effect.addSubview(view)
        window.contentView = effect

        window.setFrameOrigin(restoredOrigin())
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        app.activate(ignoringOtherApps: true)

        self.window = window
    }

    public func update(_ snapshot: TimerSnapshot) {
        view.snapshot = snapshot
        view.needsDisplay = true
    }

    public func runApplication() {
        NSApplication.shared.run()
    }

    public func close() {
        window?.orderOut(nil)
        window = nil
    }

    public func windowDidMove(_ notification: Notification) {
        guard let origin = window?.frame.origin else { return }
        UserDefaults.standard.set([origin.x, origin.y], forKey: HUDController.originDefaultsKey)
    }

    /// Last position if there is one and it is still on a screen, otherwise the
    /// top right corner of the active display.
    private func restoredOrigin() -> NSPoint {
        if let stored = UserDefaults.standard.array(forKey: HUDController.originDefaultsKey) as? [Double],
           stored.count == 2 {
            let point = NSPoint(x: stored[0], y: stored[1])
            let visible = NSRect(origin: point, size: HUDController.size)
            for screen in NSScreen.screens where screen.visibleFrame.intersects(visible) {
                return point
            }
        }

        guard let screen = NSScreen.main else { return NSPoint(x: 80, y: 80) }
        let margin: CGFloat = 24
        return NSPoint(
            x: screen.visibleFrame.maxX - HUDController.size.width - margin,
            y: screen.visibleFrame.maxY - HUDController.size.height - margin
        )
    }
}
