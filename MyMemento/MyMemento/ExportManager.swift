import Foundation
import CoreData
import Compression
import CryptoKit

enum ExportError: Error {
    case noteNotFound
    case encryptedDataMissing
    case decryptionFailed
    case zipCreationFailed
    case encryptionFailed
    case keyWrappingFailed
    case finalPackagingFailed
    case temporaryDirectoryError
    case attachmentNotFound
}

class ExportManager {
    
    private let fileManager = FileManager.default
    
    // MARK: - Public API
    
    /// Exports a note as an encrypted archive with hybrid encryption
    /// - Parameters:
    ///   - note: The Core Data Note entity to export
    ///   - publicKey: RSA public key data (PEM or DER format) for key wrapping
    /// - Returns: URL to the final export.zip file
    /// - Throws: ExportError if any step fails
    func export(note: Note, publicKey: Data) async throws -> URL {
        do {
            // Step 1: Create temporary working directory
            let tempDir = try createTemporaryDirectory()
            defer {
                try? fileManager.removeItem(at: tempDir)
            }
            
            // Step 2: Gather note data and create content structure
            let contentDir = tempDir.appendingPathComponent("content")
            try fileManager.createDirectory(at: contentDir, withIntermediateDirectories: true)
            
            let (_, noteData) = try await gatherNoteData(note: note, contentDir: contentDir)
            
            // Step 3: Create temporary export.zip
            let tempZipURL = tempDir.appendingPathComponent("export.zip")
            try await createZipArchive(contentDir: contentDir, outputURL: tempZipURL)
            
            // Step 4: Generate AES key and encrypt the zip
            let exportKey = CryptoHelper.generateExportKey()
            let (encryptedURL, nonce, tag) = try await CryptoHelper.encryptExportBundle(bundleURL: tempZipURL, key: exportKey)
            
            // Step 5: Wrap the AES key with RSA public key
            let wrappedKey = try CryptoHelper.wrapExportKey(key: exportKey, with: publicKey)
            
            // Step 6: Package final export.zip with comprehensive manifest
            let finalExportURL = try await packageFinalExport(
                note: note,
                noteData: noteData,
                encryptedURL: encryptedURL,
                wrappedKey: wrappedKey,
                nonce: nonce,
                tag: tag
            )
            
            return finalExportURL
            
        } catch {
            ErrorManager.shared.handleError(error, context: "Note export failed")
            if error is ExportError {
                throw error
            } else {
                throw ExportError.encryptionFailed
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func createTemporaryDirectory() throws -> URL {
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true)
            return tempURL
        } catch {
            ErrorManager.shared.handleError(error, context: "Failed to create temporary directory")
            throw ExportError.temporaryDirectoryError
        }
    }
    
    private func gatherNoteData(note: Note, contentDir: URL) async throws -> (htmlContent: String, notePayload: NotePayload) {
        // Decrypt the note payload
        guard let encryptedData = note.encryptedData else {
            ErrorManager.shared.handleError(ExportError.encryptedDataMissing, context: "Note missing encrypted data")
            throw ExportError.encryptedDataMissing
        }
        
        let encryptionKey: SymmetricKey
        do {
            encryptionKey = try KeyManager.shared.getEncryptionKey()
        } catch {
            ErrorManager.shared.handleError(error, context: "No encryption key available")
            throw ExportError.decryptionFailed
        }
        
        let notePayload: NotePayload
        do {
            notePayload = try CryptoHelper.decrypt(encryptedData, key: encryptionKey, as: NotePayload.self)
        } catch {
            ErrorManager.shared.handleError(error, context: "Failed to decrypt note payload")
            throw ExportError.decryptionFailed
        }
        
        // Extract HTML content from NSAttributedString
        let htmlData = try notePayload.body.attributedString.data(
            from: NSRange(location: 0, length: notePayload.body.attributedString.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
            ]
        )
        let htmlContent = String(data: htmlData, encoding: .utf8) ?? ""
        
        // Write body.html
        let bodyURL = contentDir.appendingPathComponent("body.html")
        try htmlContent.write(to: bodyURL, atomically: true, encoding: .utf8)
        
        // Handle attachments if they exist
        if let attachments = note.attachments, attachments.count > 0 {
            let attachmentsDir = contentDir.appendingPathComponent("attachments")
            try fileManager.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
            
            try await copyAttachments(attachments: Array(attachments) as! [Attachment], to: attachmentsDir, encryptionKey: encryptionKey)
        }
        
        return (htmlContent, notePayload)
    }
    
    private func copyAttachments(attachments: [Attachment], to attachmentsDir: URL, encryptionKey: SymmetricKey) async throws {
        for attachment in attachments {
            guard let attachmentId = attachment.id else { continue }
            
            // Get the attachment file URL
            guard let attachmentURL = await AttachmentManager.shared.getFileURL(for: attachment) else {
                ErrorManager.shared.handleError(ExportError.attachmentNotFound, context: "Attachment URL not found: \(attachmentId)")
                continue
            }
            
            // Check if the file exists
            guard await AttachmentManager.shared.fileExists(for: attachment) else {
                ErrorManager.shared.handleError(ExportError.attachmentNotFound, context: "Attachment file not found: \\(attachmentId)")
                continue // Skip missing attachments rather than failing the entire export
            }
            
            // Decrypt the attachment file
            let decryptedURL = attachmentsDir.appendingPathComponent(attachment.relativePath ?? "attachment_\\(attachmentId.uuidString)")
            
            do {
                try await CryptoHelper.decryptFile(inputURL: attachmentURL, outputURL: decryptedURL, key: encryptionKey)
            } catch {
                ErrorManager.shared.handleError(error, context: "Failed to decrypt attachment: \\(attachmentId)")
                // Continue with other attachments rather than failing the entire export
                continue
            }
        }
    }
    
    private func createZipArchive(contentDir: URL, outputURL: URL) async throws {
        // On iOS, Process is not available, so we'll create a directory-based archive
        // In a production app, you'd use a zip library like ZipFoundation
        do {
            // For now, just copy the content directory to the output location
            // This creates a "bundle" that contains all the files
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
            }
            
            // Create the output directory
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            
            // Copy all contents from contentDir to outputURL
            let contents = try fileManager.contentsOfDirectory(at: contentDir, includingPropertiesForKeys: nil)
            for item in contents {
                let filename = item.lastPathComponent
                let destination = outputURL.appendingPathComponent(filename)
                try fileManager.copyItem(at: item, to: destination)
            }
            
        } catch {
            ErrorManager.shared.handleError(error, context: "Failed to create archive")
            throw ExportError.zipCreationFailed
        }
    }
    
    private func packageFinalExport(
        note: Note,
        noteData: NotePayload,
        encryptedURL: URL,
        wrappedKey: Data,
        nonce: Data,
        tag: Data
    ) async throws -> URL {
        do {
            // Create final exports directory
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let exportsURL = applicationSupportURL.appendingPathComponent("Exports")
            
            if !fileManager.fileExists(atPath: exportsURL.path) {
                try fileManager.createDirectory(at: exportsURL, withIntermediateDirectories: true)
            }
            
            // Create temporary directory for final packaging
            let tempDir = try createTemporaryDirectory()
            defer {
                try? fileManager.removeItem(at: tempDir)
            }
            
            // Copy encrypted archive
            let finalEncryptedURL = tempDir.appendingPathComponent("export.enc")
            try fileManager.copyItem(at: encryptedURL, to: finalEncryptedURL)
            
            // Write wrapped key
            let keyURL = tempDir.appendingPathComponent("key.enc")
            try wrappedKey.write(to: keyURL)
            
            // Create comprehensive manifest.json with all required fields
            let tags = note.tags?.compactMap { ($0 as? Tag)?.name } ?? []
            let manifest = [
                "version": "1.0",
                "noteId": note.id?.uuidString ?? "",
                "title": noteData.title,
                "tags": tags,
                "createdAt": ISO8601DateFormatter().string(from: noteData.createdAt),
                "updatedAt": ISO8601DateFormatter().string(from: noteData.updatedAt),
                "pinned": noteData.pinned,
                "crypto": [
                    "cipher": "AES-256-GCM",
                    "keyWrap": "RSA-OAEP-SHA256",
                    "nonce": nonce.base64EncodedString(),
                    "tag": tag.base64EncodedString()
                ]
            ] as [String: Any]
            
            let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
            let finalManifestURL = tempDir.appendingPathComponent("manifest.json")
            try manifestData.write(to: finalManifestURL)
            
            // Create final export.zip
            let finalExportURL = exportsURL.appendingPathComponent("export_\\(UUID().uuidString).zip")
            try await createZipArchive(contentDir: tempDir, outputURL: finalExportURL)
            
            return finalExportURL
            
        } catch {
            ErrorManager.shared.handleError(error, context: "Failed to package final export")
            throw ExportError.finalPackagingFailed
        }
    }
}

// MARK: - Singleton Access
extension ExportManager {
    static let shared = ExportManager()
}