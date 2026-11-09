import FolderServeCore

extension ServeOptions {
    /// How many of the switches tucked into the Options popover are on (shown as "Options · 2").
    var enabledExtrasCount: Int { [spaMode, caching, https, cors, friendlyHost, !openPath.isEmpty, captureConsole].filter { $0 }.count }
}
