
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
    
    var isImporting: Bool
    var isExporting: Bool
    
    var onAddNote: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 0) {
                // Left group
                HStack(spacing: 2) {
                    Button(action: { showTagList = true }) {
                        Image(systemName: "tag")
                            .foregroundColor(.primary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { showLocationManagement = true }) {
                        Image(systemName: "location")
                            .foregroundColor(.primary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer(minLength: 0)
                
                // Center
                SettingsButton()
                
                Spacer(minLength: 0)
                
                // Right group
                HStack(spacing: 2) {
                    Button(action: { showImportPicker = true }) {
                        if isImporting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.primary)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isExporting || isImporting)
                    
                    Button(action: { showExportDialog = true }) {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.primary)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isExporting || isImporting)
                    
                    Button(action: onAddNote) {
                        Image(systemName: "plus")
                            .foregroundColor(.primary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isExporting || isImporting)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
