import Foundation

/// Plays the end-of-timer sound. Uses `afplay` rather than NSSound so the CLI
/// does not need an AppKit run loop, and so the same code path works whether or
/// not a window is on screen.
public final class Alert {
    public static let defaultSound = "Glass"
    public static let systemSoundsDirectory = "/System/Library/Sounds"

    private let url: URL
    private let loops: Bool
    private var process: Process?
    private var stoppedByUser = false

    /// `sound` is either a name from /System/Library/Sounds ("Glass",
    /// "Submarine") or a path to an audio file.
    public init?(sound: String, loops: Bool) {
        guard let url = Alert.resolve(sound) else { return nil }
        self.url = url
        self.loops = loops
    }

    public static func resolve(_ sound: String) -> URL? {
        let expanded = (sound as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return FileManager.default.fileExists(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }

        let candidates = [
            "\(systemSoundsDirectory)/\(sound).aiff",
            "\(NSHomeDirectory())/Library/Sounds/\(sound).aiff",
            "\(systemSoundsDirectory)/\(sound)",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    public static func availableSounds() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: systemSoundsDirectory)) ?? []
        return contents
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(".aiff".count)) }
            .sorted()
    }

    public func play() {
        stoppedByUser = false
        spawn()
    }

    /// Call once per frame. Restarts the sound when looping is on.
    public func pump() {
        guard loops, !stoppedByUser else { return }
        if let process = process, process.isRunning { return }
        spawn()
    }

    public var isPlaying: Bool {
        process?.isRunning ?? false
    }

    public func stop() {
        stoppedByUser = true
        if let process = process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    private func spawn() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        task.arguments = [url.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            process = task
        } catch {
            // No afplay, or the file went away mid-run. A terminal bell is a
            // better outcome here than crashing a timer that already fired.
            Terminal.bell()
            process = nil
        }
    }
}
