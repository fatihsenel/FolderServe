import Foundation

protocol ServerStoring {
    func load() -> [ServerEntry]
    func save(_ entries: [ServerEntry])
}

struct JSONFileStore: ServerStoring {
    let url: URL

    static var `default`: JSONFileStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FolderServe", isDirectory: true)
        return JSONFileStore(url: dir.appendingPathComponent("servers.json"))
    }

    /// Folders that were removed from the list but can be served again from the menu bar.
    static var recents: JSONFileStore {
        JSONFileStore(url: `default`.url.deletingLastPathComponent().appendingPathComponent("recents.json"))
    }

    func load() -> [ServerEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ServerEntry].self, from: data)) ?? []
    }

    func save(_ entries: [ServerEntry]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}
