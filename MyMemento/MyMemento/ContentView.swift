//
//  ContentView.swift
//  MyMemento
//
//  Created by James Andrew Myers on 8/21/25.
//

import SwiftUI
import CoreData
import OSLog
import Foundation
import UniformTypeIdentifiers
import CoreLocation

enum SortOption: String, CaseIterable {
    case createdAt = "Created"
    case updatedAt = "Updated" 
    case title = "Title"
    case pinned = "Pinned"
}
struct ExportFileItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var noteIndexViewModel: NoteIndexViewModel
    @StateObject private var errorManager = ErrorManager.shared
    @State private var isDeleteMode = false
    @State private var navigationPath = NavigationPath()
    @State private var showTagList = false
    @State private var showLocationManagement = false
    @State private var showExportDialog = false
    @State private var isExporting = false
    @State private var exportProgress = 0.0
    @State private var exportStatusMessage = ""
    @State private var showImportPicker = false
    @State private var showImportOptions = false
    @State private var isImporting = false
    @State private var importProgress = 0.0
    @State private var importStatusMessage = ""
    @State private var shouldOverwriteExisting = false
    @State private var showNoteTypeSelection = false
    @State private var selectedImportURL: URL?

    @State private var exportedFileURL: URL?
    
    private let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "ContentView")


    

    var body: some View {
        NavigationStack(path: $navigationPath) {
            NoteListWithFiltersView.full(
                allIndices: noteIndexViewModel.indexPayloads,
                navigationTitle: "Notes",
                onTogglePin: togglePinForIndex,
                onDelete: deleteNoteFromIndex,
                onDeleteIndices: deleteIndices
            )
            .navigationDestination(for: IndexPayload.self) { indexPayload in
                NoteEditView(indexPayload: indexPayload)
                    .onDisappear {
                        noteIndexViewModel.refreshIndex(from: viewContext)
                    }
            }
            .toolbar {
                ContentViewToolbar(
                    showTagList: $showTagList,
                    showLocationManagement: $showLocationManagement,
                    showImportPicker: $showImportPicker,
                    showExportDialog: $showExportDialog,
                    isDeleteMode: $isDeleteMode,
                    isImporting: isImporting,
                    isExporting: isExporting,
                    onToggleDeleteMode: toggleDeleteMode,
                    onAddNote: addNote
                )
            }
            .sheet(isPresented: $showTagList) {
                TagBrowserView()
            }
            .sheet(isPresented: $showLocationManagement) {
                LocationManagementView()
            }
            .sheet(isPresented: $showNoteTypeSelection) {
                NoteTypeSelectionView(isPresented: $showNoteTypeSelection) { noteType in
                    createNote(of: noteType)
                }
            }
            .alert("Export Notes", isPresented: $showExportDialog) {
                Button("OK") { exportAllNotesEncrypted() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Export all notes as encrypted zip file?")
            }
            .overlay(
                ProgressOverlayView(
                    isExporting: $isExporting,
                    isImporting: $isImporting,
                    exportProgress: $exportProgress,
                    importProgress: $importProgress,
                    exportStatusMessage: $exportStatusMessage,
                    importStatusMessage: $importStatusMessage
                )
            )
            .sheet(item: Binding<ExportFileItem?>( 
                get: { exportedFileURL.map { ExportFileItem(url: $0) } },
                set: { _ in exportedFileURL = nil } 
            )) { fileItem in 
                ShareSheet(activityItems: [fileItem.url]) 
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false,
                onCompletion: { result in
                    handleImportFile(result)
                }
            )
            .alert("Import Options", isPresented: $showImportOptions) {
                Button("Create New Notes") {
                    shouldOverwriteExisting = false
                    startImport()
                }
                Button("Overwrite Existing Notes") {
                    shouldOverwriteExisting = true
                    startImport()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("How should imported notes be handled?\n\nCreate New Notes: All notes get new IDs\nOverwrite Existing: Notes with matching IDs will be replaced")
            }
            .alert(errorManager.dialogType == .error ? "Error" : "Import Successful!", isPresented: $errorManager.showError) {
                Button("OK") { }
            } message: {
                Text(errorManager.errorMessage)
            }
        }
    }
    
    private func fetchNote(by id: UUID) -> Note? {
        let request: NSFetchRequest<Note> = Note.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        do {
            let notes = try viewContext.fetch(request)
            return notes.first
        } catch {
            logger.error("Failed to fetch note with id \(id.uuidString): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func toggleDeleteMode() {
        withAnimation {
            isDeleteMode.toggle()
        }
    }
    
    
    private func togglePinForIndex(_ indexPayload: IndexPayload) {
        guard let note = fetchNote(by: indexPayload.id) else { return }

        withAnimation {
            note.isPinned.toggle()

            // Also update the SearchIndex
            let searchIndexRequest: NSFetchRequest<SearchIndex> = SearchIndex.fetchRequest()
            searchIndexRequest.predicate = NSPredicate(format: "id == %@", indexPayload.id as CVarArg)

            do {
                if let searchIndex = try viewContext.fetch(searchIndexRequest).first,
                   let encryptedData = searchIndex.encryptedIndexData {
                    
                    let encryptionKey = try KeyManager.shared.getEncryptionKey()
                    
                    // Decrypt, update, re-encrypt
                    var decryptedPayload = try CryptoHelper.decrypt(encryptedData, key: encryptionKey, as: IndexPayload.self)
                    decryptedPayload.pinned = note.isPinned
                    
                    let encryptedIndexData = try CryptoHelper.encrypt(decryptedPayload, key: encryptionKey)
                    searchIndex.encryptedIndexData = encryptedIndexData
                }

                try viewContext.save()
                
                // Refresh the index to reflect the pin status change
                noteIndexViewModel.refreshIndex(from: viewContext)

            } catch {
                let nsError = error as NSError
                errorManager.handleCoreDataError(nsError, context: "Failed to update note pin status or search index")
            }
        }
    }
        

    
    private func deleteNoteFromIndex(_ indexPayload: IndexPayload) {
        guard let note = fetchNote(by: indexPayload.id) else { return }

        withAnimation {
            // Capture tags before deleting the note
            let associatedTags = Array(note.tags as? Set<Tag> ?? Set<Tag>())

            Task { @MainActor in
                // Clean up attachments (files + Core Data)
                do {
                    try await AttachmentManager.cleanupForDeletedNote(note: note, context: viewContext)
                } catch {
                    // Already reported via ErrorManager; continue with best-effort deletion
                }

                // Delete the corresponding SearchIndex
                let searchIndexRequest: NSFetchRequest<SearchIndex> = SearchIndex.fetchRequest()
                searchIndexRequest.predicate = NSPredicate(format: "id == %@", indexPayload.id as CVarArg)

                do {
                    let searchIndices = try viewContext.fetch(searchIndexRequest)
                    searchIndices.forEach(viewContext.delete)

                    viewContext.delete(note)
                    try viewContext.save()

                    // Clean up orphaned tags after the note is deleted and saved
                    for tag in associatedTags {
                        TagManager.handleTagRemovedFromNote(tag, in: viewContext)
                    }

                    // Refresh the index
                    noteIndexViewModel.refreshIndex(from: viewContext)

                } catch {
                    let nsError = error as NSError
                    errorManager.handleCoreDataError(nsError, context: "Failed to delete note")
                }
            }
        }
    }
    

    private func addNote() {
        showNoteTypeSelection = true
    }

    private func createNote(of type: NoteType) {
        let noteId = NoteIDManager.generateNoteID()
        let now = Date()
        
        // Create the actual Note entity based on type
        let note: Note
        switch type {
        case .text:
            note = TextNote(context: viewContext)
        case .checklist:
            note = ChecklistNote(context: viewContext)
        }
        
        note.id = noteId
        note.createdAt = now
        note.isPinned = false
        
        // Save the new note to Core Data
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            errorManager.handleCoreDataError(nsError, context: "Failed to create new note")
            return
        }
        
        // Create a temporary IndexPayload for navigation
        let newIndexPayload = IndexPayload(
            id: noteId,
            title: "New Note",
            tags: [],
            summary: "",
            createdAt: now,
            updatedAt: now,
            pinned: false
        )
        
        navigationPath.append(newIndexPayload)
    }

    private func deleteIndices(offsets: IndexSet) {
        withAnimation {
            let indicesToDelete = offsets.map { noteIndexViewModel.indexPayloads[$0] }
            
            // Capture all tags from notes before deletion
            var allAssociatedTags = Set<Tag>()
            var notesToDelete: [Note] = []
            
            for indexPayload in indicesToDelete {
                guard let note = fetchNote(by: indexPayload.id) else { continue }
                notesToDelete.append(note)
                if let tags = note.tags as? Set<Tag> {
                    allAssociatedTags.formUnion(tags)
                }
            }

            Task { @MainActor in
                // Clean up attachments for each note (best effort)
                for note in notesToDelete {
                    do { try await AttachmentManager.cleanupForDeletedNote(note: note, context: viewContext) } catch { }
                }

                // Delete corresponding SearchIndex entities
                for indexPayload in indicesToDelete {
                    let searchIndexRequest: NSFetchRequest<SearchIndex> = SearchIndex.fetchRequest()
                    searchIndexRequest.predicate = NSPredicate(format: "id == %@", indexPayload.id as CVarArg)

                    do {
                        let searchIndices = try viewContext.fetch(searchIndexRequest)
                        searchIndices.forEach(viewContext.delete)
                    } catch {
                        logger.error("Failed to fetch SearchIndex for deletion: \(error.localizedDescription)")
                    }
                }

                notesToDelete.forEach(viewContext.delete)

                do {
                    try viewContext.save()

                    // Clean up orphaned tags after notes are deleted and saved
                    for tag in allAssociatedTags {
                        TagManager.handleTagRemovedFromNote(tag, in: viewContext)
                    }

                    // Refresh the index
                    noteIndexViewModel.refreshIndex(from: viewContext)

                } catch {
                    let nsError = error as NSError
                    errorManager.handleCoreDataError(nsError, context: "Failed to delete notes")
                }
            }
        }
    }

    
    private func exportAllNotesEncrypted() {
        guard !noteIndexViewModel.indexPayloads.isEmpty else {
            errorManager.handleError(NSError(domain: "ExportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No notes to export"]), context: "Export failed")
            return
        }
        
        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = "Preparing export..."
        
        Task { @MainActor in
            do {
                let notes = try await fetchAllNotesForExport()
                await exportNotesAsEncryptedZip(notes: notes)
            } catch {
                isExporting = false
                exportProgress = 0.0
                exportStatusMessage = ""
                errorManager.handleError(error, context: "Failed to export notes")
            }
        }
    }
    
    private func fetchAllNotesForExport() async throws -> [Note] {
        let request: NSFetchRequest<Note> = Note.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)]
        return try viewContext.fetch(request)
    }
    
    private func exportNotesAsEncryptedZip(notes: [Note]) async {
        do {
            exportProgress = 0.1
            exportStatusMessage = "Getting encryption key..."
            
            // Use the local export key for the bulk export
            let publicKeyData = try KeyManager.shared.getExportPublicKeyData()
            
            exportProgress = 0.2
            exportStatusMessage = "Creating temporary workspace..."
            
            // Create temporary directory structure
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }
            
            let notesDir = tempDir.appendingPathComponent("notes")
            try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
            
            exportProgress = 0.3
            exportStatusMessage = "Encrypting \(notes.count) notes..."
            
            // Export each note as an individual encrypted file
            let totalNotes = Double(notes.count)
            for (index, note) in notes.enumerated() {
                let noteProgress = Double(index) / totalNotes
                let overallProgress = 0.3 + (noteProgress * 0.5) // 30% to 80% for note processing
                exportProgress = overallProgress
                
                let noteTitle = await getNoteTitle(note)
                exportStatusMessage = "Encrypting: \(noteTitle)"
                
                let encryptedNoteURL = try await exportSingleNoteEncrypted(
                    note: note, 
                    publicKeyData: publicKeyData, 
                    outputDir: notesDir
                )
                
                logger.info("Exported encrypted note: \(encryptedNoteURL.lastPathComponent)")
            }
            
            exportProgress = 0.8
            exportStatusMessage = "Creating final zip archive..."
            
            // Create the final zero-compression zip file
            let finalZipURL = try await createFinalZipArchive(contentDir: tempDir)
            
            exportProgress = 1.0
            exportStatusMessage = "Export completed!"
            
            // Move to documents directory for sharing
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let finalFileName = "MyMemento_Encrypted_Export_\(dateFormatter.string(from: Date())).zip"
            let shareableURL = documentsURL.appendingPathComponent(finalFileName)
            
            if FileManager.default.fileExists(atPath: shareableURL.path) {
                try FileManager.default.removeItem(at: shareableURL)
            }
            
            try FileManager.default.moveItem(at: finalZipURL, to: shareableURL)
            
            exportedFileURL = shareableURL
            isExporting = false
            exportStatusMessage = ""
            
        } catch {
            isExporting = false
            exportProgress = 0.0
            exportStatusMessage = ""
            errorManager.handleError(error, context: "Encrypted export failed")
        }
    }
    
    private func getNoteTitle(_ note: Note) async -> String {
        do {
            guard let encryptedData = note.encryptedData else { return "Untitled Note" }
            let encryptionKey = try KeyManager.shared.getEncryptionKey()
            let payload = try CryptoHelper.decrypt(encryptedData, key: encryptionKey, as: NotePayload.self)
            return payload.title.isEmpty ? "Untitled Note" : payload.title
        } catch {
            return "Untitled Note"
        }
    }
    
    private func exportSingleNoteEncrypted(note: Note, publicKeyData: Data, outputDir: URL) async throws -> URL {
        // Use ExportManager to create individual encrypted note files
        let exportManager = ExportManager.shared
        let encryptedNoteURL = try await exportManager.export(note: note, publicKey: publicKeyData)
        
        // Move to our output directory with a cleaner filename
        let noteId = note.id?.uuidString ?? UUID().uuidString
        let cleanFileName = "note_\(noteId).memento"
        let finalURL = outputDir.appendingPathComponent(cleanFileName)
        
        try FileManager.default.moveItem(at: encryptedNoteURL, to: finalURL)
        return finalURL
    }
    
    private func createFinalZipArchive(contentDir: URL) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("encrypted_export_\(UUID().uuidString).zip")
        
        // Use the existing zip creation logic but ensure zero compression
        try await createZeroCompressionZip(from: contentDir, to: outputURL)
        
        return outputURL
    }
    
    private func createZeroCompressionZip(from contentDir: URL, to outputURL: URL) async throws {
        // Create ZIP file with no compression (store only)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let writeHandle = try FileHandle(forWritingTo: outputURL)
        defer { writeHandle.closeFile() }
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: contentDir, 
            includingPropertiesForKeys: [.isDirectoryKey], 
            options: []
        )
        
        var centralDirectoryData = Data()
        var fileCount: UInt16 = 0
        var currentOffset: UInt32 = 0
        
        // Process each item (notes directory)
        for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDirectory = try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            
            if isDirectory {
                // Process files in the directory
                let subContents = try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                
                for subItem in subContents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let relativePath = "\(item.lastPathComponent)/\(subItem.lastPathComponent)"
                    let (localHeaderData, centralEntryData) = try processFileForZeroCompressionZip(
                        fileURL: subItem,
                        fileName: relativePath,
                        localHeaderOffset: currentOffset,
                        writeHandle: writeHandle
                    )
                    
                    let fileSize = try FileManager.default.attributesOfItem(atPath: subItem.path)[.size] as? NSNumber ?? 0
                    currentOffset += UInt32(localHeaderData.count) + fileSize.uint32Value
                    centralDirectoryData.append(centralEntryData)
                    fileCount += 1
                }
            }
        }
        
        // Write central directory
        let centralDirectoryOffset = currentOffset
        writeHandle.write(centralDirectoryData)
        
        // Write end of central directory record
        let endRecord = createEndOfCentralDirectoryRecord(
            fileCount: fileCount,
            centralDirectorySize: UInt32(centralDirectoryData.count),
            centralDirectoryOffset: centralDirectoryOffset
        )
        writeHandle.write(endRecord)
    }
    
    private func processFileForZeroCompressionZip(
        fileURL: URL,
        fileName: String,
        localHeaderOffset: UInt32,
        writeHandle: FileHandle
    ) throws -> (Data, Data) {
        // Get file size
        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber ?? 0
        let fileSizeUInt32 = UInt32(fileSize.uint64Value)
        
        // Calculate CRC32
        let crc32 = try calculateCRC32(fileURL: fileURL)
        
        // Create local header with STORE method (no compression)
        let fileNameData = fileName.data(using: .utf8)!
        var localHeader = Data()
        localHeader.append(Data([0x50, 0x4b, 0x03, 0x04])) // Local file header signature
        localHeader.append(Data([0x14, 0x00])) // Version needed to extract
        localHeader.append(Data([0x00, 0x00])) // General purpose bit flag
        localHeader.append(Data([0x00, 0x00])) // Compression method (0 = store, no compression)
        localHeader.append(Data([0x00, 0x00])) // File last modification time
        localHeader.append(Data([0x00, 0x00])) // File last modification date
        localHeader.append(withUnsafeBytes(of: crc32.littleEndian) { Data($0) }) // CRC-32
        localHeader.append(withUnsafeBytes(of: fileSizeUInt32.littleEndian) { Data($0) }) // Compressed size
        localHeader.append(withUnsafeBytes(of: fileSizeUInt32.littleEndian) { Data($0) }) // Uncompressed size
        localHeader.append(withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Data($0) }) // File name length
        localHeader.append(Data([0x00, 0x00])) // Extra field length
        localHeader.append(fileNameData) // File name
        
        // Write local header
        writeHandle.write(localHeader)
        
        // Write file data directly (no compression)
        let readHandle = try FileHandle(forReadingFrom: fileURL)
        defer { readHandle.closeFile() }
        
        let chunkSize = 64 * 1024
        while true {
            let chunk = readHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            writeHandle.write(chunk)
        }
        
        // Create central directory entry
        var centralEntry = Data()
        centralEntry.append(Data([0x50, 0x4b, 0x01, 0x02])) // Central file header signature
        centralEntry.append(Data([0x14, 0x00])) // Version made by
        centralEntry.append(Data([0x14, 0x00])) // Version needed to extract
        centralEntry.append(Data([0x00, 0x00])) // General purpose bit flag
        centralEntry.append(Data([0x00, 0x00])) // Compression method (0 = store)
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
    
    private func calculateCRC32(fileURL: URL) throws -> UInt32 {
        let chunkSize = 64 * 1024
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { fileHandle.closeFile() }
        
        var crc: UInt32 = 0xFFFFFFFF
        let polynomial: UInt32 = 0xEDB88320
        
        while true {
            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            
            for byte in chunk {
                crc ^= UInt32(byte)
                for _ in 0..<8 {
                    if crc & 1 != 0 {
                        crc = (crc >> 1) ^ polynomial
                    } else {
                        crc >>= 1
                    }
                }
            }
        }
        
        return ~crc
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
    
    // MARK: - Import Functions
    
    private func handleImportFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Start accessing security-scoped resource for file picker URLs
            guard url.startAccessingSecurityScopedResource() else {
                errorManager.handleError(
                    NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access selected file. Please try again."]),
                    context: "Failed to access security-scoped resource"
                )
                return
            }
            
            // Store the selected file URL and show options dialog
            selectedImportURL = url
            showImportOptions = true
            
        case .failure(let error):
            errorManager.handleError(error, context: "Failed to select import file")
        }
    }
    
    private func startImport() {
        guard selectedImportURL != nil else { return }
        
        isImporting = true
        importProgress = 0.0
        importStatusMessage = "Preparing import..."
        
        Task { @MainActor in
            do {
                try await importNotesFromFile(selectedImportURL!)
            } catch {
                isImporting = false
                importProgress = 0.0
                importStatusMessage = ""
                
                // Stop accessing security-scoped resource
                selectedImportURL?.stopAccessingSecurityScopedResource()
                selectedImportURL = nil
                
                errorManager.handleError(error, context: "Import failed")
            }
        }
    }
    
    private func importNotesFromFile(_ fileURL: URL) async throws {
        importProgress = 0.1
        importStatusMessage = "Reading import file..."
        
        // Create temporary directory for extraction
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        importProgress = 0.2
        importStatusMessage = "Extracting notes..."
        
        // Extract ZIP file
        try await extractZipFile(from: fileURL, to: tempDir)
        
        importProgress = 0.3
        importStatusMessage = "Decrypting notes..."
        
        // Find all .memento files in the extracted content
        let notesDir = tempDir.appendingPathComponent("notes")
        guard FileManager.default.fileExists(atPath: notesDir.path) else {
            throw NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid import file: no notes directory found"])
        }
        
        let mementoFiles = try FileManager.default.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "memento" }
        
        guard !mementoFiles.isEmpty else {
            throw NSError(domain: "ImportError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No encrypted notes found in import file"])
        }
        
        importProgress = 0.4
        importStatusMessage = "Processing \(mementoFiles.count) notes..."
        
        // Get local decryption key
        let privateKeyData = try KeyManager.shared.getExportPrivateKeyData()
        
        // Process each note
        let totalNotes = Double(mementoFiles.count)
        var importedCount = 0
        var overwrittenCount = 0
        
        for (index, mementoFile) in mementoFiles.enumerated() {
            let noteProgress = Double(index) / totalNotes
            let overallProgress = 0.4 + (noteProgress * 0.5) // 40% to 90% for note processing
            importProgress = overallProgress
            
            importStatusMessage = "Importing note \(index + 1) of \(mementoFiles.count)..."
            
            do {
                let wasOverwritten = try await importSingleNote(from: mementoFile, privateKey: privateKeyData)
                if wasOverwritten {
                    overwrittenCount += 1
                } else {
                    importedCount += 1
                }
            } catch {
                logger.error("Failed to import note from \(mementoFile.lastPathComponent): \(error.localizedDescription)")
                // Continue with other notes
            }
        }
        
        importProgress = 0.9
        importStatusMessage = "Finalizing import..."
        
        // Save context (database constraint will handle uniqueness)
        try viewContext.save()
        
        // Refresh the index
        noteIndexViewModel.refreshIndex(from: viewContext)
        
        importProgress = 1.0
        importStatusMessage = "Import completed!"
        
        // Show completion message
        let message = shouldOverwriteExisting ? 
            "Imported \(importedCount) new notes and overwrote \(overwrittenCount) existing notes." :
            "Imported \(importedCount + overwrittenCount) notes with new IDs."
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isImporting = false
            self.importStatusMessage = ""
            
            // Stop accessing security-scoped resource
            self.selectedImportURL?.stopAccessingSecurityScopedResource()
            self.selectedImportURL = nil
            
            // Show success alert
            self.errorManager.handleSuccess(message, context: "Import completed successfully")
        }
    }
    
    private func extractZipFile(from zipURL: URL, to destinationURL: URL) async throws {
        // Create destination directory if it doesn't exist
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        
        // Since iOS doesn't have built-in ZIP extraction, we'll implement basic ZIP reading
        // This is a simplified implementation for .memento and basic ZIP files
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.extractZipFileManually(from: zipURL, to: destinationURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: NSError(domain: "ImportError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to extract zip file: \(error.localizedDescription)"]))
                }
            }
        }
    }
    
    private func extractZipFileManually(from zipURL: URL, to destinationURL: URL) throws {
        // Read ZIP file data
        let zipData = try Data(contentsOf: zipURL)
        guard zipData.count > 22 else { // Minimum ZIP file size (end of central directory)
            throw NSError(domain: "ImportError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid ZIP file: too small"])
        }
        
        // Find End of Central Directory Record (EOCD)
        guard let eocdOffset = findEndOfCentralDirectoryRecord(in: zipData) else {
            throw NSError(domain: "ImportError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid ZIP file: no end of central directory"])
        }
        
        // Parse EOCD
        let eocdData = zipData.subdata(in: eocdOffset..<zipData.count)
        let centralDirectoryEntries = UInt16(eocdData[8]) | (UInt16(eocdData[9]) << 8)
        let _ = UInt32(eocdData[12]) | (UInt32(eocdData[13]) << 8) | (UInt32(eocdData[14]) << 16) | (UInt32(eocdData[15]) << 24) // centralDirectorySize (unused)
        let centralDirectoryOffset = UInt32(eocdData[16]) | (UInt32(eocdData[17]) << 8) | (UInt32(eocdData[18]) << 16) | (UInt32(eocdData[19]) << 24)
        
        // Read central directory
        var currentOffset = Int(centralDirectoryOffset)
        for _ in 0..<centralDirectoryEntries {
            guard currentOffset + 46 <= zipData.count else { break }
            
            let cdData = zipData.subdata(in: currentOffset..<min(currentOffset + 46, zipData.count))
            
            // Verify central directory signature
            let signature = UInt32(cdData[0]) | (UInt32(cdData[1]) << 8) | (UInt32(cdData[2]) << 16) | (UInt32(cdData[3]) << 24)
            guard signature == 0x02014b50 else { continue }
            
            let compressionMethod = UInt16(cdData[10]) | (UInt16(cdData[11]) << 8)
            let compressedSize = UInt32(cdData[20]) | (UInt32(cdData[21]) << 8) | (UInt32(cdData[22]) << 16) | (UInt32(cdData[23]) << 24)
            let _ = UInt32(cdData[24]) | (UInt32(cdData[25]) << 8) | (UInt32(cdData[26]) << 16) | (UInt32(cdData[27]) << 24) // uncompressedSize (unused)
            let fileNameLength = UInt16(cdData[28]) | (UInt16(cdData[29]) << 8)
            let extraFieldLength = UInt16(cdData[30]) | (UInt16(cdData[31]) << 8)
            let commentLength = UInt16(cdData[32]) | (UInt16(cdData[33]) << 8)
            let localHeaderOffset = UInt32(cdData[42]) | (UInt32(cdData[43]) << 8) | (UInt32(cdData[44]) << 16) | (UInt32(cdData[45]) << 24)
            
            // Read filename
            let filenameRange = (currentOffset + 46)..<(currentOffset + 46 + Int(fileNameLength))
            guard filenameRange.upperBound <= zipData.count else { continue }
            let filenameData = zipData.subdata(in: filenameRange)
            guard let filename = String(data: filenameData, encoding: .utf8) else { continue }
            
            // Skip directories
            guard !filename.hasSuffix("/") else {
                currentOffset += 46 + Int(fileNameLength) + Int(extraFieldLength) + Int(commentLength)
                continue
            }
            
            // Read local file header to get actual file data
            let localHeaderStart = Int(localHeaderOffset)
            guard localHeaderStart + 30 <= zipData.count else { continue }
            
            let localHeaderData = zipData.subdata(in: localHeaderStart..<(localHeaderStart + 30))
            let localFileNameLength = UInt16(localHeaderData[26]) | (UInt16(localHeaderData[27]) << 8)
            let localExtraFieldLength = UInt16(localHeaderData[28]) | (UInt16(localHeaderData[29]) << 8)
            
            let fileDataStart = localHeaderStart + 30 + Int(localFileNameLength) + Int(localExtraFieldLength)
            let fileDataEnd = fileDataStart + Int(compressedSize)
            
            guard fileDataEnd <= zipData.count else { continue }
            
            let compressedData = zipData.subdata(in: fileDataStart..<fileDataEnd)
            
            // Only support uncompressed files for now
            guard compressionMethod == 0 else {
                logger.warning("Skipping compressed file: \(filename)")
                currentOffset += 46 + Int(fileNameLength) + Int(extraFieldLength) + Int(commentLength)
                continue
            }
            
            // Create output file
            let outputURL = destinationURL.appendingPathComponent(filename)
            let outputDir = outputURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
            
            try compressedData.write(to: outputURL)
            
            currentOffset += 46 + Int(fileNameLength) + Int(extraFieldLength) + Int(commentLength)
        }
    }
    
    private func findEndOfCentralDirectoryRecord(in data: Data) -> Int? {
        // EOCD signature: 0x06054b50
        let signature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        
        // Search backwards from the end of the file
        for i in stride(from: data.count - 22, through: 0, by: -1) {
            if i + 4 <= data.count {
                let potentialSignature = data.subdata(in: i..<(i + 4))
                if potentialSignature.elementsEqual(signature) {
                    return i
                }
            }
        }
        
        return nil
    }
    
    private func importSingleNote(from mementoURL: URL, privateKey: Data) async throws -> Bool {
        // Create temporary directory for this note
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Extract the .memento file (which is a zip)
        try await extractZipFile(from: mementoURL, to: tempDir)
        
        // Read manifest.json
        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw NSError(domain: "ImportError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid note file: missing manifest"])
        }
        
        let manifestData = try Data(contentsOf: manifestURL)
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
            throw NSError(domain: "ImportError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid manifest format"])
        }
        
        
        // Extract note metadata including noteType (with backward compatibility)
        guard let noteIdString = manifest["noteId"] as? String,
              let noteId = UUID(uuidString: noteIdString),
              let title = manifest["title"] as? String,
              let tags = manifest["tags"] as? [String],
              let createdAtString = manifest["createdAt"] as? String,
              let updatedAtString = manifest["updatedAt"] as? String,
              let pinned = manifest["pinned"] as? Bool,
              let crypto = manifest["crypto"] as? [String: Any],
              let nonceString = crypto["nonce"] as? String,
              let tagString = crypto["tag"] as? String else {
            throw NSError(domain: "ImportError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid manifest data"])
        }
        
        // Extract note type with backward compatibility
        let noteTypeString = manifest["noteType"] as? String ?? "text" // Default to text for older exports
        
        // Parse dates
        let iso8601Formatter = ISO8601DateFormatter()
        guard let createdAt = iso8601Formatter.date(from: createdAtString),
              let updatedAt = iso8601Formatter.date(from: updatedAtString) else {
            throw NSError(domain: "ImportError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid date format in manifest"])
        }
        
        // Decrypt the note content
        let encryptedURL = tempDir.appendingPathComponent("export.enc")
        let keyURL = tempDir.appendingPathComponent("key.enc")
        
        guard FileManager.default.fileExists(atPath: encryptedURL.path),
              FileManager.default.fileExists(atPath: keyURL.path) else {
            throw NSError(domain: "ImportError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Missing encrypted content files"])
        }
        
        // Unwrap the AES key with our private key
        let wrappedKey = try Data(contentsOf: keyURL)
        let aesKey = try CryptoHelper.unwrapExportKey(wrappedKey: wrappedKey, with: privateKey)
        
        // Decrypt the content
        let nonce = Data(base64Encoded: nonceString)!
        let tag = Data(base64Encoded: tagString)!
        let decryptedURL = try await CryptoHelper.decryptExportBundle(
            encryptedURL: encryptedURL,
            key: aesKey,
            nonce: nonce,
            tag: tag
        )
        
        // Extract the decrypted content
        let contentDir = tempDir.appendingPathComponent("content")
        try await extractZipFile(from: decryptedURL, to: contentDir)
        
        // Read body.html
        let bodyURL = contentDir.appendingPathComponent("body.html")
        guard FileManager.default.fileExists(atPath: bodyURL.path) else {
            throw NSError(domain: "ImportError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Missing note body content"])
        }
        
        let htmlString = try String(contentsOf: bodyURL, encoding: .utf8)
        
        // Convert HTML back to NSAttributedString
        guard let htmlData = htmlString.data(using: .utf8) else {
            throw NSError(domain: "ImportError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid HTML content"])
        }
        
        let attributedString = try NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
        
        // Check if note with this ID already exists
        let existingNote = fetchNote(by: noteId)
        let note: Note
        var wasOverwritten = false
        
        if let existing = existingNote, shouldOverwriteExisting {
            // Overwrite existing note
            note = existing
            wasOverwritten = true
            
            // Clean up existing attachments before importing new ones
            if let existingAttachments = note.attachments as? Set<Attachment> {
                for attachment in existingAttachments {
                    try await AttachmentManager.shared.deleteAttachment(attachment, context: viewContext)
                }
            }
        } else {
            // Create new note with proper type based on manifest
            switch noteTypeString {
            case "text":
                note = TextNote(context: viewContext)
            case "checklist":
                note = ChecklistNote(context: viewContext)
            default:
                // Default to TextNote for unknown types
                note = TextNote(context: viewContext)
            }
            
            // Generate new ID to avoid uniqueness constraint violations when creating new notes
            if existingNote != nil && !shouldOverwriteExisting {
                // Note exists but we're not overwriting, so generate a new ID
                note.id = NoteIDManager.generateNoteID()
            } else {
                // Use the imported note's ID (either no existing note or we would overwrite)
                note.id = noteId
            }
            note.createdAt = createdAt
        }
        
        // Update note properties
        note.isPinned = pinned
        
        // Create note payload
        let notePayload = NotePayload(
            title: title,
            body: NSAttributedStringWrapper(attributedString),
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            pinned: pinned
        )
        
        // Encrypt and save
        let encryptionKey = try KeyManager.shared.getEncryptionKey()
        let encryptedData = try CryptoHelper.encrypt(notePayload, key: encryptionKey)
        note.encryptedData = encryptedData
        
        // Handle tags - create or find existing tags
        var tagEntities: [Tag] = []
        for tagName in tags {
            let request: NSFetchRequest<Tag> = Tag.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@", tagName)
            
            if let existingTag = try viewContext.fetch(request).first {
                tagEntities.append(existingTag)
            } else {
                let newTag = Tag(context: viewContext)
                newTag.id = UUID()
                newTag.name = tagName
                newTag.createdAt = Date()
                tagEntities.append(newTag)
            }
        }
        
        note.tags = NSSet(array: tagEntities)
        
        // Create or update search index
        let indexPayload = IndexPayload(
            id: note.id!,
            title: title,
            tags: tags,
            summary: attributedString.string.prefix(200).description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            pinned: pinned
        )
        
        // Check if SearchIndex already exists for this note ID
        let searchIndexRequest: NSFetchRequest<SearchIndex> = SearchIndex.fetchRequest()
        searchIndexRequest.predicate = NSPredicate(format: "id == %@", note.id! as CVarArg)
        
        let searchIndex: SearchIndex
        if let existingSearchIndex = try viewContext.fetch(searchIndexRequest).first {
            // Update existing SearchIndex
            searchIndex = existingSearchIndex
            logger.debug("Updating existing SearchIndex for note \(note.id?.uuidString ?? "unknown")")
        } else {
            // Create new SearchIndex with the note's ID (which may be newly generated)
            searchIndex = SearchIndex(context: viewContext)
            searchIndex.id = note.id
            logger.debug("Creating new SearchIndex for note \(note.id?.uuidString ?? "unknown")")
        }
        
        let encryptedIndexData = try CryptoHelper.encrypt(indexPayload, key: encryptionKey)
        searchIndex.encryptedIndexData = encryptedIndexData
        
        // Import checklist items if this is a ChecklistNote and checklist.json exists
        if let checklistNote = note as? ChecklistNote {
            let checklistURL = contentDir.appendingPathComponent("checklist.json")
            if FileManager.default.fileExists(atPath: checklistURL.path) {
                let checklistData = try Data(contentsOf: checklistURL)
                if let checklistItems = try JSONSerialization.jsonObject(with: checklistData) as? [NSDictionary] {
                    checklistNote.items = checklistItems as NSArray
                }
            }
        }
        
        // Import attachments if present
        // Note: For overwritten notes, existing attachments are already cleaned up above
        let attachmentsDir = contentDir.appendingPathComponent("attachments")
        if FileManager.default.fileExists(atPath: attachmentsDir.path) {
            try await importAttachments(from: attachmentsDir, to: note)
        }
        
        return wasOverwritten
    }
    
    private func importAttachments(from attachmentsDir: URL, to note: Note) async throws {
        let attachmentFiles = try FileManager.default.contentsOfDirectory(at: attachmentsDir, includingPropertiesForKeys: nil)
        
        for attachmentFile in attachmentFiles {
            // let fileName = attachmentFile.lastPathComponent // Unused variable
            let fileExtension = attachmentFile.pathExtension.lowercased()
            
            // Determine attachment type and create appropriate attachment
            if ["mp4", "mov", "avi"].contains(fileExtension) {
                _ = try await AttachmentManager.shared.createVideoAttachment(
                    for: note,
                    from: attachmentFile,
                    context: viewContext
                )
            } else if ["mp3", "m4a", "wav"].contains(fileExtension) {
                _ = try await AttachmentManager.shared.createAudioAttachment(
                    for: note,
                    from: attachmentFile,
                    context: viewContext
                )
            } else if fileExtension == "json" && attachmentFile.lastPathComponent.hasPrefix("location_") {
                try await importLocationAttachment(from: attachmentFile, to: note)
            }
            // Skip unknown file types
        }
    }
    
    private func importLocationAttachment(from jsonFile: URL, to note: Note) async throws {
        // Read and parse the JSON file
        let jsonData = try Data(contentsOf: jsonFile)
        guard let locationData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(domain: "ImportError", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid location JSON format"])
        }
        
        // Extract required location data
        guard let locationIdString = locationData["id"] as? String,
              let locationId = UUID(uuidString: locationIdString),
              let name = locationData["name"] as? String,
              let latitude = locationData["latitude"] as? Double,
              let longitude = locationData["longitude"] as? Double else {
            print("Import: Invalid location data in JSON file: \(jsonFile.lastPathComponent)")
            return
        }
        
        // Create or find existing location
        let locationManager = LocationManager(context: viewContext, keyManager: KeyManager.shared)
        
        // Check if location already exists
        let existingLocation = try locationManager.fetchLocation(by: locationId)
        let location: Location
        
        if let existing = existingLocation {
            // Use existing location
            location = existing
            print("Import: Using existing location: \(name)")
        } else {
            // Create new location
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let altitude = locationData["altitude"] as? Double
            let horizontalAccuracy = locationData["horizontalAccuracy"] as? Double
            let verticalAccuracy = locationData["verticalAccuracy"] as? Double
            
            // Create placemark data if available
            var placemark: LocationPlacemarkPayload?
            if let placemarkData = locationData["placemark"] as? [String: Any] {
                placemark = LocationPlacemarkPayload(
                    thoroughfare: placemarkData["thoroughfare"] as? String,
                    subThoroughfare: placemarkData["subThoroughfare"] as? String,
                    locality: placemarkData["locality"] as? String,
                    subLocality: placemarkData["subLocality"] as? String,
                    administrativeArea: placemarkData["administrativeArea"] as? String,
                    subAdministrativeArea: placemarkData["subAdministrativeArea"] as? String,
                    postalCode: placemarkData["postalCode"] as? String,
                    country: placemarkData["country"] as? String,
                    countryCode: placemarkData["countryCode"] as? String,
                    timeZone: placemarkData["timeZone"] as? String
                )
            }
            
            location = try locationManager.saveLocation(
                name: name,
                coordinate: coordinate,
                placemark: placemark,
                altitude: altitude,
                horizontalAccuracy: horizontalAccuracy,
                verticalAccuracy: verticalAccuracy
            )
            
            // Set the original ID and creation date if available
            location.id = locationId
            if let createdAtString = locationData["createdAt"] as? String,
               let createdAt = ISO8601DateFormatter().date(from: createdAtString) {
                location.createdAt = createdAt
            }
            
            try viewContext.save()
            print("Import: Created new location: \(name)")
        }
        
        // Create location attachment
        _ = try await AttachmentManager.shared.createLocationAttachment(
            for: note,
            from: location,
            context: viewContext
        )
        
        print("Import: Successfully imported location attachment: \(name)")
    }
}

// MARK: - Note Type Selection

enum NoteType: String, CaseIterable {
    case text = "Text Note"
    case checklist = "Checklist"
    
    var systemImage: String {
        switch self {
        case .text:
            return "doc.text"
        case .checklist:
            return "checklist"
        }
    }
    
    var description: String {
        switch self {
        case .text:
            return "Create a rich text note with formatting"
        case .checklist:
            return "Create a checklist with items to check off"
        }
    }
}

struct NoteTypeSelectionView: View {
    @Binding var isPresented: Bool
    let onSelection: (NoteType) -> Void
    
    var body: some View {
        NavigationView {
            List(NoteType.allCases, id: \.self) { noteType in
                Button(action: {
                    onSelection(noteType)
                    isPresented = false
                }) {
                    HStack(spacing: 16) {
                        Image(systemName: noteType.systemImage)
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(noteType.rawValue)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(noteType.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Choose Note Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}



#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
