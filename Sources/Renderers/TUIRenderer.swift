import Foundation
import TimerCore

public protocol TimerRenderer: AnyObject {
    func start()
    func render(_ snapshot: TimerSnapshot)
    func stop()
    /// Returns a pending keypress, or nil. Non-interactive renderers return nil.
    func readKey() -> Character?
}

/// Draws the countdown in place, in the normal terminal flow: the block is
/// repainted by moving the cursor back over it, and on exit it is replaced by a
/// single summary line. No alternate screen, so the scrollback keeps a record
/// of what ran and when it ended.
public final class TUIRenderer: TimerRenderer {
    private var started = false
    private var renderedLines = 0
    private var lastSnapshot: TimerSnapshot?

    public init() {}

    public func start() {
        guard !started else { return }
        started = true
        Terminal.installInterruptHandler()
        Terminal.enableRawMode()
        Terminal.hideCursor()
    }

    public func stop() {
        guard started else { return }
        started = false

        erase()
        if let snapshot = lastSnapshot {
            Terminal.write(summary(snapshot) + "\n")
        }

        Terminal.showCursor()
        Terminal.restoreMode()
    }

    public func readKey() -> Character? {
        Terminal.readKey()
    }

    public func render(_ snapshot: TimerSnapshot) {
        lastSnapshot = snapshot

        let (columns, rows) = Terminal.size()
        var block: [String] = []

        block.append(headerLine(snapshot))

        let color = digitsColor(for: snapshot)
        for line in BigFont.render(TimeFormatting.clock(snapshot.remaining), scale: 2) {
            block.append(color + line + Style.reset)
        }

        block.append(progressBar(snapshot, width: min(max(columns - 4, 10), 44)))
        block.append(Style.dim + "space pause   + / - 1m   r reset   q quit" + Style.reset)

        // Cursor arithmetic only works while the block fits on screen; if the
        // window is tiny, drop the trimmings rather than corrupt the display.
        while block.count > max(1, rows - 1) {
            block.removeLast()
        }

        repaint(block)
    }

    // MARK: - Pieces

    private func headerLine(_ snapshot: TimerSnapshot) -> String {
        var parts: [String] = []
        if let name = snapshot.name, !name.isEmpty {
            parts.append(Style.bold + name + Style.reset)
        }

        switch snapshot.phase {
        case .running:
            if let endsAt = snapshot.endsAt {
                parts.append(Style.dim + "ends \(Formatters.clockTime.string(from: endsAt))" + Style.reset)
            }
        case .paused:
            parts.append(Style.dim + Style.yellow + "paused" + Style.reset)
        case .finished:
            parts.append(Style.dim + "done, any key to dismiss" + Style.reset)
        case .stopped:
            parts.append(Style.dim + "stopped" + Style.reset)
        }

        return parts.joined(separator: "   ")
    }

    private func digitsColor(for snapshot: TimerSnapshot) -> String {
        switch snapshot.phase {
        case .finished: return Style.bold + Style.green
        case .paused: return Style.dim + Style.yellow
        case .stopped: return Style.dim
        case .running: return snapshot.remaining <= 5 ? Style.bold + Style.red : Style.cyan
        }
    }

    private func progressBar(_ snapshot: TimerSnapshot, width: Int) -> String {
        let filled = Int((Double(width) * snapshot.progress).rounded())
        return String(repeating: "█", count: max(0, filled))
            + Style.dim + String(repeating: "░", count: max(0, width - filled)) + Style.reset
    }

    private func summary(_ snapshot: TimerSnapshot) -> String {
        let label = snapshot.name ?? "tmr"
        switch snapshot.phase {
        case .finished:
            return "\(label): done at \(Formatters.clockTime.string(from: Date()))"
        default:
            return "\(label): stopped with \(TimeFormatting.clock(snapshot.remaining)) left"
        }
    }

    // MARK: - Painting

    private func repaint(_ block: [String]) {
        var frame = ""
        if renderedLines > 0 {
            frame += "\u{1B}[\(renderedLines)A"
        }
        for line in block {
            frame += "\r" + line + "\u{1B}[K\n"
        }
        frame += "\u{1B}[J"

        Terminal.write(frame)
        renderedLines = block.count
    }

    private func erase() {
        guard renderedLines > 0 else { return }
        Terminal.write("\u{1B}[\(renderedLines)A\r\u{1B}[J")
        renderedLines = 0
    }
}

/// Used when stdout is not a terminal: pipes, Raycast script commands, cron.
/// One line on start, one on finish, no escape codes.
public final class PlainRenderer: TimerRenderer {
    private var announced = false
    private var reportedFinish = false

    public init() {}

    public func start() {}
    public func stop() {}
    public func readKey() -> Character? { nil }

    public func render(_ snapshot: TimerSnapshot) {
        let label = snapshot.name.map { "\($0): " } ?? ""

        if !announced {
            announced = true
            print("\(label)counting down \(TimeFormatting.compact(snapshot.total))")
        }
        if snapshot.phase == .finished && !reportedFinish {
            reportedFinish = true
            print("\(label)done")
        }
    }
}

enum Formatters {
    /// Built once: DateFormatter is expensive, and this one runs every frame.
    static let clockTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
