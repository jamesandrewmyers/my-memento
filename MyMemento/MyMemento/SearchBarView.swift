
//
//  SearchBarView.swift
//  MyMemento
//
//  Created by James Andrew Myers on 9/11/25.
//

import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    @Binding var showTagSuggestions: Bool
    @Binding var tagSuggestions: [String]
    
    var onSearch: () -> Void
    var onClear: () -> Void
    var onSelectTag: (String) -> Void
    var onUpdateTagSuggestions: (String) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Search notes...", text: $searchText)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: searchText) { _, newValue in
                        onUpdateTagSuggestions(newValue)
                    }
                    .overlay(
                        HStack {
                            Spacer()
                            if !searchText.isEmpty {
                                Button(action: onClear) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .padding(.trailing, 8)
                            }
                        }
                    )
                
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.blue)
                }
                .padding(.leading, 4)
            }
            
            if showTagSuggestions {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tagSuggestions, id: \.self) { tag in
                        Button(action: { onSelectTag(tag) }) {
                            HStack {
                                Text("#\(tag)")
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .background(Color(UIColor.systemBackground))
                        
                        if tag != tagSuggestions.last {
                            Divider()
                        }
                    }
                }
                .background(Color(UIColor.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(8)
                .shadow(radius: 2)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
