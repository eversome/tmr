import Foundation
import TimerCore

/// Draws the countdown on a BUSY Bar as a third output, alongside the terminal
/// and the window. Owns the pacing: the engine ticks at 12 fps, but the bar is
/// on the far side of an HTTP round trip, so this sends at most a couple of
/// requests a second and only when something actually changed.
public final class BarRenderer {
    /// Layout constants, gathered here because they are the part you tune once
    /// you have seen it on the hardware. Front is 72x16, back is 160x80.
    public struct Layout {
        /// Nil centers the clock on the 72px strip; a number pins it.
        public var clockX: Int?
        public var clockY = 2
        public var clockFont = "normal"
        /// Rough advance per character for clockFont, used only for centering.
        /// Measured off the hardware: "00:04" in `normal` is about 40px wide.
        public var clockAdvance = 8
        public var nameX = 4
        public var nameY = 4
        public var nameFont = "normal"
        public var statusX = 4
        public var statusY = 28
        public var statusFont = "small"
        public init() {}
    }

    private let client: BusyBarClient
    private let layout: Layout
    private let blinkInterval: TimeInterval
    private let queue = DispatchQueue(label: "tmr.bar")

    private var inFlight = false
    private var lastSentKey: String?
    private var lastSentAt: Date?
    private var warned = Set<String>()
    private var finished = false

    public init(client: BusyBarClient, layout: Layout = Layout(), blinkInterval: TimeInterval = 0.5) {
        self.client = client
        self.layout = layout
        self.blinkInterval = blinkInterval
    }

    /// One-off reachability check. The timer runs regardless; this only decides
    /// whether to warn the person that nothing will appear on the device.
    public func probe() {
        client.probe { [weak self] result in
            if case .failure(let error) = result {
                self?.warnOnce("bar unreachable: \(error)")
            }
        }
    }

    public func update(_ snapshot: TimerSnapshot, now: Date) {
        let clock = TimeFormatting.clock(snapshot.remaining)

        // Finished: blink the zeros until dismissed. Blanking is done by drawing
        // an empty string rather than clearing the app, so the back display and
        // the element ids stay put.
        var visible = true
        if snapshot.phase == .finished {
            finished = true
            let phase = Int(now.timeIntervalSince1970 / blinkInterval)
            visible = phase % 2 == 0
        }

        let key = "\(clock)|\(snapshot.phase)|\(visible)|\(snapshot.name ?? "")"
        guard key != lastSentKey else { return }

        // Rate limit even when the key changes, so a blink cannot outrun the link.
        if let lastSentAt = lastSentAt, now.timeIntervalSince(lastSentAt) < blinkInterval / 2 {
            return
        }

        lastSentKey = key
        lastSentAt = now
        draw(elements(for: snapshot, clock: visible ? clock : "", now: now))
    }

    public func alert(_ sound: BusyBarClient.StockSound) {
        client.play(sound) { [weak self] result in
            if case .failure(let error) = result {
                self?.warnOnce("bar sound failed: \(error)")
            }
        }
    }

    /// Blocking on purpose: this runs on the way out, and the process must not
    /// exit before the bar has been handed back to whatever was there before.
    public func shutdown(timeout: TimeInterval = 1.5) {
        let group = DispatchGroup()

        if finished {
            group.enter()
            client.stopAudio { _ in group.leave() }
        }

        group.enter()
        client.clear { _ in group.leave() }

        _ = group.wait(timeout: .now() + timeout)
    }

    // MARK: - Layout

    private func elements(for snapshot: TimerSnapshot, clock: String, now: Date) -> [BusyBarClient.TextElement] {
        var elements: [BusyBarClient.TextElement] = [
            BusyBarClient.TextElement(
                id: "clock",
                x: clockOrigin(for: clock),
                y: layout.clockY,
                text: clock,
                font: layout.clockFont,
                display: .front
            ),
            BusyBarClient.TextElement(
                id: "name",
                x: layout.nameX,
                y: layout.nameY,
                text: snapshot.name ?? "tmr",
                font: layout.nameFont,
                display: .back
            ),
        ]

        elements.append(
            BusyBarClient.TextElement(
                id: "status",
                x: layout.statusX,
                y: layout.statusY,
                text: statusText(snapshot),
                font: layout.statusFont,
                display: .back
            )
        )

        return elements
    }

    /// The front panel is 72px wide and the API takes a left edge, not an
    /// alignment, so centering is ours to do.
    private func clockOrigin(for clock: String) -> Int {
        if let pinned = layout.clockX { return pinned }
        let width = clock.count * layout.clockAdvance
        return max(0, (72 - width) / 2)
    }

    private func statusText(_ snapshot: TimerSnapshot) -> String {
        switch snapshot.phase {
        case .running:
            guard let endsAt = snapshot.endsAt else { return "" }
            return "ends \(Formatters.clockTime.string(from: endsAt))"
        case .paused:
            return "paused"
        case .finished:
            return "done"
        case .stopped:
            return "stopped"
        }
    }

    // MARK: - Sending

    private func draw(_ elements: [BusyBarClient.TextElement]) {
        // One request at a time. A dropped frame is invisible; a queue of stale
        // frames would make the display lag behind the countdown.
        var shouldSend = false
        queue.sync {
            if !inFlight {
                inFlight = true
                shouldSend = true
            }
        }
        guard shouldSend else { return }

        client.draw(elements) { [weak self] result in
            guard let self = self else { return }
            self.queue.sync { self.inFlight = false }

            if case .failure(let error) = result {
                self.warnOnce("bar draw failed: \(error)")
            }
        }
    }

    /// Each distinct problem is reported once. A bar that is unplugged would
    /// otherwise print a line every frame.
    private func warnOnce(_ message: String) {
        var isNew = false
        queue.sync {
            isNew = warned.insert(message).inserted
        }
        guard isNew else { return }
        FileHandle.standardError.write(Data("tmr: \(message)\n".utf8))
    }
}
