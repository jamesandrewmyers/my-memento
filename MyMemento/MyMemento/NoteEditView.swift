//
//  NoteEditView.swift
//  MyMemento
//
//  Created by James Andrew Myers on 8/22/25.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreData
import Foundation
import AVFoundation
import PhotosUI
import CryptoKit

enum ValidationError: LocalizedError {
    case titleRequired
    
    var errorDescription: String? {
        switch self {
        case .titleRequired:
            return "Title is required"
        }
    }
}

struct NoteEditView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var noteIndexViewModel: NoteIndexViewModel
    @ObservedObject private var errorManager = ErrorManager.shared
    
    let indexPayload: IndexPayload
    @State private var note: Note?
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)],
        animation: .default)
    private var allNotes: FetchedResults<Note>
    
    @State private var title: String = ""
    @State private var tags: String = ""
    @State private var noteBody: NSAttributedString = NSAttributedString()
    @State private var checklistItems: [ChecklistItem] = []
    @State private var editorCoordinator: RichTextEditor.Coordinator?
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderlined = false
    @State private var isStrikethrough = false
    @State private var isBulletList = false
    @State private var isNumberedList = false
    @State private var isH1 = false
    @State private var isH2 = false
    @State private var isH3 = false
    @State private var showLinkDialog = false
    @State private var linkDisplayLabel = ""
    @State private var linkURL = ""
    
    // MARK: - Attachments UI State
    @State private var videoThumbnails: [UUID: UIImage] = [:]
    @State private var generatingThumbnailIDs: Set<UUID> = []
    @State private var selectedVideoAttachment: Attachment?
    @State private var isEncryptingAttachment = false
    @State private var showAttachOptions = false
    @State private var showVideoLibraryPicker = false
    @State private var showVideoCameraPicker = false
    @State private var attachmentsRefreshID = UUID()
    @State private var showEncryptedExport = false
    @State private var selectedAudioAttachment: Attachment?
    @State private var showVoiceRecorder = false
    @State private var showLocationPicker = false
    @State private var selectedLocationForDetail: Location?
    
    // Local validation alert state
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom toolbar
            NoteEditToolbarView(
                note: note,
                onCancel: { dismiss() },
                onTogglePin: togglePin,
                onExportHTML: exportNoteAndPresentShare,
                onExportLocalKey: exportNoteWithLocalKeyAndPresentShare,
                onExportEncrypted: { showEncryptedExport = true },
                onSave: saveNote
            )
            .background(Color(UIColor.systemBackground))
            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            
            // Main content
            Form {
            Section(header: Text("Note Details")) {
                TextField("Title", text: $title)
                    .font(.headline)
                    .onSubmit {
                        autoSave()
                    }
                
                TextField("Tags", text: $tags)
                    .font(.subheadline)
                    .onSubmit {
                        autoSave()
                    }
            }
            
            Section(header: contentHeader) {
                if note is ChecklistNote {
                    ChecklistEditor(items: $checklistItems)
                        .frame(minHeight: 400)
                        .onChange(of: checklistItems) { oldValue, newValue in
                            autoSave()
                        }
                } else {
                    if #available(iOS 15.0, *) {
                        RichTextEditorWrapper(
                            attributedText: $noteBody,
                            coordinator: $editorCoordinator,
                            isBold: $isBold,
                            isItalic: $isItalic,
                            isUnderlined: $isUnderlined,
                            isStrikethrough: $isStrikethrough,
                            isBulletList: $isBulletList,
                            isNumberedList: $isNumberedList,
                            isH1: $isH1,
                            isH2: $isH2,
                            isH3: $isH3
                        )
                        .frame(minHeight: 400)
                        .onChange(of: noteBody) { oldValue, newValue in
                            autoSave()
                        }
                    } else {
                        Text("Rich text editor requires iOS 15.0+")
                    }
                }
            }

            // MARK: - Attachments Section
            Section(header: Text("Attachments")) {
                // Attach Video button
                Button(action: { showAttachOptions = true }) {
                    HStack {
                        Image(systemName: "paperclip")
                        Text("Add Attachment")
                        if isEncryptingAttachment {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isEncryptingAttachment || note == nil)

                if let attachmentSet = note?.attachments as? Set<Attachment>, !attachmentSet.isEmpty {
                    let sortedAttachments = attachmentSet.sorted { (a, b) in
                        (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
                    }
                    
                    let videos = sortedAttachments.filter { ($0.type ?? "").lowercased() == "video" }
                    let audios = sortedAttachments.filter { ($0.type ?? "").lowercased() == "audio" }
                    let locations = sortedAttachments.filter { ($0.type ?? "").lowercased() == "location" }

                    if !videos.isEmpty {
                        ForEach(videos, id: \.id) { attachment in
                            AttachmentVideoRow(
                                attachment: attachment,
                                thumbnail: thumbnailImage(for: attachment),
                                onAppear: { ensureThumbnail(for: attachment) },
                                onTap: {
                                    selectedVideoAttachment = attachment
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteAttachment(attachment)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    
                    if !audios.isEmpty {
                        ForEach(audios, id: \.id) { attachment in
                            AttachmentAudioRow(
                                attachment: attachment,
                                onTap: {
                                    selectedAudioAttachment = attachment
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteAttachment(attachment)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    
                    if !locations.isEmpty {
                        ForEach(locations, id: \.id) { attachment in
                            AttachmentLocationRow(
                                attachment: attachment,
                                onTap: {
                                    selectedLocationForDetail = attachment.location
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteAttachment(attachment)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    
                    if videos.isEmpty && audios.isEmpty && locations.isEmpty {
                        Text("No attachments")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No attachments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .id(attachmentsRefreshID)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadNoteData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EditHyperlink"))) { notification in
            if let userInfo = notification.userInfo,
               let displayLabel = userInfo["displayLabel"] as? String,
               let url = userInfo["url"] as? String {
                linkDisplayLabel = displayLabel
                linkURL = url
                showLinkDialog = true
            }
        }
        .alert(errorManager.dialogType == .error ? "Error" : "Success", isPresented: $errorManager.showError) {
            Button("OK") {
                errorManager.dismissError()
            }
        } message: {
            Text(errorManager.errorMessage)
        }
        .alert("Title Required", isPresented: $showValidationAlert) {
            Button("OK") {
                showValidationAlert = false
            }
        } message: {
            Text(validationMessage)
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
        // Video playback sheet driven by selected item to avoid race conditions
        .sheet(item: $selectedVideoAttachment, onDismiss: { selectedVideoAttachment = nil }) { attachment in
            VideoAttachmentPlayer(attachment: attachment)
        }
        // Audio playback sheet
        .sheet(item: $selectedAudioAttachment, onDismiss: { selectedAudioAttachment = nil }) { attachment in
            AudioAttachmentPlayer(attachment: attachment)
        }
        // Video pickers
        .sheet(isPresented: $showVideoLibraryPicker) {
            VideoLibraryPicker { url in
                showVideoLibraryPicker = false
                if let url = url { handlePickedVideo(url: url) }
            }
        }
        .sheet(isPresented: $showVideoCameraPicker) {
            VideoCameraPicker { url in
                showVideoCameraPicker = false
                if let url = url { handlePickedVideo(url: url) }
            }
        }
        // Voice recorder
        .sheet(isPresented: $showVoiceRecorder) {
            VoiceRecorderView { url in
                showVoiceRecorder = false
                if let url = url { handleRecordedAudio(url: url) }
            }
        }
        // Choose source
        .confirmationDialog("Add Attachment", isPresented: $showAttachOptions, titleVisibility: .visible) {
            Button("Record Video") { showVideoCameraPicker = true }
            Button("Choose Video from Library") { showVideoLibraryPicker = true }
            Button("Record Voice") { showVoiceRecorder = true }
            Button("Location") { showLocationPicker = true }
            Button("Cancel", role: .cancel) { }
        }
        // Location picker
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(viewContext: viewContext) { selectedLocation in
                handleSelectedLocation(selectedLocation)
            }
        }
        // Location detail view
        .sheet(item: $selectedLocationForDetail) { location in
            LocationDetailView(
                location: location,
                viewContext: viewContext,
                onLocationSelected: { _ in
                    selectedLocationForDetail = nil
                }
            )
        }
        // Encrypted Export Sheet
        .sheet(isPresented: $showEncryptedExport) {
            if let note = note {
                EncryptedExportView(note: note)
            }
        }
    }
    
    private func loadNoteData() {
        // Fetch the Note entity by id
        let request: NSFetchRequest<Note> = Note.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", indexPayload.id as CVarArg)
        request.fetchLimit = 1
        
        do {
            let notes = try viewContext.fetch(request)
            if let fetchedNote = notes.first {
                note = fetchedNote
                
                // Try to decrypt existing data first
                if let encryptedData = fetchedNote.encryptedData {
                    do {
                        let encryptionKey = try KeyManager.shared.getEncryptionKey()
                        let decryptedPayload = try CryptoHelper.decrypt(encryptedData, key: encryptionKey, as: NotePayload.self)
                        
                        title = decryptedPayload.title
                        tags = decryptedPayload.tags.joined(separator: ", ")
                        if let checklistNote = fetchedNote as? ChecklistNote {
                            // Decrypted payload is only used for title/tags/timestamps; checklist items live in entity
                            noteBody = NSAttributedString()
                            checklistItems = decodeChecklistItems(from: checklistNote)
                        } else {
                            noteBody = decryptedPayload.body.attributedString
                        }
                        return
                    } catch {
                        print("Failed to decrypt note data, falling back to legacy fields: \(error)")
                    }
                }
                
                // Fallback to legacy unencrypted fields
                title = fetchedNote.title ?? ""
                tags = tagsToString(fetchedNote.tags)
                if let textNote = fetchedNote as? TextNote {
                    noteBody = textNote.richText ?? NSAttributedString()
                } else if let checklistNote = fetchedNote as? ChecklistNote {
                    checklistItems = decodeChecklistItems(from: checklistNote)
                    noteBody = NSAttributedString()
                } else {
                    noteBody = NSAttributedString()
                }
            } else {
                // Create new Note if it doesn't exist (for new notes from addNote)
                let newNote = TextNote(context: viewContext)
                newNote.id = indexPayload.id
                newNote.createdAt = indexPayload.createdAt
                newNote.isPinned = indexPayload.pinned
                note = newNote
                
                // Initialize with IndexPayload data
                title = indexPayload.title
                tags = indexPayload.tags.joined(separator: ", ")
                noteBody = NSAttributedString()
            }
        } catch {
            print("Failed to fetch note: \(error)")
            // Initialize with IndexPayload data as fallback
            title = indexPayload.title
            tags = indexPayload.tags.joined(separator: ", ")
            noteBody = NSAttributedString()
        }
    }
    
    private func tagsToString(_ tagSet: NSSet?) -> String {
        guard let tagSet = tagSet as? Set<Tag> else { return "" }
        return tagSet.compactMap { $0.name }.sorted().joined(separator: ", ")
    }
    
    private func stringToTags(_ tagString: String) -> Set<Tag> {
        let tagNames = tagString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var tagSet = Set<Tag>()
        
        for tagName in tagNames {
            guard !tagName.isEmpty else { continue }
            
            // Find existing tag or create new one
            let request: NSFetchRequest<Tag> = Tag.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@", tagName)
            
            do {
                let existingTags = try viewContext.fetch(request)
                if let existingTag = existingTags.first {
                    tagSet.insert(existingTag)
                } else {
                    let newTag = Tag(context: viewContext)
                    newTag.id = UUID()
                    newTag.name = tagName
                    newTag.createdAt = Date()
                    tagSet.insert(newTag)
                }
            } catch {
                print("Error fetching/creating tag: \(error)")
            }
        }
        
        return tagSet
    }
    
    private func autoSave() {
        let currentTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTags = tags
        let currentNoteBody = noteBody
        let currentChecklist = checklistItems
        guard let noteToSave = note else { return }
        
        guard !currentTitle.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let encryptionKey = try KeyManager.shared.getEncryptionKey()
                let tagNames = currentTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let now = Date()
                
                let contentForEncryption: NSAttributedString = {
                    if let _ = noteToSave as? ChecklistNote {
                        let text = currentChecklist
                            .map { ($0.isChecked ? "[x] " : "[ ] ") + $0.text }
                            .joined(separator: "\n")
                        return NSAttributedString(string: text)
                    } else {
                        return currentNoteBody
                    }
                }()
                
                let notePayload = NotePayload(
                    title: currentTitle,
                    body: NSAttributedStringWrapper(contentForEncryption),
                    tags: tagNames,
                    createdAt: noteToSave.createdAt ?? now,
                    updatedAt: now,
                    pinned: noteToSave.isPinned
                )
                
                let encryptedNoteData = try CryptoHelper.encrypt(notePayload, key: encryptionKey)
                let summaryBase = contentForEncryption.string
                let summary = summaryBase.prefix(100).trimmingCharacters(in: .whitespacesAndNewlines)
                
                DispatchQueue.main.async {
                    do {
                        NoteIDManager.ensureNoteHasID(noteToSave)
                        noteToSave.encryptedData = encryptedNoteData
                        
                        if let checklistNote = noteToSave as? ChecklistNote {
                            checklistNote.items = self.encodeChecklistItems(currentChecklist)
                        }
                        
                        let searchIndexRequest: NSFetchRequest<SearchIndex> = SearchIndex.fetchRequest()
                        searchIndexRequest.predicate = NSPredicate(format: "id == %@", noteToSave.id! as CVarArg)
                        
                        let searchIndex: SearchIndex
                        if let existingIndex = try self.viewContext.fetch(searchIndexRequest).first {
                            searchIndex = existingIndex
                        } else {
                            searchIndex = SearchIndex(context: self.viewContext)
                            searchIndex.id = noteToSave.id!
                        }
                        
                        let indexPayload = IndexPayload(
                            id: noteToSave.id!,
                            title: currentTitle,
                            tags: tagNames,
                            summary: String(summary),
                            createdAt: noteToSave.createdAt ?? now,
                            updatedAt: now,
                            pinned: noteToSave.isPinned
                        )
                        
                        let encryptedIndexData = try CryptoHelper.encrypt(indexPayload, key: encryptionKey)
                        searchIndex.encryptedIndexData = encryptedIndexData
                        
                        var tagEntities: [Tag] = []
                        for tagName in tagNames {
                            let request: NSFetchRequest<Tag> = Tag.fetchRequest()
                            request.predicate = NSPredicate(format: "name == %@", tagName)
                            
                            if let existingTag = try self.viewContext.fetch(request).first {
                                tagEntities.append(existingTag)
                            } else {
                                let newTag = Tag(context: self.viewContext)
                                newTag.id = UUID()
                                newTag.name = tagName
                                newTag.createdAt = Date()
                                tagEntities.append(newTag)
                            }
                        }
                        
                        noteToSave.tags = NSSet(array: tagEntities)
                        try self.viewContext.save()
                        self.noteIndexViewModel.refreshIndex(from: self.viewContext)
                        SyncService.shared.upload(notes: Array(self.allNotes))
                        
                    } catch {
                        if NoteIDManager.handleSaveError(error, in: self.viewContext, retryAction: {
                            try self.viewContext.save()
                            self.noteIndexViewModel.refreshIndex(from: self.viewContext)
                            SyncService.shared.upload(notes: Array(self.allNotes))
                        }) {
                            return
                        }
                        
                        let nsError = error as NSError
                        print("Auto-save error: \(nsError)")
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    let nsError = error as NSError
                    print("Auto-save encryption error: \(nsError)")
                }
            }
        }
    }
    
    private func saveNote() {
        // Capture current state immediately
        let currentTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTags = tags
        let currentNoteBody = noteBody
        let currentChecklist = checklistItems
        guard let noteToSave = note else { return }
        
        // Validate that title is not empty
        guard !currentTitle.isEmpty else {
            // Use local alert state to avoid presentation conflicts
            validationMessage = "Please add a title before saving the note"
            showValidationAlert = true
            return
        }
        
        // Perform save operation completely async
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Get encryption key
                let encryptionKey = try KeyManager.shared.getEncryptionKey()
                
                // Parse tags from string
                let tagNames = currentTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                
                // Create current timestamp for updates
                let now = Date()
                
                // Prepare content string based on note type
                let contentForEncryption: NSAttributedString = {
                    if let _ = noteToSave as? ChecklistNote {
                        let text = currentChecklist
                            .map { ($0.isChecked ? "[x] " : "[ ] ") + $0.text }
                            .joined(separator: "\n")
                        return NSAttributedString(string: text)
                    } else {
                        return currentNoteBody
                    }
                }()
                
                // Build NotePayload from captured state first (off main thread)
                let notePayload = NotePayload(
                    title: currentTitle,
                    body: NSAttributedStringWrapper(contentForEncryption),
                    tags: tagNames,
                    createdAt: noteToSave.createdAt ?? now, // Preserve original creation date
                    updatedAt: now,
                    pinned: noteToSave.isPinned
                )
                
                // Encrypt NotePayload
                let encryptedNoteData = try CryptoHelper.encrypt(notePayload, key: encryptionKey)
                
                // Build IndexPayload for search
                let summaryBase = contentForEncryption.string
                let summary = summaryBase.prefix(100).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Perform Core Data operations on main queue
                DispatchQueue.main.async {
                    do {
                        // Ensure note has an ID
                        NoteIDManager.ensureNoteHasID(noteToSave)
                        
                        // Store encrypted data
                        noteToSave.encryptedData = encryptedNoteData
                        
                        // Persist checklist items if applicable
                        if let checklistNote = noteToSave as? ChecklistNote {
                            // Persist checklist items; content lives in encrypted payload as well
                            checklistNote.items = encodeChecklistItems(checklistItems)
                        } else if noteToSave is TextNote {
                            // Avoid writing transformable NSAttributedString to Core Data to prevent
                            // NSSecureUnarchiveFromData transformer errors. Text content is persisted
                            // in encryptedData and surfaced via the search index.
                        }
                        
                        // Find or create matching SearchIndex entity
                        let searchIndexRequest: NSFetchRequest<SearchIndex> = SearchIndex.fetchRequest()
                        searchIndexRequest.predicate = NSPredicate(format: "id == %@", noteToSave.id! as CVarArg)
                        
                        let searchIndex: SearchIndex
                        if let existingIndex = try self.viewContext.fetch(searchIndexRequest).first {
                            searchIndex = existingIndex
                        } else {
                            searchIndex = SearchIndex(context: self.viewContext)
                            searchIndex.id = noteToSave.id!
                        }
                        
                        // Build IndexPayload with correct ID
                        let indexPayload = IndexPayload(
                            id: noteToSave.id!,
                            title: currentTitle,
                            tags: tagNames,
                            summary: String(summary),
                            createdAt: noteToSave.createdAt ?? now, // Preserve original creation date
                            updatedAt: now,
                            pinned: noteToSave.isPinned
                        )
                        
                        // Encrypt IndexPayload and store
                        let encryptedIndexData = try CryptoHelper.encrypt(indexPayload, key: encryptionKey)
                        searchIndex.encryptedIndexData = encryptedIndexData
                        
                        print("=== SAVE DEBUG ===")
                        print("Note ID: \(noteToSave.id?.uuidString ?? "nil")")
                        print("Encrypted data size: \(encryptedNoteData.count) bytes")
                        print("SearchIndex ID: \(searchIndex.id?.uuidString ?? "nil")")
                        print("Encrypted index size: \(encryptedIndexData.count) bytes")
                        print("==================")
                        
                        // Update Core Data tag relationships
                        var tagEntities: [Tag] = []
                        for tagName in tagNames {
                            let request: NSFetchRequest<Tag> = Tag.fetchRequest()
                            request.predicate = NSPredicate(format: "name == %@", tagName)
                            
                            if let existingTag = try self.viewContext.fetch(request).first {
                                tagEntities.append(existingTag)
                            } else {
                                let newTag = Tag(context: self.viewContext)
                                newTag.id = UUID()
                                newTag.name = tagName
                                newTag.createdAt = Date()
                                tagEntities.append(newTag)
                            }
                        }
                        
                        noteToSave.tags = NSSet(array: tagEntities)
                        
                        // Save the Core Data context (directly on main queue)
                        try self.viewContext.save()
                        
                        print("=== SAVE SUCCESS ===")
                        
                        // Refresh the index to reflect tag changes
                        self.noteIndexViewModel.refreshIndex(from: self.viewContext)
                        
                        // Upload notes for sync (will need to be updated for encrypted data)
                        SyncService.shared.upload(notes: Array(self.allNotes))
                        
                        self.dismiss()
                        
                    } catch {
                        // Try to handle unique constraint violations
                        if NoteIDManager.handleSaveError(error, in: self.viewContext, retryAction: {
                            try self.viewContext.save()
                            
                            // Refresh the index to reflect tag changes
                            self.noteIndexViewModel.refreshIndex(from: self.viewContext)
                            
                            // Upload notes for sync
                            SyncService.shared.upload(notes: Array(self.allNotes))
                            
                            self.dismiss()
                        }) {
                            // Constraint violation was handled successfully
                            return
                        }
                        
                        // If constraint violation handling failed or it's a different error
                        let nsError = error as NSError
                        print("=== CORE DATA SAVE ERROR ===")
                        print("Error: \(nsError)")
                        print("Domain: \(nsError.domain)")
                        print("Code: \(nsError.code)")
                        print("UserInfo: \(nsError.userInfo)")
                        print("=============================")
                        self.errorManager.handleCoreDataError(nsError, context: "Failed to save encrypted note")
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    let nsError = error as NSError
                    print("=== ENCRYPTION ERROR ===")
                    print("Error: \(nsError)")
                    print("Domain: \(nsError.domain)")
                    print("Code: \(nsError.code)")
                    print("=========================")
                    self.errorManager.handleCoreDataError(nsError, context: "Failed to encrypt note data")
                }
            }
        }
    }

    // MARK: - Checklist Models & Helpers
    struct ChecklistItem: Identifiable, Equatable {
        let id: UUID
        var text: String
        var isChecked: Bool
        
        init(id: UUID = UUID(), text: String, isChecked: Bool = false) {
            self.id = id
            self.text = text
            self.isChecked = isChecked
        }
    }
    
    private func decodeChecklistItems(from note: ChecklistNote) -> [ChecklistItem] {
        guard let array = note.items as? [NSDictionary] else { return [] }
        return array.compactMap { dict in
            let text = (dict["text"] as? String) ?? ""
            let isChecked = (dict["checked"] as? Bool) ?? false
            let idString = dict["id"] as? String
            let id = idString.flatMap(UUID.init(uuidString:)) ?? UUID()
            return ChecklistItem(id: id, text: text, isChecked: isChecked)
        }
    }
    
    private func encodeChecklistItems(_ items: [ChecklistItem]) -> NSArray {
        let mapped: [NSDictionary] = items.map { item in
            [
                "id": item.id.uuidString,
                "text": item.text,
                "checked": item.isChecked
            ] as NSDictionary
        }
        return mapped as NSArray
    }
    
    private func togglePin() {
        guard let noteToSave = note else { return }
        noteToSave.isPinned.toggle()

        // Also update the SearchIndex
        let searchIndexRequest: NSFetchRequest<SearchIndex> = SearchIndex.fetchRequest()
        searchIndexRequest.predicate = NSPredicate(format: "id == %@", noteToSave.id! as CVarArg)

        do {
            if let searchIndex = try viewContext.fetch(searchIndexRequest).first,
               let encryptedData = searchIndex.encryptedIndexData {
                
                let encryptionKey = try KeyManager.shared.getEncryptionKey()
                
                // Decrypt, update, re-encrypt
                var decryptedPayload = try CryptoHelper.decrypt(encryptedData, key: encryptionKey, as: IndexPayload.self)
                decryptedPayload.pinned = noteToSave.isPinned
                
                let encryptedIndexData = try CryptoHelper.encrypt(decryptedPayload, key: encryptionKey)
                searchIndex.encryptedIndexData = encryptedIndexData
            }

            try viewContext.save()
            
            // Refresh the index to reflect the pin status change
            noteIndexViewModel.refreshIndex(from: viewContext)
            
            SyncService.shared.upload(notes: Array(allNotes))
        } catch {
            let nsError = error as NSError
            errorManager.handleCoreDataError(nsError, context: "Failed to update note pin status or search index")
        }
    }

    
    private func createLink() {
        guard let editorCoordinator = editorCoordinator else { return }
        editorCoordinator.createLink(displayLabel: linkDisplayLabel, url: linkURL)
        
        // Clear the input fields
        linkDisplayLabel = ""
        linkURL = ""
    }
    
    private func exportNoteAndPresentShare() {
        guard let generated = generateHTMLTempFile() else { return }
        // Present standard iOS share sheet with a real file URL
        presentShareSheet(for: generated.url)
    }

    private func exportNoteWithLocalKeyAndPresentShare() {
        guard let note else { 
            print("Export: No note available for export")
            return 
        }
        
        print("Export: Starting local key export for note \(note.id?.uuidString ?? "unknown")")
        
        Task {
            do {
                print("Export: Calling ExportManager.shared.exportWithLocalKey")
                let url = try await ExportManager.shared.exportWithLocalKey(note: note)
                print("Export: Successfully exported to \(url.path)")
                
                // Verify the file exists before sharing
                if FileManager.default.fileExists(atPath: url.path) {
                    print("Export: File exists at \(url.path), presenting share sheet")
                    // Ensure UI updates happen on main thread
                    DispatchQueue.main.async {
                        self.presentShareSheet(for: url)
                    }
                } else {
                    print("Export: ERROR - File does not exist at \(url.path)")
                    DispatchQueue.main.async {
                        self.errorManager.handleError(ExportError.finalPackagingFailed, context: "Export file was not created")
                    }
                }
            } catch {
                print("Export: ERROR - \(error)")
                // Ensure error handling happens on main thread
                DispatchQueue.main.async {
                    self.errorManager.handleError(error, context: "Failed to export note with local key")
                }
            }
        }
    }

    private func generateHTMLTempFile() -> (url: URL, data: Data, name: String)? {
        let content = noteBody
        guard content.length > 0 else { return nil }
        do {
            let htmlData = try content.data(
                from: NSRange(location: 0, length: content.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
                ]
            )
            let fileNameBase = (title.isEmpty ? "Note" : title)
                .replacingOccurrences(of: "[\\/:\n\r\t]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let suggestedName = "\(fileNameBase.isEmpty ? "Note" : fileNameBase).html"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
            // Write the HTML Data directly to preserve encoding and formatting
            try htmlData.write(to: tempURL, options: .atomic)
            return (tempURL, htmlData, suggestedName)
        } catch {
            errorManager.handleError(error, context: "Failed to export note as HTML")
            return nil
        }
    }

    private func presentShareSheet(for url: URL) {
        print("ShareSheet: Preparing to present share sheet for \(url.path)")
        print("ShareSheet: File extension is: \(url.pathExtension)")
        // Get file size for logging
        do {
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber ?? 0
            print("ShareSheet: File size: \(fileSize) bytes")
        } catch {
            print("ShareSheet: Could not get file size: \(error)")
        }
        
        // For maximum compatibility, share the file URL directly without custom wrappers
        // The file should already have a safe extension (.zip) from ExportManager
        print("ShareSheet: Using file URL directly for maximum compatibility")
        
        print("ShareSheet: Creating UIActivityViewController with direct file URL")
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        // Debug: Log all available activities
        print("ShareSheet: Available activities will be determined by iOS...")
        
        // Don't exclude any activities to see what's available
        activityVC.excludedActivityTypes = []
        print("ShareSheet: Set excludedActivityTypes to empty array to see all options")
        if let popover = activityVC.popoverPresentationController {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                popover.sourceView = windowScene.windows.first { $0.isKeyWindow }
            }
            if let sourceView = popover.sourceView {
                popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        
        print("ShareSheet: Getting top view controller")
        guard let topVC = topViewController() else {
            print("ShareSheet: ERROR - No top view controller found")
            return
        }
        
        print("ShareSheet: Presenting activity view controller")
        topVC.present(activityVC, animated: true) {
            print("ShareSheet: Activity view controller presented successfully")
        }
    }

    private func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }

    // MARK: - Attachments Helpers
    private func thumbnailImage(for attachment: Attachment) -> UIImage? {
        guard let id = attachment.id else { return nil }
        return videoThumbnails[id]
    }

    private func ensureThumbnail(for attachment: Attachment) {
        guard let id = attachment.id else { return }
        // Avoid regenerating
        if videoThumbnails[id] != nil || generatingThumbnailIDs.contains(id) { return }
        // Defer state mutation to avoid publishing during view updates
        DispatchQueue.main.async {
            self.generatingThumbnailIDs.insert(id)
        }

        // Capture path info on main thread to avoid Core Data threading issues
        let relativePath = attachment.relativePath

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let relativePath = relativePath,
                      let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                    throw DecryptedAssetError.fileNotFound
                }

                let encryptedURL = appSupport.appendingPathComponent(relativePath)
                guard FileManager.default.fileExists(atPath: encryptedURL.path) else {
                    throw DecryptedAssetError.fileNotFound
                }

                let key = try KeyManager.shared.getEncryptionKey()
                let asset = DecryptedAsset(encryptedFileURL: encryptedURL, key: key)

                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                // Try a small offset to avoid black first frame
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                
                generator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
                    if let cgImage = cgImage, error == nil {
                        let image = UIImage(cgImage: cgImage)
                        DispatchQueue.main.async {
                            self.videoThumbnails[id] = image
                            self.generatingThumbnailIDs.remove(id)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.generatingThumbnailIDs.remove(id)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.generatingThumbnailIDs.remove(id)
                    // Non-critical: log only, avoid presenting alerts during view updates
                    ErrorManager.shared.log(error, context: "Generating video thumbnail")
                }
            }
        }
    }

    private func handlePickedVideo(url: URL) {
        guard let note = note else { return }
        isEncryptingAttachment = true
        Task { @MainActor in
            do {
                // Call manager (runs on @MainActor)
                _ = try await AttachmentManager.createVideoAttachment(for: note, from: url, context: viewContext)
                // Save is done in manager, but ensure UI reflects changes
                attachmentsRefreshID = UUID()
                // Kick off thumbnails for new attachments
                if let newSet = note.attachments as? Set<Attachment> {
                    for att in newSet where (att.type ?? "").lowercased() == "video" {
                        ensureThumbnail(for: att)
                    }
                }
            } catch {
                ErrorManager.shared.handleError(error, context: "Attaching video")
            }
            isEncryptingAttachment = false
        }
    }

    private func handleRecordedAudio(url: URL) {
        guard let note = note else { return }
        isEncryptingAttachment = true
        Task { @MainActor in
            do {
                // Call manager to create audio attachment (will need to implement)
                _ = try await AttachmentManager.createAudioAttachment(for: note, from: url, context: viewContext)
                // Save is done in manager, but ensure UI reflects changes
                attachmentsRefreshID = UUID()
            } catch {
                ErrorManager.shared.handleError(error, context: "Attaching voice recording")
            }
            isEncryptingAttachment = false
        }
    }

    private func handleSelectedLocation(_ location: Location) {
        guard let note = note else { return }
        isEncryptingAttachment = true
        Task { @MainActor in
            do {
                _ = try await AttachmentManager.createLocationAttachment(for: note, from: location, context: viewContext)
                attachmentsRefreshID = UUID()
            } catch {
                ErrorManager.shared.handleError(error, context: "Attaching location")
            }
            isEncryptingAttachment = false
        }
    }
    
    private func deleteAttachment(_ attachment: Attachment) {
        guard let id = attachment.id else { return }
        Task { @MainActor in
            do {
                try await AttachmentManager.deleteAttachment(attachment, context: viewContext)
                // Update UI caches and refresh the section
                videoThumbnails.removeValue(forKey: id)
                generatingThumbnailIDs.remove(id)
                attachmentsRefreshID = UUID()
            } catch {
                ErrorManager.shared.handleError(error, context: "Deleting attachment")
            }
        }
    }
}

// MARK: - Attachment Video Row View
private struct AttachmentVideoRow: View {
    let attachment: Attachment
    let thumbnail: UIImage?
    let onAppear: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    if let thumbnail = thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                        ProgressView()
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .frame(width: 120, height: 68)
                .clipped()
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Video")
                        .font(.headline)
                        .foregroundColor(.primary)
                    if let date = attachment.createdAt {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .onAppear(perform: onAppear)
    }
}

// MARK: - Attachment Audio Row View
private struct AttachmentAudioRow: View {
    let attachment: Attachment
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "waveform")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice Recording")
                        .font(.headline)
                        .foregroundColor(.primary)
                    if let date = attachment.createdAt {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                
                Image(systemName: "play.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Audio Attachment Player
struct AudioAttachmentPlayer: View {
    let attachment: Attachment
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var hasError = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                
                // Audio visualization
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 200, height: 200)
                    
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .scaleEffect(isPlaying ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPlaying)
                }
                
                // Time display
                VStack(spacing: 8) {
                    HStack {
                        Text(formatTime(currentTime))
                        Spacer()
                        Text(formatTime(duration))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    // Progress bar
                    ProgressView(value: duration > 0 ? currentTime / duration : 0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                }
                
                // Play/Pause button
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                }
                .disabled(hasError)
                
                if hasError, let errorMessage = errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Voice Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        stopPlayback()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            stopPlayback()
        }
    }
    
    private func setupPlayer() {
        guard let relativePath = attachment.relativePath,
              let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            hasError = true
            errorMessage = "Could not locate audio file"
            return
        }
        
        let encryptedURL = appSupport.appendingPathComponent(relativePath)
        
        Task {
            do {
                // Decrypt the audio file
                let key = try KeyManager.shared.getEncryptionKey()
                let encryptedData = try Data(contentsOf: encryptedURL)
                
                // Extract components (same format as video encryption)
                let nonceData = encryptedData.prefix(12)
                let tagData = encryptedData.suffix(16)
                let ciphertextData = encryptedData.dropFirst(12).dropLast(16)
                
                let nonce = try AES.GCM.Nonce(data: nonceData)
                let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
                let decryptedData = try AES.GCM.open(sealedBox, using: key)
                
                // Create player from decrypted data
                await MainActor.run {
                    do {
                        self.player = try AVAudioPlayer(data: decryptedData)
                        self.duration = player?.duration ?? 0
                        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                        try AVAudioSession.sharedInstance().setActive(true)
                    } catch {
                        self.hasError = true
                        self.errorMessage = "Failed to create audio player: \(error.localizedDescription)"
                    }
                }
                
            } catch {
                await MainActor.run {
                    self.hasError = true
                    self.errorMessage = "Failed to decrypt audio: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func togglePlayback() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            timer?.invalidate()
            timer = nil
        } else {
            player.play()
            startTimer()
        }
        isPlaying = player.isPlaying
    }
    
    private func stopPlayback() {
        player?.stop()
        timer?.invalidate()
        timer = nil
        isPlaying = false
        currentTime = 0
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let player = player {
                currentTime = player.currentTime
                if !player.isPlaying {
                    isPlaying = false
                    timer?.invalidate()
                    timer = nil
                }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Voice Recorder View
struct VoiceRecorderView: View {
    let onComplete: (URL?) -> Void
    
    @State private var audioRecorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var hasRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var recordingURL: URL?
    @State private var hasError = false
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                
                // Recording visualization
                ZStack {
                    Circle()
                        .fill(isRecording ? Color.red.opacity(0.2) : Color.gray.opacity(0.1))
                        .frame(width: 200, height: 200)
                        .animation(.easeInOut(duration: 0.3), value: isRecording)
                    
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 80))
                        .foregroundColor(isRecording ? .red : .gray)
                        .scaleEffect(isRecording ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                }
                
                // Time display
                Text(formatTime(recordingTime))
                    .font(.system(.title, design: .monospaced))
                    .foregroundColor(isRecording ? .red : .primary)
                
                // Recording controls
                HStack(spacing: 40) {
                    // Record/Stop button
                    Button(action: toggleRecording) {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 60))
                            .foregroundColor(isRecording ? .red : .blue)
                    }
                    .disabled(hasError)
                    
                    // Use button (only show if we have a recording)
                    if hasRecording && !isRecording {
                        Button(action: useRecording) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                        }
                    }
                }
                
                if hasError {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Voice Recorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        stopRecording()
                        onComplete(nil)
                    }
                }
            }
        }
        .onAppear {
            setupRecorder()
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    private func setupRecorder() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            // Request permission
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if !granted {
                        self.hasError = true
                        self.errorMessage = "Microphone permission is required"
                    }
                }
            }
            
            // Create recording URL
            let tempDir = FileManager.default.temporaryDirectory
            recordingURL = tempDir.appendingPathComponent("voice_recording_\(UUID().uuidString).m4a")
            
            // Configure recorder
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            if let url = recordingURL {
                audioRecorder = try AVAudioRecorder(url: url, settings: settings)
                audioRecorder?.prepareToRecord()
            }
            
        } catch {
            hasError = true
            errorMessage = "Failed to setup audio recorder: \(error.localizedDescription)"
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard let recorder = audioRecorder else { return }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            recorder.record()
            isRecording = true
            recordingTime = 0
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingTime = recorder.currentTime
            }
        } catch {
            hasError = true
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        
        if recordingTime > 0 {
            hasRecording = true
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
    
    private func useRecording() {
        onComplete(recordingURL)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, centiseconds)
    }
}

// Ensure Core Data Attachment works with `sheet(item:)`


// MARK: - UIKit/PhotosUI Wrappers
private struct VideoLibraryPicker: UIViewControllerRepresentable {
    typealias UIViewControllerType = PHPickerViewController
    var onComplete: (URL?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: (URL?) -> Void
        init(onComplete: @escaping (URL?) -> Void) { self.onComplete = onComplete }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                picker.dismiss(animated: true) { self.onComplete(nil) }
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    var exportedURL: URL? = nil
                    if let error = error {
                        ErrorManager.shared.log(error, context: "Picking video from library")
                    } else if let srcURL = url {
                        // Copy to a stable temp location before dismissing the picker
                        let tmpDir = FileManager.default.temporaryDirectory
                        let ext = srcURL.pathExtension.isEmpty ? "mov" : srcURL.pathExtension
                        let dstURL = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                        do {
                            // Remove if exists (unlikely)
                            try? FileManager.default.removeItem(at: dstURL)
                            try FileManager.default.copyItem(at: srcURL, to: dstURL)
                            exportedURL = dstURL
                        } catch {
                            ErrorManager.shared.log(error, context: "Copying picked video to temp")
                        }
                    }
                    DispatchQueue.main.async {
                        picker.dismiss(animated: true) { self.onComplete(exportedURL) }
                    }
                }
            } else {
                picker.dismiss(animated: true) { self.onComplete(nil) }
            }
        }
    }
}

private struct VideoCameraPicker: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIImagePickerController
    var onComplete: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoQuality = .typeMedium
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onComplete: (URL?) -> Void
        init(onComplete: @escaping (URL?) -> Void) { self.onComplete = onComplete }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { self.onComplete(nil) }
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            var outputURL: URL? = nil
            if let srcURL = info[.mediaURL] as? URL {
                // Copy to a stable temp location before dismissing
                let tmpDir = FileManager.default.temporaryDirectory
                let ext = srcURL.pathExtension.isEmpty ? "mov" : srcURL.pathExtension
                let dstURL = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                do {
                    try? FileManager.default.removeItem(at: dstURL)
                    try FileManager.default.copyItem(at: srcURL, to: dstURL)
                    outputURL = dstURL
                } catch {
                    ErrorManager.shared.log(error, context: "Copying recorded video to temp")
                }
            }
            picker.dismiss(animated: true) { self.onComplete(outputURL) }
        }
    }
}

// MARK: - UIActivityItemSource for sharing files
class ShareableFileItem: NSObject, UIActivityItemSource {
    let url: URL
    let filename: String
    
    init(url: URL, filename: String) {
        self.url = url
        self.filename = filename
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return url
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        if url.pathExtension == "memento" && activityType?.rawValue.contains("mail") == true {
            // Create a temporary copy with .txt extension for Gmail compatibility testing
            let tempURL = createTempFileForEmail()
            return tempURL ?? url
        }
        return url
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        let baseFilename = (filename as NSString).deletingPathExtension
        return "MyMemento Export: \(baseFilename)"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        if url.pathExtension == "memento" {
            // Use generic binary data UTI for better email client compatibility
            return "public.data"
        }
        return "public.item"
    }
    

    
    private func createTempFileForEmail() -> URL? {
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileName = "\((filename as NSString).deletingPathExtension).txt"
            let tempURL = tempDir.appendingPathComponent(tempFileName)
            
            // Remove if it exists
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            
            // Copy the file with .txt extension
            try FileManager.default.copyItem(at: url, to: tempURL)
            print("ShareSheet: Created temp file for email: \(tempURL.path)")
            return tempURL
        } catch {
            print("ShareSheet: Failed to create temp file for email: \(error)")
            return nil
        }
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        // Provide a custom icon for .memento files to help with recognition
        return UIImage(systemName: "doc.badge.gearshape.fill")
    }
}

// MARK: - AdaptiveShareItem that chooses the best approach per app

class AdaptiveShareItem: NSObject, UIActivityItemSource {
    let url: URL
    let data: Data
    let filename: String
    
    init(url: URL, data: Data, filename: String) {
        self.url = url
        self.data = data
        self.filename = filename
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return data // Use data as placeholder
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        guard let activityType = activityType else {
            print("ShareSheet: No activity type, using data")
            return data
        }
        
        print("ShareSheet: Activity type: \(activityType.rawValue)")
        
        // For mail apps (Gmail, Apple Mail, etc), use data to avoid file system issues
        if activityType.rawValue.contains("mail") || activityType.rawValue.contains("gmail") {
            print("ShareSheet: Using data for mail app (\(data.count) bytes)")
            return data
        }
        
        // For file-based apps (Files app, cloud storage), use file URL
        if activityType.rawValue.contains("files") || activityType.rawValue.contains("document") || 
           activityType.rawValue.contains("dropbox") || activityType.rawValue.contains("drive") {
            print("ShareSheet: Using file URL for file-based app")
            return url
        }
        
        // For messaging apps, try data first
        if activityType.rawValue.contains("message") || activityType.rawValue.contains("whatsapp") ||
           activityType.rawValue.contains("telegram") || activityType.rawValue.contains("signal") {
            print("ShareSheet: Using data for messaging app (\(data.count) bytes)")
            return data
        }
        
        // Default to data for unknown apps to avoid file system issues
        print("ShareSheet: Using data for unknown app type (\(data.count) bytes)")
        return data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        let baseFilename = (filename as NSString).deletingPathExtension
        return "MyMemento Export: \(baseFilename)"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        // Always use generic binary data UTI for maximum compatibility
        return "public.data"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        return UIImage(systemName: "doc.badge.gearshape.fill")
    }
}

// MARK: - ShareableDataItem for data-based sharing

class ShareableDataItem: NSObject, UIActivityItemSource {
    let data: Data
    let filename: String
    
    init(data: Data, filename: String) {
        self.data = data
        self.filename = filename
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        // For mail apps, provide the data directly
        if activityType?.rawValue.contains("mail") == true {
            print("ShareSheet: Providing data directly for mail app (\(data.count) bytes)")
            return data
        }
        // For other apps, also provide data
        return data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        let baseFilename = (filename as NSString).deletingPathExtension
        return "MyMemento Export: \(baseFilename)"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        // Use application/octet-stream for binary data
        return "public.data"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        return UIImage(systemName: "doc.badge.gearshape.fill")
    }
}

// MARK: - Formatting Bar (visual only)

extension NoteEditView {
    private var contentHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
            if !(note is ChecklistNote) {
                formattingBar
            }
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

            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleStrikethrough()
                }
            }) {
                Image(systemName: "strikethrough")
                    .imageScale(.medium)
                    .accessibilityLabel("Strikethrough")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isStrikethrough))
            
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

// MARK: - Share Sheet Wrapper + Custom Button Styles

// Simple UIKit share sheet wrapper
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

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
    @Binding var isStrikethrough: Bool
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
        
        editorView.onFormattingChange = { bold, italic, underlined, strikethrough, bulletList, numberedList, h1, h2, h3 in
            DispatchQueue.main.async {
                isBold = bold
                isItalic = italic
                isUnderlined = underlined
                isStrikethrough = strikethrough
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

// MARK: - AttachmentLocationRow
private struct AttachmentLocationRow: View {
    let attachment: Attachment
    let onTap: () -> Void
    @Environment(\.managedObjectContext) private var viewContext
    @State private var locationName: String = "Loading..."
    @State private var locationAddress: String = "Loading address..."
    
    var body: some View {
        HStack {
            Image(systemName: "location.fill")
                .foregroundColor(.blue)
                .font(.title2)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(locationName)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(locationAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onAppear {
            loadLocationData()
        }
    }
    
    private func loadLocationData() {
        guard let location = attachment.location else {
            locationName = "Unknown Location"
            locationAddress = "No location data"
            return
        }
        
        Task {
            do {
                let locationManager = LocationManager(context: viewContext, keyManager: KeyManager.shared)
                
                // Location is already available from the relationship
                await MainActor.run {
                    locationName = location.name ?? "Unnamed Location"
                }
                
                let address = try locationManager.formatAddress(from: location)
                await MainActor.run {
                    locationAddress = address
                }
            } catch {
                await MainActor.run {
                    locationName = "Error Loading Location"
                    locationAddress = "Failed to load location data"
                }
            }
        }
    }
}

// MARK: - ChecklistEditor
private struct ChecklistEditor: View {
    @Binding var items: [NoteEditView.ChecklistItem]
    @State private var newItemText: String = ""
    
    // Computed property to sort items for display: unchecked first, then checked
    private var sortedItems: [NoteEditView.ChecklistItem] {
        items.sorted { !$0.isChecked && $1.isChecked }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("No items yet. Add one below.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                
                Spacer()
            } else {
                // Wrap checklist items in ScrollView for proper scrollability
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sortedItems.indices, id: \.self) { sortedIndex in
                            let sortedItem = sortedItems[sortedIndex]
                            if let originalIndex = items.firstIndex(where: { $0.id == sortedItem.id }) {
                                HStack(spacing: 12) {
                                    Button(action: { 
                                        items[originalIndex].isChecked.toggle()
                                    }) {
                                        Image(systemName: items[originalIndex].isChecked ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(items[originalIndex].isChecked ? .green : .gray)
                                            .font(.system(size: 20))
                                    }
                                    .buttonStyle(.plain)

                                    TextField("List item", text: $items[originalIndex].text)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.body)
                                    
                                    Button(action: {
                                        items.remove(at: originalIndex)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                            .font(.system(size: 16))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 6)
                                .background(Color.clear)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            
            // Add new item section
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                    .padding(.vertical, 4)
                
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                    
                    TextField("Add new item", text: $newItemText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.body)
                        .onSubmit {
                            addNewItem()
                        }
                    
                    Button("Add") {
                        addNewItem()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func addNewItem() {
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        items.append(NoteEditView.ChecklistItem(text: text))
        newItemText = ""
    }
}
