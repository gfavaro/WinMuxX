import AppKit
import Darwin

/// App bundles identify snapping tools too; process names also cover command-line tilers.
@MainActor
func runningOtherWindowManagers() -> [String] {
    let apps = otherTilingManagers(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    let capacity = max(Int(proc_listallpids(nil, 0)), 0) + 128
    var pids = [pid_t](repeating: 0, count: capacity)
    let count = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride))
    var processNames: [String] = []
    for pid in pids.prefix(min(max(Int(count), 0), capacity)) where pid > 0 && pid != getpid() {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { continue }
        processNames.append(String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }
    return Array(Set(apps + otherTilingManagerProcesses(processNames))).sorted()
}

func otherTilingManagerProcesses(_ processNames: [String]) -> [String] {
    let known = [
        "aerospace": "AeroSpace", "amethyst": "Amethyst", "yabai": "yabai",
        "kiwidesk": "KiwiDesk", "dinky": "Dinky",
    ]
    return Set(processNames.compactMap { known[$0.lowercased()] }).sorted()
}
