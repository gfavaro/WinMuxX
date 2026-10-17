import AppKit
import Common

struct ExecAndForgetCommand: Command {
    let args: ExecAndForgetCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        // todo shall exec-and-forget fork exec session?
        // It doesn't throw if exit code is non-zero
        let process = Process()
        process.environment = execEnvironment(config.execConfig.envVariables, context: env.asMap,
            cliDirectory: bundledCliDirectory)
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = ["-c", args.bashScript]
        return Result { try process.run() }.isSuccess
    }
}

// A separate Helpers directory avoids a case-insensitive collision with WinMuxX.
private var bundledCliDirectory: String? {
    let directory = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers")
    return FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("winmuxx").path)
        ? directory.path : nil
}

func execEnvironment(_ base: [String: String], context: [String: String], cliDirectory: String?) -> [String: String] {
    var result = base + context
    if let cliDirectory {
        let path = result["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        result["PATH"] = cliDirectory + ":" + path
    }
    return result
}
