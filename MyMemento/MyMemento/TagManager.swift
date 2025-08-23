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
    
    /// Merges a source tag into a target tag by moving all note relationships
    /// - Parameters:
    ///   - sourceTag: The tag to be merged and removed
    ///   - targetTag: The existing tag to receive all note relationships
    ///   - context: The managed object context to use for operations
    /// - Throws: Core Data errors if operations fail
    static func mergeTag(_ sourceTag: Tag, into targetTag: Tag, in context: NSManagedObjectContext) throws {
        let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "TagManager")
        
        guard sourceTag.id != targetTag.id else {
            logger.info("Attempted to merge tag into itself, ignoring")
            return
        }
        
        logger.info("Merging tag '\(sourceTag.name ?? "Unknown")' into '\(targetTag.name ?? "Unknown")'")
        
        // Get all notes associated with the source tag
        if let sourceNotes = sourceTag.notes as? Set<Note> {
            for note in sourceNotes {
                // Remove the note from source tag
                note.removeFromTags(sourceTag)
                
                // Add the note to target tag (if not already associated)
                if let targetNotes = targetTag.notes as? Set<Note>, !targetNotes.contains(note) {
                    note.addToTags(targetTag)
                }
            }
        }
        
        // Delete the source tag
        context.delete(sourceTag)
        
        // Save changes
        try context.save()
        
        logger.info("Successfully merged tag and moved \((sourceTag.notes as? Set<Note>)?.count ?? 0) note associations")
    }
    
    /// Finds an existing tag with the same name (case-insensitive) excluding the specified tag
    /// - Parameters:
    ///   - name: The tag name to search for
    ///   - excludeTag: The tag to exclude from the search (usually the tag being renamed)
    ///   - context: The managed object context to use for the search
    /// - Returns: The existing tag if found, nil otherwise
    /// - Throws: Core Data errors if fetch fails
    static func findExistingTag(named name: String, excluding excludeTag: Tag, in context: NSManagedObjectContext) throws -> Tag? {
        let fetchRequest: NSFetchRequest<Tag> = Tag.fetchRequest()
        let tagId = excludeTag.id ?? UUID()
        fetchRequest.predicate = NSPredicate(format: "name ==[c] %@ AND id != %@", name, tagId as CVarArg)
        
        let results = try context.fetch(fetchRequest)
        return results.first
    }
}