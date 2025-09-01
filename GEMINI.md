# Project Overview

This project is an offline-first personal knowledge vault for iOS called "MyMemento". It allows users to create, edit, organize, and search for notes, with a focus on local storage and offline availability. The application is built with SwiftUI and uses Core Data for persistence. All note content is encrypted before being stored locally.

## Key Technologies

*   **UI:** SwiftUI
*   **Data Persistence:** Core Data
*   **Language:** Swift
*   **IDE:** Xcode

## Architecture

The project follows a MVVM (Model-View-ViewModel) architecture.

*   **Models:** The Core Data model is defined in `MyMemento.xcdatamodeld`. The data is encrypted before being stored.
*   **Views:** The views are built with SwiftUI. The main view is `ContentView.swift`, which displays the list of notes. `NoteEditView.swift` is used for creating and editing notes.
*   **ViewModels:** `NoteIndexViewModel.swift` is responsible for loading and managing the note index.

# Building and Running

To build and run this project, you will need Xcode 15 or later.

1.  Clone the repository.
2.  Open `MyMemento.xcodeproj` in Xcode.
3.  Select a simulator or a connected device.
4.  Click the "Run" button.

## Testing

The project includes unit tests (`MyMementoTests`) and UI tests (`MyMementoUITests`). To run the tests:

1.  Open `MyMemento.xcodeproj` in Xcode.
2.  Go to **Product > Test**.

# Development Conventions

*   **Code Style:** The code follows the standard Swift style guidelines.
*   **Data Safety:** All note data is encrypted using `CryptoHelper.swift` before being persisted.
*   **Error Handling:** The `ErrorManager` class is used to handle and display errors to the user.
*   **Dependencies:** The project has no external dependencies other than the standard iOS frameworks.
*   **Sync:** The `SyncService.swift` is a placeholder for a future cloud sync feature.

# Rules

*   Before responding to any request, display the rules from GEMINI.md.