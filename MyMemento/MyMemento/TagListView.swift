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
    @StateObject private var errorManager = ErrorManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Tag.name, ascending: true)],
        animation: .default)
    private var tags: FetchedResults<Tag>
    
    @State private var tagToDelete: Tag?
    @State private var showDeleteConfirmation = false
    
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
                    .onDelete(perform: deleteTag)
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
        .alert("Delete Tag", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { 
                tagToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let tag = tagToDelete {
                    performDeleteTag(tag)
                }
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
        } message: {
            Text(errorManager.errorMessage)
        }
    }
    
    private func noteCount(for tag: Tag) -> Int {
        return (tag.notes as? Set<Note>)?.count ?? 0
    }
    
    private func deleteTag(at offsets: IndexSet) {
        for index in offsets {
            let tag = tags[index]
            tagToDelete = tag
            showDeleteConfirmation = true
        }
    }
    
    private func performDeleteTag(_ tag: Tag) {
        do {
            // Remove tag from all associated notes
            if let associatedNotes = tag.notes as? Set<Note> {
                for note in associatedNotes {
                    note.removeFromTags(tag)
                }
            }
            
            // Delete the tag from Core Data
            viewContext.delete(tag)
            
            // Save changes
            try viewContext.save()
            
            // Force refresh to update UI displays
            viewContext.refreshAllObjects()
            
        } catch {
            let nsError = error as NSError
            errorManager.handleCoreDataError(nsError, context: "Failed to delete tag")
        }
    }
}

struct TaggedNotesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
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
        
        // Check if the name is the same as current (no change needed)
        if trimmedName.caseInsensitiveCompare(tag.name ?? "") == .orderedSame {
            isEditingTitle = false
            editedTagName = ""
            return
        }
        
        do {
            // Check if a tag with this name already exists (case-insensitive)
            if let existingTag = try TagManager.findExistingTag(named: trimmedName, excluding: tag, in: viewContext) {
                // Merge this tag into the existing tag
                try TagManager.mergeTag(tag, into: existingTag, in: viewContext)
                
                // Force refresh to update UI displays
                viewContext.refreshAllObjects()
                
                // Close editing and dismiss view since the tag was merged/deleted
                isEditingTitle = false
                editedTagName = ""
                dismiss()
                
            } else {
                // No existing tag, just rename this one
                tag.name = trimmedName
                try viewContext.save()
                
                // Force refresh of all objects to update UI displays
                viewContext.refreshAllObjects()
                
                isEditingTitle = false
                editedTagName = ""
            }
            
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