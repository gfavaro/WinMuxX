import Common

func lowestUnusedPositiveIndex(_ usedIndices: Set<Int>) -> Int {
    var candidate = 1
    while usedIndices.contains(candidate) {
        candidate += 1
    }
    return candidate
}

@MainActor
func nextAutomaticWorkspaceName() -> String {
    var candidate = 1
    while runtime.workspaces.workspaceIdByName[String(candidate)] != nil {
        candidate += 1
    }
    return String(candidate)
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
