//
//  TagListView.swift
//  MyMemento
//
//  Created by Claude on 8/23/25.
//

import SwiftUI
import CoreData

struct TagListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Tag.name, ascending: true)],
        animation: .default)
    private var tags: FetchedResults<Tag>
    
    var body: some View {
        NavigationStack {
            List {
                if tags.isEmpty {
                    Text("No tags created yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(tags, id: \.id) { tag in
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
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func noteCount(for tag: Tag) -> Int {
        return (tag.notes as? Set<Note>)?.count ?? 0
    }
}

struct TaggedNotesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var errorManager = ErrorManager.shared
    let tag: Tag
    
    @State private var isEditingTitle = false
    @State private var editedTagName = ""
    
    private var notes: [Note] {
        guard let noteSet = tag.notes as? Set<Note> else { return [] }
        return Array(noteSet).sorted { note1, note2 in
            // Sort by pinned status first, then by creation date
            if note1.isPinned != note2.isPinned {
                return note1.isPinned && !note2.isPinned
            }
            return (note1.createdAt ?? Date()) > (note2.createdAt ?? Date())
        }
    }
    
    var body: some View {
        List {
            if notes.isEmpty {
                Text("No notes with this tag")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(notes, id: \.id) { note in
                    NavigationLink(destination: NoteEditView(note: note)) {
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
                            
                            if let body = note.body, !body.isEmpty {
                                Text(body)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            let tagString = tagsToString(note.tags)
                            if !tagString.isEmpty {
                                Text(tagString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if isEditingTitle {
                    TextField("Tag name", text: $editedTagName, onCommit: saveTagName)
                        .font(.headline)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onAppear {
                            editedTagName = tag.name ?? ""
                        }
                } else {
                    Button(action: startEditing) {
                        HStack {
                            Text(tag.name ?? "Tagged Notes")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            if isEditingTitle {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("Cancel") {
                            cancelEditing()
                        }
                        .foregroundColor(.secondary)
                        
                        Button("Save") {
                            saveTagName()
                        }
                        .fontWeight(.semibold)
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
    
    private func startEditing() {
        isEditingTitle = true
        editedTagName = tag.name ?? ""
    }
    
    private func cancelEditing() {
        isEditingTitle = false
        editedTagName = ""
    }
    
    private func saveTagName() {
        let trimmedName = editedTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate tag name
        guard !trimmedName.isEmpty else {
            errorManager.handleCoreDataError(
                NSError(domain: "TagEdit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tag name cannot be empty"]),
                context: "Tag name validation failed"
            )
            return
        }
        
        // Check if tag name already exists (excluding current tag)
        let fetchRequest: NSFetchRequest<Tag> = Tag.fetchRequest()
        let tagId = tag.id ?? UUID()
        fetchRequest.predicate = NSPredicate(format: "name == %@ AND id != %@", trimmedName, tagId as CVarArg)
        
        do {
            let existingTags = try viewContext.fetch(fetchRequest)
            if !existingTags.isEmpty {
                errorManager.handleCoreDataError(
                    NSError(domain: "TagEdit", code: 2, userInfo: [NSLocalizedDescriptionKey: "A tag with this name already exists"]),
                    context: "Tag name validation failed"
                )
                return
            }
            
            // Save the new tag name
            tag.name = trimmedName
            try viewContext.save()
            
            // Force refresh of all objects to update UI displays
            viewContext.refreshAllObjects()
            
            isEditingTitle = false
            editedTagName = ""
            
        } catch {
            let nsError = error as NSError
            errorManager.handleCoreDataError(nsError, context: "Failed to update tag name")
        }
    }
    
    private func tagsToString(_ tagSet: NSSet?) -> String {
        guard let tagSet = tagSet as? Set<Tag> else { return "" }
        return tagSet.compactMap { $0.name }.sorted().joined(separator: ", ")
    }
}

#Preview {
    TagListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}