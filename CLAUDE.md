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
- The app is **sandboxed**: it only reads folders the user drops or picks (security-scoped bookmarks).
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

Known renderer quirks: a segmented `Picker` draws as a yellow bar with a "no entry" icon, and hover/cursor/animation
cannot be captured — seed state through initialisers (`ActivityView(initiallyHovered:)`, `AddFolderButton(initiallyHovering:)`,
`JSONTreeView(folded:)`) and check the live behaviour by hand.

## Git workflow

- There is **no remote**: everything lives in this local repo. Do not assume a push target.
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
