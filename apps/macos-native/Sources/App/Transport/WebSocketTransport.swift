#if canImport(SwiftUI) && os(macOS)
import Foundation

// MARK: - WebSocket Transport

@MainActor
final class WebSocketTransport: ObservableObject, @unchecked Sendable {
  enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
  }

  @Published private(set) var connectionState: ConnectionState = .disconnected
  @Published private(set) var welcomePayload: WsWelcomePayload?

  private var webSocketTask: URLSessionWebSocketTask?
  private var session: URLSession?
  private var url: URL?
  private var pendingRequests: [String: CheckedContinuation<WebSocketResponse, Error>] = [:]
  private var pushHandlers: [String: [(Any) -> Void]] = [:]
  private var reconnectAttempt = 0
  private var isIntentionalDisconnect = false
  private let maxReconnectDelay: TimeInterval = 8.0
  private let baseReconnectDelay: TimeInterval = 0.5
  private let requestTimeout: TimeInterval = 60.0

  func connect(to url: URL) {
    self.url = url
    isIntentionalDisconnect = false
    reconnectAttempt = 0
    establishConnection()
  }

  func disconnect() {
    isIntentionalDisconnect = true
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    connectionState = .disconnected
    cancelAllPending()
  }

  func send(method: String, params: [String: Any] = [:]) async throws -> WebSocketResponse {
    guard let webSocketTask, connectionState == .connected else {
      throw TransportError.notConnected
    }

    let requestId = UUID().uuidString
    var body = params
    body["_tag"] = method

    let request: [String: Any] = [
      "id": requestId,
      "body": body,
    ]

    let data = try JSONSerialization.data(withJSONObject: request)
    let message = URLSessionWebSocketTask.Message.data(data)
    try await webSocketTask.send(message)

    return try await withCheckedThrowingContinuation { continuation in
      pendingRequests[requestId] = continuation

      Task { [weak self] in
        let timeout = self?.requestTimeout ?? 60.0
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        await MainActor.run {
          if let cont = self?.pendingRequests.removeValue(forKey: requestId) {
            cont.resume(throwing: TransportError.timeout)
          }
        }
      }
    }
  }

  func onPush(channel: String, handler: @escaping (Any) -> Void) {
    pushHandlers[channel, default: []].append(handler)
  }

  // MARK: - Private

  private func establishConnection() {
    guard let url else { return }

    if reconnectAttempt > 0 {
      connectionState = .reconnecting(attempt: reconnectAttempt)
    } else {
      connectionState = .connecting
    }

    let config = URLSessionConfiguration.default
    config.waitsForConnectivity = true
    session = URLSession(configuration: config)
    webSocketTask = session?.webSocketTask(with: url)
    webSocketTask?.resume()
    listenForMessages()

    Task { @MainActor in
      connectionState = .connected
      reconnectAttempt = 0
    }
  }

  private func listenForMessages() {
    webSocketTask?.receive { [weak self] result in
      Task { @MainActor [weak self] in
        guard let self else { return }
        switch result {
        case .success(let message):
          self.handleMessage(message)
          self.listenForMessages()
        case .failure:
          self.handleDisconnection()
        }
      }
    }
  }

  private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
    let data: Data
    switch message {
    case .data(let d):
      data = d
    case .string(let s):
      data = Data(s.utf8)
    @unknown default:
      return
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return
    }

    if let type = json["type"] as? String, type == "push",
      let channel = json["channel"] as? String
    {
      let pushData = json["data"]

      if channel == "server.welcome" {
        if let welcomeData = pushData,
          let welcomeJson = try? JSONSerialization.data(withJSONObject: welcomeData),
          let welcome = try? JSONDecoder().decode(WsWelcomePayload.self, from: welcomeJson)
        {
          welcomePayload = welcome
        }
      }

      pushHandlers[channel]?.forEach { handler in
        if let pushData {
          handler(pushData)
        }
      }
      return
    }

    if let id = json["id"] as? String,
      let continuation = pendingRequests.removeValue(forKey: id)
    {
      do {
        let response = try JSONDecoder().decode(WebSocketResponse.self, from: data)
        continuation.resume(returning: response)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  private func handleDisconnection() {
    guard !isIntentionalDisconnect else { return }
    cancelAllPending()
    reconnectAttempt += 1
    let delay = min(baseReconnectDelay * pow(2, Double(reconnectAttempt - 1)), maxReconnectDelay)
    connectionState = .reconnecting(attempt: reconnectAttempt)

    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      self?.establishConnection()
    }
  }

  private func cancelAllPending() {
    for (_, cont) in pendingRequests {
      cont.resume(throwing: TransportError.disconnected)
    }
    pendingRequests.removeAll()
  }
}

enum TransportError: Error, LocalizedError {
  case notConnected
  case timeout
  case disconnected
  case serverError(String)

  var errorDescription: String? {
    switch self {
    case .notConnected: "Not connected to server"
    case .timeout: "Request timed out"
    case .disconnected: "Connection lost"
    case .serverError(let msg): msg
    }
  }
}
#endif
