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
- Not supported: WebSockets, chunked request bodies, HTTP/2 to the browser.
- The app allows plain-http targets (`NSAllowsArbitraryLoads`), because the target is whatever you configure.
