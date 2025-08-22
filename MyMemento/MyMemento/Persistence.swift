//
//  Persistence.swift
//  MyMemento
//
//  Created by James Andrew Myers on 8/21/25.
//

import CoreData
import OSLog

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for i in 0..<10 {
            let newNote = Note(context: viewContext)
            newNote.id = UUID()
            newNote.title = "Sample Note \(i + 1)"
            newNote.body = "This is the body of sample note \(i + 1)"
            newNote.tags = "sample,note"
            newNote.createdAt = Date()
        }
        do {
            try viewContext.save()
        } catch {
            // Log preview data creation failure - this is non-critical for app functionality
            let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "Persistence")
            let nsError = error as NSError
            logger.error("Failed to save preview data: \(nsError.localizedDescription) - Code: \(nsError.code)")
            // Don't crash for preview data - the app can function without sample data
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MyMemento")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Log the critical Core Data store loading error
                let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "Persistence")
                logger.critical("Failed to load Core Data persistent store: \(error.localizedDescription) - Code: \(error.code), UserInfo: \(String(describing: error.userInfo))")
                
                /*
                 This is a critical error - the app cannot function without Core Data.
                 In a production app, you might want to:
                 * Show a user-friendly error message
                 * Try to recover by deleting and recreating the store
                 * Gracefully degrade functionality
                 
                 For now, we still need to terminate as the app cannot function without Core Data.
                 */
                fatalError("Core Data store failed to load: \(error.localizedDescription)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Create example notes in debug mode when storage is empty
        createExampleNotesIfNeeded()
    }
    
    /// Creates example notes when storage is empty and DEBUG_MODE is enabled
    private func createExampleNotesIfNeeded() {
        guard DEBUG_MODE else { return }
        
        let context = container.viewContext
        let request: NSFetchRequest<Note> = Note.fetchRequest()
        
        do {
            let existingNotesCount = try context.count(for: request)
            
            // Only create example notes if storage is completely empty
            guard existingNotesCount == 0 else { return }
            
            let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "Persistence")
            logger.info("DEBUG_MODE: Creating example notes for empty storage")
            
            // Create 3 example notes with different content
            let exampleNotes = [
                (title: "Welcome to MyMemento", 
                 body: "This is your personal note-taking app. You can create, edit, and organize your thoughts here. Use tags to categorize your notes and search to find them quickly.",
                 tags: "welcome,getting-started"),
                 
                (title: "Meeting Notes - Project Alpha", 
                 body: "Discussed the new features for Q4:\n• Implement user authentication\n• Add export functionality\n• Improve search capabilities\n\nNext meeting: Friday 2PM",
                 tags: "work,meetings,project-alpha"),
                 
                (title: "Book Ideas", 
                 body: "Random thoughts for the novel I want to write:\n\n- Character: A detective who can see memories\n- Setting: Near-future cyberpunk city\n- Plot twist: The memories aren't real\n\nNeed to research: Memory implantation technology",
                 tags: "creative,writing,ideas")
            ]
            
            for (index, noteData) in exampleNotes.enumerated() {
                let note = Note(context: context)
                note.id = UUID()
                note.title = noteData.title
                note.body = noteData.body
                note.tags = noteData.tags
                note.createdAt = Date().addingTimeInterval(-Double(index * 3600)) // Stagger creation times by 1 hour each
            }
            
            try context.save()
            logger.info("DEBUG_MODE: Successfully created \(exampleNotes.count) example notes")
            
        } catch {
            let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "Persistence")
            let nsError = error as NSError
            logger.error("DEBUG_MODE: Failed to create example notes: \(nsError.localizedDescription)")
        }
    }
}
