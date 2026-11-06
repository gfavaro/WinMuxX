import CoreGraphics

@MainActor
func logWindowDragHitTestIfNeeded(signature: @autoclosure () -> String, _ message: @autoclosure () -> String) {
    guard isDebug else { return }
    let signature = signature()
    guard lastWindowDragHitTestLogSignature != signature else { return }
    lastWindowDragHitTestLogSignature = signature
    debugLog(.focus, message())
}

@MainActor
func logWindowDragIntentIfNeeded(signature: @autoclosure () -> String, _ message: @autoclosure () -> String) {
    guard isDebug else { return }
    let signature = signature()
    guard lastWindowDragIntentLogSignature != signature else { return }
    lastWindowDragIntentLogSignature = signature
    debugLog(.focus, message())
}

@MainActor
func logWindowDragLive(_ message: @autoclosure () -> String) {
    debugLog(.focus, "[drag-live] \(message())")
}

func debugDescribeDragPointBucket(_ point: CGPoint) -> String {
    let bucketSize = CGFloat(80)
    let x = Int((point.x / bucketSize).rounded(.down))
    let y = Int((point.y / bucketSize).rounded(.down))
    return "\(x),\(y)"
}
