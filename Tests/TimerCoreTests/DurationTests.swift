import XCTest
@testable import TimerCore

final class DurationTests: XCTestCase {
    func testBareNumberIsSeconds() throws {
        XCTAssertEqual(try DurationParser.parse("90"), 90)
        XCTAssertEqual(try DurationParser.parse(" 5 "), 5)
    }

    func testSingleUnits() throws {
        XCTAssertEqual(try DurationParser.parse("30s"), 30)
        XCTAssertEqual(try DurationParser.parse("5m"), 300)
        XCTAssertEqual(try DurationParser.parse("2h"), 7200)
        XCTAssertEqual(try DurationParser.parse("1d"), 86400)
        XCTAssertEqual(try DurationParser.parse("250ms"), 0.25, accuracy: 0.0001)
    }

    func testCompoundUnits() throws {
        XCTAssertEqual(try DurationParser.parse("1h30m"), 5400)
        XCTAssertEqual(try DurationParser.parse("1h 5m 30s"), 3930)
        XCTAssertEqual(try DurationParser.parse("1H30M"), 5400)
    }

    func testLongUnitNames() throws {
        XCTAssertEqual(try DurationParser.parse("2min"), 120)
        XCTAssertEqual(try DurationParser.parse("3hours"), 10800)
    }

    func testFractions() throws {
        XCTAssertEqual(try DurationParser.parse("1.5m"), 90)
    }

    func testColonForm() throws {
        XCTAssertEqual(try DurationParser.parse("25:00"), 1500)
        XCTAssertEqual(try DurationParser.parse("1:02:03"), 3723)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try DurationParser.parse(""))
        XCTAssertThrowsError(try DurationParser.parse("abc"))
        XCTAssertThrowsError(try DurationParser.parse("5x"))
        XCTAssertThrowsError(try DurationParser.parse("0"))
        XCTAssertThrowsError(try DurationParser.parse("5m30"))     // stray number
        XCTAssertThrowsError(try DurationParser.parse("1:2:3:4"))
        XCTAssertThrowsError(try DurationParser.parse("1:99"))     // not a clock value
    }

    func testUnknownUnitIsNamed() {
        XCTAssertThrowsError(try DurationParser.parse("5w")) { error in
            XCTAssertEqual(error as? DurationParseError, .unknownUnit("w"))
        }
    }

    func testClockFormattingRoundsUp() {
        XCTAssertEqual(TimeFormatting.clock(60), "01:00")
        XCTAssertEqual(TimeFormatting.clock(59.4), "01:00")
        XCTAssertEqual(TimeFormatting.clock(0), "00:00")
        XCTAssertEqual(TimeFormatting.clock(3723), "1:02:03")
    }

    func testCompactFormatting() {
        XCTAssertEqual(TimeFormatting.compact(90), "1m30s")
        XCTAssertEqual(TimeFormatting.compact(3600), "1h")
        XCTAssertEqual(TimeFormatting.compact(0), "0s")
    }
}
