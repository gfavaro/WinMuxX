@testable import AppBundle
import Foundation
import XCTest

final class WorkspaceSidebarClockComponentsTest: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var thursdayJanuary31: Date {
        calendar.date(from: DateComponents(year: 2030, month: 1, day: 31, hour: 12, minute: 34, second: 56))!
    }

    func testExpandedClockUsesSeparateFullEnglishWeekdayAndMonthDayLines() {
        let lines = WorkspaceSidebarExpandedClockDateLines(
            date: thursdayJanuary31,
            locale: Locale(identifier: "en_US"),
            calendar: calendar
        )

        XCTAssertEqual(lines.weekday, "Thursday")
        XCTAssertEqual(lines.monthAndDay, "January 31")
    }

    func testExpandedClockKeepsLongLocalizedDateTextUnabbreviated() {
        let lines = WorkspaceSidebarExpandedClockDateLines(
            date: thursdayJanuary31,
            locale: Locale(identifier: "de_DE"),
            calendar: calendar
        )

        XCTAssertEqual(lines.weekday, "Donnerstag")
        XCTAssertEqual(lines.monthAndDay, "31. Januar")
    }

    func testCachedDateLinesUpdateAtMidnightAndWhenTimezoneChanges() {
        let midnight = calendar.date(from: DateComponents(year: 2030, month: 2, day: 1))!
        let locale = Locale(identifier: "en_US")
        let before = WorkspaceSidebarExpandedClockDateLines(date: midnight.addingTimeInterval(-1), locale: locale, calendar: calendar)
        let after = WorkspaceSidebarExpandedClockDateLines(date: midnight, locale: locale, calendar: calendar)
        XCTAssertEqual(before.monthAndDay, "January 31")
        XCTAssertEqual(after.monthAndDay, "February 1")
        XCTAssertEqual(after.weekday, "Friday")

        var westCalendar = calendar
        westCalendar.timeZone = TimeZone(secondsFromGMT: -8 * 3600)!
        let west = WorkspaceSidebarExpandedClockDateLines(date: midnight, locale: locale, calendar: westCalendar)
        XCTAssertEqual(west.monthAndDay, "January 31")
        XCTAssertEqual(west.weekday, "Thursday")
    }

    func testExpandedClockDateAndWeekdayLinesAreIndependent() {
        XCTAssertEqual(workspaceSidebarExpandedClockDateLineCount(showsDate: false, showsWeekday: false), 0)
        XCTAssertEqual(workspaceSidebarExpandedClockDateLineCount(showsDate: true, showsWeekday: false), 1)
        XCTAssertEqual(workspaceSidebarExpandedClockDateLineCount(showsDate: false, showsWeekday: true), 1)
        XCTAssertEqual(workspaceSidebarExpandedClockDateLineCount(showsDate: true, showsWeekday: true), 2)
    }

    func testExpandedClockGrowsForEachVisibleDateLine() {
        XCTAssertEqual(workspaceSidebarExpandedClockCardHeight(showsDate: false, showsWeekday: false), 68)
        XCTAssertEqual(workspaceSidebarExpandedClockCardHeight(showsDate: true, showsWeekday: false), 87)
        XCTAssertEqual(workspaceSidebarExpandedClockCardHeight(showsDate: true, showsWeekday: true), 106)
    }

    func testExpandedClockAccessibilityKeepsDateAndWeekdayIndependent() {
        let weekdayOnly = workspaceSidebarExpandedClockAccessibilitySummary(
            date: thursdayJanuary31,
            showsSeconds: false,
            showsDate: false,
            showsWeekday: true,
            locale: Locale(identifier: "en_US"),
            calendar: calendar
        )
        let dateOnly = workspaceSidebarExpandedClockAccessibilitySummary(
            date: thursdayJanuary31,
            showsSeconds: false,
            showsDate: true,
            showsWeekday: false,
            locale: Locale(identifier: "en_US"),
            calendar: calendar
        )

        XCTAssertTrue(weekdayOnly.contains("Thursday"))
        XCTAssertFalse(weekdayOnly.contains("January"))
        XCTAssertTrue(dateOnly.contains("January 31"))
        XCTAssertFalse(dateOnly.contains("Thursday"))
    }
}
