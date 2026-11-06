import Foundation
import CoreServices

/// Recursive FSEvents watcher that coalesces bursts of changes into one `onChange` call.
public final class FolderWatcher: @unchecked Sendable {
    private let root: URL
    private let debounce: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "folderserve.watcher")
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    public init(root: URL, debounce: TimeInterval = 0.1, onChange: @escaping @Sendable () -> Void) {
        self.root = root.resolvingSymlinksInPath()
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        queue.sync {
            guard stream == nil else { return }
            var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                               retain: nil, release: nil, copyDescription: nil)
            let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                watcher.handle(Array(list.prefix(count)))
            }
            let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
            guard let s = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [root.path] as CFArray,
                                              FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags) else { return }
            FSEventStreamSetDispatchQueue(s, queue)
            FSEventStreamStart(s)
            stream = s
        }
    }

    public func stop() {
        queue.sync {
            pending?.cancel()
            pending = nil
            guard let s = stream else { return }
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
    }

    // Runs on `queue` (the stream's dispatch queue).
    private func handle(_ paths: [String]) {
        guard paths.contains(where: { !Self.isIgnored($0) }) else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [onChange] in onChange() }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private static func isIgnored(_ path: String) -> Bool {
        path.contains("/.git/") || path.hasSuffix("/.git") || path.hasSuffix("/.DS_Store")
    }
}
