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

## Core Data Model Guidelines

### Adding Inverse Relationships to Core Data Model

When manually editing the Core Data model XML file (`MyMemento.xcdatamodeld/MyMemento.xcdatamodel/contents`) to add inverse relationships, follow this exact process:

1. **Update model metadata** to current tool versions:
   ```xml
   <model type="com.apple.IDECoreDataModeler.DataModel" 
          documentVersion="1.0" 
          lastSavedToolsVersion="23788.4" 
          systemVersion="24G84" 
          minimumToolsVersion="Automatic" 
          sourceLanguage="Swift" 
          userDefinedModelVersionIdentifier="">
   ```

2. **Simplify attribute declarations** by removing unnecessary optional/scalar specifications:
   ```xml
   <!-- WRONG (overly complex) -->
   <attribute name="body" optional="NO" attributeType="String"/>
   <attribute name="createdAt" optional="NO" attributeType="Date" usesScalarValueType="NO"/>
   
   <!-- CORRECT (simplified) -->
   <attribute name="body" attributeType="String"/>
   <attribute name="createdAt" attributeType="Date" usesScalarValueType="NO"/>
   ```

3. **Add complete inverse relationship specifications** with BOTH required attributes:
   ```xml
   <!-- Note entity relationship -->
   <relationship name="tags" optional="YES" toMany="YES" deletionRule="Nullify" 
                destinationEntity="Tag" inverseName="notes" inverseEntity="Tag"/>
   
   <!-- Tag entity relationship -->
   <relationship name="notes" optional="YES" toMany="YES" deletionRule="Nullify" 
                destinationEntity="Note" inverseName="tags" inverseEntity="Note"/>
   ```

4. **Remove `<elements>` positioning section** entirely to avoid conflicts.

5. **Critical**: NEVER add only `inverseName` without `inverseEntity` - this will cause Xcode crashes with "relationship's inverse must be both named and charged to an entity" errors.

6. **Clear derived data** after model changes: `rm -rf ~/Library/Developer/Xcode/DerivedData`

## Development Guidelines

I give you permission to run any and all docker commands you see fit.
I give you permission to run any and all gh commands you see fit.
I give you permission to make all filesystem changes except removal.
I give you permission to make any and all git commands except removal. 
Never include references to this assistant in any content generated unless explicitly asked to do so.
Do not add unrequested features to code unless expressly required by other requested features.
