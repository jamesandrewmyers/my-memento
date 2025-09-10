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
    @State private var searchText = ""
    @State private var filteredIndices: [IndexPayload] = []
    @State private var isSearching = false
    @State private var isDeleteMode = false
    @State private var navigationPath = NavigationPath()
    @State private var showTagSuggestions = false
    @State private var tagSuggestions: [String] = []
    @State private var justSelectedTag = false
    @State private var lastSearchTextAfterSelection = ""
    @State private var sortOption: SortOption = .createdAt
    @State private var showTagList = false
    @State private var showExportDialog = false
    @State private var isExporting = false
    @State private var exportProgress = 0.0
    @State private var exportStatusMessage = ""

    @State private var exportedFileURL: URL?
    
    private let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "ContentView")


    
    private var displayedIndices: [IndexPayload] {
        let baseIndices = isSearching ? filteredIndices : noteIndexViewModel.indexPayloads
        
        return baseIndices.sorted { index1, index2 in
            switch sortOption {
            case .pinned:
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                // Secondary sort by creation date for pinned items
                return index1.createdAt > index2.createdAt
                
            case .title:
                // First sort by pinned status, then by title
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                return index1.title.localizedCaseInsensitiveCompare(index2.title) == .orderedAscending
                
            case .updatedAt:
                // First sort by pinned status, then by update date
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                return index1.updatedAt > index2.updatedAt
                
            case .createdAt:
                // First sort by pinned status, then by creation date
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                return index1.createdAt > index2.createdAt
            }
        }
    }
    
    private var allTags: [String] {
        return TagManager.extractTagsFromIndex(noteIndexViewModel.indexPayloads)
    }
    
    private func tagsToString(_ tags: [String]) -> String {
        return tags.sorted().joined(separator: ", ")
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                VStack(alignment: .leading) {
                    HStack {
                        TextField("Search notes...", text: $searchText)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: searchText) { _, newValue in
                                updateTagSuggestions(for: newValue)
                            }
                            .overlay(
                                HStack {
                                    Spacer()
                                    if !searchText.isEmpty {
                                        Button(action: clearSearch) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.trailing, 8)
                                    }
                                }
                            )
                        
                        Button(action: performSearch) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.blue)
                        }
                        .padding(.leading, 4)
                    }
                    
                    if showTagSuggestions {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(tagSuggestions, id: \.self) { tag in
                                Button(action: { selectTag(tag) }) {
                                    HStack {
                                        Text("#\(tag)")
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .background(Color(UIColor.systemBackground))
                                
                                if tag != tagSuggestions.last {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(UIColor.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(8)
                        .shadow(radius: 2)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Sort options
                HStack {
                    Text("Sort by:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button(action: { sortOption = option }) {
                            Text(option.rawValue.lowercased())
                                .font(.subheadline)
                                .foregroundColor(sortOption == option ? .blue : .secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                List {
                    if displayedIndices.isEmpty {
                        Text("(no notes)")
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(displayedIndices, id: \.id) { indexPayload in
                            HStack {
                                if isDeleteMode {
                                    Button(action: { deleteNoteFromIndex(indexPayload) }) {
                                        Image(systemName: "x.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.title2)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                
                                NavigationLink(value: indexPayload) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            if indexPayload.pinned {
                                                Image(systemName: "pin.fill")
                                                    .foregroundColor(.orange)
                                                    .font(.caption)
                                            }
                                            Text(indexPayload.title)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        
                                        let tagString = tagsToString(indexPayload.tags)
                                        if !tagString.isEmpty {
                                            Text(tagString)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                .disabled(isDeleteMode)
                                
                                if !isDeleteMode {
                                    Button(action: { togglePinForIndex(indexPayload) }) {
                                        Image(systemName: indexPayload.pinned ? "pin.slash" : "pin")
                                            .foregroundColor(indexPayload.pinned ? .orange : .gray)
                                            .font(.title3)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .onDelete(perform: isDeleteMode ? nil : deleteIndices)
                    }
                }
                .navigationTitle("Notes")
            }
            .navigationDestination(for: IndexPayload.self) { indexPayload in
                NoteEditView(indexPayload: indexPayload)
                    .onDisappear {
                        // Refresh index when returning from note editing
                        noteIndexViewModel.refreshIndex(from: viewContext)
                    }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showTagList = true }) {
                        Image(systemName: "tag")
                            .foregroundColor(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { showExportDialog = true }) {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.primary)
                            }
                        }
                        .disabled(isExporting)
                        
                        Button(action: toggleDeleteMode) {
                            Image(systemName: "minus")
                                .foregroundColor(isDeleteMode ? .red : .primary)
                        }
                        .disabled(isExporting)
                        
                        Button(action: addNote) {
                            Image(systemName: "plus")
                        }
                        .disabled(isExporting)
                    }
                }
            }
            .sheet(isPresented: $showTagList) {
                TagBrowserView()
            }
            .alert("Export Notes", isPresented: $showExportDialog) {
                Button("OK") {
                    exportAllNotesEncrypted()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Export all notes as encrypted zip file?")
            }
            // Progress overlay
            .overlay(
                Group {
                    if isExporting {
                        ZStack {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                            
                            VStack(spacing: 20) {
                                ProgressView(value: exportProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .frame(width: 200)
                                
                                Text(exportStatusMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                
                                Text("\(Int(exportProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(30)
                            .background(Color(UIColor.systemBackground))
                            .cornerRadius(12)
                            .shadow(radius: 10)
                        }
                    }
                }
            )
            .sheet(item: Binding<ExportFileItem?>(
                get: { exportedFileURL.map { ExportFileItem(url: $0) } },
                set: { _ in exportedFileURL = nil }
            )) { fileItem in
                ShareSheet(activityItems: [fileItem.url])
            }
            .alert("Error", isPresented: $errorManager.showError) {
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
    
    private func clearSearch() {
        searchText = ""
        showTagSuggestions = false
        tagSuggestions = []
        justSelectedTag = false
        lastSearchTextAfterSelection = ""
        isSearching = false
        filteredIndices = []
    }
    
    private func performSearch() {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearchText.isEmpty {
            isSearching = false
            filteredIndices = []
        } else {
            isSearching = true
            filteredIndices = noteIndexViewModel.indexPayloads.filter { indexPayload in
                // Search in title
                let titleContains = indexPayload.title.localizedCaseInsensitiveContains(trimmedSearchText)
                
                // Search in summary (body content)
                let summaryContains = indexPayload.summary.localizedCaseInsensitiveContains(trimmedSearchText)
                
                // Search in tags - handle both #tag and plain tag search
                var tagsContains = false
                if trimmedSearchText.hasPrefix("#") {
                    let tagQuery = String(trimmedSearchText.dropFirst())
                    tagsContains = indexPayload.tags.contains { tag in
                        tag.localizedCaseInsensitiveContains(tagQuery)
                    }
                } else {
                    // Also search tags without # prefix
                    tagsContains = indexPayload.tags.contains { tag in
                        tag.localizedCaseInsensitiveContains(trimmedSearchText)
                    }
                }
                
                return titleContains || summaryContains || tagsContains
            }
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
    
    private func updateTagSuggestions(for text: String) {
        // If we just selected a tag, only show suggestions if user has typed significantly new content
        if justSelectedTag {
            // Check if the current text is just the same as after selection (possibly with trailing spaces)
            let textWithoutTrailingSpaces = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastTextWithoutTrailingSpaces = lastSearchTextAfterSelection.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if textWithoutTrailingSpaces == lastTextWithoutTrailingSpaces {
                // User hasn't typed any meaningful new content, keep suggestions hidden
                showTagSuggestions = false
                tagSuggestions = []
                return
            } else {
                // User typed something new, reset the flag
                justSelectedTag = false
            }
        }
        
        let words = text.split(separator: " ")
        guard let currentWord = words.last, currentWord.hasPrefix("#") else {
            showTagSuggestions = false
            tagSuggestions = []
            return
        }
        
        if currentWord.count == 1 {
            // Just typed "#", show all available tags
            if allTags.isEmpty {
                showTagSuggestions = false
                tagSuggestions = []
            } else {
                showTagSuggestions = true
                tagSuggestions = allTags
            }
            return
        }
        
        // Filter tags based on partial input
        let tagQuery = String(currentWord.dropFirst())
        let matchingTags = allTags.filter { tag in
            tag.localizedCaseInsensitiveContains(tagQuery)
        }
        
        if matchingTags.isEmpty {
            showTagSuggestions = false
            tagSuggestions = []
        } else {
            showTagSuggestions = true
            tagSuggestions = matchingTags
        }
    }
    
    private func selectTag(_ tag: String) {
        // Replace the current partial tag with the selected tag
        let words = searchText.split(separator: " ")
        var newWords = Array(words.dropLast())
        newWords.append("#\(tag)")
        
        searchText = newWords.joined(separator: " ") + " "
        lastSearchTextAfterSelection = searchText
        
        showTagSuggestions = false
        tagSuggestions = []
        justSelectedTag = true
        
        // Trigger search with new tag
        performSearch()
    }

    private func addNote() {
        let noteId = UUID()
        let now = Date()
        
        // Create a temporary IndexPayload for the new note
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
            let indicesToDelete = offsets.map { displayedIndices[$0] }
            
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
        guard !displayedIndices.isEmpty else {
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
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        var itemsToShare: [Any] = []
        
        for item in activityItems {
            if let fileURL = item as? URL {
                let provider = NSItemProvider(contentsOf: fileURL)!
                provider.registerFileRepresentation(forTypeIdentifier: "app.jam.ios.memento",
                                                  fileOptions: [],
                                                  visibility: .all) { completion in
                    completion(fileURL, true, nil)
                    return nil
                }
                itemsToShare.append(provider)
            } else {
                itemsToShare.append(item)
            }
        }
        
        let controller = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
