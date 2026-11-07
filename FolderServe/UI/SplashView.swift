import SwiftUI
import AppKit

enum SplashSettings {
    static let enabledKey = "showSplash"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    static let duration: Double = 2.4
    static let size = CGSize(width: 440, height: 520)
}

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
private func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

/// Splash content. `time` fixes the animation clock (used for static / Reduce Motion / snapshots);
/// nil means "animate from now".
struct SplashView: View {
    var time: Double?
    @State private var start = Date()

    var body: some View {
        Group {
            if let time { content(at: time) }
            else {
                TimelineView(.animation) { ctx in content(at: ctx.date.timeIntervalSince(start)) }
            }
        }
        .frame(width: SplashSettings.size.width, height: SplashSettings.size.height)
        .background(
            LinearGradient(colors: [Color(red: 0.09, green: 0.07, blue: 0.24), Color(red: 0.20, green: 0.10, blue: 0.40), Color(red: 0.42, green: 0.14, blue: 0.48)],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private func content(at t: Double) -> some View { SignalSplash(t: t) }
}

private struct AppIconImage: View {
    var size: CGFloat
    var body: some View {
        Image(nsImage: NSImage(named: "AppIcon") ?? NSImage()).resizable().frame(width: size, height: size)
    }
}

private struct Wordmark: View {
    let t: Double
    var delay = 0.4
    var tagline: String? = "Serve any folder, instantly"
    var body: some View {
        VStack(spacing: 6) {
            Text("FolderServe").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .opacity(clamp((t - delay) / 0.5)).offset(y: (1 - easeOut((t - delay) / 0.5)) * 8)
            if let tagline {
                Text(tagline).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                    .opacity(clamp((t - delay - 0.3) / 0.5))
            }
        }
    }
}

// Pulsing rings around the icon
private struct SignalSplash: View {
    let t: Double
    var body: some View {
        VStack(spacing: 34) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.7 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle().strokeBorder(Theme.accent.opacity((1 - phase) * 0.55), lineWidth: 2)
                        .frame(width: 130 + phase * 250, height: 130 + phase * 250)
                }
                AppIconImage(size: 150)
                    .scaleEffect(lerp(0.78, 1, easeOut(t / 0.6)))
                    .opacity(clamp(t / 0.35))
                    .shadow(color: Theme.accent.opacity(0.6), radius: 24)
            }
            .frame(height: 300)
            VStack(spacing: 18) {
                Wordmark(t: t)
                let dots = String(repeating: ".", count: Int(t * 3) % 4)
                Text(t > SplashSettings.duration - 0.5 ? "Ready" : "Starting servers\(dots)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.running.opacity(0.9))
                    .opacity(clamp((t - 0.9) / 0.4))
            }
        }
        .padding(.top, 20)
    }
}

/// Shows the splash in a borderless floating window and fades it out.
@MainActor
final class SplashController {
    static let shared = SplashController()
    private var window: NSWindow?

    func show() {
        guard window == nil else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let hosting = NSHostingView(rootView:
            SplashView(time: reduce ? SplashSettings.duration : nil)
                .onTapGesture { [weak self] in self?.dismiss() })
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: SplashSettings.size),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.contentView = hosting
        w.center()
        w.alphaValue = 0
        w.orderFrontRegardless()
        window = w
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; w.animator().alphaValue = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 1.0 : SplashSettings.duration)) { [weak self] in self?.dismiss() }
    }

    func dismiss() {
        guard let w = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; w.animator().alphaValue = 0 },
                                             completionHandler: { w.orderOut(nil) })
    }
}
