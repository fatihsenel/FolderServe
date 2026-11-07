import SwiftUI

/// Large round start/stop button in the style of a primary "scan" action.
/// Hover: grows slightly, glow intensifies and a soft ring pulses out. Press: squishes.
struct RoundActionButton: View {
    let isRunning: Bool
    let isBusy: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glow: Color { isRunning ? Theme.failed : Theme.running }

    var body: some View {
        Button(action: action) {
            ZStack {
                if hovering && !isBusy { PulseRing(color: glow, reduceMotion: reduceMotion) }
                face
            }
            .frame(width: 68, height: 68)
        }
        .buttonStyle(PressScaleStyle(reduceMotion: reduceMotion))
        .scaleEffect(hovering && !isBusy && !reduceMotion ? 1.08 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hovering)
        .onHover { hovering = $0 }
        .disabled(isBusy)
        .help(isRunning ? "Stop serving this folder" : "Start serving this folder")
    }

    private var face: some View {
        VStack(spacing: 4) {
            Image(systemName: isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: 20, weight: .bold))
                .scaleEffect(hovering && !isBusy && !reduceMotion ? 1.15 : 1)
                .offset(x: hovering && !isBusy && !isRunning && !reduceMotion ? 2 : 0)
                .contentTransition(.symbolEffect(.replace))
            Text(isRunning ? "Stop" : "Start").font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(width: 68, height: 68)
        .background(
            Circle().fill(LinearGradient(
                colors: isRunning ? [Color(red: 1, green: 0.45, blue: 0.5), Color(red: 0.85, green: 0.22, blue: 0.4)]
                                  : [Color(red: 0.35, green: 0.92, blue: 0.72), Color(red: 0.12, green: 0.65, blue: 0.62)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(Circle().strokeBorder(.white.opacity(hovering ? 0.6 : 0.35), lineWidth: 1))
        .brightness(hovering && !isBusy ? 0.06 : 0)
        .shadow(color: glow.opacity(hovering && !isBusy ? 0.75 : 0.45), radius: hovering && !isBusy ? 22 : 14, y: 6)
        .animation(.easeOut(duration: 0.2), value: hovering)
    }
}

private struct PressScaleStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A ring that expands and fades while the pointer is over the button.
private struct PulseRing: View {
    let color: Color
    let reduceMotion: Bool
    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(color.opacity(0.6), lineWidth: 2)
            .frame(width: 68, height: 68)
            .scaleEffect(expanded ? 1.45 : 1)
            .opacity(expanded ? 0 : 0.9)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) { expanded = true }
            }
            .allowsHitTesting(false)
    }
}
