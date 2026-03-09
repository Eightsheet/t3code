import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class DesktopUpdateControllerTests: XCTestCase {
  func testControllerTransitionsThroughAvailableDownloadAndInstallFailure() async {
    let runtimeInfo = DesktopRuntimeInfo(hostArch: .arm64, appArch: .x64, runningUnderArm64Translation: true)
    let environment = DesktopUpdateEnvironment(
      isDevelopment: false,
      isPackaged: true,
      platformIdentifier: "darwin",
      appImagePath: nil,
      disabledByEnvironment: false
    )
    let client = FakeDesktopUpdaterClient()
    client.checkResult = .updateAvailable(version: "2.0.0")
    client.downloadResult = DesktopUpdateDownloadResult(version: "2.0.0")
    client.installError = TestError.installFailed

    let controller = DesktopUpdateController(
      configuration: DesktopUpdateControllerConfiguration(
        currentVersion: "1.0.0",
        runtimeInfo: runtimeInfo,
        environment: environment,
        startupDelay: .milliseconds(10),
        pollInterval: .seconds(60),
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
      ),
      updaterClient: client
    )

    await controller.checkForUpdates(reason: "manual")
    var state = await controller.currentState()
    XCTAssertEqual(state.status, .available)
    XCTAssertEqual(state.availableVersion, "2.0.0")

    let downloadResult = await controller.downloadAvailableUpdate()
    XCTAssertTrue(downloadResult.accepted)
    XCTAssertTrue(downloadResult.completed)
    state = await controller.currentState()
    XCTAssertEqual(state.status, .downloaded)
    XCTAssertEqual(state.downloadPercent, 100)

    let installResult = await controller.installDownloadedUpdate()
    XCTAssertTrue(installResult.accepted)
    XCTAssertFalse(installResult.completed)
    state = await controller.currentState()
    XCTAssertEqual(state.status, .downloaded)
    XCTAssertEqual(state.errorContext, .install)
    XCTAssertEqual(state.message, TestError.installFailed.localizedDescription)
  }

  func testPolicyDisablesUnpackagedBuildsAndThrottlesProgressBroadcast() {
    let environment = DesktopUpdateEnvironment(
      isDevelopment: false,
      isPackaged: false,
      platformIdentifier: "darwin",
      appImagePath: nil,
      disabledByEnvironment: false
    )

    XCTAssertEqual(
      DesktopUpdatePolicy.disabledReason(for: environment),
      "Automatic updates are only available in packaged production builds."
    )

    let state = DesktopUpdateStateMachine.reduceOnDownloadStart(
      DesktopUpdateStateMachine.configuredState(
        currentVersion: "1.0.0",
        runtimeInfo: DesktopRuntimeInfo(hostArch: .arm64, appArch: .arm64, runningUnderArm64Translation: false),
        enabled: true
      )
    )
    XCTAssertFalse(DesktopUpdatePolicy.shouldBroadcastDownloadProgress(currentState: state, nextPercent: 9))
    XCTAssertTrue(DesktopUpdatePolicy.shouldBroadcastDownloadProgress(currentState: state, nextPercent: 10))
  }
}

private final class FakeDesktopUpdaterClient: DesktopUpdaterClient, @unchecked Sendable {
  var checkResult: DesktopUpdateCheckResult = .noUpdate
  var downloadResult = DesktopUpdateDownloadResult(version: "1.0.1")
  var installError: Error?

  func checkForUpdates() async throws -> DesktopUpdateCheckResult {
    checkResult
  }

  func downloadUpdate(
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> DesktopUpdateDownloadResult {
    progress(5)
    progress(10)
    progress(55)
    progress(100)
    return downloadResult
  }

  func installUpdate() async throws {
    if let installError {
      throw installError
    }
  }
}

private enum TestError: LocalizedError {
  case installFailed

  var errorDescription: String? {
    switch self {
    case .installFailed:
      return "install failed"
    }
  }
}
