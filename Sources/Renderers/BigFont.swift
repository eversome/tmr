import Foundation

/// A 3x5 pixel font. Deliberately tiny: the BUSY Bar's main display is 72x16,
/// so the same glyphs scaled 3x fill it almost exactly (15 of 16 rows), and the
/// terminal view and the bar can share one renderer later.
public enum BigFont {
    public static let glyphHeight = 5

    private static let glyphs: [Character: [String]] = [
        "0": ["###", "#.#", "#.#", "#.#", "###"],
        "1": ["..#", "..#", "..#", "..#", "..#"],
        "2": ["###", "..#", "###", "#..", "###"],
        "3": ["###", "..#", "###", "..#", "###"],
        "4": ["#.#", "#.#", "###", "..#", "..#"],
        "5": ["###", "#..", "###", "..#", "###"],
        "6": ["###", "#..", "###", "#.#", "###"],
        "7": ["###", "..#", "..#", "..#", "..#"],
        "8": ["###", "#.#", "###", "#.#", "###"],
        "9": ["###", "#.#", "###", "..#", "###"],
        ":": ["...", ".#.", "...", ".#.", "..."],
        ".": ["...", "...", "...", "...", ".#."],
        "-": ["...", "...", "###", "...", "..."],
        " ": ["...", "...", "...", "...", "..."],
    ]

    /// Renders text into `glyphHeight` lines. Each pixel becomes `scale`
    /// characters wide, which compensates for the aspect ratio of a terminal
    /// cell. Unknown characters render as blanks rather than throwing.
    public static func render(_ text: String, scale: Int = 2, on: String = "█", off: String = " ") -> [String] {
        var lines = [String](repeating: "", count: glyphHeight)
        let onRun = String(repeating: on, count: scale)
        let offRun = String(repeating: off, count: scale)

        for (index, character) in text.enumerated() {
            let glyph = glyphs[character] ?? glyphs[" "]!
            for row in 0..<glyphHeight {
                var line = ""
                for pixel in glyph[row] {
                    line += (pixel == "#") ? onRun : offRun
                }
                lines[row] += line
                if index < text.count - 1 {
                    lines[row] += offRun
                }
            }
        }

        return lines
    }

    public static func width(of text: String, scale: Int = 2) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.count * 3 * scale + (text.count - 1) * scale
    }
}
