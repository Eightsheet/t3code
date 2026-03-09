import XCTest

@testable import T3CodeMacOSRuntime

final class DesktopRuntimeInfoTests: XCTestCase {
  func testResolveRecognizesTranslatedIntelBuildOnAppleSilicon() {
    let runtimeInfo = DesktopRuntimeInfoResolver.resolve(
      platformIdentifier: "darwin",
      processArchitecture: "x64",
      runningUnderArm64Translation: true
    )

    XCTAssertEqual(runtimeInfo.hostArch, .arm64)
    XCTAssertEqual(runtimeInfo.appArch, .x64)
    XCTAssertTrue(runtimeInfo.runningUnderArm64Translation)
    XCTAssertTrue(DesktopRuntimeInfoResolver.isArm64HostRunningIntelBuild(runtimeInfo))
  }
}
