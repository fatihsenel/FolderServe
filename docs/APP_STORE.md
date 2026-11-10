# Mac App Store: setup and listing

The App Store build is the normal source compiled with `-D APPSTORE` (no update checker: guideline 2.4.5). Build and export it
with `scripts/appstore.sh`. The Homebrew / GitHub build is unchanged (`scripts/release.sh`).

## One-time setup (Account Holder, team `XC7ZHWDHCA`)

1. App Store Connect ▸ Apps ▸ **+** ▸ New App: platform macOS, name `FolderServe`, bundle ID `com.fatihsenel.FolderServe`, SKU `folderserve`.
2. Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ **+**: `Apple Distribution` and `Mac Installer Distribution`.
3. Publish `docs/PRIVACY.md` at a public URL (the GitHub link below works) and use it as the Privacy Policy URL.
4. Run `scripts/appstore.sh --upload` (or without `--upload`, then open the `.pkg` in Transporter). Each upload needs a new `CURRENT_PROJECT_VERSION` in `project.yml`.
5. In App Store Connect fill in the listing below, pick the build, set the price (free), age rating and territories, and press **Submit for Review**.

Privacy URL: https://github.com/fatihsenel/FolderServe/blob/main/docs/PRIVACY.md
Support URL: https://github.com/fatihsenel/FolderServe/issues
App Privacy answers: **Data Not Collected**. Export compliance: standard encryption only (Apple's TLS for the HTTPS option), exempt.

## Listing text

**Name:** FolderServe
**Subtitle (30):** Local server for your folders
**Category:** Developer Tools (secondary: Utilities)
**Keywords (100):** localhost,web server,live reload,http,https,proxy,mock,api,frontend,static,preview,dev server,cors

**Promotional text (170):** Drop a folder, get a localhost address. See every request, mock any response and test on your phone, all from a native Mac app that lives in your menu bar.

**Description:**
FolderServe serves any folder on your Mac over HTTP, so you can open a site you are building without setting up a server.

• Drop a folder and it is served at once on localhost, on a free port
• Live reload: the page refreshes when a file changes, and stylesheet edits apply without a reload
• Activity: every request with headers, bodies, timing and a JSON tree, like browser dev tools. Replay or edit and replay a request
• API proxy: forward /api-style requests to another server, with no CORS errors
• Mock any response for a path, and slow every answer down to test loading states
• HTTPS, CORS and single-page-app mode with a switch each
• Share on your network and scan a QR code to test on a phone
• Page console: see a page's console messages and errors in the app
• Menu bar companion with recent folders and a badge when requests fail
• Right-click a folder in Finder ▸ Services ▸ Serve with FolderServe

Private by design: servers listen on 127.0.0.1 unless you switch Share on, request data is held in memory only, and nothing is sent anywhere. Free and open source.

**What's new (first version):** First release on the Mac App Store.

## Review notes (paste into "App Review Information ▸ Notes")

FolderServe is a developer tool that serves a folder the user chooses over HTTP so they can preview a website.
To try it: click **Add Folder…** (or drop any folder with an index.html) and click the address shown on the card. Activity lists the request.

- **Network:** the app listens on 127.0.0.1 only. It listens on the local network only if the user turns on **Share** for a folder (off by default; a warning icon is shown).
- **App Transport Security:** the optional API proxy forwards to a URL the user types, often `http://localhost:…`, so `NSAllowsArbitraryLoads` is set. The app itself makes no other network requests.
- **File access:** sandboxed; only folders the user drops or picks (read-only security-scoped bookmarks). The read-write entitlement exists only so Activity ▸ Export can save a HAR file where the user chooses.
- **No account or sign-in is needed.**

## Screenshots

macOS accepts 1280×800, 1440×900, 2560×1600 or 2880×1800. Use real captures of the Servers, Activity and request detail screens (see README screenshots for the content).
