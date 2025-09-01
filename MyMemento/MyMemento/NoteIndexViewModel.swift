import SwiftUI
import CoreData
import OSLog
import Foundation

@MainActor
class NoteIndexViewModel: ObservableObject {
    @Published var indexPayloads: [IndexPayload] = []
    private let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "NoteIndexViewModel")
    
    func loadIndex(from context: NSManagedObjectContext) {
        do {
            let encryptionKey = try KeyManager.shared.getEncryptionKey()
            
            let request: NSFetchRequest<SearchIndex> = SearchIndex.fetchRequest()
            let searchIndices = try context.fetch(request)
            
            // Fetch all notes to check for pin status consistency
            let noteRequest: NSFetchRequest<Note> = Note.fetchRequest()
            let allNotes = try context.fetch(noteRequest)
            let notesById = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.id!, $0) })
            
            var decryptedPayloads: [IndexPayload] = []
            var updatedSearchIndices: [SearchIndex] = []
            
            for searchIndex in searchIndices {
                guard let encryptedData = searchIndex.encryptedIndexData else {
                    logger.warning("SearchIndex \(searchIndex.id?.uuidString ?? "unknown") has no encrypted data")
                    continue
                }
                
                do {
                    var indexPayload = try CryptoHelper.decrypt(encryptedData, key: encryptionKey, as: IndexPayload.self)
                    
                    // Check if the corresponding Note exists and sync pin status
                    if let note = notesById[indexPayload.id] {
                        if indexPayload.pinned != note.isPinned {
                            logger.info("Syncing pin status for note \(indexPayload.id): IndexPayload.pinned=\(indexPayload.pinned) -> Note.isPinned=\(note.isPinned)")
                            indexPayload.pinned = note.isPinned
                            
                            // Re-encrypt with updated pin status
                            let updatedEncryptedData = try CryptoHelper.encrypt(indexPayload, key: encryptionKey)
                            searchIndex.encryptedIndexData = updatedEncryptedData
                            updatedSearchIndices.append(searchIndex)
                        }
                    }
                    
                    decryptedPayloads.append(indexPayload)
                } catch {
                    logger.error("Failed to decrypt SearchIndex \(searchIndex.id?.uuidString ?? "unknown"): \(error.localizedDescription)")
                }
            }
            
            // Save any updated SearchIndex entities
            if !updatedSearchIndices.isEmpty {
                try context.save()
                logger.info("Updated pin status for \(updatedSearchIndices.count) search indices")
            }
            
            // Sort by pinned status, then by creation date (newest first)
            self.indexPayloads = decryptedPayloads.sorted { index1, index2 in
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                return index1.createdAt > index2.createdAt
            }
            
            logger.info("Loaded and decrypted \(self.indexPayloads.count) note indices")
            
        } catch {
            logger.error("Failed to load note index: \(error.localizedDescription)")
        }
    }
    
    func refreshIndex(from context: NSManagedObjectContext) {
        loadIndex(from: context)
    }
}