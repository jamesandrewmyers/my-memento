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
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderlined = false
    @State private var isBulletList = false
    @State private var isNumberedList = false
    @State private var isH1 = false
    @State private var isH2 = false
    @State private var isH3 = false
    @State private var showLinkDialog = false
    @State private var linkDisplayLabel = ""
    @State private var linkURL = ""
    
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
                        coordinator: $editorCoordinator,
                        isBold: $isBold,
                        isItalic: $isItalic,
                        isUnderlined: $isUnderlined,
                        isBulletList: $isBulletList,
                        isNumberedList: $isNumberedList,
                        isH1: $isH1,
                        isH2: $isH2,
                        isH3: $isH3
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
        .sheet(isPresented: $showLinkDialog) {
            NavigationView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display Label")
                            .font(.headline)
                        TextField("Enter display text", text: $linkDisplayLabel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("URL")
                            .font(.headline)
                        TextField("Enter URL", text: $linkURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                    }
                    
                    HStack {
                        Spacer()
                        Button("OK") {
                            createLink()
                            showLinkDialog = false
                        }
                        .disabled(linkDisplayLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("Add Link")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showLinkDialog = false
                            linkDisplayLabel = ""
                            linkURL = ""
                        }
                    }
                }
            }
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
    
    private func createLink() {
        guard let editorCoordinator = editorCoordinator else { return }
        editorCoordinator.createLink(displayLabel: linkDisplayLabel, url: linkURL)
        
        // Clear the input fields
        linkDisplayLabel = ""
        linkURL = ""
    }
}

// MARK: - Formatting Bar (visual only)

extension NoteEditView {
    private var contentHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
            formattingBar
        }
    }

    private var formattingBar: some View {
        HStack(spacing: 8) {
            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleBold()
                }
            }) {
                Image(systemName: "bold")
                    .imageScale(.medium)
                    .accessibilityLabel("Bold")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isBold))

            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleItalic()
                }
            }) {
                Image(systemName: "italic")
                    .imageScale(.medium)
                    .accessibilityLabel("Italic")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isItalic))

            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleUnderline()
                }
            }) {
                Image(systemName: "underline")
                    .imageScale(.medium)
                    .accessibilityLabel("Underline")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isUnderlined))
            
            // Header dropdown menu
            Menu {
                Button(action: {
                    if #available(iOS 15.0, *) {
                        editorCoordinator?.toggleHeader1()
                    }
                }) {
                    HStack {
                        Text("H1")
                        Spacer()
                        if isH1 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Button(action: {
                    if #available(iOS 15.0, *) {
                        editorCoordinator?.toggleHeader2()
                    }
                }) {
                    HStack {
                        Text("H2")
                        Spacer()
                        if isH2 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Button(action: {
                    if #available(iOS 15.0, *) {
                        editorCoordinator?.toggleHeader3()
                    }
                }) {
                    HStack {
                        Text("H3")
                        Spacer()
                        if isH3 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            } label: {
                Text("H")
                    .font(.system(size: 16, weight: .medium))
                    .accessibilityLabel("Headers")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isH1 || isH2 || isH3))
            
            // Link button
            Button(action: {
                // Set display label to selected text if any
                if let editorCoordinator = editorCoordinator {
                    linkDisplayLabel = editorCoordinator.getSelectedText()
                }
                showLinkDialog = true
            }) {
                Image(systemName: "link")
                    .imageScale(.medium)
                    .accessibilityLabel("Link")
            }
            .buttonStyle(FormattingButtonStyle(isActive: false))
            
            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleBulletList()
                }
            }) {
                Image(systemName: "list.bullet")
                    .imageScale(.medium)
                    .accessibilityLabel("Bullet List")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isBulletList))

            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleNumberedList()
                }
            }) {
                Image(systemName: "list.number")
                    .imageScale(.medium)
                    .accessibilityLabel("Numbered List")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isNumberedList))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Custom Button Styles

struct FormattingButtonStyle: ButtonStyle {
    let isActive: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(isActive ? .primary : .secondary)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isActive: isActive, isPressed: configuration.isPressed))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(borderColor(isActive: isActive, isPressed: configuration.isPressed), lineWidth: 1)
                    )
                    .shadow(
                        color: shadowColor(isActive: isActive, isPressed: configuration.isPressed),
                        radius: shadowRadius(isActive: isActive, isPressed: configuration.isPressed),
                        x: 0,
                        y: shadowOffset(isActive: isActive, isPressed: configuration.isPressed)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isActive)
    }
    
    private func backgroundColor(isActive: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return isActive ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15)
        } else if isActive {
            return Color.blue.opacity(0.15)
        } else {
            return Color(UIColor.systemBackground)
        }
    }
    
    private func borderColor(isActive: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return isActive ? Color.blue.opacity(0.4) : Color.gray.opacity(0.4)
        } else if isActive {
            return Color.blue.opacity(0.3)
        } else {
            return Color.gray.opacity(0.3)
        }
    }
    
    private func shadowColor(isActive: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return Color.clear
        } else {
            return Color.black.opacity(0.1)
        }
    }
    
    private func shadowRadius(isActive: Bool, isPressed: Bool) -> CGFloat {
        return isPressed ? 0 : 1
    }
    
    private func shadowOffset(isActive: Bool, isPressed: Bool) -> CGFloat {
        return isPressed ? 0 : 1
    }
}

// MARK: - RichTextEditorWrapper

@available(iOS 15.0, *)
struct RichTextEditorWrapper: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var coordinator: RichTextEditor.Coordinator?
    @Binding var isBold: Bool
    @Binding var isItalic: Bool
    @Binding var isUnderlined: Bool
    @Binding var isBulletList: Bool
    @Binding var isNumberedList: Bool
    @Binding var isH1: Bool
    @Binding var isH2: Bool
    @Binding var isH3: Bool
    
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
        
        editorView.onFormattingChange = { bold, italic, underlined, bulletList, numberedList, h1, h2, h3 in
            DispatchQueue.main.async {
                isBold = bold
                isItalic = italic
                isUnderlined = underlined
                isBulletList = bulletList
                isNumberedList = numberedList
                isH1 = h1
                isH2 = h2
                isH3 = h3
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
