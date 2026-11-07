import SwiftUI
import AppKit

// These animations are deliberately cheap: nothing is redrawn per frame. Heavy pieces (glows, borders) are
// rasterised once with `drawingGroup()` and only their transform or opacity is animated; there are no
// materials (backdrop blur) over the list and no per-frame TimelineViews.

/// Shown while a folder is dragged over the window: dimmed background and a landing pad with soft ripples.
struct DropOverlayView: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.7), lineWidth: 2)
                        .frame(width: 300, height: 210)
                        .scaleEffect(pulse ? 1.7 : 1)
                        .opacity(pulse ? 0 : 0.8)
                        .animation(rippleAnimation(delay: Double(i) * 0.9), value: pulse)
                }
                pad
                    .scaleEffect(pulse ? 1.025 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    .overlay(alignment: .top) {
                        Image(systemName: "folder.fill.badge.plus")
                            .font(.system(size: 52, weight: .light))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Theme.running, .white)
                            .offset(y: pulse ? 26 : 34)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    }
            }
        }
        .allowsHitTesting(false)
        .onAppear { if !reduceMotion { pulse = true } }
    }

    private func rippleAnimation(delay: Double) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(delay)
    }

    /// The pad is rendered to a texture once (fill, dashed border, glow, text); only its transform animates.
    private var pad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.17, blue: 0.50), Color(red: 0.14, green: 0.11, blue: 0.38)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: Theme.accent.opacity(0.55), radius: 22)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [12, 9]))
            VStack(spacing: 8) {
                Color.clear.frame(height: 56)   // room for the bobbing icon
                Text("Drop to start serving").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text("Each folder gets its own port").font(.callout).foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(width: 300, height: 210)
        .padding(30)             // leave room for the glow inside the texture
        .drawingGroup()
        .padding(-30)
    }
}

/// A short burst where the folder was dropped: two rings and a few sparks (transform and opacity only).
struct DropBurstView: View {
    let point: CGPoint
    @State private var go = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle().strokeBorder(i == 0 ? Theme.running : Theme.accent, lineWidth: i == 0 ? 3 : 2)
                    .frame(width: 60, height: 60)
                    .scaleEffect(go ? (i == 0 ? 3.4 : 5.2) : 0.3)
                    .opacity(go ? 0 : 0.9)
            }
            if !reduceMotion {
                ForEach(0..<8, id: \.self) { i in
                    let angle = Double(i) / 8 * 2 * .pi
                    Circle().fill(i.isMultiple(of: 2) ? Theme.running : Theme.accent)
                        .frame(width: 7, height: 7)
                        .offset(x: go ? cos(angle) * 90 : 0, y: go ? sin(angle) * 90 : 0)
                        .scaleEffect(go ? 0.2 : 1)
                        .opacity(go ? 0 : 1)
                }
            }
        }
        .position(point)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: reduceMotion ? 0.3 : 0.7)) { go = true } }
    }
}

/// Glow around a card that was just added (or dropped again): the glow is drawn once and only its opacity pulses.
struct JustAddedGlow: ViewModifier {
    let active: Bool
    var cornerRadius: CGFloat = 24
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.running, lineWidth: 2.5)
                .shadow(color: Theme.running.opacity(0.7), radius: 12)
                .drawingGroup()
                .opacity(active ? (dim ? 0.45 : 1) : 0)
                .animation(.smooth(duration: 0.4), value: active)
                .animation(active && !reduceMotion ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default, value: dim)
                .onChange(of: active) { _, isActive in dim = isActive && !reduceMotion }
                .onAppear { dim = active && !reduceMotion }
                .allowsHitTesting(false)
        }
    }
}

extension View {
    func justAddedGlow(_ active: Bool, cornerRadius: CGFloat = 24) -> some View {
        modifier(JustAddedGlow(active: active, cornerRadius: cornerRadius))
    }
}

enum DropFeedback {
    /// A light tap on trackpads that support it.
    @MainActor static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
