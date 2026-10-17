@testable import Common
import Network
import XCTest

private actor FrameInput {
    var bytes: Data
    private(set) var reads = 0
    init(_ bytes: Data) { self.bytes = bytes }
    func receive(_ minimum: Int, _ maximum: Int) -> Result<IPCReadChunk, NWError> {
        reads += 1
        let chunk = Data(bytes.prefix(min(2, maximum)))
        bytes.removeFirst(chunk.count)
        return .success(IPCReadChunk(data: chunk, complete: bytes.isEmpty))
    }
}

final class IPCFrameTest: XCTestCase {
    private func framed(_ text: String) -> Data {
        let payload = Data(text.utf8)
        return withUnsafeBytes(of: UInt32(payload.count)) { Data($0) } + payload
    }
    func testPartialReadsAndConsecutiveFramesKeepBoundaries() async throws {
        let input = FrameInput(framed("hello") + framed("world"))
        for expected in ["hello", "world"] {
            let result = await readIPCFrame { await input.receive($0, $1) }
            XCTAssertEqual(try result.get(), Data(expected.utf8))
        }
    }
    func testOversizedHeaderIsRejectedWithoutReadingItsPayload() async {
        let input = FrameInput(withUnsafeBytes(of: UInt32.max) { Data($0) })
        let result = await readIPCFrame { await input.receive($0, $1) }
        guard case .failure(.posix(.EMSGSIZE)) = result else { return XCTFail("Expected frame limit") }
        let reads = await input.reads
        XCTAssertEqual(reads, 2)
    }
    func testEarlyEofAndTruncatedFramesTerminate() async {
        for bytes in [Data(), Data([1, 2]), Data(framed("hello").dropLast())] {
            let input = FrameInput(bytes)
            let result = await readIPCFrame { await input.receive($0, $1) }
            guard case .failure = result else { return XCTFail("Expected EOF failure") }
        }
    }
    func testEmptyPayloadIsAValidFrameAndCancellationStopsReads() async throws {
        let input = FrameInput(framed(""))
        let result = await readIPCFrame { await input.receive($0, $1) }
        XCTAssertEqual(try result.get(), Data())
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await readIPCFrame { _, _ in XCTFail("Cancelled read reached transport"); return .success(IPCReadChunk(data: Data(), complete: true)) }
        }
        guard case .failure(.posix(.ECANCELED)) = await cancelled.value else { return XCTFail("Expected cancellation") }
    }
}
