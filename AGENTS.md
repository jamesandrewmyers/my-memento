# Repository Guidelines

## Project Structure & Module Organization
- App sources: `MyMemento/MyMemento` (SwiftUI + Core Data). Key files: `ContentView.swift`, `NoteEditView.swift`, `TagBrowserView.swift`, `TagManager.swift`, `Persistence.swift`, `SyncService.swift`, `ErrorManager.swift`.
- Data model: `MyMemento/MyMemento/MyMemento.xcdatamodeld` (Notes, Tags, relationships).
- Assets: `MyMemento/MyMemento/Assets.xcassets`.
- Tests: `MyMemento/MyMementoTests` (unit) and `MyMemento/MyMementoUITests` (UI).
- Future modules: `MyMemento/Services`.

## Build, Test, and Development Commands
- Open in Xcode: `open MyMemento/MyMemento.xcodeproj` (scheme: `MyMemento`).
- Build (CLI): `xcodebuild -project MyMemento/MyMemento.xcodeproj -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' build`.
- Test (CLI): `xcodebuild -project MyMemento/MyMemento.xcodeproj -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' test`.
- Run locally: Xcode ▶︎ (⌘R) on an iOS Simulator with the `MyMemento` scheme.

## Coding Style & Naming Conventions
- Swift 5; Xcode defaults; 4‑space indentation; aim for ≤120‑char lines.
- Types: UpperCamelCase; properties/functions: lowerCamelCase; test classes end with `Tests`.
- Prefer `guard`, avoid force‑unwraps. Route errors via `ErrorManager`.
- No linter configured; match nearby file organization and style.

## Testing Guidelines
- Frameworks: XCTest (unit), XCUITest (UI).
- Naming: `testFunction_behaves_whenCondition`; one concern per test.
- Core Data: use in‑memory containers. Cover tagging, search, pinning, and migrations.
- Run via Xcode Test navigator or the CLI test command above.

## Commit & Pull Request Guidelines
- Commits: imperative mood, concise summary; optional scope (e.g., `UI:`, `Tags:`).
- PRs: include purpose, key changes, screenshots for UI changes, test plan, and linked issues.
- Model changes: document relationship/migration updates and adjust affected tests.

## Security & Configuration Tips
- Debug toggles: `DebugConfig.swift` (e.g., `DEBUG_MODE`). Do not hardcode secrets.
- Sync is stubbed; avoid adding network calls without discussion. Centralize error handling with `ErrorManager`.

