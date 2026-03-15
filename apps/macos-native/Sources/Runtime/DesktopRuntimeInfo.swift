import Foundation

public enum DesktopRuntimeArch: String, Equatable, Sendable {
  case arm64
  case x64
  case other
}

public struct DesktopRuntimeInfo: Equatable, Sendable {
  public let hostArch: DesktopRuntimeArch
  public let appArch: DesktopRuntimeArch
  public let runningUnderArm64Translation: Bool

  public init(
    hostArch: DesktopRuntimeArch,
    appArch: DesktopRuntimeArch,
    runningUnderArm64Translation: Bool
  ) {
    self.hostArch = hostArch
    self.appArch = appArch
    self.runningUnderArm64Translation = runningUnderArm64Translation
  }
}

public enum DesktopRuntimeInfoResolver {
  public static func current(runningUnderArm64Translation: Bool = false) -> DesktopRuntimeInfo {
    resolve(
      platformIdentifier: currentPlatformIdentifier(),
      processArchitecture: currentProcessArchitecture(),
      runningUnderArm64Translation: runningUnderArm64Translation
    )
  }

  public static func resolve(
    platformIdentifier: String,
    processArchitecture: String,
    runningUnderArm64Translation: Bool
  ) -> DesktopRuntimeInfo {
    let appArch = normalize(architecture: processArchitecture)

    guard platformIdentifier == "darwin" else {
      return DesktopRuntimeInfo(
        hostArch: appArch,
        appArch: appArch,
        runningUnderArm64Translation: false
      )
    }

    let hostArch: DesktopRuntimeArch =
      appArch == .arm64 || runningUnderArm64Translation ? .arm64 : appArch

    return DesktopRuntimeInfo(
      hostArch: hostArch,
      appArch: appArch,
      runningUnderArm64Translation: runningUnderArm64Translation
    )
  }

  public static func isArm64HostRunningIntelBuild(_ runtimeInfo: DesktopRuntimeInfo) -> Bool {
    runtimeInfo.hostArch == .arm64 && runtimeInfo.appArch == .x64
  }

  private static func normalize(architecture: String) -> DesktopRuntimeArch {
    switch architecture {
    case "arm64":
      return .arm64
    case "x64", "x86_64", "amd64":
      return .x64
    default:
      return .other
    }
  }

  private static func currentPlatformIdentifier() -> String {
#if os(macOS)
    return "darwin"
#elseif os(Linux)
    return "linux"
#elseif os(Windows)
    return "win32"
#else
    return "other"
#endif
  }

  private static func currentProcessArchitecture() -> String {
#if arch(arm64)
    return "arm64"
#elseif arch(x86_64)
    return "x64"
#else
    return "other"
#endif
  }
}
