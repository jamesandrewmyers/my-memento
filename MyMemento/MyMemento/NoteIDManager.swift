import Foundation
import CoreData
import OSLog

/// Manages note ID generation and handles constraint violations
class NoteIDManager {
    
    private static let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "NoteIDManager")
    
    /// Generates a UUID for a new note
    /// - Returns: A new UUID
    static func generateNoteID() -> UUID {
        return UUID()
    }
    
    /// Ensures a note has an ID, generating one if necessary
    /// - Parameter note: The note to ensure has an ID
    static func ensureNoteHasID(_ note: Note) {
        if note.id == nil {
            note.id = generateNoteID()
            logger.debug("Assigned new ID to note: \(note.id?.uuidString ?? "unknown")")
        }
    }
    
    /// Handles Core Data save errors, specifically unique constraint violations
    /// - Parameters:
    ///   - error: The Core Data error
    ///   - context: The context that failed to save
    ///   - retryAction: Action to retry after fixing the constraint violation
    /// - Returns: True if the error was handled, false otherwise
    static func handleSaveError(_ error: Error, in context: NSManagedObjectContext, retryAction: @escaping () throws -> Void) -> Bool {
        let nsError = error as NSError
        
        // Check if this is a unique constraint violation
        // Core Data returns NSValidationErrorDuplicateObjects (1550) for unique constraint violations
        if nsError.domain == "NSCocoaErrorDomain" && nsError.code == 1550 {
            logger.warning("Unique constraint violation detected, attempting to resolve...")
            
            // Find notes with duplicate IDs and regenerate them
            do {
                let request: NSFetchRequest<Note> = Note.fetchRequest()
                let allNotes = try context.fetch(request)
                
                var seenIDs: Set<UUID> = []
                var notesToFix: [Note] = []
                
                for note in allNotes {
                    guard let noteID = note.id else { continue }
                    
                    if seenIDs.contains(noteID) {
                        notesToFix.append(note)
                        logger.warning("Found duplicate note ID: \(noteID.uuidString), will regenerate")
                    } else {
                        seenIDs.insert(noteID)
                    }
                }
                
                // Regenerate IDs for duplicate notes
                for note in notesToFix {
                    note.id = generateNoteID()
                    logger.info("Regenerated ID for note: \(note.id?.uuidString ?? "unknown")")
                }
                
                // Retry the save operation
                try retryAction()
                return true
                
            } catch {
                logger.error("Failed to resolve unique constraint violation: \(error.localizedDescription)")
                return false
            }
        }
        
        return false
    }
}
