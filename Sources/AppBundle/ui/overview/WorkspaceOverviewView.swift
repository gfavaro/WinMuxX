import AppKit
import SwiftUI

struct WorkspaceOverviewView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.workspaceSidebarPreviewAccessibility) private var previewAccessibility
    @AccessibilityFocusState private var accessibilitySelection: WorkspaceOverviewAccessibilitySelection?
    @ObservedObject var model: WorkspaceOverviewDisplayModel
    let monitorName: String
    private var increasedContrast: Bool { contrast == .increased || previewAccessibility.increasedContrast }
    var body: some View {
        GeometryReader { geometry in
            let metrics = WorkspaceOverviewGridMetrics(availableHeight: geometry.size.height)
            VStack(spacing: 18) {
                HStack {
                    Text("Workspace Overview").font(.title2.bold())
                    Text(monitorName).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Close", action: { model.dismiss?() }).keyboardShortcut(.cancelAction)
                }
                HStack {
                    Text(keyHint).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).help(keyHint)
                    Spacer()
                    Button("Previous", action: { model.changePage(-1) }).disabled(model.page == 0)
                    Text("\(model.page + 1) / \(model.pageCount)").monospacedDigit()
                    Button("Next", action: { model.changePage(1) }).disabled(model.page + 1 >= model.pageCount)
                }
                if metrics.scrolls {
                    // Small displays cannot fit three rows at the minimum card size.
                    ScrollViewReader { proxy in
                        ScrollView { grid(cardHeight: metrics.cardHeight) }
                            // The opening selection is set before the view appears; reveal it too.
                            .onAppear { if let id = model.selectedCard?.id { proxy.scrollTo(id) } }
                            .onChange(of: model.selection) { _ in
                                if let id = model.selectedCard?.id { proxy.scrollTo(id) }
                            }
                    }
                } else {
                    grid(cardHeight: metrics.cardHeight)
                }
                if model.cards.isEmpty { Text("No workspaces on this display in the current project.").foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }.padding(32)
        }
        .onAppear { accessibilitySelection = model.accessibilitySelection }
        .onChange(of: model.accessibilitySelection) { accessibilitySelection = $0 }
        .onChange(of: accessibilitySelection) { model.syncAccessibilityFocus($0) }
        .onChange(of: model.focusRequest) { _ in accessibilitySelection = model.accessibilitySelection }
        .background {
            // One shared surface; cards do not allocate additional blur layers.
            OverlaySurface()
            .contentShape(Rectangle())
            .onTapGesture { model.dismiss?() }
        }
        .modifier(OverlayAppearance(monitor: model.monitor))
    }

    private var keyHint: String {
        "Arrow keys select workspace · Tab selects window · Return opens · Esc closes"
            + (model.canSwitchDisplay ? " · [ ] switch display" : "")
    }

    private func grid(cardHeight: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 4), spacing: 18) {
            ForEach(model.visibleCards) { card in
                VStack(spacing: 6) {
                    desktop(card)
                        .aspectRatio(card.desktopSize.width / max(1, card.desktopSize.height), contentMode: .fit)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(model.selectedCard?.id == card.id ? Color(nsColor: winMuxAccentColor) : Color(nsColor: .separatorColor), lineWidth: model.selectedCard?.id == card.id ? 3 : (increasedContrast ? 2 : 1)))
                        .frame(maxWidth: .infinity, maxHeight: cardHeight, alignment: .top)
                    Button(card.title) { model.activate?(card.id, nil) }.buttonStyle(.plain)
                        .lineLimit(1).truncationMode(.middle)
                        .accessibilityHidden(true) // The desktop button already exposes this action.
                    let unknown = card.windows.filter { $0.frame == nil }
                    if !unknown.isEmpty {
                        Menu("\(unknown.count) windows without saved positions") {
                            ForEach(unknown) { window in
                                Button(window.title) { model.activate?(card.id, window.id) }
                                    .accessibilityLabel("\(window.appName): \(window.title)")
                                    .accessibilityAddTraits(model.selectedWindow == window.id ? .isSelected : [])
                            }
                        }.lineLimit(1)
                    }
                }.frame(height: cardHeight + 48, alignment: .top).id(card.id)
            }
        }
    }

    private func desktop(_ card: WorkspaceOverviewCard) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Button { model.activate?(card.id, nil) } label: {
                    ZStack {
                        Color(nsColor: .underPageBackgroundColor)
                        if let image = model.images[card.id] {
                            Image(decorative: image, scale: 1).resizable().interpolation(.medium)
                        } else if card.windows.isEmpty {
                            Text("Empty workspace").foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open workspace \(card.title)")
                    .accessibilityAddTraits(model.accessibilitySelection == .workspace(card.id) ? .isSelected : [])
                    .accessibilityValue(model.selectedCard?.id == card.id ? card.windows.first(where: { $0.id == model.selectedWindow }).map { "Selected window: \($0.title)" } ?? "" : "")
                    .accessibilityFocused($accessibilitySelection, equals: .workspace(card.id))
                    .help("\(card.title) · \(card.windows.count) windows")
                ForEach(card.windows) { window in
                    if let rect = window.frame, rect.intersects(CGRect(x: 0, y: 0, width: 1, height: 1)) {
                        Button { model.activate?(card.id, window.id) } label: {
                            VStack(spacing: 0) {
                                HStack(spacing: 3) {
                                    if let icon = window.icon { Image(nsImage: icon).resizable().frame(width: 12, height: 12) }
                                    Text(window.title).font(.system(size: 10)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.padding(3).foregroundStyle(.primary)
                                    .background(Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency || previewAccessibility.reduceTransparency || increasedContrast ? 1 : 0.92))
                                Spacer(minLength: 0)
                            }
                            .frame(width: max(1, rect.width * geometry.size.width), height: max(1, rect.height * geometry.size.height))
                            .background(model.images[card.id] == nil ? Color.gray.opacity(0.25) : .clear)
                            .overlay(Rectangle().stroke(model.selectedWindow == window.id && model.selectedCard?.id == card.id ? Color(nsColor: winMuxAccentColor) : Color(nsColor: .separatorColor), lineWidth: model.selectedWindow == window.id ? 3 : (increasedContrast ? 2 : 1)))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(window.appName): \(window.title), workspace \(card.title)")
                            .accessibilityAddTraits(model.selectedWindow == window.id && model.selectedCard?.id == card.id ? .isSelected : [])
                            .accessibilityFocused($accessibilitySelection, equals: .window(window.id))
                            .accessibilityHint("Open this window")
                            .help("\(window.appName): \(window.title)")
                            .offset(x: rect.minX * geometry.size.width, y: rect.minY * geometry.size.height)
                    }
                }
            }.clipped().clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}

/// Card sizing for the overview grid. Below the minimum card height three rows of cards no
/// longer fit the display, so the grid scrolls instead of overflowing.
struct WorkspaceOverviewGridMetrics: Equatable {
    static let minimumCardHeight: CGFloat = 50
    let cardHeight: CGFloat
    let scrolls: Bool

    init(availableHeight: CGFloat) {
        let fitted = (availableHeight - 200) / 3 - 48
        cardHeight = max(Self.minimumCardHeight, fitted)
        scrolls = fitted < Self.minimumCardHeight
    }
}
