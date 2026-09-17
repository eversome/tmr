import Foundation

public enum TimerPhase: Equatable {
    case running
    case paused
    case finished
    case stopped
}

public struct TimerSnapshot: Equatable {
    public let name: String?
    public let phase: TimerPhase
    public let total: TimeInterval
    public let remaining: TimeInterval
    /// Seconds since the countdown hit zero. Zero while it is still running.
    public let overtime: TimeInterval
    /// Wall-clock moment the timer will fire. Nil while paused, finished or stopped.
    public let endsAt: Date?

    public var elapsed: TimeInterval { max(0, total - remaining) }

    public var progress: Double {
        guard total > 0 else { return 1 }
        return min(1, max(0, elapsed / total))
    }
}

public enum TimerCommand: Equatable {
    case pause
    case resume
    case toggle
    /// Positive or negative seconds. Never drives the timer below zero.
    case adjust(TimeInterval)
    case reset
    case stop
}

public enum TimerEvent: Equatable {
    case paused
    case resumed
    case adjusted(TimeInterval)
    case reset
    case finished
    case stopped
}

/// The whole timer, with no notion of how it is displayed and no timer of its
/// own: the caller supplies `now`. That makes it exhaustively testable and lets
/// the terminal, the window and the BUSY Bar share one source of truth.
public final class TimerEngine {
    private enum State {
        case running(deadline: Date)
        case paused(remaining: TimeInterval)
        case finished(at: Date)
        case stopped
    }

    public let name: String?
    public private(set) var total: TimeInterval

    private let initialTotal: TimeInterval
    private var state: State

    public init(duration: TimeInterval, name: String? = nil, now: Date = Date()) {
        self.name = name
        self.total = duration
        self.initialTotal = duration
        self.state = .running(deadline: now.addingTimeInterval(duration))
    }

    /// Call once per frame. Emits `.finished` exactly once.
    @discardableResult
    public func update(now: Date) -> [TimerEvent] {
        if case .running(let deadline) = state, now >= deadline {
            state = .finished(at: deadline)
            return [.finished]
        }
        return []
    }

    @discardableResult
    public func apply(_ command: TimerCommand, now: Date) -> [TimerEvent] {
        switch command {
        case .pause:
            guard case .running(let deadline) = state else { return [] }
            state = .paused(remaining: max(0, deadline.timeIntervalSince(now)))
            return [.paused]

        case .resume:
            guard case .paused(let remaining) = state else { return [] }
            state = .running(deadline: now.addingTimeInterval(remaining))
            return [.resumed]

        case .toggle:
            switch state {
            case .running: return apply(.pause, now: now)
            case .paused: return apply(.resume, now: now)
            default: return []
            }

        case .adjust(let delta):
            return adjust(by: delta, now: now)

        case .reset:
            total = initialTotal
            state = .running(deadline: now.addingTimeInterval(initialTotal))
            return [.reset]

        case .stop:
            if case .stopped = state { return [] }
            state = .stopped
            return [.stopped]
        }
    }

    public func snapshot(now: Date) -> TimerSnapshot {
        switch state {
        case .running(let deadline):
            return TimerSnapshot(
                name: name,
                phase: .running,
                total: total,
                remaining: max(0, deadline.timeIntervalSince(now)),
                overtime: 0,
                endsAt: deadline
            )

        case .paused(let remaining):
            return TimerSnapshot(
                name: name,
                phase: .paused,
                total: total,
                remaining: remaining,
                overtime: 0,
                endsAt: nil
            )

        case .finished(let at):
            return TimerSnapshot(
                name: name,
                phase: .finished,
                total: total,
                remaining: 0,
                overtime: max(0, now.timeIntervalSince(at)),
                endsAt: nil
            )

        case .stopped:
            return TimerSnapshot(
                name: name,
                phase: .stopped,
                total: total,
                remaining: 0,
                overtime: 0,
                endsAt: nil
            )
        }
    }

    private func adjust(by delta: TimeInterval, now: Date) -> [TimerEvent] {
        switch state {
        case .running(let deadline):
            let newDeadline = deadline.addingTimeInterval(delta)
            total = max(0, total + delta)
            if newDeadline <= now {
                state = .finished(at: now)
                return [.adjusted(delta), .finished]
            }
            state = .running(deadline: newDeadline)
            return [.adjusted(delta)]

        case .paused(let remaining):
            let newRemaining = max(0, remaining + delta)
            total = max(0, total + delta)
            state = .paused(remaining: newRemaining)
            return [.adjusted(delta)]

        case .finished:
            // Adding time to a ringing timer revives it. Useful for "+1m" on
            // the alert screen; subtracting from a finished timer does nothing.
            guard delta > 0 else { return [] }
            total += delta
            state = .running(deadline: now.addingTimeInterval(delta))
            return [.adjusted(delta), .resumed]

        case .stopped:
            return []
        }
    }
}
