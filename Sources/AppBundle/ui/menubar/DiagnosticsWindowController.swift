import AppKit
import SwiftUI

@MainActor
final class DiagnosticsWindowController {
    static let shared = DiagnosticsWindowController()
    private var window: NSWindow?
    private let model = DiagnosticsModel()

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "WinMux Diagnostics"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DiagnosticsView(model: model))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.refresh()
    }
}

@MainActor
@Observable
final class DiagnosticsModel {
    var report = ""
    var isRefreshing = false

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            report = await buildDiagnosticsReport()
            isRefreshing = false
        }
    }
}

private struct DiagnosticsView: View {
    var model: DiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics").font(.headline)
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small) }
                Button("Refresh") { model.refresh() }.disabled(model.isRefreshing)
                Button("Copy Diagnostics") { model.report.copyToClipboard() }
                    .disabled(model.report.isEmpty || model.isRefreshing)
            }
            Text("Checks are read-only. Reports include app names and local paths; review before sharing.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(model.report.isEmpty ? "Collecting diagnostics…" : model.report)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 360)
    }
}
