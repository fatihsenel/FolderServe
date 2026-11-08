import SwiftUI
import AppKit

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

    /// A pointing-hand cursor over this view. The system owns it (no push/pop pairs), so it cannot get stuck
    /// when the view disappears or the window changes while the mouse is over it.
    func handCursor() -> some View { modifier(HandCursor()) }
}

private struct HandCursor: ViewModifier {
    @Environment(\.isSnapshotRendering) private var isSnapshot

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.link)
        } else if isSnapshot {
            content   // ImageRenderer cannot draw AppKit-backed views
        } else {
            content.overlay(CursorRectView().allowsHitTesting(false))
        }
    }
}

/// macOS 14: a cursor rect covering the view. AppKit applies and removes it by itself.
private struct CursorRectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { RectView() }
    func updateNSView(_ nsView: NSView, context: Context) { nsView.window?.invalidateCursorRects(for: nsView) }

    private final class RectView: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct SnapshotRenderingKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True while rendering with ImageRenderer, which cannot draw AppKit-backed views (drop targets).
    var isSnapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}
