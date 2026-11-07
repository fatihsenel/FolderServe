import SwiftUI
import AppKit

enum SplashStyle: String, CaseIterable, Identifiable {
    case signal, assembly, minimal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .signal: "Signal rings"
        case .assembly: "Folder assembly"
        case .minimal: "Minimal"
        }
    }
}

enum SplashSettings {
    static let enabledKey = "showSplash"
    static let styleKey = "splashStyle"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    static var style: SplashStyle {
        get { SplashStyle(rawValue: UserDefaults.standard.string(forKey: styleKey) ?? "") ?? .signal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: styleKey) }
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
    let style: SplashStyle
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

    @ViewBuilder private func content(at t: Double) -> some View {
        switch style {
        case .signal: SignalSplash(t: t)
        case .assembly: AssemblySplash(t: t)
        case .minimal: MinimalSplash(t: t)
        }
    }
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

// A — pulsing rings around the icon
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

// B — file chips fly into a folder, then it goes live
private struct AssemblySplash: View {
    let t: Double
    private let chips: [(name: String, color: Color, dx: Double, dy: Double, at: Double)] = [
        ("index.html", Color(red: 0.93, green: 0.93, blue: 1.0), -150, -150, 0.3),
        ("app.js", Color(red: 0.62, green: 0.88, blue: 0.80), 150, -120, 0.65),
        ("style.css", Color(red: 0.69, green: 0.66, blue: 0.93), -110, -60, 1.0),
    ]
    private var landed: Int { chips.filter { t > $0.at + 0.5 }.count }
    private var bump: Double {
        // short squash each time a chip lands
        guard let last = chips.map({ $0.at + 0.5 }).filter({ $0 < t }).max() else { return 0 }
        let x = (t - last) / 0.25
        return x < 1 ? sin(x * .pi) * 0.07 : 0
    }

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                folder.scaleEffect(1 + bump).offset(y: 30)
                ForEach(0..<chips.count, id: \.self) { i in
                    let c = chips[i]
                    let p = easeOut((t - c.at) / 0.5)
                    if t >= c.at && p < 1 {
                        Text(c.name).font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.15, green: 0.12, blue: 0.4))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(c.color))
                            .scaleEffect(lerp(1, 0.5, p)).opacity(1 - p * 0.9)
                            .offset(x: lerp(c.dx, 0, p), y: lerp(c.dy, 30, p))
                    }
                }
            }
            .frame(height: 300)
            VStack(spacing: 16) {
                Wordmark(t: t, delay: 1.0, tagline: nil)
                HStack(spacing: 8) {
                    Circle().fill(Theme.running).frame(width: 8, height: 8)
                        .shadow(color: Theme.running, radius: 5).opacity(0.6 + 0.4 * sin(t * 6))
                    Text("Live on 127.0.0.1").font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.1)))
                .opacity(clamp((t - 1.7) / 0.4)).scaleEffect(lerp(0.9, 1, easeOut((t - 1.7) / 0.4)))
            }
        }
        .padding(.top, 20)
    }

    private var folder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.79, blue: 0.65), Color(red: 0.11, green: 0.62, blue: 0.46)], startPoint: .top, endPoint: .bottom))
                .frame(width: 170, height: 120).offset(y: -4)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.36, green: 0.79, blue: 0.65)).frame(width: 64, height: 24).offset(x: -53, y: -66)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.72, green: 0.92, blue: 0.85), Color(red: 0.50, green: 0.85, blue: 0.72)], startPoint: .top, endPoint: .bottom))
                .frame(width: 170, height: 92).offset(y: 14)
        }
        .shadow(color: Theme.running.opacity(0.3), radius: 20, y: 8)
    }
}

// C — logo, progress bar, version
private struct MinimalSplash: View {
    let t: Double
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    var body: some View {
        VStack(spacing: 28) {
            AppIconImage(size: 170)
                .scaleEffect(lerp(0.85, 1, easeOut(t / 0.7))).opacity(clamp(t / 0.4))
                .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
            Wordmark(t: t, delay: 0.3, tagline: nil)
            VStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14)).frame(width: 160, height: 4)
                    Capsule().fill(LinearGradient(colors: [Theme.running, Theme.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 160 * easeOut(t / SplashSettings.duration), height: 4)
                }
                Text("Version \(version)").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            .opacity(clamp((t - 0.5) / 0.4))
        }
        .padding(.top, 20)
    }
}

/// Shows the splash in a borderless floating window and fades it out.
@MainActor
final class SplashController {
    static let shared = SplashController()
    private var window: NSWindow?

    func show(style: SplashStyle = SplashSettings.style) {
        guard window == nil else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let hosting = NSHostingView(rootView:
            SplashView(style: style, time: reduce ? SplashSettings.duration : nil)
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
