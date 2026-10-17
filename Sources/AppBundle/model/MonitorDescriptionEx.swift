import Common

extension MonitorDescription {
    func resolveMonitor(sortedMonitors: [Monitor]) -> Monitor? {
        return switch self {
            case .sequenceNumber(let number): sortedMonitors.getOrNil(atIndex: number - 1)
            case .uuid(let uuid): sortedMonitors.filter { $0.displayUUID?.caseInsensitiveCompare(uuid) == .orderedSame }.singleOrNil()
            case .hardware(let identity): sortedMonitors.filter { $0.hardwareIdentity == identity }.singleOrNil()
            case .main: mainMonitor
            case .pattern(_, let regex): sortedMonitors.first { monitor in monitor.name.contains(regex.val) }
            case .secondary:
                sortedMonitors.takeIf { $0.count == 2 }?
                    .first { $0.rect.topLeftCorner != mainMonitor.rect.topLeftCorner }
        }
    }
}
