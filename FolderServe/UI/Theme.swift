import SwiftUI

enum Theme {
    static let accent = Color(red: 0.42, green: 0.40, blue: 1.0)
    static let running = Color(red: 0.25, green: 0.86, blue: 0.62)
    static let stopped = Color(white: 0.62)
    static let failed = Color(red: 1.0, green: 0.36, blue: 0.40)
    static let warning = Color(red: 1.0, green: 0.74, blue: 0.25)

    static func statusColor(_ status: ServerStatus) -> Color {
        switch status {
        case .running: return running
        case .stopped: return stopped
        case .finding: return warning
        case .error: return failed
        case .folderMissing: return warning
        }
    }

    static func background(_ scheme: ColorScheme) -> LinearGradient {
        let colors: [Color] = scheme == .dark
            ? [Color(red: 0.09, green: 0.07, blue: 0.24), Color(red: 0.20, green: 0.10, blue: 0.40), Color(red: 0.42, green: 0.14, blue: 0.48)]
            : [Color(red: 0.90, green: 0.92, blue: 1.0), Color(red: 0.93, green: 0.90, blue: 1.0), Color(red: 0.98, green: 0.90, blue: 0.97)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.10)))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

private struct SnapshotRenderingKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True while rendering with ImageRenderer, which cannot draw AppKit-backed views (drop targets).
    var isSnapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}
