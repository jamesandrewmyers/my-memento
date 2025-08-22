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
    }
}
