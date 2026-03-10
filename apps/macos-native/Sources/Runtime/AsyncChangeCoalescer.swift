import Foundation

@MainActor
public final class AsyncChangeCoalescer {
  private let debounceNanoseconds: UInt64
  private var runnerTask: Task<Void, Never>?
  private var isDirty = false

  public init(debounceMilliseconds: UInt64 = 0) {
    debounceNanoseconds = debounceMilliseconds * 1_000_000
  }

  public func signal(_ operation: @escaping @MainActor () async -> Void) {
    isDirty = true
    guard runnerTask == nil else { return }

    runnerTask = Task { @MainActor in
      await self.drain(operation)
    }
  }

  public func cancel() {
    runnerTask?.cancel()
    runnerTask = nil
    isDirty = false
  }

  private func drain(_ operation: @escaping @MainActor () async -> Void) async {
    while true {
      guard isDirty else {
        runnerTask = nil
        return
      }

      isDirty = false

      if debounceNanoseconds > 0 {
        try? await Task.sleep(nanoseconds: debounceNanoseconds)
        if Task.isCancelled {
          runnerTask = nil
          return
        }
        if isDirty {
          continue
        }
      }

      await operation()
    }
  }
}
