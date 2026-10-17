import Foundation
import Network

public let maximumIPCFrameBytes = 16 * 1024 * 1024

struct IPCReadChunk: Sendable {
    let data: Data
    let complete: Bool
}

/// Preserve the existing native-endian header while bounding allocation and EOF handling.
func readIPCFrame(receive: @Sendable (Int, Int) async -> Result<IPCReadChunk, NWError>) async -> Result<Data, NWError> {
    func read(_ count: Int) async -> Result<Data, NWError> {
        var result = Data()
        while result.count < count {
            if Task.isCancelled { return .failure(.posix(.ECANCELED)) }
            let remaining = min(65536, count - result.count)
            switch await receive(1, remaining) {
                case .failure(let error): return .failure(error)
                case .success(let chunk):
                    guard !chunk.data.isEmpty, chunk.data.count <= remaining else { return .failure(.posix(.ECONNRESET)) }
                    result.append(chunk.data)
                    if chunk.complete && result.count < count { return .failure(.posix(.ECONNRESET)) }
            }
        }
        return .success(result)
    }
    switch await read(4) {
        case .failure(let error): return .failure(error)
        case .success(let header):
            let count = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            guard count <= maximumIPCFrameBytes else { return .failure(.posix(.EMSGSIZE)) }
            return await read(Int(count))
    }
}
