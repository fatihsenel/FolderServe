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

    func load() -> [ServerEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ServerEntry].self, from: data)) ?? []
    }

    func save(_ entries: [ServerEntry]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}
