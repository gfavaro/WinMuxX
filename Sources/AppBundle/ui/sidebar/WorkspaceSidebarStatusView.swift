import AppKit
import Foundation
import SwiftUI

private struct WorkspaceSidebarClockDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    var workspaceSidebarClockDate: Date? {
        get { self[WorkspaceSidebarClockDateKey.self] }
        set { self[WorkspaceSidebarClockDateKey.self] = newValue }
    }
}

struct WorkspaceSidebarStatusView: View {
    @Environment(\.workspaceSidebarClockDate) private var clockDate
    let sectionWidth: CGFloat
    let isCompact: Bool
    let showsSeconds: Bool
    let showsDate: Bool
    let showsWeekday: Bool

    var body: some View {
        Group {
            if let clockDate {
                clockCard(date: clockDate)
            } else if showsSeconds {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    clockCard(date: context.date)
                }
            } else {
                TimelineView(.everyMinute) { context in
                    clockCard(date: context.date)
                }
            }
        }
        .frame(width: sectionWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.16), value: isCompact)
    }

    @ViewBuilder
    private func clockCard(date: Date) -> some View {
        if isCompact {
            WorkspaceSidebarCompactClockCard(date: date, sectionWidth: sectionWidth, showsSeconds: showsSeconds)
        } else {
            WorkspaceSidebarExpandedStatusCard(
                date: date, sectionWidth: sectionWidth, showsSeconds: showsSeconds,
                showsDate: showsDate, showsWeekday: showsWeekday
            )
        }
    }
}
