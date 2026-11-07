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
- Requests whose `Host` header is not a loopback name (`localhost`, `*.localhost`, `127.x.x.x`, `[::1]`) get 403, to block DNS-rebinding
  attacks from web pages. This also means tunnels that forward a public hostname (ngrok etc.) are rejected.
- HTTP only (no HTTPS), no LAN access, no CSS hot-swap — see the spec's out-of-scope list.

## Project badges

Each server card (and menu bar row) shows the detected framework: Angular, React, Vue, Svelte, Next.js,
Nuxt, Astro, Vite or plain HTML. Source folders are identified from `package.json` / config files; built
output (`dist/`, `build/`) from markers in `index.html`. Detection for built output is heuristic. The mark
appears once the server has started. Logos are from [Simple Icons](https://simpleicons.org) (CC0); the
framework names and logos are trademarks of their owners.

The app icon source is `branding/AppIcon.svg`.

## CORS

Each folder has a **CORS** switch (off by default). When on, responses carry
`Access-Control-Allow-Origin: *` and `OPTIONS` preflight requests are answered, so a page on another
origin (for example an app on `localhost:4200`) can read files served here.

Turning it on lets *any* website open in your browser read those files, so leave it off unless you need it.
It does not help with errors from calling an API on another origin from your served app: for that, use the
API proxy below.

## API proxy

The **Proxy** button on a folder card forwards requests that start with a prefix to another server, so the
browser only ever talks to one origin and CORS does not apply (like the proxy in Vite or Angular's dev server).

Example: `/uiapi` → `https://localhost:5003` sends `/uiapi/Account/Login` to
`https://localhost:5003/uiapi/Account/Login`. Tick "Remove prefix" to send `/Account/Login` instead.

- Methods: GET, POST, PUT, PATCH, DELETE, HEAD (request bodies up to 32 MB). Responses are streamed.
- Rules take precedence over files in the folder; invalid rules are ignored.
- **Hard-coded API address:** if your app has the target address in its files (for example
  `"baseUrl": "https://localhost:5003/uiapi/"` in `assets/config.json`), the browser would still call the API
  directly and hit CORS. With "Point this address at FolderServe in served files" (on by default), the address is
  replaced by this server's address in `.json`, `.js`, `.mjs` and `.html` files (up to 10 MB) as they are served.
  Files on disk are not changed. Addresses that are assembled in code (`"https://" + host`) are not detected.
- Self-signed certificates are accepted for `localhost` / `127.x` targets only (ASP.NET Core dev certificate).
- `Origin` and `Referer` are rewritten to the target. Redirects are not followed; a `Location` pointing at the
  target is turned into a local path.
- `Set-Cookie`: `Secure` and `Domain` are removed and `SameSite=None` becomes `Lax`, because the browser reaches
  the proxy over plain http.
- Requests from other origins (`Origin` or `Sec-Fetch-Site` not same-origin) get 403 unless CORS is on for the
  folder, so a web page cannot drive your backend through the proxy.
- WebSockets (and other `Upgrade` connections) pass through a proxy rule as a plain byte tunnel, so dev-server hot reload and SignalR work. The cross-origin guard applies to them too.
- Not supported: chunked request bodies, HTTP/2 to the browser.
- The app allows plain-http targets (`NSAllowsArbitraryLoads`), because the target is whatever you configure.

## Activity

The Activity tab lists requests with a dev-tools style category: Fetch/XHR, Doc, JS, CSS, Img, Media, Font and
Other. Click a chip to filter (the chips show counts for the chosen server). The category comes from the
browser's `Sec-Fetch-Dest` header when it sends one, otherwise from the file extension; proxied API calls
are Fetch/XHR. Browsers also send `Sec-Fetch-Dest: empty` for preloads (e.g. `modulepreload` chunks), so plain
`.js`, `.css`, image, font and media files are always grouped by their type; `.json` and extensionless paths
requested that way stay Fetch/XHR. **Clear** removes the activity of the chosen server, or of all servers when "All servers" is selected.

### Request details

Click a request in Activity to open its details (Esc or × closes them): **Headers** (URL, status, time, size, request and
response headers), **Payload** (request body of proxied calls, JSON pretty-printed, forms decoded), **Preview**
(images rendered with their size, JSON and text, a sample line for fonts) and **Response** (raw body with Copy).

- Files served from your folder are read from disk when you open them, so nothing extra is kept in memory. If the
  proxy address was replaced in a file when it was served, the panel says so and shows the file on disk.
- For proxied calls the first 32 KB of the request and 128 KB of the response are kept (the rest is marked truncated).
  When kept bodies exceed 20 MB, the oldest requests lose their bodies (headers stay).
- Details are held in memory only: never written to disk, gone on Clear or quit. They are shown **unmasked**
  (`Authorization`, `Cookie`, request bodies such as passwords), as in browser dev tools.
- Not included yet: audio/video preview, a timing waterfall, WebSocket frames, HAR export.

## Dropping folders

While you drag a folder over the window the list dims and a landing pad appears ("Drop to start serving"). On drop
a burst of rings and sparks plays where you let go, the new card pops in, scrolls into view and glows green for a
couple of seconds (also when you drop a folder that is already listed, or open one via the Dock or `open -a`).
With Reduce Motion on, the dashes, ripples and sparks are replaced by a simple fade.

## Removing a folder

The trash button on a card opens a confirmation over the window: the folder's name, framework and path, then what
will happen (its server stops, its settings such as a custom name and proxy rules are forgotten) and a reminder that
the files in the folder are never deleted. Cancel (or Esc, or a click outside) keeps everything; Remove confirms.
