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
    @StateObject private var errorManager = ErrorManager.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Tag.name, ascending: true)],
        animation: .default)
    private var tags: FetchedResults<Tag>

    // Search state (no leading “#” required)
    @State private var searchText = ""
    @State private var filteredTags: [Tag] = []
    @State private var isSearching = false
    @State private var showTagSuggestions = false
    @State private var tagSuggestions: [String] = []
    @State private var justSelectedSuggestion = false
    @State private var lastSearchTextAfterSelection = ""
    @State private var tagToDelete: Tag?
    @State private var showDeleteConfirmation = false

    private var displayedTags: [Tag] {
        isSearching ? filteredTags : Array(tags)
    }

    private var allTagNames: [String] {
        // Build a case-insensitive, de-duplicated, non-empty list of tag names
        var seen = Set<String>()
        var unique: [String] = []
        for name in tags.compactMap({ $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            if name.isEmpty { continue }
            let key = name.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(name)
            }
        }
        return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
                        ForEach(displayedTags, id: \.id) { tag in
                            NavigationLink(destination: TaggedNotesView(tag: tag)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tag.name ?? "Unknown Tag")
                                            .font(.headline)
                                            .foregroundColor(.primary)

                                        Text("\(noteCount(for: tag)) note\(noteCount(for: tag) == 1 ? "" : "s")")
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
                    "This will remove \"\(tag.name ?? "")\" from \(noteCount) note\(noteCount == 1 ? "" : "s")." :
                    "This will permanently delete the tag \"\(tag.name ?? "")\"."
                Text(message)
            }
        }
        .alert("Error", isPresented: $errorManager.showError) {
            Button("OK") { }
        } message: { Text(errorManager.errorMessage) }
    }

    // MARK: - Helpers

    private func noteCount(for tag: Tag) -> Int {
        return (tag.notes as? Set<Note>)?.count ?? 0
    }

    private func deleteTag(at offsets: IndexSet) {
        for index in offsets {
            let tag = displayedTags[index]
            tagToDelete = tag
            showDeleteConfirmation = true
        }
    }

    private func performDeleteTag(_ tag: Tag) {
        do {
            if let associatedNotes = tag.notes as? Set<Note> {
                for note in associatedNotes { note.removeFromTags(tag) }
            }
            viewContext.delete(tag)
            try viewContext.save()
            viewContext.refreshAllObjects()
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
        let matches = allTagNames.filter { $0.lowercased().hasPrefix(lower) }
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
            filteredTags = tags.filter { ( $0.name ?? "" ).localizedCaseInsensitiveContains(trimmed) }
        }
    }
}

#Preview {
    TagBrowserView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
