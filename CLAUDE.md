# FolderServe — notes for Claude

A native macOS app (SwiftUI window + menu bar) that serves folders over HTTP on localhost with live reload,
an API proxy, optional HTTPS and LAN sharing, and a dev-tools style Activity log. User-facing behaviour is
documented in `README.md`; the original design is in `docs/superpowers/specs/`.

## Layout

- `Packages/FolderServeCore` — the server, no UI: HTTP/1.1 on `NWListener` (`StaticServer`), `ProxyForwarder`,
  `WebSocketTunnel`, live reload (`FolderWatcher` + `ReloadHub`), `RequestLogEntry`, `ProjectDetector`, …
  Its tests run with `swift test`.
- `FolderServe/Model` — `ServerManager` (`@Observable`, owns servers, statuses and the request log), `ServerEntry`,
  persistence (`ServerStore`).
- `FolderServe/UI` — SwiftUI views. `Theme.swift` has colours, `.card()` and the `isSnapshotRendering` environment flag.
- `FolderServe/UI/Previews.swift` — `PreviewData` sample data and a `#Preview` for every non-private view.
- `FolderServeTests` — app tests, including snapshot tests that render views to PNG.
- `project.yml` — XcodeGen spec. **`FolderServe.xcodeproj` is generated and git-ignored.**

## Build and test

```bash
xcodegen generate                                                            # after adding or removing source files
xcodebuild -scheme FolderServe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme FolderServe -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
swift test --package-path Packages/FolderServeCore
```

CI (`.github/workflows/ci.yml`) runs `swift test` for the package and the app tests on a macOS runner for every push to `main`
and every pull request.

Run the whole suite before committing. `xcodebuild` prints a lot of `linkd` / `remoteObjectProxy` / `nw_path` log
noise that is harmless; filter with `grep -E "Executed|\*\* TEST|error:"`.

Single test class: `-only-testing:FolderServeTests/RequestDetailTests`.

## Conventions

- **Swift 5.10 mode**, macOS 14 minimum. SwiftUI views read the manager with `@Environment(ServerManager.self)`;
  it is injected with `.environment(manager)` (see `FolderServeApp`). A view that reads it **must get it in its
  preview too** — that was the cause of an earlier "No Observable object of type ServerManager found" crash.
- Put logic that needs tests in `static` functions on the view (`RequestDetailView.displayText`,
  `ActivityView.durationText`, …) and test them directly.
- Every non-private view gets a `#Preview` in `Previews.swift` (inside `#if DEBUG`), using `PreviewData.manager(populated:)`.
  Private views are covered by their parent's preview.
- Respect **Reduce Motion** (`@Environment(\.accessibilityReduceMotion)`) in any animation.
- Settings that are not per-server use `@AppStorage` / `UserDefaults` (`activityShowDetached`, `activityDetailHintSeen`).
- The app is **sandboxed**: it only reads folders the user drops or picks (security-scoped bookmarks, created read-only
  with `.securityScopeAllowOnlyReadAccess`). The `user-selected.read-write` entitlement exists only so Activity's Export can
  save a HAR file where the user chooses; nothing writes into served folders.
  Servers bind to `127.0.0.1` unless Share is on; non-loopback `Host` headers are rejected on purpose.
- Request bodies and headers are held in memory only and shown unmasked, like browser dev tools. Do not write them to disk.

## Snapshot tests (how to look at the UI without a display)

`ImageRenderer` renders a view to PNG. Set `.environment(\.isSnapshotRendering, true)` so views avoid what it cannot
draw (`ScrollView` content, AppKit-backed drop targets). Output goes to `$FOLDERSERVE_SNAPSHOT_DIR`
(default: the sandbox temp dir); with `xcodebuild` the variable must also be passed as `TEST_RUNNER_FOLDERSERVE_SNAPSHOT_DIR`:

```bash
D=/tmp/snaps; mkdir -p $D
FOLDERSERVE_SNAPSHOT_DIR=$D TEST_RUNNER_FOLDERSERVE_SNAPSHOT_DIR=$D \
  xcodebuild test -scheme FolderServe -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Known renderer quirks: a segmented `Picker`, a `TextField`, a `Menu` and a link-style button draw as a yellow bar with a
"no entry" icon, so views check `isSnapshotRendering` and draw a plain stand-in (the detail tabs, Activity's search and sort,
the proxy rule fields, a server's URL). Do the same for any new control. Hover/cursor/animation
cannot be captured — seed state through initialisers (`ActivityView(initiallyHovered:)`, `AddFolderButton(initiallyHovering:)`,
`JSONTreeView(folded:)`) and check the live behaviour by hand.

## Git workflow

- `origin` is the public GitHub repo `fatihsenel/FolderServe` (`main` only; feature branches stay local). Push `main` after a merge
  only when asked. Everything in the history is public: no secrets, real paths or real request data in code, tests or docs.
- Work on a branch (`feat/…`, `fix/…`), commit, then merge into `main` with `--no-ff` and a message like
  `Merge feat/x: what it does`. Commit messages are `feat(ui): …` / `fix(ui): …` with a short body.
- Adding a new source file, or switching to a branch that has different files, means regenerating the project
  (`xcodegen generate`); the generated `.xcodeproj` is not committed, and a stale one fails with "Build input file cannot be found".

## Things worth knowing

- Activity rows adapt to the list width (full → medium → compact) so nothing wraps when the detail panel is open;
  `ActivityView.rowDetail(for:)` holds the thresholds.
- The JSON preview is a foldable tree (`JSONTreeView` in `RequestDetailView.swift`); keys are sorted, matching
  `displayText`. Bodies that are not valid JSON objects/arrays, or are over 256 KB, fall back to plain text.
- `RequestLogEntry.durationMs` is how long the server took to answer; it feeds the Activity time column and the "Took" row.
- **Replay** (`RequestReplay`, the button in the detail panel) re-sends a captured request to the server's *current* address with an
  `X-FolderServe-Replay` header (`RequestLogEntry.replayHeader`). The proxy never forwards that header, and `RepeatAnalysis` uses it to
  say "replayed". Bodies are only replayable when captured whole.
- **Chunked request bodies** are decoded by `ChunkedBody` (core) in the proxy path and forwarded with a `Content-Length`; other transfer
  codings still get 501.
- **Name address** (`ServeOptions.friendlyHost`) only changes the URL the app shows and opens (`ServerManager.hostName(for:)`,
  `HostSlug`); `HostPolicy` already accepts any `*.localhost` host, and nothing else.
- Swift treats `"\r\n"` as a single `Character`, so `string.contains("\r")` does not match it: check `unicodeScalars` when guarding
  against header injection.
- The pointing-hand cursor uses `.handCursor()` (system-owned), never `NSCursor.push()`/`pop()`, which can leave the hand stuck.
- **Update check** (`UpdateChecker`, `UpdateViews.swift`): asks GitHub's latest-release API once a day, shows a banner / Settings row / menu item, and
  never installs anything. It is optional in the environment (`@Environment(\.updates)`, nil in previews and tests), so views using it need no injection.
  The release page address from GitHub's answer must be on github.com under this project before it is ever opened. Sparkle (in-place updates) was
  considered and left out on purpose: the sandbox needs extra XPC entitlements, and it needs a signing key and an appcast.
- **Recent folders** (`ServerManager.recents`, `MenuBarRecents`): `remove(_:)` keeps the removed `ServerEntry` (bookmark included) in `recents.json` (newest first, max 6);
  `reopenRecent(_:)` serves it again and `add(folder:)` also restores a matching recent's name, port and options. Tests pass no `recentsStore`, so nothing is written to disk.
- **Live reload** (`FolderWatcher` → `ReloadKind.classify` → `ReloadHub` → `ReloadScript`): the watcher passes the changed paths; a burst of only `.css` files sends `data: css`
  (pages re-fetch their same-origin `<link rel=stylesheet>` with a `_fs` query and keep their state), anything else sends `data: reload` (`location.reload()`).
  The script must keep reloading on any message other than `css`, so pages that still run an older script keep working.
  Editors save through a temporary file whose name varies by editor and macOS (`a.css.sb-…`, `.dat.nosync…`), so `classify` ignores paths that no longer exist
  (unless they look like a page or script) and needs at least one stylesheet that still does. CI runs an older macOS than development machines: test with explicit temp names.
- **Activity filters** combine: server picker, search words, category chips (`RequestCategory`) and status chips (`StatusFilter`: any / success 2xx / redirects 3xx / errors 4xx+). Each chip row counts what the *other* filters leave,
  and the HAR export respects all of them (`lines`).
- **Open in a browser** (`BrowserOpener`): every "open this server" goes through `BrowserOpener.open` (card Open, menu bar Recent folders, files passed to the app); it reads the browser's bundle id from
  `UserDefaults` (`openBrowserID`, empty = system default; an uninstalled browser falls back to the default). `ServeOptions.openPath` is appended by `ServerManager.openURL(for:)`; `normalizedPath` refuses anything that is not a
  path on the server. Settings' picker and the Options text field need snapshot stand-ins.
- **Edit & Replay** (`EditableRequest`, `EditReplayView`): the sheet edits a copy of the logged request; `EditableRequest.urlRequest(base:)` validates it (path-only target, header-name tokens, no control
  characters via `unicodeScalars`, reserved headers refused) and `RequestReplay.send` sends it. The sheet needs snapshot stand-ins for its pickers and text fields like every other control.
- **Menu bar actions** (`MenuBarRow`, `MenuBarBadge`): rows have Open / Copy URL / Start-Stop and a context menu. `ServerManager.unseenErrors` counts failed requests per server in `append` (rule: `RequestLogEntry.countsAsUnseenError`: 4xx/5xx, not replays,
  not detached, not `/favicon.ico`); the icon label shows the total, and it clears per server when the row's red number is tapped, or on stop, remove or clear log. Tapping it sets `ServerManager.activityRequest`, which `MainWindow` and `ActivityView`
  consume (server filter plus status chip). `openWindow` is used from the row because the popover is a `MenuBarExtra`.
- **Menu bar icon** (`MenuBarLabel`): the number is `ServerManager.attentionCount` (unseen failed requests plus servers in `.error`). Each logged request bumps `requestTick`; the label dims the glyph for 250 ms
  (`MenuBarBadge.shouldPulse`: off with Reduce Motion). The dim is a plain opacity change, not an animation, because a `MenuBarExtra` label is not animated reliably.
