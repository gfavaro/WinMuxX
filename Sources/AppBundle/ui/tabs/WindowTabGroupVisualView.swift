import SwiftUI

struct WindowTabGroupVisualView: View {
    let strip: WindowTabStripViewModel

    var body: some View {
        GeometryReader { proxy in
            WindowTabGroupFrameView(
                strip: strip,
                groupSize: proxy.size,
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .modifier(ChromeResolvedAppearance())
        .windowTabOcclusionMasked(
            panelFrame: strip.groupFrame,
            occludingScreenFrames: strip.occludingFloatingWindowFrames,
        )
    }
}
