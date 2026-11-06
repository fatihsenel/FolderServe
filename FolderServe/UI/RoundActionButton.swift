import SwiftUI

/// Large round start/stop button in the style of a primary "scan" action.
struct RoundActionButton: View {
    let isRunning: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
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
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: (isRunning ? Theme.failed : Theme.running).opacity(0.45), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help(isRunning ? "Stop serving this folder" : "Start serving this folder")
    }
}
