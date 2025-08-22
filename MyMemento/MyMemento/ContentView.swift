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

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                HStack {
                    TextField("Search notes...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: performSearch) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                    }
                    .padding(.leading, 4)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                List {
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
    
    private func performSearch() {
        if searchText.isEmpty {
            isSearching = false
            filteredNotes = []
        } else {
            isSearching = true
            filteredNotes = notes.filter { note in
                let titleContains = (note.title ?? "").localizedCaseInsensitiveContains(searchText)
                let bodyContains = (note.body ?? "").localizedCaseInsensitiveContains(searchText)
                return titleContains || bodyContains
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
