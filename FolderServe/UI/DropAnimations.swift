import SwiftUI
import AppKit

/// Full-screen overlay shown while a folder is dragged over the window: dimmed background, a landing pad with
/// marching dashes, ripples spreading from it and a bobbing folder.
struct DropOverlayView: View {
    /// Fixes the animation clock (snapshots); nil = live.
    var time: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let time { content(at: time) } else {
            TimelineView(.animation(paused: reduceMotion)) { ctx in content(at: ctx.date.timeIntervalSinceReferenceDate) }
        }
    }

    private func content(at rawTime: Double) -> some View {
        let t = reduceMotion ? 0 : rawTime
        return ZStack {
            Color.black.opacity(0.38)
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.55 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    RoundedRectangle(cornerRadius: 36 + phase * 40, style: .continuous)
                        .strokeBorder(Theme.accent.opacity((1 - phase) * 0.6), lineWidth: 2)
                        .frame(width: 300 + phase * 220, height: 210 + phase * 170)
                }
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 300, height: 210)
                    .shadow(color: Theme.accent.opacity(0.55), radius: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [12, 9], dashPhase: -t * 36))
                    )
                VStack(spacing: 10) {
                    Image(systemName: "folder.fill.badge.plus")
                        .font(.system(size: 52, weight: .light))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.running, .white)
                        .offset(y: sin(t * 3.2) * 6)
                        .shadow(color: Theme.running.opacity(0.6), radius: 12)
                    Text("Drop to start serving").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Each folder gets its own port").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A short burst where the folder was dropped: two rings and a spray of sparks.
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
                ForEach(0..<10, id: \.self) { i in
                    let angle = Double(i) / 10 * 2 * .pi
                    Circle().fill(i.isMultiple(of: 2) ? Theme.running : Theme.accent)
                        .frame(width: i.isMultiple(of: 3) ? 8 : 5, height: i.isMultiple(of: 3) ? 8 : 5)
                        .offset(x: go ? cos(angle) * 96 : 0, y: go ? sin(angle) * 96 : 0)
                        .scaleEffect(go ? 0.2 : 1)
                        .opacity(go ? 0 : 1)
                }
            }
        }
        .position(point)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: reduceMotion ? 0.3 : 0.8)) { go = true } }
    }
}

/// Glow around a card that was just added (or dropped again): a couple of soft pulses, then it fades out.
struct JustAddedGlow: ViewModifier {
    let active: Bool
    var cornerRadius: CGFloat = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            TimelineView(.animation(paused: !active || reduceMotion)) { ctx in
                let pulse = reduceMotion ? 1 : 0.55 + 0.45 * (0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 7))
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.running.opacity(pulse), lineWidth: 2.5)
                    .shadow(color: Theme.running.opacity(0.7 * pulse), radius: 14)
                    .opacity(active ? 1 : 0)
                    .animation(.smooth(duration: 0.5), value: active)
            }
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
