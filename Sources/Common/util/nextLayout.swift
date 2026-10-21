/// Cycle after the last matching description; choose the first if none matches.
public func nextLayout<T>(in layouts: [T], matching matches: (T) -> Bool) -> T {
    precondition(!layouts.isEmpty)
    guard let index = layouts.lastIndex(where: matches) else { return layouts[0] }
    return layouts[(index + 1) % layouts.count]
}
