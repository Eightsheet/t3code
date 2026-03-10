#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - Empty State

struct EmptyStateView: View {
  @ObservedObject var store: AppStore
  @State private var animateIn = false

  var body: some View {
    VStack(spacing: T3Design.Spacing.xxl) {
      Spacer()

      VStack(spacing: T3Design.Spacing.xl) {
        ZStack {
          Circle()
            .fill(T3Design.accentPurple.opacity(0.06))
            .frame(width: 120, height: 120)
            .scaleEffect(animateIn ? 1.0 : 0.8)

          Circle()
            .fill(T3Design.accentPurple.opacity(0.1))
            .frame(width: 80, height: 80)
            .scaleEffect(animateIn ? 1.0 : 0.85)

          Image(systemName: "sparkles")
            .font(.system(size: 36, weight: .light))
            .foregroundStyle(T3Design.accentPurple)
            .scaleEffect(animateIn ? 1.0 : 0.6)
            .opacity(animateIn ? 1.0 : 0.0)
        }
        .animation(T3Design.Animation.bouncy.delay(0.1), value: animateIn)

        VStack(spacing: T3Design.Spacing.sm) {
          Text("Start a conversation")
            .font(T3Design.Fonts.displayMedium)
            .opacity(animateIn ? 1.0 : 0.0)
            .offset(y: animateIn ? 0 : 8)
            .animation(T3Design.Animation.smooth.delay(0.2), value: animateIn)

          Text("Select a thread from the sidebar or create a new one to begin coding with AI")
            .font(T3Design.Fonts.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            .opacity(animateIn ? 1.0 : 0.0)
            .offset(y: animateIn ? 0 : 6)
            .animation(T3Design.Animation.smooth.delay(0.3), value: animateIn)
        }

        Button {
          Task {
            guard let project = store.activeProjects.first else { return }
            _ = await store.createThread(projectId: project.id)
          }
        } label: {
          Label("New Thread", systemImage: "plus")
            .font(T3Design.Fonts.bodyMedium)
        }
        .buttonStyle(.borderedProminent)
        .tint(T3Design.accentPurple)
        .controlSize(.large)
        .opacity(animateIn ? 1.0 : 0.0)
        .offset(y: animateIn ? 0 : 10)
        .animation(T3Design.Animation.smooth.delay(0.4), value: animateIn)
      }

      if !store.activeProjects.isEmpty {
        quickActionsGrid
          .opacity(animateIn ? 1.0 : 0.0)
          .offset(y: animateIn ? 0 : 12)
          .animation(T3Design.Animation.smooth.delay(0.5), value: animateIn)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      animateIn = true
    }
  }

  private var quickActionsGrid: some View {
    VStack(spacing: T3Design.Spacing.md) {
      Text("Quick actions")
        .font(T3Design.Fonts.captionMedium)
        .foregroundStyle(.tertiary)

      HStack(spacing: T3Design.Spacing.md) {
        QuickActionCard(
          icon: "doc.text",
          title: "Write code",
          subtitle: "Generate, refactor, or explain",
          color: T3Design.accentPurple
        )

        QuickActionCard(
          icon: "ant",
          title: "Fix bugs",
          subtitle: "Debug and resolve issues",
          color: T3Design.errorRed
        )

        QuickActionCard(
          icon: "arrow.triangle.branch",
          title: "Git workflow",
          subtitle: "Branches, commits, and PRs",
          color: T3Design.successGreen
        )
      }
      .frame(maxWidth: 520)
    }
  }
}

// MARK: - Quick Action Card

private struct QuickActionCard: View {
  let icon: String
  let title: String
  let subtitle: String
  let color: Color
  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: T3Design.Spacing.sm) {
      Image(systemName: icon)
        .font(.system(size: 20, weight: .light))
        .foregroundStyle(color)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(T3Design.Fonts.bodyMedium)
          .foregroundStyle(.primary)

        Text(subtitle)
          .font(T3Design.Fonts.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(T3Design.Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: T3Design.Radius.lg, style: .continuous)
        .fill(isHovering ? color.opacity(0.06) : .clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: T3Design.Radius.lg, style: .continuous)
        .strokeBorder(T3Design.Colors.border.opacity(isHovering ? 0.4 : 0.2), lineWidth: 0.5)
    )
    .onHover { isHovering = $0 }
    .animation(T3Design.Animation.quick, value: isHovering)
  }
}
#endif
