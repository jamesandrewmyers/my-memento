//
//  NoteEditView.swift
//  MyMemento
//
//  Created by James Andrew Myers on 8/22/25.
//

import SwiftUI
import CoreData

struct NoteEditView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var errorManager = ErrorManager.shared
    
    @ObservedObject var note: Note
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)],
        animation: .default)
    private var allNotes: FetchedResults<Note>
    
    @State private var title: String = ""
    @State private var tags: String = ""
    @State private var noteBody: String = ""
    
    var body: some View {
        Form {
            Section(header: Text("Note Details")) {
                TextField("Title", text: $title)
                    .font(.headline)
                
                TextField("Tags", text: $tags)
                    .font(.subheadline)
            }
            
            Section(header: Text("Content")) {
                TextEditor(text: $noteBody)
                    .frame(minHeight: 200)
            }
        }
        .navigationTitle("Edit Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .principal) {
                Button(action: togglePin) {
                    Image(systemName: note.isPinned ? "pin.slash" : "pin")
                        .foregroundColor(note.isPinned ? .orange : .gray)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveNote()
                }
            }
        }
        .onAppear {
            loadNoteData()
        }
        .alert("Error", isPresented: $errorManager.showError) {
            Button("OK") { }
        } message: {
            Text(errorManager.errorMessage)
        }
    }
    
    private func loadNoteData() {
        title = note.title ?? ""
        tags = tagsToString(note.tags)
        noteBody = note.body ?? ""
    }
    
    private func tagsToString(_ tagSet: NSSet?) -> String {
        guard let tagSet = tagSet as? Set<Tag> else { return "" }
        return tagSet.compactMap { $0.name }.sorted().joined(separator: ", ")
    }
    
    private func stringToTags(_ tagString: String) -> Set<Tag> {
        let tagNames = tagString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var tagSet = Set<Tag>()
        
        for tagName in tagNames {
            if !tagName.isEmpty {
                // Try to find existing tag
                let fetchRequest: NSFetchRequest<Tag> = Tag.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "name == %@", tagName)
                
                let existingTag = try? viewContext.fetch(fetchRequest).first
                
                if let existingTag = existingTag {
                    tagSet.insert(existingTag)
                } else {
                    // Create new tag
                    let newTag = Tag(context: viewContext)
                    newTag.id = UUID()
                    newTag.name = tagName
                    newTag.createdAt = Date()
                    tagSet.insert(newTag)
                }
            }
        }
        
        return tagSet
    }
    
    private func saveNote() {
        note.title = title
        
        // Clear existing tags
        note.removeFromTags(note.tags ?? NSSet())
        
        // Add new tags
        let newTags = stringToTags(tags)
        for tag in newTags {
            note.addToTags(tag)
        }
        
        note.body = noteBody
        
        do {
            try viewContext.save()
            SyncService.shared.upload(notes: Array(allNotes))
            dismiss()
        } catch {
            let nsError = error as NSError
            errorManager.handleCoreDataError(nsError, context: "Failed to save note")
        }
    }
    
    private func togglePin() {
        note.isPinned.toggle()
        
        do {
            try viewContext.save()
            SyncService.shared.upload(notes: Array(allNotes))
        } catch {
            let nsError = error as NSError
            errorManager.handleCoreDataError(nsError, context: "Failed to update note pin status")
        }
    }
}
