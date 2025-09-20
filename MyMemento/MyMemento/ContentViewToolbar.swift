
//
//  ContentViewToolbar.swift
//  MyMemento
//
//  Created by James Andrew Myers on 9/11/25.
//

import SwiftUI

struct ContentViewToolbar: ToolbarContent {
    @Binding var showTagList: Bool
    @Binding var showLocationManagement: Bool
    @Binding var showImportPicker: Bool
    @Binding var showExportDialog: Bool
    @Binding var isDeleteMode: Bool
    
    var isImporting: Bool
    var isExporting: Bool
    
    var onToggleDeleteMode: () -> Void
    var onAddNote: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack {
                Button(action: { showTagList = true }) {
                    Image(systemName: "tag")
                        .foregroundColor(.primary)
                }
                
                Button(action: { showLocationManagement = true }) {
                    Image(systemName: "location")
                        .foregroundColor(.primary)
                }
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack {
                Button(action: { showImportPicker = true }) {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(.primary)
                    }
                }
                .disabled(isExporting || isImporting)
                
                Button(action: { showExportDialog = true }) {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.primary)
                    }
                }
                .disabled(isExporting || isImporting)
                
                Button(action: onToggleDeleteMode) {
                    Image(systemName: "minus")
                        .foregroundColor(isDeleteMode ? .red : .primary)
                }
                .disabled(isExporting || isImporting)
                
                Button(action: onAddNote) {
                    Image(systemName: "plus")
                }
                .disabled(isExporting || isImporting)
            }
        }
    }
}
