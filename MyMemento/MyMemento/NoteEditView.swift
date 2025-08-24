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
    @State private var noteBody: NSAttributedString = NSAttributedString()
    @State private var editorCoordinator: RichTextEditor.Coordinator?
    
    var body: some View {
        Form {
            Section(header: Text("Note Details")) {
                TextField("Title", text: $title)
                    .font(.headline)
                
                TextField("Tags", text: $tags)
                    .font(.subheadline)
            }
            
            Section(header: contentHeader) {
                if #available(iOS 15.0, *) {
                    RichTextEditorWrapper(
                        attributedText: $noteBody,
                        coordinator: $editorCoordinator
                    )
                    .frame(minHeight: 200)
                } else {
                    Text("Rich text editor requires iOS 15.0+")
                }
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
        noteBody = note.richText ?? NSAttributedString()
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
        
        // Capture existing tags before removing them for cleanup
        let existingTags = Array(note.tags as? Set<Tag> ?? Set<Tag>())
        
        // Clear existing tags
        note.removeFromTags(note.tags ?? NSSet())
        
        // Add new tags
        let newTags = stringToTags(tags)
        for tag in newTags {
            note.addToTags(tag)
        }
        
        note.richText = noteBody
        print("=== PRE-SAVE VALIDATION ===")
          print("Note ID: \(note.id?.description ?? "nil")")
          print("Note title: \(note.title ?? "nil")")
          print("Note richText is nil: \(note.richText == nil)")
          if let richText = note.richText {
              print("Note richText length: \(richText.length)")
              print("Note richText string: '\(richText.string)'")
          } else {
              print("Note richText is completely nil!")
          }
          print("Note createdAt: \(note.createdAt?.description ?? "nil")")
          print("Note isPinned: \(note.isPinned)")
          print("===========================")
        do {
            try viewContext.save()
            
            // Clean up orphaned tags from the previously existing tags
            for tag in existingTags {
                TagManager.handleTagRemovedFromNote(tag, in: viewContext)
            }
            
            SyncService.shared.upload(notes: Array(allNotes))
            dismiss()
        } catch {
            let nsError = error as NSError
            print("=== DETAILED SAVE ERROR ===")
             print("Error: \(nsError)")
             print("Domain: \(nsError.domain)")
             print("Code: \(nsError.code)")
             print("UserInfo:")
             for (key, value) in nsError.userInfo {
                 print("  \(key): \(value)")
             }
             if let detailedErrors = nsError.userInfo[NSDetailedErrorsKey] as?
         [NSError] {
                 print("Detailed Errors:")
                 for detailError in detailedErrors {
                     print("  - \(detailError)")
                 }
             }
             print("===========================")
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

// MARK: - Formatting Bar (visual only)

extension NoteEditView {
    private var contentHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Content")
            Spacer()
            formattingBar
        }
    }

    private var formattingBar: some View {
        HStack(spacing: 16) {
            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleBold()
                }
            }) {
                Image(systemName: "bold")
                    .imageScale(.medium)
                    .accessibilityLabel("Bold")
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.secondary)

            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleItalic()
                }
            }) {
                Image(systemName: "italic")
                    .imageScale(.medium)
                    .accessibilityLabel("Italic")
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.secondary)

            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleUnderline()
                }
            }) {
                Image(systemName: "underline")
                    .imageScale(.medium)
                    .accessibilityLabel("Underline")
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - RichTextEditorWrapper

@available(iOS 15.0, *)
struct RichTextEditorWrapper: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var coordinator: RichTextEditor.Coordinator?
    
    func makeCoordinator() -> RichTextEditor.Coordinator {
        let coord = RichTextEditor.Coordinator()
        DispatchQueue.main.async {
            coordinator = coord
        }
        return coord
    }
    
    func makeUIView(context: Context) -> RichTextEditorView {
        let editorView = RichTextEditorView()
        editorView.onTextChange = { newAttributedText in
            DispatchQueue.main.async {
                attributedText = newAttributedText
            }
        }
        
        // Store reference in coordinator for formatting methods
        context.coordinator.editorView = editorView
        
        return editorView
    }
    
    func updateUIView(_ uiView: RichTextEditorView, context: Context) {
        let currentText = uiView.getAttributedText()
        if !currentText.isEqual(to: attributedText) {
            uiView.setAttributedText(attributedText)
        }
    }
}
