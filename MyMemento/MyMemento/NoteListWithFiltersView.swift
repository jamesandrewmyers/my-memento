//
//  NoteListWithFiltersView.swift
//  MyMemento
//
//  Created by Claude on 9/20/25.
//

import SwiftUI
import CoreData

struct NoteListWithFiltersView: View {
    // Required data
    let allIndices: [IndexPayload]
    
    // Optional customization
    var showSearch: Bool = true
    var showSort: Bool = true
    var showDeleteMode: Bool = true
    var navigationTitle: String = "Notes"
    
    // Callbacks
    var onTogglePin: ((IndexPayload) -> Void)?
    var onDelete: ((IndexPayload) -> Void)?
    var onDeleteIndices: ((IndexSet) -> Void)?
    
    // Internal state
    @State private var searchText = ""
    @State private var filteredIndices: [IndexPayload] = []
    @State private var isSearching = false
    @State private var isDeleteMode = false
    @State private var showTagSuggestions = false
    @State private var tagSuggestions: [String] = []
    @State private var justSelectedTag = false
    @State private var lastSearchTextAfterSelection = ""
    @State private var sortOption: SortOption = .createdAt
    
    var displayedIndices: [IndexPayload] {
        let indicesToDisplay = isSearching ? filteredIndices : allIndices
        return indicesToDisplay.sorted { index1, index2 in
            switch sortOption {
            case .pinned:
                // First sort by pinned status, then by creation date
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                // Secondary sort by creation date for pinned items
                return index1.createdAt > index2.createdAt
                
            case .title:
                // First sort by pinned status, then by title
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                return index1.title.localizedCaseInsensitiveCompare(index2.title) == .orderedAscending
                
            case .updatedAt:
                // First sort by pinned status, then by update date
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                return index1.updatedAt > index2.updatedAt
                
            case .createdAt:
                // First sort by pinned status, then by creation date
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                return index1.createdAt > index2.createdAt
            }
        }
    }
    
    private var allTags: [String] {
        return TagManager.extractTagsFromIndex(allIndices)
    }
    
    private func tagsToString(_ tags: [String]) -> String {
        return tags.sorted().joined(separator: ", ")
    }
    
    var body: some View {
        VStack {
            if showSearch {
                SearchBarView(
                    searchText: $searchText,
                    showTagSuggestions: $showTagSuggestions,
                    tagSuggestions: $tagSuggestions,
                    onSearch: performSearch,
                    onClear: clearSearch,
                    onSelectTag: selectTag,
                    onUpdateTagSuggestions: updateTagSuggestions
                )
            }

            if showSort {
                SortOptionsView(sortOption: $sortOption)
            }

            NoteListView(
                indices: displayedIndices,
                isDeleteMode: showDeleteMode ? $isDeleteMode : .constant(false),
                onTogglePin: onTogglePin ?? { _ in },
                onDelete: onDelete ?? { _ in },
                onDeleteIndices: onDeleteIndices ?? { _ in },
                tagsToString: tagsToString
            )
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            if showDeleteMode {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: toggleDeleteMode) {
                        Image(systemName: "minus")
                            .foregroundColor(isDeleteMode ? .red : .primary)
                    }
                }
            }
        }
    }
    
    // MARK: - Search and Filter Functions
    
    private func performSearch() {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedSearchText.isEmpty {
            clearSearch()
            return
        }
        
        isSearching = true
        
        filteredIndices = allIndices.filter { indexPayload in
            // Search in title
            if indexPayload.title.localizedCaseInsensitiveContains(trimmedSearchText) {
                return true
            }
            
            // Search in tags
            if indexPayload.tags.contains(where: { tag in
                tag.localizedCaseInsensitiveContains(trimmedSearchText)
            }) {
                return true
            }
            
            // Search in summary
            if indexPayload.summary.localizedCaseInsensitiveContains(trimmedSearchText) {
                return true
            }
            
            return false
        }
    }
    
    private func clearSearch() {
        searchText = ""
        filteredIndices = []
        isSearching = false
        showTagSuggestions = false
        tagSuggestions = []
    }
    
    private func selectTag(_ tag: String) {
        justSelectedTag = true
        lastSearchTextAfterSelection = tag
        searchText = tag
        showTagSuggestions = false
        performSearch()
        
        // Reset the flag after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            justSelectedTag = false
        }
    }
    
    private func updateTagSuggestions(_ text: String) {
        // Don't update suggestions if we just selected a tag
        if justSelectedTag && text == lastSearchTextAfterSelection {
            return
        }
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedText.isEmpty {
            showTagSuggestions = false
            tagSuggestions = []
            return
        }
        
        // Filter tags that start with or contain the search text
        let matchingTags = allTags.filter { tag in
            tag.localizedCaseInsensitiveContains(trimmedText)
        }.sorted()
        
        tagSuggestions = Array(matchingTags.prefix(5)) // Limit to 5 suggestions
        showTagSuggestions = !matchingTags.isEmpty
        
        // Auto-perform search as user types
        performSearch()
    }
    
    private func toggleDeleteMode() {
        isDeleteMode.toggle()
    }
}

// MARK: - Convenience Initializers

extension NoteListWithFiltersView {
    /// Creates a note list view with all features enabled
    static func full(
        allIndices: [IndexPayload],
        navigationTitle: String = "Notes",
        onTogglePin: @escaping (IndexPayload) -> Void,
        onDelete: @escaping (IndexPayload) -> Void,
        onDeleteIndices: @escaping (IndexSet) -> Void
    ) -> NoteListWithFiltersView {
        return NoteListWithFiltersView(
            allIndices: allIndices,
            showSearch: true,
            showSort: true,
            showDeleteMode: true,
            navigationTitle: navigationTitle,
            onTogglePin: onTogglePin,
            onDelete: onDelete,
            onDeleteIndices: onDeleteIndices
        )
    }
    
    /// Creates a simple read-only note list view
    static func readOnly(
        allIndices: [IndexPayload],
        navigationTitle: String = "Notes",
        showSearch: Bool = true,
        showSort: Bool = true
    ) -> NoteListWithFiltersView {
        return NoteListWithFiltersView(
            allIndices: allIndices,
            showSearch: showSearch,
            showSort: showSort,
            showDeleteMode: false,
            navigationTitle: navigationTitle
        )
    }
    
    /// Creates a note list view with custom configuration
    static func custom(
        allIndices: [IndexPayload],
        showSearch: Bool = true,
        showSort: Bool = true,
        showDeleteMode: Bool = true,
        navigationTitle: String = "Notes",
        onTogglePin: ((IndexPayload) -> Void)? = nil,
        onDelete: ((IndexPayload) -> Void)? = nil,
        onDeleteIndices: ((IndexSet) -> Void)? = nil
    ) -> NoteListWithFiltersView {
        return NoteListWithFiltersView(
            allIndices: allIndices,
            showSearch: showSearch,
            showSort: showSort,
            showDeleteMode: showDeleteMode,
            navigationTitle: navigationTitle,
            onTogglePin: onTogglePin,
            onDelete: onDelete,
            onDeleteIndices: onDeleteIndices
        )
    }
}