import Foundation

public enum DurationParseError: Error, Equatable, CustomStringConvertible {
    case empty
    case invalidFormat(String)
    case unknownUnit(String)
    case notPositive

    public var description: String {
        switch self {
        case .empty:
            return "no duration given"
        case .invalidFormat(let input):
            return "cannot read '\(input)' as a duration (try 90, 5m, 1h30m, 25:00)"
        case .unknownUnit(let unit):
            return "unknown time unit '\(unit)' (use ms, s, m, h, d)"
        case .notPositive:
            return "duration must be greater than zero"
        }
    }
}

public enum DurationParser {
    private static let units: [(String, TimeInterval)] = [
        ("ms", 0.001),
        ("s", 1), ("sec", 1), ("secs", 1), ("second", 1), ("seconds", 1),
        ("m", 60), ("min", 60), ("mins", 60), ("minute", 60), ("minutes", 60),
        ("h", 3600), ("hr", 3600), ("hrs", 3600), ("hour", 3600), ("hours", 3600),
        ("d", 86400), ("day", 86400), ("days", 86400),
    ]

    /// Accepts three shapes:
    ///   bare number  -> seconds, like `sleep`:        "90"
    ///   unit form    -> any order, spaces optional:   "5m", "1h30m", "1h 5m 30s", "1.5m"
    ///   colon form   -> mm:ss or hh:mm:ss:            "25:00", "1:02:03"
    public static func parse(_ raw: String) throws -> TimeInterval {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !input.isEmpty else { throw DurationParseError.empty }

        let total = input.contains(":")
            ? try parseColonForm(input, original: raw)
            : try parseUnitForm(input.replacingOccurrences(of: " ", with: ""), original: raw)

        guard total > 0 else { throw DurationParseError.notPositive }
        return total
    }

    private static func parseColonForm(_ input: String, original: String) throws -> TimeInterval {
        let parts = input.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3 else {
            throw DurationParseError.invalidFormat(original)
        }

        var values: [Double] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isNumber }), let value = Double(part) else {
                throw DurationParseError.invalidFormat(original)
            }
            values.append(value)
        }

        // Every component but the first is a real clock field.
        for value in values.dropFirst() where value > 59 {
            throw DurationParseError.invalidFormat(original)
        }

        if values.count == 2 {
            return values[0] * 60 + values[1]
        }
        return values[0] * 3600 + values[1] * 60 + values[2]
    }

    private static func parseUnitForm(_ input: String, original: String) throws -> TimeInterval {
        var total: TimeInterval = 0
        var index = input.startIndex
        var sawToken = false

        while index < input.endIndex {
            var numberEnd = index
            while numberEnd < input.endIndex, input[numberEnd].isNumber || input[numberEnd] == "." {
                numberEnd = input.index(after: numberEnd)
            }
            guard numberEnd > index, let value = Double(input[index..<numberEnd]) else {
                throw DurationParseError.invalidFormat(original)
            }

            var unitEnd = numberEnd
            while unitEnd < input.endIndex, input[unitEnd].isLetter {
                unitEnd = input.index(after: unitEnd)
            }
            let unit = String(input[numberEnd..<unitEnd])

            if unit.isEmpty {
                // A bare number is only allowed on its own, and then it means seconds.
                guard !sawToken, unitEnd == input.endIndex else {
                    throw DurationParseError.invalidFormat(original)
                }
                total += value
            } else {
                guard let multiplier = multiplier(for: unit) else {
                    throw DurationParseError.unknownUnit(unit)
                }
                total += value * multiplier
            }

            sawToken = true
            index = unitEnd
        }

        guard sawToken else { throw DurationParseError.invalidFormat(original) }
        return total
    }

    private static func multiplier(for unit: String) -> TimeInterval? {
        for (name, value) in units where name == unit {
            return value
        }
        return nil
    }
}

public enum TimeFormatting {
    /// Remaining time is rounded up, so a 60s timer shows 01:00 on the first
    /// frame and only reaches 00:00 when it is genuinely over.
    public static func clock(_ interval: TimeInterval, forceHours: Bool = false) -> String {
        let totalSeconds = Int(ceil(max(0, interval)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 || forceHours {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Human-readable total, used in log lines and the plain (non-TTY) output.
    public static func compact(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(ceil(max(0, interval)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds)s") }
        return parts.joined()
    }
}
