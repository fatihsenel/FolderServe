# FolderServe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS window + menu bar app that serves any folder over HTTP on localhost with live reload, SPA fallback and drag-and-drop.

**Architecture:** All server logic lives in a local Swift package (`FolderServeCore`) with no UI dependencies, tested with `swift test`. A SwiftUI app target (generated from an XcodeGen `project.yml`) depends on the package and owns persistence, windows, menu bar and drag-and-drop. HTTP is a hand-written HTTP/1.1 handler over `NWListener`.

**Tech Stack:** Swift 5.10+, SwiftUI (`MenuBarExtra`, `@Observable`), Network framework, FSEvents (CoreServices), XCTest, XcodeGen, Xcode 27.

**Spec:** `docs/superpowers/specs/2026-11-06-folderserve-design.md`

## Global Constraints

- macOS 14+ deployment target; no third-party runtime dependencies (XcodeGen is a build-time tool only).
- Server binds to `127.0.0.1` only.
- Dotfiles (`.env`, `.git`, …) are not served by default.
- Live reload: on by default, per-folder toggle, full-page reload only; script injected before `</body>` of HTML responses; SSE endpoint is `/__reload`; watcher debounce ~100 ms.
- SPA mode: per-folder toggle, on by default; fallback only when no file/dir matches, path has no extension, and `Accept` allows `text/html`; missing assets still 404.
- Traversal (`..`, encoded variants, symlinks escaping root) → 403.
- Port in use → next free port with a notice; manual port in use → error on the card.
- UI: CleanMyMac-inspired original design (translucent materials, dark gradient, sidebar, rounded cards, round start/stop button); no copied assets/branding; follows system light/dark.
- App sandboxed with security-scoped bookmarks for served folders.

## Review Focus

1. URLs with query strings/fragments (`/app.js?v=3`, `/page#x`) must resolve to the same file as without them.
2. Filenames with spaces, `%`-encoding and non-ASCII (`my file ü.html` ↔ `/my%20file%20%C3%BC.html`) must be served and listed with correct links.
3. Large files (≥ 500 MB) must be streamed in chunks, not read into memory; a client disconnecting mid-transfer must not crash or leak.
4. HTML lacking `</body>`, or with `</BODY>` casing, must still get the reload script (appended at end).
5. `Range` edge cases: suffix (`bytes=-500`), open-ended (`bytes=100-`), beyond EOF → 416 with `Content-Range: bytes */size`, and `HEAD` with `Range`.

---

### Task 1: Scaffold repo, core package, app project

**Files:**
- Create: `.gitignore`, `project.yml`, `FolderServe/FolderServeApp.swift`, `FolderServe/FolderServe.entitlements`, `Packages/FolderServeCore/Package.swift`, `Packages/FolderServeCore/Sources/FolderServeCore/FolderServeCore.swift`, `Packages/FolderServeCore/Tests/FolderServeCoreTests/SmokeTests.swift`

**Interfaces:**
- Produces: package target `FolderServeCore` (library, macOS 14), test target `FolderServeCoreTests`; app target + scheme `FolderServe` linking the package; `public enum FolderServeCore { public static let version: String }`.

- [ ] **Step 1:** `.gitignore` ignoring `.build/`, `*.xcodeproj`, `DerivedData/`, `.DS_Store`, `.claude-flow/`, `.swarm/`.
- [ ] **Step 2:** Write failing test `SmokeTests.testVersionIsNotEmpty` asserting `!FolderServeCore.version.isEmpty`. Run `swift test --package-path Packages/FolderServeCore` → FAIL (does not compile).
- [ ] **Step 3:** Create `Package.swift` (platforms `.macOS(.v14)`) and `FolderServeCore.swift` with `version = "0.1.0"`. Run tests → PASS.
- [ ] **Step 4:** Write `project.yml` (XcodeGen): app target `FolderServe`, bundle id `com.fatihsenel.FolderServe`, macOS 14, local package dependency on `Packages/FolderServeCore`, entitlements with `com.apple.security.app-sandbox`, `network.server`, `files.user-selected.read-only`, `files.bookmarks.app-scope`. `FolderServeApp.swift` is a minimal `@main App` with an empty `WindowGroup`.
- [ ] **Step 5:** `brew install xcodegen` if missing; run `xcodegen generate` then `xcodebuild -project FolderServe.xcodeproj -scheme FolderServe -destination 'platform=macOS' build` → `BUILD SUCCEEDED`.
- [ ] **Step 6:** Commit `chore: scaffold project`.

### Task 2: HTTP request parser

**Files:**
- Create: `Sources/FolderServeCore/HTTPRequestParser.swift`; Test: `Tests/FolderServeCoreTests/HTTPRequestParserTests.swift` (paths relative to `Packages/FolderServeCore/`)

**Interfaces:**
- Produces:
  - `public struct HTTPRequest: Equatable { method: String; path: String /* percent-decoded, no query/fragment */; rawQuery: String?; headers: [String:String] /* lowercased keys */ }`
  - `public enum HTTPParseResult: Equatable { case needMore; case request(HTTPRequest, consumed: Int); case malformed }`
  - `public enum HTTPRequestParser { public static func parse(_ data: Data) -> HTTPParseResult }`

- [ ] **Step 1:** Write failing tests: `testParsesSimpleGET`; `testSplitsQueryAndFragment` (`/app.js?v=3#x` → path `/app.js`, rawQuery `v=3`); `testDecodesPercentAndUnicode` (`/my%20file%20%C3%BC.html` → `/my file ü.html`); `testLowercasesHeaderNames`; `testNeedMoreWithoutBlankLine`; `testMalformedRequestLine` (`"GARBAGE\r\n\r\n"`); `testRejectsHeadersOverMaxSize` (>16 KB → malformed); `testConsumedCountsBytesOfFirstRequestOnly`.
- [ ] **Step 2:** Run `swift test --filter HTTPRequestParserTests` → FAIL.
- [ ] **Step 3:** Implement parser per signatures; split on `\r\n\r\n`; reject invalid percent-encoding and NUL bytes as `.malformed`.
- [ ] **Step 4:** Run tests → PASS. **Step 5:** Commit `feat(core): HTTP request parser`.

### Task 3: Path resolution (traversal, dotfiles, index, listing, SPA)

**Files:**
- Create: `Sources/FolderServeCore/PathResolver.swift`, `ServeOptions.swift`; Test: `PathResolverTests.swift`

**Interfaces:**
- Produces:
  - `public struct ServeOptions: Codable, Equatable { public var spaMode = true; public var liveReload = true; public var serveDotfiles = false }`
  - `public enum Resolution: Equatable { case file(URL); case directoryListing(URL); case redirect(String) /* path with trailing slash */; case notFound; case forbidden }`
  - `public struct PathResolver { public init(root: URL, options: ServeOptions); public func resolve(path: String, acceptsHTML: Bool) -> Resolution }`

- [ ] **Step 1:** Write failing tests using a temp-directory fixture: `testServesFile`; `testDirectoryWithIndexServesIndex`; `testDirectoryWithoutIndexListsIt`; `testDirectoryWithoutTrailingSlashRedirects`; `testDotDotIsForbidden` (`/../etc/passwd`, `/a/../../x`); `testSymlinkEscapingRootIsForbidden`; `testSymlinkInsideRootIsServed`; `testDotfileIsForbiddenByDefault` and served when `serveDotfiles`; `testNestedDotDirectoryForbidden` (`/.git/config`); `testSPAFallbackForExtensionlessPath` (→ `.file(root/index.html)`); `testSPANoFallbackForMissingAsset` (`/missing.js` → `.notFound`); `testSPANoFallbackWhenNotAcceptingHTML`; `testSPAOffReturnsNotFound`; `testSPAWithoutRootIndexReturnsNotFound`; `testUnicodeAndSpacesInName`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement: standardize + `resolvingSymlinksInPath()` the candidate and require the real path to have the real root as prefix (compare with trailing slash to avoid `/root2` matching `/root`).
- [ ] **Step 4:** Run → PASS. **Step 5:** Commit `feat(core): path resolver with SPA fallback`.

### Task 4: MIME types and Range handling

**Files:**
- Create: `Sources/FolderServeCore/MIMEType.swift`, `RangeHeader.swift`; Test: `MIMETypeTests.swift`, `RangeHeaderTests.swift`

**Interfaces:**
- Produces:
  - `public enum MIMEType { public static func forExtension(_ ext: String) -> String }` — covers html, css, js, mjs, json, svg, png, jpg, jpeg, gif, webp, ico, woff, woff2, ttf, wasm, mp4, webm, mp3, pdf, txt, xml, map; unknown → `application/octet-stream`; text types include `; charset=utf-8`.
  - `public enum RangeResult: Equatable { case none; case partial(ClosedRange<Int64>); case unsatisfiable }`
  - `public enum RangeHeader { public static func parse(_ header: String?, fileSize: Int64) -> RangeResult }`

- [ ] **Step 1:** Write failing tests: MIME for `html/js/css/wasm/svg`, case-insensitive ext, unknown fallback; Range: `bytes=0-99`, `bytes=100-` (open-ended), `bytes=-500` (suffix), end clamped to size-1, `bytes=9999-` on 100-byte file → `.unsatisfiable`, nil/garbage/multi-range (`bytes=0-1,5-6`) → `.none`, zero-byte file with any range → `.unsatisfiable`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS. **Step 5:** Commit `feat(core): MIME types and range parsing`.

### Task 5: Directory listing and error pages

**Files:**
- Create: `Sources/FolderServeCore/DirectoryListing.swift`, `ErrorPage.swift`; Test: `DirectoryListingTests.swift`

**Interfaces:**
- Produces:
  - `public enum DirectoryListing { public static func html(directory: URL, urlPath: String, showDotfiles: Bool) -> String }` — folders first, then files, alphabetical; links percent-encoded; names HTML-escaped; parent link `..` except at root.
  - `public enum ErrorPage { public static func html(status: Int, message: String) -> String }`

- [ ] **Step 1:** Write failing tests: ordering, hides dotfiles unless `showDotfiles`, escapes `<script>` in a filename, link for `my file ü.html` is `my%20file%20%C3%BC.html`, no `..` at `/`, error page contains status and escaped message.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement (self-contained HTML + inline CSS, light/dark via `prefers-color-scheme`). **Step 4:** Run → PASS. **Step 5:** Commit `feat(core): directory listing and error pages`.

### Task 6: StaticServer over NWListener (no live reload yet)

**Files:**
- Create: `Sources/FolderServeCore/StaticServer.swift`, `RequestLogEntry.swift`; Test: `StaticServerIntegrationTests.swift`

**Interfaces:**
- Consumes: `HTTPRequestParser`, `PathResolver`, `MIMEType`, `RangeHeader`, `DirectoryListing`, `ErrorPage`.
- Produces:
  - `public struct RequestLogEntry: Sendable { date: Date; method: String; path: String; status: Int; bytes: Int64 }`
  - `public final class StaticServer: @unchecked Sendable { public init(root: URL, port: UInt16, options: ServeOptions); public func start() async throws -> UInt16 /* actual port; 0 = ephemeral */; public func stop(); public func updateOptions(_ o: ServeOptions); public var onRequest: (@Sendable (RequestLogEntry) -> Void)? }`
  - `public enum StaticServerError: Error { case portInUse(UInt16); case listenerFailed(String) }`

- [ ] **Step 1:** Write failing integration tests (start on port 0, hit with `URLSession`): `testServesFileWithMIMEAndLength`; `testHEADHasHeadersNoBody`; `testIndexFallback`; `testListing`; `testRedirectToTrailingSlash` (301, `Location`); `testTraversalReturns403` (raw socket/`URLRequest` with `/%2e%2e/…`); `testMissingReturns404Page`; `testQueryStringIgnoredForLookup`; `testUnicodeFilename`; `testRange206PartialSuffixOpenEnded`; `testRangeBeyondEOF416WithContentRange`; `testHEADWithRange`; `testSPADeepLinkReturnsIndex200` and `testSPAMissingAssetReturns404`; `testNonGETMethodReturns405`; `testMalformedRequestReturns400AndServerSurvives`; `testBindsOnlyToLoopback` (connect via a non-loopback local interface address fails, skip if none); `testPortInUseThrows`; `testLargeFileStreamedWithoutMemorySpike` (sparse 600 MB file, request first 1 MB range and full request cancelled mid-way, server still serves the next request); `testOnRequestCallbackReportsStatusAndBytes`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement: bind with `NWParameters.tcp` and `requiredLocalEndpoint = 127.0.0.1:port`; per-connection state machine reads until `HTTPRequestParser` yields a request; sends headers then streams file in 64 KB chunks via `FileHandle`; `Connection: close` (keep-alive deferred, YAGNI); `Cache-Control: no-store`; `Accept-Ranges: bytes`; cancel file handle on connection failure.
- [ ] **Step 4:** Run → PASS. **Step 5:** Commit `feat(core): static HTTP server`.

### Task 7: Live reload (watcher, SSE hub, script injection)

**Files:**
- Create: `Sources/FolderServeCore/FolderWatcher.swift`, `ReloadScript.swift`, `ReloadHub.swift`; Modify: `StaticServer.swift`; Test: `ReloadScriptTests.swift`, `FolderWatcherTests.swift`, `LiveReloadIntegrationTests.swift`

**Interfaces:**
- Produces:
  - `public enum ReloadScript { public static func inject(into html: Data) -> Data }` — inserts `<script>new EventSource('/__reload').onmessage=()=>location.reload()</script>` before the last case-insensitive `</body>`, else appends.
  - `public final class FolderWatcher { public init(root: URL, debounce: TimeInterval = 0.1, onChange: @escaping @Sendable () -> Void); public func start(); public func stop() }` (FSEvents, recursive).
  - `final class ReloadHub { func add(_ c: NWConnection); func broadcast(); func removeAll() }` (internal); `StaticServer` serves `GET /__reload` as `text/event-stream` and calls `hub.broadcast()` on watcher change when `options.liveReload`.

- [ ] **Step 1:** Write failing tests: inject before `</body>`; `</BODY>` casing; no `</body>` appends; non-HTML (css/js/png) never modified and `Content-Length` of injected HTML correct; watcher fires once for a burst of 5 writes within debounce window; watcher sees nested-directory change; integration: connect to `/__reload`, touch a file, receive `data:` event within 2 s; no event when `liveReload == false`; SPA fallback response contains the script; `Range` requests on HTML are not injected.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement; stop watcher and drop SSE connections in `StaticServer.stop()`; send `: ping` comment every 15 s to keep connections alive.
- [ ] **Step 4:** Run → PASS. **Step 5:** Commit `feat(core): live reload`.

### Task 8: Port finder

**Files:**
- Create: `Sources/FolderServeCore/PortFinder.swift`; Test: `PortFinderTests.swift`

**Interfaces:**
- Produces: `public enum PortFinder { public static func firstFree(startingAt: UInt16, upTo: UInt16 = 65535) -> UInt16? }` (probes by binding to 127.0.0.1).

- [ ] **Step 1:** Failing tests: returns start port when free; skips an occupied port (occupy with a `StaticServer`); returns nil when range exhausted.
- [ ] **Step 2–4:** Run FAIL → implement via BSD `socket/bind` probe → PASS. **Step 5:** Commit `feat(core): port finder`.

### Task 9: ServerEntry, persistence, ServerManager

**Files:**
- Create: `FolderServe/Model/ServerEntry.swift`, `ServerStore.swift`, `ServerManager.swift`; Test target `FolderServeTests` (add to `project.yml`): `ServerManagerTests.swift`

**Interfaces:**
- Consumes: `StaticServer`, `ServeOptions`, `PortFinder`.
- Produces:
  - `struct ServerEntry: Codable, Identifiable { id: UUID; bookmark: Data; folderPath: String; preferredPort: UInt16?; options: ServeOptions; autoStart: Bool }`
  - `enum ServerStatus: Equatable { case stopped; case running(port: UInt16); case error(String); case folderMissing }`
  - `protocol ServerStoring { func load() -> [ServerEntry]; func save(_ e: [ServerEntry]) }` with JSON file implementation in Application Support.
  - `@MainActor @Observable final class ServerManager { init(store: ServerStoring); var entries: [ServerEntry]; var statuses: [UUID: ServerStatus]; var notice: String?; var log: [RequestLogEntry] /* last 500 */; func add(folder: URL) -> UUID /* de-dupes same path, starts it */; func addDropped(url: URL) -> (id: UUID, openPath: String?); func remove(_ id: UUID); func start(_ id: UUID); func stop(_ id: UUID); func setOptions(_ id: UUID, _ o: ServeOptions); func relocate(_ id: UUID, to: URL); func startAutoStartEntries(); func stopAll() }`

- [ ] **Step 1:** Write failing tests (in-memory store): add starts server and status `.running`; adding same folder twice returns same id; port conflict picks next free and sets `notice`; preferred manual port taken → `.error`; deleting folder on disk then `start` → `.folderMissing`; persistence round-trip; `addDropped` with a file URL serves parent and returns `openPath`; `setOptions` live-updates a running server (reload toggle); `stopAll` stops all.
- [ ] **Step 2:** Run `xcodebuild test -scheme FolderServe -destination 'platform=macOS'` → FAIL.
- [ ] **Step 3:** Implement; resolve bookmarks with `.withSecurityScope`, hold `startAccessingSecurityScopedResource` while running and release on stop.
- [ ] **Step 4:** Run → PASS. **Step 5:** Commit `feat(app): server manager and persistence`.

### Task 10: Theme and main window (sidebar, cards, empty state)

**Files:**
- Create: `FolderServe/UI/Theme.swift`, `MainWindow.swift`, `SidebarView.swift`, `ServersView.swift`, `ServerCardView.swift`, `DropZoneView.swift`, `RoundActionButton.swift`; Modify: `FolderServeApp.swift` (inject `ServerManager` via `.environment`)

**Interfaces:**
- Consumes: `ServerManager` API from Task 9.
- Produces: `enum SidebarItem { servers, activity, settings }`; `Theme` (gradient, card style, accent colors, `statusColor(_: ServerStatus)`); `ServerCardView(entryID: UUID)`; `DropZoneView` accepting folder drops via `.dropDestination(for: URL.self)` → `manager.addDropped`.

- [ ] **Step 1:** Add `#Preview`s for empty state, running card, error card, folder-missing card. Build → `BUILD SUCCEEDED`.
- [ ] **Step 2:** Implement views: translucent `.ultraThinMaterial` window background over dark gradient; sidebar; cards show folder name, path, URL, status glow, round start/stop button, open-in-browser (`NSWorkspace`), copy URL, live-reload toggle, SPA toggle, remove, and "Relocate…" on `.folderMissing`; "Add Folder…" uses `NSOpenPanel`; `notice` shown as a dismissible banner.
- [ ] **Step 3:** Launch the app (`run` skill), add a temp folder, verify start/stop, URL opens in browser, toggles work; capture screenshots of empty and populated states.
- [ ] **Step 4:** Commit `feat(app): main window UI`.

### Task 11: Drag and drop everywhere

**Files:**
- Create: `FolderServe/AppDelegate.swift`; Modify: `FolderServeApp.swift`, `project.yml` (declare `public.folder` document type so Dock-icon drops are accepted)

**Interfaces:**
- Consumes: `ServerManager.addDropped(url:)`.
- Produces: `AppDelegate.application(_:open:)` handling folder/file URLs from Dock-icon drops and `open -a FolderServe <folder>`.

- [ ] **Step 1:** Write failing unit test in `FolderServeTests`: `AppDelegate.handleOpen(urls:manager:)` adds each folder and, for a file URL, opens `http://127.0.0.1:<port>/<file>` via an injectable opener closure.
- [ ] **Step 2:** Run → FAIL; implement; run → PASS.
- [ ] **Step 3:** Manually verify: `open -a <built app> ~/some/folder`, drop folder on Dock icon, on the window, and on the menu bar icon (Task 12); record results.
- [ ] **Step 4:** Commit `feat(app): drag and drop and open-with`.

### Task 12: Menu bar companion

**Files:**
- Create: `FolderServe/UI/MenuBarView.swift`; Modify: `FolderServeApp.swift` (add `MenuBarExtra` scene, `.window` style)

**Interfaces:**
- Consumes: `ServerManager`.
- Produces: `MenuBarView` — compact list (name, status dot, start/stop, copy URL), "Add Folder…", "Open FolderServe", "Quit"; menu bar icon accepts folder drops (`.dropDestination`).

- [ ] **Step 1:** Add previews; build. **Step 2:** Implement. **Step 3:** Launch and verify start/stop from menu bar reflects in main window and vice versa; screenshot.
- [ ] **Step 4:** Commit `feat(app): menu bar companion`.

### Task 13: Activity log and Settings

**Files:**
- Create: `FolderServe/UI/ActivityView.swift`, `SettingsView.swift`; Modify: `ServerManager.swift` (global `serveDotfiles` default, launch-at-login)

**Interfaces:**
- Consumes: `ServerManager.log`.
- Produces: Activity table (time, method, path, status colored, bytes, filter by server); Settings: serve dotfiles (applies to all servers), start enabled servers at launch (`autoStart`), launch at login (`SMAppService.mainApp`).

- [ ] **Step 1:** Failing unit test: toggling global dotfiles calls `setOptions` on every entry and a running server then serves `/.env`. Run → FAIL; implement; run → PASS.
- [ ] **Step 2:** Implement views; verify Activity shows live requests when loading a served page in a browser.
- [ ] **Step 3:** Commit `feat(app): activity log and settings`.

### Task 14: End-to-end verification and polish

**Files:**
- Create: `README.md`; Modify as needed

- [ ] **Step 1:** Run full suite: `swift test --package-path Packages/FolderServeCore` and `xcodebuild test -scheme FolderServe -destination 'platform=macOS'` → all pass.
- [ ] **Step 2:** Manual E2E with a real Vite/React-Router build (or a hand-written SPA fixture): deep link refresh works, edit a file → browser auto-reloads, relaunch app → folders restored and autoStart servers running, delete a served folder → card shows "Folder missing", two folders served at once on different ports.
- [ ] **Step 3:** Verify sandbox: app can read a folder only after drop/pick, and bookmarks survive relaunch.
- [ ] **Step 4:** Write `README.md` (build with `xcodegen generate`, features, limits). Commit `docs: README`.

---

## Self-Review

- **Spec coverage:** StaticServer features (T2–T6), SPA (T3, T6, T7), live reload (T7), ServerManager/persistence/bookmarks/port handling/folder-missing (T8–T9), window UI + cards + toggles (T10), drop on window/Dock/menu bar (T10–T12), menu bar (T12), Activity (T13), dotfile setting (T13), error handling (T3, T6, T9, T10), testing section (every task + T14). No gaps found.
- **Type consistency:** `ServeOptions`, `Resolution`, `RequestLogEntry`, `ServerStatus`, `ServerManager` method names match across tasks.
- **Review Focus** items each have a named test: #1 `testQueryStringIgnoredForLookup`/`testSplitsQueryAndFragment`; #2 `testUnicodeFilename`/listing test; #3 `testLargeFileStreamedWithoutMemorySpike`; #4 ReloadScript casing/append tests; #5 Range tests in T4/T6.
