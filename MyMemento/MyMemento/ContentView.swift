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
    @State private var searchText = ""
    @State private var filteredNotes: [Note] = []
    @State private var isSearching = false

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
        NavigationView {
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
                    NavigationLink(destination: NoteEditView(note: note)) {
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
                }
                .onDelete(perform: deleteNotes)
                }
                .navigationTitle("Notes")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addNote) {
                        Image(systemName: "plus")
                    }
                }
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
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }

    private func deleteNotes(offsets: IndexSet) {
        withAnimation {
            offsets.map { displayedNotes[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
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
