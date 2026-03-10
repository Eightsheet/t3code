#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - Toast Overlay

struct ToastOverlay: View {
  @ObservedObject var store: AppStore

  var body: some View {
    VStack(spacing: T3Design.Spacing.sm) {
      Spacer()

      ForEach(store.toasts) { toast in
        toastView(toast)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .padding(T3Design.Spacing.xl)
    .animation(T3Design.Animation.smooth, value: store.toasts.count)
  }

  private func toastView(_ toast: ToastMessage) -> some View {
    HStack(spacing: T3Design.Spacing.sm) {
      Image(systemName: toastIcon(toast.kind))
        .font(.system(size: 13))
        .foregroundStyle(toastColor(toast.kind))

      Text(toast.text)
        .font(T3Design.Fonts.body)
        .lineLimit(2)

      Spacer()

      Button {
        store.toasts.removeAll { $0.id == toast.id }
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .medium))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, T3Design.Spacing.md)
    .padding(.vertical, T3Design.Spacing.sm)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: T3Design.Radius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: T3Design.Radius.lg, style: .continuous)
        .strokeBorder(toastColor(toast.kind).opacity(0.3), lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    .frame(maxWidth: 400)
  }

  private func toastIcon(_ kind: ToastMessage.ToastKind) -> String {
    switch kind {
    case .success: "checkmark.circle.fill"
    case .error: "exclamationmark.triangle.fill"
    case .info: "info.circle.fill"
    }
  }

  private func toastColor(_ kind: ToastMessage.ToastKind) -> Color {
    switch kind {
    case .success: T3Design.successGreen
    case .error: T3Design.errorRed
    case .info: T3Design.infoBlue
    }
  }
}

// MARK: - Confirmation Dialogs

struct DeleteThreadDialog: ViewModifier {
  @ObservedObject var store: AppStore
  @Binding var threadId: ThreadId?
  @State private var deleteWorktree = false

  func body(content: Content) -> some View {
    content
      .alert("Delete Thread?", isPresented: Binding(
        get: { threadId != nil },
        set: { if !$0 { threadId = nil } }
      )) {
        Button("Cancel", role: .cancel) { threadId = nil }
        Button("Delete", role: .destructive) {
          if let id = threadId {
            Task { await store.deleteThread(id, deleteWorktree: deleteWorktree) }
            threadId = nil
          }
        }
      } message: {
        Text("This will permanently delete this thread and its history.")
      }
  }
}

struct DeleteProjectDialog: ViewModifier {
  @ObservedObject var store: AppStore
  @Binding var projectId: ProjectId?

  func body(content: Content) -> some View {
    content
      .alert("Delete Project?", isPresented: Binding(
        get: { projectId != nil },
        set: { if !$0 { projectId = nil } }
      )) {
        Button("Cancel", role: .cancel) { projectId = nil }
        Button("Delete", role: .destructive) {
          if let id = projectId {
            Task { await store.deleteProject(id) }
            projectId = nil
          }
        }
      } message: {
        Text("This will remove the project from T3 Code. Your files will not be affected.")
      }
  }
}
#endif
