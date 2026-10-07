import Foundation
import os

struct WorkspaceSidebarClockComponents {
    let hour: String
    let minute: String
    let second: String

    init(date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        hour = Self.format(components.hour)
        minute = Self.format(components.minute)
        second = Self.format(components.second)
    }

    private static func format(_ value: Int?) -> String {
        String(format: "%02d", value ?? 0)
    }
}

private struct SidebarClockDateLinesCacheEntry {
    let day: Date
    let locale: Locale
    let calendar: Calendar
    let weekday: String
    let monthAndDay: String
}

// One bounded entry shared by the visible clock and its accessibility label.
// Include the calendar (and its timezone) so locale and timezone changes invalidate it.
private let sidebarClockDateLinesCache = OSAllocatedUnfairLock<SidebarClockDateLinesCacheEntry?>(initialState: nil)

struct WorkspaceSidebarExpandedClockDateLines: Equatable {
    let weekday: String
    let monthAndDay: String

    init(
        date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let locale = locale == .autoupdatingCurrent ? Locale.current : locale
        let calendar = calendar == .autoupdatingCurrent ? Calendar.current : calendar
        let day = calendar.startOfDay(for: date)
        let lines = sidebarClockDateLinesCache.withLock { cached in
            if let cached, cached.day == day, cached.locale == locale, cached.calendar == calendar {
                return cached
            }
            let style = Date.FormatStyle(
                date: .omitted, time: .omitted, locale: locale,
                calendar: calendar, timeZone: calendar.timeZone
            )
            let lines = SidebarClockDateLinesCacheEntry(
                day: day, locale: locale, calendar: calendar,
                weekday: date.formatted(style.weekday(.wide)),
                monthAndDay: date.formatted(style.month(.wide).day())
            )
            cached = lines
            return lines
        }
        weekday = lines.weekday
        monthAndDay = lines.monthAndDay
    }
}

func workspaceSidebarExpandedClockDateLineCount(showsDate: Bool, showsWeekday: Bool) -> Int {
    (showsDate ? 1 : 0) + (showsWeekday ? 1 : 0)
}

func workspaceSidebarExpandedClockCardHeight(showsDate: Bool, showsWeekday: Bool) -> CGFloat {
    68 + CGFloat(workspaceSidebarExpandedClockDateLineCount(
        showsDate: showsDate,
        showsWeekday: showsWeekday
    )) * 19
}

func workspaceSidebarExpandedClockAccessibilitySummary(
    date: Date,
    showsSeconds: Bool,
    showsDate: Bool,
    showsWeekday: Bool,
    locale: Locale = .autoupdatingCurrent,
    calendar: Calendar = .autoupdatingCurrent
) -> String {
    let timeStyle = Date.FormatStyle(
        date: .omitted, time: showsSeconds ? .standard : .shortened,
        locale: locale, calendar: calendar, timeZone: calendar.timeZone
    )

    let dateLines = WorkspaceSidebarExpandedClockDateLines(
        date: date,
        locale: locale,
        calendar: calendar
    )
    var parts = [date.formatted(timeStyle)]
    if showsWeekday {
        parts.append(dateLines.weekday)
    }
    if showsDate {
        parts.append(dateLines.monthAndDay)
    }
    return parts.joined(separator: ", ")
}
