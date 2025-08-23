# CLAUDE.md

This file provides guidance to you when working with code in this repository.

## Project Architecture

MyMemento is an offline-first iOS note-taking app built with SwiftUI and Core Data:

- **Core Data Model**: `Note` entity with id (UUID), title, body, createdAt (Date), isPinned (Bool), and many-to-many relationship to `Tag` entity. `Tag` entity with id (UUID), name, and createdAt (Date)
- **SwiftUI Views**: 
  - `ContentView`: Main notes list with add/delete functionality
  - `NoteEditView`: Individual note editing interface
- **Persistence**: `PersistenceController` manages Core Data stack with shared instance and preview data
- **App Structure**: Standard iOS app with `MyMementoApp.swift` as entry point

## Development Commands

### Building and Running
```bash
# Build the project
cd MyMemento && xcodebuild -scheme MyMemento -configuration Debug

# Run tests
cd MyMemento && xcodebuild test -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15'

# Run UI tests specifically
cd MyMemento && xcodebuild test -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyMementoUITests

# Run unit tests specifically  
cd MyMemento && xcodebuild test -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyMementoTests
```

### Project Structure
- `MyMemento/MyMemento/` - Main app source code
- `MyMemento/MyMementoTests/` - Unit tests
- `MyMemento/MyMementoUITests/` - UI tests
- Core Data model: `MyMemento.xcdatamodeld`

## Development Guidelines

I give you permission to run any and all docker commands you see fit.
I give you permission to run any and all gh commands you see fit.
I give you permission to make all filesystem changes except removal.
I give you permission to make any and all git commands except removal. 
Never include references to this assistant in any content generated unless explicitly asked to do so.
Do not add unrequested features to code unless expressly required by other requested features.
