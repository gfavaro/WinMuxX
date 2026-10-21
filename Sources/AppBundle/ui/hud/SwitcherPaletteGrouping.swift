/// Preserve workspace order from the opening snapshot (focused workspace first),
/// and fuzzy ranking within each group. Header rows never enter selection indices.
func groupSwitcherPaletteItems(_ matches: [SwitcherPaletteItem],
                              workspaceOrder: [SwitcherPaletteItem]) -> [SwitcherPaletteItem] {
    var groups: [String: [SwitcherPaletteItem]] = [:]
    for item in matches { groups[item.workspaceName, default: []].append(item) }
    var result: [SwitcherPaletteItem] = []
    result.reserveCapacity(matches.count)
    for item in workspaceOrder {
        if let group = groups.removeValue(forKey: item.workspaceName) { result.append(contentsOf: group) }
    }
    return result
}
