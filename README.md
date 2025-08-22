# MyMemento

An **offline-first personal knowledge vault** built for iOS.  
MyMemento helps you capture, organize, and revisit your thoughts — even without an internet connection.

---

## 🚀 MVP Scope

This project is focused on delivering a minimal but fully usable note-taking experience:

- **Note creation & editing** – write, update, and delete text notes.  
- **Local offline storage** – Core Data persistence so notes remain available without network access.  
- **Basic search** – find notes by keyword in titles or bodies.  
- **Tagging / categorization** – add and remove simple tags for organization.  
- **Lightweight UI** – SwiftUI views for listing, creating, editing, and searching notes.  
- **Sync placeholder** – stubbed methods for future cloud sync (not yet implemented).  

---

## 🛠 Tech Stack

- **SwiftUI** – modern declarative UI for iOS.  
- **Core Data** – local persistence layer for offline-first storage.  
- **Xcode 15+** – project setup and builds.  

---

## 📂 Project Structure

- `Models/` – Core Data entities and supporting data structures.  
- `Views/` – SwiftUI screens for notes, search, and editing.  
- `ViewModels/` – state management and Core Data CRUD.  
- `Services/SyncService.swift` – placeholder for future sync integration.  

---

## 🏗 Getting Started

1. Clone the repository  
   ```bash
   git clone https://github.com/your-org/MyMemento.git
   cd MyMemento