import ArgumentParser
import Darwin
import Foundation
import Renderers
import TimerCore

@main
struct Tmr: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tmr",
        abstract: "A countdown timer for the terminal, with a sound at the end.",
        discussion: """
        Examples:
          tmr 5m                  five minutes, default sound
          tmr -t 25m -n focus     named timer
          tmr -a Submarine 90     pick a system sound
          tmr -a ~/gong.wav 1h    pick a file
          tmr -s 30               no sound
        """,
        version: "0.1.0"
    )

    @Argument(help: "Duration: 90, 5m, 1h30m, 25:00.")
    var timespec: String?

    @Option(name: [.short, .customLong("time")], help: "Duration, same syntax as the argument.")
    var time: String?

    @Option(name: [.short, .long], help: "Name shown above the countdown.")
    var name: String?

    @Flag(name: [.short, .long], help: "Show a floating window (arriving in v0.2).")
    var ui = false

    @Option(name: [.customShort("a"), .customLong("alert")],
            help: "Alert sound: a name from /System/Library/Sounds, or a path. Bare -a uses \(Alert.defaultSound).")
    var alert: String = Alert.defaultSound

    @Flag(name: [.short, .long], help: "Run without any sound.")
    var silent = false

    @Flag(help: "Keep ringing until a key is pressed.")
    var ring = false

    @Option(name: [.customShort("q"), .customLong("quit-after")],
            help: "Quit N seconds after the countdown ends.")
    var quitAfter: Double?

    @Flag(help: "List the available alert sounds and exit.")
    var listSounds = false

    /// ArgumentParser has no notion of an option whose value is optional, but
    /// `-a` on its own is part of the interface, so a bare `-a` gets the
    /// default value spliced in before parsing.
    static func main() {
        let arguments = expandBareAlertFlag(Array(CommandLine.arguments.dropFirst()))
        do {
            var command = try parseAsRoot(arguments)
            try command.run()
        } catch {
            exit(withError: error)
        }
    }

    static func expandBareAlertFlag(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            result.append(argument)
            if argument == "-a" || argument == "--alert" {
                let next = index + 1 < arguments.count ? arguments[index + 1] : nil
                let missingValue = next == nil || next!.hasPrefix("-")
                if missingValue {
                    result.append(Alert.defaultSound)
                }
            }
            index += 1
        }
        return result
    }

    func run() throws {
        if listSounds {
            print(Alert.availableSounds().joined(separator: "\n"))
            return
        }

        guard let spec = time ?? timespec else {
            throw ValidationError("give me a duration, e.g. tmr 5m")
        }

        let duration: TimeInterval
        do {
            duration = try DurationParser.parse(spec)
        } catch let error as DurationParseError {
            throw ValidationError(error.description)
        }

        if ui {
            warn("-u lands in v0.2; showing the terminal view for now")
        }

        var alertPlayer: Alert?
        if !silent {
            alertPlayer = Alert(sound: alert, loops: ring)
            if alertPlayer == nil {
                warn("sound '\(alert)' not found; falling back to the terminal bell")
            }
        }

        let engine = TimerEngine(duration: duration, name: name)
        let renderer: TimerRenderer = Terminal.isInteractive ? TUIRenderer() : PlainRenderer()

        renderer.start()
        defer { renderer.stop() }

        loop(engine: engine, renderer: renderer, alertPlayer: alertPlayer)
    }

    private func loop(engine: TimerEngine, renderer: TimerRenderer, alertPlayer: Alert?) {
        let frameInterval: useconds_t = 80_000   // 12.5 fps, cheap and smooth enough
        var finishedAt: Date?

        while true {
            let now = Date()

            if engine.update(now: now).contains(.finished) {
                finishedAt = now
                if let player = alertPlayer {
                    player.play()
                } else if !silent {
                    Terminal.bell()
                }
            }

            let snapshot = engine.snapshot(now: now)
            renderer.render(snapshot)
            alertPlayer?.pump()

            if let key = renderer.readKey() {
                if handle(key: key, engine: engine, now: now, finished: finishedAt != nil) {
                    alertPlayer?.stop()
                    return
                }
                // A revived timer starts a fresh countdown.
                if engine.snapshot(now: now).phase == .running {
                    finishedAt = nil
                    alertPlayer?.stop()
                }
            }

            if let finishedAt = finishedAt, shouldExit(finishedAt: finishedAt, now: now, alertPlayer: alertPlayer) {
                alertPlayer?.stop()
                return
            }

            usleep(frameInterval)
        }
    }

    /// Returns true when the loop should end.
    private func handle(key: Character, engine: TimerEngine, now: Date, finished: Bool) -> Bool {
        switch key {
        case "q", "Q", "\u{1B}", "\u{3}":
            engine.apply(.stop, now: now)
            return true
        case " ", "p", "P":
            if finished { return true }
            engine.apply(.toggle, now: now)
        case "+", "=":
            engine.apply(.adjust(60), now: now)
        case "-", "_":
            engine.apply(.adjust(-60), now: now)
        case "r", "R":
            engine.apply(.reset, now: now)
        default:
            // Any other key dismisses a ringing timer, and is ignored otherwise.
            if finished { return true }
        }
        return false
    }

    private func shouldExit(finishedAt: Date, now: Date, alertPlayer: Alert?) -> Bool {
        if ring {
            return false                                    // only a keypress ends it
        }
        if let quitAfter = quitAfter {
            return now.timeIntervalSince(finishedAt) >= quitAfter
        }
        if let player = alertPlayer {
            return !player.isPlaying                        // let the sound finish
        }
        return now.timeIntervalSince(finishedAt) >= 0.5
    }

    private func warn(_ message: String) {
        FileHandle.standardError.write(Data("tmr: \(message)\n".utf8))
    }
}
