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
    let tag: Tag
    
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
        .navigationTitle(tag.name ?? "Tagged Notes")
        .navigationBarTitleDisplayMode(.large)
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