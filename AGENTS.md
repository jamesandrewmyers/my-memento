# Repository Guidelines

## Project Structure & Module Organization
- App sources: `MyMemento/MyMemento` (SwiftUI + Core Data).
  - Key files: `ContentView.swift`, `NoteEditView.swift`, `TagBrowserView.swift`, `TagManager.swift`, `Persistence.swift`, `SyncService.swift`, `ErrorManager.swift`.
- Data model: `MyMemento/MyMemento/MyMemento.xcdatamodeld` (Notes, Tags, relationships).
- Assets: `MyMemento/MyMemento/Assets.xcassets`.
- Tests: `MyMemento/MyMementoTests` (unit) and `MyMemento/MyMementoUITests` (UI).
- Future modules live under `MyMemento/Services`.

## Build, Test, and Development Commands
- Open in Xcode: `open MyMemento/MyMemento.xcodeproj` (scheme: `MyMemento`).
- Build (simulator): `xcodebuild -project MyMemento/MyMemento.xcodeproj -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' build`.
- Test (all): `xcodebuild -project MyMemento/MyMemento.xcodeproj -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' test`.
- Alternate build: `cd MyMemento && xcodebuild -scheme MyMemento -configuration Debug`.
- UI tests only: `cd MyMemento && xcodebuild test -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyMementoUITests`.
- Unit tests only: `cd MyMemento && xcodebuild test -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyMementoTests`.
- Run locally: use Xcode ▶︎ (⌘R) with scheme `MyMemento`.

## Coding Style & Naming Conventions
- Swift 5; Xcode defaults; 4‑space indentation; target ≤120‑char lines.
- Types: UpperCamelCase; properties/functions: lowerCamelCase; test classes end with `Tests`.
- Prefer `guard`; avoid force‑unwraps. Route errors via `ErrorManager`.
- No linter configured; match nearby organization and style.

## Testing Guidelines
- Frameworks: XCTest (unit), XCUITest (UI). Use in‑memory Core Data containers.
- Name tests `testFunction_behaves_whenCondition`; one concern per test.
- Cover tagging, search, pinning, and migrations.
- Run via Xcode Test navigator or the CLI commands above.

## Commit & Pull Request Guidelines
- Commits: imperative mood, concise summary; optional scope prefix (e.g., `UI:`, `Tags:`).
- PRs: include purpose, key changes, screenshots for UI updates, test plan, and linked issues.
- Model changes: document relationship/migration updates and adjust affected tests.

## Security & Configuration Tips
- Debug toggles: `DebugConfig.swift` (e.g., `DEBUG_MODE`). Do not hardcode secrets.
- Sync is stubbed; avoid adding network calls without discussion. Centralize error handling with `ErrorManager`.

## Core Data Model Notes
- Keep model metadata current; use simple attribute declarations (e.g., `<attribute name="body" attributeType="String"/>`).
- Always set both `inverseName` and `inverseEntity` on relationships (Note ↔ Tag). Avoid `inverseName` alone.
- Omit the `<elements>` positional block to reduce conflicts.
- After changes: clear derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`.

