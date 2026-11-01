import Common

func lowestUnusedPositiveIndex(_ usedIndices: Set<Int>) -> Int {
    var candidate = 1
    while usedIndices.contains(candidate) {
        candidate += 1
    }
    return candidate
}

@MainActor
func nextAutomaticWorkspaceName(projectId _: WorkspaceProjectId = workspaceProjectDefaultId, monitor: Monitor = mainMonitor) -> String {
    var candidate = 1
    while true {
        let name = String(candidate)
        if runtime.workspaces.workspaceIdByName[name] == nil,
           isValidAssignment(workspaceName: name, screen: monitor.rect.topLeftCorner)
        {
            return name
        }
        candidate += 1
    }
}

func parsePositiveWorkspaceDisplayIndex(_ workspaceName: String) -> Int? {
    guard let targetIndex = Int(workspaceName),
          targetIndex > 0,
          String(targetIndex) == workspaceName
    else {
        return nil
    }
    return targetIndex
}
