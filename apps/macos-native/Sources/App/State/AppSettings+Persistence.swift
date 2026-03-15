#if canImport(SwiftUI) && os(macOS)
import Foundation

// MARK: - App Settings Persistence

extension AppSettings {
  private static let storageKey = "t3code.appSettings"

  static func load() -> AppSettings {
    guard let data = UserDefaults.standard.data(forKey: storageKey),
      let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
    else {
      return AppSettings()
    }
    return settings
  }

  func save() {
    if let data = try? JSONEncoder().encode(self) {
      UserDefaults.standard.set(data, forKey: AppSettings.storageKey)
    }
  }
}

// MARK: - Composer Draft Persistence

final class ComposerDraftStore {
  private static let storageKey = "t3code.composerDrafts"

  static let shared = ComposerDraftStore()
  private var drafts: [ThreadId: String] = [:]

  private init() {
    if let data = UserDefaults.standard.data(forKey: Self.storageKey),
      let loaded = try? JSONDecoder().decode([String: String].self, from: data)
    {
      drafts = loaded
    }
  }

  func draft(for threadId: ThreadId) -> String {
    drafts[threadId] ?? ""
  }

  func saveDraft(_ text: String, for threadId: ThreadId) {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      drafts.removeValue(forKey: threadId)
    } else {
      drafts[threadId] = text
    }
    persist()
  }

  func clearDraft(for threadId: ThreadId) {
    drafts.removeValue(forKey: threadId)
    persist()
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(drafts) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
  }
}
#endif
