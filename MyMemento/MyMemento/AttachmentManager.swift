import Foundation
import CoreData
import CryptoKit
import OSLog

/// Manages CRUD operations and cleanup for encrypted attachments
@MainActor
class AttachmentManager: ObservableObject {
    
    enum AttachmentError: Error, LocalizedError {
        case invalidSourceFile
        case encryptionFailed
        case fileOperationFailed(String)
        case coreDataOperationFailed(String)
        case applicationSupportNotFound
        case attachmentNotFound
        
        var errorDescription: String? {
            switch self {
            case .invalidSourceFile:
                return "The source file is invalid or cannot be accessed"
            case .encryptionFailed:
                return "Failed to encrypt the attachment file"
            case .fileOperationFailed(let details):
                return "File operation failed: \(details)"
            case .coreDataOperationFailed(let details):
                return "Database operation failed: \(details)"
            case .applicationSupportNotFound:
                return "Could not access application storage directory"
            case .attachmentNotFound:
                return "Attachment not found or already deleted"
            }
        }
    }
    
    private let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "AttachmentManager")
    private let fileManager = FileManager.default
    
    /// Creates a new encrypted video attachment for a note
    /// - Parameters:
    ///   - note: The note to attach the video to
    ///   - sourceURL: URL of the source video file to encrypt
    ///   - context: Core Data managed object context
    /// - Returns: The created Attachment entity
    /// - Throws: AttachmentError if creation fails
    func createVideoAttachment(for note: Note, from sourceURL: URL, context: NSManagedObjectContext) async throws -> Attachment {
        do {
            // Validate source file exists and is accessible
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw AttachmentError.invalidSourceFile
            }
            
            // Get Application Support directory
            guard let applicationSupportURL = getApplicationSupportURL() else {
                throw AttachmentError.applicationSupportNotFound
            }
            
            // Create Media directory if it doesn't exist
            let mediaDirectoryURL = applicationSupportURL.appendingPathComponent("Media")
            try fileManager.createDirectory(at: mediaDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            
            // Generate unique filename for encrypted attachment
            let attachmentUUID = UUID()
            let encryptedFilename = "\(attachmentUUID.uuidString).vaultvideo"
            let encryptedFileURL = mediaDirectoryURL.appendingPathComponent(encryptedFilename)
            let relativePath = "Media/\(encryptedFilename)"
            
            // Get encryption key
            let encryptionKey = try KeyManager.shared.getEncryptionKey()
            
            // Encrypt the source file
            try await CryptoHelper.encryptFile(inputURL: sourceURL, outputURL: encryptedFileURL, key: encryptionKey)
            
            // Create Attachment entity in Core Data
            let attachment = Attachment(context: context)
            attachment.id = attachmentUUID
            attachment.type = "video"
            attachment.relativePath = relativePath
            attachment.createdAt = Date()
            attachment.note = note
            
            // Save context
            try context.save()
            
            logger.info("Created video attachment: \(attachmentUUID.uuidString) for note: \(note.id?.uuidString ?? "unknown")")
            
            return attachment
            
        } catch let error as AttachmentError {
            ErrorManager.shared.handleError(error, context: "Creating video attachment")
            throw error
        } catch {
            let wrappedError = AttachmentError.coreDataOperationFailed(error.localizedDescription)
            ErrorManager.shared.handleError(wrappedError, context: "Creating video attachment")
            throw wrappedError
        }
    }
    
    /// Creates an encrypted audio attachment from a source audio file
    @MainActor
    func createAudioAttachment(for note: Note, from sourceURL: URL, context: NSManagedObjectContext) async throws -> Attachment {
        do {
            // Validate source file exists and is accessible
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw AttachmentError.invalidSourceFile
            }
            
            // Get Application Support directory
            guard let applicationSupportURL = getApplicationSupportURL() else {
                throw AttachmentError.applicationSupportNotFound
            }
            
            // Create Media directory if it doesn't exist
            let mediaDirectoryURL = applicationSupportURL.appendingPathComponent("Media")
            try fileManager.createDirectory(at: mediaDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            
            // Generate unique filename for encrypted attachment
            let attachmentUUID = UUID()
            let encryptedFilename = "\(attachmentUUID.uuidString).vaultaudio"
            let encryptedFileURL = mediaDirectoryURL.appendingPathComponent(encryptedFilename)
            let relativePath = "Media/\(encryptedFilename)"
            
            // Get encryption key
            let encryptionKey = try KeyManager.shared.getEncryptionKey()
            
            // Encrypt the source file
            try await CryptoHelper.encryptFile(inputURL: sourceURL, outputURL: encryptedFileURL, key: encryptionKey)
            
            // Create Attachment entity in Core Data
            let attachment = Attachment(context: context)
            attachment.id = attachmentUUID
            attachment.type = "audio"
            attachment.relativePath = relativePath
            attachment.createdAt = Date()
            attachment.note = note
            
            // Save context
            try context.save()
            
            logger.info("Created audio attachment: \(attachmentUUID.uuidString) for note: \(note.id?.uuidString ?? "unknown")")
            
            return attachment
            
        } catch let error as AttachmentError {
            ErrorManager.shared.handleError(error, context: "Creating audio attachment")
            throw error
        } catch {
            let wrappedError = AttachmentError.coreDataOperationFailed(error.localizedDescription)
            ErrorManager.shared.handleError(wrappedError, context: "Creating audio attachment")
            throw wrappedError
        }
    }
    
    /// Creates a location attachment for a note
    /// - Parameters:
    ///   - note: The note to attach the location to
    ///   - location: The location to attach
    ///   - context: Core Data managed object context
    /// - Returns: The created Attachment entity
    /// - Throws: AttachmentError if creation fails
    func createLocationAttachment(for note: Note, from location: Location, context: NSManagedObjectContext) async throws -> Attachment {
        do {
            logger.info("Creating location attachment for note \(note.id?.uuidString ?? "unknown") with location \(location.name ?? "unnamed")")
            
            // Create Attachment entity in Core Data
            let attachment = Attachment(context: context)
            attachment.id = UUID()
            attachment.type = "location"
            attachment.relativePath = nil  // Location attachments don't use file paths
            attachment.createdAt = Date()
            attachment.note = note
            attachment.location = location
            
            // Save context
            try context.save()
            
            logger.info("Created location attachment: \(attachment.id?.uuidString ?? "unknown") for note: \(note.id?.uuidString ?? "unknown")")
            
            return attachment
            
        } catch {
            let wrappedError = AttachmentError.coreDataOperationFailed(error.localizedDescription)
            ErrorManager.shared.handleError(wrappedError, context: "Creating location attachment")
            throw wrappedError
        }
    }
    
    /// Deletes an attachment and its encrypted file from disk
    /// - Parameters:
    ///   - attachment: The attachment to delete
    ///   - context: Core Data managed object context
    /// - Throws: AttachmentError if deletion fails
    func deleteAttachment(_ attachment: Attachment, context: NSManagedObjectContext) async throws {
        do {
            let attachmentID = attachment.id?.uuidString ?? "unknown"
            logger.info("Deleting attachment: \(attachmentID)")
            
            // Delete encrypted file from disk if it exists
            if let relativePath = attachment.relativePath,
               let applicationSupportURL = getApplicationSupportURL() {
                let fileURL = applicationSupportURL.appendingPathComponent(relativePath)
                
                if fileManager.fileExists(atPath: fileURL.path) {
                    do {
                        try fileManager.removeItem(at: fileURL)
                        logger.info("Deleted encrypted file: \(relativePath)")
                    } catch {
                        logger.error("Failed to delete file \(relativePath): \(error.localizedDescription)")
                        // Continue with Core Data deletion even if file deletion fails
                        let fileError = AttachmentError.fileOperationFailed("Could not delete file: \(error.localizedDescription)")
                        ErrorManager.shared.handleError(fileError, context: "Deleting attachment file")
                    }
                }
            }
            
            // Remove from Core Data
            context.delete(attachment)
            try context.save()
            
            logger.info("Successfully deleted attachment: \(attachmentID)")
            
        } catch {
            let wrappedError = AttachmentError.coreDataOperationFailed(error.localizedDescription)
            ErrorManager.shared.handleError(wrappedError, context: "Deleting attachment")
            throw wrappedError
        }
    }
    
    /// Cleans up orphaned attachment files that no longer have corresponding Core Data entries
    /// - Parameter context: Core Data managed object context
    /// - Throws: AttachmentError if cleanup fails
    func cleanupOrphanedAttachments(context: NSManagedObjectContext) async throws {
        do {
            logger.info("Starting cleanup of orphaned attachments")
            
            // Get Application Support/Media directory
            guard let applicationSupportURL = getApplicationSupportURL() else {
                throw AttachmentError.applicationSupportNotFound
            }
            
            let mediaDirectoryURL = applicationSupportURL.appendingPathComponent("Media")
            
            // Check if Media directory exists
            guard fileManager.fileExists(atPath: mediaDirectoryURL.path) else {
                logger.info("Media directory does not exist, no cleanup needed")
                return
            }
            
            // Get all .vaultvideo and .vaultaudio files in Media directory
            let diskFiles = try fileManager.contentsOfDirectory(at: mediaDirectoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .filter { $0.pathExtension == "vaultvideo" || $0.pathExtension == "vaultaudio" }
                .map { "Media/\($0.lastPathComponent)" }
            
            // Get all relativePath values from Attachments in Core Data
            let fetchRequest: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            let attachments = try context.fetch(fetchRequest)
            let attachmentPaths = Set(attachments.compactMap { $0.relativePath })
            
            // Find orphaned files (on disk but not in database)
            let orphanedFiles = Set(diskFiles).subtracting(attachmentPaths)
            
            // Delete orphaned files
            var deletedCount = 0
            for relativePath in orphanedFiles {
                let fileURL = applicationSupportURL.appendingPathComponent(relativePath)
                do {
                    try fileManager.removeItem(at: fileURL)
                    deletedCount += 1
                    logger.info("Deleted orphaned file: \(relativePath)")
                } catch {
                    logger.error("Failed to delete orphaned file \(relativePath): \(error.localizedDescription)")
                    let fileError = AttachmentError.fileOperationFailed("Could not delete orphaned file: \(error.localizedDescription)")
                    ErrorManager.shared.handleError(fileError, context: "Cleaning up orphaned files")
                }
            }
            
            logger.info("Cleanup completed: deleted \(deletedCount) orphaned files out of \(orphanedFiles.count) found")
            
        } catch {
            let wrappedError = AttachmentError.fileOperationFailed(error.localizedDescription)
            ErrorManager.shared.handleError(wrappedError, context: "Cleaning up orphaned attachments")
            throw wrappedError
        }
    }

    /// Cleans up all attachments (files + Core Data objects) for a note being permanently deleted
    /// - Parameters:
    ///   - note: The note whose attachments should be removed
    ///   - context: Core Data context
    /// - Important: Performs file I/O off the main thread; Core Data deletions on main actor
    func cleanupForDeletedNote(note: Note, context: NSManagedObjectContext) async throws {
        // Capture attachment info on main actor to avoid threading issues
        let attachments: [Attachment] = (note.attachments as? Set<Attachment>).map(Array.init) ?? []
        let attachmentRelativePaths: [String] = attachments
            .filter { ["video", "audio"].contains(($0.type ?? "").lowercased()) }
            .compactMap { $0.relativePath }

        // Delete files off the main thread
        if !attachmentRelativePaths.isEmpty, let appSupport = getApplicationSupportURL() {
            let fileURLs = attachmentRelativePaths.map { appSupport.appendingPathComponent($0) }

            // Launch detached tasks to ensure work is off the main actor
            var tasks: [Task<Void, Never>] = []
            for url in fileURLs {
                let t = Task.detached(priority: .userInitiated) {
                    do {
                        if FileManager.default.fileExists(atPath: url.path) {
                            try FileManager.default.removeItem(at: url)
                        }
                    } catch {
                        await MainActor.run {
                            ErrorManager.shared.handleError(error, context: "Deleting attachment file: \(url.lastPathComponent)")
                        }
                    }
                }
                tasks.append(t)
            }
            // Await all deletions
            for t in tasks { await t.value }
        }

        // Delete Attachment objects from Core Data (on main)
        for attachment in attachments {
            context.delete(attachment)
        }
        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            ErrorManager.shared.handleCoreDataError(nsError, context: "Saving after attachment cleanup")
            throw error
        }
    }

    // MARK: - Helper Methods
    
    /// Gets the Application Support directory URL
    /// - Returns: URL to Application Support directory, or nil if not accessible
    private func getApplicationSupportURL() -> URL? {
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
    
    /// Gets the full file URL for an attachment
    /// - Parameter attachment: The attachment to get the URL for
    /// - Returns: Full URL to the encrypted file, or nil if not available
    func getFileURL(for attachment: Attachment) -> URL? {
        guard let relativePath = attachment.relativePath,
              let applicationSupportURL = getApplicationSupportURL() else {
            return nil
        }
        
        return applicationSupportURL.appendingPathComponent(relativePath)
    }
    
    /// Checks if an attachment's file exists on disk
    /// - Parameter attachment: The attachment to check
    /// - Returns: True if the file exists, false otherwise
    func fileExists(for attachment: Attachment) -> Bool {
        guard let fileURL = getFileURL(for: attachment) else {
            return false
        }
        
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    /// Gets file size for an attachment
    /// - Parameter attachment: The attachment to get size for
    /// - Returns: File size in bytes, or 0 if file doesn't exist or size can't be determined
    func getFileSize(for attachment: Attachment) -> Int64 {
        guard let fileURL = getFileURL(for: attachment) else {
            return 0
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            logger.error("Failed to get file size for attachment \(attachment.id?.uuidString ?? "unknown"): \(error.localizedDescription)")
            return 0
        }
    }
}

// MARK: - Convenience Extensions

extension AttachmentManager {
    
    /// Shared instance for global access
    static let shared = AttachmentManager()
    
    /// Creates a video attachment using the shared instance
    /// - Parameters:
    ///   - note: The note to attach the video to
    ///   - sourceURL: URL of the source video file
    ///   - context: Core Data managed object context
    /// - Returns: The created Attachment entity
    static func createVideoAttachment(for note: Note, from sourceURL: URL, context: NSManagedObjectContext) async throws -> Attachment {
        return try await shared.createVideoAttachment(for: note, from: sourceURL, context: context)
    }
    
    /// Creates an audio attachment using the shared instance
    /// - Parameters:
    ///   - note: The note to attach the audio to
    ///   - sourceURL: URL of the source audio file
    ///   - context: Core Data managed object context
    /// - Returns: The created Attachment entity
    static func createAudioAttachment(for note: Note, from sourceURL: URL, context: NSManagedObjectContext) async throws -> Attachment {
        return try await shared.createAudioAttachment(for: note, from: sourceURL, context: context)
    }
    
    /// Creates a location attachment using the shared instance
    /// - Parameters:
    ///   - note: The note to attach the location to
    ///   - location: The location to attach
    ///   - context: Core Data managed object context
    /// - Returns: The created Attachment entity
    static func createLocationAttachment(for note: Note, from location: Location, context: NSManagedObjectContext) async throws -> Attachment {
        return try await shared.createLocationAttachment(for: note, from: location, context: context)
    }
    
    /// Deletes an attachment using the shared instance
    /// - Parameters:
    ///   - attachment: The attachment to delete
    ///   - context: Core Data managed object context
    static func deleteAttachment(_ attachment: Attachment, context: NSManagedObjectContext) async throws {
        try await shared.deleteAttachment(attachment, context: context)
    }
    
    /// Cleans up orphaned attachments using the shared instance
    /// - Parameter context: Core Data managed object context
    static func cleanupOrphanedAttachments(context: NSManagedObjectContext) async throws {
        try await shared.cleanupOrphanedAttachments(context: context)
    }

    /// Cleans up all attachments for a deleted note using the shared instance
    static func cleanupForDeletedNote(note: Note, context: NSManagedObjectContext) async throws {
        try await shared.cleanupForDeletedNote(note: note, context: context)
    }
}
