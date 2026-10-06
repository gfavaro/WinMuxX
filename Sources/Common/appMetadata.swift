public let stableWinMuxAppId: String = "com.gfavaro.winmuxx"
public let forkRepositoryURL = "https://github.com/gfavaro/WinMuxX"
public let winMuxAppSupportDirectoryName = "WinMux-GF"
#if DEBUG
    public let winMuxAppId: String = "com.gfavaro.winmuxx.debug"
    public let winMuxAppName: String = "WinMuxX-Debug"
#else
    public let winMuxAppId: String = stableWinMuxAppId
    public let winMuxAppName: String = "WinMuxX"
#endif
