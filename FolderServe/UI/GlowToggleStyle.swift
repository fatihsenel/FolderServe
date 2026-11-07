import SwiftUI

/// Pill switch: gradient track with a soft glow when on, springy knob with a check/dot, hover lift.
struct GlowToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn
                          ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.35, green: 0.92, blue: 0.72), Color(red: 0.12, green: 0.65, blue: 0.62)],
                                                         startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.primary.opacity(hovering ? 0.22 : 0.14)))
                    .overlay(Capsule().strokeBorder(.white.opacity(configuration.isOn ? 0.35 : 0.18), lineWidth: 0.5))
                    .shadow(color: Theme.running.opacity(configuration.isOn ? (hovering ? 0.7 : 0.45) : 0), radius: hovering ? 9 : 6)
                Circle()
                    .fill(.white)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Color(red: 0.12, green: 0.55, blue: 0.5))
                            .opacity(configuration.isOn ? 1 : 0)
                            .scaleEffect(configuration.isOn ? 1 : 0.3))
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(2)
                    .scaleEffect(hovering && isEnabled ? 1.08 : 1)
            }
            .frame(width: 40, height: 22)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: configuration.isOn)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
        }
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAction { if isEnabled { configuration.isOn.toggle() } }
    }
}
