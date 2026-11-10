# FolderServe privacy policy

FolderServe does not collect, store or send any personal data to its author or to anyone else.

- **No accounts, no analytics, no tracking.** The app contains no analytics or advertising code.
- **Your folders stay on your Mac.** FolderServe only reads folders you drop on it or pick, and it never writes into them.
  It serves them on `127.0.0.1` (this Mac only), or on your local network while you have switched **Share** on for that folder.
- **The request log is memory only.** The Activity list, request and response bodies, headers and the page console are held in
  memory while the app runs and are never written to disk. Quitting the app clears them.
- **What is saved on your Mac:** the list of served folders and their settings (name, port, options, proxy rules and the
  mock responses you create), recent folders, and your preferences. This stays in the app's own container and is not shared.
- **The API proxy** forwards requests only to the addresses you configure, from your Mac, as you would from your browser.
- **Updates:** the Mac App Store version makes no network requests of its own. (The version downloaded from GitHub asks GitHub once
  a day whether a newer release exists and sends nothing about you or your folders.)

Questions: open an issue at <https://github.com/fatihsenel/FolderServe/issues>.

Last updated: 2026-11-10
