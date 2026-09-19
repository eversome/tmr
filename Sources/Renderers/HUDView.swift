import AppKit
import TimerCore

/// The contents of the floating window. Draws itself in one pass and reports
/// keypresses and control clicks through `onKey`, using the same key semantics
/// as the terminal view so both share one handler.
public final class HUDView: NSView {
    public var snapshot: TimerSnapshot?
    public var onKey: ((Character) -> Void)?

    private var hovering = false
    private var trackingArea: NSTrackingArea?

    // Recomputed on every draw so the layout stays in one place.
    private var pauseRect = NSRect.zero
    private var plusRect = NSRect.zero
    private var closeRect = NSRect.zero

    public override var acceptsFirstResponder: Bool { true }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    public override func keyDown(with event: NSEvent) {
        guard let character = event.charactersIgnoringModifiers?.first else { return }
        onKey?(character)
    }

    /// Clicks on a control act on the timer; anywhere else drags the window.
    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hovering {
            if pauseRect.contains(point) { onKey?(" "); return }
            if plusRect.contains(point) { onKey?("+"); return }
            if closeRect.contains(point) { onKey?("q"); return }
        }
        window?.performDrag(with: event)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let snapshot = snapshot else { return }

        drawRing(snapshot)
        drawClock(snapshot)

        if hovering {
            drawControls(snapshot)
        } else {
            drawSubtitle(snapshot)
        }
    }

    // MARK: - Pieces

    private func accentColor(_ snapshot: TimerSnapshot) -> NSColor {
        switch snapshot.phase {
        case .finished: return .systemGreen
        case .paused: return .systemYellow
        case .stopped: return .systemGray
        case .running: return snapshot.remaining <= 5 ? .systemRed : .systemTeal
        }
    }

    private func drawRing(_ snapshot: TimerSnapshot) {
        let center = NSPoint(x: 52, y: bounds.midY)
        let radius: CGFloat = 26
        let lineWidth: CGFloat = 6

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.white.withAlphaComponent(0.15).setStroke()
        track.stroke()

        let progress = snapshot.progress
        guard progress > 0 else { return }

        // Starts at twelve o'clock and sweeps clockwise as time is consumed.
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * CGFloat(progress),
            clockwise: true
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        accentColor(snapshot).setStroke()
        arc.stroke()
    }

    private func drawClock(_ snapshot: TimerSnapshot) {
        let text = TimeFormatting.clock(snapshot.remaining) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 30, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: 92, y: bounds.midY - size.height / 2 + 10), withAttributes: attributes)
    }

    private func drawSubtitle(_ snapshot: TimerSnapshot) {
        let text: String
        switch snapshot.phase {
        case .running:
            text = snapshot.name ?? TimeFormatting.compact(snapshot.total)
        case .paused:
            text = "paused"
        case .finished:
            text = "done"
        case .stopped:
            text = "stopped"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        (text as NSString).draw(at: NSPoint(x: 93, y: 18), withAttributes: attributes)
    }

    private func drawControls(_ snapshot: TimerSnapshot) {
        pauseRect = NSRect(x: 92, y: 14, width: 26, height: 20)
        plusRect = NSRect(x: 122, y: 14, width: 38, height: 20)
        closeRect = NSRect(x: 164, y: 14, width: 26, height: 20)

        let pauseGlyph = snapshot.phase == .paused ? "▶" : "❚❚"
        draw(label: pauseGlyph, in: pauseRect)
        draw(label: "+1m", in: plusRect)
        draw(label: "✕", in: closeRect)
    }

    private func draw(label: String, in rect: NSRect) {
        let background = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.white.withAlphaComponent(0.12).setFill()
        background.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let text = label as NSString
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        text.draw(at: origin, withAttributes: attributes)
    }
}
