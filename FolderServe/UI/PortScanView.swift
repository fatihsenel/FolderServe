import SwiftUI

/// "Finding a free port" animation: steps through the ports that were really tried,
/// flashing busy ones red, and lands on the one the server got.
struct PortScanView: View {
    let search: PortSearch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(search.began)
            row(at: t)
        }
    }

    private var steps: [UInt16] { search.busy + (search.landed.map { [$0] } ?? []) }

    @ViewBuilder private func row(at t: Double) -> some View {
        let steps = self.steps
        // Reveal the real attempts over ~75% of the hold, then rest on the last one.
        let slot = steps.isEmpty ? 1 : max(0.12, search.duration * 0.75 / Double(steps.count))
        let index = steps.isEmpty ? nil : min(steps.count - 1, max(0, Int(t / slot)))
        let isLast = index == steps.count - 1
        let landedNow = search.landed != nil && isLast && t >= slot * Double(steps.count - 1)
        let port = index.map { steps[$0] }
        let isBusy = port != nil && !landedNow

        HStack(spacing: 10) {
            ZStack {
                if landedNow {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.running)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.warning)
                        .rotationEffect(.degrees(reduceMotion ? 0 : sin(t * 7) * 14))
                }
            }
            .font(.system(size: 14, weight: .semibold)).frame(width: 18)

            Text(port.map { "127.0.0.1:\(String($0))" } ?? "Finding a free port")
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .foregroundStyle(landedNow ? Theme.running : (isBusy ? Theme.failed : .primary))
                .strikethrough(isBusy, color: Theme.failed)
                .contentTransition(.numericText())
                .scaleEffect(landedNow && !reduceMotion ? 1.06 : 1, anchor: .leading)

            Text(landedNow ? "free" : (isBusy ? "in use" : "scanning…"))
                .font(.caption2.weight(.semibold)).textCase(.uppercase)
                .foregroundStyle(landedNow ? Theme.running : (isBusy ? Theme.failed : .secondary))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill((landedNow ? Theme.running : (isBusy ? Theme.failed : Color.gray)).opacity(0.18)))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            Capsule().fill(.white.opacity(0.06))
                .overlay(alignment: .leading) { sweep(t: t) }
                .clipShape(Capsule()))
        .overlay(Capsule().strokeBorder((landedNow ? Theme.running : Theme.warning).opacity(0.5), lineWidth: 1))
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: port)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: landedNow)
    }

    /// A soft highlight sweeping across the pill while scanning.
    private func sweep(t: Double) -> some View {
        GeometryReader { geo in
            let phase = (t * 1.4).truncatingRemainder(dividingBy: 1)
            LinearGradient(colors: [.clear, Theme.warning.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.45)
                .offset(x: -geo.size.width * 0.45 + phase * geo.size.width * 1.45)
                .opacity(reduceMotion || search.landed != nil && t > search.duration * 0.8 ? 0 : 1)
        }
    }
}
