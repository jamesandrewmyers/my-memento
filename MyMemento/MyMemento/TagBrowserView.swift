//
//  TagBrowserView.swift
//  MyMemento
//
//  Created by MyMemento Assistant on 8/24/25.
//

import SwiftUI
import CoreData

struct TagBrowserView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var noteIndexViewModel: NoteIndexViewModel
    @StateObject private var errorManager = ErrorManager.shared

    // Search state (no leading "#" required)
    @State private var searchText = ""
    @State private var filteredTags: [String] = []
    @State private var isSearching = false
    @State private var showTagSuggestions = false
    @State private var tagSuggestions: [String] = []
    @State private var justSelectedSuggestion = false
    @State private var lastSearchTextAfterSelection = ""
    @State private var tagToDelete: String?
    @State private var showDeleteConfirmation = false

    private var allTags: [String] {
        return TagManager.extractTagsFromIndex(noteIndexViewModel.indexPayloads)
    }

    private var displayedTags: [String] {
        isSearching ? filteredTags : allTags
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Search bar (mirrors notes list styling)
                VStack(alignment: .leading) {
                    HStack {
                        TextField("Search tags...", text: $searchText)
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
                            ForEach(tagSuggestions, id: \.self) { suggestion in
                                Button(action: { selectSuggestion(suggestion) }) {
                                    HStack {
                                        Text(suggestion)
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .background(Color(UIColor.systemBackground))

                                if suggestion != tagSuggestions.last {
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

                List {
                    if displayedTags.isEmpty {
                        Text("No tags created yet")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(displayedTags, id: \.self) { tagName in
                            NavigationLink(value: tagName) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tagName)
                                            .font(.headline)
                                            .foregroundColor(.primary)

                                        Text("\(noteCount(for: tagName)) note\(noteCount(for: tagName) == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: deleteTag)
                    }
                }
                .navigationTitle("Tags")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .navigationDestination(for: String.self) { tagName in
                TaggedNotesView(tagName: tagName)
            }
        }
        .alert("Delete Tag", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { tagToDelete = nil }
            Button("Delete", role: .destructive) {
                if let tag = tagToDelete { performDeleteTag(tag) }
                tagToDelete = nil
            }
        } message: {
            if let tag = tagToDelete {
                let noteCount = noteCount(for: tag)
                let message = noteCount > 0 ?
                    "This will remove \"\(tag)\" from \(noteCount) note\(noteCount == 1 ? "" : "s")." :
                    "This will permanently delete the tag \"\(tag)\"."
                Text(message)
            }
        }
        .alert(errorManager.dialogType == .error ? "Error" : "Success", isPresented: $errorManager.showError) {
            Button("OK") { }
        } message: { Text(errorManager.errorMessage) }
    }

    // MARK: - Helpers

    private func noteCount(for tagName: String) -> Int {
        return TagManager.countNotes(for: tagName, in: noteIndexViewModel.indexPayloads)
    }

    private func deleteTag(at offsets: IndexSet) {
        for index in offsets {
            let tag = displayedTags[index]
            tagToDelete = tag
            showDeleteConfirmation = true
        }
    }

    private func performDeleteTag(_ tagName: String) {
        // Find all notes that contain this tag and remove it from their encrypted data
        let notesToUpdate = TagManager.filterNotes(by: tagName, in: noteIndexViewModel.indexPayloads)
        
        do {
            let encryptionKey = try KeyManager.shared.getEncryptionKey()
            
            for indexPayload in notesToUpdate {
                // Find the corresponding Note entity
                let noteRequest: NSFetchRequest<Note> = Note.fetchRequest()
                noteRequest.predicate = NSPredicate(format: "id == %@", indexPayload.id as CVarArg)
                
                if let note = try viewContext.fetch(noteRequest).first,
                   let encryptedData = note.encryptedData {
                    
                    // Decrypt NotePayload, remove tag, re-encrypt
                    var notePayload = try CryptoHelper.decrypt(encryptedData, key: encryptionKey, as: NotePayload.self)
                    notePayload.tags.removeAll { $0.caseInsensitiveCompare(tagName) == .orderedSame }
                    
                    let updatedEncryptedData = try CryptoHelper.encrypt(notePayload, key: encryptionKey)
                    note.encryptedData = updatedEncryptedData
                    
                    // Also update SearchIndex
                    let searchIndexRequest: NSFetchRequest<SearchIndex> = SearchIndex.fetchRequest()
                    searchIndexRequest.predicate = NSPredicate(format: "id == %@", indexPayload.id as CVarArg)
                    
                    if let searchIndex = try viewContext.fetch(searchIndexRequest).first {
                        var updatedIndexPayload = indexPayload
                        updatedIndexPayload.tags.removeAll { $0.caseInsensitiveCompare(tagName) == .orderedSame }
                        
                        let updatedEncryptedIndexData = try CryptoHelper.encrypt(updatedIndexPayload, key: encryptionKey)
                        searchIndex.encryptedIndexData = updatedEncryptedIndexData
                    }
                }
            }
            
            try viewContext.save()
            noteIndexViewModel.refreshIndex(from: viewContext)
            
        } catch {
            let nsError = error as NSError
            errorManager.handleCoreDataError(nsError, context: "Failed to delete tag")
        }
    }

    private func clearSearch() {
        searchText = ""
        isSearching = false
        filteredTags = []
        showTagSuggestions = false
        tagSuggestions = []
        justSelectedSuggestion = false
        lastSearchTextAfterSelection = ""
    }

    private func updateTagSuggestions(for text: String) {
        // If we just selected a suggestion, keep suggestions hidden
        if justSelectedSuggestion {
            let textTrimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastTrimmed = lastSearchTextAfterSelection.trimmingCharacters(in: .whitespacesAndNewlines)
            if textTrimmed == lastTrimmed {
                showTagSuggestions = false
                tagSuggestions = []
                return
            } else {
                // User typed something new; allow suggestions again
                justSelectedSuggestion = false
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showTagSuggestions = false
            tagSuggestions = []
            return
        }
        let lower = trimmed.lowercased()
        let matches = allTags.filter { $0.lowercased().hasPrefix(lower) }
        if matches.isEmpty {
            showTagSuggestions = false
            tagSuggestions = []
        } else {
            tagSuggestions = matches
            showTagSuggestions = true
        }
    }

    private func selectSuggestion(_ suggestion: String) {
        searchText = suggestion
        showTagSuggestions = false
        tagSuggestions = []
        justSelectedSuggestion = true
        lastSearchTextAfterSelection = suggestion
        performSearch()
    }

    private func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isSearching = false
            filteredTags = []
        } else {
            isSearching = true
            filteredTags = allTags.filter { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }
}

#Preview {
    TagBrowserView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
