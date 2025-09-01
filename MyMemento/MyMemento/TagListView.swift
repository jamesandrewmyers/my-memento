import SwiftUI
import CoreData

struct TagListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var noteIndexViewModel: NoteIndexViewModel
    @StateObject private var errorManager = ErrorManager.shared
    
    @State private var tagToDelete: String?
    @State private var showDeleteConfirmation = false
    
    private var allTags: [String] {
        return TagManager.extractTagsFromIndex(noteIndexViewModel.indexPayloads)
    }
    
    var body: some View {
        NavigationStack {
            List {
                if allTags.isEmpty {
                    Text("No tags created yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(allTags, id: \.self) { tagName in
                        NavigationLink(destination: TaggedNotesView(tagName: tagName)) {
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
                let count = noteCount(for: tag)
                let message = count > 0 ? 
                    "This will remove \"\(tag)\" from \(count) note\(count == 1 ? "" : "s")." : 
                    "This will permanently delete the tag \"\(tag)\"."
                Text(message)
            }
        }
        .alert("Error", isPresented: $errorManager.showError) {
            Button("OK") { }
        } message: {
            Text(errorManager.errorMessage)
        }
    }
    
    private func noteCount(for tagName: String) -> Int {
        return TagManager.countNotes(for: tagName, in: noteIndexViewModel.indexPayloads)
    }
    
    private func deleteTag(at offsets: IndexSet) {
        for index in offsets {
            let tag = allTags[index]
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
}

struct TaggedNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var noteIndexViewModel: NoteIndexViewModel
    
    let tagName: String
    
    private var filteredIndices: [IndexPayload] {
        return TagManager.filterNotes(by: tagName, in: noteIndexViewModel.indexPayloads)
            .sorted { index1, index2 in
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                return index1.createdAt > index2.createdAt
            }
    }
    
    var body: some View {
        List {
            if filteredIndices.isEmpty {
                Text("No notes with this tag")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(filteredIndices, id: \.id) { indexPayload in
                    NavigationLink(destination: NoteEditView(indexPayload: indexPayload)) {
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
                            
                            if !indexPayload.summary.isEmpty {
                                Text(indexPayload.summary)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(tagName)
        .navigationBarTitleDisplayMode(.inline)
    }
}