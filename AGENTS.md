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

### Additional CLI variants
- Build (alt): `cd MyMemento && xcodebuild -scheme MyMemento -configuration Debug`.
- UI tests only: `cd MyMemento && xcodebuild test -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyMementoUITests`.
- Unit tests only: `cd MyMemento && xcodebuild test -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyMementoTests`.

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

## Core Data Model Guidelines
When editing the Core Data model XML directly (`MyMemento/MyMemento/MyMemento.xcdatamodeld/.../contents`), follow these rules to avoid Xcode crashes and schema drift:

1. Model metadata: keep `model` attributes current (e.g., `lastSavedToolsVersion`, `systemVersion`, `sourceLanguage="Swift"`).
2. Attributes: use simple declarations; avoid unnecessary `optional`/scalar flags when defaults suffice.
   - Example: `<attribute name="body" attributeType="String"/>`
3. Inverse relationships: always specify BOTH `inverseName` and `inverseEntity` on each side of the many-to-many.
   - Note → Tags: `<relationship name="tags" toMany="YES" deletionRule="Nullify" destinationEntity="Tag" inverseName="notes" inverseEntity="Tag"/>`
   - Tag → Notes: `<relationship name="notes" toMany="YES" deletionRule="Nullify" destinationEntity="Note" inverseName="tags" inverseEntity="Note"/>`
4. Elements section: omit the `<elements>` positional block to reduce merge conflicts.
5. Critical: never set only `inverseName` without `inverseEntity` (this can cause Xcode crashes and validation errors).
6. After changes: clear derived data to rebuild model artifacts: `rm -rf ~/Library/Developer/Xcode/DerivedData`.

## Agent Conduct
- Do not reference the assistant in generated content unless explicitly asked.
- Avoid adding unrequested features; keep changes scoped to the request.
