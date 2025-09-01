//
//  Persistence.swift
//  MyMemento
//
//  Created by James Andrew Myers on 8/21/25.
//

import CoreData
import OSLog
import UIKit

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        do {
            // Get encryption key for preview data
            let encryptionKey = try KeyManager.shared.getEncryptionKey()
            
            // Create 3 preview notes with encrypted storage
            for i in 0..<3 {
                let note = Note(context: viewContext)
                note.id = UUID()
                
                let now = Date().addingTimeInterval(-Double(i * 1800)) // Stagger by 30 minutes
                
                // Create attributed string for the note body
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.label
                ]
                let attributedBody = NSAttributedString(
                    string: "This is the body content of preview note \(i + 1)", 
                    attributes: attributes
                )
                
                // Build NotePayload
                let notePayload = NotePayload(
                    title: "Preview Note \(i + 1)",
                    body: NSAttributedStringWrapper(attributedBody),
                    tags: ["preview", "sample"],
                    createdAt: now,
                    updatedAt: now,
                    pinned: i == 0
                )
                
                // Encrypt and store NotePayload
                let encryptedNoteData = try CryptoHelper.encrypt(notePayload, key: encryptionKey)
                note.encryptedData = encryptedNoteData
                
                // Build IndexPayload for search
                let indexPayload = IndexPayload(
                    id: note.id!,
                    title: "Preview Note \(i + 1)",
                    tags: ["preview", "sample"],
                    summary: "This is the body content of preview note \(i + 1)",
                    createdAt: now,
                    updatedAt: now,
                    pinned: i == 0
                )
                
                // Create SearchIndex entity
                let searchIndex = SearchIndex(context: viewContext)
                searchIndex.id = note.id!
                
                // Encrypt and store IndexPayload
                let encryptedIndexData = try CryptoHelper.encrypt(indexPayload, key: encryptionKey)
                searchIndex.encryptedIndexData = encryptedIndexData
            }
            
            try viewContext.save()
        } catch {
            // Log preview data creation failure - this is non-critical for app functionality
            let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "Persistence")
            let nsError = error as NSError
            logger.error("Failed to save encrypted preview data: \(nsError.localizedDescription) - Code: \(nsError.code)")
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
            logger.info("DEBUG_MODE: Creating example notes for empty storage using encrypted format")
            
            // Get encryption key
            let encryptionKey = try KeyManager.shared.getEncryptionKey()
            
            // Create 3 example notes with different content
            let exampleNotes = [
                (title: "Welcome to MyMemento", 
                 body: "This is your personal note-taking app. You can create, edit, and organize your thoughts here. Use tags to categorize your notes and search to find them quickly.",
                 tags: ["welcome", "getting-started"],
                 pinned: true),
                 
                (title: "Meeting Notes - Project Alpha", 
                 body: "Discussed the new features for Q4:\n• Implement user authentication\n• Add export functionality\n• Improve search capabilities\n\nNext meeting: Friday 2PM",
                 tags: ["work", "meetings", "project-alpha"],
                 pinned: false),
                 
                (title: "Book Ideas", 
                 body: "Random thoughts for the novel I want to write:\n\n- Character: A detective who can see memories\n- Setting: Near-future cyberpunk city\n- Plot twist: The memories aren't real\n\nNeed to research: Memory implantation technology",
                 tags: ["creative", "writing", "ideas"],
                 pinned: false)
            ]
            
            for (index, noteData) in exampleNotes.enumerated() {
                let note = Note(context: context)
                note.id = UUID()
                
                let now = Date().addingTimeInterval(-Double(index * 3600)) // Stagger creation times by 1 hour each
                
                // Create NSAttributedString with basic formatting
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.label
                ]
                let attributedBody = NSAttributedString(string: noteData.body, attributes: attributes)
                
                // Build NotePayload
                let notePayload = NotePayload(
                    title: noteData.title,
                    body: NSAttributedStringWrapper(attributedBody),
                    tags: noteData.tags,
                    createdAt: now,
                    updatedAt: now,
                    pinned: noteData.pinned
                )
                
                // Encrypt and store NotePayload
                let encryptedNoteData = try CryptoHelper.encrypt(notePayload, key: encryptionKey)
                note.encryptedData = encryptedNoteData
                
                // Build IndexPayload for search
                let summary = noteData.body.prefix(100).trimmingCharacters(in: .whitespacesAndNewlines)
                let indexPayload = IndexPayload(
                    id: note.id!,
                    title: noteData.title,
                    tags: noteData.tags,
                    summary: String(summary),
                    createdAt: now,
                    updatedAt: now,
                    pinned: noteData.pinned
                )
                
                // Create SearchIndex entity
                let searchIndex = SearchIndex(context: context)
                searchIndex.id = note.id!
                
                // Encrypt and store IndexPayload
                let encryptedIndexData = try CryptoHelper.encrypt(indexPayload, key: encryptionKey)
                searchIndex.encryptedIndexData = encryptedIndexData
            }
            
            try context.save()
            logger.info("DEBUG_MODE: Successfully created \(exampleNotes.count) encrypted example notes")
            
        } catch {
            let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "Persistence")
            let nsError = error as NSError
            logger.error("DEBUG_MODE: Failed to create encrypted example notes: \(nsError.localizedDescription)")
        }
    }
}
