
//
//  NoteListView.swift
//  MyMemento
//
//  Created by James Andrew Myers on 9/11/25.
//

import SwiftUI

struct NoteListView: View {
    var indices: [IndexPayload]
    @Binding var isDeleteMode: Bool
    
    var onTogglePin: (IndexPayload) -> Void
    var onDelete: (IndexPayload) -> Void
    var onDeleteIndices: (IndexSet) -> Void
    var tagsToString: ([String]) -> String

    var body: some View {
        List {
            if indices.isEmpty {
                Text("(no notes)")
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(indices, id: \.id) { indexPayload in
                    HStack {
                        if isDeleteMode {
                            Button(action: { onDelete(indexPayload) }) {
                                Image(systemName: "x.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        NavigationLink(value: indexPayload) {
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
                                
                                let tagString = tagsToString(indexPayload.tags)
                                if !tagString.isEmpty {
                                    Text(tagString)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .disabled(isDeleteMode)
                        
                        if !isDeleteMode {
                            Button(action: { onTogglePin(indexPayload) }) {
                                Image(systemName: indexPayload.pinned ? "pin.slash" : "pin")
                                    .foregroundColor(indexPayload.pinned ? .orange : .gray)
                                    .font(.title3)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .onDelete(perform: isDeleteMode ? nil : onDeleteIndices)
            }
        }
    }
}
