import SwiftUI

/// Large round start/stop button in the style of a primary "scan" action.
///
/// Every state change is a smooth (non-bouncy) transition driven by one animation per state:
/// hover (grow, glow, ring), running (start ⇄ stop cross-fade), busy (fade to grey), press (squish).
struct RoundActionButton: View {
    let isRunning: Bool
    let isBusy: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let startColors = [Color(red: 0.35, green: 0.92, blue: 0.72), Color(red: 0.12, green: 0.65, blue: 0.62)]
    private static let stopColors = [Color(red: 1, green: 0.45, blue: 0.5), Color(red: 0.85, green: 0.22, blue: 0.4)]

    private var active: Bool { hovering && !isBusy }

    var body: some View {
        Button(action: action) {
            ZStack {
                ring
                face
            }
            .frame(width: 68, height: 68)
            .contentShape(Circle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(PressScaleStyle(reduceMotion: reduceMotion))
        .scaleEffect(active && !reduceMotion ? 1.1 : 1)
        .animation(.smooth(duration: 0.35), value: active)
        .disabled(isBusy)
        .help(isRunning ? "Stop serving this folder" : "Start serving this folder")
    }

    private var face: some View {
        ZStack {
            // Two gradient discs cross-fade instead of snapping when the state flips.
            Circle().fill(LinearGradient(colors: Self.startColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(isRunning ? 0 : 1)
            Circle().fill(LinearGradient(colors: Self.stopColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(isRunning ? 1 : 0)
            VStack(spacing: 4) {
                ZStack {
                    glyph("play.fill", visible: !isRunning)
                    glyph("stop.fill", visible: isRunning)
                }
                .frame(height: 24)
                .scaleEffect(active && !reduceMotion ? 1.12 : 1)   // about its own centre: the icon never moves
                ZStack {
                    label("Start", visible: !isRunning)
                    label("Stop", visible: isRunning)
                }
            }
            .foregroundStyle(.white)
        }
        .frame(width: 68, height: 68)
        .overlay(Circle().strokeBorder(.white.opacity(active ? 0.6 : 0.35), lineWidth: 1))
        .brightness(active ? 0.08 : 0)
        .shadow(color: Theme.running.opacity(glowOpacity * (isRunning ? 0 : 1)), radius: glowRadius, y: 6)
        .shadow(color: Theme.failed.opacity(glowOpacity * (isRunning ? 1 : 0)), radius: glowRadius, y: 6)
        .saturation(isBusy ? 0 : 1)
        .opacity(isBusy ? 0.4 : 1)
        .animation(.smooth(duration: 0.4), value: isRunning)
        .animation(.smooth(duration: 0.3), value: isBusy)
    }

    private var glowOpacity: Double { isBusy ? 0 : (hovering ? 0.85 : 0.45) }
    private var glowRadius: CGFloat { active ? 26 : 14 }

    private func glyph(_ name: String, visible: Bool) -> some View {
        Image(systemName: name).font(.system(size: 20, weight: .bold))
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.6)
            .blur(radius: visible ? 0 : 2)
    }

    private func label(_ text: String, visible: Bool) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).opacity(visible ? 1 : 0)
    }

    /// Soft ring that expands and fades while hovering. Always in the tree (so it fades out instead of vanishing);
    /// its clock only runs while hovering.
    private var ring: some View {
        TimelineView(.animation(paused: !hovering || reduceMotion)) { ctx in
            let phase = (ctx.date.timeIntervalSinceReferenceDate / 1.6).truncatingRemainder(dividingBy: 1)
            Circle()
                .strokeBorder((isRunning ? Theme.failed : Theme.running).opacity(0.55), lineWidth: 2)
                .frame(width: 68, height: 68)
                .scaleEffect(1 + phase * 0.5)
                .opacity((1 - phase) * 0.9)
        }
        .opacity(active && !reduceMotion ? 1 : 0)
        .animation(.smooth(duration: 0.3), value: active)
        .allowsHitTesting(false)
    }
}

private struct PressScaleStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
