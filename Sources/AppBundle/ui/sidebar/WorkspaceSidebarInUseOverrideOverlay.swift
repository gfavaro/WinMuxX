import SwiftUI

struct WorkspaceSidebarInUseOverrideOverlay: View {
    @SidebarColors var sidebarColors: WorkspaceSidebarPalette
    let text: String
    var isCompact = false
    let onOverride: () -> Void
    var onCancel: () -> Void = {}
    @State private var isOverrideHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .overlay {
                    shape.fill(Color(nsColor: .systemRed).opacity(0.14))
                }
                .clipShape(shape)
                .allowsHitTesting(false)

            shape.strokeBorder(Color(nsColor: .systemRed).opacity(0.45), lineWidth: 0.8)
                .allowsHitTesting(false)

            VStack(spacing: 8) {
                if !isCompact {
                    Text(text)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(sidebarColors.text(opacity: 0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                HStack(spacing: 8) {
                    Button(action: onOverride) {
                        Group {
                            if isCompact {
                                Image(systemName: "arrow.left.arrow.right")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 10, height: 10)
                                    .frame(maxWidth: .infinity, minHeight: 28)
                            } else {
                                Text("Override")
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 4)
                            }
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Override")
                    .help(text + ". Swap workspaces between displays.")
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(nsColor: .systemRed).opacity(isOverrideHovered ? 1 : 0.88))
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(sidebarColors.foreground.opacity(isOverrideHovered ? 0.28 : 0), lineWidth: 0.6)
                            .allowsHitTesting(false)
                    }
                    .onHover { hovering in
                        isOverrideHovered = hovering
                    }
                    if !isCompact {
                        Button("Cancel", action: onCancel)
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(isCompact ? 4 : 10)
        }
        .contentShape(Rectangle())
    }
}

/// Observe the confirmation that is actually rendered, including width/filter changes.
struct WorkspaceSidebarOverrideConfirmationState: Equatable {
    let workspaceName: String?
    let locksCollapse: Bool

    init(requestedWorkspaceName: String?, visibleWorkspaceNames: Set<String>, isCompact: Bool) {
        workspaceName = requestedWorkspaceName.flatMap { visibleWorkspaceNames.contains($0) ? $0 : nil }
        locksCollapse = workspaceName != nil && !isCompact
    }
}

@MainActor
func workspaceSidebarOverrideConfirmationState(
    snapshot: WorkspaceSidebarSnapshot, browseMode: WorkspaceSidebarBrowseMode,
    query: String, requestedWorkspaceName: String?
) -> WorkspaceSidebarOverrideConfirmationState {
    let progress = max(0, min(1, (snapshot.visibleWidth - snapshot.configuration.collapsedWidth) /
        max(snapshot.configuration.expandedWidth - snapshot.configuration.collapsedWidth, 1)))
    let visible = workspaceSidebarVisibleWorkspacesByProject(
        workspaces: snapshot.workspaces, selectedScopeId: snapshot.selectedMonitorScopeId,
        focusedMonitorScopeId: snapshot.focusedMonitorScopeId, browsedProjectId: browseMode.otherProjectId
    )
    let filtered = workspaceSidebarFilteredWorkspacesByProject(visible, projects: snapshot.projects, query: query)
    let allowsActivation = snapshot.selectedMonitorScopeId == workspaceSidebarDefaultScopeId && browseMode == .activeProject
    let workspaces = allowsActivation ? filtered[snapshot.activeProjectId] ?? [] : []
    return WorkspaceSidebarOverrideConfirmationState(
        requestedWorkspaceName: requestedWorkspaceName,
        visibleWorkspaceNames: Set(workspaces.filter {
            workspaceSidebarWorkspaceIsInUseOnOtherDisplay($0, selectedScopeId: snapshot.targetMonitorScopeId)
        }.map(\.name)),
        isCompact: progress < workspaceSidebarRowsRevealProgress
    )
}
