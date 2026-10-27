import Foundation
import Darwin
import Common

/// The replacement inode is private before it becomes visible at the destination.
func writePrivateData(_ data: Data, to url: URL) throws {
    assertTestWriteIsTemporary(url)
    let temporary = url.deletingLastPathComponent().appendingPathComponent(".winmuxx-\(UUID().uuidString)")
    guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer { try? FileManager.default.removeItem(at: temporary) }
    let handle = try FileHandle(forWritingTo: temporary)
    do { try handle.write(contentsOf: data); try handle.close() }
    catch { try? handle.close(); throw error }
    guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
