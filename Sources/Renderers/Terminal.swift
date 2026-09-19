import Darwin
import Foundation

/// Saved outside the enum so the SIGINT handler, which cannot capture context,
/// can still put the terminal back the way it found it.
private var savedTermios: termios?

/// Set from the SIGINT handler, which may not touch anything else.
private var interruptCount: sig_atomic_t = 0

public enum Terminal {
    public static var isInteractive: Bool {
        isatty(STDOUT_FILENO) == 1 && isatty(STDIN_FILENO) == 1
    }

    public static func size() -> (columns: Int, rows: Int) {
        var window = winsize()
        // NOTE: if this line fails to compile on your toolchain, the fix is the
        // cast on TIOCGWINSZ, e.g. UInt(bitPattern: Int(TIOCGWINSZ)).
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &window) == 0,
           window.ws_col > 0, window.ws_row > 0 {
            return (Int(window.ws_col), Int(window.ws_row))
        }
        return (80, 24)
    }

    public static func enableRawMode() {
        guard isInteractive else { return }
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return }
        savedTermios = original

        var raw = original
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON))

        // Polling reads via VMIN/VTIME, deliberately NOT via O_NONBLOCK on
        // STDIN_FILENO: in a terminal, stdin and stdout share one open file
        // description, so that flag would also make writes fail with EAGAIN.
        withUnsafeMutablePointer(to: &raw.c_cc) { pointer in
            pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { cc in
                cc[Int(VMIN)] = 0
                cc[Int(VTIME)] = 0
            }
        }

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    public static func restoreMode() {
        guard var original = savedTermios else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        savedTermios = nil
    }

    public static func readKey() -> Character? {
        var byte: UInt8 = 0
        let count = read(STDIN_FILENO, &byte, 1)
        guard count == 1 else { return nil }
        return Character(UnicodeScalar(byte))
    }

    // MARK: - ANSI

    /// Writes straight to the fd. FileHandle.write raises an ObjC exception on
    /// any error, including a transient EAGAIN, and a timer has no business
    /// aborting because a terminal buffer was briefly full.
    public static func write(_ text: String) {
        let bytes = Array(text.utf8)
        var offset = 0

        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBufferPointer { buffer in
                Darwin.write(STDOUT_FILENO, buffer.baseAddress, buffer.count)
            }

            if written > 0 {
                offset += written
                continue
            }
            if written < 0 && errno == EINTR {
                continue
            }
            if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                usleep(1_000)
                continue
            }
            return                  // a real error: drop the frame, keep the timer alive
        }
    }

    public static func hideCursor() { write("\u{1B}[?25l") }
    public static func showCursor() { write("\u{1B}[?25h") }
    public static func clearToEnd() { write("\u{1B}[J") }
    public static func moveUp(_ lines: Int) { if lines > 0 { write("\u{1B}[\(lines)A") } }
    public static func bell() { write("\u{7}") }

    /// True once the person has pressed Ctrl-C. Drivers poll this and shut
    /// down in an orderly way, which matters when a BUSY Bar is showing our
    /// layer: killing the process outright would leave it stuck on the device.
    /// A second Ctrl-C is the escape hatch and exits immediately.
    public static var wasInterrupted: Bool { interruptCount > 0 }

    public static func installInterruptHandler() {
        signal(SIGINT) { _ in
            interruptCount += 1
            if interruptCount > 1 {
                Terminal.restoreMode()
                Terminal.showCursor()
                _exit(130)
            }
        }
    }
}

public enum Style {
    public static let reset = "\u{1B}[0m"
    public static let bold = "\u{1B}[1m"
    public static let dim = "\u{1B}[2m"
    public static let red = "\u{1B}[31m"
    public static let green = "\u{1B}[32m"
    public static let yellow = "\u{1B}[33m"
    public static let cyan = "\u{1B}[36m"
}
