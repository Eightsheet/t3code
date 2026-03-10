import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class AsyncChangeCoalescerTests: XCTestCase {
  func testCoalescesBurstSignalsIntoSingleRun() async throws {
    let coalescer = await MainActor.run {
      AsyncChangeCoalescer(debounceMilliseconds: 20)
    }
    let ran = expectation(description: "operation ran once")
    let runCounter = RunCounter()

    let operation: @MainActor () async -> Void = {
      _ = await runCounter.increment()
      ran.fulfill()
    }

    await MainActor.run {
      coalescer.signal(operation)
      coalescer.signal(operation)
      coalescer.signal(operation)
    }

    await fulfillment(of: [ran], timeout: 1)
    try? await Task.sleep(nanoseconds: 60_000_000)

    let runCount = await runCounter.value
    XCTAssertEqual(runCount, 1)
  }

  func testRunsTrailingPassWhenSignaledDuringActiveRun() async throws {
    let coalescer = await MainActor.run { AsyncChangeCoalescer() }
    let firstRunStarted = expectation(description: "first run started")
    let completedRuns = expectation(description: "two runs completed")
    completedRuns.expectedFulfillmentCount = 2
    let runCounter = RunCounter()

    let operation: @MainActor () async -> Void = {
      let runCount = await runCounter.increment()
      if runCount == 1 {
        firstRunStarted.fulfill()
        try? await Task.sleep(nanoseconds: 40_000_000)
      }
      completedRuns.fulfill()
    }

    await MainActor.run {
      coalescer.signal(operation)
    }
    await fulfillment(of: [firstRunStarted], timeout: 1)
    await MainActor.run {
      coalescer.signal(operation)
    }

    await fulfillment(of: [completedRuns], timeout: 1)
    let runCount = await runCounter.value
    XCTAssertEqual(runCount, 2)
  }
}

private actor RunCounter {
  private(set) var value = 0

  func increment() -> Int {
    value += 1
    return value
  }
}
