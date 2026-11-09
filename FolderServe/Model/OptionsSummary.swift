import FolderServeCore

extension ServeOptions {
    /// How many of the switches tucked into the Options popover are on (shown as "Options · 2").
    /// "200 ms", "1 s", "2.5 s" — or "Off".
    static func delayLabel(_ ms: Int) -> String {
        if ms <= 0 { return "Off" }
        if ms < 1000 { return "\(ms) ms" }
        return ms % 1000 == 0 ? "\(ms / 1000) s" : String(format: "%.1f s", Double(ms) / 1000)
    }

    var enabledExtrasCount: Int { [spaMode, caching, https, cors, friendlyHost, !openPath.isEmpty, captureConsole, effectiveDelayMs > 0].filter { $0 }.count }
}
