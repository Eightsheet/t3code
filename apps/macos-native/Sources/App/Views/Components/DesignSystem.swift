#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - Design System

enum T3Design {
  // MARK: Colors

  static let accentPurple = Color(red: 0.35, green: 0.22, blue: 0.82)
  static let accentPurpleLight = Color(red: 0.45, green: 0.32, blue: 0.92)

  static let successGreen = Color(red: 0.2, green: 0.78, blue: 0.56)
  static let warningAmber = Color(red: 0.96, green: 0.73, blue: 0.23)
  static let errorRed = Color(red: 0.94, green: 0.31, blue: 0.31)
  static let infoBlue = Color(red: 0.24, green: 0.51, blue: 0.96)

  // MARK: Semantic Colors

  enum Colors {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfacePrimary = Color(nsColor: .controlBackgroundColor)
    static let surfaceSecondary = Color(nsColor: .underPageBackgroundColor)
    static let surfaceTertiary = Color(nsColor: .gridColor).opacity(0.3)
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let border = Color(nsColor: .separatorColor)
    static let divider = Color(nsColor: .separatorColor)

    static let userBubble = Color.accentColor.opacity(0.1)
    static let assistantBubble = Color(nsColor: .controlBackgroundColor)
    static let codeBg = Color(nsColor: .textBackgroundColor).opacity(0.6)

    static let sidebarBg = Color(nsColor: .windowBackgroundColor)
    static let sidebarHover = Color.primary.opacity(0.06)
    static let sidebarActive = Color.accentColor.opacity(0.12)
  }

  // MARK: Typography

  enum Fonts {
    static let displayLarge = Font.system(size: 28, weight: .bold, design: .default)
    static let displayMedium = Font.system(size: 22, weight: .semibold, design: .default)
    static let headline = Font.system(size: 15, weight: .semibold, design: .default)
    static let body = Font.system(size: 13, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 13, weight: .medium, design: .default)
    static let caption = Font.system(size: 11, weight: .regular, design: .default)
    static let captionMedium = Font.system(size: 11, weight: .medium, design: .default)
    static let code = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let codeSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
  }

  // MARK: Spacing

  enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
  }

  // MARK: Radius

  enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 14
    static let xxl: CGFloat = 18
  }

  // MARK: Animation

  enum Animation {
    static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
    static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
    static let smooth = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let bouncy = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.7)
  }
}

// MARK: - View Extensions

extension View {
  func cardStyle(padding: CGFloat = T3Design.Spacing.md) -> some View {
    self
      .padding(padding)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: T3Design.Radius.lg, style: .continuous))
  }

  func subtleBorder() -> some View {
    self.overlay(
      RoundedRectangle(cornerRadius: T3Design.Radius.lg, style: .continuous)
        .strokeBorder(T3Design.Colors.border.opacity(0.3), lineWidth: 0.5)
    )
  }
}

// MARK: - Status Indicator

struct StatusDot: View {
  let color: Color
  let size: CGFloat

  init(_ color: Color, size: CGFloat = 8) {
    self.color = color
    self.size = size
  }

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: size, height: size)
      .shadow(color: color.opacity(0.4), radius: 3)
  }
}

// MARK: - Keyboard Shortcut Label

struct KeyboardShortcutBadge: View {
  let keys: String

  var body: some View {
    Text(keys)
      .font(T3Design.Fonts.codeSmall)
      .foregroundStyle(.tertiary)
      .padding(.horizontal, 4)
      .padding(.vertical, 2)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
  }
}

// MARK: - File Status Helpers

enum FileStatusStyle {
  static func icon(for status: String) -> String {
    switch status {
    case "added": "plus.circle.fill"
    case "deleted": "minus.circle.fill"
    case "modified": "pencil.circle.fill"
    case "renamed": "arrow.right.circle.fill"
    default: "circle.fill"
    }
  }

  static func color(for status: String) -> Color {
    switch status {
    case "added": T3Design.successGreen
    case "deleted": T3Design.errorRed
    case "modified": T3Design.warningAmber
    case "renamed": T3Design.infoBlue
    default: .secondary
    }
  }
}
#endif
