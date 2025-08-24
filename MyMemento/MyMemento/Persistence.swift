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
        
        // Create sample tags
        let sampleTag = Tag(context: viewContext)
        sampleTag.id = UUID()
        sampleTag.name = "sample"
        sampleTag.createdAt = Date()
        
        let noteTag = Tag(context: viewContext)
        noteTag.id = UUID()
        noteTag.name = "note"
        noteTag.createdAt = Date()
        
        for i in 0..<10 {
            let newNote = Note(context: viewContext)
            newNote.id = UUID()
            newNote.title = "Sample Note \(i + 1)"
            newNote.richText = NSAttributedString(string: "This is the body of sample note \(i + 1)")
            newNote.createdAt = Date()
            newNote.addToTags(sampleTag)
            newNote.addToTags(noteTag)
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
        
        // Enable automatic lightweight migration
        container.persistentStoreDescriptions.forEach { storeDescription in
            storeDescription.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            storeDescription.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "Persistence")
                logger.critical("Failed to load Core Data persistent store: \(error.localizedDescription) - Code: \(error.code), UserInfo: \(String(describing: error.userInfo))")
                
                // Attempt to recover by deleting and recreating the store
                logger.info("Attempting to recover by deleting and recreating the Core Data store")
                
                if let storeURL = storeDescription.url {
                    // Remove the existing store files
                    let fileManager = FileManager.default
                    let walURL = storeURL.appendingPathExtension("sqlite-wal")
                    let shmURL = storeURL.appendingPathExtension("sqlite-shm")
                    
                    try? fileManager.removeItem(at: storeURL)
                    try? fileManager.removeItem(at: walURL)
                    try? fileManager.removeItem(at: shmURL)
                    
                    logger.info("Deleted corrupted store files - app will restart with fresh store")
                    
                    // For now, just crash to force app restart with clean state
                    fatalError("Core Data store was corrupted and has been reset. Please restart the app.")
                } else {
                    fatalError("Core Data store failed to load and no URL available for recovery: \(error.localizedDescription)")
                }
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
            
            // Create example tags first
            let welcomeTag = Tag(context: context)
            welcomeTag.id = UUID()
            welcomeTag.name = "welcome"
            welcomeTag.createdAt = Date()
            
            let gettingStartedTag = Tag(context: context)
            gettingStartedTag.id = UUID()
            gettingStartedTag.name = "getting-started"
            gettingStartedTag.createdAt = Date()
            
            let workTag = Tag(context: context)
            workTag.id = UUID()
            workTag.name = "work"
            workTag.createdAt = Date()
            
            let meetingsTag = Tag(context: context)
            meetingsTag.id = UUID()
            meetingsTag.name = "meetings"
            meetingsTag.createdAt = Date()
            
            let projectAlphaTag = Tag(context: context)
            projectAlphaTag.id = UUID()
            projectAlphaTag.name = "project-alpha"
            projectAlphaTag.createdAt = Date()
            
            let creativeTag = Tag(context: context)
            creativeTag.id = UUID()
            creativeTag.name = "creative"
            creativeTag.createdAt = Date()
            
            let writingTag = Tag(context: context)
            writingTag.id = UUID()
            writingTag.name = "writing"
            writingTag.createdAt = Date()
            
            let ideasTag = Tag(context: context)
            ideasTag.id = UUID()
            ideasTag.name = "ideas"
            ideasTag.createdAt = Date()
            
            // Create 3 example notes with different content
            let exampleNotes = [
                (title: "Welcome to MyMemento", 
                 body: "This is your personal note-taking app. You can create, edit, and organize your thoughts here. Use tags to categorize your notes and search to find them quickly.",
                 tags: [welcomeTag, gettingStartedTag]),
                 
                (title: "Meeting Notes - Project Alpha", 
                 body: "Discussed the new features for Q4:\n• Implement user authentication\n• Add export functionality\n• Improve search capabilities\n\nNext meeting: Friday 2PM",
                 tags: [workTag, meetingsTag, projectAlphaTag]),
                 
                (title: "Book Ideas", 
                 body: "Random thoughts for the novel I want to write:\n\n- Character: A detective who can see memories\n- Setting: Near-future cyberpunk city\n- Plot twist: The memories aren't real\n\nNeed to research: Memory implantation technology",
                 tags: [creativeTag, writingTag, ideasTag])
            ]
            
            for (index, noteData) in exampleNotes.enumerated() {
                let note = Note(context: context)
                note.id = UUID()
                note.title = noteData.title
                note.richText = NSAttributedString(string: noteData.body)
                note.createdAt = Date().addingTimeInterval(-Double(index * 3600)) // Stagger creation times by 1 hour each
                note.isPinned = (index == 0) // Pin the first note (Welcome) as an example
                
                // Add tags to the note
                for tag in noteData.tags {
                    note.addToTags(tag)
                }
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
