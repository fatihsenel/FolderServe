import FolderServeCore

extension ServeOptions {
    /// How many of the switches tucked into the Options popover are on (shown as "Options · 2").
    var enabledExtrasCount: Int { [spaMode, caching, https, cors, friendlyHost].filter { $0 }.count }
}

extension ServeOptions {
    /// Fake responses and extra headers that are switched on and valid (shown on the Mocks button).
    var activeMockCount: Int {
        mockRules.filter { $0.enabled && $0.problem == nil }.count + headerRules.filter { $0.enabled && $0.problem == nil }.count
    }
}
