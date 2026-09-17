import XCTest
@testable import TimerCore

final class TimerEngineTests: XCTestCase {
    /// Every test drives the engine with explicit timestamps, so nothing here
    /// depends on wall-clock time and nothing sleeps.
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ offset: TimeInterval) -> Date {
        t0.addingTimeInterval(offset)
    }

    func testCountsDown() {
        let engine = TimerEngine(duration: 60, now: t0)
        XCTAssertEqual(engine.snapshot(now: t0).remaining, 60)
        XCTAssertEqual(engine.snapshot(now: at(20)).remaining, 40)
        XCTAssertEqual(engine.snapshot(now: at(20)).progress, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testFinishesExactlyOnce() {
        let engine = TimerEngine(duration: 10, now: t0)
        XCTAssertEqual(engine.update(now: at(9)), [])
        XCTAssertEqual(engine.update(now: at(10)), [.finished])
        XCTAssertEqual(engine.update(now: at(11)), [])
        XCTAssertEqual(engine.snapshot(now: at(11)).phase, .finished)
    }

    func testFinishTimestampIsTheDeadlineNotTheTick() {
        // A late frame must not smear the finish time, or overtime drifts.
        let engine = TimerEngine(duration: 10, now: t0)
        XCTAssertEqual(engine.update(now: at(13)), [.finished])
        XCTAssertEqual(engine.snapshot(now: at(13)).overtime, 3)
    }

    func testPauseFreezesRemaining() {
        let engine = TimerEngine(duration: 60, now: t0)
        XCTAssertEqual(engine.apply(.pause, now: at(20)), [.paused])
        XCTAssertEqual(engine.snapshot(now: at(20)).remaining, 40)
        XCTAssertEqual(engine.snapshot(now: at(100)).remaining, 40)
        XCTAssertEqual(engine.snapshot(now: at(100)).phase, .paused)
    }

    func testResumePushesTheDeadlineOut() {
        let engine = TimerEngine(duration: 60, now: t0)
        engine.apply(.pause, now: at(20))
        XCTAssertEqual(engine.apply(.resume, now: at(100)), [.resumed])
        XCTAssertEqual(engine.snapshot(now: at(100)).remaining, 40)
        XCTAssertEqual(engine.update(now: at(139)), [])
        XCTAssertEqual(engine.update(now: at(140)), [.finished])
    }

    func testPauseIsIdempotentAndToggleWorks() {
        let engine = TimerEngine(duration: 60, now: t0)
        XCTAssertEqual(engine.apply(.pause, now: at(10)), [.paused])
        XCTAssertEqual(engine.apply(.pause, now: at(11)), [])
        XCTAssertEqual(engine.apply(.toggle, now: at(12)), [.resumed])
        XCTAssertEqual(engine.apply(.toggle, now: at(13)), [.paused])
    }

    func testAddingTimeExtendsDeadlineAndTotal() {
        let engine = TimerEngine(duration: 60, now: t0)
        XCTAssertEqual(engine.apply(.adjust(60), now: at(10)), [.adjusted(60)])
        XCTAssertEqual(engine.total, 120)
        XCTAssertEqual(engine.snapshot(now: at(10)).remaining, 110)
    }

    func testSubtractingPastZeroFinishes() {
        let engine = TimerEngine(duration: 60, now: t0)
        let events = engine.apply(.adjust(-120), now: at(10))
        XCTAssertEqual(events, [.adjusted(-120), .finished])
        XCTAssertEqual(engine.snapshot(now: at(10)).phase, .finished)
    }

    func testAddingTimeRevivesAFinishedTimer() {
        let engine = TimerEngine(duration: 10, now: t0)
        engine.update(now: at(10))
        let events = engine.apply(.adjust(60), now: at(12))
        XCTAssertEqual(events, [.adjusted(60), .resumed])
        XCTAssertEqual(engine.snapshot(now: at(12)).phase, .running)
        XCTAssertEqual(engine.snapshot(now: at(12)).remaining, 60)
    }

    func testSubtractingFromAFinishedTimerDoesNothing() {
        let engine = TimerEngine(duration: 10, now: t0)
        engine.update(now: at(10))
        XCTAssertEqual(engine.apply(.adjust(-60), now: at(12)), [])
        XCTAssertEqual(engine.snapshot(now: at(12)).phase, .finished)
    }

    func testResetRestoresTheOriginalDuration() {
        let engine = TimerEngine(duration: 60, now: t0)
        engine.apply(.adjust(60), now: at(10))
        XCTAssertEqual(engine.apply(.reset, now: at(20)), [.reset])
        XCTAssertEqual(engine.total, 60)
        XCTAssertEqual(engine.snapshot(now: at(20)).remaining, 60)
        XCTAssertEqual(engine.update(now: at(80)), [.finished])
    }

    func testStopIsTerminal() {
        let engine = TimerEngine(duration: 60, now: t0)
        XCTAssertEqual(engine.apply(.stop, now: at(10)), [.stopped])
        XCTAssertEqual(engine.apply(.stop, now: at(11)), [])
        XCTAssertEqual(engine.apply(.resume, now: at(12)), [])
        XCTAssertEqual(engine.update(now: at(999)), [])
        XCTAssertEqual(engine.snapshot(now: at(999)).phase, .stopped)
    }

    func testRemainingNeverGoesNegative() {
        let engine = TimerEngine(duration: 10, now: t0)
        XCTAssertEqual(engine.snapshot(now: at(500)).remaining, 0)
        XCTAssertEqual(engine.snapshot(now: at(500)).progress, 1)
    }
}
