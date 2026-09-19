import Darwin
import Foundation
import Renderers
import TimerCore

/// What a keypress means and when the process is done. Shared by both drivers
/// so the terminal and the window never drift apart in behaviour.
struct SessionPolicy {
    let ring: Bool
    let quitAfter: Double?
    let silent: Bool

    enum KeyOutcome {
        case handled
        case quit
    }

    func handle(key: Character, engine: TimerEngine, now: Date, finished: Bool) -> KeyOutcome {
        switch key {
        case "q", "Q", "\u{1B}", "\u{3}":
            engine.apply(.stop, now: now)
            return .quit
        case " ", "p", "P":
            if finished { return .quit }
            engine.apply(.toggle, now: now)
        case "+", "=":
            engine.apply(.adjust(60), now: now)
        case "-", "_":
            engine.apply(.adjust(-60), now: now)
        case "r", "R":
            engine.apply(.reset, now: now)
        default:
            // Any other key dismisses a ringing timer and is ignored otherwise.
            if finished { return .quit }
        }
        return .handled
    }

    func shouldExit(finishedAt: Date, now: Date, alert: Alert?) -> Bool {
        if ring {
            return false                                // only a keypress ends it
        }
        if let quitAfter = quitAfter {
            return now.timeIntervalSince(finishedAt) >= quitAfter
        }
        if let alert = alert {
            return !alert.isPlaying                     // let the sound finish
        }
        return now.timeIntervalSince(finishedAt) >= 0.5
    }
}

/// The bar as an output: the renderer plus the sound it plays on finish.
struct BarOutput {
    let renderer: BarRenderer
    let sound: BusyBarClient.StockSound?

    func alert() {
        guard let sound = sound else { return }
        renderer.alert(sound)
    }
}

/// Drives the countdown in the terminal with a plain polling loop.
final class TerminalDriver {
    private let engine: TimerEngine
    private let alert: Alert?
    private let policy: SessionPolicy
    private let bar: BarOutput?
    private let renderer: TimerRenderer

    init(engine: TimerEngine, alert: Alert?, policy: SessionPolicy, bar: BarOutput?) {
        self.engine = engine
        self.alert = alert
        self.policy = policy
        self.bar = bar
        self.renderer = Terminal.isInteractive ? TUIRenderer() : PlainRenderer()
    }

    func run() {
        let frameInterval: useconds_t = 80_000    // 12.5 fps, cheap and smooth enough
        var finishedAt: Date?

        renderer.start()
        Terminal.installInterruptHandler()
        bar?.renderer.probe()
        defer {
            renderer.stop()
            alert?.stop()
            bar?.renderer.shutdown()
        }

        while true {
            let now = Date()

            if engine.update(now: now).contains(.finished) {
                finishedAt = now
                startAlert()
                bar?.alert()
            }

            let snapshot = engine.snapshot(now: now)
            renderer.render(snapshot)
            bar?.renderer.update(snapshot, now: now)
            alert?.pump()

            if Terminal.wasInterrupted {
                engine.apply(.stop, now: now)
                renderer.render(engine.snapshot(now: now))
                return
            }

            if let key = renderer.readKey() {
                if policy.handle(key: key, engine: engine, now: now, finished: finishedAt != nil) == .quit {
                    return
                }
                if engine.snapshot(now: now).phase == .running {
                    finishedAt = nil                     // revived by + or r
                    alert?.stop()
                }
            }

            if let finishedAt = finishedAt,
               policy.shouldExit(finishedAt: finishedAt, now: now, alert: alert) {
                return
            }

            usleep(frameInterval)
        }
    }

    private func startAlert() {
        if let alert = alert {
            alert.play()
        } else if !policy.silent {
            Terminal.bell()
        }
    }
}

/// Drives the same countdown in the floating window. AppKit owns the run loop
/// here, so the tick is a repeating timer instead of a sleep.
final class HUDDriver {
    private let engine: TimerEngine
    private let alert: Alert?
    private let policy: SessionPolicy
    private let bar: BarOutput?
    private let controller = HUDController()
    private var finishedAt: Date?

    init(engine: TimerEngine, alert: Alert?, policy: SessionPolicy, bar: BarOutput?) {
        self.engine = engine
        self.alert = alert
        self.policy = policy
        self.bar = bar
    }

    func run() {
        // Strong captures on purpose. The driver has to outlive this call for
        // as long as the window is up, and nothing else owns it. That is a
        // retain cycle, which is fine here: quit() ends the process outright.
        controller.onKey = { character in
            self.handle(key: character)
        }
        Terminal.installInterruptHandler()
        bar?.renderer.probe()
        controller.show()
        controller.update(engine.snapshot(now: Date()))

        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            self.tick()
        }
        // .common keeps the countdown live while the window is being dragged.
        RunLoop.main.add(timer, forMode: .common)

        controller.runApplication()
    }

    private func tick() {
        let now = Date()

        if engine.update(now: now).contains(.finished) {
            finishedAt = now
            alert?.play()
            bar?.alert()
        }

        let snapshot = engine.snapshot(now: now)
        controller.update(snapshot)
        bar?.renderer.update(snapshot, now: now)
        alert?.pump()

        if Terminal.wasInterrupted {
            quit()
            return
        }

        if let finishedAt = finishedAt,
           policy.shouldExit(finishedAt: finishedAt, now: now, alert: alert) {
            quit()
        }
    }

    private func handle(key: Character) {
        let now = Date()
        if policy.handle(key: key, engine: engine, now: now, finished: finishedAt != nil) == .quit {
            quit()
            return
        }
        if engine.snapshot(now: now).phase == .running {
            finishedAt = nil
            alert?.stop()
        }
        controller.update(engine.snapshot(now: now))
    }

    private func quit() {
        alert?.stop()
        controller.close()
        bar?.renderer.shutdown()
        exit(0)
    }
}
