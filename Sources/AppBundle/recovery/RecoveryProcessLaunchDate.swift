import Darwin
import Foundation

/// LaunchServices can omit the launch date of a directly launched menu-bar app.
/// The kernel's process birth time supplies a stable PID-reuse-safe fallback.
func recoveryProcessLaunchDate(_ pid: Int32) -> Date? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
    guard count == size, info.pbi_start_tvsec > 0 else { return nil }
    return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
}
