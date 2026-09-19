import ArgumentParser
import Darwin
import Foundation
import Renderers
import TimerCore

@main
struct Tmr: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tmr",
        abstract: "A countdown timer for the terminal or a floating window, with a sound at the end.",
        discussion: """
        Examples:
          tmr 5m                  five minutes, default sound
          tmr -u -a -t 1m         floating window, default sound
          tmr -t 25m -n focus     named timer
          tmr -a Submarine 90     pick a system sound
          tmr -a ~/gong.wav 1h    pick a file
          tmr -s 30               no sound
        """,
        version: "0.2.0"
    )

    @Argument(help: "Duration: 90, 5m, 1h30m, 25:00.")
    var timespec: String?

    @Option(name: [.short, .customLong("time")], help: "Duration, same syntax as the argument.")
    var time: String?

    @Option(name: [.short, .long], help: "Name shown next to the countdown.")
    var name: String?

    @Flag(name: [.short, .long], help: "Show a floating window instead of the terminal view.")
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
                if next == nil || next!.hasPrefix("-") {
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

        var alertPlayer: Alert?
        if !silent {
            alertPlayer = Alert(sound: alert, loops: ring)
            if alertPlayer == nil {
                warn("sound '\(alert)' not found; falling back to the terminal bell")
            }
        }

        let engine = TimerEngine(duration: duration, name: name)
        let policy = SessionPolicy(ring: ring, quitAfter: quitAfter, silent: silent)

        if ui {
            HUDDriver(engine: engine, alert: alertPlayer, policy: policy).run()
        } else {
            TerminalDriver(engine: engine, alert: alertPlayer, policy: policy).run()
        }
    }

    private func warn(_ message: String) {
        FileHandle.standardError.write(Data("tmr: \(message)\n".utf8))
    }
}
