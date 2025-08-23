//
//  TagManager.swift
//  MyMemento
//
//  Created by Claude on 8/23/25.
//

import CoreData
import OSLog

/// Utility class for managing tag lifecycle and cleanup operations
struct TagManager {
    
    /// Removes orphaned tags that have no associated notes
    /// - Parameters:
    ///   - tags: Array of tags to check for orphaned status
    ///   - context: The managed object context to use for operations
    /// - Throws: Core Data errors if deletion or save operations fail
    static func cleanupOrphanedTags(_ tags: [Tag], in context: NSManagedObjectContext) throws {
        let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "TagManager")
        var deletedCount = 0
        
        for tag in tags {
            // Check if tag has any associated notes
            let noteCount = (tag.notes as? Set<Note>)?.count ?? 0
            
            if noteCount == 0 {
                logger.info("Deleting orphaned tag: \(tag.name ?? "Unknown")")
                context.delete(tag)
                deletedCount += 1
            }
        }
        
        if deletedCount > 0 {
            try context.save()
            logger.info("Cleaned up \(deletedCount) orphaned tag\(deletedCount == 1 ? "" : "s")")
        }
    }
    
    /// Removes orphaned tags for a specific tag if it has no associated notes
    /// - Parameters:
    ///   - tag: The tag to check and potentially delete
    ///   - context: The managed object context to use for operations
    /// - Throws: Core Data errors if deletion or save operations fail
    static func cleanupOrphanedTag(_ tag: Tag, in context: NSManagedObjectContext) throws {
        try cleanupOrphanedTags([tag], in: context)
    }
    
    /// Handles tag cleanup when a tag is removed from a note
    /// - Parameters:
    ///   - tag: The tag that was removed from a note
    ///   - context: The managed object context to use for operations
    static func handleTagRemovedFromNote(_ tag: Tag, in context: NSManagedObjectContext) {
        do {
            try cleanupOrphanedTag(tag, in: context)
        } catch {
            let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "TagManager")
            let nsError = error as NSError
            logger.error("Failed to cleanup orphaned tag: \(nsError.localizedDescription)")
        }
    }
    
    /// Handles tag cleanup when a note is deleted
    /// - Parameters:
    ///   - note: The note that is being deleted
    ///   - context: The managed object context to use for operations
    static func handleNoteDeleted(_ note: Note, in context: NSManagedObjectContext) {
        guard let associatedTags = note.tags as? Set<Tag> else { return }
        
        do {
            try cleanupOrphanedTags(Array(associatedTags), in: context)
        } catch {
            let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "TagManager")
            let nsError = error as NSError
            logger.error("Failed to cleanup orphaned tags after note deletion: \(nsError.localizedDescription)")
        }
    }
}