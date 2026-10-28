/// Pure planning for adding native desktops; no creation or window movement.
public enum NativeDesktopTopUpPlan {
    /// The desktop count the config numbers: the highest numeric persistent workspace.
    public static func target(_ persistent: some Sequence<String>) -> Int {
        persistent.compactMap { Int($0) }.filter { $0 > 0 }.max() ?? 0
    }

    /// The next desktop to create and its display, nil when there are enough.
    public static func next(_ displays: [NativeSpaceDisplay], target: Int,
                            home: (Int) -> String?) -> (number: Int, display: String)? {
        let count = displays.reduce(0) { $0 + $1.spaces.count(where: \.isDesktop) }
        guard count < target else { return nil }
        let number = count + 1
        let identifiers = displays.map(\.identifier)
        guard let display = home(number).flatMap({ identifiers.contains($0) ? $0 : nil }) ?? identifiers.first else { return nil }
        return (number, display)
    }
}
