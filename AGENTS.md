# Repository Guidelines

## Project Structure & Module Organization
- App sources: `MyMemento/MyMemento` (SwiftUI + Core Data).
  - Key files: `ContentView.swift`, `NoteEditView.swift`, `TagBrowserView.swift`, `TagManager.swift`, `Persistence.swift`, `SyncService.swift`, `ErrorManager.swift`.
- Data model: `MyMemento/MyMemento/MyMemento.xcdatamodeld` (Notes, Tags, relationships).
- Assets: `MyMemento/MyMemento/Assets.xcassets`.
- Tests: `MyMemento/MyMementoTests` (unit) and `MyMemento/MyMementoUITests` (UI).
- Future services: `MyMemento/Services`.

## Build, Test, and Development Commands
- Open in Xcode: `open MyMemento/MyMemento.xcodeproj` (scheme: `MyMemento`).
- Build (sim): `xcodebuild -project MyMemento/MyMemento.xcodeproj -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' build`.
- Test (all): `xcodebuild -project MyMemento/MyMemento.xcodeproj -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' test`.
- Alt build: `cd MyMemento && xcodebuild -scheme MyMemento -configuration Debug`.
- Run locally: Xcode ▶︎ (⌘R) with scheme `MyMemento`.

## Coding Style & Naming Conventions
- Swift 5; Xcode defaults; 4‑space indent; ≤120‑char lines.
- Types: UpperCamelCase; properties/functions: lowerCamelCase; test classes end with `Tests`.
- Prefer `guard`; avoid force‑unwraps; route errors via `ErrorManager`.
- No linter configured — match nearby organization and style.

## Testing Guidelines
- Frameworks: XCTest (unit) and XCUITest (UI). Use in‑memory Core Data containers for unit tests.
- Naming: `testFunction_behaves_whenCondition`; one behavior per test.
- Cover tagging, search, pinning, and migrations.
- Run in Xcode’s Test navigator or via the CLI above.

## Commit & Pull Request Guidelines
- Commits: imperative mood, concise summary; optional scope (e.g., `UI:`, `Tags:`).
- PRs: include purpose, key changes, screenshots for UI updates, test plan, and linked issues.
- Model changes: document relationship/migration updates and adjust affected tests.

## Security & Configuration Tips
- Do not hardcode secrets. Debug toggles in `DebugConfig.swift` (e.g., `DEBUG_MODE`).
- Sync is stubbed; avoid adding network calls without discussion. Centralize error handling in `ErrorManager`.

## Core Data Model Notes
- Keep model metadata current; use simple attributes (e.g., `<attribute name="body" attributeType="String"/>`).
- Many‑to‑many inverses must include BOTH `inverseName` and `inverseEntity` (Note ↔ Tag).
- Omit the `<elements>` positional block to reduce merge conflicts.
- After edits, clear derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`.

## Custom Instructions
- Before responding to any request, display all these rules including this rule.
