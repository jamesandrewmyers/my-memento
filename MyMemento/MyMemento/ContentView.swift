//
//  ContentView.swift
//  MyMemento
//
//  Created by James Andrew Myers on 8/21/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var errorManager = ErrorManager.shared
    @State private var searchText = ""
    @State private var filteredNotes: [Note] = []
    @State private var isSearching = false
    @State private var isDeleteMode = false
    @State private var navigationPath = NavigationPath()
    @State private var showTagSuggestions = false
    @State private var tagSuggestions: [String] = []
    @State private var justSelectedTag = false
    @State private var lastSearchTextAfterSelection = ""
    @State private var sortByTitle = false
    @State private var showTagList = false

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Note.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)
        ],
        animation: .default)
    private var notes: FetchedResults<Note>
    
    private var displayedNotes: [Note] {
        let baseNotes = isSearching ? filteredNotes : Array(notes)
        
        if sortByTitle {
            return baseNotes.sorted { note1, note2 in
                // First sort by pinned status
                if note1.isPinned != note2.isPinned {
                    return note1.isPinned && !note2.isPinned
                }
                // Then sort by title
                let title1 = note1.title ?? "Untitled"
                let title2 = note2.title ?? "Untitled"
                return title1.localizedCaseInsensitiveCompare(title2) == .orderedAscending
            }
        } else {
            return baseNotes
        }
    }
    
    private var allTags: [String] {
        let allTagSets = notes.compactMap { $0.tags as? Set<Tag> }
        let allTagNames = allTagSets.flatMap { tagSet in
            tagSet.compactMap { $0.name }
        }
        return Array(Set(allTagNames)).sorted()
    }
    
    private func tagsToString(_ tagSet: NSSet?) -> String {
        guard let tagSet = tagSet as? Set<Tag> else { return "" }
        return tagSet.compactMap { $0.name }.sorted().joined(separator: ", ")
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                VStack(alignment: .leading) {
                    HStack {
                        TextField("Search notes...", text: $searchText)
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
                    
                    Button(action: { sortByTitle = false }) {
                        Text("created")
                            .font(.subheadline)
                            .foregroundColor(sortByTitle ? .blue : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { sortByTitle = true }) {
                        Text("title")
                            .font(.subheadline)
                            .foregroundColor(sortByTitle ? .secondary : .blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                List {
                    if displayedNotes.isEmpty {
                        Text("(no notes)")
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(displayedNotes, id: \.objectID) { note in
                            HStack {
                                if isDeleteMode {
                                    Button(action: { deleteNote(note) }) {
                                        Image(systemName: "x.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.title2)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                
                                NavigationLink(value: note) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            if note.isPinned {
                                                Image(systemName: "pin.fill")
                                                    .foregroundColor(.orange)
                                                    .font(.caption)
                                            }
                                            Text(note.title ?? "Untitled")
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        
                                        let tagString = tagsToString(note.tags)
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
                                    Button(action: { togglePin(for: note) }) {
                                        Image(systemName: note.isPinned ? "pin.slash" : "pin")
                                            .foregroundColor(note.isPinned ? .orange : .gray)
                                            .font(.title3)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .onDelete(perform: isDeleteMode ? nil : deleteNotes)
                    }
                }
                .navigationTitle("Notes")
            }
            .navigationDestination(for: Note.self) { note in
                NoteEditView(note: note)
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
                TagListView()
            }
            .alert("Error", isPresented: $errorManager.showError) {
                Button("OK") { }
            } message: {
                Text(errorManager.errorMessage)
            }
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
        filteredNotes = []
    }
    
    private func togglePin(for note: Note) {
        withAnimation {
            note.isPinned.toggle()
            
            do {
                try viewContext.save()
                SyncService.shared.upload(notes: Array(notes))
            } catch {
                let nsError = error as NSError
                errorManager.handleCoreDataError(nsError, context: "Failed to update note pin status")
            }
        }
    }
    
    private func deleteNote(_ note: Note) {
        withAnimation {
            // Capture tags before deleting the note
            let associatedTags = Array(note.tags as? Set<Tag> ?? Set<Tag>())
            
            viewContext.delete(note)
            
            do {
                try viewContext.save()
                
                // Clean up orphaned tags after the note is deleted and saved
                for tag in associatedTags {
                    TagManager.handleTagRemovedFromNote(tag, in: viewContext)
                }
                
                SyncService.shared.upload(notes: Array(notes))
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
                tagSuggestions = allTags
                showTagSuggestions = true
            }
            return
        }
        
        let tagPrefix = String(currentWord.dropFirst()).lowercased()
        let matchingTags = allTags.filter { tag in
            tag.lowercased().hasPrefix(tagPrefix)
        }
        
        if matchingTags.isEmpty {
            showTagSuggestions = false
            tagSuggestions = []
        } else {
            tagSuggestions = matchingTags
            showTagSuggestions = true
        }
    }
    
    private func selectTag(_ tag: String) {
        let words = searchText.split(separator: " ")
        var newWords = words.dropLast()
        newWords.append("#\(tag)")
        let newText = newWords.joined(separator: " ") + " "
        searchText = newText
        lastSearchTextAfterSelection = newText
        showTagSuggestions = false
        tagSuggestions = []
        justSelectedTag = true
        performSearch()
    }
    
    private func performSearch() {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearchText.isEmpty {
            isSearching = false
            filteredNotes = []
        } else {
            isSearching = true
            filteredNotes = notes.filter { note in
                let titleContains = (note.title ?? "").localizedCaseInsensitiveContains(trimmedSearchText)
                let bodyContains = (note.body ?? "").localizedCaseInsensitiveContains(trimmedSearchText)
                var tagsContains = false;
                if trimmedSearchText.hasPrefix("#") {
                    tagsContains = tagsToString(note.tags).localizedCaseInsensitiveContains(trimmedSearchText.dropFirst())
                }
                if titleContains {
                    print("title contains")
                }
                if bodyContains {
                    print("body contains")
                }
                if tagsContains {
                    print("tags contains")
                }
                return titleContains || bodyContains || tagsContains;
            }.sorted { note1, note2 in
                if note1.isPinned != note2.isPinned {
                    return note1.isPinned && !note2.isPinned
                }
                if sortByTitle {
                    let title1 = note1.title ?? "Untitled"
                    let title2 = note2.title ?? "Untitled"
                    return title1.localizedCaseInsensitiveCompare(title2) == .orderedAscending
                } else {
                    return (note1.createdAt ?? Date()) > (note2.createdAt ?? Date())
                }
            }
        }
    }

    private func addNote() {
        let note = Note(context: viewContext)
        note.id = UUID()
        note.title = "New Note"
        note.body = ""
        // Tags will be empty NSSet by default
        note.createdAt = Date()
        note.isPinned = false

        do {
            try viewContext.save()
            SyncService.shared.upload(notes: Array(notes))
            navigationPath.append(note)
        } catch {
            viewContext.delete(note)
            let nsError = error as NSError
            errorManager.handleCoreDataError(nsError, context: "Failed to save new note")
        }
    }

    private func deleteNotes(offsets: IndexSet) {
        withAnimation {
            let notesToDelete = offsets.map { displayedNotes[$0] }
            
            // Capture all tags from notes before deletion
            var allAssociatedTags = Set<Tag>()
            for note in notesToDelete {
                if let tags = note.tags as? Set<Tag> {
                    allAssociatedTags.formUnion(tags)
                }
            }
            
            notesToDelete.forEach(viewContext.delete)

            do {
                try viewContext.save()
                
                // Clean up orphaned tags after notes are deleted and saved
                for tag in allAssociatedTags {
                    TagManager.handleTagRemovedFromNote(tag, in: viewContext)
                }
                
                SyncService.shared.upload(notes: Array(notes))
            } catch {
                let nsError = error as NSError
                errorManager.handleCoreDataError(nsError, context: "Failed to delete notes")
            }
        }
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
