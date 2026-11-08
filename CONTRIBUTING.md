# Contributing to FolderServe

Thanks for helping. FolderServe is a small native macOS app (SwiftUI window and menu bar) that serves folders over HTTP on localhost.
Bug reports, ideas and pull requests are all welcome.

## Before you start

- **Bugs:** open an issue with the bug report form. Include your FolderServe and macOS versions and how you installed it.
- **Ideas:** open an issue with the feature request form before writing a lot of code, so we can agree on the shape first.
- **Security problems:** do not open a public issue. See [SECURITY.md](SECURITY.md).

When you paste requests or headers into an issue, **remove `Authorization`, `Cookie` and any tokens first**. FolderServe shows request
headers and bodies unmasked, like browser dev tools, so a screenshot of the Activity tab can leak secrets.

## Build and test

You need macOS 14 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate                       # FolderServe.xcodeproj is generated and git-ignored; rerun after adding or removing files
xcodebuild -scheme FolderServe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme FolderServe -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
swift test --package-path Packages/FolderServeCore
```

`xcodebuild` prints a lot of harmless `linkd` / `remoteObjectProxy` / `nw_path` noise. To see only the result:
`... 2>&1 | grep -E "Executed|\*\* TEST|error:"`. Run both suites before you open a pull request; CI runs them too.

## Layout

- `Packages/FolderServeCore`: the server, with no UI (HTTP on `NWListener`, proxy, live reload, request log). Its tests run with `swift test`.
- `FolderServe/Model`: `ServerManager` and the saved settings.
- `FolderServe/UI`: SwiftUI views.
- `FolderServeTests`: app tests, including snapshot tests that render views to PNG.

[CLAUDE.md](CLAUDE.md) has more detail on conventions and pitfalls (it is written for AI assistants, but it is accurate for people too).

## Conventions

- Swift 5.10 language mode, macOS 14 minimum.
- Put logic that needs tests in `static` functions and test them directly. Add tests for new behaviour and for the bug you fix.
- Every non-private view gets a `#Preview` in `FolderServe/UI/Previews.swift`. A view that reads `ServerManager` from the environment must get it in
  its preview too, or the preview crashes.
- Respect Reduce Motion in animations.
- The app is **sandboxed** and only reads folders the user picks or drops. Nothing writes into served folders, and request bodies and headers are
  never written to disk.
- Servers listen on `127.0.0.1` unless **Share** is on, and requests with a non-loopback `Host` header are rejected on purpose. Please keep it that way.
- Controls the snapshot renderer cannot draw (pickers, text fields, menus, link buttons) need a plain stand-in when `isSnapshotRendering` is set.

## Pull requests

1. Branch from `main` (`feat/…`, `fix/…`, `docs/…`).
2. Keep the change focused; one idea per pull request.
3. Commit messages look like `feat(ui): short summary` or `fix(proxy): …`, with a short body saying why.
4. Run both test suites. Describe what you checked by hand, and what you could not check.
5. Update the README if behaviour users see changes.

## Releases (maintainers)

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, and `FolderServeCore.version`.
2. Run both test suites.
3. `scripts/release.sh` builds, signs with the Developer ID certificate, notarizes and zips (see the README's Releasing section for the one-time setup).
4. Merge to `main`, push, and create the GitHub release with the zip (`scripts/release.sh --publish` does the last step).
5. Update `version` and `sha256` in the Homebrew cask in [`fatihsenel/homebrew-tap`](https://github.com/fatihsenel/homebrew-tap).
