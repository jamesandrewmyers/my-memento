# MyMemento

An **offline-first personal knowledge vault** built for iOS.  
MyMemento helps you capture, organize, and revisit your thoughts — even without an internet connection.

---

## 🌟 Features

### Note Types
- **Text Notes** – Rich text editing with formatting support (bold, italic, underline, strikethrough, headings, lists, links)
- **Checklist Notes** – Interactive task lists with checkable items, inline editing, and reordering

### Organization & Discovery
- **Tags** – Multi-tag support for categorizing notes with many-to-many relationships
- **Search** – Full-text search across note titles and content with encrypted index
- **Pinning** – Pin important notes to keep them at the top
- **Sorting** – Sort by creation date, modification date, or title

### Rich Attachments
- **Video** – Attach videos from library or record new ones, with thumbnail generation
- **Audio** – Record voice memos and attach audio files to notes
- **Locations** – Attach GPS locations with coordinates, placemark data, and map visualization

### Privacy & Security
- **End-to-End Encryption** – All note content encrypted at rest using AES encryption
- **Encrypted Storage** – Attachments and sensitive data stored with encryption
- **Local Key Management** – Encryption keys managed securely on device
- **Private by Default** – No cloud dependency, all data stays local

### Data Portability
- **Export** – Export all notes as encrypted ZIP archives with public key encryption
- **Import** – Import encrypted note archives with private key decryption
- **Share** – Share individual notes as HTML, encrypted files, or plain text
- **Backup** – Full backup and restore capability for all notes and attachments

### Offline-First Architecture
- **Core Data Persistence** – Local SQLite database for reliable offline storage
- **No Network Dependency** – Fully functional without internet connection
- **Fast & Responsive** – All operations happen locally for instant performance

---

## 🛠 Tech Stack

- **SwiftUI** – Modern declarative UI framework for iOS
- **Core Data** – Local persistence layer with entity inheritance
- **CryptoKit** – Native encryption for data protection
- **MapKit** – Location services and map visualization
- **AVFoundation** – Audio/video recording and playback
- **Xcode 15+** – Development environment
- **iOS 15.0+** – Minimum deployment target

---

## 📂 Project Structure

```
MyMemento/
├── MyMemento/                      # Main app source code
│   ├── MyMementoApp.swift         # App entry point
│   ├── ContentView.swift          # Main notes list view
│   ├── NoteEditView.swift         # Note editing interface
│   ├── Persistence.swift          # Core Data stack management
│   ├── CryptoHelper.swift         # Encryption utilities
│   ├── KeyManager.swift           # Secure key management
│   ├── TagManager.swift           # Tag operations
│   ├── AttachmentManager.swift    # Attachment handling
│   ├── LocationManager.swift      # GPS and location services
│   ├── ExportManager.swift        # Import/export functionality
│   ├── NoteIndexViewModel.swift   # Search index management
│   ├── RichTextEditorView.swift   # Rich text editing
│   ├── TagBrowserView.swift       # Tag browsing interface
│   ├── LocationPickerView.swift   # Location selection
│   ├── SettingsView.swift         # App settings
│   └── MyMemento.xcdatamodeld/    # Core Data model
├── MyMementoTests/                # Unit tests
└── MyMementoUITests/              # UI tests
```

---

## 📊 Core Data Model

### Entities

**Note** (abstract parent entity)
- `id` (UUID) – Unique identifier
- `title` (String) – Note title
- `encryptedData` (Binary) – Encrypted note content
- `createdAt` (Date) – Creation timestamp
- `isPinned` (Boolean) – Pin status
- Relationships: `tags` (many-to-many), `attachments` (one-to-many)

**TextNote** (inherits from Note)
- `body` (String) – Plain text content
- `richText` (NSAttributedString) – Formatted text with styling

**ChecklistNote** (inherits from Note)
- `items` (NSArray) – Array of checklist items with text and completion status

**Tag**
- `id` (UUID) – Unique identifier
- `name` (String) – Tag name
- `createdAt` (Date) – Creation timestamp
- Relationship: `notes` (many-to-many)

**Attachment**
- `id` (UUID) – Unique identifier
- `type` (String) – Attachment type (video, audio, location)
- `relativePath` (String) – Path to encrypted file
- `createdAt` (Date) – Creation timestamp
- Relationships: `note` (many-to-one), `location` (many-to-one)

**Location**
- `id` (UUID) – Unique identifier
- `name` (String) – Location name
- `latitude` / `longitude` (Double) – GPS coordinates
- `altitude` (Double) – Elevation
- `horizontalAccuracy` / `verticalAccuracy` (Double) – Accuracy metrics
- `encryptedPlacemarkData` (Binary) – Encrypted address/placemark info
- `createdAt` (Date) – Creation timestamp
- Relationship: `attachments` (one-to-many)

**SearchIndex**
- `id` (UUID) – Unique identifier
- `encryptedIndexData` (Binary) – Encrypted search index for fast lookups

---

## 🏗 Getting Started

### Prerequisites
- macOS 14.0+ (Sonoma or later)
- Xcode 15.0+
- iOS 15.0+ device or simulator

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/my-memento.git
   cd my-memento
   ```

2. **Open in Xcode**
   ```bash
   open MyMemento/MyMemento.xcodeproj
   ```

3. **Build and run**
   - Select your target device/simulator
   - Press `Cmd + R` to build and run

### Building from Command Line

```bash
# Build the project
cd MyMemento && xcodebuild -scheme MyMemento -configuration Debug

# Run tests
cd MyMemento && xcodebuild test -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15'

# Run UI tests specifically
cd MyMemento && xcodebuild test -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyMementoUITests

# Run unit tests specifically  
cd MyMemento && xcodebuild test -scheme MyMemento -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MyMementoTests

# Clean derived data (if needed after model changes)
rm -rf ~/Library/Developer/Xcode/DerivedData
```

---

## 🎯 Usage

### Creating Notes
1. Tap the **+** button in the toolbar
2. Select **Text Note** or **Checklist**
3. Enter a title (required)
4. Add content, tags, and attachments
5. Save automatically on navigation

### Managing Tags
- Add tags in note editor using comma-separated format
- Browse all tags via Tags button in main view
- Filter notes by selecting tags
- Tags are created automatically when first used

### Adding Attachments
- **Video**: Tap attachment button → select from library or record new
- **Audio**: Tap microphone icon → record voice memo
- **Location**: Tap location icon → select from saved locations or current GPS

### Searching Notes
- Use search bar at top of main view
- Search matches note titles and content
- Results update in real-time as you type

### Exporting & Importing
- **Export All**: Export all notes as encrypted ZIP file
- **Import**: Import encrypted archive with decryption
- **Share Single Note**: Export individual note as HTML or encrypted file

---

## 🔒 Security Model

MyMemento uses a multi-layer encryption approach:

1. **Note Content**: Encrypted with AES before storage
2. **Attachments**: Video and audio files encrypted on disk
3. **Search Index**: Encrypted to protect content while enabling search
4. **Location Data**: Placemark information encrypted
5. **Export Archives**: Public key encryption for sharing

All encryption keys are managed locally on device using iOS Keychain.

---

## 🧪 Development

### Code Style
- SwiftUI declarative patterns
- MVVM-inspired architecture
- Core Data for persistence layer
- Coordinator pattern for rich text editing

### Testing
- Unit tests in `MyMementoTests/`
- UI tests in `MyMementoUITests/`
- Run with `Cmd + U` or command line

### Contributing
This is a personal project, but feedback and suggestions are welcome via issues.

---

## 📄 License

See [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

Built with SwiftUI and Core Data, leveraging Apple's native frameworks for a privacy-focused, offline-first note-taking experience.
