import Foundation

/// A dotted version such as `0.2.0` or `v1.4` (a leading `v` is ignored). `0.2.0-beta` sorts before `0.2.0`.
struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    let numbers: [Int]
    let isPrerelease: Bool

    init?(_ text: String) {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        let pre = t.firstIndex(of: "-")
        let core = pre.map { String(t[..<$0]) } ?? t
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, !parts.contains(nil) else { return nil }
        numbers = parts.compactMap { $0 }
        isPrerelease = pre != nil
    }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.numbers.count, b.numbers.count)
        for i in 0..<n {
            let x = i < a.numbers.count ? a.numbers[i] : 0, y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x < y }
        }
        return a.isPrerelease && !b.isPrerelease
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }

    var description: String { numbers.map(String.init).joined(separator: ".") + (isPrerelease ? "-pre" : "") }
}

struct LatestRelease: Equatable {
    var tag: String
    var version: AppVersion
    /// The release page (checked to be on github.com under this project before it is ever opened).
    var url: URL
}

enum UpdateError: Error, Equatable {
    case badResponse
    case network(String)

    var message: String {
        switch self {
        case .badResponse: "GitHub's answer could not be read."
        case .network(let text): "Could not reach GitHub: \(text)"
        }
    }
}

/// Asks GitHub whether a newer release exists. It only reads the latest release's version and page; nothing about
/// the user or their folders is sent. The app never installs anything itself.
@MainActor
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(LatestRelease)
        case failed(String)
    }

    static let repository = "fatihsenel/FolderServe"
    static let enabledKey = "checkForUpdates"
    static let lastCheckKey = "lastUpdateCheck"
    static let dismissedKey = "dismissedUpdateTag"
    /// Automatic checks happen at most this often.
    static let interval: TimeInterval = 24 * 60 * 60

    private(set) var state: State = .idle
    /// The release whose banner the user closed (so it does not come back until a newer one appears).
    private(set) var dismissedTag: String?

    let currentVersion: AppVersion
    private let fetch: () async throws -> LatestRelease
    private let defaults: UserDefaults
    private let now: () -> Date

    init(currentVersion: AppVersion? = nil,
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         fetch: (() async throws -> LatestRelease)? = nil) {
        self.currentVersion = currentVersion
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) ?? AppVersion("0")!
        self.defaults = defaults
        self.now = now
        self.fetch = fetch ?? { try await Self.fetchFromGitHub() }
        self.dismissedTag = defaults.string(forKey: Self.dismissedKey)
    }

    /// Automatic checks are on unless the user turned them off in Settings.
    var automaticChecksEnabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }

    /// The newer release to show a banner for (nil when up to date, unknown or dismissed).
    var bannerRelease: LatestRelease? {
        if case .available(let r) = state, r.tag != dismissedTag { return r }
        return nil
    }

    func dismissBanner() {
        guard case .available(let r) = state else { return }
        dismissedTag = r.tag
        defaults.set(r.tag, forKey: Self.dismissedKey)
    }

    /// At launch: checks when automatic checks are on and the last check is over a day old.
    func checkIfDue() async {
        guard automaticChecksEnabled else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date, now().timeIntervalSince(last) < Self.interval { return }
        await run()
    }

    /// The "Check now" button and the menu item: always asks, and shows the banner again even if it was closed.
    @discardableResult
    func checkNow() async -> State {
        dismissedTag = nil
        defaults.removeObject(forKey: Self.dismissedKey)
        await run()
        return state
    }

    private func run() async {
        guard state != .checking else { return }
        state = .checking
        defaults.set(now(), forKey: Self.lastCheckKey)   // recorded even on failure, so a broken network is not retried at every launch
        do {
            let latest = try await fetch()
            state = latest.version > currentVersion ? .available(latest) : .upToDate
        } catch let error as UpdateError {
            state = .failed(error.message)
        } catch {
            state = .failed(UpdateError.network(error.localizedDescription).message)
        }
    }

    // MARK: GitHub

    static var latestReleaseURL: URL { URL(string: "https://api.github.com/repos/\(repository)/releases/latest")! }

    static func fetchFromGitHub(session: URLSession = .shared) async throws -> LatestRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FolderServe", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }
            return try parse(data)
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
    }

    /// Reads `tag_name` and `html_url` from GitHub's "latest release" answer. Drafts and pre-releases are refused, and the page
    /// address must be on github.com under this project (an answer cannot send the user to another site).
    static func parse(_ data: Data) throws -> LatestRelease {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, let version = AppVersion(tag),
              let page = json["html_url"] as? String, let url = URL(string: page),
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/\(repository)/") else { throw UpdateError.badResponse }
        return LatestRelease(tag: tag, version: version, url: url)
    }

    /// What to run for people who installed with Homebrew.
    static let brewCommand = "brew upgrade --cask folderserve"
}

/// What Settings says about the last check.
enum UpdateStatusText {
    static func make(_ state: UpdateChecker.State, current: AppVersion) -> String {
        switch state {
        case .idle: "You have version \(current)."
        case .checking: "Checking…"
        case .upToDate: "You have the latest version (\(current))."
        case .available(let r): "Version \(r.version) is available (you have \(current))."
        case .failed(let message): message
        }
    }
}
