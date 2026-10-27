public struct DoctorCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public var simulateNativePan = false
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .doctor,
        allowInConfig: false,
        help: """
            USAGE: doctor [-h|--help] [--simulate-native-pan]

            Print diagnostics: permissions, monitors, per-app accessibility latency,
            and window manager state. Useful for bug reports and performance triage.
            --simulate-native-pan posts a one-second Option + two-finger scroll over the
            visible native scrolling desktop and reports how closely the windows followed.
            """,
        flags: ["--simulate-native-pan": trueBoolFlag(\.simulateNativePan)],
        posArgs: [],
    )
}
