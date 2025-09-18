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
    /// - Returns: URL to the final export.memento file
    /// - Throws: ExportError if any step fails
    func export(note: Note, publicKey: Data) async throws -> URL {
        // Preserve existing behavior: no keyOwner in manifest and random filename
        return try await export(note: note, publicKey: publicKey, keyOwner: nil, preferredFileName: nil)
    }

    /// Exports a note using the app's local RSA keypair for key wrapping
    /// - Parameter note: The Core Data Note entity to export
    /// - Returns: URL to the final export_local.memento file in Application Support/Exports
    /// - Throws: ExportError if any step fails
    func exportWithLocalKey(note: Note) async throws -> URL {
        let exportStartTime = CFAbsoluteTimeGetCurrent()
        do {
            print("ExportManager: [\(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - exportStartTime))s] Getting export public key data")
            let publicKeyData = try KeyManager.shared.getExportPublicKeyData()
            print("ExportManager: [\(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - exportStartTime))s] Got public key data, calling export")
            let result = try await export(note: note, publicKey: publicKeyData, keyOwner: "local", preferredFileName: "export_local.memento")
            let totalTime = CFAbsoluteTimeGetCurrent() - exportStartTime
            print("ExportManager: [\(String(format: "%.2f", totalTime))s] Export completed successfully, returning URL: \(result.path)")
            return result
        } catch {
            let totalTime = CFAbsoluteTimeGetCurrent() - exportStartTime
            print("ExportManager: [\(String(format: "%.2f", totalTime))s] Export failed with error: \(error)")
            ErrorManager.shared.handleError(error, context: "Local-key export failed")
            throw error
        }
    }

    /// Core export implementation supporting optional manifest fields and filename override
    /// - Parameters:
    ///   - note: The note to export
    ///   - publicKey: RSA public key data for wrapping the export key
    ///   - keyOwner: Optional key owner label for manifest (e.g., "local")
    ///   - preferredFileName: Optional fixed filename for final export (e.g., "export_local.memento")
    private func export(note: Note, publicKey: Data, keyOwner: String?, preferredFileName: String?) async throws -> URL {
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
            
            // Step 6: Package final export.memento with comprehensive manifest
            let finalExportURL = try await packageFinalExport(
                note: note,
                noteData: noteData,
                encryptedURL: encryptedURL,
                wrappedKey: wrappedKey,
                nonce: nonce,
                tag: tag,
                keyOwner: keyOwner,
                preferredFileName: preferredFileName
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
        print("Export Debug: Note ID: \(note.id?.uuidString ?? "nil")")
        print("Export Debug: Note type: \(type(of: note))")
        print("Export Debug: Note title: \(note.title ?? "nil")")
        print("Export Debug: Note createdAt: \(note.createdAt?.description ?? "nil")")
        print("Export Debug: Note encryptedData: \(note.encryptedData?.count ?? 0) bytes")
        
        guard let encryptedData = note.encryptedData else {
            print("Export Debug: WARNING - Note missing encryptedData, skipping note \(note.id?.uuidString ?? "unknown")")
            // Skip notes without encrypted data instead of failing the entire export
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
            
            print("Export: Processing \(attachments.count) attachments for note \(note.id?.uuidString ?? "unknown")")
            try await copyAttachments(attachments: Array(attachments) as! [Attachment], to: attachmentsDir, encryptionKey: encryptionKey)
        }
        
        return (htmlContent, notePayload)
    }
    
    private func copyAttachments(attachments: [Attachment], to attachmentsDir: URL, encryptionKey: SymmetricKey) async throws {
        for attachment in attachments {
            guard let attachmentId = attachment.id else { 
                ErrorManager.shared.handleError(ExportError.attachmentNotFound, context: "Attachment missing ID")
                continue 
            }
            
            // Get the attachment file URL
            guard let attachmentURL = await AttachmentManager.shared.getFileURL(for: attachment) else {
                let error = ExportError.attachmentNotFound
                ErrorManager.shared.handleError(error, context: "Attachment URL not found: \(attachmentId)")
                print("Export: Skipping attachment \(attachmentId) - URL not found")
                continue
            }
            
            // Check if the file exists with more detailed error info
            guard await AttachmentManager.shared.fileExists(for: attachment) else {
                let error = ExportError.attachmentNotFound
                let relativePath = attachment.relativePath ?? "unknown path"
                ErrorManager.shared.handleError(error, context: "Attachment file not found: \(attachmentId) at path: \(relativePath)")
                print("Export: Skipping attachment \(attachmentId) - file not found at: \(relativePath)")
                continue // Skip missing attachments rather than failing the entire export
            }
            
            // Prepare output filename - ensure it has proper extension
            let originalFilename = attachment.relativePath?.components(separatedBy: "/").last ?? "attachment_\(attachmentId.uuidString)"
            let outputFilename: String
            if originalFilename.hasSuffix(".vaultvideo") {
                // Remove .vaultvideo extension and add proper video extension
                let nameWithoutVault = String(originalFilename.dropLast(11)) // Remove ".vaultvideo"
                outputFilename = nameWithoutVault.isEmpty ? "\(attachmentId.uuidString).mp4" : "\(nameWithoutVault).mp4"
            } else {
                outputFilename = originalFilename
            }
            let decryptedURL = attachmentsDir.appendingPathComponent(outputFilename)
            
            // Decrypt the attachment file with better error handling
            do {
                print("Export: Decrypting attachment \(attachmentId) from \(attachmentURL.path) to \(decryptedURL.path)")
                try await CryptoHelper.decryptFile(inputURL: attachmentURL, outputURL: decryptedURL, key: encryptionKey)
                print("Export: Successfully decrypted attachment \(attachmentId)")
            } catch {
                ErrorManager.shared.handleError(error, context: "Failed to decrypt attachment: \(attachmentId) from path: \(attachmentURL.path)")
                print("Export: Failed to decrypt attachment \(attachmentId): \(error.localizedDescription)")
                // Continue with other attachments rather than failing the entire export
                continue
            }
        }
    }
    
    private func createZipArchive(contentDir: URL, outputURL: URL) async throws {
        do {
            let overallStartTime = CFAbsoluteTimeGetCurrent()
            print("ZIP: Starting file-based ZIP creation for \(contentDir.path)")
            
            // Remove existing output if it exists
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
                print("ZIP: Removed existing file at \(outputURL.path)")
            }
            
            // Create ZIP file by streaming directly to disk
            print("ZIP: Creating ZIP file with streaming approach")
            let zipCreationStartTime = CFAbsoluteTimeGetCurrent()
            try createZipFileStreaming(from: contentDir, to: outputURL)
            let zipCreationTime = CFAbsoluteTimeGetCurrent() - zipCreationStartTime
            print("ZIP: ZIP file created in \(String(format: "%.2f", zipCreationTime))s")
            
            // Verify the zip file was created as a single file
            guard fileManager.fileExists(atPath: outputURL.path) else {
                print("ZIP: ERROR - ZIP file does not exist after writing")
                throw ExportError.zipCreationFailed
            }
            
            // Ensure it's a file, not a directory
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                print("ZIP: ERROR - ZIP output is a directory, not a file")
                throw ExportError.zipCreationFailed
            }
            
            // Get final file size
            let fileSize = try fileManager.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber ?? 0
            let overallTime = CFAbsoluteTimeGetCurrent() - overallStartTime
            print("ZIP: ZIP creation completed successfully - \(fileSize.uint64Value / 1024)KB file in \(String(format: "%.2f", overallTime))s total")
            
        } catch {
            print("ZIP: ERROR - \(error)")
            ErrorManager.shared.handleError(error, context: "Failed to create ZIP archive")
            throw ExportError.zipCreationFailed
        }
    }
    
    private func createZipData(from contentDir: URL) throws -> Data {
        print("ZIP: Starting createZipData from \(contentDir.path)")
        
        // Create a proper ZIP file manually using the ZIP format specification
        var zipData = Data()
        let contents = try fileManager.contentsOfDirectory(at: contentDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        print("ZIP: Found \(contents.count) items in content directory")
        
        var centralDirectoryEntries = Data()
        var centralDirectoryOffset: UInt32 = 0
        var fileCount: UInt16 = 0
        
        for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            print("ZIP: Processing item: \(item.lastPathComponent)")
            let isDirectory = try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            
            if isDirectory {
                print("ZIP: Processing subdirectory: \(item.lastPathComponent)")
                // Handle subdirectories
                let subContents = try fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                print("ZIP: Subdirectory contains \(subContents.count) files")
                
                for subItem in subContents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let relativePath = "\(item.lastPathComponent)/\(subItem.lastPathComponent)"
                    print("ZIP: Processing file \(relativePath)")
                    
                    // Check file size before processing
                    let fileSize = try fileManager.attributesOfItem(atPath: subItem.path)[.size] as? NSNumber ?? 0
                    print("ZIP: File size: \(fileSize) bytes")
                    
                    let (localHeader, centralEntry) = try createZipEntryWithStreaming(
                        fileName: relativePath,
                        fileURL: subItem,
                        localHeaderOffset: UInt32(zipData.count)
                    )
                    
                    print("ZIP: Appending header to ZIP archive")
                    zipData.append(localHeader)
                    
                    print("ZIP: Streaming file data to ZIP archive")
                    try streamFileDataToZip(from: subItem, to: &zipData)
                    
                    centralDirectoryEntries.append(centralEntry)
                    fileCount += 1
                    print("ZIP: Completed processing \(relativePath)")
                }
            } else {
                // Handle top-level files
                print("ZIP: Processing top-level file: \(item.lastPathComponent)")
                let fileSize = try fileManager.attributesOfItem(atPath: item.path)[.size] as? NSNumber ?? 0
                print("ZIP: File size: \(fileSize) bytes")
                
                let relativePath = item.lastPathComponent
                
                let (localHeader, centralEntry) = try createZipEntryWithStreaming(
                    fileName: relativePath,
                    fileURL: item,
                    localHeaderOffset: UInt32(zipData.count)
                )
                
                zipData.append(localHeader)
                try streamFileDataToZip(from: item, to: &zipData)
                centralDirectoryEntries.append(centralEntry)
                fileCount += 1
                print("ZIP: Completed processing \(relativePath)")
            }
        }
        
        // Add central directory
        centralDirectoryOffset = UInt32(zipData.count)
        zipData.append(centralDirectoryEntries)
        
        // Add end of central directory record
        let endRecord = createEndOfCentralDirectoryRecord(
            fileCount: fileCount,
            centralDirectorySize: UInt32(centralDirectoryEntries.count),
            centralDirectoryOffset: centralDirectoryOffset
        )
        zipData.append(endRecord)
        
        return zipData
    }
    
    private func createZipFileStreaming(from contentDir: URL, to outputURL: URL) throws {
        print("ZIP: Starting file-based streaming ZIP creation")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Create the output file and get a write handle
        fileManager.createFile(atPath: outputURL.path, contents: nil)
        let writeHandle = try FileHandle(forWritingTo: outputURL)
        defer { 
            writeHandle.closeFile()
            print("ZIP: Closed output file handle")
        }
        
        let contents = try fileManager.contentsOfDirectory(at: contentDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        print("ZIP: Found \(contents.count) items to process")
        
        var centralDirectoryData = Data()
        var fileCount: UInt16 = 0
        var currentOffset: UInt32 = 0
        
        // Process each item and write directly to file
        for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDirectory = try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            
            if isDirectory {
                print("ZIP: Processing subdirectory: \(item.lastPathComponent)")
                let subContents = try fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                
                for subItem in subContents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let relativePath = "\(item.lastPathComponent)/\(subItem.lastPathComponent)"
                    let (localHeaderData, centralEntryData) = try processFileForStreaming(
                        fileURL: subItem,
                        fileName: relativePath,
                        localHeaderOffset: currentOffset,
                        writeHandle: writeHandle
                    )
                    
                    currentOffset += UInt32(localHeaderData.count) + (try fileManager.attributesOfItem(atPath: subItem.path)[.size] as? NSNumber ?? 0).uint32Value
                    centralDirectoryData.append(centralEntryData)
                    fileCount += 1
                }
            } else {
                print("ZIP: Processing top-level file: \(item.lastPathComponent)")
                let (localHeaderData, centralEntryData) = try processFileForStreaming(
                    fileURL: item,
                    fileName: item.lastPathComponent,
                    localHeaderOffset: currentOffset,
                    writeHandle: writeHandle
                )
                
                currentOffset += UInt32(localHeaderData.count) + (try fileManager.attributesOfItem(atPath: item.path)[.size] as? NSNumber ?? 0).uint32Value
                centralDirectoryData.append(centralEntryData)
                fileCount += 1
            }
        }
        
        print("ZIP: Writing central directory (\(centralDirectoryData.count) bytes)")
        let centralDirectoryOffset = currentOffset
        writeHandle.write(centralDirectoryData)
        
        print("ZIP: Writing end of central directory record")
        let endRecord = createEndOfCentralDirectoryRecord(
            fileCount: fileCount,
            centralDirectorySize: UInt32(centralDirectoryData.count),
            centralDirectoryOffset: centralDirectoryOffset
        )
        writeHandle.write(endRecord)
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("ZIP: File-based streaming completed in \(String(format: "%.2f", totalTime))s")
    }
    
    private func processFileForStreaming(
        fileURL: URL,
        fileName: String,
        localHeaderOffset: UInt32,
        writeHandle: FileHandle
    ) throws -> (Data, Data) {
        print("ZIP: Processing \(fileName) for streaming")
        let processStartTime = CFAbsoluteTimeGetCurrent()
        
        // Get file size
        let fileSize = try fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber ?? 0
        let fileSizeUInt32 = UInt32(fileSize.uint64Value)
        
        // Calculate CRC32 by streaming
        let crc32 = try calculateCRC32Streaming(fileURL: fileURL)
        
        // Create local header
        let fileNameData = fileName.data(using: .utf8)!
        var localHeader = Data()
        localHeader.append(Data([0x50, 0x4b, 0x03, 0x04])) // Local file header signature
        localHeader.append(Data([0x14, 0x00])) // Version needed to extract
        localHeader.append(Data([0x00, 0x00])) // General purpose bit flag
        localHeader.append(Data([0x00, 0x00])) // Compression method (stored)
        localHeader.append(Data([0x00, 0x00])) // File last modification time
        localHeader.append(Data([0x00, 0x00])) // File last modification date
        localHeader.append(withUnsafeBytes(of: crc32.littleEndian) { Data($0) }) // CRC-32
        localHeader.append(withUnsafeBytes(of: fileSizeUInt32.littleEndian) { Data($0) }) // Compressed size
        localHeader.append(withUnsafeBytes(of: fileSizeUInt32.littleEndian) { Data($0) }) // Uncompressed size
        localHeader.append(withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Data($0) }) // File name length
        localHeader.append(Data([0x00, 0x00])) // Extra field length
        localHeader.append(fileNameData) // File name
        
        print("ZIP: Writing local header for \(fileName) (\(localHeader.count) bytes)")
        writeHandle.write(localHeader)
        
        print("ZIP: Streaming file content for \(fileName)")
        try streamFileDirectlyToHandle(from: fileURL, to: writeHandle)
        
        // Create central directory entry
        var centralEntry = Data()
        centralEntry.append(Data([0x50, 0x4b, 0x01, 0x02])) // Central file header signature
        centralEntry.append(Data([0x14, 0x00])) // Version made by
        centralEntry.append(Data([0x14, 0x00])) // Version needed to extract
        centralEntry.append(Data([0x00, 0x00])) // General purpose bit flag
        centralEntry.append(Data([0x00, 0x00])) // Compression method
        centralEntry.append(Data([0x00, 0x00])) // File last modification time
        centralEntry.append(Data([0x00, 0x00])) // File last modification date
        centralEntry.append(withUnsafeBytes(of: crc32.littleEndian) { Data($0) }) // CRC-32
        centralEntry.append(withUnsafeBytes(of: fileSizeUInt32.littleEndian) { Data($0) }) // Compressed size
        centralEntry.append(withUnsafeBytes(of: fileSizeUInt32.littleEndian) { Data($0) }) // Uncompressed size
        centralEntry.append(withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Data($0) }) // File name length
        centralEntry.append(Data([0x00, 0x00])) // Extra field length
        centralEntry.append(Data([0x00, 0x00])) // File comment length
        centralEntry.append(Data([0x00, 0x00])) // Disk number start
        centralEntry.append(Data([0x00, 0x00])) // Internal file attributes
        centralEntry.append(Data([0x00, 0x00, 0x00, 0x00])) // External file attributes
        centralEntry.append(withUnsafeBytes(of: localHeaderOffset.littleEndian) { Data($0) }) // Local header offset
        centralEntry.append(fileNameData) // File name
        
        let processTime = CFAbsoluteTimeGetCurrent() - processStartTime
        print("ZIP: Completed processing \(fileName) in \(String(format: "%.3f", processTime))s")
        
        return (localHeader, centralEntry)
    }
    
    private func streamFileDirectlyToHandle(from fileURL: URL, to writeHandle: FileHandle) throws {
        let chunkSize = 64 * 1024 // 64KB chunks for better responsiveness
        let readHandle = try FileHandle(forReadingFrom: fileURL)
        defer { readHandle.closeFile() }
        
        var totalBytes = 0
        var chunkCount = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        
        while true {
            let chunkStartTime = CFAbsoluteTimeGetCurrent()
            let chunk = readHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            
            let readTime = CFAbsoluteTimeGetCurrent() - chunkStartTime
            let writeStartTime = CFAbsoluteTimeGetCurrent()
            writeHandle.write(chunk)
            let writeTime = CFAbsoluteTimeGetCurrent() - writeStartTime
            
            totalBytes += chunk.count
            chunkCount += 1
            
            // Log progress more frequently to track per-chunk timing
            if chunkCount % 100 == 0 || totalBytes % (5 * 1024 * 1024) == 0 {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let mbps = Double(totalBytes) / (1024 * 1024) / elapsed
                print("ZIP: Chunk \(chunkCount): read \(String(format: "%.3f", readTime))s, write \(String(format: "%.3f", writeTime))s, total: \(totalBytes / (1024*1024))MB (\(String(format: "%.1f", mbps)) MB/s)")
            }
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let mbps = totalTime > 0 ? Double(totalBytes) / (1024 * 1024) / totalTime : 0
        print("ZIP: Completed streaming \(totalBytes) bytes from \(fileURL.lastPathComponent) in \(String(format: "%.3f", totalTime))s (\(String(format: "%.1f", mbps)) MB/s) - \(chunkCount) chunks")
    }
    
    // Legacy method - kept for compatibility but not used in streaming implementation
    private func streamFileDataToZip(from fileURL: URL, to zipData: inout Data) throws {
        let chunkSize = 1024 * 1024 // 1MB chunks
        print("ZIP: Starting streaming from \(fileURL.lastPathComponent)")
        
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { 
            fileHandle.closeFile() 
            print("ZIP: Closed file handle for \(fileURL.lastPathComponent)")
        }
        
        var totalBytes = 0
        var chunkCount = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        
        while true {
            let chunkStartTime = CFAbsoluteTimeGetCurrent()
            let chunk = fileHandle.readData(ofLength: chunkSize)
            let chunkReadTime = CFAbsoluteTimeGetCurrent() - chunkStartTime
            
            if chunk.isEmpty { 
                print("ZIP: Reached end of file \(fileURL.lastPathComponent) after \(chunkCount) chunks")
                break 
            }
            
            let appendStartTime = CFAbsoluteTimeGetCurrent()
            zipData.append(chunk)
            let appendTime = CFAbsoluteTimeGetCurrent() - appendStartTime
            
            totalBytes += chunk.count
            chunkCount += 1
            
            // Log progress more frequently for debugging
            if totalBytes % (5 * 1024 * 1024) == 0 || chunkCount % 10 == 0 { // Every 5MB or 10 chunks
                print("ZIP: Chunk \(chunkCount): read \(chunk.count) bytes in \(String(format: "%.3f", chunkReadTime))s, append in \(String(format: "%.3f", appendTime))s, total: \(totalBytes) bytes")
            }
            
            // Check for potential memory issues
            if zipData.count > 100 * 1024 * 1024 { // 100MB threshold
                print("ZIP: WARNING - ZIP data size is now \(zipData.count) bytes (\(zipData.count / (1024*1024))MB)")
            }
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("ZIP: Completed streaming \(totalBytes) bytes from \(fileURL.lastPathComponent) in \(String(format: "%.2f", totalTime))s (\(chunkCount) chunks)")
    }
    
    private func createZipEntryWithStreaming(fileName: String, fileURL: URL, localHeaderOffset: UInt32) throws -> (Data, Data) {
        // Get file size
        let fileSize = try fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber ?? 0
        let fileSizeUInt32 = UInt32(fileSize.uint64Value)
        
        // Calculate CRC32 by streaming through file
        let crc32 = try calculateCRC32Streaming(fileURL: fileURL)
        
        let fileNameData = fileName.data(using: .utf8)!
        
        // Local file header
        var localHeader = Data()
        localHeader.append(Data([0x50, 0x4b, 0x03, 0x04])) // Local file header signature
        localHeader.append(Data([0x14, 0x00])) // Version needed to extract
        localHeader.append(Data([0x00, 0x00])) // General purpose bit flag
        localHeader.append(Data([0x00, 0x00])) // Compression method (stored)
        localHeader.append(Data([0x00, 0x00])) // File last modification time
        localHeader.append(Data([0x00, 0x00])) // File last modification date
        localHeader.append(withUnsafeBytes(of: crc32.littleEndian) { Data($0) }) // CRC-32
        localHeader.append(withUnsafeBytes(of: fileSizeUInt32.littleEndian) { Data($0) }) // Compressed size
        localHeader.append(withUnsafeBytes(of: fileSizeUInt32.littleEndian) { Data($0) }) // Uncompressed size
        localHeader.append(withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Data($0) }) // File name length
        localHeader.append(Data([0x00, 0x00])) // Extra field length
        localHeader.append(fileNameData) // File name
        
        // Central directory entry
        var centralEntry = Data()
        centralEntry.append(Data([0x50, 0x4b, 0x01, 0x02])) // Central file header signature
        centralEntry.append(Data([0x14, 0x00])) // Version made by
        centralEntry.append(Data([0x14, 0x00])) // Version needed to extract
        centralEntry.append(Data([0x00, 0x00])) // General purpose bit flag
        centralEntry.append(Data([0x00, 0x00])) // Compression method
        centralEntry.append(Data([0x00, 0x00])) // File last modification time
        centralEntry.append(Data([0x00, 0x00])) // File last modification date
        centralEntry.append(withUnsafeBytes(of: crc32.littleEndian) { Data($0) }) // CRC-32
        centralEntry.append(withUnsafeBytes(of: fileSizeUInt32.littleEndian) { Data($0) }) // Compressed size
        centralEntry.append(withUnsafeBytes(of: fileSizeUInt32.littleEndian) { Data($0) }) // Uncompressed size
        centralEntry.append(withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Data($0) }) // File name length
        centralEntry.append(Data([0x00, 0x00])) // Extra field length
        centralEntry.append(Data([0x00, 0x00])) // File comment length
        centralEntry.append(Data([0x00, 0x00])) // Disk number start
        centralEntry.append(Data([0x00, 0x00])) // Internal file attributes
        centralEntry.append(Data([0x00, 0x00, 0x00, 0x00])) // External file attributes
        centralEntry.append(withUnsafeBytes(of: localHeaderOffset.littleEndian) { Data($0) }) // Local header offset
        centralEntry.append(fileNameData) // File name
        
        return (localHeader, centralEntry)
    }
    
    private func calculateCRC32Streaming(fileURL: URL) throws -> UInt32 {
        // Use smaller chunks for CRC32 to get more granular timing
        let chunkSize = 256 * 1024 // 256KB chunks
        print("ZIP: Starting optimized CRC32 calculation for \(fileURL.lastPathComponent)")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { 
            fileHandle.closeFile() 
            print("ZIP: CRC32 calculation completed for \(fileURL.lastPathComponent)")
        }
        
        var crc: UInt32 = 0xFFFFFFFF
        var totalBytes = 0
        var chunkCount = 0
        
        // Pre-compute CRC32 lookup table for better performance
        let crcTable = computeCRC32Table()
        
        while true {
            let chunkStartTime = CFAbsoluteTimeGetCurrent()
            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            
            chunkCount += 1
            totalBytes += chunk.count
            
            // Process chunk with lookup table (much faster than bit-by-bit)
            let crcStartTime = CFAbsoluteTimeGetCurrent()
            chunk.withUnsafeBytes { bytes in
                for byte in bytes {
                    let tableIndex = Int((crc ^ UInt32(byte)) & 0xFF)
                    crc = (crc >> 8) ^ crcTable[tableIndex]
                }
            }
            let crcTime = CFAbsoluteTimeGetCurrent() - crcStartTime
            let chunkTime = CFAbsoluteTimeGetCurrent() - chunkStartTime
            
            // Log progress frequently to identify bottlenecks
            if chunkCount % 20 == 0 || totalBytes % (5 * 1024 * 1024) == 0 {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let mbps = elapsed > 0 ? Double(totalBytes) / (1024 * 1024) / elapsed : 0
                print("ZIP: CRC32 chunk \(chunkCount): \(String(format: "%.3f", chunkTime))s total (\(String(format: "%.3f", crcTime))s calc), \(totalBytes / (1024*1024))MB (\(String(format: "%.1f", mbps)) MB/s)")
            }
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let mbps = totalTime > 0 ? Double(totalBytes) / (1024 * 1024) / totalTime : 0
        print("ZIP: CRC32 calculation completed for \(fileURL.lastPathComponent): \(totalBytes) bytes in \(String(format: "%.2f", totalTime))s (\(String(format: "%.1f", mbps)) MB/s) - \(chunkCount) chunks")
        
        return ~crc
    }
    
    private func computeCRC32Table() -> [UInt32] {
        var table = [UInt32](repeating: 0, count: 256)
        let polynomial: UInt32 = 0xEDB88320
        
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ polynomial
                } else {
                    crc >>= 1
                }
            }
            table[i] = crc
        }
        return table
    }
    
    private func createZipEntry(fileName: String, fileData: Data, localHeaderOffset: UInt32) throws -> (Data, Data) {
        let fileNameData = fileName.data(using: .utf8)!
        let crc32 = calculateCRC32(data: fileData)
        
        // Local file header
        var localHeader = Data()
        localHeader.append(Data([0x50, 0x4b, 0x03, 0x04])) // Local file header signature
        localHeader.append(Data([0x14, 0x00])) // Version needed to extract
        localHeader.append(Data([0x00, 0x00])) // General purpose bit flag
        localHeader.append(Data([0x00, 0x00])) // Compression method (stored)
        localHeader.append(Data([0x00, 0x00])) // File last modification time
        localHeader.append(Data([0x00, 0x00])) // File last modification date
        localHeader.append(withUnsafeBytes(of: crc32.littleEndian) { Data($0) }) // CRC-32
        localHeader.append(withUnsafeBytes(of: UInt32(fileData.count).littleEndian) { Data($0) }) // Compressed size
        localHeader.append(withUnsafeBytes(of: UInt32(fileData.count).littleEndian) { Data($0) }) // Uncompressed size
        localHeader.append(withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Data($0) }) // File name length
        localHeader.append(Data([0x00, 0x00])) // Extra field length
        localHeader.append(fileNameData) // File name
        
        // Central directory entry
        var centralEntry = Data()
        centralEntry.append(Data([0x50, 0x4b, 0x01, 0x02])) // Central file header signature
        centralEntry.append(Data([0x14, 0x00])) // Version made by
        centralEntry.append(Data([0x14, 0x00])) // Version needed to extract
        centralEntry.append(Data([0x00, 0x00])) // General purpose bit flag
        centralEntry.append(Data([0x00, 0x00])) // Compression method
        centralEntry.append(Data([0x00, 0x00])) // File last modification time
        centralEntry.append(Data([0x00, 0x00])) // File last modification date
        centralEntry.append(withUnsafeBytes(of: crc32.littleEndian) { Data($0) }) // CRC-32
        centralEntry.append(withUnsafeBytes(of: UInt32(fileData.count).littleEndian) { Data($0) }) // Compressed size
        centralEntry.append(withUnsafeBytes(of: UInt32(fileData.count).littleEndian) { Data($0) }) // Uncompressed size
        centralEntry.append(withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Data($0) }) // File name length
        centralEntry.append(Data([0x00, 0x00])) // Extra field length
        centralEntry.append(Data([0x00, 0x00])) // File comment length
        centralEntry.append(Data([0x00, 0x00])) // Disk number start
        centralEntry.append(Data([0x00, 0x00])) // Internal file attributes
        centralEntry.append(Data([0x00, 0x00, 0x00, 0x00])) // External file attributes
        centralEntry.append(withUnsafeBytes(of: localHeaderOffset.littleEndian) { Data($0) }) // Local header offset
        centralEntry.append(fileNameData) // File name
        
        return (localHeader, centralEntry)
    }
    
    private func createEndOfCentralDirectoryRecord(fileCount: UInt16, centralDirectorySize: UInt32, centralDirectoryOffset: UInt32) -> Data {
        var endRecord = Data()
        endRecord.append(Data([0x50, 0x4b, 0x05, 0x06])) // End of central dir signature
        endRecord.append(Data([0x00, 0x00])) // Number of this disk
        endRecord.append(Data([0x00, 0x00])) // Disk where central directory starts
        endRecord.append(withUnsafeBytes(of: fileCount.littleEndian) { Data($0) }) // Number of central directory records on this disk
        endRecord.append(withUnsafeBytes(of: fileCount.littleEndian) { Data($0) }) // Total number of central directory records
        endRecord.append(withUnsafeBytes(of: centralDirectorySize.littleEndian) { Data($0) }) // Size of central directory
        endRecord.append(withUnsafeBytes(of: centralDirectoryOffset.littleEndian) { Data($0) }) // Offset of central directory
        endRecord.append(Data([0x00, 0x00])) // Comment length
        
        return endRecord
    }
    
    private func calculateCRC32(data: Data) -> UInt32 {
        // Simple CRC32 implementation
        var crc: UInt32 = 0xFFFFFFFF
        let polynomial: UInt32 = 0xEDB88320
        
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ polynomial
                } else {
                    crc >>= 1
                }
            }
        }
        
        return ~crc
    }
    
    private func packageFinalExport(
        note: Note,
        noteData: NotePayload,
        encryptedURL: URL,
        wrappedKey: Data,
        nonce: Data,
        tag: Data,
        keyOwner: String?,
        preferredFileName: String?
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
            
            // Determine note type
            let noteType: String
            if note is TextNote {
                noteType = "text"
            } else if note is ChecklistNote {
                noteType = "checklist"
            } else {
                noteType = "text" // Default fallback for older notes
            }
            
            // Create comprehensive manifest.json with all required fields including note type
            let coreDataTags = note.tags?.compactMap { ($0 as? Tag)?.name } ?? []
            
            // Use Core Data tags if available, otherwise fall back to encrypted payload tags
            let tagsToUse = !coreDataTags.isEmpty ? coreDataTags : noteData.tags
            
            let manifest = [
                "version": "1.0",
                "noteId": note.id?.uuidString ?? "",
                "title": noteData.title,
                "tags": tagsToUse,
                "createdAt": ISO8601DateFormatter().string(from: noteData.createdAt),
                "updatedAt": ISO8601DateFormatter().string(from: noteData.updatedAt),
                "pinned": noteData.pinned,
                "noteType": noteType,
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
            
            // Create final export with safe extension for Gmail compatibility
            let baseFileName = preferredFileName ?? "export_\(UUID().uuidString).memento"
            // Use .zip extension for maximum compatibility with email clients
            let fileName = baseFileName.replacingOccurrences(of: ".memento", with: ".zip")
            print("EXPORT: Using safe filename for email: \(fileName) (was: \(baseFileName))")
            
            // For sharing, use Documents directory which has better app-to-app sharing support
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let shareableExportURL = documentsURL.appendingPathComponent(fileName)
            print("EXPORT: Creating shareable file at: \(shareableExportURL.path) (Documents directory)")
            
            if fileManager.fileExists(atPath: shareableExportURL.path) {
                try fileManager.removeItem(at: shareableExportURL)
                print("EXPORT: Removed existing file at \(shareableExportURL.path)")
            }
            
            try await createZipArchive(contentDir: tempDir, outputURL: shareableExportURL)
            
            // Verify the file was created and get its properties
            guard fileManager.fileExists(atPath: shareableExportURL.path) else {
                print("EXPORT: ERROR - Shareable file does not exist after creation")
                throw ExportError.finalPackagingFailed
            }
            
            let fileAttributes = try fileManager.attributesOfItem(atPath: shareableExportURL.path)
            let fileSize = fileAttributes[.size] as? NSNumber ?? 0
            let filePermissions = fileAttributes[.posixPermissions] as? NSNumber ?? 0
            print("EXPORT: Shareable file created - Size: \(fileSize) bytes, Permissions: \(String(format: "%o", filePermissions.uint16Value))")
            
            // Test file readability
            let testData = try? Data(contentsOf: shareableExportURL, options: [.mappedIfSafe])
            print("EXPORT: File readability test - \(testData != nil ? "SUCCESS" : "FAILED")")
            
            // Check if it's actually a ZIP file by reading the header
            if let headerData = try? Data(contentsOf: shareableExportURL, options: []).prefix(4) {
                let zipHeader = Data([0x50, 0x4b, 0x03, 0x04])
                let isValidZip = headerData == zipHeader
                print("EXPORT: ZIP header validation - \(isValidZip ? "VALID" : "INVALID") (got: \(headerData.map { String(format: "%02x", $0) }.joined(separator: " ")))")
            }
            
            // Also keep a copy in Application Support for local storage
            let finalExportURL = exportsURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: finalExportURL.path) {
                try fileManager.removeItem(at: finalExportURL)
            }
            try await createZipArchive(contentDir: tempDir, outputURL: finalExportURL)
            
            print("EXPORT: Returning shareable URL: \(shareableExportURL.path)")
            return shareableExportURL
            
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