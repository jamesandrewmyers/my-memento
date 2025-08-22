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

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)],
        animation: .default)
    private var notes: FetchedResults<Note>
    
    private var displayedNotes: [Note] {
        if isSearching {
            return filteredNotes
        } else {
            return Array(notes)
        }
    }
    
    private var allTags: [String] {
        let tagStrings = notes.compactMap { $0.tags }
        let individualTags = tagStrings.flatMap { tagString in
            tagString.split(separator: " ").map { String($0) }
        }
        return Array(Set(individualTags)).sorted()
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
                                        Text(note.title ?? "Untitled")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        if let tags = note.tags, !tags.isEmpty {
                                            Text(tags)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                .disabled(isDeleteMode)
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
    
    private func deleteNote(_ note: Note) {
        withAnimation {
            viewContext.delete(note)
            
            do {
                try viewContext.save()
                SyncService.shared.upload(notes: Array(notes))
            } catch {
                let nsError = error as NSError
                errorManager.handleCoreDataError(nsError, context: "Failed to delete note")
            }
        }
    }
    
    private func updateTagSuggestions(for text: String) {
        // If we just selected a tag, don't show suggestions until user types non-whitespace
        if justSelectedTag {
            // Check if user typed a non-whitespace character after tag selection
            let trimmedText = text.trimmingCharacters(in: .whitespaces)
            if text.count > trimmedText.count + 1 { // Still just whitespace after tag
                showTagSuggestions = false
                tagSuggestions = []
                return
            } else {
                // User typed a non-whitespace character, reset the flag
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
        searchText = newWords.joined(separator: " ") + " "
        showTagSuggestions = false
        tagSuggestions = []
        justSelectedTag = true
        performSearch()
    }
    
    private func performSearch() {
        if searchText.isEmpty {
            isSearching = false
            filteredNotes = []
        } else {
            isSearching = true
            filteredNotes = notes.filter { note in
                let titleContains = (note.title ?? "").localizedCaseInsensitiveContains(searchText)
                let bodyContains = (note.body ?? "").localizedCaseInsensitiveContains(searchText)
                var tagsContains = false;
                if searchText.hasPrefix("#") {
                    tagsContains = (note.tags ?? "").localizedCaseInsensitiveContains(searchText.dropFirst())
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
            }
        }
    }

    private func addNote() {
        let note = Note(context: viewContext)
        note.id = UUID()
        note.title = "New Note"
        note.body = ""
        note.tags = ""
        note.createdAt = Date()

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
            offsets.map { displayedNotes[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
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
