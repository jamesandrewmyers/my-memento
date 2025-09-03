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
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.primary)
                        }
                        
                        Button(action: toggleDeleteMode) {
                            Image(systemName: "minus")
                                .foregroundColor(isDeleteMode ? .red : .primary)
                        }
                        
                        Button(action: addNote) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showTagList) {
                TagBrowserView()
            }
            .alert("Export Notes", isPresented: $showExportDialog) {
                Button("OK") {
                    exportNotesToJSON()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Export all notes to zip?")
            }
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
            
            // Also delete the corresponding SearchIndex
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

    
    private func exportNotesToJSON() {
        let request: NSFetchRequest<Note> = Note.fetchRequest()
        
        do {
            let notes = try viewContext.fetch(request)
            let encryptionKey = try KeyManager.shared.getEncryptionKey()
            
            var exportData: [[String: Any]] = []
            
            for note in notes {
                var noteData: [String: Any] = [:]
                
                noteData["id"] = note.id?.uuidString ?? ""
                
                // Decrypt the note data to get actual title, body, and tags
                if let encryptedData = note.encryptedData {
                    let decryptedPayload = try CryptoHelper.decrypt(encryptedData, key: encryptionKey, as: NotePayload.self)
                    
                    noteData["title"] = decryptedPayload.title
                    // Convert NSAttributedString to HTML (same as share functionality)
                    let attributedString = decryptedPayload.body.attributedString
                    if attributedString.length > 0 {
                        do {
                            let htmlData = try attributedString.data(
                                from: NSRange(location: 0, length: attributedString.length),
                                documentAttributes: [
                                    .documentType: NSAttributedString.DocumentType.html,
                                    .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
                                ]
                            )
                            noteData["body"] = String(data: htmlData, encoding: .utf8) ?? ""
                        } catch {
                            logger.error("Failed to convert note body to HTML: \(error.localizedDescription)")
                            noteData["body"] = attributedString.string
                        }
                    } else {
                        noteData["body"] = ""
                    }
                    noteData["tags"] = decryptedPayload.tags
                    noteData["createdAt"] = ISO8601DateFormatter().string(from: decryptedPayload.createdAt)
                    noteData["updatedAt"] = ISO8601DateFormatter().string(from: decryptedPayload.updatedAt)
                    noteData["isPinned"] = decryptedPayload.pinned
                } else {
                    // Fallback for unencrypted data (shouldn't happen in normal operation)
                    noteData["title"] = note.title ?? ""
                    noteData["body"] = note.body ?? ""
                    noteData["createdAt"] = ISO8601DateFormatter().string(from: note.createdAt ?? Date())
                    noteData["isPinned"] = note.isPinned
                    noteData["tags"] = []
                }
                
                exportData.append(noteData)
            }
            
            let jsonData = ["notes": exportData]
            
            guard let jsonDataToWrite = try? JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted) else {
                logger.error("Failed to serialize notes to JSON")
                return
            }
            
            // Create temporary file
            let tempDir = FileManager.default.temporaryDirectory
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let fileName = "MyMemento_Export_\(dateFormatter.string(from: Date())).json"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            try jsonDataToWrite.write(to: fileURL)
            
            exportedFileURL = fileURL
            
        } catch {
            logger.error("Failed to export notes: \(error.localizedDescription)")
            errorManager.handleCoreDataError(error as NSError, context: "Failed to export notes")
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        var itemsToShare: [Any] = []
        
        for item in activityItems {
            if let fileURL = item as? URL {
                let provider = NSItemProvider(contentsOf: fileURL)!
                provider.registerFileRepresentation(forTypeIdentifier: "public.json",
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
