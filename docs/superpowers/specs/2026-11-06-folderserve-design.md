# FolderServe — Design Spec

Date: 2026-11-06

## Purpose

A native macOS app that serves any folder over HTTP on localhost for local web
development preview. Pick or drag in a folder, get a URL, and see changes in the
browser instantly via live reload.

Not a production server. Not for LAN sharing (v1 binds to 127.0.0.1 only).

## Success criteria

- Drop a folder on the window, menu bar icon, or Dock icon → server running and URL
  available within a second, no further configuration.
- Multiple folders can be served at once, each on its own port.
- Editing a file in a served folder reloads open browser tabs automatically.
- Servers and folder list persist across app launches.
- Cannot be used to read files outside the served folder.

## Decisions (agreed with user)

- Native Swift/SwiftUI, built with Xcode, macOS 14+.
- App shape: main window **plus** menu bar companion.
- UI style: CleanMyMac-inspired (original implementation, no copied assets or
  branding): translucent materials, dark gradient, sidebar, large rounded cards,
  prominent round start/stop button. Follows system light/dark.
- Live reload included in v1. Drag-and-drop included in v1.
- Server binds to `127.0.0.1` only.

## Architecture

Xcode project with a local Swift package (`FolderServeCore`) holding the logic so it is
testable without UI, and a SwiftUI app target depending on it.

### Units

- **StaticServer** (package) — serves one folder on one port using Network framework
  (`NWListener`) and a hand-written HTTP/1.1 parser. Supports GET and HEAD, URL→file
  mapping with path-traversal protection, MIME types, `Range` requests, `index.html`
  fallback, generated directory listing, 400/403/404 pages. Dotfiles (e.g. `.env`,
  `.git`) not served by default (setting to change).
  **SPA mode** (per-folder toggle, on by default): when a GET/HEAD request matches no
  file or directory, and the path has no file extension, and the `Accept` header allows
  `text/html`, respond 200 with the root `index.html` so client-side routers (React
  Router, Vue Router, etc.) work on deep links and refresh. Requests that look like
  assets (have an extension, e.g. missing `.js`/`.css`/`.png`) still return a real 404.
  Live-reload script injection applies to the fallback page too. If no root `index.html`
  exists, normal 404 behaviour applies.
- **LiveReload** (package) — per-server FSEvents watcher on the folder, debounced
  ~100 ms. StaticServer injects a small `<script>` before `</body>` of HTML responses
  that connects via Server-Sent Events to `/__reload`; on change the server emits a
  `reload` event and the page refreshes. On by default, toggle per folder. Full-page
  reload only in v1 (no CSS hot-swap).
- **ServerManager** (app) — observable list of entries (folder, port, running state,
  live-reload flag). Persists to disk. Picks next free port when requested port is
  taken. Stores security-scoped bookmarks for folder access.
- **UI** (app) — SwiftUI.
  - Main window: sidebar (Servers, Activity, Settings). Servers view shows a large drop
    zone when empty; otherwise one rounded card per folder with status glow, URL,
    start/stop button, open-in-browser, copy URL, live-reload toggle, SPA-mode toggle,
    remove.
    Activity shows a live request log.
  - `MenuBarExtra` popover: compact server list, start/stop, copy URL, "Open App".
  - Drop targets: main window, menu bar icon, Dock icon. Dropping a folder adds and
    starts it on a free port. Dropping a file serves its parent folder and opens that file.

## Error handling

- Port in use: auto-pick next free port with a notice; a manually chosen port shows an
  error on the card.
- Folder moved/deleted: card turns amber "Folder missing", server stops, user can
  relocate or remove.
- Unresolvable bookmark: prompt to re-select the folder.
- Malformed requests never crash the server; connections are isolated.
- Traversal attempts (`..`, encoded variants, symlinks escaping root) → 403.

## Testing

- XCTest unit tests for StaticServer: traversal (plain, encoded, symlink), MIME types,
  Range, index fallback, directory listing, HEAD vs GET, script injection only on HTML,
  SPA fallback (deep link → index.html, missing asset → 404, toggle off → 404, no
  root index.html → 404, fallback response gets reload script).
- Integration: real server on ephemeral port via `URLSession`; modify a file and assert
  an SSE `reload` event arrives.
- UI verified manually by building and launching: drag and drop, start/stop, menu bar
  popover, with screenshots.

## Out of scope (v1)

LAN/remote access, HTTPS, CSS hot-swap, proxying/custom rewrite rules (only the SPA
index.html fallback is supported), authentication, server-side scripting.
