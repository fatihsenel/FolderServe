# FolderServe

A native macOS app (window + menu bar) that serves any folder over HTTP on localhost — for previewing
static sites and single page apps, with live reload.

## Features

- Drop a folder on the window, the Dock icon or the menu bar popover — it starts serving immediately.
  Also works from Terminal: `open -a FolderServe ~/my-site`.
- Many folders at once, each on its own port (starts at 8080, next free port if busy).
- **Live reload**: a small script is injected into HTML pages; editing a file refreshes open tabs.
- **SPA mode**: unknown extension-less paths return `index.html` (React Router, Vue Router, …).
  Missing assets (`/missing.js`) still return 404.
- Range requests (video/audio seeking), directory listings, correct MIME types, files streamed in chunks.
- Servers listen on `127.0.0.1` only. Path traversal (`..`, encoded, symlinks leaving the folder) → 403.
  Dotfiles (`.env`, `.git`) are not served unless you enable it in Settings.
- Activity log of requests, per-folder toggles, start-at-launch and launch-at-login.

## Build

Requires Xcode 15+ (developed with Xcode 27) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate            # creates FolderServe.xcodeproj from project.yml
open FolderServe.xcodeproj   # or: xcodebuild -scheme FolderServe -destination 'platform=macOS' build
```

## Tests

```bash
swift test --package-path Packages/FolderServeCore                       # server logic (HTTP, paths, live reload)
xcodebuild test -scheme FolderServe -destination 'platform=macOS'        # app: server manager, open handling, UI snapshots
```

## Layout

- `Packages/FolderServeCore` — HTTP/1.1 server on `NWListener`, path resolver, live reload (FSEvents + SSE), port finder. No UI.
- `FolderServe/` — SwiftUI app: `Model/` (ServerManager, persistence), `UI/` (window, menu bar, theme).
- `docs/superpowers/` — design spec and implementation plan.

## Known limits

- The app is sandboxed: it can only read folders you drop or pick. Dropping a single *file* grants access
  to that file only, so sibling files of a dropped file may not be readable.
- Dropping onto the menu bar *icon* itself is not supported (SwiftUI `MenuBarExtra`); drop on the popover instead.
- HTTP only (no HTTPS), no LAN access, no CSS hot-swap — see the spec's out-of-scope list.
