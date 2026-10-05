import Foundation
import TimerCore

/// Draws the countdown on a BUSY Bar as a third output, alongside the terminal
/// and the window. Owns the pacing: the engine ticks at 12 fps, but the bar is
/// on the far side of an HTTP round trip, so this sends at most a couple of
/// requests a second and only when something actually changed.
public final class BarRenderer {
    /// The front panel, in device pixels.
    private static let width = 72
    private static let height = 16
    private static let barHeight = 2

    public struct Layout {
        /// Nil lets the firmware center the clock via align "top_mid"; a number
        /// pins its left edge instead.
        public var clockX: Int?
        /// `extra_large` is a caps-only face, which is no loss for digits, and
        /// its ink is 10 rows tall starting 2 below y: rows 2...11, clear of
        /// the progress bar along rows 14 and 15.
        public var clockY = 0
        public var clockFont = "extra_large"
        public var showProgress = true
        /// Overrides the running colour, as #RRGGBB. The track beneath it is
        /// derived by darkening, so only one colour has to be picked.
        public var accent: String?
        public var nameX = 4
        public var nameY = 4
        public var nameFont = "normal"
        public var statusX = 4
        public var statusY = 28
        public var statusFont = "small"
        public init() {}
    }

    /// Accent and track colours per phase, as #RRGGBB. Alpha is added later.
    private enum Palette {
        static let running = ("#FFFFFF", "#383838")
        static let ending = ("#FF3B30", "#4A0B08")
        static let paused = ("#FFB020", "#4A2E00")
        static let finished = ("#FFFFFF", "#4A0B08")

        /// Named shortcuts for --bar-color; anything else is taken as hex.
        static let named = [
            "cyan": "#3FD8FF", "teal": "#3FD8FF",
            "green": "#36D399", "lime": "#AAFF00",
            "amber": "#FFB020", "orange": "#FF7A18",
            "red": "#FF3B30", "pink": "#FF4FA3",
            "purple": "#A67CFF", "blue": "#4D7CFF",
            "white": "#FFFFFF",
        ]

        /// Reads "#RRGGBB", "RRGGBB" or a name, and returns nil for junk so the
        /// CLI can complain rather than draw something invisible.
        static func resolve(_ value: String) -> String? {
            if let named = named[value.lowercased()] { return named }

            let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
            guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
            return "#" + hex.uppercased()
        }

        /// The track is the accent at about a fifth of its brightness, which
        /// reads as a dim rail rather than as a second colour.
        static func track(for accent: String) -> String {
            let hex = accent.dropFirst()
            var out = "#"
            for start in stride(from: 0, to: 6, by: 2) {
                let from = hex.index(hex.startIndex, offsetBy: start)
                let to = hex.index(from, offsetBy: 2)
                let value = Int(hex[from..<to], radix: 16) ?? 0
                out += String(format: "%02X", Int(Double(value) * 0.22))
            }
            return out
        }
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
    private var ledFlashed = false

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
        // Finished: blink until dismissed. The firmware never forgets an id, so
        // blanking is done by sending the same element at zero alpha rather
        // than by leaving it out of the frame.
        var visible = true
        if snapshot.phase == .finished {
            finished = true
            visible = Int(now.timeIntervalSince1970 / blinkInterval) % 2 == 0
        }

        let clock = TimeFormatting.clock(snapshot.remaining)
        let filled = progressWidth(snapshot)
        let key = "\(clock)|\(snapshot.phase)|\(visible)|\(filled)|\(snapshot.name ?? "")"
        guard key != lastSentKey else { return }

        // Rate limit even when the key changes, so a blink cannot outrun the link.
        if let lastSentAt = lastSentAt, now.timeIntervalSince(lastSentAt) < blinkInterval / 2 {
            return
        }

        lastSentKey = key
        lastSentAt = now

        // One flash when the timer fires, not one per frame.
        var led: String?
        if snapshot.phase == .finished && !ledFlashed {
            ledFlashed = true
            led = Palette.ending.0 + "FF"
        }

        draw(elements(for: snapshot, clock: clock, visible: visible, filled: filled), ledColor: led)
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

    private func palette(for snapshot: TimerSnapshot) -> (String, String) {
        switch snapshot.phase {
        case .finished: return Palette.finished
        case .paused: return Palette.paused
        case .stopped: return Palette.paused
        case .running:
            if snapshot.remaining <= 5 { return Palette.ending }
            guard let accent = layout.accent else { return Palette.running }
            return (accent, Palette.track(for: accent))
        }
    }

    public static func color(named value: String) -> String? {
        Palette.resolve(value)
    }

    private func progressWidth(_ snapshot: TimerSnapshot) -> Int {
        guard layout.showProgress else { return 0 }
        let remaining = 1 - snapshot.progress
        return Int((Double(BarRenderer.width) * remaining).rounded())
    }

    /// Order matters and never changes: the firmware paints by first-seen id,
    /// so the track and the fill have to be established before the digits or
    /// they would cover them.
    private func elements(
        for snapshot: TimerSnapshot,
        clock: String,
        visible: Bool,
        filled: Int
    ) -> [BusyBarClient.Element] {
        let (accent, dim) = palette(for: snapshot)
        var elements: [BusyBarClient.Element] = []

        if layout.showProgress {
            elements.append(.rectangle(BusyBarClient.RectangleElement(
                id: "track",
                x: 0,
                y: BarRenderer.height - BarRenderer.barHeight,
                width: BarRenderer.width,
                height: BarRenderer.barHeight,
                fillColors: [dim + "80"],
                display: .front
            )))

            // A zero-width rectangle is not allowed, so an empty bar is sent
            // transparent instead.
            elements.append(.rectangle(BusyBarClient.RectangleElement(
                id: "fill",
                x: 0,
                y: BarRenderer.height - BarRenderer.barHeight,
                width: max(1, filled),
                height: BarRenderer.barHeight,
                fill: "gradient_h",
                fillColors: filled > 0 ? [accent + "47", accent + "FF"] : ["#00000000"],
                display: .front
            )))
        }

        elements.append(.text(BusyBarClient.TextElement(
            id: "clock",
            x: layout.clockX ?? BarRenderer.width / 2,
            y: layout.clockY,
            text: clock,
            font: layout.clockFont,
            color: accent + (visible ? "FF" : "00"),
            align: layout.clockX == nil ? "top_mid" : "top_left",
            display: .front
        )))

        elements.append(.text(BusyBarClient.TextElement(
            id: "name",
            x: layout.nameX,
            y: layout.nameY,
            text: snapshot.name ?? "tmr",
            font: layout.nameFont,
            display: .back
        )))

        elements.append(.text(BusyBarClient.TextElement(
            id: "status",
            x: layout.statusX,
            y: layout.statusY,
            text: statusText(snapshot),
            font: layout.statusFont,
            display: .back
        )))

        return elements
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

    private func draw(_ elements: [BusyBarClient.Element], ledColor: String? = nil) {
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

        client.draw(elements, ledColor: ledColor) { [weak self] result in
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
